#!/bin/bash

################################################################################
#                    CI/CD VPS DIAGNOSTIC SCRIPT v2
#                         Version 2.0 - 2026-06-30
#
# Script de diagnostic robuste pour VPS
################################################################################

# Désactiver l'arrêt sur erreur pour les tests individuels
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

################################################################################
# UTILITY FUNCTIONS
################################################################################

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo -e "\n${YELLOW}▶ $1${NC}"
}

print_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAILED++))
}

print_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

print_info() {
    echo -e "  ${GRAY}ℹ${NC} $1"
}

print_code() {
    echo -e "  ${GRAY}$ $1${NC}"
}

################################################################################
# PHASE 1: SYSTEM INFO
################################################################################

print_header "PHASE 1: INFORMATIONS SYSTÈME"

print_section "Information de base"

print_info "Hostname: $(hostname 2>/dev/null || echo 'N/A')"
print_info "IP: $(hostname -I 2>/dev/null | awk '{print $1}' || echo 'N/A')"
print_info "Utilisateur: $(whoami 2>/dev/null || echo 'N/A')"

if [ -f "/etc/os-release" ]; then
    os_name=$(grep "^NAME=" /etc/os-release 2>/dev/null | cut -d '"' -f 2)
    print_info "OS: $os_name"
fi

uptime_output=$(uptime -p 2>/dev/null || uptime | awk -F'up' '{print $2}' | cut -d',' -f1)
print_info "Uptime: $uptime_output"

print_section "Espace disque"

