# Rapport séance 2 - team3

Service : `team3-fraud-api` (Cloud Run, `europe-west1`), déployé par Terraform.
Dépôt : <https://github.com/DeJongnick/ai-cloud-infra-terraform-student>

## Infrastructure

| Ressource Terraform | Rôle |
| --- | --- |
| `google_service_account.run` | compte d'exécution `team3-run` |
| `google_storage_bucket_iam_member.models_reader` | `roles/storage.objectViewer` sur `advanced-cloud-ai-models` |
| `google_project_iam_member.log_writer` | `roles/logging.logWriter` sur le projet |
| `google_cloud_run_v2_service.api` | service privé : port 8000, 1 vCPU, 1 Gio, 0 à 3 instances, bucket monté sur `/mnt/models` |
| `google_cloud_run_v2_service_iam_member.invokers` | `roles/run.invoker` pour les 4 membres de l'équipe |

Le service tourne sous son propre compte `team3-run`, limité à deux droits, au lieu du compte
partagé `cloudai-runner` utilisé en partie A (qui a aussi `aiplatform.user`,
`artifactregistry.reader` et `monitoring.metricWriter`).

## Mesures

50 requêtes séquentielles sur `/health`, le 12 novembre 2026 à 17:42 (UTC+1).

| Mesure | Valeur |
| --- | --- |
| Latence p50 / p95 / p99 (console, côté serveur) | 5,1 ms / 9,7 ms / 85,5 ms |
| Latence p50 / p99 (`curl`, de bout en bout) | ≈ 54 ms / ≈ 130 ms |
| Latence de démarrage du conteneur | p50 11,0 s, p99 11,6 s |
| Nombre d'instances au pic | 2 |
| Débit | 0,83 requête/s, 100 % de réponses 2xx |

## Analyse

- **Le traitement est rapide, le réseau domine.** Côté serveur, le p50 est de 5 ms ; vu du client,
  il est de 54 ms. Environ 50 ms viennent donc du réseau (Paris ↔ Belgique), du TLS et du
  frontal Google.
- **Le p99 est 17 fois le p50.** Avec 50 requêtes, le p99 correspond à la pire requête : la
  première sur une instance qui venait de démarrer. Côté client, elle a pris 145 ms, contre
  environ 55 ms pour les suivantes.
- **Le démarrage à froid prend environ 11 s** : récupération de l'image (237 Mo), lancement de
  Python, chargement du modèle XGBoost et lecture des fichiers parquet à travers le montage du
  bucket. Avec `min_instance_count = 0`, le premier utilisateur après une période sans trafic
  attend ce délai. `min_instance_count = 1` le supprimerait, au prix d'une instance facturée en
  permanence.
- **Le pic à 2 instances vient de la bascule de révision**, pas de la charge : les requêtes
  étaient envoyées une par une, et une instance en accepte 80 simultanément. L'instance de
  l'ancienne révision était encore active pendant que la nouvelle prenait le trafic.

## Modifications et révisions

| Révision | Changement | Résultat du `plan` |
| --- | --- | --- |
| `team3-fraud-api-00001-htb` | création | 8 à créer |
| `team3-fraud-api-00002-7m4` | mémoire 1 Gio → 2 Gio | 1 à modifier sur place |
| `team3-fraud-api-00003-sct` | mémoire 2 Gio → 1 Gio | 1 à modifier sur place |

Une modification de la mémoire ne touche qu'une ressource sur huit (le service) et la modifie
sur place (`~`) : l'URL et les droits sont conservés. Côté Cloud Run, chaque modification crée
une nouvelle révision immuable, qui reçoit 100 % du trafic ; les anciennes restent disponibles
pour un retour arrière.

## Partie A : déploiement à la main

- Une quinzaine de champs remplis dans la console. Une faute de frappe (un espace devant
  `WEB_CONCURRENCY`) est passée inaperçue au déploiement : la variable était ignorée sans
  erreur. Le même service en Terraform se relit, se versionne et se recrée à l'identique.
- Sans jeton, l'appel renvoie 403 : la requête est rejetée par le frontal Google (IAM) avant
  d'atteindre le conteneur. Avec un jeton d'identité et le rôle `roles/run.invoker`, le service
  répond.
