# Estrategia de Disaster Recovery Multi-Región en AWS (Warm Standby)

Proyecto de diseño e implementación de una arquitectura de alta disponibilidad y recuperación ante desastres en **Amazon Web Services (AWS)** bajo el modelo **Warm Standby**, con objetivos de nivel de servicio estrictos:
* **RTO (Recovery Time Objective):** < 15 minutos
* **RPO (Recovery Point Objective):** < 5 minutos

---

## Equipo

* **Integrantes:**
  * Maykol Stiven Madrid Romero — `T00078588` (Compute & Networking Specialist)
  * Joel David Gonzalez Barros — `T00078571` (DevOps Lead & Core IaC)
  * Álvaro Jesús Ayala Alcala — `T00078312` (Database & Persistence Engineer)
  * Diego Peña Paez — `T00067812` (SRE & Automation Engineer)

---

## Arquitectura de la Solución

```text
                          [ Clientes / Tráfico ]
                                     │
                             [ AWS CloudFront ]
                        (Origin Group Multi-Región)
                                     │
                         [ Route 53 Failover DNS ]
                       (Health Check cada 10 seg)
                      ┌──────────────┴──────────────┐
             (Primary)│                             │(Secondary Warm Standby)
                      ▼                             ▼
         ┌───────────────────────────┐ ┌───────────────────────────┐
         │     Región us-east-1      │ │     Región us-west-2      │
         ├───────────────────────────┤ ├───────────────────────────┤
         │ • VPC 10.0.0.0/16 (3-Tier)│ │ • VPC 10.1.0.0/16 (3-Tier)│
         │ • ALB Primario            │ │ • ALB Secundario (Activo) │
         │ • EC2 ASG (2-4 instancias)│ │ • EC2 ASG (desired=0)     │
         │ • RDS MySQL Multi-AZ      │ │ • RDS Read Replica        │
         │   (Escritor Primario)     │ │   (Asíncrona Cross-Region)│
         │ • S3 Source Bucket        │ │ • S3 Replica Bucket       │
         │   (Versionado activado)   │ │   (CRR sincronizado)      │
         └─────────────┬─────────────┘ └─────────────┬─────────────┘
                       │                             │
                       └──────────────┬──────────────┘
                                      ▼
                      ┌─────────────────────────────┐
                      │    DynamoDB Global Tables   │
                      │  (Replicación Activa-Activa)│
                      └─────────────────────────────┘
```

---

## Estructura del Repositorio

```text
├── .github/
│   └── workflows/
│       └── terraform.yml                # CI/CD: Validación en PRs y Despliegue Secuencial (Fases 1, 2 y 3) en main
├── api/
│   ├── Dockerfile                       # Imagen multi-stage optimizada (Python 3.11-slim)
│   ├── main.py                          # API REST transaccional (FastAPI, SQLAlchemy, Boto3)
│   └── requirements.txt                 # Dependencias Python
├── automation/
│   └── failover_trigger.py              # Script SRE Boto3: promueve RDS Read Replica, escala ASG (0->2) y mide RTO
├── docs/
│   └── runbook.md                       # Procedimientos operativos estándar (SOP de Failover & Failback)
├── terraform/
│   ├── environments/
│   │   ├── global/                      # Fase 3: Route 53 Failover DNS + CloudFront Origin Group
│   │   ├── primary_us_east_1/           # Fase 1: Región primaria activa en us-east-1 (desired=2)
│   │   └── secondary_us_west_2/         # Fase 2: Región Warm Standby en us-west-2 (desired=0) + Replicación
│   └── modules/
│       ├── compute_alb_asg/             # Balanceador ALB, IAM Roles, Launch Template y Auto Scaling Group
│       ├── database_rds/                # Instancia MySQL 8.0 (soporta Primary Multi-AZ y Read Replica Cross-Region)
│       ├── route53_failover/            # Hosted Zone, Health Checks HTTP (10s) y Registros Alias PRIMARY/SECONDARY
│       ├── storage_s3/                  # Buckets S3 con versionado, cifrado AES-256 y reglas CRR
│       └── vpc/                         # Red VPC 3-Tier (subredes públicas, privadas de app y privadas de datos aisladas)
├── tests/
│   ├── test_api_connection.py           # Suite de validación E2E Fase 1 (6 pruebas de salud y persistencia)
│   └── test_replication_fase2.py        # Suite de validación E2E Fase 2 (auditoría de replicación en us-west-2)
└── docker-compose.yml                   # Entorno local completo (MySQL 8.0 + LocalStack S3/DynamoDB + API)
```

---

## Fases Implementadas

### Fase 1: Región Primaria (`us-east-1`) y API Transaccional
* **Red 3-Tier (`10.0.0.0/16`):** Subredes públicas (ALB y NAT Gateway), privadas de aplicación (EC2 ASG) y privadas de datos aisladas sin salida a internet (RDS).
* **Persistencia Triple:**
  * **RDS MySQL 8.0 Multi-AZ:** Instancia maestra (`dr-architecture-primary-mysql`) con retención de backups de 7 días.
  * **DynamoDB (`user_sessions`):** Tabla NoSQL `PAY_PER_REQUEST` con `DynamoDB Streams` (`NEW_AND_OLD_IMAGES`) habilitado para Global Tables.
  * **S3 Source Bucket:** Almacenamiento de comprobantes con versionado activo y bloqueo de acceso público.
