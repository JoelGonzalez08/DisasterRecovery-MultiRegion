import os
import uuid
from datetime import datetime, timezone
from typing import Optional, List

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, Float, String, create_engine, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import declarative_base, sessionmaker

app = FastAPI(
    title="DR Transactional API",
    description="API transaccional para validación de persistencia multi-región (RDS, DynamoDB, S3) bajo Warm Standby.",
    version="1.0.0"
)

# --------------------------------------------------------------------------
# Configuración y Variables de Entorno (Inyectadas por EC2 User Data en AWS)
# --------------------------------------------------------------------------
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.getenv("DB_USER", "admin")
DB_PASS = os.getenv("DB_PASS", "password")
DB_NAME = os.getenv("DB_NAME", "transactions_db")

DYNAMO_TABLE = os.getenv("DYNAMO_TABLE", "user_sessions")
S3_BUCKET = os.getenv("S3_BUCKET", "dr-invoice-bucket")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# --------------------------------------------------------------------------
# Configuración de SQLAlchemy (Capa Relacional - RDS MySQL)
# --------------------------------------------------------------------------
DATABASE_URL = f"mysql+pymysql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# pool_pre_ping=True verifica la conexión antes de usarla (ideal ante failovers)
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600,
    connect_args={"connect_timeout": 5}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class TransactionModel(Base):
    __tablename__ = "transactions"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(64), nullable=False, index=True)
    amount = Column(Float, nullable=False)
    description = Column(String(255), default="")
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    region = Column(String(32), default=AWS_REGION)


def init_db():
    """Intenta inicializar las tablas en la BD relacional."""
    try:
        Base.metadata.create_all(bind=engine)
    except Exception as e:
        # No bloquear el arranque de la API si la BD aún está inicializándose
        print(f"[WARN] No se pudo inicializar la base de datos relacional: {e}")


@app.on_event("startup")
def on_startup():
    init_db()


# --------------------------------------------------------------------------
# Clientes AWS Boto3 (DynamoDB y S3)
# --------------------------------------------------------------------------
dynamodb = boto3.client("dynamodb", region_name=AWS_REGION)
s3 = boto3.client("s3", region_name=AWS_REGION)


# --------------------------------------------------------------------------
# Esquemas Pydantic para Validación de Datos
# --------------------------------------------------------------------------
class TransactionCreate(BaseModel):
    user_id: str = Field(default="usr-1001", description="Identificador del usuario")
    amount: float = Field(default=99.99, gt=0, description="Monto de la transacción")
    description: str = Field(default="Pago orden de compra", description="Detalle")


class CartItem(BaseModel):
    user_id: str = Field(default="usr-1001", description="ID del usuario")
    item: str = Field(default="SKU-994", description="Identificador del producto")
    quantity: int = Field(default=1, ge=1, description="Cantidad agregada al carrito")


class InvoiceCreate(BaseModel):
    invoice_id: Optional[str] = Field(default=None, description="Número de factura opcional")
    customer_name: str = Field(default="Cliente Corporativo", description="Nombre del cliente")
    amount: float = Field(default=150.00, description="Total facturado")


# --------------------------------------------------------------------------
# Endpoints de Observabilidad y Monitoreo (Route 53 / ALB)
# --------------------------------------------------------------------------
@app.get("/health", status_code=status.HTTP_200_OK)
def health_check():
    """Endpoint ligero e inmediato para el Health Check del ALB en Route 53."""
    return {
        "status": "healthy",
        "region": AWS_REGION,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }


@app.get("/readiness")
def readiness_check():
    """Verifica conectividad activa con los 3 componentes de persistencia."""
    checks = {
        "region": AWS_REGION,
        "rds_mysql": "unknown",
        "dynamodb": "unknown",
        "s3": "unknown"
    }

    # 1. Comprobar RDS MySQL
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        checks["rds_mysql"] = "connected"
    except Exception as e:
        checks["rds_mysql"] = f"error: {str(e)}"

    # 2. Comprobar DynamoDB
    try:
        dynamodb.describe_table(TableName=DYNAMO_TABLE)
        checks["dynamodb"] = "connected"
    except Exception as e:
        checks["dynamodb"] = f"error: {str(e)}"

    # 3. Comprobar S3
    try:
        s3.head_bucket(Bucket=S3_BUCKET)
        checks["s3"] = "connected"
    except Exception as e:
        checks["s3"] = f"error: {str(e)}"

    return checks


# --------------------------------------------------------------------------
# Endpoints Transaccionales (Capa Relacional - RDS MySQL)
# --------------------------------------------------------------------------
@app.post("/transaction", status_code=status.HTTP_201_CREATED)
def create_transaction(payload: TransactionCreate):
    """Registra una transacción real en RDS MySQL."""
    db = SessionLocal()
    try:
        new_tx = TransactionModel(
            user_id=payload.user_id,
            amount=payload.amount,
            description=payload.description,
            created_at=datetime.now(timezone.utc),
            region=AWS_REGION
        )
        db.add(new_tx)
        db.commit()
        db.refresh(new_tx)
        return {
            "status": "Transacción financiera registrada",
            "transaction_id": new_tx.id,
            "user_id": new_tx.user_id,
            "amount": new_tx.amount,
            "created_at": new_tx.created_at.isoformat(),
            "region": new_tx.region
        }
    except SQLAlchemyError as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Fallo al registrar en RDS: {str(e)}"
        )
    finally:
        db.close()


