# Etapa 1: Construcción (Builder)
FROM python:3.11-slim as builder
WORKDIR /app
COPY requirements.txt .
# Generar wheels para las dependencias incluyendo subdependencias
RUN pip wheel --no-cache-dir --wheel-dir /app/wheels -r requirements.txt

# Etapa 2: Producción (Runner)
FROM python:3.11-slim
WORKDIR /app
# Copiar únicamente los binarios compilados desde la etapa anterior
COPY --from=builder /app/wheels /wheels
COPY --from=builder /app/requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt && rm -rf /wheels
COPY . .

# Exponer el puerto de Uvicorn
EXPOSE 8000

# Health Check del contenedor
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]