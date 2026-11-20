# Compte rendu — séance 6, équipe 3

**Date :** 20 novembre 2026

**Projet :** `advanced-cloud-ai`, région `europe-west1`

## Résultat

Le challenger (modèle v2) a été validé, observé en ombre, puis déployé par paliers jusqu'à 100 %.
L'alias Vertex AI `champion` a été déplacé vers v2. La version suivante fournie pour l'exercice a
échoué dès son passage à 10 % : son modèle attendait 22 features alors que le service en fournit 20.
Le signal a été détecté, le trafic est revenu sur la révision saine `candidate`, et le tag `next` a
été retiré.

## Déroulement et mesures

| Étape | Résultat |
| --- | --- |
| 0 — Référence | Révision champion `team3-scorer-prep-1119180441` ; p95 2,45 ms, erreurs 0 %, alertes 12,09 %, âge maximal 0 s. |
| 1 — Critères | Objectif : au moins 95 % des transactions scorées en 10 ms ou moins ; observation de 5 min par palier. Les seuils sont détaillés ci-dessous et dans [mesures.md](./mesures.md). |
| 2 — Validation et ombre | Contrat valide à 20 features. AP challenger 0,8679 contre 0,8473 (écart +0,0206, IC95 [0,0158 ; 0,0251]) ; segment le plus faible +0,0082. En ombre : désaccord 4,34 %, écart d'alertes −1,83 point ; candidat autorisé à recevoir du trafic. |
| 3 — Paliers | Candidate : à 10 %, 303 transactions distinctes, erreurs 0 %, p95 2,625 ms ; à 50 %, 1 508, erreurs 0 %, p95 2,643 ms ; à 100 %, 3 849, erreurs 0 %, p95 2,32 ms. Les critères sont restés satisfaits. L'alias `champion` a ensuite été promu à la version 2. |
| 4 — Panne | `next` déployée sans trafic avec `MODELS_DIR=/mnt/models/td6/next-model` et `MODEL_VERSION=next`, puis routée à 10 % à 13 h 28 min 43 s. Premier relevé à 13 h 31 min 31 s : 184 livraisons en échec, taux d'erreur 100 %, 0 transaction scorée. Confirmation : 300 échecs sur la fenêtre de 5 min. |
| 5 — Retour | Le log révèle `Feature shape mismatch, expected: 22, got 20`. `candidate` est revenue à 100 % ; après 3 min, 1 751 transactions distinctes, erreurs 0 %, p95 2,1 ms, alertes 6,1 %, âge maximal 0 s. Le tag `next` a été retiré. |

## Choix effectués

- **Seuils de décision fixés avant le déploiement :** p95 ≤ 10 ms pour avancer et > 20 ms pour
  revenir ; erreurs ≤ 2 % pour avancer et > 5 % pour revenir ; alertes entre 5 % et 20 % pour
  avancer, < 2 % ou > 30 % pour revenir ; âge du plus ancien message < 90 s pour avancer et
  ≥ 180 s pour revenir. Entre les bornes, prolonger l'observation. La plage d'alertes a été
  confirmée après l'ombre.
- **Réutilisation de la révision candidate existante :** elle était déjà saine et validée ; créer
  une seconde candidate n'aurait apporté aucune preuve supplémentaire.
- **Progression jusqu'à 100 % :** les mesures de chaque palier satisfaisaient les critères. Le
  déplacement de l'alias `champion` vers v2 a été fait séparément du routage Cloud Run, qui était
  déjà à 100 % sur `candidate`.
- **Diagnostic de `next` par révision :** `/health` répondait 200, mais ne validait pas le scoring.
  Le taux d'erreur de 100 % a franchi le seuil > 5 % ; l'âge des messages est resté à 26 s. P95 et
  taux d'alertes de `next` n'étaient pas calculables, faute de scores réussis.
- **Retour arrière :** `candidate` était la révision saine après la promotion ; elle a donc été
  remise à 100 %, mesurée après 3 min, puis le tag `next` a été supprimé.

## Restitution

En 90 secondes, présenter : le modèle `next` et son incompatibilité 22/20 features ; le premier
signal (100 % d'erreurs) ; le délai de détection (2 min 48 s) ; le retour vérifié sur `candidate` ;
et les deux améliorations proposées : un smoke test bloquant de scoring avant le trafic et une
alerte d'erreur par révision sur une fenêtre d'une minute. Le texte de présentation complet figure
dans [post-mortem.md](./post-mortem.md).

## État final et suite

- Cloud Run : `candidate` à 100 % ; tag `next` absent ; le tag `champion` reste sur l'ancienne
  révision à 0 %.
- La checklist signale comme non réalisés le test du mode dégradé, la reconstruction Terraform
  complète et la formalisation des propriétaires/politique de réentraînement. Ces points sont
  distingués des étapes 0 à 5 effectivement terminées.

Les preuves détaillées sont dans [mesures.md](./mesures.md), la cause et la restitution dans
[post-mortem.md](./post-mortem.md), et l'état de préparation dans [checklist.md](./checklist.md).
