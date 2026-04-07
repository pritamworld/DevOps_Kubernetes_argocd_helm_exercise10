We can monitor that Flask + Redis app nicely with **Prometheus + Grafana** (cluster-wide metrics) and **Kubernetes probes/labels** (app-level health).

I’ll assume:

* Your app is in namespace `default`
* Argo CD is in `argocd` (optional, just for context)
* You’re okay deploying community charts/manifests

---

## 1 Install Helm

- https://helm.sh/docs/intro/install/

## 2 Add health & resource monitoring to your Deployment

We already added `livenessProbe` and `readinessProbe` earlier, but let’s be explicit and add resource requests/limits and useful labels that monitoring tools can use:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hellodocker
  labels:
    app: hellodocker
    tier: frontend
    monitored: "true"
spec:
  replicas: 3 #OR your desired number of replicas
  selector:
    matchLabels:
      app: hellodocker
  template:
    metadata:
      labels:
        app: hellodocker
        tier: frontend
        monitored: "true"
    spec:
      containers:
        - name: hellodocker
          image: pritamworld/hellodocker:latest #Replace with your image <dockerusername>/hellodocker:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
          env:
            - name: NAME
              value: "Pritesh from minikube and Kubernetes"
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 10
          resources:
            limits:
              memory: 512Mi
              cpu: "1"
            requests:
              memory: 256Mi
              cpu: "0.2" 

```

This gives you:

* Basic **health checks** (Kubernetes will restart unhealthy pods).
* **Labels** (`app`, `tier`, `monitored`) that Prometheus / Grafana dashboards can filter on.

Redis can also get some resource limits and labels:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  labels:
    app: redis
    tier: cache
    monitored: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        tier: cache
        monitored: "true"
    spec:
      containers:
        - name: redis
          image: redis:7
          ports:
            - containerPort: 6379
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
```

---

## 3 Install Prometheus & Grafana (Prometheus Stack)

The easiest way is the **kube-prometheus-stack** Helm chart (Prometheus + Grafana + node exporter + alertmanager).

If you have Helm:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

This will install:

* Prometheus Server & Alertmanager
* Grafana
* Pre-built Kubernetes dashboards

kube-prometheus-stack has been installed. Check its status by running:
  ```kubectl --namespace monitoring get pods -l "release=monitoring"```


### Access Grafana

Port-forward:

```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
```

Open: `http://localhost:3000`

* Default user/pass (if not overridden): `admin / prom-operator` (or check the secret):

  ```bash
  kubectl get secret -n monitoring \
    monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
  ```

Inside Grafana:

* Add Prometheus as a data source (often already pre-configured).
* Use dashboards like:

  * “Kubernetes / Compute Resources / Namespace (Pods)”
  * “Kubernetes / Compute Resources / Pod”

Filter by:

* Namespace: `default`
* `pod` or `app` label: `flask-redis-app` or `redis`

You’ll see CPU/memory usage, restarts, etc.

NOTE: Visit <https://github.com/prometheus-operator/kube-prometheus> for instructions on how to create & configure Alertmanager a
nd Prometheus instances using the Operator.

---

## 4 Scraping app metrics (optional custom metrics)

Right now, your Flask app does **not** expose Prometheus metrics. If you want **custom app-level metrics** (e.g., visits counter, response times), you’d:

1. Add `prometheus_client` to Flask
2. Expose `/metrics` endpoint
3. Annotate the Service so Prometheus auto-discovers it

### 4.1 Modify Flask app (Python side)

Install library in your image:

```bash
pip install prometheus_client
```

Update your app:

```python
from flask import Flask, Response
from redis import Redis, RedisError
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
import os
import socket

redis = Redis(host="redis", db=0, socket_connect_timeout=2, socket_timeout=2)
app = Flask(__name__)

# Define a Prometheus counter for visits
VISITS_COUNTER = Counter('flask_app_visits_total', 'Total visits to the root endpoint')

@app.route("/")
def hello():
    try:
        visits = redis.incr("counter")
    except RedisError:
        visits = -1  # use -1 to indicate error
    VISITS_COUNTER.inc()
    html = "<h3>Hello {name}!</h3>" \
           "<b>Hostname:</b> {hostname}<br/>" \
           "<b>Visits:</b> {visits}"
    return html.format(name=os.getenv("NAME", "world"), hostname=socket.gethostname(), visits=visits)

@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80)
```

Now your app exposes Prometheus metrics at `/metrics`.

### 4.2 Annotate the Service for Prometheus scrape

If you’re using kube-prometheus-stack, the Prometheus instance normally watches services with specific annotations.

Update your Flask Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hellodocker-nodeport
  labels:
    app: hellodocker
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/path: "/metrics"
    prometheus.io/port: "80"
spec:
  type: NodePort #OR LoadBalancer or ClusterIP depending on your needs
  selector:
    app: hellodocker
  ports:
    - name: http
      port: 80
      targetPort: 80
      nodePort: 30080 # optional; pick any free port in 30000–32767

```

Prometheus will start scraping `http://<pod-ip>:80/metrics`.

You can now **query in Prometheus/Grafana**:

* `flask_app_visits_total` per pod
* Combine with Kubernetes labels for more detail

---

## 5 Basic alerting examples

Once Prometheus is scraping data, you can add some simple alert rules to catch problems.

Example `PrometheusRule` (for kube-prometheus-stack) to alert on:

* High error rate on Flask (if you add HTTP error_metrics later)
* Pods restarting too often
* High CPU usage

Create: `flask-redis-alerts.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: flask-redis-alerts
  namespace: monitoring
  labels:
    release: monitoring
spec:
  groups:
    - name: flask-redis.rules
      rules:
        - alert: FlaskRedisHighRestart
          expr: increase(kube_pod_container_status_restarts_total{namespace="default", pod=~"flask-redis-app-.*"}[5m]) > 3
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Flask Redis app pod is restarting frequently"
            description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} restarted more than 3 times in 5m."

        - alert: FlaskRedisHighCPU
          expr: sum(rate(container_cpu_usage_seconds_total{namespace="default", pod=~"flask-redis-app-.*"}[5m])) > 0.5
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "High CPU usage for Flask Redis app"
            description: "Total CPU usage > 0.5 cores for more than 10m."

        - alert: RedisHighCPU
          expr: sum(rate(container_cpu_usage_seconds_total{namespace="default", pod=~"redis-.*"}[5m])) > 0.5
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "High CPU usage for Redis"
            description: "Redis CPU usage > 0.5 cores for more than 10m."
```

Apply:

```bash
kubectl apply -f flask-redis-alerts.yaml
```

Alertmanager (from the same Helm stack) can then be configured to send alerts via email, Slack, etc.

---

## 6 Optional: Argo CD monitoring

Since you’re already using Argo CD, you can also:

* Install the **Argo CD Grafana dashboard** (provided in kube-prometheus-stack examples), or
* Use Argo CD’s own metrics (`argocd-metrics` service) to monitor sync status, health, etc.

If you want, I can next:

* Add **Grafana dashboard JSON** specifically for your `flask-redis-app`
* Or show how to **expose Prometheus & Grafana via Ingress** in your cluster.
