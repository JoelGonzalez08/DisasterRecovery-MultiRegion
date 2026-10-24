#!/usr/bin/env python3
"""
test_replication_fase2.py
Script de validación para la Fase 2 (Warm Standby & Replicación Cross-Region).
Verifica:
1. Escritura en la API Primaria (us-east-1): RDS, DynamoDB y S3.
2. Estado de replicación en la Región Secundaria (us-west-2):
   - Estado de la Read Replica de RDS MySQL en us-west-2.
   - Lectura directa del ítem replicado en DynamoDB Global Table (us-west-2).
   - Verificación del objeto replicado por S3 CRR en el bucket réplica (us-west-2).
"""

import argparse
import sys
import time
import boto3
import requests


def verify_phase2_replication(
    primary_url: str,
    secondary_rds_id: str,
    dynamo_table: str,
    replica_bucket: str,
    secondary_region: str = "us-west-2",
):
    primary_url = primary_url.rstrip("/")
    print("\n=======================================================")
    print(" Iniciando Validación de Replicación Cross-Region (Fase 2)")
    print(f" API Primaria (us-east-1) : {primary_url}")
    print(f" Región Secundaria        : {secondary_region}")
    print("=======================================================\n")

    results = []

    # 1. Escribir en API Primaria (RDS, DynamoDB, S3)
    test_user = f"usr-dr-{int(time.time())}"
    print(f"[1/4] Generando transacciones de prueba en región primaria ({test_user})...")
    invoice_id = None
    try:
        r_tx = requests.post(
            f"{primary_url}/transaction",
            json={"user_id": test_user, "amount": 499.99, "description": "Validacion RPO Fase 2"},
            timeout=10,
        )
        r_cart = requests.post(
            f"{primary_url}/cart",
            json={"user_id": test_user, "item": "cluster-multi-region", "quantity": 3},
            timeout=10,
        )
        r_inv = requests.post(
            f"{primary_url}/invoice",
            json={"customer_name": "Auditoria DR UTB", "amount": 499.99},
            timeout=10,
        )

        if r_tx.status_code == 201 and r_cart.status_code == 200 and r_inv.status_code == 201:
            invoice_id = r_inv.json().get("invoice_id")
            print(f"      [OK] Datos escritos en us-east-1 (Factura: {invoice_id}).")
            results.append(("Escritura Primaria (us-east-1)", True))
        else:
            print("      [FAIL] Error escribiendo en la API primaria.")
            results.append(("Escritura Primaria (us-east-1)", False))
    except Exception as e:
        print(f"      [ERROR] No se pudo conectar al ALB primario: {e}")
        results.append(("Escritura Primaria (us-east-1)", False))

    # 2. Verificar RDS Read Replica en us-west-2
    print(f"\n[2/4] Verificando estado de RDS Read Replica ({secondary_rds_id}) en {secondary_region}...")
    try:
        rds_client = boto3.client("rds", region_name=secondary_region)
        resp = rds_client.describe_db_instances(DBInstanceIdentifier=secondary_rds_id)
        db_inst = resp["DBInstances"][0]
        status = db_inst.get("DBInstanceStatus")
        source = db_inst.get("ReadReplicaSourceDBInstanceIdentifier", "none")
        print(f"      Estado RDS: {status} | Fuente de replicación: {source}")
        results.append(("RDS Read Replica (us-west-2)", status == "available"))
    except Exception as e:
        print(f"      [ERROR] Fallo al consultar RDS en {secondary_region}: {e}")
        results.append(("RDS Read Replica (us-west-2)", False))

    # 3. Verificar DynamoDB Global Table en us-west-2
    print(f"\n[3/4] Verificando replicación activa-activa en DynamoDB ({secondary_region})...")
    try:
        time.sleep(3)  # Esperar propagación asíncrona (< 1-2s habitual)
        dynamo_sec = boto3.client("dynamodb", region_name=secondary_region)
        item_resp = dynamo_sec.get_item(
            TableName=dynamo_table,
            Key={"user_id": {"S": test_user}},
        )
        if "Item" in item_resp:
            origin_reg = item_resp["Item"].get("region", {}).get("S")
            print(f"      [OK] Registro '{test_user}' encontrado en {secondary_region} (origen: {origin_reg}).")
            results.append(("DynamoDB Global Table (us-west-2)", True))
        else:
            print(f"      [FAIL] El registro aún no aparece en {secondary_region}.")
            results.append(("DynamoDB Global Table (us-west-2)", False))
    except Exception as e:
        print(f"      [ERROR] Fallo consultando DynamoDB en {secondary_region}: {e}")
        results.append(("DynamoDB Global Table (us-west-2)", False))

    # 4. Verificar S3 Cross-Region Replication (CRR) en us-west-2
    print(f"\n[4/4] Verificando S3 Cross-Region Replication en bucket '{replica_bucket}'...")
    if not invoice_id:
        print("      [SKIP] No se generó factura en el paso 1.")
        results.append(("S3 CRR Replica (us-west-2)", False))
    else:
        s3_sec = boto3.client("s3", region_name=secondary_region)
        s3_key = f"invoices/{invoice_id}.txt"
        replicated = False
        for attempt in range(1, 7):
            try:
                head = s3_sec.head_object(Bucket=replica_bucket, Key=s3_key)
                print(
                    f"      [OK] Objeto '{s3_key}' replicado en {secondary_region} "
                    f"(VersionId: {head.get('VersionId')})."
                )
                replicated = True
                break
            except Exception:
                print(f"      Intento {attempt}/6: Esperando replicación S3 CRR (5s)...")
                time.sleep(5)
        results.append(("S3 CRR Replica (us-west-2)", replicated))

    # Resumen final
    print("\n=======================================================")
    print(" RESUMEN DE VALIDACIÓN FASE 2 (REPLICACIÓN MULTI-REGIÓN)")
    print("=======================================================")
    all_passed = True
    for name, passed in results:
        status_str = "PASÓ [OK]" if passed else "FALLÓ [X]"
        if not passed:
            all_passed = False
        print(f" - {name:<35}: {status_str}")
    print("=======================================================")

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validación de Replicación Multi-Región - Fase 2")
    parser.add_argument("--primary-url", required=True, help="URL base del ALB primario en us-east-1")
    parser.add_argument(
        "--secondary-rds-id",
        default="dr-architecture-secondary-mysql",
        help="Identificador de la Read Replica de RDS en us-west-2",
    )
    parser.add_argument("--dynamo-table", default="user_sessions", help="Nombre de la tabla DynamoDB")
    parser.add_argument("--replica-bucket", required=True, help="Nombre del bucket S3 réplica en us-west-2")
    parser.add_argument("--secondary-region", default="us-west-2", help="Región secundaria de AWS")
    args = parser.parse_args()

    verify_phase2_replication(
        primary_url=args.primary_url,
        secondary_rds_id=args.secondary_rds_id,
        dynamo_table=args.dynamo_table,
        replica_bucket=args.replica_bucket,
        secondary_region=args.secondary_region,
    )

