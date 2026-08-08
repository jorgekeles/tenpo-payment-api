import os
import json
from datetime import datetime
from flask import Flask, request, jsonify
from google.cloud import pubsub_v1

app = Flask(__name__)

# Configuración básica leída de variables de entorno
PROJECT_ID = os.getenv("GCP_PROJECT", "tenpo-payment-challenge")
TOPIC_NAME = os.getenv("PUBSUB_TOPIC", "tenpo-payment-events-dev")

# Inicialización del cliente de Pub/Sub
try:
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(PROJECT_ID, TOPIC_NAME)
except Exception as e:
    print(f"Advertencia: No se pudo conectar a Pub/Sub localmente: {e}")
    publisher = None

# Helper para logs de pagos exitosos
def log_success(payload, message_id, start_time):
    duration_ms = (datetime.utcnow() - start_time).total_seconds() * 1000.0
    log_data = {
        "level": "INFO",
        "message": "Pago procesado exitosamente",
        "transaction_id": payload["transaction_id"],
        "user_id": payload["user_id"],
        "amount": payload["amount"],
        "currency": payload["currency"],
        "status": "SUCCESS",
        "pubsub_message_id": message_id,
        "duration_ms": duration_ms,
        "timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    print(json.dumps(log_data))

# Helper para logs de fallos
def log_failure(error_code, error_message, start_time, transaction_id=None):
    duration_ms = (datetime.utcnow() - start_time).total_seconds() * 1000.0
    log_data = {
        "level": "ERROR",
        "message": "Fallo en el procesamiento de pago",
        "error_code": error_code,
        "error_message": error_message,
        "status": "FAILED",
        "duration_ms": duration_ms,
        "timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    if transaction_id:
        log_data["transaction_id"] = transaction_id
    print(json.dumps(log_data))

@app.route("/", methods=["GET"])
def health():
    # Endpoint básico para el health check de Cloud Run
    return jsonify({"status": "healthy"}), 200

@app.route("/payments", methods=["POST"])
def process_payment():
    start_time = datetime.utcnow()
    
    # Validamos que la petición contenga JSON
    data = request.get_json(silent=True)
    if not data:
        log_failure("BAD_REQUEST", "El payload no es un JSON valido", start_time)
        return jsonify({"error": "Invalid payload"}), 400

    # Extraemos y validamos campos obligatorios
    transaction_id = data.get("transaction_id")
    user_id = data.get("user_id")
    amount = data.get("amount")
    currency = data.get("currency")

    if not all([transaction_id, user_id, amount, currency]):
        log_failure("MISSING_FIELDS", "Faltan campos mandatorios en el JSON", start_time, transaction_id)
        return jsonify({"error": "Missing mandatory fields"}), 400

    # Validamos que el monto sea un número positivo
    try:
        amount_val = float(amount)
        if amount_val <= 0:
            log_failure("INVALID_AMOUNT", "El monto de la transaccion debe ser mayor a cero", start_time, transaction_id)
            return jsonify({"error": "Amount must be greater than zero"}), 400
    except ValueError:
        log_failure("INVALID_AMOUNT", "El monto ingresado no es un numero valido", start_time, transaction_id)
        return jsonify({"error": "Amount must be a numeric value"}), 400

    # Armamos la estructura de la transacción
    payload = {
        "transaction_id": str(transaction_id),
        "user_id": str(user_id),
        "amount": amount_val,
        "currency": str(currency),
        "status": "SUCCESS",
        "created_at": start_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    }

    # Intentamos publicar en Pub/Sub
    if publisher is None:
        log_failure("PUBSUB_OFFLINE", "Cliente Pub/Sub no inicializado", start_time, transaction_id)
        return jsonify({"error": "Internal error: Pub/Sub unavailable"}), 500

    try:
        message_bytes = json.dumps(payload).encode("utf-8")
        future = publisher.publish(topic_path, data=message_bytes)
        message_id = future.result() # Esperamos confirmación de envío
        
        # Log estructurado de éxito
        log_success(payload, message_id, start_time)
        
        return jsonify({
            "message": "Payment processed",
            "transaction_id": transaction_id,
            "status": "SUCCESS"
        }), 201

    except Exception as e:
        # Fallo de conexión o credenciales al publicar en el tópico
        log_failure("PUBSUB_PUBLISH_FAILED", str(e), start_time, transaction_id)
        return jsonify({"error": "Internal server error"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 8080)), debug=True)
