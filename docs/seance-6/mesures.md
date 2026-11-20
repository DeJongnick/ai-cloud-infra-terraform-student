# Mesures séance 6 — team3

## Valeurs de référence (étape 0)

| Mesure | Valeur |
| --- | --- |
| Heure du relevé ; fenêtre | 20 novembre 2026, vers 12 h 34 (Europe/Paris) ; 10 min |
| Révision en service (tag `champion`) | `team3-scorer-prep-1119180441`, 100 % du trafic |
| Latence p95 (`p95 ms` de `measure.py`) | 2,45 ms |
| Taux d'erreur (`erreurs`) | 0 % |
| Taux d'alerte (`alertes`) | 12,09 % |
| Âge du plus ancien message non acquitté (tableau de bord) | 0 s |

`measure.py` : 3 219 livraisons et 2 904 transactions distinctes, sans troncature.
L'âge est relevé via l'API Monitoring avec le filtre et l'agrégation du tableau de bord
« TD6 team3 » : maximum de 0 s sur la fenêtre de 10 minutes.
`/health` répond 200, avec `status=ok`, cette révision, `model_version=1` et `threshold=0.0012`.

## Critères (étape 1)

Heure à laquelle les critères sont figés : 20 novembre 2026, 12 h 38 (Europe/Paris).

Objectif de service : au moins 95 % des transactions scorées en 10 ms ou moins.

| Signal | Référence | Seuil d'avancement | Seuil de retour arrière | Source |
| --- | --- | --- | --- | --- |
| Latence p95 | 2,45 ms | ≤ 10 ms | > 20 ms | `measure.py`, `p95 ms` |
| Taux d'erreur | 0 % | ≤ 2 % | > 5 % | `measure.py`, `erreurs` |
| Taux d'alerte | 12,09 % | entre 5 % et 20 % inclus | < 2 % ou > 30 % | `measure.py`, `alertes` |
| Âge du plus ancien message | 0 s | < 90 s | ≥ 180 s | tableau de bord |

En dehors des seuils d'avancement mais avant les seuils de retour arrière, prolonger l'observation.
Les seuils d'alerte sont provisoires jusqu'à la mesure en ombre de cette reprise.

Borne d'alertes fixée après l'ombre (étape 2) : avancement entre 5 % et 20 % inclus,
retour arrière sous 2 % ou au-dessus de 30 % ; écart candidat − champion mesuré en ombre :
−1,83 point ; taux candidat 7,50 % ; heure : 20 novembre 2026, 12 h 52 (Europe/Paris).
Le taux candidat et son écart observé restent dans les bornes : pas de motif de retour arrière.

Durée d'observation par palier : 5 min.

Commande de retour arrière (étapes 1 à 3) :

```bash
gcloud run services update-traffic team3-scorer --project advanced-cloud-ai --region europe-west1 --to-tags champion=100
```

Commande de retour arrière (à partir du palier à 100 %) ; `champion=100` si vous avez refusé le challenger :

```bash
gcloud run services update-traffic team3-scorer --project advanced-cloud-ai --region europe-west1 --to-tags candidate=100
```

## Validation (étape 2)

| Mesure | Valeur |
| --- | --- |
| `contrat.ok` ; latence pour 1 000 lignes (champion, candidat) | vrai ; 5,862 ms, 10,592 ms |
| AP globale champion, candidat ; écart et `ic95` | 0,8473, 0,8679 ; +0,0206 [0,0158 ; 0,0251] |
| Segment le plus faible ; son écart et son `ic95` | montant de 75 ou plus ; +0,0082 [0,0034 ; 0,0132] |
| Segments non concluants | aucun |
| `rejeu` : désaccord, taux d'alerte champion et candidat | 7,14 %, 13,83 %, 9,58 % |
| Révision candidate ; version du modèle | `team3-scorer-candidate-1119195956` ; 2 |
| Verdict | candidat autorisé à passer au premier palier ; validation conforme et mesures d'ombre dans les critères |

