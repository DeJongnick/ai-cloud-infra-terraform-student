# Séance 6, après le TD — team3

Qui a fait quoi : Léo Bouchand (import du scorer, `release.tf`, alerte, test de l'ombre, ce document).

Relevé le 23 novembre 2026, vers 15 h (Europe/Paris). L'état du service après le TD ne tenait qu'à
des commandes tapées à la main. Il est maintenant décrit en Terraform.

| Ce qui était fait à la main | Fichier | Ce qui en a été fait |
| --- | --- | --- |
| Trafic, tags, modèle et variables de `team3-scorer` | `infra/scorer/main.tf`, `infra/scorer/scorer.tf` | `import` et `terraform plan` seulement, jamais `apply` |
| Abonnement d'ombre `team3-shadow` | `infra/release.tf` | `apply`, ombre désactivée par défaut |
| Règle d'alerte qui aurait détecté la panne | `infra/release.tf` | `apply` : règle `team3-scorer-release` créée |

## 1. Le service, décrit sans être appliqué

`infra/scorer/` a son propre état, local, sans bloc `backend`. Le service appartient au socle : on
n'y lance ni `apply` ni `destroy`. `scorer.tf` a été généré par
`terraform plan -generate-config-out=scorer.tf`, sans retouche, puis complété par
`lifecycle { prevent_destroy = true }`.

```text
$ terraform plan -no-color | tee ../../docs/seance-6/plan.txt
  # google_cloud_run_v2_service.scorer will be imported
Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
```

La sortie complète est dans [plan.txt](./plan.txt). Les adresses `creator` et `last_modifier` y
sont masquées. Après masquage, `grep '@'` ne renvoie que des comptes de service et des empreintes
d'image.

**Écart à connaître pour reconstruire le service.** Le bloc `template` décrit la dernière révision
créée, pas celle qui sert :

| Champ | Révision |
| --- | --- |
| `template.revision` | `team3-scorer-smoke-1123140542`, avec `MODELS_DIR=/mnt/models/runs/team3/models/20261118T185924Z6e84b7` et `MODEL_VERSION=2` |
| `traffic` à 100 % | `team3-scorer-candidate-1119195956` (tag `candidate`) |

Le premier plan, généré le 23 novembre avant le test de fumée de `release.yml`, montrait encore
`team3-scorer-next-1120132555` (`MODELS_DIR=/mnt/models/td6/next-model`, `MODEL_VERSION=next`) :
le gabarit courant était celui de la version défaillante de l'étape 4, et un déploiement parti de
ce gabarit aurait refait la panne. Le test de fumée a ensuite créé deux révisions `smoke`, sans
trafic : la dernière, avec le modèle version 2, est devenue le gabarit. `scorer.tf` et `plan.txt`
ont été régénérés après ce test, et le plan reste `1 to import, 0 to add, 0 to change, 0 to destroy`.
Le gabarit porte maintenant le même modèle que la révision servie, mais pas le même nom de
révision. Pour reconstruire le service tel qu'il sert, il faut reprendre les variables de la
révision `candidate`, pas celles du gabarit : le gabarit suit la dernière révision créée, quelle
qu'elle soit.

## 2. L'alerte

La règle `team3-scorer-release` est évaluée révision par révision de `team3-scorer`. Le projet n'a
pas de canal de notification : elle ouvre un incident dans **Monitoring → Alertes**, sans envoi.

| Choix | Valeur | Justification |
| --- | --- | --- |
| (1) Signal | `logging.googleapis.com/user/td6_failed`, `ALIGN_SUM`, `REDUCE_SUM`, groupé par `revision_name` | Seul signal qui a vu la panne : `next` n'a scoré aucune transaction, donc ni p95 ni taux d'alerte n'étaient calculables. L'âge du plus ancien message est resté à 26 s, sous notre seuil. |
| (2) Seuil | plus de 10 échecs par minute sur une révision | En temps normal, 0 échec : aucun `td6_failed` pour `candidate` ni `champion` pendant toute la séance. Pendant la panne, `next` en a compté 23 la première minute, puis 55 à 75 par minute. |
| (3) Durée | 60 s | Un échec isolé n'ouvre pas la règle ; une panne franche l'ouvre en deux minutes environ. |

Séries `td6_failed` par minute pour `team3-scorer-next-1120132555`, le 20 novembre (fin de minute,
heure de Paris), lues dans l'API Monitoring avec la même agrégation que la règle :

| 13:28 | 13:29 | 13:30 | 13:31 | 13:32 | 13:33 | 13:34 | 13:35 | 13:36 | 13:37 | 13:38 | 13:39 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 23 | 74 | 62 | 55 | 58 | 63 | 67 | 75 | 68 | 63 | 0 |

**Délai gagné, estimé.** `next` passe à 10 % à 13 h 28 min 43 s. La condition est vraie dès la
minute qui finit à 13 h 29 (23 échecs) et le reste ensuite. Après 60 s, la règle se serait ouverte
vers 13 h 30, plus le délai d'ingestion des métriques de logs, que nous n'avons pas mesuré. Notre
détection manuelle date de 13 h 31 min 31 s. Le gain est donc d'environ 1 min 30, moins ce délai
d'ingestion. C'est une estimation sur les séries enregistrées : la règle n'existait pas pendant la
panne, et elle n'a pas été déclenchée depuis.

```text
$ terraform apply -target=google_pubsub_subscription.shadow -target=google_monitoring_alert_policy.release
  # google_monitoring_alert_policy.release will be created
Plan: 1 to add, 0 to change, 0 to destroy.
google_monitoring_alert_policy.release: Creation complete after 12s [id=projects/advanced-cloud-ai/alertPolicies/13752530996358291967]
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

## 3. L'ombre

L'abonnement `google_pubsub_subscription.shadow` n'existe que si `shadow_tag` est renseigné. Il a
été créé une fois vers `candidate`, puis supprimé.

```text
$ terraform apply -var shadow_tag=candidate -target=google_pubsub_subscription.shadow -target=google_monitoring_alert_policy.release
  # google_pubsub_subscription.shadow[0] will be created
      + name                       = "team3-shadow"
          + push_endpoint = "https://candidate---team3-scorer-ueiaychpgq-ew.a.run.app/pubsub/shadow"
Plan: 1 to add, 0 to change, 0 to destroy.
google_pubsub_subscription.shadow[0]: Creation complete after 7s [id=projects/advanced-cloud-ai/subscriptions/team3-shadow]
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

$ gcloud pubsub subscriptions describe team3-shadow --format="value(name,pushConfig.pushEndpoint,pushConfig.oidcToken.serviceAccountEmail)"
projects/advanced-cloud-ai/subscriptions/team3-shadow  https://candidate---team3-scorer-ueiaychpgq-ew.a.run.app/pubsub/shadow  team3-scorer-push@advanced-cloud-ai.iam.gserviceaccount.com

$ gcloud logging read '... jsonPayload.message="scored" AND jsonPayload.shadow=true' --freshness 2m --limit 3
(aucune ligne)

$ terraform apply -target=google_pubsub_subscription.shadow -target=google_monitoring_alert_policy.release
  # google_pubsub_subscription.shadow[0] will be destroyed
Plan: 0 to add, 0 to change, 1 to destroy.
Apply complete! Resources: 0 added, 0 changed, 1 destroyed.
```

**Limite du test.** Aucune ligne `scored` d'ombre n'a été lue, car le flux `ff-td6` est arrêté : le
dernier message scoré par `team3-scorer` date du 20 novembre à 18 h 37 (Europe/Paris). Le test
prouve que Terraform crée l'abonnement vers la bonne adresse, avec le bon compte de poussée, puis le
supprime. Il ne prouve pas que les messages arrivent jusqu'à `/pubsub/shadow` : il faudrait relancer
le test pendant que le flux tourne. Nous n'avons rien publié dans `ff-td6`, qui appartient au socle
et qui est lu par toutes les équipes.

## 4. État final vérifié

```text
$ gcloud pubsub subscriptions list --filter 'name~team3-shadow' --format 'value(name)'
(aucune ligne)

$ gcloud run services describe team3-scorer --region europe-west1 --flatten 'status.traffic[]' \
    --format 'table(status.traffic.revisionName,status.traffic.tag,status.traffic.percent)'
REVISION_NAME                      TAG        PERCENT
team3-scorer-candidate-1119195956  candidate  100
team3-scorer-prep-1119180441       champion

$ terraform plan        # depuis infra/
No changes. Your infrastructure matches the configuration.
```

La règle `team3-scorer-release` est active (`enabled: true`, libellé `team: team3`) avec le filtre,
l'agrégation, le seuil (`COMPARISON_GT 10`) et la durée (`60s`) ci-dessus.
