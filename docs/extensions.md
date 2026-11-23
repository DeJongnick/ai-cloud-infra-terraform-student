# Extensions — team3

Qui a fait quoi : Léo Bouchand (les six extensions ci-dessous).

Chaque entrée donne le domaine, ce qui a été construit (fichier et commit) et comment le voir
fonctionner. Le détail, les mesures et les limites sont dans le fichier cité.

| # | Domaine | Extension | Origine |
| --- | --- | --- | --- |
| 1 | Monitoring, Terraform | Alerte par révision qui aurait détecté la panne du TD6 | TD6, extension « Alerte » |
| 2 | Terraform | Service `team3-scorer` décrit en Terraform, sans l'appliquer | TD6, « Après le TD » |
| 3 | Cycle de vie du modèle | Contrôle de dérive entre deux semaines, avec une décision | TD6, extension « Dérive » |
| 4 | Cycle de vie du modèle | Politique de réentraînement et responsables | TD6, extension « Politique de réentraînement » |
| 5 | Déploiement | Test de fumée bloquant dans le workflow de livraison | TD6, extension « Livraison » |
| 6 | Déploiement, Terraform | Déploiement continu, et `lifecycle` pour que Terraform ne le défasse pas | TD2, partie D |

## 1. Alerte par révision (Monitoring, Terraform)

**Ce qui a été construit.** La règle `team3-scorer-release`, écrite en code dans `infra/release.tf`
(commit `57a81c3`) et appliquée avec `-target`. Elle se déclenche quand une révision de `team3-scorer`
compte plus de 10 échecs `td6_failed` par minute pendant 60 s (`ALIGN_SUM`, `REDUCE_SUM`, groupé par
révision). En temps normal, il y a 0 échec. Pendant la panne de `next`, il y en a eu 23, puis 55 à 75
par minute. La règle aurait donc ouvert un incident vers 13 h 30, contre une détection manuelle à
13 h 31 min 31 s. C'est une estimation : le délai d'ingestion des métriques de logs n'a pas été mesuré.

**Comment le voir.** Console → Monitoring → Alertes → `team3-scorer-release`, ou
`terraform -chdir=infra state show google_monitoring_alert_policy.release`. Détail :
[`seance-6/apres-td.md`](seance-6/apres-td.md).

## 2. Le scorer décrit en Terraform (Terraform)

**Ce qui a été construit.** `infra/scorer/main.tf` (bloc `import`, état local, pas de backend) et
`infra/scorer/scorer.tf`, généré par `terraform plan -generate-config-out` puis protégé par
`prevent_destroy` (commit `57a81c3`). Ce dossier sert uniquement au `plan` : le service appartient au
socle. La sortie est dans [`seance-6/plan.txt`](seance-6/plan.txt), avec les adresses masquées. La
ligne d'en-tête note que le gabarit courant (`template.revision`) n'est pas la révision qui sert le
trafic.

**Comment le voir.** `terraform -chdir=infra/scorer init && terraform -chdir=infra/scorer plan` :
`Plan: 1 to import, 0 to add, 0 to change, 0 to destroy`.

## 3. Contrôle de dérive (cycle de vie du modèle)

**Ce qui a été construit.** La comparaison de `fraudfinder.tx_seed` entre la semaine du 10 au
16 septembre et celle du 24 au 30 septembre (commit `17f3cb7`). Le montant médian, le 95ᵉ centile et
l'activité par client bougent de moins de 0,2 %. Le taux de fraude monte de 0,901 % à 1,236 %
(+37 %), mais il repose sur des labels encore incomplets pour la semaine la plus récente. Décision :
pas de réentraînement sur ce seul signal.

**Comment le voir.** La requête et le tableau d'écarts sont dans
[`seance-6/extensions.md`](seance-6/extensions.md), section « Dérive ». On la relance dans la console
BigQuery, emplacement `europe-west1`.

## 4. Politique de réentraînement et responsables (cycle de vie du modèle)

**Ce qui a été construit.** Une politique de réentraînement sur résultats (commit `17f3cb7`). Chaque
semaine, on mesure l'AP du champion sur la semaine J−14 à J−7, dont les labels sont arrivés. Si elle
passe sous 0,8492, la borne basse de son intervalle sur le test de la séance 5, on réentraîne sur les
3 derniers mois. Le nouveau modèle passe ensuite par la règle d'entrée, la validation, l'ombre et les
paliers. Un responsable est nommé pour chaque élément (ligne « Owned » de la checklist).

**Comment le voir.** [`seance-6/extensions.md`](seance-6/extensions.md), section « Politique de
réentraînement » ; [`seance-6/checklist.md`](seance-6/checklist.md), ligne « Owned ».

## 5. Test de fumée bloquant (déploiement)

**Ce qui a été construit.** `.github/workflows/release.yml` dans le dépôt applicatif
[`DeJongnick/td2-fraud-api-albertschool`](https://github.com/DeJongnick/td2-fraud-api-albertschool),
branche `ci-livraison` (commit `936b7e3`). Le workflow déploie une révision taguée sans trafic sur
`team3-scorer`. Il vérifie ensuite `/health` (`status=ok`), puis score une vraie transaction avec
`POST /predict`, et échoue si l'une des deux vérifications ne passe pas. Avec le modèle `next` du TD6,
`/health` répond 200 mais `/predict` répond 500 : le test aurait arrêté la panne avant toute mise en
trafic.

**Comment le voir.** Exécution en échec voulu sur le test de fumée :
[45189954111](https://github.com/DeJongnick/td2-fraud-api-albertschool/actions/runs/45189954111).
Exécution réussie :
[45190412288](https://github.com/DeJongnick/td2-fraud-api-albertschool/actions/runs/45190412288).
Détail : [`ci-livraison.md`](ci-livraison.md).

## 6. Déploiement continu et `lifecycle` (déploiement, Terraform)

**Ce qui a été construit.** `.github/workflows/deploy.yml` dans le dépôt applicatif (commit
`2c510da`). Un push construit l'image `linux/amd64`, taguée par le hash du commit, la pousse dans le
registre partagé, et crée une révision de `team3-fraud-api` sans trafic, avec le tag `livraison`.
L'authentification se fait par fédération d'identité, avec le compte `team3-cd`, sans fichier de clé.
Dans `infra/main.tf`, un bloc `lifecycle { ignore_changes = [...] }` (commit `44e0655`) empêche
Terraform de remettre `var.image` et d'effacer la révision créée par le workflow.

**Comment le voir.** Exécution réussie :
[45191209073](https://github.com/DeJongnick/td2-fraud-api-albertschool/actions/runs/45191209073).
`gcloud run services describe team3-fraud-api --region europe-west1` montre le tag `livraison`.
`terraform -chdir=infra plan` affiche « No changes ». Détail : [`ci-livraison.md`](ci-livraison.md).
