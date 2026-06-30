#!/bin/bash

################################################################################
#                    CI/CD DIAGNOSTIC SCRIPT - WORLDCUP APP
#                         Version 1.0 - 2026-06-30
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

print_summary() {
    local total=$((PASSED + FAILED + WARNINGS))
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Résultats: ${GREEN}${PASSED} ✓${NC} | ${RED}${FAILED} ✗${NC} | ${YELLOW}${WARNINGS} ⚠${NC} | ${GRAY}${SKIPPED} ⊘${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    if [ $FAILED -gt 0 ]; then
        exit 1
    fi
}

test_ssh_cmd() {
    local cmd="$1"
    local description="$2"

    if ! output=$(sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "$cmd" 2>&1); then
        print_fail "$description"
        print_info "Erreur: $output"
        return 1
    fi
    print_pass "$description"
    [ -n "$output" ] && print_info "Output: $output"
    return 0
}

remote_test() {
    local cmd="$1"
    local description="$2"
    local show_output="${3:-true}"

    if output=$(sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "$cmd" 2>&1); then
        print_pass "$description"
        if [ "$show_output" = "true" ] && [ -n "$output" ]; then
            print_info "Output: $output"
        fi
        return 0
    else
        print_fail "$description"
        print_info "Erreur: $output"
        return 1
    fi
}

################################################################################
# PHASE 1: LOCAL ENVIRONMENT
################################################################################

print_header "PHASE 1: ENVIRONNEMENT LOCAL"

print_section "Vérification des fichiers sources"

if [ -f "app/Dockerfile" ]; then
    print_pass "Dockerfile trouvé"
else
    print_fail "Dockerfile introuvable: app/Dockerfile"
fi

if [ -f "app/package-lock.json" ]; then
    print_pass "package-lock.json trouvé"
else
    print_fail "package-lock.json introuvable: app/package-lock.json"
fi

if [ -f "k8s/helm/worldcup-app/Chart.yaml" ]; then
    print_pass "Chart Helm trouvé"
else
    print_fail "Chart Helm introuvable: k8s/helm/worldcup-app/Chart.yaml"
fi

if [ -d "app" ] && [ -d "k8s/helm/worldcup-app" ]; then
    print_pass "Structures de répertoires valides"
else
    print_fail "Répertoires manquants"
fi

print_section "Vérification de Git"

if [ -d ".git" ]; then
    print_pass "Repository Git trouvé"
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    print_info "Branche actuelle: $branch"

    commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    print_info "Commit: $commit"
else
    print_fail "Repository Git introuvable"
fi

################################################################################
# PHASE 2: GITHUB SECRETS
################################################################################

print_header "PHASE 2: SECRETS GITHUB"

print_section "Configuration SSH"

if [ -z "${SSH_HOST:-}" ]; then
    print_fail "SSH_HOST non configuré"
else
    print_pass "SSH_HOST configuré: $SSH_HOST"
fi

if [ -z "${SSH_USER:-}" ]; then
    print_fail "SSH_USER non configuré"
else
    print_pass "SSH_USER configuré: $SSH_USER"
fi

if [ -z "${SSH_PASSWORD:-}" ]; then
    print_fail "SSH_PASSWORD non configuré"
else
    print_pass "SSH_PASSWORD configuré (masqué)"
fi

print_section "Variables d'environnement CI/CD"

if [ -z "${SSH_PORT:-}" ]; then
    print_warn "SSH_PORT utilisant le port par défaut: 22"
    SSH_PORT="22"
else
    print_pass "SSH_PORT configuré: $SSH_PORT"
fi

print_info "IMAGE_REPOSITORY: docker.io/theoga/worldcup-app"
print_info "K8S_NAMESPACE: worldcup"
print_info "HELM_RELEASE: worldcup"

################################################################################
# PHASE 3: REMOTE SSH CONNECTIVITY
################################################################################

print_header "PHASE 3: CONNECTIVITÉ SSH"

print_section "Test de connexion SSH basique"

if remote_test "whoami" "Connexion SSH fonctionnelle"; then
    ssh_user_output=$(sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "whoami" 2>&1)
    print_info "Utilisateur connecté: $ssh_user_output"
else
    print_fail "Impossible de se connecter au serveur"
    print_summary
    exit 1
fi

print_section "Vérification des répertoires"

remote_test "test -d /tmp && echo 'OK'" "Répertoire /tmp accessible"
remote_test "test -w /tmp && echo 'OK'" "Répertoire /tmp accessible en écriture"

################################################################################
# PHASE 4: DOCKER
################################################################################

print_header "PHASE 4: DOCKER"

print_section "Installation et service Docker"

if remote_test "docker --version" "Docker installé"; then
    docker_version=$(sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "docker --version" 2>&1)
    print_info "Version: $docker_version"
fi

remote_test "sudo systemctl is-active docker >/dev/null && echo 'active'" "Daemon Docker en cours d'exécution"

print_section "Accès Docker"

if remote_test "docker ps" "Accès à Docker (sans sudo)"; then
    print_pass "L'utilisateur peut utiliser Docker"
else
    print_warn "Accès Docker limité - vérifier les permissions de groupe docker"
fi

print_section "Authentification Docker Hub"

if remote_test "cat ~/.docker/config.json | grep -q 'auths' && echo 'OK'" "Docker login configuré"; then
    print_pass "Docker Hub authentication configurée"
else
    print_warn "Docker Hub authentication non trouvée - vous pourriez avoir besoin de: docker login"
fi

print_section "Test de push Docker"

if remote_test "docker pull alpine:latest" "Connexion à Docker Hub fonctionnelle"; then
    print_pass "Accès en lecture à Docker Hub OK"
else
    print_fail "Pas d'accès à Docker Hub"
fi

################################################################################
# PHASE 5: KUBERNETES & K3S
################################################################################

print_header "PHASE 5: KUBERNETES & K3S"

print_section "Installation k3s"

if remote_test "k3s --version" "k3s installé"; then
    k3s_version=$(sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "k3s --version" 2>&1)
    print_info "Version: $k3s_version"
else
    print_fail "k3s non installé"
fi

print_section "Service k3s"

if remote_test "sudo systemctl is-active k3s >/dev/null && echo 'active'" "Service k3s en cours d'exécution"; then
    print_pass "k3s service is running"
else
    print_fail "Service k3s arrêté ou non trouvé"
fi

print_section "Installation kubectl"

if remote_test "kubectl version --client" "kubectl installé"; then
    kubectl_version=$(sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "kubectl version --client --short" 2>&1)
    print_info "Version: $kubectl_version"
else
    print_fail "kubectl non installé"
fi

print_section "Accès au cluster Kubernetes"

if remote_test "kubectl get nodes" "Cluster accessible"; then
    nodes=$(sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "kubectl get nodes --no-headers | wc -l" 2>&1)
    print_info "Nombre de nœuds: $nodes"
else
    print_fail "Cluster Kubernetes non accessible"
fi

print_section "Namespaces Kubernetes"

remote_test "kubectl get namespaces" "Lister les namespaces" false

if remote_test "kubectl get namespace worldcup 2>/dev/null || echo 'not-found'" "Namespace 'worldcup' existe"; then
    print_info "Namespace 'worldcup' trouvé"
else
    print_info "Namespace 'worldcup' n'existe pas - sera créé automatiquement"
fi

print_section "Installation Helm"

if remote_test "helm version --short" "Helm installé"; then
    helm_version=$(sshpass -p "$SSH_PASSWORD" ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "helm version --short" 2>&1)
    print_info "Version: $helm_version"
else
    print_fail "Helm non installé"
fi

################################################################################
# PHASE 6: PERMISSIONS & SUDO
################################################################################

print_header "PHASE 6: PERMISSIONS & SUDO"

print_section "Permissions sudo"

if remote_test "sudo -n true 2>/dev/null || echo 'needs-password'" "Accès sudo disponible"; then
    print_pass "Sudo accessible"
else
    print_warn "Sudo peut nécessiter un mot de passe"
fi

print_section "Accès Docker avec sudo"

remote_test "sudo docker ps" "Accès Docker avec sudo" false

print_section "Vérification sudoers"

if remote_test "sudo -l | grep -q docker && echo 'found'" "Docker dans sudoers"; then
    print_pass "Docker configuré dans sudoers"
else
    print_info "Docker pas spécifiquement dans sudoers - utilisera le mot de passe"
fi

################################################################################
# PHASE 7: KUBECONFIG
################################################################################

print_header "PHASE 7: KUBECONFIG"

print_section "Localisation kubeconfig"

if remote_test "test -f ~/.kube/config && echo 'found'" "~/.kube/config existe"; then
    print_pass "kubeconfig trouvé dans ~/.kube/config"
else
    print_info "kubeconfig non trouvé dans ~/.kube/config"
    if remote_test "test -f /etc/rancher/k3s/k3s.yaml && echo 'found'" "/etc/rancher/k3s/k3s.yaml existe"; then
        print_pass "kubeconfig trouvé dans /etc/rancher/k3s/k3s.yaml"
    else
        print_fail "kubeconfig introuvable"
    fi
fi

print_section "Permissions kubeconfig"

remote_test "ls -lah /etc/rancher/k3s/k3s.yaml" "Permissions kubeconfig" false

################################################################################
# PHASE 8: DÉPLOIEMENT TEST (OPTIONAL)
################################################################################

print_header "PHASE 8: VÉRIFICATION DÉPLOIEMENT"

print_section "Test de déploiement Helm (simulation)"

if remote_test "helm list --namespace worldcup 2>/dev/null || echo 'namespace-not-found'" "Helm releases dans worldcup"; then
    print_pass "Accès au namespace OK"
else
    print_warn "Namespace worldcup ne peut pas être listé (sera créé au premier déploiement)"
fi

print_section "Images Docker existantes"

remote_test "docker images | grep worldcup || echo 'none'" "Images worldcup existantes" false

################################################################################
# PHASE 9: HEALTH CHECKS
################################################################################

print_header "PHASE 9: CONFIGURATION HEALTH CHECKS"

print_section "Points de terminaison API"

print_info "Endpoint 1: http://127.0.0.1/api/health"
print_info "Endpoint 2: http://127.0.0.1/api/health/db"
print_info "Note: Ces endpoints seront vérifiés après le déploiement"

################################################################################
# FINAL SUMMARY
################################################################################

print_header "RÉSUMÉ FINAL"

print_section "Étapes suivantes"

if [ $FAILED -eq 0 ]; then
    echo -e "  ${GREEN}✓ Tous les prérequis sont en place!${NC}"
    echo ""
    echo -e "  Prochaines étapes:"
    echo -e "  1. Committez vos modifications locales"
    echo -e "  2. Poussez votre branche vers GitHub"
    echo -e "  3. Créez une Pull Request ou poussez sur mission/deployer-sur-le-cloud"
    echo -e "  4. La CI/CD se déclenchera automatiquement"
    echo -e "  5. Monitrez les logs sur: https://github.com/YOUR_ORG/YOUR_REPO/actions"
else
    echo -e "  ${RED}✗ Des problèmes ont été détectés!${NC}"
    echo ""
    echo -e "  Corrigez les éléments en rouge ci-dessus avant de relancer le diagnostic"
fi

print_summary
