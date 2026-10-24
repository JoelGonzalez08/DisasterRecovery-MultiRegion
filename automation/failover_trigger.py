#!/usr/bin/env python3
"""
failover_trigger.py
Automatización SRE para Conmutación por Error (Failover) bajo arquitectura Warm Standby en AWS.
Ejecuta en paralelo:
  1. Promoción de la Read Replica de RDS MySQL en us-west-2 a instancia Writer independiente.
  2. Escalado horizontal del Auto Scaling Group secundario (de desired=0 a desired=2).
  3. Monitoreo de convergencia y cálculo del RTO (Recovery Time Objective < 15 minutos).
"""

import argparse
import sys
import time
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError
import requests


def find_asg_by_prefix(asg_client, prefix: str) -> str:
    """Descubre automáticamente el nombre completo del ASG a partir de su name_prefix."""
    paginator = asg_client.get_paginator("describe_auto_scaling_groups")
    for page in paginator.paginate():
        for group in page.get("AutoScalingGroups", []):
            name = group.get("AutoScalingGroupName", "")
            if name.startswith(prefix):
                return name
    raise RuntimeError(f"No se encontró ningún Auto Scaling Group con el prefijo '{prefix}'.")


def promote_rds_replica(rds_client, db_identifier: str) -> bool:
    """Promueve la Read Replica de RDS MySQL a Writer primario en la región secundaria."""
    print(f"[1/3] Inspeccionando instancia RDS '{db_identifier}'...")
    try:
        resp = rds_client.describe_db_instances(DBInstanceIdentifier=db_identifier)
        db = resp["DBInstances"][0]
        status = db.get("DBInstanceStatus")
        replica_source = db.get("ReadReplicaSourceDBInstanceIdentifier")

        print(f"      Estado actual: {status} | Fuente de replicación: {replica_source or 'Ninguna (Standalone)'}")

        if not replica_source:
            print("      [OK] La instancia RDS ya se encuentra promovida como Writer independiente.")
            return True

        print(f"      >> Ejecutando promote_read_replica en '{db_identifier}'...")
        rds_client.promote_read_replica(DBInstanceIdentifier=db_identifier)
        print("      [OK] Orden de promoción enviada exitosamente a AWS RDS.")
        return True
    except ClientError as e:
        print(f"      [ERROR] Fallo al promover RDS Read Replica: {e.response['Error']['Message']}")
        return False


def scale_up_asg(asg_client, asg_name: str, target_capacity: int, max_capacity: int = 4) -> bool:
    """Escala el Auto Scaling Group secundario desde Warm Standby (0) hasta capacidad productiva."""
    print(f"\n[2/3] Escalando Auto Scaling Group '{asg_name}' a capacidad={target_capacity}...")
    try:
        asg_client.update_auto_scaling_group(
            AutoScalingGroupName=asg_name,
            MinSize=target_capacity,
            DesiredCapacity=target_capacity,
            MaxSize=max(max_capacity, target_capacity),
        )
        print(
            f"      [OK] ASG actualizado: MinSize={target_capacity}, "
            f"DesiredCapacity={target_capacity}, MaxSize={max(max_capacity, target_capacity)}."
        )
        return True
    except ClientError as e:
        print(f"      [ERROR] Fallo al escalar Auto Scaling Group: {e.response['Error']['Message']}")
        return False


def wait_for_convergence(
    rds_client,
    asg_client,
    db_identifier: str,
    asg_name: str,
    target_capacity: int,
    secondary_alb_url: str = None,
    timeout_seconds: int = 900,
) -> bool:
    """Monitorea la promoción de RDS y el arranque de instancias EC2 hasta cumplir el RTO (< 15 min)."""
    print("\n[3/3] Monitoreando convergencia de infraestructura en región secundaria...")
    start_wait = time.time()
    rds_ready = False
    asg_ready = False
    api_ready = secondary_alb_url is None

    while (time.time() - start_wait) < timeout_seconds:
        elapsed = int(time.time() - start_wait)

        # 1. Verificar RDS
        if not rds_ready:
            try:
                resp = rds_client.describe_db_instances(DBInstanceIdentifier=db_identifier)
                db = resp["DBInstances"][0]
                status = db.get("DBInstanceStatus")
                replica_src = db.get("ReadReplicaSourceDBInstanceIdentifier")
                if status == "available" and not replica_src:
                    rds_ready = True
                    print(f"      [+{elapsed}s] [OK] RDS '{db_identifier}' promovido y disponible para escritura.")
            except Exception as e:
                print(f"      [+{elapsed}s] [WARN] Error consultando RDS: {e}")

        # 2. Verificar instancias InService en ASG
        if not asg_ready:
            try:
                resp = asg_client.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])
                groups = resp.get("AutoScalingGroups", [])
                if groups:
                    instances = groups[0].get("Instances", [])
                    in_service = [i for i in instances if i.get("LifecycleState") == "InService"]
                    if len(in_service) >= target_capacity:
                        asg_ready = True
                        print(
                            f"      [+{elapsed}s] [OK] ASG '{asg_name}' tiene "
                            f"{len(in_service)}/{target_capacity} instancias InService."
                        )
            except Exception as e:
                print(f"      [+{elapsed}s] [WARN] Error consultando ASG: {e}")

        # 3. Verificar endpoint HTTP del ALB secundario (opcional)
        if asg_ready and not api_ready and secondary_alb_url:
            try:
                url = f"{secondary_alb_url.rstrip('/')}/health"
                r = requests.get(url, timeout=5)
                if r.status_code == 200 and r.json().get("status") == "healthy":
                    api_ready = True
                    print(f"      [+{elapsed}s] [OK] ALB Secundario respondiendo HTTP 200 en {url}.")
            except Exception:
                pass

        if rds_ready and asg_ready and api_ready:
            return True

        print(
            f"      [+{elapsed}s] Estado -> RDS Writer: {'LISTO' if rds_ready else 'PROMOVIENDO'} | "
            f"ASG ({target_capacity} EC2): {'LISTO' if asg_ready else 'ESCALANDO'}..."
        )
        time.sleep(15)

    print("      [TIMEOUT] Se superó el tiempo máximo de espera (15 minutos).")
    return False


