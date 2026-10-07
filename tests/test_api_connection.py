#!/usr/bin/env python3
"""
test_api_connection.py
Script de validación inicial para la Fase 1.
Prueba end-to-end la conectividad entre el ALB público y los 3 servicios de persistencia en AWS (RDS, DynamoDB, S3).
"""

import sys
import time
import argparse
import requests

def run_tests(base_url: str):
    base_url = base_url.rstrip("/")
    print(f"\n=======================================================")
    print(f" Iniciando Pruebas de Validación - Fase 1")
    print(f" URL Base del ALB: {base_url}")
    print(f"=======================================================\n")

    results = []

    # 1. Probar /health
    print("[1/6] Verificando Health Check del ALB (/health)...")
    try:
        r = requests.get(f"{base_url}/health", timeout=10)
        if r.status_code == 200 and r.json().get("status") == "healthy":
            print(f"      [OK] ALB y API saludables. Región: {r.json().get('region')}")
            results.append(("ALB /health", True))
        else:
            print(f"      [FAIL] Status: {r.status_code}, Body: {r.text}")
            results.append(("ALB /health", False))
    except Exception as e:
        print(f"      [ERROR] No se pudo conectar: {e}")
        results.append(("ALB /health", False))

    # 2. Probar /readiness
    print("\n[2/6] Verificando conectividad a componentes AWS (/readiness)...")
    try:
        r = requests.get(f"{base_url}/readiness", timeout=15)
        if r.status_code == 200:
            data = r.json()
            print(f"      Estado reportado: {data}")
            all_connected = all(v == "connected" for k, v in data.items() if k != "region")
            results.append(("AWS Readiness", all_connected))
        else:
            print(f"      [FAIL] Status: {r.status_code}, Body: {r.text}")
            results.append(("AWS Readiness", False))
    except Exception as e:
        print(f"      [ERROR] No se pudo conectar: {e}")
        results.append(("AWS Readiness", False))

    # 3. Probar persistencia relacional en RDS MySQL
    print("\n[3/6] Probando inserción relacional en RDS MySQL (/transaction)...")
    try:
        tx_payload = {
            "user_id": "test-student-utb",
            "amount": 250.75,
            "description": "Prueba de validacion Fase 1"
        }
        r = requests.post(f"{base_url}/transaction", json=tx_payload, timeout=10)
        if r.status_code == 201:
            tx_id = r.json().get("transaction_id")
            print(f"      [OK] Transacción registrada con éxito. ID: {tx_id}")
            results.append(("RDS MySQL Write", True))
        else:
            print(f"      [FAIL] Status: {r.status_code}, Body: {r.text}")
            results.append(("RDS MySQL Write", False))
    except Exception as e:
        print(f"      [ERROR] Fallo en RDS: {e}")
        results.append(("RDS MySQL Write", False))

    # 4. Probar consulta de auditoría en MySQL
    print("\n[4/6] Verificando consulta de auditoría (/transactions/latest)...")
    try:
        r = requests.get(f"{base_url}/transactions/latest", timeout=10)
        if r.status_code == 200 and len(r.json()) > 0:
            print(f"      [OK] Se recuperaron {len(r.json())} transacciones de RDS.")
            results.append(("RDS MySQL Read", True))
        else:
            print(f"      [FAIL] No se encontraron registros.")
            results.append(("RDS MySQL Read", False))
    except Exception as e:
        print(f"      [ERROR] Fallo al consultar transacciones: {e}")
        results.append(("RDS MySQL Read", False))

    # 5. Probar DynamoDB
    print("\n[5/6] Probando escritura y lectura en DynamoDB (/cart)...")
    try:
        cart_payload = {"user_id": "usr-fase1", "item": "servidor-cloud", "quantity": 2}
        r_post = requests.post(f"{base_url}/cart", json=cart_payload, timeout=10)
        r_get = requests.get(f"{base_url}/cart/usr-fase1", timeout=10)
        if r_post.status_code == 200 and r_get.status_code == 200:
            print(f"      [OK] Carrito persistido y recuperado de DynamoDB.")
            results.append(("DynamoDB", True))
        else:
            print(f"      [FAIL] POST: {r_post.status_code}, GET: {r_get.status_code}")
            results.append(("DynamoDB", False))
    except Exception as e:
        print(f"      [ERROR] Fallo en DynamoDB: {e}")
        results.append(("DynamoDB", False))

    # 6. Probar S3
    print("\n[6/6] Probando subida de comprobante a S3 (/invoice)...")
    try:
        inv_payload = {"customer_name": "Facultad de Sistemas UTB", "amount": 800.00}
        r_post = requests.post(f"{base_url}/invoice", json=inv_payload, timeout=10)
        if r_post.status_code == 201:
            inv_id = r_post.json().get("invoice_id")
            r_get = requests.get(f"{base_url}/invoice/{inv_id}", timeout=10)
            if r_get.status_code == 200:
                print(f"      [OK] Factura {inv_id} subida y verificada en S3.")
                results.append(("S3 Object Storage", True))
            else:
                print(f"      [FAIL] No se pudo verificar factura en S3.")
                results.append(("S3 Object Storage", False))
        else:
            print(f"      [FAIL] Fallo al subir factura a S3: {r_post.text}")
            results.append(("S3 Object Storage", False))
    except Exception as e:
        print(f"      [ERROR] Fallo en S3: {e}")
        results.append(("S3 Object Storage", False))

    # Resumen
    print("\n=======================================================")
    print(" RESUMEN DE RESULTADOS FASE 1")
    print("=======================================================")
    all_passed = True
    for name, passed in results:
        status_str = "PASÓ [OK]" if passed else "FALLÓ [X]"
        if not passed:
            all_passed = False
        print(f" - {name:<22}: {status_str}")

    print("=======================================================")
    if all_passed:
        print(">> TODOS LOS COMPONENTES DE LA FASE 1 ESTÁN OPERACIONALES <<\n")
        sys.exit(0)
    else:
        print(">> SE DETECTARON FALLOS EN LA VALIDACIÓN <<\n")
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validación end-to-end de la Fase 1 en AWS")
    parser.add_argument("--url", default="http://localhost:8000", help="URL base del ALB o localhost")
    args = parser.parse_args()
    run_tests(args.url)
