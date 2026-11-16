# Compte rendu séance 3 — team3

| Mesure | Valeur |
| --- | --- |
| Messages traités et débit atteint | ≈ 384 000 messages scorés, doublons compris (≈ 398 000 requêtes `/pubsub`, dont 14 550 refusées en 429 puis relivrées) ; palier le plus haut suivi sans retard qui grossit : ≈ 530 messages/s |
| Âge maximal du plus ancien message non acquitté pendant la montée en charge | 138 s, au palier de ≈ 700 messages/s (file maximale : 81 038 messages à 18:11) |
| Nombre d'instances au pic | 3 (maximum autorisé : 3), atteint dès 100 messages/s |
| `tx_id` lu dans la file de messages morts | `poison-20261116`, arrivé 1 min 35 s après la première tentative (17:57:46 → 17:59:21, 5 livraisons) |
| Lien du dépôt (Terraform et service) | <https://github.com/DeJongnick/ai-cloud-infra-terraform-student> ; <https://github.com/DeJongnick/td2-fraud-api-albertschool> |

## Configuration testée

| Paramètre | Valeur |
| --- | --- |
| Image | `team3-fraud-api:td3` |
| Concurrence par instance (`max_instance_request_concurrency`) | 4 |
| Instances (`min_instance_count` / `max_instance_count`) | 0 / 3 |
| Ressources par instance | 1 vCPU, 1 Gio |
| Abonnement `team3-tx-push` | délai d'acquittement 30 s, relivraison entre 10 et 60 s, file de messages morts après 5 tentatives |

## Mesures pendant la montée en charge (16 novembre 2026, UTC+1)

Valeurs lues minute par minute dans Cloud Monitoring.

| Heure | Débit reçu (req/s) | Messages en attente (max) | Âge du plus ancien (s) | Instances | Latence p50 / p99 (ms) |
| --- | --- | --- | --- | --- | --- |
| 17:59 – 18:01 | ≈ 100 | 0 | 0 | 3 | 5 / 15 – 24 |
| 18:02 | ≈ 320 | 17 | 3 | 3 | 5 / 24 |
| 18:03 – 18:06 | ≈ 500 – 530 | 54 – 103 | 0 – 5 | 3 | 5 / 10 – 11 |
| 18:07 | ≈ 700 – 760 | 3 409 | – | 3 | 5 / 12 |
| 18:08 | ≈ 750 | 25 351 | 36 | 3 | 5 / 13 |
| 18:09 | ≈ 700 | 46 031 | 60 | 3 | 5 / 16 |
| 18:10 | ≈ 690 | 66 881 | 88 | 3 | 5 / 16 |
| 18:11 | ≈ 640 | 81 038 | 121 | 3 | 5 / 13 |
| 18:12 | ≈ 460 | 43 172 | 116 | 3 | 5 / 15 |
| 18:13 | ≈ 0 | 5 018 | 138 | 3 | – |
| 18:14 | 0 | 0 | 0 | 3 | – |

## Étape 1 — Brancher

**1. Messages non acquittés et âge du plus ancien message pendant les 404.**
Le 12 novembre, de 18:56 à 19:17, le service renvoyait 404 sur `/pubsub` (1 039 requêtes en 404).
Aucun message n'était acquitté : le nombre de messages non acquittés a grimpé de façon continue
(65 à 19:00, 442 à 19:18) et l'âge du plus ancien message aussi, à peu près au rythme de l'horloge
(134 s à 19:00, 1 035 s à 19:18). En parallèle, 5 à 20 messages par minute partaient dans la file de
messages morts. Dès le déploiement de `/pubsub` (premier 204 à 19:17), la file s'est vidée en une
minute et l'âge est retombé à 0.

**2. Pourquoi un compte `team3-push` séparé de `team3-run` ?**
Les deux comptes représentent deux rôles différents :

| Compte | Qui l'utilise | Droits |
| --- | --- | --- |
| `team3-run` | le code du service, à l'exécution | lecture du bucket des modèles (`roles/storage.objectViewer`), écriture des logs (`roles/logging.logWriter`) |
| `team3-push` | Pub/Sub, pour signer le jeton OIDC envoyé avec chaque message | appel du service (`roles/run.invoker` sur `team3-fraud-api` uniquement) |

