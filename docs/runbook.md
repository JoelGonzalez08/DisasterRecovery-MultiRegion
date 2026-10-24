# Runbook Operativo: Disaster Recovery Multi-Región (Warm Standby)

Este documento define los **Procedimientos Operativos Estándar (SOP)** para ejecutar, validar y auditar la conmutación por error (**Failover**) y la recuperación a la región original (**Failback**) entre **`us-east-1` (Primaria)** y **`us-west-2` (Secundaria - Warm Standby)**.

---

## 1. Objetivos de Nivel de Servicio (SLA) y Presupuesto de Tiempo

| Métrica | Objetivo | Mecanismo Técnico | Tiempo Estimado Real |
| :--- | :---: | :--- | :---: |
| **RPO (Recovery Point Objective)** | **< 5 minutos** | • **DynamoDB Global Tables:** Replicación activa-activa.<br>• **RDS MySQL Read Replica:** Replicación asíncrona cross-region.<br>• **S3 CRR:** Replicación continua de objetos con versionado. | **1 – 15 segundos** (RDS/DynamoDB)<br>**< 1 – 3 minutos** (S3 CRR) |
| **RTO (Recovery Time Objective)** | **< 15 minutos** | • **Route 53 Health Check:** Intervalo de 10s (3 fallos = 30s).<br>• **RDS Promotion:** `promote_read_replica` vía Boto3.<br>• **EC2 ASG Scale-Out:** Escalado de `0 -> 2` instancias en `us-west-2`. | **3 – 6 minutos** |

---

## 2. Secuencia de Despliegue de Infraestructura (End-to-End)

El despliegue sigue un orden lineal sin dependencias circulares:

```bash
# 1. Fase 1: Región Primaria (us-east-1)
cd terraform/environments/primary_us_east_1
terraform init
terraform apply -auto-approve

# 2. Fase 2: Región Secundaria Warm Standby + Replicación (us-west-2)
cd ../secondary_us_west_2
terraform init
terraform apply -auto-approve

# 3. Fase 3: Capa Global (Route 53 Failover DNS + CloudFront Origin Group)
cd ../global
terraform init
terraform apply -auto-approve
```

---

## 3. Verificación Pre-Incidente (Estado Saludable y Replicación)

Antes de ejecutar un simulacro de desastre (Chaos / DR Drill), verifique que la región primaria y la replicación hacia `us-west-2` estén operativas:

### 3.1 Validar API y Persistencia en Región Primaria (Fase 1)
```bash
python tests/test_api_connection.py --url http://<ALB_PRIMARY_DNS>
```

### 3.2 Validar Replicación Cross-Region hacia `us-west-2` (Fase 2)
```bash
python tests/test_replication_fase2.py \
  --primary-url http://<ALB_PRIMARY_DNS> \
  --replica-bucket <S3_REPLICA_BUCKET_NAME>
```

---

## 4. Procedimiento de Conmutación por Error (Failover: `us-east-1` -> `us-west-2`)

### Paso 1: Detección del Incidente
1. El Health Check de Route 53 (`GET /health` cada `10 segundos`, `failure_threshold = 3`) detecta la indisponibilidad del ALB primario en **`30 segundos`**.
2. Route 53 conmuta las respuestas DNS del registro `PRIMARY` (`us-east-1`) al registro `SECONDARY` (`us-west-2`), y CloudFront activa su **Origin Failover** ante códigos `500/502/503/504`.

### Paso 2: Promoción de Base de Datos y Escalado de Cómputo (`failover_trigger.py`)
Ejecute el script automatizado de SRE para promover la Read Replica de RDS MySQL a **Standalone Writer** y escalar el Auto Scaling Group secundario de `0` a `2` instancias EC2:

```bash
python automation/failover_trigger.py \
  --region us-west-2 \
  --rds-id dr-architecture-secondary-mysql \
  --capacity 2 \
  --secondary-alb-url http://<ALB_SECONDARY_DNS>
```

> **Nota:** Si desea disparar las acciones en AWS sin esperar en consola, agregue la bandera `--no-wait`.

### Paso 3: Validación Post-Failover y Auditoría de RPO/RTO
Una vez que `failover_trigger.py` confirme la convergencia y reporte el **RTO total alcanzado**:

1. **Verificar salud y escritura en la nueva región activa (`us-west-2`):**
   ```bash
   python tests/test_api_connection.py --url http://<ALB_SECONDARY_DNS>
   ```
2. **Auditar RPO (Cero pérdida de transacciones previas al corte):**
   ```bash
   curl -s http://<ALB_SECONDARY_DNS>/transactions/latest | python -m json.tool
   ```
   Verifique que las transacciones con `"region": "us-east-1"` creadas antes del incidente estén presentes junto con las nuevas transacciones registradas bajo `"region": "us-west-2"`.
3. **Verificar resolución DNS Failover en Route 53:**
   ```bash
   nslookup api.dr-utb-cloud.com <ROUTE53_NAMESERVER>
   ```

---

## 5. Procedimiento de Retorno a la Normalidad (Failback: `us-west-2` -> `us-east-1`)

Cuando la región primaria (`us-east-1`) se ha recuperado:

1. **Restablecer la topología de Base de Datos Relacional:**
   * Generar un snapshot de la instancia RDS promovida en `us-west-2` o configurar replicación hacia `us-east-1` durante una ventana de mantenimiento controlada.
   * Recrear la Read Replica en `us-west-2` ejecutando `terraform apply` en `terraform/environments/secondary_us_west_2`.
2. **Restaurar el Tráfico Global a `us-east-1`:**
   * Al estar saludable `GET /health` en el ALB de `us-east-1`, Route 53 y CloudFront redirigen automáticamente el tráfico hacia el origen `PRIMARY` (`us-east-1`).
3. **Reducir el Cómputo Secundario a Modo Warm Standby (`desired=0`):**
   * Para detener el cobro de instancias EC2 en `us-west-2` y regresar al estado de reposo Warm Standby:
   ```bash
   python automation/failover_trigger.py --region us-west-2 --mode scale-down
   ```

