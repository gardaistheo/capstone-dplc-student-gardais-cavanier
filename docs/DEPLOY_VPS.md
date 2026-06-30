# Déploiement Kubernetes (k3s) — World Cup 2026

> Guide de déploiement pour Claude Code sur le VPS cible.
> Suis chaque étape dans l'ordre et vérifie le résultat avant de continuer.

## Architecture déployée

```
Internet (port 80/443)
        │
        ▼
  Traefik Ingress  (k3s built-in)
        │
        ▼
  worldcup-app Service (ClusterIP :3000)
        │
    ┌───┴────┐
    │        │
  Pod 1    Pod 2   ← minReplicas: 2, maxReplicas: 10 (HPA sur CPU)
    │
    ▼
postgres Service (ClusterIP :5432)
    │
    ▼
postgres StatefulSet + PVC 1Gi  (local-path)

namespace: monitoring
  ├── Prometheus  (métriques, scrape /metrics toutes les 15s)
  ├── Grafana     (dashboards)
  └── Alertmanager (alertes CPU, mémoire, crash, latence)
```

## Prérequis VPS

- OS : Ubuntu 20.04+ ou Debian 11+
- CPU : 2+ vCPU, RAM : 4+ GB, Stockage : 20+ GB
- Ports ouverts en entrée : 22, 80, 443, 6443
- Accès root ou sudo

---

## Étape 0 — Variables de session

Exécute ces commandes au début. Elles seront utilisées dans toutes les étapes suivantes.

```bash
# Adapter DOCKER_REGISTRY à ton registry (Docker Hub ou GHCR)
export DOCKER_REGISTRY="docker.io/TON_USERNAME"   # ex: docker.io/gardaistheo
# ou : export DOCKER_REGISTRY="ghcr.io/TON_GITHUB_USERNAME"

export IMAGE_NAME="worldcup-app"
export IMAGE_TAG="latest"
export K8S_NAMESPACE="worldcup"
export HELM_RELEASE="worldcup"
export DB_PASSWORD=$(openssl rand -base64 24)

echo "====================================="
echo "DOCKER_REGISTRY : $DOCKER_REGISTRY"
echo "K8S_NAMESPACE   : $K8S_NAMESPACE"
echo "DB_PASSWORD     : $DB_PASSWORD"
echo "====================================="
echo "⚠️  Notez DB_PASSWORD — il ne sera plus affiché."
```

---

## Étape 1 — Installation des outils

### 1.1 Docker

```bash
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker $USER
  newgrp docker
else
  echo "✓ Docker $(docker --version)"
fi
```

### 1.2 k3s

```bash
if ! command -v kubectl &>/dev/null; then
  curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
  sleep 20
else
  echo "✓ k3s déjà installé"
fi

# Configurer kubectl
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
export KUBECONFIG=~/.kube/config
grep -q 'KUBECONFIG' ~/.bashrc || echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

# Vérification
kubectl get nodes
# Attendu : nœud en état "Ready"
```

### 1.3 Helm

```bash
if ! command -v helm &>/dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "✓ Helm $(helm version --short)"
fi
```

### 1.4 Vérification globale

```bash
echo "=== Versions ===" && docker --version && kubectl version --client --short && helm version --short
echo "=== Nœud k3s ===" && kubectl get nodes
# Le nœud doit être "Ready" avant de continuer
```

---

## Étape 2 — Build et push de l'image Docker

```bash
cd ~/capstone-dplc-student-gardais-cavanier

# Build
docker build -t $DOCKER_REGISTRY/$IMAGE_NAME:$IMAGE_TAG ./app

# Login au registry
# Docker Hub :
docker login
# ou GHCR : echo $GITHUB_PAT | docker login ghcr.io -u TON_USERNAME --password-stdin

# Push
docker push $DOCKER_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
echo "✓ Image poussée : $DOCKER_REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
```

### (Optionnel) Si le registry est privé — imagePullSecret

