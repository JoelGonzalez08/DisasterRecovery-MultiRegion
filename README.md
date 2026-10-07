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

```
                          [ Clientes / Tráfico ]
                                     │
                             [ AWS CloudFront ]
                                     │
                         [ Route 53 Failover DNS ]
                       (Health Check cada 10 seg)
                      ┌──────────────┴──────────────┐
             (Primary)│                             │(Secondary Warm Standby)
                      ▼                             ▼
         ┌───────────────────────────┐ ┌───────────────────────────┐
         │     Región us-east-1      │ │     Región us-west-2      │
         ├───────────────────────────┤ ├───────────────────────────┤
         │ • ALB Primario            │ │ • ALB Secundario          │
         │ • EC2 ASG (2-4 instancias)│ │ • EC2 ASG (desired=0)     │
         │ • RDS MySQL Multi-AZ      │ │ • RDS Read Replica        │
         │   (Escritor Primario)     │ │   (Asíncrona)             │
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

## 📁 Estructura del Repositorio

```text
├── .github/
│   └── workflows/
│       └── terraform.yml            # CI/CD: Terraform Init, Format, Validate, Plan & Apply
├── api/
│   ├── Dockerfile                   # Imagen multi-stage optimizada
│   ├── main.py                      # API REST transaccional (FastAPI, SQLAlchemy, Boto3)
│   └── requirements.txt             # Dependencias Python
├── automation/
│   └── failover_trigger.py          # Script Boto3 para promover RDS y escalar ASG
├── docs/
│   └── runbook.md                   # Procedimientos operativos estándar (Failover & Failback)
├── terraform/
│   ├── environments/
│   │   ├── global/                  # Route 53, CloudFront, DynamoDB Global Tables
│   │   ├── primary_us_east_1/       # Módulos desplegados en us-east-1
│   │   └── secondary_us_west_2/     # Módulos desplegados en us-west-2 (desired=0)
│   └── modules/
│       ├── compute_alb_asg/         # Balanceador y grupos de autoescalado
│       ├── database_rds/            # Instancia MySQL Multi-AZ y Read Replica
│       ├── route53_failover/        # Registros DNS y Health Checks
│       ├── storage_s3/              # Buckets con versionado y reglas CRR
│       └── vpc/                     # Red VPC, subredes públicas y privadas, gateways
└── docker-compose.yml               # Entorno de pruebas local para desarrollo rápido
```

---

## Ejecución Local de la API para Pruebas

Para validar los endpoints transaccionales localmente sin costos de infraestructura:

```bash
docker compose up --build
```

La API estará disponible en `http://localhost:8000/docs` con documentación OpenAPI interactiva (Swagger UI).

### Endpoints Principales:
* `GET /health`: Health Check liviano para Route 53 / ALB.
* `GET /readiness`: Chequeo profundo de conexión a RDS, DynamoDB y S3.
* `POST /transaction`: Simula escritura financiera en RDS MySQL.
* `GET /transactions/latest`: Consulta transacciones recientes para auditoría de RPO.
* `POST /cart`: Actualiza carritos en DynamoDB (Global Tables).
* `POST /invoice`: Sube comprobante a S3 (Cross-Region Replication).