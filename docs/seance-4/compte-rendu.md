# Compte rendu séance 4 — team3

| Mesure | Valeur |
| --- | --- |
| Lignes dans `tx_history`, transactions distinctes, doublons | 101 359 lignes, 100 859 `TX_ID` distincts, 500 doublons |
| Octets traités par votre requête de comptage, avec puis sans filtre sur `TX_TS` | 7,0 Mo, 6,2 Mo |
| Résultat de `check.sql` | client : 0 ; terminal : 0 |
| Client `7989449428740969`, jour 2026-10-01 dans `customer_daily` | `n` = 5 , `amount_sum` = 100,79 |
| Lecture des compteurs, source `parquet` (p50, p99) | ... ms, ... ms |
| Lecture des compteurs, source `bigquery` (p50, p99) | ... ms, ... ms |
| Lecture des compteurs, source `firestore` (p50, p99) | ... ms, ... ms |
| Score de la transaction `275114ca...` : `parquet`, `firestore` | ... , ... |
| Partie D : réglage retenu pour un rappel@10 ≥ 0,95 | `m` = 16 , `ef` = 4 ; rappel 0,990 ; p50 0,51 ms, p95 1,13 ms |
| Partie D : clients ayant présenté le même document que `0018478647296750` | `3263319564977208` , `2947552228922773` , `0553287702820053` |
| Lien du dépôt (Terraform et SQL) | <https://github.com/DeJongnick/ai-cloud-infra-terraform-student> |

Première requête de l'étape 0 (`fraudfinder.tx_seed`, 24 au 30 septembre) : 7 lignes, environ
100 000 transactions par jour, 11 259 488 octets traités (10,7 Mio).

## Partie D — mesures

300 requêtes, 10 voisins, temps mesuré par le serveur.

`m = 16` (index construit en 105 s) :

| ef | rappel@10 | p50 (ms) | p95 (ms) |
| --- | --- | --- | --- |
| exact | 1.000 | 11.54 | 15.70 |
| 4 | 0.990 | 0.51 | 1.13 |
| 8 | 0.990 | 0.49 | 0.77 |
| 16 | 0.992 | 0.56 | 1.37 |
| 32 | 0.996 | 0.64 | 1.29 |
| 64 | 0.996 | 0.80 | 1.62 |
| 128 | 0.996 | 1.07 | 2.11 |
| 256 | 0.999 | 1.29 | 2.33 |

`m = 4` (index construit en 94 s) :

| ef | rappel@10 | p50 (ms) | p95 (ms) |
| --- | --- | --- | --- |
| exact | 1.000 | 10.62 | 22.64 |
| 4 | 0.732 | 0.40 | 0.69 |
| 8 | 0.732 | 0.48 | 1.25 |
| 16 | 0.766 | 0.48 | 1.11 |
| 32 | 0.823 | 0.48 | 0.70 |
| 64 | 0.855 | 0.57 | 0.88 |
| 128 | 0.909 | 0.80 | 1.60 |
| 256 | 0.948 | 0.99 | 1.64 |

**Réglage retenu : `m = 16`, `ef = 4`.** Avec `m = 4`, aucun `ef` n'atteint 0,95 (0,948 à
`ef = 256`). Avec `m = 16`, le rappel est déjà de 0,990 au plus petit `ef`, pour une latence
inférieure à la milliseconde. Les valeurs de `ef` en dessous de 10 donnent le même rappel : pour
renvoyer 10 voisins, la recherche explore au moins 10 candidats. Les écarts de latence entre `ef = 4`
et `ef = 8` relèvent du bruit de mesure.

Le document 87 (client `0018478647296750`) est le bulletin de paie de Jules Laurent, Énergie du Sud,
19/09/2026. Trois autres clients ont présenté le même bulletin, avec seulement le salaire modifié
(similarité ≥ 0,999) : `3263319564977208`, `2947552228922773` et `0553287702820053`. Les voisins
suivants (0,98) sont d'autres bulletins de la même entreprise, au nom d'autres personnes.

