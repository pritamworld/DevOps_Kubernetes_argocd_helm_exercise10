Now you’re stepping into a **real platform build**—this is essentially a **mini production Kubernetes environment on Azure**. A single VM won’t cut it anymore, so we’ll restructure into:

* 🖥️ 1 Control Plane VM
* 🖥️ 2 Worker VMs
* ⚙️ Automated cluster bootstrap (kubeadm)
* 🌐 Ingress + TLS (NGINX + cert-manager)
* 🔁 GitOps (ArgoCD)
* 📊 Observability (Prometheus + Grafana + Loki + Tempo)
* 🐳 Sample microservices app

I’ll give you a **clean, scalable Terraform + cloud-init design**, not a hacky script.

---

# 🧱 Architecture Overview

```
Azure
 ├── VNet
 ├── Control Plane VM
 ├── Worker VM 1
 ├── Worker VM 2
 └── Public IP (control plane)

Inside Kubernetes:
 ├── Ingress Controller (NGINX)
 ├── cert-manager (TLS)
 ├── ArgoCD (GitOps)
 ├── kube-prometheus-stack
 ├── Loki + Tempo
 └── Sample App (frontend + API + DB)
```

---

# 📁 Terraform Structure (clean + modular)

```
.
├── main.tf
├── variables.tf
├── outputs.tf
├── cloud-init/
│   ├── control-plane.yaml
│   └── worker.yaml
```

---

# 🔥 Key Terraform (multi-VM cluster)

## 🖥️ Create multiple VMs

```hcl id="cluster-vms"
locals {
  worker_count = 2
}

# Control Plane
resource "azurerm_linux_virtual_machine" "control_plane" {
  name                = "cp-1"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = "Standard_B4ms"
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.cp_nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.public_key
  }

  custom_data = base64encode(file("${path.module}/cloud-init/control-plane.yaml"))
}

# Workers
resource "azurerm_linux_virtual_machine" "workers" {
  count               = local.worker_count
  name                = "worker-${count.index}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = "Standard_B2s"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.worker_nic[count.index].id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.public_key
  }

  custom_data = base64encode(file("${path.module}/cloud-init/worker.yaml"))
}
```

---

# ☸️ Control Plane Bootstrap

## 📁 `cloud-init/control-plane.yaml`

```yaml id="control-plane"
#cloud-config
package_update: true
packages:
  - curl
  - apt-transport-https
  - ca-certificates

runcmd:
  # Install container runtime
  - apt-get update
  - apt-get install -y containerd

  # Kubernetes tools
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/k8s.gpg
  - echo "deb [signed-by=/etc/apt/keyrings/k8s.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" > /etc/apt/sources.list.d/k8s.list
  - apt-get update
  - apt-get install -y kubelet kubeadm kubectl

  # Init cluster
  - kubeadm init --pod-network-cidr=10.244.0.0/16

  # kubeconfig
  - mkdir -p /home/azureuser/.kube
  - cp /etc/kubernetes/admin.conf /home/azureuser/.kube/config
  - chown -R azureuser:azureuser /home/azureuser/.kube

  # Flannel network
  - su - azureuser -c "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"

  # Install Helm
  - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  # Install NGINX Ingress
  - su - azureuser -c "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx"
  - su - azureuser -c "helm install ingress ingress-nginx/ingress-nginx"

  # Install cert-manager
  - su - azureuser -c "helm repo add jetstack https://charts.jetstack.io"
  - su - azureuser -c "helm install cert-manager jetstack/cert-manager --set installCRDs=true"

  # Install ArgoCD
  - su - azureuser -c "kubectl create namespace argocd"
  - su - azureuser -c "kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

  # Observability stack
  - su - azureuser -c "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"
  - su - azureuser -c "helm repo add grafana https://grafana.github.io/helm-charts"

  - su - azureuser -c "helm install monitoring prometheus-community/kube-prometheus-stack"

  # Loki + Tempo
  - su - azureuser -c "helm install loki grafana/loki-stack"
  - su - azureuser -c "helm install tempo grafana/tempo"

  # Sample microservices app
  - su - azureuser -c "kubectl create namespace demo"
  - su - azureuser -c "kubectl apply -n demo -f https://k8s.io/examples/application/guestbook/redis-leader-deployment.yaml"
  - su - azureuser -c "kubectl apply -n demo -f https://k8s.io/examples/application/guestbook/frontend-deployment.yaml"
```

---

# 👷 Worker Node Bootstrap

## 📁 `cloud-init/worker.yaml`

```yaml id="worker-node"
#cloud-config
package_update: true

runcmd:
  - apt-get update
  - apt-get install -y containerd

  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/k8s.gpg
  - echo "deb [signed-by=/etc/apt/keyrings/k8s.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" > /etc/apt/sources.list.d/k8s.list
  - apt-get update
  - apt-get install -y kubelet kubeadm

  # ⚠️ Join command placeholder
  # Replace with output from control plane:
  # kubeadm join <IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

---

# ⚠️ IMPORTANT (Real-world constraint)

Terraform **cannot automatically pass the kubeadm join token** cleanly between VMs without extra tooling.

### ✅ Proper solutions:

* Use **Ansible after provisioning**
* Or use:

  * Azure VM extensions
  * Terraform `null_resource` + SSH (less ideal)

👉 If you want, I can wire **fully automated join with Ansible**.

---

# 🌐 What you get

## Kubernetes Platform

* Multi-node cluster
* Ingress controller
* TLS-ready (cert-manager)

## GitOps

* ArgoCD installed
* Ready to sync apps from GitHub

## Observability

* Prometheus + Grafana
* Loki (logs)
* Tempo (traces)

## App Layer

* Sample microservices deployed

---

# 🚀 What’s missing (next step)

To make this **production-grade**, you should add:

### 🔐 TLS ClusterIssuer

* Let’s Encrypt config

### 🌍 DNS

* Point domain → public IP

### 🔁 ArgoCD App

* Auto-deploy from Git repo

---

# ⚡ If you want next level

I can upgrade this into:

* ✅ Fully automated node join (no manual step)
* ✅ Real domain + HTTPS (Let’s Encrypt working)
* ✅ ArgoCD app-of-apps pattern
* ✅ Production microservices (React + Node + PostgreSQL)
* ✅ Horizontal autoscaling (HPA)
* ✅ CI/CD pipeline (GitHub Actions → deploy to cluster)

---

Just tell me:

👉 “make it fully automated (no manual kubeadm step)”

and I’ll wire the missing piece (this is where most people get stuck).
