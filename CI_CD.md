# Pipeline CI/CD

## Objectif

La pipeline GitHub Actions automatise le deploiement de l'application sur le VPS k3s.

Elle fait trois choses :

1. lancer les tests Node.js ;
2. builder et pousser l'image Docker sur Docker Hub ;
3. deployer le chart Helm sur le cluster k3s via SSH.

## Declenchement

Le workflow `.github/workflows/ci-cd.yml` se lance :

- sur pull request vers `main` ou `mission/deployer-sur-le-cloud` : tests uniquement ;
- sur push vers `mission/deployer-sur-le-cloud` : tests, build image, push Docker Hub, deploy VPS ;
- manuellement avec `workflow_dispatch`.

## Secrets GitHub requis

Dans GitHub : `Settings` -> `Secrets and variables` -> `Actions`.

Secrets a creer :

```text
DOCKERHUB_USERNAME=theoga
DOCKERHUB_TOKEN=<token Docker Hub>
SSH_HOST=178.170.25.235
SSH_PORT=22
SSH_USER=root
SSH_PRIVATE_KEY=<cle privee SSH autorisee sur le VPS>
```

Ne mets pas le mot de passe root du VPS dans GitHub Actions. C'est faisable avec des actions tierces, mais c'est une mauvaise idee. Une cle SSH dediee est plus propre et plus facile a supprimer apres la soutenance.

## Creation d'une cle de deploiement

Sur ta machine :

```bash
ssh-keygen -t ed25519 -C "github-actions-worldcup" -f ./github-actions-worldcup
```

Ajouter la cle publique sur le VPS :

```bash
ssh-copy-id -i ./github-actions-worldcup.pub root@178.170.25.235
```

Mettre le contenu de la cle privee dans le secret GitHub :

```bash
cat ./github-actions-worldcup
```

## Ce que fait le deploiement

Le job `deploy` :

- package le chart Helm local ;
- l'envoie sur le VPS dans `/tmp/worldcup-app-chart.tgz` ;
- execute `helm upgrade --install worldcup /tmp/worldcup-app-chart.tgz` ;
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
