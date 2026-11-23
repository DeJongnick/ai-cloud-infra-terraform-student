# Livraison continue — team3

Qui a fait quoi : Léo Bouchand.

Deux workflows GitHub Actions dans le dépôt applicatif
<https://github.com/DeJongnick/td2-fraud-api-albertschool>, branche `ci-livraison`. Ils s'authentifient
auprès du projet avec le compte `team3-cd`, par fédération d'identité, sans fichier de clé. Seul ce
dépôt est autorisé : `roles/iam.workloadIdentityUser` sur `team3-cd` pour
`attribute.repository/DeJongnick/td2-fraud-api-albertschool`.

| Workflow | Séance | Ce qu'il fait |
| --- | --- | --- |
| `.github/workflows/release.yml` | 6, extension « Livraison » | déploie une révision de `team3-scorer` sans trafic avec un tag, puis lance un test de fumée **bloquant** |
| `.github/workflows/deploy.yml` | 2, partie D | construit l'image, la pousse avec le hash du commit pour tag, déploie une révision de `team3-fraud-api` sans trafic, puis lance un test de fumée bloquant |

`workflow_dispatch` ne fonctionne que si le fichier est sur la branche par défaut. Pour ne pas toucher
à `main`, les deux workflows se déclenchent aussi sur un push sur `ci-livraison`. Dans ce cas,
`release.yml` lit ses paramètres (`TAG`, `MODEL`, `ENV`) dans `.github/release.conf`.

## Séance 6 — test de fumée bloquant (`release.yml`)

Le workflow fourni (`docs/seance-6/release.yml`) testait seulement `/health`, avec
`continue-on-error: true`. Or, pendant la panne de la séance 6, la version suivante répondait
`/health` 200 avec `status=ok` alors qu'elle ne savait pas scorer. Notre version retire donc
`continue-on-error` et teste deux choses sur l'adresse du tag, avec un jeton d'identité de
`team3-cd` (qui a `roles/run.invoker` sur `team3-scorer`) :

1. `/health` répond 200 avec `status=ok` ;
2. `POST /predict` sur une transaction répond 200 avec un score compris entre 0 et 1.

`/predict` n'écrit pas de ligne `scored` dans les logs : le test ne fausse pas `measure.py`.