* **Cómputo Elástico:** ALB público + Auto Scaling Group (`min=2, desired=2, max=4`) desplegando automáticamente el contenedor de la API vía `user_data`.

### Fase 2: Región Secundaria Warm Standby (`us-west-2`) y Replicación Multi-Región
* **Red Secundaria Independiente (`10.1.0.0/16`):** Desplegada en `us-west-2` sin solapamiento de bloques CIDR.
* **Replicación Asíncrona Continua (RPO < 5 min):**
  * **RDS Cross-Region Read Replica:** Instancia `dr-architecture-secondary-mysql` vinculada al ARN primario de `us-east-1` (protegida con `ignore_changes = [replicate_source_db]` ante promociones de failover).
  * **DynamoDB Global Table Replica (`aws_dynamodb_table_replica`):** Replicación activa-activa bidireccional entre `us-east-1` y `us-west-2`.
  * **S3 Cross-Region Replication (CRR):** Bucket réplica en `us-west-2` y configuración automática de la regla CRR e IAM Role sobre el bucket primario.
* **Cómputo en Modo Warm Standby:** ALB secundario activo y Auto Scaling Group configurado en reposo (`min=0, desired=0, max=4`) para optimización de costos hasta que ocurra un evento DR.

### Fase 3: Enrutamiento Global, Automatización SRE y Runbook
* **Route 53 Failover DNS (`route53_failover`):** Health Checks HTTP cada **10 segundos** sobre `GET /health` (`failure_threshold = 3`, detección en 30 segundos) y registros Alias `PRIMARY` (`us-east-1`) y `SECONDARY` (`us-west-2`).
* **AWS CloudFront Multi-Región (`global`):** Distribución global con **Origin Group Failover** que conmuta automáticamente al ALB secundario ante errores `500, 502, 503, 504`.
* **Automatización de Failover (`automation/failover_trigger.py`):** Script Boto3 que autodescubre el ASG secundario, promueve la Read Replica de RDS a *Standalone Writer* (`promote_read_replica`), escala el ASG de `0` a `2` instancias EC2 y calcula en vivo el **RTO total alcanzado (< 15 min)**.
* **CI/CD Multi-Entorno (`.github/workflows/terraform.yml`):** Valida formato y sintaxis de las 3 fases en cada push/PR y ejecuta `terraform apply` secuencialmente (`primary` $\rightarrow$ `secondary` $\rightarrow$ `global`) al integrarse en `main`.

---

## Ejecución Local de la API para Pruebas

El entorno local incluye **MySQL 8.0** y **LocalStack (S3 + DynamoDB)** para validar los 6 endpoints sin costos de infraestructura:

```bash
docker compose up --build -d
python tests/test_api_connection.py --url http://localhost:8000
```

La documentación interactiva OpenAPI (Swagger UI) estará disponible en `http://localhost:8000/docs`.

### Endpoints Principales:
* `GET /health`: Health Check ligero e inmediato para Route 53 / ALB.
* `GET /readiness`: Chequeo profundo de conectividad hacia RDS MySQL, DynamoDB y S3.
* `POST /transaction`: Registra una transacción financiera en RDS MySQL.
* `GET /transactions/latest`: Consulta las últimas transacciones para auditoría de RPO.
* `POST /cart` y `GET /cart/{user_id}`: Gestiona carritos de compra en DynamoDB Global Tables.
* `POST /invoice` y `GET /invoice/{invoice_id}`: Sube y verifica comprobantes digitales en S3 (CRR).

---

## Validación en AWS y Simulación de Desastre (Failover)

1. **Validar conectividad y persistencia en Región Primaria (Fase 1):**
   ```bash
   python tests/test_api_connection.py --url http://<ALB_PRIMARY_DNS>
   ```
2. **Validar replicación multi-región hacia `us-west-2` (Fase 2):**
   ```bash
   python tests/test_replication_fase2.py \
     --primary-url http://<ALB_PRIMARY_DNS> \
     --replica-bucket <S3_REPLICA_BUCKET_NAME>
   ```
3. **Disparar Failover Automatizado hacia `us-west-2` (Fase 3):**
   ```bash
   python automation/failover_trigger.py \
     --region us-west-2 \
     --rds-id dr-architecture-secondary-mysql \
     --capacity 2 \
     --secondary-alb-url http://<ALB_SECONDARY_DNS>
   ```
4. **Retornar ASG secundario a modo Warm Standby (`desired=0`) tras Failback:**
   ```bash
   python automation/failover_trigger.py --region us-west-2 --mode scale-down
   ```

Consulta el procedimiento operativo detallado paso a paso en [`docs/runbook.md`](docs/runbook.md).
