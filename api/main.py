import os
import boto3
from fastapi import FastAPI
from sqlalchemy import create_engine

app = FastAPI(title="DR Transactional API")

# Variables de entorno inyectadas por EC2 User Data en AWS
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_USER = os.getenv("DB_USER", "admin")
DB_PASS = os.getenv("DB_PASS", "password")
DB_NAME = os.getenv("DB_NAME", "transactions_db")
DYNAMO_TABLE = os.getenv("DYNAMO_TABLE", "user_sessions")
S3_BUCKET = os.getenv("S3_BUCKET", "dr-invoice-bucket")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# Inicialización de clientes Boto3 y SQLAlchemy
engine = create_engine(f"mysql+pymysql://{DB_USER}:{DB_PASS}@{DB_HOST}/{DB_NAME}")
dynamodb = boto3.client('dynamodb', region_name=AWS_REGION)
s3 = boto3.client('s3', region_name=AWS_REGION)

@app.get("/health")
def health_check():
    """Endpoint crucial para el Health Check del ALB en Route 53."""
    return {"status": "healthy"}

@app.post("/transaction")
def create_transaction():
    """Simula escritura relacional (RDS)."""
    # Lógica de inserción usando SQLAlchemy
    return {"status": "Transacción financiera registrada"}

@app.post("/cart")
def update_cart(user_id: str, item: str):
    """Simula escritura NoSQL (DynamoDB)."""
    dynamodb.put_item(
        TableName=DYNAMO_TABLE,
        Item={'user_id': {'S': user_id}, 'item': {'S': item}}
    )
    return {"status": "Carrito actualizado"}

@app.post("/invoice")
def upload_invoice(invoice_id: str):
    """Simula escritura de objetos (S3)."""
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=f"invoices/{invoice_id}.pdf",
        Body=b"Contenido del comprobante digital simulado"
    )
    return {"status": "Comprobante digital subido"}