Séparer les comptes applique le moindre privilège : le code du service n'a pas le droit de s'appeler
lui-même, et l'identité de livraison ne peut ni lire les données ni écrire de logs. On voit aussi dans
les journaux d'audit qui a fait quoi, et on peut retirer le droit de livraison sans toucher au service.

**3. Contenu de `team3-tx-dead-pull` après 3 minutes.**
Des transactions FraudFinder parfaitement valides. Elles n'avaient rien d'anormal : elles ont été
livrées 5 fois, ont reçu 5 fois un 404 parce que l'endpoint n'existait pas encore, et Pub/Sub les a
mises de côté. La file de messages morts ne dit pas qu'un message est invalide, seulement qu'il n'a
pas pu être traité après 5 tentatives.

## Étape 3 — Observer et casser

**1. À quel débit le retard grossit-il, et qu'est-ce qui l'absorbe ?**
Le service suit jusqu'à ≈ 530 messages/s : la file reste sous 100 messages et l'âge sous 5 s. Au-delà,
vers 700 messages/s, il plafonne à ≈ 700 – 750 requêtes traitées par seconde et la file grossit de
≈ 20 000 messages par minute.

La limite est le nombre maximal d'instances : les 3 instances sont occupées dès 100 messages/s et ne
peuvent plus augmenter. Avec une concurrence de 4, le service traite au plus 12 requêtes à la fois.
La latence côté serveur reste stable (p50 de 5 ms du début à la fin) : le code ne ralentit pas, c'est
la capacité totale qui sature. Au-delà, Cloud Run renvoie 429 (« request aborted after waiting too
long for an available instance », 14 550 fois entre 18:05 et 18:11). Un 429 n'acquitte pas le message :
Pub/Sub le garde et le relivre, ce qui absorbe le surplus dans la file. Aucun message n'a été perdu, et
la file s'est vidée en deux minutes quand la charge est retombée. Augmenter `max_instance_count` ou la
concurrence par instance relèverait ce plafond.

**2. Sans file de messages morts, que serait devenu le message empoisonné ?**
Il aurait été relivré indéfiniment, toutes les 10 à 60 s, jusqu'à la fin de la rétention de
l'abonnement (1 heure) : un rejet en boucle qui consomme des requêtes et des instances, puis une
disparition silencieuse. Avec la file de messages morts, il a été relivré 5 fois (4 lignes `rejected`
dans les logs, 5 livraisons comptées par Pub/Sub), puis mis de côté dans `team3-tx-dead`, où il a pu
être lu et examiné.

**3. Doublons de `tx_id`, et comment distinguer une nouvelle livraison d'une seconde publication.**
Oui. Pendant la montée en charge, 15 591 lignes `scored` portent un `delivery_attempt` supérieur à 1
(15 432 à la 2ᵉ tentative, 159 à la 3ᵉ). Sur un échantillon de 20 de ces `tx_id`, 8 n'ont qu'une ligne
`scored` (la première tentative a été refusée en 429 avant d'atteindre le conteneur) et 12 en ont deux :
ce sont de vrais doublons. Exemple, `1ddda9530cce8a3b6084ca6829b6b0fc8e3e8f37` : scoré à 18:05:26
(tentative 1), puis à nouveau à 18:08:51 (tentative 2), avec le même score. L'explication la plus
probable : pendant la saturation, la requête a attendu une instance libre, et le 204 est arrivé après le
délai d'acquittement de 30 s ; Pub/Sub avait déjà considéré la livraison comme échouée et a relivré.
Pub/Sub garantit une livraison « au moins une fois », pas « exactement une fois ».

Pour vérifier les doublons, on regroupe les lignes `scored` par `tx_id` (Logs Explorer ou Log Analytics)
et on garde ceux qui apparaissent plus d'une fois. Pour savoir d'où vient le doublon :

- **nouvelle livraison par Pub/Sub** : même message, même `messageId`, `delivery_attempt` supérieur à 1 ;
- **seconde publication** : nouveau message, `messageId` différent, `delivery_attempt` égal à 1.

Le doublon ci-dessus est une nouvelle livraison (`delivery_attempt` = 2). Comme `/pubsub` n'enregistre
rien dans les compteurs, elle donne le même score : le traitement est idempotent, et le doublon ne
fausse aucun résultat. Ajouter le `messageId` dans la ligne de log permettrait de trancher directement.