## Partie A — Historiser

Avec le filtre, la requête traite 6 998 808 octets ; sans le filtre, 6 187 352 octets. Le filtre
n'écarte ici aucune partition, car toute la table est dans la partition du 1er octobre. La requête
filtrée lit même un peu plus, parce qu'elle doit lire la colonne `TX_TS` en plus de `TX_ID` et
`message_id`. Le gain apparaîtra quand la table contiendra plusieurs jours : un filtre sur `TX_TS`
ne lira que les partitions demandées. Juste après le rejeu, les deux requêtes affichaient 0 octet,
car les lignes étaient encore dans la zone d'écriture en continu.

**1. Les doublons ont-ils le même `message_id` ?**
Non. Les 500 `TX_ID` en double ont chacun deux `message_id` différents : la table compte autant de
`message_id` distincts que de lignes (101 359). Exemple : `a4192595823f9d76cb512fd158401f5219324826`,
publié une première fois à 18:52:42 (message `23291410429823364`), puis à 18:56:08 (message
`23290152046177500`). Il s'agit donc de **secondes publications** : la même transaction a été
publiée deux fois dans le topic. Ce ne sont pas de nouvelles livraisons par Pub/Sub, qui garderaient
le même `message_id`. `write_metadata` permet de faire cette distinction, et le `GROUP BY TX_ID` de la
partie B supprime ces doublons.

**2. Le service était-il nécessaire pour remplir la table ?**
Non. L'abonnement BigQuery écrit lui-même chaque message dans `tx_history` : aucun service ne tourne
et aucun code n'est déployé. Si l'historisation avait été une ligne de code dans `/pubsub`, un arrêt du
service aurait aussi arrêté l'historique. Les messages se seraient accumulés, puis seraient partis
dans la file de messages morts ou auraient expiré au bout de la rétention (1 heure). L'historique
aurait dépendu de la disponibilité du scoring, alors que les deux besoins sont indépendants.

**3. Pourquoi partitionner sur `TX_TS` plutôt que sur `publish_time` ?**
Les transactions datent du 1er octobre 2026, mais elles ont été publiées le 16 novembre, jour du
rejeu. Avec `publish_time`, toutes les lignes tomberaient dans la partition du 16 novembre, et un
filtre sur la date de la transaction ne permettrait d'écarter aucune partition. Les requêtes portent
sur la date de la transaction (les compteurs sont calculés par jour de transaction) : partitionner
sur `TX_TS` permet à BigQuery de ne lire que les jours demandés, et c'est ce filtre qui borne le coût.

## Partie B — Agréger

**1. En lisant `tx_history` directement dans `tx`, sans passer par `flux`, que devient `n` ?**
Il est surestimé pour chaque client concerné par une seconde publication. Sur le 1er octobre, la
somme des `n` passerait de 100 859 à 101 359 : les 500 doublons seraient comptés comme des
transactions, chez 497 clients. Le client `7989449428740969` n'a aucune transaction publiée deux
fois, donc son `n` reste à 5. En revanche, le client `4491307209748891` passerait de 4 à 6
transactions, et le client `7285705276607806` de 6 à 8. Leur nombre de transactions et leur montant
moyen seraient faux, alors que ce sont des variables du modèle.

**2. Où la règle « une transaction du 2 octobre ne lit que les jours jusqu'au 1er octobre » est-elle
appliquée ?**
Au moment de la lecture, pas dans la table. `customer_daily` et `terminal_daily` contiennent un
compteur par jour, y compris le jour en cours. C'est le service qui, pour une transaction du jour J,
ne somme que les jours J−1 à J−14. Si le compteur du jour même était lu, la transaction se compterait
elle-même, ainsi que les transactions plus tardives du même jour : c'est une fuite temporelle. Le
modèle verrait en production une valeur différente de celle de l'entraînement : partielle si le jour
n'est pas fini, venue du futur si la table est recalculée après coup.

