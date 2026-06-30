#!/bin/bash

################################################################################
#                    CI/CD VPS DIAGNOSTIC SCRIPT
#                         Version 1.0 - 2026-06-30
#
# Exécutez ce script directement sur votre VPS :
# curl -fsSL https://your-url/vps-diagnostic.sh | bash
# ou
# bash vps-diagnostic.sh
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0
SKIPPED=0

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

print_skip() {
    echo -e "  ${GRAY}⊘${NC} $1"
    ((SKIPPED++))
}

print_code() {
    echo -e "  ${GRAY}$ $1${NC}"
}

print_summary() {
    local total=$((PASSED + FAILED + WARNINGS))
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Résultats: ${GREEN}${PASSED} ✓${NC} | ${RED}${FAILED} ✗${NC} | ${YELLOW}${WARNINGS} ⚠${NC} | ${GRAY}${SKIPPED} ⊘${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    if [ $FAILED -gt 0 ]; then
        return 1
    fi
    return 0
}

test_command() {
    local cmd="$1"
    local description="$2"
    local show_output="${3:-true}"

    if output=$(eval "$cmd" 2>&1); then
        print_pass "$description"
        if [ "$show_output" = "true" ] && [ -n "$output" ]; then
            print_info "$output"
        fi
        return 0
    else
        print_fail "$description"
        [ -n "$output" ] && print_info "Erreur: $output"
        return 1
    fi
}

test_file_exists() {
    local filepath="$1"
    local description="$2"

    if [ -f "$filepath" ]; then
        print_pass "$description"
        print_info "Chemin: $filepath"
        return 0
    else
        print_fail "$description: $filepath"
        return 1
    fi
}

test_dir_exists() {
    local dirpath="$1"
    local description="$2"

    if [ -d "$dirpath" ]; then
        print_pass "$description"
        print_info "Chemin: $dirpath"
        return 0
    else
        print_fail "$description: $dirpath"
        return 1
    fi
}

test_dir_writable() {
    local dirpath="$1"
    local description="$2"

    if [ -d "$dirpath" ] && [ -w "$dirpath" ]; then
        print_pass "$description"
        return 0
    else
        print_fail "$description: $dirpath"
        return 1
    fi
}

test_port_open() {
    local port="$1"
    local description="$2"

    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        print_pass "$description (port $port)"
        return 0
    else
        print_fail "$description (port $port fermé)"
        return 1
    fi
}

test_service_running() {
    local service="$1"
    local description="$2"

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        print_pass "$description"
        return 0
    else
        print_fail "$description"
        return 1
    fi
}

print_linux_info() {
    echo ""
    print_section "Informations système"
    if [ -f "/etc/os-release" ]; then
        os_name=$(grep "^NAME=" /etc/os-release | cut -d '"' -f 2)
        os_version=$(grep "^VERSION_ID=" /etc/os-release | cut -d '"' -f 2)
        print_info "OS: $os_name $os_version"
    fi
    print_info "Hostname: $(hostname)"
    print_info "IP: $(hostname -I | awk '{print $1}')"
    print_info "Uptime: $(uptime -p)"
}

################################################################################
# PHASE 1: SYSTEM INFO
################################################################################

print_header "PHASE 1: INFORMATIONS SYSTÈME"

print_section "Système d'exploitation"
test_command "uname -a" "Information système" true

print_linux_info

print_section "Utilisateur courant"
current_user=$(whoami)
print_info "Utilisateur: $current_user"

if [ "$current_user" = "root" ]; then
    print_warn "Script exécuté en tant que root - idéalement utiliser un utilisateur SSH standard"
fi

print_section "Répertoires essentiels"
test_dir_exists "/tmp" "Répertoire /tmp"
test_dir_writable "/tmp" "Répertoire /tmp accessible en écriture"

################################################################################
# PHASE 2: DOCKER
################################################################################

print_header "PHASE 2: DOCKER"

print_section "Installation Docker"

if test_command "docker --version" "Docker installé" true; then
    print_info ""
else
    print_fail "Docker n'est pas installé"
    print_info "Installation: curl -fsSL https://get.docker.com | sh"
fi

print_section "Service Docker"

if test_service_running "docker" "Service Docker en cours d'exécution"; then
    print_pass ""
else
    print_fail "Service Docker arrêté"
    print_code "sudo systemctl start docker"
    print_code "sudo systemctl enable docker"
fi

print_section "Accès Docker"

if docker ps &>/dev/null; then
    print_pass "Accès Docker sans sudo"
else
    print_warn "Accès Docker limité - vous êtes peut-être pas dans le groupe docker"
    print_code "sudo usermod -aG docker $USER"
    print_code "newgrp docker"
fi

print_section "Docker Daemon"

test_command "docker info --format 'Containers: {{.Containers}} | Images: {{.Images}}'" "Daemon Docker fonctionnel" true

print_section "Authentification Docker Hub"

docker_config="$HOME/.docker/config.json"
if [ -f "$docker_config" ]; then
    if grep -q "\"auths\"" "$docker_config"; then
        print_pass "Configuration Docker Hub trouvée"
        username=$(grep -o '"Username":"[^"]*' "$docker_config" | head -1 | cut -d '"' -f 4)
        if [ -n "$username" ]; then
            print_info "Utilisateur: $username"
        fi
    else
        print_warn "Configuration Docker Hub incomplète"
    fi
else
    print_warn "Configuration Docker non trouvée - pas encore connecté à Docker Hub"
    print_code "docker login"
fi

print_section "Connexion Docker Hub"

if docker pull alpine:latest &>/dev/null; then
    print_pass "Connexion à Docker Hub fonctionnelle"
    docker rmi alpine:latest &>/dev/null || true
else
    print_fail "Impossible de télécharger depuis Docker Hub"
    print_info "Vérifiez vos credentials: docker login"
fi

print_section "Images Docker existantes"

image_count=$(docker images --format "table" | wc -l)
print_info "Nombre d'images: $((image_count - 1))"
docker images --format "{{.Repository}}:{{.Tag}}" | head -5 | while read -r img; do
    print_info "  - $img"
done

################################################################################
# PHASE 3: KUBERNETES & K3S
################################################################################

print_header "PHASE 3: KUBERNETES & K3S"

print_section "Installation k3s"

if test_command "k3s --version" "k3s installé" true; then
    print_info ""
else
    print_fail "k3s n'est pas installé"
    print_info "Installation: curl -sfL https://get.k3s.io | sh -"
fi

print_section "Service k3s"

if test_service_running "k3s" "Service k3s en cours d'exécution"; then
    print_pass ""
else
    print_fail "Service k3s arrêté"
    print_code "sudo systemctl start k3s"
    print_code "sudo systemctl enable k3s"
fi

print_section "Installation kubectl"

if test_command "kubectl version --client --short" "kubectl installé" true; then
    print_info ""
else
    print_fail "kubectl n'est pas installé"
fi

print_section "Accès au cluster"

if kubectl cluster-info &>/dev/null; then
    print_pass "Cluster Kubernetes accessible"
else
    print_warn "Impossible d'accéder au cluster"
    print_info "Vérifiez KUBECONFIG"
fi

print_section "Nœuds du cluster"

if nodes=$(kubectl get nodes --no-headers 2>/dev/null); then
    node_count=$(echo "$nodes" | wc -l)
    print_pass "Accès aux nœuds ($node_count nœud(s))"
    echo "$nodes" | awk '{print "  - " $1 " (" $2 ")"}' | head -5 | while IFS= read -r line; do
        print_info "$line"
    done
else
    print_fail "Impossible de lister les nœuds"
fi

print_section "Namespaces"

if kubectl get namespaces &>/dev/null; then
    ns_count=$(kubectl get namespaces --no-headers | wc -l)
    print_pass "Namespaces accessibles ($ns_count)"

    if kubectl get namespace worldcup &>/dev/null; then
        print_pass "Namespace 'worldcup' existe"
        pod_count=$(kubectl get pods -n worldcup --no-headers 2>/dev/null | wc -l)
        print_info "  Pods: $pod_count"
    else
        print_info "Namespace 'worldcup' n'existe pas (sera créé au déploiement)"
    fi
else
    print_fail "Impossible de lister les namespaces"
fi

print_section "Services Kubernetes"

if kubectl get svc -A &>/dev/null; then
    svc_count=$(kubectl get svc -A --no-headers | wc -l)
    print_info "Services totaux: $svc_count"

    if kubectl get svc -n worldcup &>/dev/null 2>&1; then
        worldcup_svc=$(kubectl get svc -n worldcup --no-headers 2>/dev/null | wc -l)
        print_info "Services dans worldcup: $worldcup_svc"
    fi
else
    print_warn "Impossible de lister les services"
fi

################################################################################
# PHASE 4: HELM
################################################################################

print_header "PHASE 4: HELM"

print_section "Installation Helm"

if test_command "helm version --short" "Helm installé" true; then
    print_info ""
else
    print_fail "Helm n'est pas installé"
    print_info "Installation: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
fi

print_section "Helm Releases"

if helm list -A &>/dev/null; then
    release_count=$(helm list -A --no-headers | wc -l)
    print_info "Releases totales: $release_count"

    if helm list -n worldcup &>/dev/null; then
        worldcup_releases=$(helm list -n worldcup --no-headers 2>/dev/null | wc -l)
        print_info "Releases dans worldcup: $worldcup_releases"
        helm list -n worldcup --no-headers 2>/dev/null | awk '{print "  - " $1 " (v" $9 ")"}' | while IFS= read -r line; do
            print_info "$line"
        done
    else
        print_info "Aucun release dans le namespace worldcup"
    fi
else
    print_fail "Impossible de lister les releases Helm"
fi

################################################################################
# PHASE 5: KUBECONFIG
################################################################################

print_header "PHASE 5: KUBECONFIG"

print_section "Localisation kubeconfig"

kubeconfig_found=false

if [ -f "$HOME/.kube/config" ]; then
    test_file_exists "$HOME/.kube/config" "kubeconfig dans ~/.kube/config"
    kubeconfig_found=true
fi

if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
    test_file_exists "/etc/rancher/k3s/k3s.yaml" "kubeconfig dans /etc/rancher/k3s/k3s.yaml"
    kubeconfig_found=true
fi

if ! $kubeconfig_found; then
    print_fail "Aucun kubeconfig trouvé"
fi

print_section "Permissions kubeconfig"

if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
    perms=$(ls -l /etc/rancher/k3s/k3s.yaml | awk '{print $1}')
    print_info "Permissions /etc/rancher/k3s/k3s.yaml: $perms"

    if [ -r "/etc/rancher/k3s/k3s.yaml" ]; then
        print_pass "kubeconfig lisible"
    else
        print_warn "kubeconfig non lisible - peut nécessiter sudo"
    fi
fi

print_section "KUBECONFIG env var"

if [ -n "${KUBECONFIG:-}" ]; then
    print_pass "KUBECONFIG défini: $KUBECONFIG"
else
    print_info "KUBECONFIG non défini (utilisera ~/.kube/config ou /etc/rancher/k3s/k3s.yaml)"
fi

################################################################################
# PHASE 6: PERMISSIONS & SUDO
################################################################################

print_header "PHASE 6: PERMISSIONS & SUDO"

print_section "Utilisateur système"

print_info "Utilisateur: $(whoami)"
print_info "Groupe primaire: $(id -gn)"
print_info "Groupes: $(id -G | tr ' ' ',')"

print_section "Groupe docker"

if groups | grep -q docker; then
    print_pass "Utilisateur dans le groupe docker"
else
    print_warn "Utilisateur pas dans le groupe docker"
    print_code "sudo usermod -aG docker $USER"
fi

print_section "Accès sudo"

if sudo -n true &>/dev/null; then
    print_pass "Sudo accessible sans mot de passe"
else
    print_info "Sudo nécessite un mot de passe"
fi

print_section "Sudoers configuration"

if sudo -l 2>/dev/null | grep -q docker; then
    print_info "Docker configuré dans sudoers"
elif sudo -l 2>/dev/null | grep -q "ALL=(ALL)"; then
    print_info "Accès sudo complet (ALL=(ALL))"
else
    print_info "Sudoers configuration standard"
fi

################################################################################
# PHASE 7: PORTS & RÉSEAU
################################################################################

print_header "PHASE 7: PORTS & RÉSEAU"

print_section "Ports essentiels"

test_port_open "22" "SSH (port 22)"
test_port_open "80" "HTTP (port 80)"
test_port_open "443" "HTTPS (port 443)"
test_port_open "6443" "Kubernetes API (port 6443)"

print_section "Autres ports"

test_port_open "3000" "Port 3000"
test_port_open "5000" "Port 5000"

print_section "Réseau"

if command -v curl &>/dev/null; then
    print_info "curl disponible"
else
    print_warn "curl non disponible"
fi

if command -v wget &>/dev/null; then
    print_info "wget disponible"
else
    print_warn "wget non disponible"
fi

################################################################################
# PHASE 8: STOCKAGE & DISQUE
################################################################################

print_header "PHASE 8: STOCKAGE & DISQUE"

print_section "Espace disque"

df -h | grep -E "^/dev|Mounted on" | head -5 | while IFS= read -r line; do
    print_info "$line"
done

root_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$root_usage" -gt 80 ]; then
    print_warn "Espace disque faible sur / ($root_usage%)"
elif [ "$root_usage" -gt 90 ]; then
    print_fail "Espace disque critique sur / ($root_usage%)"
else
    print_pass "Espace disque OK ($root_usage%)"
fi

print_section "Espace Docker"

if docker info --format='{{.DockerRootDir}}' &>/dev/null; then
    docker_root=$(docker info --format='{{.DockerRootDir}}')
    docker_size=$(du -sh "$docker_root" 2>/dev/null | awk '{print $1}')
    print_info "Répertoire Docker: $docker_root"
    print_info "Taille: $docker_size"
fi

################################################################################
# PHASE 9: LOGS & DEBUGGING
################################################################################

print_header "PHASE 9: LOGS & DEBUGGING"

print_section "Logs Docker"

docker_logs=$(docker logs $(docker ps -q | head -1) 2>&1 | tail -5)
if [ -n "$docker_logs" ]; then
    print_info "Derniers logs Docker:"
    echo "$docker_logs" | while IFS= read -r line; do
        print_info "  $line"
    done
else
    print_info "Pas de conteneurs en cours d'exécution"
fi

print_section "Logs k3s"

if [ -f "/var/log/k3s.log" ]; then
    print_pass "Log k3s disponible"
    tail_logs=$(tail -3 /var/log/k3s.log)
    print_info "Dernières lignes:"
    echo "$tail_logs" | while IFS= read -r line; do
        print_info "  $line"
    done
else
    print_info "Log k3s non trouvé"
fi

print_section "Journal système"

if command -v journalctl &>/dev/null; then
    recent_errors=$(journalctl -n 5 --no-pager -p err 2>/dev/null || echo "N/A")
    print_info "Erreurs récentes:"
    echo "$recent_errors" | head -3 | while IFS= read -r line; do
        [ -n "$line" ] && print_info "  $line"
    done
else
    print_info "journalctl non disponible"
fi

################################################################################
# FINAL SUMMARY & RECOMMENDATIONS
################################################################################

print_header "RÉSUMÉ & RECOMMANDATIONS"

print_section "Résumé des vérifications"

if print_summary; then
    echo -e "  ${GREEN}✓ Tous les composants sont en place!${NC}"
else
    echo -e "  ${RED}✗ Des problèmes ont été détectés${NC}"
fi

print_section "Guide de correction"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo -e "  ${RED}Problèmes détectés à corriger:${NC}"
    echo ""
    echo "  Si Docker n'est pas installé:"
    print_code "sudo apt-get update && sudo apt-get install -y docker.io"
    echo ""
    echo "  Si k3s n'est pas installé:"
    print_code "curl -sfL https://get.k3s.io | sh -"
    echo ""
    echo "  Si Helm n'est pas installé:"
    print_code "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    echo ""
    echo "  Pour ajouter l'utilisateur au groupe docker:"
    print_code "sudo usermod -aG docker \$USER && newgrp docker"
    echo ""
    echo "  Pour démarrer les services:"
    print_code "sudo systemctl start docker k3s"
    echo ""
fi

print_section "Prochaines étapes"

echo ""
echo "  1. Corrigez les problèmes en rouge (s'il y en a)"
echo "  2. Relancez ce script pour vérifier"
echo "  3. Une fois OK, l'équipe GitHub Actions pourra déployer"
echo ""
echo "  Pour surveiller les déploiements:"
print_code "kubectl get pods -n worldcup -w"
echo ""
echo "  Pour voir les logs d'un pod:"
print_code "kubectl logs -n worldcup -f deployment/worldcup-app"
echo ""

print_section "Contact & Support"

echo ""
echo "  En cas d'erreur, vérifiez:"
echo "  1. https://docs.k3s.io"
echo "  2. https://helm.sh/docs"
echo "  3. https://docs.docker.com"
echo ""