disk_ok=true
df -h 2>/dev/null | tail -n +2 | while read -r line; do
    usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
    mount=$(echo "$line" | awk '{print $NF}')

    if [ -z "$usage" ] || ! [[ "$usage" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    if [ "$usage" -ge 90 ]; then
        print_fail "Disque critique sur $mount ($usage%)"
    elif [ "$usage" -ge 80 ]; then
        print_warn "Disque faible sur $mount ($usage%)"
    else
        print_pass "Espace OK sur $mount ($usage%)"
    fi
done

################################################################################
# PHASE 2: DOCKER
################################################################################

print_header "PHASE 2: DOCKER"

print_section "Installation et service"

if command -v docker &>/dev/null; then
    docker_version=$(docker --version 2>/dev/null)
    print_pass "Docker installé: $docker_version"
else
    print_fail "Docker n'est pas installé"
    print_code "sudo apt-get install -y docker.io"
fi

if systemctl is-active --quiet docker 2>/dev/null; then
    print_pass "Service Docker en cours d'exécution"
else
    print_fail "Service Docker arrêté"
    print_code "sudo systemctl start docker"
fi

print_section "Accès Docker"

if docker ps &>/dev/null; then
    print_pass "Accès Docker sans sudo"
    container_count=$(docker ps -q 2>/dev/null | wc -l)
    print_info "Conteneurs en cours: $container_count"
else
    print_warn "Accès Docker limité (nécessite sudo)"
    print_code "sudo usermod -aG docker $USER"
fi

print_section "Docker Hub authentification"

if [ -f "$HOME/.docker/config.json" ]; then
    if grep -q '"auths"' "$HOME/.docker/config.json" 2>/dev/null; then
        print_pass "Configuration Docker Hub trouvée"
    else
        print_warn "Configuration Docker Hub incomplète"
        print_code "docker login"
    fi
else
    print_warn "Docker Hub non configuré"
    print_code "docker login"
fi

if docker pull alpine:latest &>/dev/null 2>&1; then
    print_pass "Connexion Docker Hub fonctionnelle"
    docker rmi alpine:latest &>/dev/null 2>&1 || true
else
    print_fail "Impossible de télécharger depuis Docker Hub"
fi

print_section "Images Docker"

image_count=$(docker images --format "table" 2>/dev/null | wc -l)
print_info "Nombre d'images: $((image_count - 1))"

################################################################################
# PHASE 3: KUBERNETES & K3S
################################################################################

print_header "PHASE 3: KUBERNETES & K3S"

print_section "Installation k3s"

if command -v k3s &>/dev/null; then
    k3s_version=$(k3s --version 2>/dev/null)
    print_pass "k3s installé: $k3s_version"
else
    print_fail "k3s n'est pas installé"
    print_code "curl -sfL https://get.k3s.io | sh -"
fi

print_section "Service k3s"

if systemctl is-active --quiet k3s 2>/dev/null; then
    print_pass "Service k3s en cours d'exécution"
else
    print_fail "Service k3s arrêté"
    print_code "sudo systemctl start k3s"
fi

print_section "Installation kubectl"

if command -v kubectl &>/dev/null; then
    kubectl_version=$(kubectl version --client --short 2>/dev/null)
    print_pass "kubectl installé: $kubectl_version"
else
    print_fail "kubectl n'est pas installé"
fi

print_section "Accès au cluster"

if kubectl cluster-info &>/dev/null 2>&1; then
    print_pass "Cluster Kubernetes accessible"

    node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    print_info "Nombre de nœuds: $node_count"

    nodes=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $1, $2}' | head -5)
    if [ -n "$nodes" ]; then
        while IFS= read -r node_line; do
            print_info "  - $node_line"
        done <<< "$nodes"
    fi
else
    print_fail "Cluster Kubernetes non accessible"
fi

print_section "Namespaces"

if kubectl get namespaces &>/dev/null 2>&1; then
    ns_count=$(kubectl get namespaces --no-headers 2>/dev/null | wc -l)
    print_info "Namespaces: $ns_count"

    if kubectl get namespace worldcup &>/dev/null 2>&1; then
        print_pass "Namespace 'worldcup' existe"
        pod_count=$(kubectl get pods -n worldcup --no-headers 2>/dev/null | wc -l)
        print_info "  Pods: $pod_count"

        if [ "$pod_count" -gt 0 ]; then
            kubectl get pods -n worldcup --no-headers 2>/dev/null | head -3 | while read -r pod_line; do
                pod_name=$(echo "$pod_line" | awk '{print $1}')
                pod_status=$(echo "$pod_line" | awk '{print $3}')
                print_info "    - $pod_name ($pod_status)"
            done
        fi
    else
        print_info "Namespace 'worldcup' n'existe pas (créé au déploiement)"
    fi
else
    print_fail "Impossible de lister les namespaces"
fi

################################################################################
# PHASE 4: HELM
################################################################################

print_header "PHASE 4: HELM"

print_section "Installation Helm"

if command -v helm &>/dev/null; then
    helm_version=$(helm version --short 2>/dev/null)
    print_pass "Helm installé: $helm_version"
else
    print_fail "Helm n'est pas installé"
    print_code "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
fi

print_section "Helm releases"

if helm list -A &>/dev/null 2>&1; then
    release_count=$(helm list -A --no-headers 2>/dev/null | wc -l)
    print_info "Releases totales: $release_count"

    worldcup_releases=$(helm list -n worldcup --no-headers 2>/dev/null | wc -l)
    if [ "$worldcup_releases" -gt 0 ]; then
        print_info "Releases dans worldcup: $worldcup_releases"
        helm list -n worldcup --no-headers 2>/dev/null | while read -r release; do
            release_name=$(echo "$release" | awk '{print $1}')
            release_status=$(echo "$release" | awk '{print $8}')
            print_info "  - $release_name ($release_status)"
        done
    else
        print_info "Aucune release dans worldcup"
    fi
else
    print_fail "Impossible de lister les releases Helm"
fi

################################################################################
# PHASE 5: KUBECONFIG
################################################################################

print_header "PHASE 5: KUBECONFIG"

print_section "Localisation"

if [ -f "$HOME/.kube/config" ]; then
    print_pass "kubeconfig trouvé dans ~/.kube/config"
    perms=$(ls -l "$HOME/.kube/config" 2>/dev/null | awk '{print $1}')
    print_info "Permissions: $perms"
elif [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
    print_pass "kubeconfig trouvé dans /etc/rancher/k3s/k3s.yaml"
    perms=$(ls -l /etc/rancher/k3s/k3s.yaml 2>/dev/null | awk '{print $1}')
    print_info "Permissions: $perms"
else
    print_fail "kubeconfig introuvable"
fi

if [ -n "${KUBECONFIG:-}" ]; then
    print_info "KUBECONFIG défini: $KUBECONFIG"
else
    print_info "KUBECONFIG non défini (auto-détection)"
fi

################################################################################
# PHASE 6: PERMISSIONS
################################################################################

print_header "PHASE 6: PERMISSIONS & SUDO"

print_section "Utilisateur"

print_info "Utilisateur: $(whoami)"
print_info "Groupes: $(id -G | tr ' ' ',')"

if id -G | grep -q docker; then
    print_pass "Utilisateur dans le groupe docker"
else
    print_warn "Utilisateur pas dans le groupe docker"
    print_code "sudo usermod -aG docker $USER && newgrp docker"
fi

print_section "Accès sudo"

if sudo -n true 2>/dev/null; then
    print_pass "Sudo sans mot de passe"
else
    print_info "Sudo nécessite un mot de passe"
fi

################################################################################
# PHASE 7: PORTS
################################################################################

print_header "PHASE 7: PORTS & RÉSEAU"

print_section "Ports essentiels"

for port in 22 80 443 6443; do
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        print_pass "Port $port OUVERT"
    else
        print_fail "Port $port FERMÉ"
    fi
done

################################################################################
# PHASE 8: LOGS & DEBUGGING
################################################################################

print_header "PHASE 8: LOGS & DEBUGGING"

print_section "Logs k3s"

if [ -f "/var/log/k3s.log" ]; then
    print_pass "Log k3s disponible"
    tail_errors=$(grep -i "error\|fail" /var/log/k3s.log 2>/dev/null | tail -3)
    if [ -n "$tail_errors" ]; then
        print_warn "Erreurs récentes:"
        echo "$tail_errors" | while read -r line; do
            print_info "  $line"
        done
    fi
else
    print_info "Log k3s non trouvé"
fi

print_section "Logs Docker"

running_containers=$(docker ps -q 2>/dev/null | head -1)
if [ -n "$running_containers" ]; then
    print_info "Logs du dernier conteneur:"
    docker logs "$running_containers" 2>/dev/null | tail -3 | while read -r line; do
        print_info "  $line"
    done
else
    print_info "Aucun conteneur en cours d'exécution"
fi

print_section "Erreurs système"

if command -v journalctl &>/dev/null; then
    errors=$(journalctl -n 3 --no-pager -p err 2>/dev/null)
    if [ -n "$errors" ]; then
        print_warn "Erreurs système récentes:"
        echo "$errors" | while read -r line; do
            print_info "  $line"
        done
    fi
fi

################################################################################
# FINAL SUMMARY
################################################################################

print_header "RÉSUMÉ & RECOMMANDATIONS"

echo -e "\n  Résultats: ${GREEN}${PASSED} ✓${NC} | ${RED}${FAILED} ✗${NC} | ${YELLOW}${WARNINGS} ⚠${NC}\n"

if [ $FAILED -eq 0 ]; then
    echo -e "  ${GREEN}✓ Tous les composants essentiels sont en place!${NC}\n"
else
    echo -e "  ${RED}✗ Des composants manquent ou ne fonctionnent pas.${NC}\n"
    echo "  Veuillez corriger les éléments en rouge ci-dessus.\n"
fi

print_section "Commandes utiles"

echo ""
echo "  Vérifier le statut du cluster:"
print_code "kubectl get nodes"
echo ""
echo "  Voir les pods du namespace worldcup:"
print_code "kubectl get pods -n worldcup"
echo ""
echo "  Afficher les logs d'un déploiement:"
print_code "kubectl logs -n worldcup -f deployment/worldcup-app"
echo ""
echo "  Redémarrer les services:"
print_code "sudo systemctl restart docker k3s"
echo ""

print_header "FIN DU DIAGNOSTIC"