@app.get("/transactions/latest")
def get_latest_transactions(limit: int = 10):
    """Consulta las últimas transacciones registradas (útil para auditar RPO)."""
    db = SessionLocal()
    try:
        query = select(TransactionModel).order_by(TransactionModel.created_at.desc()).limit(limit)
        results = db.execute(query).scalars().all()
        return [
            {
                "id": t.id,
                "user_id": t.user_id,
                "amount": t.amount,
                "description": t.description,
                "created_at": t.created_at.isoformat(),
                "region": t.region
            }
            for t in results
        ]
    except SQLAlchemyError as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error consultando transacciones: {str(e)}"
        )
    finally:
        db.close()


# --------------------------------------------------------------------------
# Endpoints NoSQL (Capa DynamoDB - Global Tables)
# --------------------------------------------------------------------------
@app.post("/cart", status_code=status.HTTP_200_OK)
def update_cart(cart: CartItem):
    """Registra o actualiza el carrito de compras en DynamoDB con replicación activa-activa."""
    current_time = datetime.now(timezone.utc).isoformat()
    try:
        dynamodb.put_item(
            TableName=DYNAMO_TABLE,
            Item={
                "user_id": {"S": cart.user_id},
                "item": {"S": cart.item},
                "quantity": {"N": str(cart.quantity)},
                "updated_at": {"S": current_time},
                "region": {"S": AWS_REGION}
            }
        )
        return {
            "status": "Carrito actualizado",
            "user_id": cart.user_id,
            "item": cart.item,
            "quantity": cart.quantity,
            "updated_at": current_time,
            "region": AWS_REGION
        }
    except ClientError as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Fallo en DynamoDB: {e.response['Error']['Message']}"
        )


@app.get("/cart/{user_id}")
def get_cart(user_id: str):
    """Obtiene el carrito de compras de DynamoDB para verificar replicación entre regiones."""
    try:
        response = dynamodb.get_item(
            TableName=DYNAMO_TABLE,
            Key={"user_id": {"S": user_id}}
        )
        if "Item" not in response:
            raise HTTPException(status_code=404, detail="Carrito no encontrado")
        
        item = response["Item"]
        return {
            "user_id": item.get("user_id", {}).get("S"),
            "item": item.get("item", {}).get("S"),
            "quantity": int(item.get("quantity", {}).get("N", 1)),
            "updated_at": item.get("updated_at", {}).get("S"),
            "region": item.get("region", {}).get("S")
        }
    except ClientError as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Fallo consultando DynamoDB: {e.response['Error']['Message']}"
        )


# --------------------------------------------------------------------------
# Endpoints Almacenamiento de Objetos (S3 Cross-Region Replication)
# --------------------------------------------------------------------------
@app.post("/invoice", status_code=status.HTTP_201_CREATED)
def upload_invoice(invoice: InvoiceCreate):
    """Carga un comprobante digital en S3 para ejercitar Cross-Region Replication."""
    inv_id = invoice.invoice_id or f"INV-{uuid.uuid4().hex[:8].upper()}"
    timestamp = datetime.now(timezone.utc).isoformat()
    content = (
        f"FACTURA: {inv_id}\n"
        f"CLIENTE: {invoice.customer_name}\n"
        f"MONTO: ${invoice.amount:.2f} USD\n"
        f"EMISIÓN: {timestamp}\n"
        f"REGIÓN DE ORIGEN: {AWS_REGION}\n"
    )
    s3_key = f"invoices/{inv_id}.txt"

    try:
        put_resp = s3.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=content.encode("utf-8"),
            ContentType="text/plain",
            Metadata={
                "customer": invoice.customer_name,
                "amount": str(invoice.amount),
                "origin_region": AWS_REGION,
                "timestamp": timestamp
            }
        )
        return {
            "status": "Comprobante digital subido",
            "invoice_id": inv_id,
            "s3_bucket": S3_BUCKET,
            "s3_key": s3_key,
            "version_id": put_resp.get("VersionId", "none"),
            "timestamp": timestamp,
            "region": AWS_REGION
        }
    except ClientError as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Fallo al subir a S3: {e.response['Error']['Message']}"
        )


@app.get("/invoice/{invoice_id}")
def get_invoice(invoice_id: str):
    """Recupera la metadata de una factura en S3 para verificar la replicación por CRR."""
    s3_key = f"invoices/{invoice_id}.txt"
    try:
        response = s3.head_object(Bucket=S3_BUCKET, Key=s3_key)
        return {
            "invoice_id": invoice_id,
            "s3_bucket": S3_BUCKET,
            "s3_key": s3_key,
            "version_id": response.get("VersionId", "none"),
            "content_length": response.get("ContentLength"),
            "last_modified": response.get("LastModified", "").isoformat() if response.get("LastModified") else None,
            "metadata": response.get("Metadata", {})
        }
    except ClientError as e:
        if e.response['Error']['Code'] == '404':
            raise HTTPException(status_code=404, detail="Factura no encontrada")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Fallo consultando S3: {e.response['Error']['Message']}"
        )