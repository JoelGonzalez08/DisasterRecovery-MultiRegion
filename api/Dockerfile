# Etapa 1: Construcción (Builder)
FROM python:3.11-slim as builder
WORKDIR /app
COPY requirements.txt .
# Generar wheels para las dependencias sin instalar caché innecesario
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /app/wheels -r requirements.txt

# Etapa 2: Producción (Runner)
FROM python:3.11-slim
WORKDIR /app
# Copiar únicamente los binarios compilados desde la etapa anterior
COPY --from=builder /app/wheels /wheels
COPY --from=builder /app/requirements.txt .
RUN pip install --no-cache /wheels/* && rm -rf /wheels
COPY . .

# Exponer el puerto de Uvicorn
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]