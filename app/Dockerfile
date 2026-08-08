FROM python:3.10-alpine

WORKDIR /app

# Copiamos e instalamos dependencias primero para optimizar el cacheo de capas
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiamos el codigo de la app
COPY main.py .

# Cloud Run escucha por defecto en el puerto 8080
EXPOSE 8080

# Corremos con gunicorn para produccion
CMD ["gunicorn", "-b", "0.0.0.0:8080", "main:app"]