```bash
# À exécuter après création du namespace (Étape 3)
kubectl create secret docker-registry registry-credentials \
  --docker-server=ghcr.io \
  --docker-username=TON_GITHUB_USERNAME \
  --docker-password=$GITHUB_PAT \
  -n $K8S_NAMESPACE

# Puis décommenter dans values.yaml :
# imagePullSecrets:
# - name: registry-credentials
```

---

## Étape 3 — Configuration du Helm Chart

### 3.1 Mettre à jour le repository d'image

```bash
cd ~/capstone-dplc-student-gardais-cavanier

# Mettre à jour values.yaml avec le bon repository
sed -i "s|repository: \"\"|repository: \"$DOCKER_REGISTRY/$IMAGE_NAME\"|" \
  k8s/helm/worldcup-app/values.yaml

# Vérifier
grep "repository:" k8s/helm/worldcup-app/values.yaml
# Attendu : repository: "docker.io/username/worldcup-app"
```

### 3.2 (Optionnel) Configurer un domaine

Si tu as un domaine DNS pointant sur ce VPS, édite `k8s/helm/worldcup-app/values.yaml` :

```yaml
ingress:
  host: "worldcup.ton-domaine.com"
  tls:
    enabled: false   # passer à true après installation de cert-manager
```

---

## Étape 4 — Namespace et secret base de données

```bash
# Créer le namespace
kubectl create namespace $K8S_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Créer le secret DB (JAMAIS en clair dans le code)
kubectl create secret generic db-credentials \
  --from-literal=password="$DB_PASSWORD" \
  -n $K8S_NAMESPACE

# Vérifier
kubectl get secret db-credentials -n $K8S_NAMESPACE
echo "✓ Secret db-credentials créé dans namespace $K8S_NAMESPACE"
```

---

## Étape 5 — Stack de monitoring (Prometheus + Grafana)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorNamespaceSelector="{}" \
  --set grafana.adminPassword="admin123" \
  --set alertmanager.alertmanagerSpec.retention=24h \
  --timeout 10m \
  --wait

echo "=== Pods monitoring ===" && kubectl get pods -n monitoring
# Tous les pods doivent être "Running" (peut prendre 3-5 min)
```

---

## Étape 6 — Déploiement de l'application

```bash
cd ~/capstone-dplc-student-gardais-cavanier

helm install $HELM_RELEASE ./k8s/helm/worldcup-app \
  --namespace $K8S_NAMESPACE \
  --create-namespace \
  --wait \
  --timeout 5m

echo "=== Résultat ===" && kubectl get all -n $K8S_NAMESPACE
```

**Résultat attendu :**
- 2 pods `worldcup-app-xxx` → `Running`
- 1 pod `postgres-0` → `Running`
- 1 HPA `worldcup-app` → `2/2 replicas`
- 1 Ingress `worldcup-app`

---

## Étape 7 — Vérification complète

### 7.1 État des ressources

```bash
echo "=== Pods ===" && kubectl get pods -n $K8S_NAMESPACE
echo "=== Services ===" && kubectl get svc -n $K8S_NAMESPACE
echo "=== HPA ===" && kubectl get hpa -n $K8S_NAMESPACE
echo "=== Ingress ===" && kubectl get ingress -n $K8S_NAMESPACE
echo "=== PVC ===" && kubectl get pvc -n $K8S_NAMESPACE
```

### 7.2 Tests de santé HTTP

```bash
VPS_IP=$(hostname -I | awk '{print $1}')
echo "IP du VPS : $VPS_IP"

curl -sf http://$VPS_IP/api/health      && echo "✓ /api/health OK"
curl -sf http://$VPS_IP/api/health/db  && echo "✓ /api/health/db OK"
curl -sf http://$VPS_IP/api/teams | python3 -m json.tool | head -20
curl -sf http://$VPS_IP/api/groups | python3 -m json.tool | head -10
```

### 7.3 Vérifier les métriques Prometheus

```bash
curl -sf http://$VPS_IP/metrics | head -30
# Doit retourner des métriques prom-client (process_cpu_seconds_total, http_requests_total, etc.)
```

---

## Étape 8 — Accès au monitoring

### Grafana

```bash
VPS_IP=$(hostname -I | awk '{print $1}')