Validation : exécution `team3-validate-kpztq`, résultat dans `validation.txt`. Le mois de validation
a servi à choisir les hyperparamètres ; les écarts mesurés sur ce mois peuvent être optimistes.

## Mesures par palier

Une ligne par palier, relevée à la fin de la durée d'observation. La révision mesurée est la
nouvelle (`candidate`, puis `next` pour la panne, puis `candidate` au retour) ; la révision de
comparaison est celle qui sert de référence au même moment (`champion` jusqu'au palier à 100 %,
`candidate` pour la panne). Chaque case de signal porte deux valeurs : mesurée / comparaison. Au
palier à 100 % et au retour, la révision de comparaison n'a plus de trafic : comparez à la
référence de l'étape 0.

| Palier | Début | Fin | Révision mesurée | Révision de comparaison | `tx distinctes` (mesurée / comparaison) | p95 ms (mesurée / comparaison) | Erreurs (mesurée / comparaison) | Alertes (mesurée / comparaison) | Âge du plus ancien message | Décision | Critère invoqué |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Ombre (0 %) | vers 12 h 44 | 12 h 52 | `team3-scorer-candidate-1119195956` | `team3-scorer-prep-1119180441` | 4 787 / 4 792 | 2,324 / 2,58 | 0 % / 0 % | 7,50 % / 9,33 % | 0 s | autorisé au premier palier | contrat valide ; p95, erreurs, alertes et âge dans les bornes |
| 10 % | 12 h 56 | 13 h 02 | `team3-scorer-candidate-1119195956` | `team3-scorer-prep-1119180441` | 303 / 2 688 | 2,625 / 2,607 | 0 % / 0 % | 8,25 % / 9,38 % | 0 s | avancer à 50 % | les quatre signaux restent sous les seuils d'avancement |
| 50 % | 13 h 02 | 13 h 08 | `team3-scorer-candidate-1119195956` | `team3-scorer-prep-1119180441` | 1 508 / 1 478 | 2,643 / 2,55 | 0 % / 0 % | 7,69 % / 9,61 % | 0 s | avancer à 100 % | les quatre signaux restent sous les seuils d'avancement |
| 100 % | 13 h 09 | 13 h 15 | `team3-scorer-candidate-1119195956` | référence étape 0 | 3 849 / 2 904 | 2,32 / 2,45 | 0 % / 0 % | 9,07 % / 12,09 % | 14 s | palier validé ; alias `champion` déplacé sur la version 2 | p95, erreurs, alertes et âge respectent les seuils |
| Panne (`next` à 10 %) | 13 h 28 min 43 s | 13 h 35 min 29 s | `team3-scorer-next-1120132555` | `team3-scorer-candidate-1119195956` | 0 / 2 975 | — / 2,1 | 100 % / 0 % | — / 8,7 % | 26 s | retour à `candidate` (100 %) | erreurs 100 % > 5 % ; 300 livraisons `next` en échec |
| Retour (`candidate` à 100 %) | 13 h 37 min 57 s | 13 h 41 min 26 s | `team3-scorer-candidate-1119195956` | référence étape 0 | 1 751 / 2 904 | 2,1 / 2,45 | 0 % / 0 % | 6,1 % / 12,09 % | 0 s | retour vérifié ; tag `next` retiré | signaux disponibles dans les bornes ; aucun log `next` sur 3 min |

En ombre : désaccord 4,34 % et écart d'alertes −1,83 point (`--compare`), sur 4 773 transactions
communes. La fenêtre de huit minutes contient 4 793 livraisons en ombre et 4 792 en réel,
sans troncature ; l'âge maximal du message non acquitté est de 0 s sur sept points Monitoring.

Le candidat existant a été revalidé et mesuré en ombre. L'abonnement d'ombre a été supprimé avant
le palier à 10 %. Après validation des trois paliers, le candidat reçoit 100 % du trafic réel.

