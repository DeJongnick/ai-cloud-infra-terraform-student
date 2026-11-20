# Post-mortem séance 6 — team3

Un post-mortem sans blâme décrit des mécanismes, pas des personnes : ce que le système a permis, ce
qu'il n'a pas vu, ce qui l'aurait vu plus tôt. Chaque affirmation renvoie à une mesure, un extrait de
log ou une courbe.

Résumé en une phrase : la révision `next` a reçu 10 % du trafic alors que son modèle attendait 22
features et que le service n'en fournissait que 20 ; le taux d'erreur a atteint 100 %, puis le retour
sur `candidate` a rétabli les signaux.

## 1. Chronologie

| Heure | Événement | Source |
| --- | --- | --- |
| 13 h 26 | `next` déployée sans trafic avec `MODELS_DIR=/mnt/models/td6/next-model` et `MODEL_VERSION=next` ; `/health` répond 200 | révision `team3-scorer-next-1120132555`, réponse `/health` |
| 13 h 28 min 43 s | `next` passe à 10 % ; `candidate` reste à 90 % | commande `update-traffic` |
| 13 h 31 min 31 s | premier relevé : 184 livraisons `next`, toutes en erreur ; `candidate` à 0 % d'erreur | `measure.py`, fenêtre glissante de 5 min |
| 13 h 33 min 19 s | log `failed` : `Feature shape mismatch, expected: 22, got 20` | log de `team3-scorer-next-1120132555` |
| 13 h 35 min 29 s | confirmation sur 5 min : 300 échecs `next`, 0 transaction scorée | `measure.py` |
| 13 h 36 min 14 s – 13 h 37 min 57 s | retour demandé puis terminé : `candidate` à 100 % | commande et table `update-traffic` |
| 13 h 41 min 26 s | après 3 min : 1 751 transactions distinctes, 0 % d'erreur, p95 2,1 ms ; aucun log `next` | `measure.py`, `/health`, Monitoring |
| Après la mesure de retour | tag `next` retiré ; `candidate` reste à 100 % | table finale du trafic Cloud Run |

## 2. Signal

- Signal : taux d'erreur de `next` à 100 %, au-dessus du seuil de retour arrière (> 5 %) ; la
  première mesure le détecte à 13 h 31 min 31 s. `candidate` reste à 0 % d'erreur.
- Délai entre le passage à 10 % et la détection : 2 min 48 s.
- L'âge maximal du message non acquitté est resté à 26 s, sous le seuil d'avancement de 90 s.
  Latence p95 et taux d'alerte de `next` ne sont pas calculables, car aucun score n'a réussi.
- Avant la détection, `next` avait 184 livraisons en échec et 0 transaction distincte scorée. À
  100 % du même flux, une extrapolation linéaire donne environ 1 840 tentatives en échec, toujours
  0 transaction scorée.

## 3. Cause

- Les variables de modèle ont changé : `MODELS_DIR=/mnt/models/td6/next-model` et
  `MODEL_VERSION=next`. Le modèle chargé attend 22 features, contre les 20 fournies par le contrat
  du service.
- Cette incompatibilité provoque un échec à chaque scoring, donc 100 % d'erreurs et aucun score.
- Le log de la révision `next` l'établit ; `/health` répondait pourtant 200, car il ne vérifie pas
  la compatibilité du modèle avec un vrai payload de scoring.

```text
Feature shape mismatch, expected: 22, got 20
```

## 4. Action qui aurait détecté plus tôt

| Action | Ce qu'elle aurait vu | Quand (étape de la livraison) | Délai gagné | Responsable |
| --- | --- | --- | --- | --- |
| Smoke test bloquant de scoring sur l'URL de révision, avec un payload représentatif et le contrat de 20 features | l'incompatibilité 22 contre 20, avant toute exposition au trafic | après le déploiement sans trafic, avant `update-traffic` | panne détectée avant le palier | équipe du service (à désigner) |
| Alerte Cloud Monitoring par révision sur le taux d'échec > 5 % pendant une fenêtre d'une minute, à partir de `td6_failed` et des scores | le taux d'erreur de `next`, sans attendre la mesure manuelle | palier à 10 % | non mesuré ; cible d'une fenêtre d'une minute contre 2 min 48 observées | équipe de garde (à désigner) |

## 5. Restitution (90 secondes)

Notre révision `next` utilisait le modèle de `/mnt/models/td6/next-model`. À 10 % du trafic,
`/health` répondait encore 200, mais le premier relevé a montré 100 % d'erreurs sur cette révision ;
`candidate` restait à 0 %. Les logs ont donné la cause : le modèle attendait 22 features et le
service en envoyait 20. Nous l'avons détecté 2 min 48 s après le passage à 10 %. L'âge des messages
n'a pas alerté, et aucun p95 ni taux d'alerte n'était calculable faute de scores réussis. Nous avons
rétabli `candidate` à 100 %, vérifié son retour dans les critères, puis retiré le tag `next`.
Pour éviter une répétition, nous ajouterions un smoke test bloquant de scoring avant toute mise en
trafic et une alerte d'erreur calculée par révision sur une fenêtre d'une minute.