**3. `n_fraud` vaut 0 pour le 1er octobre : est-ce une erreur ?**
Non. Le flux ne porte pas de label (`TX_FRAUD` est `NULL` pour ces lignes), donc `COUNTIF(TX_FRAUD = 1)`
vaut 0. Dans un vrai système, on n'apprend qu'une transaction était frauduleuse que plus tard :
contestation du client, rétrofacturation, enquête. Cela prend des jours, parfois des semaines. Le
délai de 7 jours reproduit ce retard : le service ne lit que des taux de fraude déjà connus au moment
de scorer, comme pendant l'entraînement.

## Partie C — Servir

**1. Pourquoi le score change-t-il entre `parquet` et les deux autres sources ?**
...

**2. Que perd-on en gardant `parquet` ?**
...

**3. Pourquoi ne pas lire BigQuery à chaque transaction ?**
...

**4. À quelle fréquence relancer la copie vers Firestore, et qui s'en chargerait ?**
...

## Partie D — Questions

**1. Que gagne-t-on et que perd-on avec `ef` et `m` ?**
Pour `m = 4`, passer `ef` de 4 à 256 fait monter le rappel de 0,732 à 0,948, mais la latence p50
passe de 0,40 à 0,99 ms (× 2,5) : on explore plus de candidats, donc on calcule plus de distances.
Passer de `m = 4` à `m = 16` à `ef` égal améliore bien plus le rappel (0,732 → 0,990 à `ef = 4`)
pour un faible surcoût de latence (0,40 → 0,51 ms). Le prix se paie ailleurs : plus de liens par
document, donc plus de mémoire, et une construction plus longue (105 s contre 94 s).

**2. À partir de quel volume l'index devient-il nécessaire ?**
La recherche exacte lit tous les vecteurs : son temps croît proportionnellement au nombre de
documents. Environ 11 ms pour 49 394 documents donne environ 0,2 µs par vecteur, soit environ
230 ms pour 1 million de documents et plus de 2 s pour 10 millions. L'index HNSW, lui, croît à peu
près comme le logarithme du volume. Pour un budget de quelques dizaines de millisecondes par
recherche, l'index devient nécessaire autour de quelques centaines de milliers de documents, ou
plus tôt si les recherches sont nombreuses en parallèle.

**3. Un rappel de 0,95 est-il acceptable ?**
Pour retrouver un document réutilisé, c'est juste. Chaque voisin manqué peut être un compte
frauduleux non détecté. Les copies sont très proches (similarité ≥ 0,999), donc l'index les trouve
presque toujours. On vise quand même un rappel plus élevé : `m = 16` donne 0,99 et plus. Une
recherche exacte peut servir de confirmation sur les cas suspects. Pour proposer des documents
similaires à un analyste, 0,95 suffit largement : un voisin manqué sur vingt ne change pas l'aide
apportée.

**4. Qu'avez-vous mis dans `scaling`, et pourquoi ? Que devient l'index si l'instance redémarre ?**
`min_instance_count = 1` et `max_instance_count = 1`. L'index vit dans la mémoire d'une seule
instance. Avec un minimum à 0, Cloud Run arrêterait l'instance au repos et l'index serait perdu.
Avec un maximum supérieur à 1, une seconde instance démarrerait avec une mémoire vide, et les
réponses dépendraient de l'instance qui reçoit la requête. Si l'instance redémarre, l'index
disparaît (404 sur la collection) et il faut relancer `load`. Pour le garder, il faudrait un stockage
persistant.

**5. Si on change de modèle d'embedding, que faut-il recalculer ?**
Tout : les embeddings des 49 394 documents, ceux des requêtes, et l'index HNSW, avec une nouvelle
collection si la dimension change. Les vecteurs de deux modèles différents ne sont pas comparables
entre eux, on ne peut donc pas mélanger anciens et nouveaux.

## Conclusion

...