# Exposer Grafana sur le port 3001
kubectl port-forward -n monitoring svc/prometheus-grafana 3001:80 --address 0.0.0.0 &
echo "Grafana : http://$VPS_IP:3001  (admin / admin123)"
```

#### Dashboards à importer (Grafana → + → Import) :

| Dashboard | ID Grafana.com | Usage |
|-----------|---------------|-------|
| Node.js Application Metrics | `11159` | Métriques app (CPU, mémoire, requêtes) |
| Node Exporter Full | `1860` | Métriques système du VPS |
| Kubernetes Cluster Overview | `7249` | État du cluster k8s |

#### Requêtes PromQL utiles (Grafana → Explore → Prometheus) :

```promql
# Taux de requêtes HTTP/s
rate(http_requests_total[5m])

# Latence p95
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# CPU de l'app
rate(process_cpu_seconds_total{job="worldcup-app"}[5m]) * 100

# Pods en cours
kube_pod_status_phase{namespace="worldcup", phase="Running"}
```

### Prometheus UI

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 --address 0.0.0.0 &
echo "Prometheus : http://$VPS_IP:9090"
```

### Alertmanager

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093 --address 0.0.0.0 &
echo "Alertmanager : http://$VPS_IP:9093"
```

---

## Étape 9 — Tests de validation

### 9.1 Test de résilience (crash < 15s)

```bash
VPS_IP=$(hostname -I | awk '{print $1}')

echo "=== Avant le crash ==="
kubectl get pods -n $K8S_NAMESPACE | grep worldcup-app

echo "=== Déclenchement du crash ==="
curl -X POST http://$VPS_IP/api/admin/kill || true

echo "=== Surveillance du redémarrage (20s) ==="
for i in $(seq 1 20); do
  sleep 1
  STATUS=$(kubectl get pods -n $K8S_NAMESPACE --no-headers | grep worldcup-app | awk '{print $3}' | tr '\n' ' ')
  echo "t+${i}s : $STATUS"
done

echo "=== Vérification finale ==="
curl -sf http://$VPS_IP/api/health && echo "✓ App revenue en < 15s"
```

### 9.2 Test d'auto-scaling (HPA)

```bash
VPS_IP=$(hostname -I | awk '{print $1}')

echo "=== État HPA avant ==="
kubectl get hpa -n $K8S_NAMESPACE

echo "=== Génération de charge CPU (endpoint /api/compute) ==="
for i in $(seq 1 30); do curl -s http://$VPS_IP/api/compute & done
wait

echo "Attente de 60s pour que le HPA réagisse..."
sleep 60

echo "=== État HPA après ==="
kubectl get hpa -n $K8S_NAMESPACE
kubectl get pods -n $K8S_NAMESPACE | grep worldcup-app
# Attendu : plus de 2 réplicas si CPU > 70%
```

### 9.3 Test de haute disponibilité

```bash
echo "=== Suppression d'un pod (HA test) ==="
POD=$(kubectl get pods -n $K8S_NAMESPACE -l app.kubernetes.io/name=worldcup-app -o name | head -1)
echo "Suppression de : $POD"
kubectl delete $POD -n $K8S_NAMESPACE

sleep 5
kubectl get pods -n $K8S_NAMESPACE | grep worldcup-app
# Attendu : k8s recrée immédiatement un pod, toujours 2 Running
```

---

## (Optionnel) HTTPS avec cert-manager

```bash
# Installer cert-manager
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true --wait

# Créer un ClusterIssuer Let's Encrypt
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: gardaistheo@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: traefik
EOF

# Mettre à jour values.yaml puis :
# ingress:
#   host: "worldcup.ton-domaine.com"
#   tls:
#     enabled: true