def main():
    parser = argparse.ArgumentParser(
        description="Script SRE de Failover Automatizado para Warm Standby en AWS (us-west-2)"
    )
    parser.add_argument("--region", default="us-west-2", help="Región secundaria de recuperación (default: us-west-2)")
    parser.add_argument(
        "--rds-id",
        default="dr-architecture-secondary-mysql",
        help="Identificador de la instancia RDS Read Replica en la región secundaria",
    )
    parser.add_argument(
        "--asg-name",
        default=None,
        help="Nombre exacto del ASG secundario (si se omite, se descubre por prefijo)",
    )
    parser.add_argument(
        "--asg-prefix",
        default="dr-architecture-secondary-asg-",
        help="Prefijo del ASG secundario para autodescubrimiento",
    )
    parser.add_argument(
        "--capacity",
        type=int,
        default=2,
        help="Capacidad deseada de instancias EC2 al activar el entorno secundario (default: 2)",
    )
    parser.add_argument(
        "--secondary-alb-url",
        default=None,
        help="URL opcional del ALB secundario para verificar /health tras escalar",
    )
    parser.add_argument(
        "--no-wait",
        action="store_true",
        help="Disparar la promoción de RDS y el escalado del ASG sin bloquear esperando convergencia",
    )
    parser.add_argument(
        "--mode",
        choices=["failover", "scale-down"],
        default="failover",
        help="Modo de operación: 'failover' (promueve RDS y escala ASG a 2) o 'scale-down' (regresa ASG a 0)",
    )

    args = parser.parse_args()
    t0 = time.time()
    now_iso = datetime.now(timezone.utc).isoformat()

    print("\n=====================================================================")
    print(f" AUTOMATIZACIÓN DR (WARM STANDBY) - MODO: {args.mode.upper()}")
    print(f" Inicio UTC : {now_iso}")
    print(f" Región DR  : {args.region}")
    print("=====================================================================\n")

    rds_client = boto3.client("rds", region_name=args.region)
    asg_client = boto3.client("autoscaling", region_name=args.region)

    try:
        asg_name = args.asg_name or find_asg_by_prefix(asg_client, args.asg_prefix)
        print(f"[INFO] Auto Scaling Group detectado: {asg_name}\n")
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)

    if args.mode == "scale-down":
        ok = scale_up_asg(asg_client, asg_name, target_capacity=0, max_capacity=4)
        sys.exit(0 if ok else 1)

    # Modo Failover: 1. Promover RDS + 2. Escalar ASG
    rds_ok = promote_rds_replica(rds_client, args.rds_id)
    asg_ok = scale_up_asg(asg_client, asg_name, target_capacity=args.capacity)

    if not (rds_ok and asg_ok):
        print("\n[FAIL] Se produjeron errores al disparar las acciones de Failover.")
        sys.exit(1)

    if not args.no_wait:
        converged = wait_for_convergence(
            rds_client=rds_client,
            asg_client=asg_client,
            db_identifier=args.rds_id,
            asg_name=asg_name,
            target_capacity=args.capacity,
            secondary_alb_url=args.secondary_alb_url,
        )
        total_seconds = int(time.time() - t0)
        minutes, seconds = divmod(total_seconds, 60)
        print("\n=====================================================================")
        print(f" TIEMPO TOTAL DE RECUPERACIÓN (RTO): {minutes}m {seconds}s (Objetivo SLA: < 15m)")
        print("=====================================================================")
        sys.exit(0 if converged else 1)

    print("\n[OK] Acciones de Failover disparadas en segundo plano (--no-wait).")


if __name__ == "__main__":
    main()

