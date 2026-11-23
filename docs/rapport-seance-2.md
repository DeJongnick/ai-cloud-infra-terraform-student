# Rapport séance 2 - team3

Qui a fait quoi : Léo Bouchand (image, Terraform, mesures et rapport).

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

## Preuves relevées le 23 novembre 2026

Le service a été détruit en fin de séance 2, puis recréé par le même `infra/main.tf` le 12 novembre
pour la séance 3. Les noms de révision du tableau ci-dessus n'existent donc plus. Les preuves
ci-dessous portent sur le service recréé, tel qu'il tourne aujourd'hui.

**Image construite pour `linux/amd64`, dans le registre partagé.**

```text
$ docker buildx imagetools inspect europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/team3-fraud-api:v1
  Platform:    linux/amd64
  Platform:    unknown/unknown        # attestation de build, pas une seconde image
```

Les révisions `team3-fraud-api-00001-ptn` et `00002-797` (12 novembre, 17:45 et 18:06 UTC) ont tourné
sur cette image (`team3-fraud-api@sha256:d0a705e4…`). Depuis la séance 4, le service utilise l'image
de référence `ref-fraud-api:td4`, comme le demande l'énoncé de la séance 4.

**Terraform ne voit aucun écart après l'`apply`.**

```text
$ terraform plan
No changes. Your infrastructure matches the configuration.
```

**Service privé : 403 sans jeton, 200 avec.**

```text
$ curl -s -o /dev/null -w "%{http_code}\n" $URL/health
403
$ curl -s -w "\n%{http_code}\n" -H "Authorization: Bearer $(gcloud auth print-identity-token)" $URL/health
{"status":"ok","pid":1,"features":20,"source":"firestore","database":"team3","rss_mb":172.5}
200
```

**Moindre privilège.** Personne n'a de droit `allUsers` ou `allAuthenticatedUsers`, ni sur le service
ni sur le projet. `roles/run.invoker` sur `team3-fraud-api` est donné aux quatre membres de l'équipe
et à `team3-push` (séance 3). En séance 2, `team3-run` avait deux droits :
`roles/storage.objectViewer` sur le bucket des modèles et `roles/logging.logWriter`. Depuis la
partie C de la séance 4 (`infra/features.tf`), il a aussi `roles/bigquery.dataViewer` sur le dataset
`team3`, et `roles/bigquery.jobUser` et `roles/datastore.user` sur le projet. Ces trois droits lui
servent à lire les compteurs dans BigQuery et Firestore.