Panne : `next` passe à 10 % à 13 h 28 min 43 s. Premier franchissement observé à 13 h 31 min 31 s,
soit un délai de 2 min 48 s ; confirmation à 13 h 35 min 29 s sur une fenêtre complète de 5 min.
Le premier relevé compte 184 livraisons `next`, toutes en erreur ; la confirmation en compte 300,
avec 0 transaction distincte scorée. `candidate` reste à 0 % d'erreur. L'âge maximal du message
non acquitté est de 26 s (fenêtre Monitoring de 5 min), sous la borne de 90 s.

Les logs `failed` de `next` indiquent `Feature shape mismatch, expected: 22, got 20` : le modèle
attend 22 features alors que le service lui en fournit 20. `/health` répondait pourtant HTTP 200
avec `status=ok`, ce qui ne vérifie pas la compatibilité au moment du scoring.

Le retour vers `candidate` est demandé à 13 h 36 min 14 s et terminé à 13 h 37 min 57 s.
Après 3 min, `/health` répond HTTP 200 sur le candidat ; `measure.py` compte 1 751 transactions
distinctes, 0 % d'erreur, p95 à 2,1 ms et 6,1 % d'alertes ; aucun log `next`. L'âge maximal du
message non acquitté est de 0 s. Le tag `next` a ensuite été retiré ; l'état final conserve
`candidate` à 100 % et `champion` à 0 %.

Alias `champion` du registre déplacé de la version 1 vers la version 2 à environ 13 h 15 le
20 novembre. La vérification finale confirme que la version 2 porte `champion` et `challenger`.

## Réponses aux questions

### Étape 2 — Validation et ombre

1. L'écart global de +0,0206 a un intervalle [0,0158 ; 0,0251] qui exclut 0. La validation ayant
   servi au choix des hyperparamètres, ce résultat peut être optimiste ; la décision de séance 5
   sur le test reste distincte.
2. Aucun segment n'est non concluant dans ce résultat. Un segment avec trop peu de fraudes ne
   fournirait pas une estimation assez fiable pour décider seul.
3. Le désaccord est de 4,34 % en ombre contre 7,14 % en validation. Des transactions et des
   distributions différentes, ainsi que des données de features différentes, peuvent l'expliquer.
4. L'ombre mesure le candidat dans les conditions du service et du flux, notamment sa latence et
   les divergences de décision sur des transactions communes, sans appliquer ses décisions.

### Étape 3 — Paliers

1. À 10 %, le candidat a scoré 303 transactions distinctes. Cela atteint le minimum d'environ 300
   suggéré par l'énoncé pour une première estimation du taux d'alerte, sans garantir une grande
   précision statistique.
2. En marge absolue dans les unités communes aux taux, le taux d'erreur était le plus proche du
   retour arrière : 0 % face à un seuil > 5 %. Pour le taux d'alerte, la plus petite marge était au
   palier de 50 % : 7,69 %, soit 5,69 points au-dessus de la borne basse de 2 %. Aucun signal n'a
   approché son seuil de retour arrière.
3. `promote.sh` a déplacé l'alias `champion` de la version 1 à la version 2 sans changer le trafic
   Cloud Run : celui-ci était déjà à 100 % sur le tag `candidate`. L'alias nomme la version modèle
   par défaut pour les prochains déploiements ; le tag identifie une révision Cloud Run et sa route.

### Étape 4 — Panne

1. Le taux d'erreur de `next` atteint 100 % dès le premier relevé, au-dessus du seuil de retour
   arrière (> 5 %). L'âge du plus ancien message reste à 26 s, sous le seuil d'avancement de 90 s.
   Latence p95 et taux d'alerte de `next` ne sont pas calculables : aucune transaction n'a été scorée.
2. Le taux d'erreur suffit à détecter cette panne. L'âge du message ne l'aurait pas détectée dans
   cette fenêtre ; p95 et alertes ne sont pas disponibles faute de scores réussis.
3. `next` n'a scoré aucune transaction distincte : 184 livraisons en échec étaient déjà visibles
   au premier relevé, puis 300 sur la fenêtre de confirmation. À 100 % du même flux, cela aurait
   représenté environ 1 840 tentatives en échec avant la détection, toujours 0 transaction scorée.
