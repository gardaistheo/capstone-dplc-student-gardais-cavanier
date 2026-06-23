# 📘 Guide de Déploiement — Étudiants

## Prérequis

Avant de commencer, assurez-vous d'avoir installé sur votre machine :

- **Docker** (>= 20.x) et **Docker Compose** (>= 2.x)
- **Git**
- Un terminal bash (Linux/macOS natif, ou WSL2 sous Windows)

---

## 1. Récupérer le projet

```bash
git clone <url-du-depot>
cd capstone-dplc
```

---

## 2. Lancer l'application en local

```bash
docker-compose up --build
```

Cela démarre deux services :

| Service | Image | Port exposé |
|---------|-------|-------------|
| `app` | Construite depuis `app/Dockerfile` | `3000` (hôte) |
| `db` | `postgres:15` | `5432` (interne) |

Au premier démarrage, le fichier `app/init.sql` est automatiquement exécuté par PostgreSQL (monté dans `/docker-entrypoint-initdb.d/`). Il crée les tables et insère les 48 équipes + matchs de la Coupe du Monde 2026.

---

## 3. Vérifier que tout fonctionne

```bash
# Health check de l'application
curl http://localhost:3000/
# Réponse attendue : {"status":"ok"}

# Health check de la base de données
curl http://localhost:3000/api/health/db
# Réponse attendue : {"status":"ok"}

# Métriques Prometheus
curl http://localhost:3000/metrics
```

---

## 4. Les routes de l'application

| Route | Méthode | Description |
|-------|---------|-------------|
| `/` | GET | Health check applicatif — retourne `{"status": "ok"}` |
| `/api/compute` | GET | Calcul CPU intensif (2-3s) — simule une charge lourde |
| `/api/health/db` | GET | Vérifie la connexion PostgreSQL |
| `/api/data` | POST | Insère un résultat de match en base |
| `/api/admin/kill` | POST | **Crash volontaire** — arrête le processus (`process.exit(1)`) |
| `/metrics` | GET | Métriques Prometheus (compteurs, histogrammes, CPU, mémoire) |
| `/api/vote` | POST | Voter pour une équipe (pronostic vainqueur) |
| `/api/votes/results` | GET | Résultats des votes en pourcentage |

### Exemples de requêtes

```bash
# Insérer un résultat de match
curl -X POST http://localhost:3000/api/data \
  -H "Content-Type: application/json" \
  -d '{"team_home":"France","team_away":"Brazil","score_home":2,"score_away":1,"stage":"Group Stage","date":"2026-06-20"}'

# Voter pour une équipe (team_id entre 1 et 48)
curl -X POST http://localhost:3000/api/vote \
  -H "Content-Type: application/json" \
  -d '{"team_id": 33}'

# Voir les résultats
curl http://localhost:3000/api/votes/results

# Provoquer un crash (pour tester le self-healing)
curl -X POST http://localhost:3000/api/admin/kill
```

---

## 5. Variables d'environnement

L'application attend les variables suivantes (définies dans `docker-compose.yml`) :

| Variable | Description | Valeur par défaut |
|----------|-------------|-------------------|
| `DB_HOST` | Hôte PostgreSQL | `db` |
| `DB_PORT` | Port PostgreSQL | `5432` |
| `DB_USER` | Utilisateur | `postgres` |
| `DB_PASSWORD` | Mot de passe | `postgres` |
| `DB_NAME` | Nom de la base | `worldcup2026` |

---

## 6. Ce que vous devez faire (vos missions)

### 6.1 Optimiser le Dockerfile

Le Dockerfile actuel contient **volontairement** des anti-patterns. Analysez-le et identifiez ce qui ne va pas.

Votre version optimisée doit suivre les bonnes pratiques professionnelles de conteneurisation :

- **Légèreté** — Réduire la taille de l'image au minimum nécessaire
- **Sécurité** — Ne pas exécuter l'application en tant que superutilisateur
- **Performance de build** — Exploiter le cache Docker intelligemment
- **Hygiène** — Ne pas embarquer de fichiers inutiles dans l'image

Appuyez-vous sur la documentation officielle Docker et les guides de bonnes pratiques Node.js pour construire une image de production professionnelle.
- **Observable** — métriques et logs centralisés

### 6.3 Contruiser un Job 

Concevez un Job (K8s Job/CronJob ou AWS Batch/Lambda) qui :

- Lit les données sportives depuis la base PostgreSQL
- Effectue un traitement de votre choix (classement, stats, prédictions, rapport PDF…)
- S'exécute de manière automatique ou planifiée

---

## 7. Structure du projet

```
capstone-dplc/
├── app/
│   ├── main.js              # Application Express (monolithe)
│   ├── package.json         # Dépendances Node.js
│   ├── init.sql             # Script d'initialisation de la BDD
│   ├── Dockerfile           # Dockerfile (à optimiser !)
│   └── tests/               # Tests property-based
├── docs/
│   └── GUIDE-ETUDIANT.md   # Ce guide
├── docker-compose.yml       # Orchestration locale
├── .gitignore
└── README.md                # Présentation du projet
```

---

## 8. Conseils

- **Testez en local** avant de déployer. `docker-compose up` doit fonctionner parfaitement.
- **Ne modifiez pas** les routes de l'application — l'enseignant les utilise pour les tests automatisés.
- **Documentez votre architecture** avec un schéma clair (Draw.io, Mermaid, Excalidraw…).
- **Préparez votre URL publique** — c'est la première chose que l'enseignant testera.
- Le endpoint `/metrics` est votre meilleur ami pour comprendre ce qui se passe sous charge.

---

## 9. Arrêter l'environnement local

```bash
docker-compose down

# Pour supprimer aussi les données PostgreSQL :
docker-compose down -v
```
