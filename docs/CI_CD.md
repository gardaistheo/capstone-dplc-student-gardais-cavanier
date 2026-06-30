# Pipeline CI/CD

## Objectif

La pipeline GitHub Actions automatise le deploiement de l'application sur le VPS k3s.

Elle fait trois choses :

1. lancer les tests Node.js ;
2. envoyer les sources sur le VPS ;
3. builder/push l'image Docker depuis l'utilisateur `claude`, puis deployer le chart Helm sur k3s.

## Declenchement

Le workflow `.github/workflows/ci-cd.yml` se lance :

- sur pull request vers `main` ou `mission/deployer-sur-le-cloud` : tests uniquement ;
- sur push vers `mission/deployer-sur-le-cloud` : tests, build image, push Docker Hub, deploy VPS ;
- manuellement avec `workflow_dispatch`.

## Secrets GitHub requis

Les secrets utilises sont des **environment secrets** dans l'environnement GitHub `prod`.

Dans GitHub : `Settings` -> `Environments` -> `prod` -> `Environment secrets`.

Secrets requis :

```text
SSH_HOST=178.170.25.235
SSH_USER=claude
SSH_PASSWORD=<mot de passe SSH>
```

La connexion par cle privee etant desactivee, la pipeline utilise `sshpass` avec `SSH_PASSWORD`.

## Pre-requis sur la VM

Sur la VM, l'utilisateur `claude` doit deja avoir :

- acces a `sudo docker` ;
- une session Docker Hub deja connectee (`docker login`) ;
- acces a `kubectl` et `helm` ;
- un kubeconfig lisible, idealement `~/.kube/config`.

Verification rapide sur la VM :

```bash
ssh claude@178.170.25.235
sudo DOCKER_CONFIG=/home/claude/.docker docker info
sudo DOCKER_CONFIG=/home/claude/.docker docker push docker.io/theoga/worldcup-app:test-ci
kubectl get nodes
helm version
```

## Ce que fait le deploiement

Le job `deploy` :

- package `app/` et `k8s/helm/worldcup-app/` ;
- envoie l'archive sur le VPS avec SSH par mot de passe ;
- build l'image sur le VPS avec `sudo docker` ;
- push `docker.io/theoga/worldcup-app:<sha>` et `docker.io/theoga/worldcup-app:latest` avec le Docker config de `claude` ;
- execute `helm upgrade --install worldcup ./k8s/helm/worldcup-app` ;
- force l'image a utiliser le tag du commit GitHub ;
- attend le rollout Kubernetes ;
- verifie `/api/health` et `/api/health/db`.

## Verification apres pipeline

Sur le VPS :

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pods -n worldcup
kubectl get hpa -n worldcup
helm history worldcup -n worldcup
```

Depuis n'importe ou :

```bash
curl -sf http://178.170.25.235/api/health
curl -sf http://178.170.25.235/api/health/db
```

## Limite importante

Cette pipeline deploie sur un cluster k3s single-node. Donc oui, c'est une CI/CD fonctionnelle. Non, ce n'est pas une architecture zero-downtime multi-zone de production. Si on te challenge la-dessus, il faut le dire clairement.

Autre limite : le mot de passe SSH dans GitHub Actions marche pour une demo, mais ce n'est pas le top niveau securite. Pour un vrai projet, il faudrait retablir une cle SSH de deploiement limitee ou passer par un runner self-hosted sur la VM.