helm upgrade $HELM_RELEASE ./k8s/helm/worldcup-app -n $K8S_NAMESPACE
```

---

## Dépannage

### Pod en CrashLoopBackOff

```bash
POD=$(kubectl get pods -n $K8S_NAMESPACE --no-headers | grep worldcup-app | awk 'NR==1{print $1}')
kubectl describe pod $POD -n $K8S_NAMESPACE | tail -30
kubectl logs $POD -n $K8S_NAMESPACE --previous
```

Causes fréquentes :
- **Secret manquant** : `kubectl get secret db-credentials -n $K8S_NAMESPACE` — refaire Étape 4
- **Image introuvable** : vérifier `app.image.repository` dans values.yaml et que l'image est bien pushée
- **PostgreSQL pas prêt** : `kubectl logs postgres-0 -n $K8S_NAMESPACE`

### Pod Pending

```bash
kubectl describe pod <pod-name> -n $K8S_NAMESPACE
# Regarder la section "Events:" en bas
kubectl get pvc -n $K8S_NAMESPACE
# Si Pending : vérifier que local-path provisioner tourne
kubectl get pods -n kube-system | grep local-path
```

### Ingress ne répond pas (port 80)

```bash
kubectl describe ingress -n $K8S_NAMESPACE
kubectl get svc -n kube-system | grep traefik
# Tester en direct via port-forward
kubectl port-forward svc/$HELM_RELEASE-worldcup-app 8080:3000 -n $K8S_NAMESPACE &
curl http://localhost:8080/api/health
```

### HPA ne scale pas

```bash
kubectl describe hpa -n $K8S_NAMESPACE
# metrics-server doit être actif (inclus dans k3s)
kubectl get pods -n kube-system | grep metrics-server
kubectl top pods -n $K8S_NAMESPACE
```

### ServiceMonitor non découvert par Prometheus

```bash
kubectl get servicemonitor -n $K8S_NAMESPACE
# Vérifier que le label "release" correspond au nom de la release Helm du monitoring
helm list -n monitoring
# Si la release s'appelle "kube-prometheus" et non "prometheus", corriger :
# helm upgrade $HELM_RELEASE ./k8s/helm/worldcup-app \
#   --set monitoring.prometheusRelease=kube-prometheus -n $K8S_NAMESPACE
```

---

## Commandes du quotidien

```bash
# État général
kubectl get all -n worldcup

# Logs en temps réel
kubectl logs -f -l app.kubernetes.io/name=worldcup-app -n worldcup

# Scaling manuel
kubectl scale deployment worldcup-app --replicas=3 -n worldcup

# Mise à jour de l'image (nouvelle version)
docker build -t $DOCKER_REGISTRY/$IMAGE_NAME:v2 ./app
docker push $DOCKER_REGISTRY/$IMAGE_NAME:v2
helm upgrade $HELM_RELEASE ./k8s/helm/worldcup-app \
  --set app.image.tag=v2 -n $K8S_NAMESPACE

# Rollback
helm rollback $HELM_RELEASE -n $K8S_NAMESPACE

# Désinstaller
helm uninstall $HELM_RELEASE -n $K8S_NAMESPACE
kubectl delete namespace $K8S_NAMESPACE
```

---

## Estimation des coûts

| Solution | Coût mensuel estimé |
|----------|-------------------|
| **VPS Ikoula (YNOV)** | **0 €/mois** (offert par l'école) |
| AWS EKS (2× t3.medium) + RDS + ALB | ~120 $/mois |
| GKE Autopilot + Cloud SQL | ~70 $/mois |
| Hetzner VPS CX21 (DIY k3s) | ~6 €/mois |

Le choix k3s sur VPS Ikoula permet une économie de **70-120 $/mois** vs cloud managé, au prix d'une gestion manuelle de l'infra (mises à jour k3s, backups PVC, monitoring des ressources système).
