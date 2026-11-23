# Extensions séance 6 — team3

Qui a fait quoi : Léo Bouchand (dérive et politique de réentraînement).

## Dérive

**Protocole.** Requête de l'énoncé (« Requête de l'extension Dérive »), lancée telle quelle le
23 novembre 2026 à 14 h 58 (Europe/Paris), emplacement `europe-west1` :

```bash
bq query --use_legacy_sql=false --location=europe-west1 --project_id=advanced-cloud-ai < drift.sql
```

Job `bqjob_r6f2b8d824e9412b9_000001a208b3d881_1` : 59 011 092 octets traités (56,3 Mio).

| Grandeur | 10-16 sept. | 24-30 sept. | Écart relatif |
| --- | --- | --- | --- |
| Montant médian (`TX_AMOUNT`) | 52,40 | 52,36 | −0,08 % |
| Montant au 95ᵉ centile | 98,51 | 98,43 | −0,08 % |
| Transactions par client actif et par jour | 2,664 | 2,669 | +0,16 % |
| Taux de fraude (`TX_FRAUD`) | 0,901 % | 1,236 % | +37,2 % (+0,34 point) |

Écart relatif = (24-30 sept. − 10-16 sept.) / 10-16 sept.

**Requête complémentaire, par jour** (même filtre, 47 770 884 octets traités, même heure). Elle sert à
lire la variabilité du taux de fraude d'un jour à l'autre :

```sql
SELECT DATE(TX_TS) AS jour, COUNT(*) AS n_tx, COUNT(DISTINCT CUSTOMER_ID) AS clients_actifs,
  SUM(TX_FRAUD) AS n_fraudes, ROUND(AVG(TX_FRAUD), 5) AS taux_fraude
FROM `fraudfinder.tx_seed`
WHERE (TX_TS >= TIMESTAMP '2026-09-10' AND TX_TS < TIMESTAMP '2026-09-17')
   OR (TX_TS >= TIMESTAMP '2026-09-24' AND TX_TS < TIMESTAMP '2026-10-01')
GROUP BY jour ORDER BY jour
```

| Semaine | Transactions | Clients actifs par jour | Fraudes | Taux de fraude par jour (min – max) |
| --- | --- | --- | --- | --- |
| 10-16 sept. | 701 308 | 37 536 – 37 698 | 6 318 | 0,55 % – 1,36 % |
| 24-30 sept. | 703 718 | 37 545 – 37 763 | 8 698 | 0,69 % – 1,57 % |

**Lecture.**

- Les trois grandeurs d'entrée ne bougent pas : montant médian, montant p95 et activité des clients
  varient de moins de 0,2 %. Le volume (+0,34 %) et le nombre de clients actifs sont stables. Les
  variables que lit le modèle ne dérivent pas sur ces deux semaines.
- Seul le taux de fraude monte : +37 %, soit +0,34 point. Avec 700 000 transactions par semaine,
  l'écart n'est pas un effet d'échantillon. Mais le taux varie déjà du simple au double à l'intérieur
  d'une même semaine (0,55 % à 1,36 % du 10 au 16 septembre) : la fraude arrive par vagues.
- Le taux de la semaine du 24 au 30 septembre repose sur des labels incomplets. Une fraude n'est
  connue qu'après contestation ou enquête, avec au moins 7 jours de retard (séance 4, partie B.3).
  Les derniers jours de la semaine ont donc encore des fraudes à venir. Le vrai taux est au moins
  celui qu'on lit, sans doute plus haut.

**Décision : pas de réentraînement maintenant.**

- Les entrées du modèle sont stables. Rien n'indique que le champion voie des transactions
  différentes de celles de son entraînement.
- La hausse porte sur la part de fraudes, pas sur leur forme. Elle ne dit pas si le modèle les
  détecte moins bien. Le modèle en service (version 2) a été testé sur septembre 2026 en séance 5 :
  AP de 0,8587, IC à 95 % [0,8492 ; 0,8667].
- La question à trancher est la performance, et elle ne se mesure qu'avec des labels complets. On
  recalcule l'AP du champion sur la semaine du 24 au 30 septembre une fois ses labels arrivés, avec
  la règle de la section suivante. Sous le seuil, on réentraîne.
- Limite : trois grandeurs agrégées ne voient pas tout. Une dérive sur les terminaux, sur une
  tranche de montants ou sur la répartition par heure n'apparaîtrait pas ici.

## Politique de réentraînement

**Choix : réentraîner sur résultats**, c'est-à-dire quand l'AP mesurée sur des labels arrivés passe
sous un seuil. Ni au calendrier ni sur dérive.

1. Les labels de fraude arrivent avec au moins 7 jours de retard (séance 4, B.3). Toute mesure de
   performance porte donc sur des transactions d'il y a 7 jours ou plus. C'est le délai minimal de
   la politique, quelle qu'elle soit.
2. Une politique sur dérive des entrées aurait manqué le cas mesuré ci-dessus : entrées stables
   (moins de 0,2 % d'écart), mais taux de fraude en hausse de 37 %. La dérive reste un signal
   d'alerte, lu chaque semaine, pas un déclencheur.
3. Un calendrier réentraînerait sans savoir si c'est utile. Chaque nouveau modèle passe par la
   validation, l'ombre et trois paliers de 5 minutes (séance 6). Chaque passage est un risque : la
   version `next` a donné 100 % d'erreurs à 10 % du trafic.
4. Le coût de calcul ne contraint pas le choix : 0,035 $ à 0,067 $ par recherche de 40 essais, et
   9 minutes de custom job sur une `n2-standard-8` pour 3 mois de données, de la soumission à la
   fin (séance 5). Ce qui compte, c'est le délai des labels et le risque d'une mise en service.
5. La règle, chaque semaine : AP du champion sur la semaine J−14 à J−7, dont les labels sont
   arrivés. Sous 0,8492, la borne basse de son IC sur le test de la séance 5, on réentraîne sur les
   3 derniers mois aux labels arrivés. Le modèle obtenu passe la règle d'entrée de la séance 5
   (marge 0,003, test lu une fois), puis la validation, l'ombre et les paliers de la séance 6.

**Responsables (ligne « Owned »).**

| Élément | Responsable | Ce qu'il fait |
| --- | --- | --- |
| Modèle et réentraînement | Léo Bouchand | calcul hebdomadaire de l'AP sur labels arrivés, réentraînement, règle d'entrée au registre (séance 5) |
| Données et agrégats | Léo Bouchand | `tx_history`, `customer_daily` et `terminal_daily`, `check.sql`, copie vers Firestore (séance 4) ; requête de dérive hebdomadaire |
| Recherche d'hyperparamètres et coûts | Nicolas Lejeune | job `team3-train`, recherche parallèle et son coût (séance 5) |
| Validation du candidat | Richard Brouquier | `validate.sh`, segments, ombre (séance 6) |
| Mise en service et retour arrière | Pierre Salmon | paliers, critères, commande de retour arrière, flux Pub/Sub (séances 3 et 6) |
| Alerte et astreinte | Pierre Salmon | règle `team3-scorer-release`, réponse à l'alerte, post-mortem |

**Limites.** La mesure hebdomadaire de l'AP n'est pas automatisée : aucune tâche planifiée ne la
lance aujourd'hui. Le seuil de 0,8492 vient d'un seul jeu de test et serait à revoir après quelques
semaines de mesures.
