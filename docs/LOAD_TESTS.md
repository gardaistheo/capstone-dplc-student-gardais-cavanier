# Live load tests

## Objectif

Ces scripts servent a refaire les tests de charge en direct pendant la soutenance.

Ils sont volontairement simples : `bash`, `curl`, et `kubectl` si tu veux afficher l'etat Kubernetes en meme temps. Pas besoin d'installer k6, Artillery ou JMeter au dernier moment.

## Test HTTP mixte

Ce test charge les routes publiques et les routes API en parallele :

```bash
TARGET_URL=http://178.170.25.235 \
DURATION_SECONDS=60 \
CONCURRENCY=30 \
./scripts/live-load-test.sh
```

Ce que tu dois montrer :

- le nombre de requetes augmente ;
- les erreurs restent a `0` ou tres bas ;
- les pods `worldcup-app` restent `Running` ;
- `/metrics` continue de repondre pendant la charge.

## Test CPU pour HPA

Ce test tape `/api/compute`, l'endpoint fait expres pour consommer du CPU et declencher l'autoscaling.

```bash
TARGET_URL=http://178.170.25.235 \
DURATION_SECONDS=180 \
CONCURRENCY=40 \
./scripts/hpa-scale-test.sh
```

Ce que tu dois montrer :

- `kubectl get hpa -n worldcup` affiche une hausse du CPU ;
- le nombre de replicas passe au-dessus de `2` si la charge dure assez longtemps ;
- les nouveaux pods deviennent `Running` ;
- l'application continue a repondre.

Si le HPA ne scale pas instantanement, ce n'est pas forcement un bug : Kubernetes agregge les metriques avec un delai. Il faut tenir la charge 2 a 3 minutes pour une demo honnete.

## Commandes utiles pendant la demo

```bash
kubectl get hpa -n worldcup -w
kubectl get pods -n worldcup -l app.kubernetes.io/name=worldcup-app -w
kubectl top pods -n worldcup
curl -sf http://178.170.25.235/api/health/db
curl -sf http://178.170.25.235/metrics | head
```

## Remise a zero apres un test HPA

Le HPA redescend tout seul, mais pas immediatement. Pour forcer le retour a 2 replicas avant une nouvelle demo :

```bash
kubectl scale deployment worldcup-app --replicas=2 -n worldcup
kubectl get pods -n worldcup
```

Ne mens pas en soutenance : si tu forces le scale-down, dis-le. Le scale-up est le comportement important a demontrer.
