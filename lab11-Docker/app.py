from flask import Flask, Response
from redis import Redis, RedisError
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
import os
import socket

# Connect to Redis
redis = Redis(host="redis", db=0, socket_connect_timeout=2, socket_timeout=2)

app = Flask(__name__)

# Define a Prometheus counter for visits
VISITS_COUNTER = Counter('flask_app_visits_total', 'Total visits to the root endpoint')

@app.route("/")
def hello():
    try:
        visits = redis.incr("counter")
    except RedisError:
        visits = "<i>cannot connect to Redis, counter disabled</i>"
    
    VISITS_COUNTER.inc()
    html = "<h3>Hello {name}!</h3>" \
                "<b>Hostname:</b> {hostname}<br/>" \
                "<b>Visits:</b> {visits}"
    return html.format(name=os.getenv("NAME", "world"), hostname=socket.gethostname(), visits=visits)

@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

# This returns the Pod Name in a Kubernetes environment
@app.route("/hostname")
def hostname():
    pod_name = socket.gethostname()
    return f"<h1>Host name is: {pod_name} </h1>", 200

@app.route("/greet")
def greet():
    return "<h1>Welcome to Minikube, kubernetes, monitoring (Grafana & Prometheus setup using helm) and argoCD examples</h1>"

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80)