**Échec volontaire.** Nous avons repris la version suivante de la séance 6 :
`ENV=MODELS_DIR=/mnt/models/td6/next-model MODEL_VERSION=next`, tag `smoke`, base `candidate`.
Exécution [45189954111](https://github.com/DeJongnick/td2-fraud-api-albertschool/actions/runs/45189954111),
commit `936b7e3`, en échec sur l'étape « Smoke test /health and /predict » :

```text
Révision : team3-scorer-smoke-1123140304
/health : HTTP 200
{"status":"ok",...,"revision":"team3-scorer-smoke-1123140304","model_version":"next",...}
/predict : HTTP 500
Internal Server Error
##[error]/predict renvoie 500 sur team3-scorer-smoke-1123140304 : la révision ne sait pas scorer
```

Le test aurait arrêté la panne de la séance 6 avant le palier à 10 %, alors que la détection
manuelle a pris 2 min 48 s après la mise en trafic. Un test sur `/health` seul l'aurait laissée
passer.

**Essai témoin.** Même workflow, avec le modèle de la révision en service (`ENV=` vide).
Exécution [45190412288](https://github.com/DeJongnick/td2-fraud-api-albertschool/actions/runs/45190412288),
commit `9d98c8a`, réussie :

```text
Révision : team3-scorer-smoke-1123140542
/health : HTTP 200
{"status":"ok",...,"model_version":"2",...}
/predict : HTTP 200
{"scores":[{"tx_id":"smoke-test","score":0.4994315505027771}],...}
Test de fumée réussi sur team3-scorer-smoke-1123140542
```

Les deux révisions ont été déployées avec `--no-traffic`. Le tag `smoke` a ensuite été retiré
(`gcloud run services update-traffic team3-scorer --remove-tags smoke`). Le trafic est revenu à son
état de départ :

```text
REVISION_NAME                      TAG        PERCENT
team3-scorer-candidate-1119195956  candidate  100
team3-scorer-prep-1119180441       champion
```

## Séance 2, partie D — déploiement continu (`deploy.yml`)

L'enseignant devait fournir un workflow, mais nous ne l'avons pas trouvé dans son dépôt. Nous
l'avons donc écrit à partir de `release.yml`. À chaque push, il fait ceci :

1. `docker build --platform linux/amd64`, puis push de
   `europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/team3-fraud-api:<hash du commit>` ;
2. `gcloud run deploy team3-fraud-api --no-traffic --tag livraison --revision-suffix cd-<hash court>` ;
3. un test de fumée bloquant : la révision est `Ready`, elle sert l'image construite, et `/health`
   sans jeton renvoie 403, donc le service est resté privé.

`team3-cd` n'a pas `roles/run.invoker` sur `team3-fraud-api` : seuls l'équipe et `team3-push`
l'appellent. Le test ne peut donc pas appeler le service avec un jeton. Pour un test fonctionnel, il
faudrait ajouter `team3-cd` à `var.invokers`.

Premier essai, [45190861041](https://github.com/DeJongnick/td2-fraud-api-albertschool/actions/runs/45190861041) :
l'image est construite et poussée, mais le déploiement échoue avec
`service.spec.traffic[1].tag: must be at least 3 characters long`, car le tag `cd` est trop court.
Le tag a été renommé en `livraison`. Second essai,
[45191209073](https://github.com/DeJongnick/td2-fraud-api-albertschool/actions/runs/45191209073),
commit `2c510da`, réussi :

```text
Révision : team3-fraud-api-cd-2c510da
Adresse du tag : https://livraison---team3-fraud-api-ueiaychpgq-ew.a.run.app
État de team3-fraud-api-cd-2c510da : Ready	True
Image servie : europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/team3-fraud-api@sha256:eeff1f9a…
/health sans jeton : HTTP 403
Test de fumée réussi sur team3-fraud-api-cd-2c510da
```

Avec un jeton de l'équipe, la nouvelle révision répond :

```text
$ curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" https://livraison---team3-fraud-api-ueiaychpgq-ew.a.run.app/health
{"status":"ok","pid":1,"features":20,"customers":49394,"terminals":4985,"last_day":"2026-09-30","rss_mb":326.2}
```

Le trafic reste sur la révision décrite par Terraform. C'est elle qui sert les mesures des
séances 3 et 4 (image `ref-fraud-api:td4`, source `firestore`) :

```text
REVISION_NAME               TAG        PERCENT
team3-fraud-api-00006-qtq              100
team3-fraud-api-cd-2c510da  livraison
```

### Ce que propose `terraform plan` après le déploiement continu, et pourquoi

```text
  # google_cloud_run_v2_service.api will be updated in-place
  ~ resource "google_cloud_run_v2_service" "api" {
      - client                  = "gcloud" -> null
      - client_version          = "591.0.0" -> null
      ~ template {
          - revision                         = "team3-fraud-api-cd-2c510da" -> null
          ~ containers {
              ~ image            = ".../team3-fraud-api:2c510da808cd..." -> ".../ref-fraud-api:td4"
```

Le gabarit du service (`template`) décrit la dernière révision créée, ici celle du workflow.
Terraform la compare à `infra/main.tf`, qui contient toujours `var.image`. Il propose donc de remettre
l'ancienne image et d'effacer le nom de révision et le client (`gcloud`) écrits par le workflow. Un
`terraform apply` aurait créé une nouvelle révision et annulé le déploiement continu. Inversement, le
déploiement suivant aurait encore créé un écart.

La correction se trouve dans `infra/main.tf`, avec un bloc `lifecycle` qui ignore seulement ce que
choisit le déploiement continu :

```hcl
  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].revision,
      template[0].containers[0].image,
    ]
  }
```

Le reste de la configuration reste à Terraform : compte d'exécution, ressources, scaling, volumes et
variables. Le trafic n'est pas déclaré dans `main.tf`, si bien que le tag `livraison` et la
répartition sans trafic ne créent pas d'écart. Après l'ajout du bloc :

```text
$ terraform plan -target=google_cloud_run_v2_service.api
No changes. Your infrastructure matches the configuration.
```

Limite : avec ce bloc, changer `var.image` dans `terraform.tfvars` n'a plus d'effet sur un service
existant. L'image ne se choisit plus que par le workflow, ou par `gcloud run deploy`.
