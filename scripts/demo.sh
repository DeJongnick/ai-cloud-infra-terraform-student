#!/usr/bin/env bash
# Démonstration de bout en bout pour la soutenance team3 (déroulé : docs/soutenance.md).
#
# On suit une transaction du flux au modèle en service. Chaque étape affiche la commande, puis
# son résultat, et attend Entrée. Tout est en lecture seule, sauf deux publications dans notre
# topic team3-demo (infra/demo.tf) et l'acquittement de notre message dans la file de messages
# morts. Le script ne touche jamais à team3-scorer (ressource du socle).
#
#   scripts/demo.sh            # toute la démo
#   scripts/demo.sh 6          # reprendre à l'étape 6
#   DEMO_AUTO=1 scripts/demo.sh  # répétition sans pause
#
# Prérequis : gcloud auth login, bq, gh auth login, terraform init dans infra/.

set -u

PROJECT=advanced-cloud-ai
REGION=europe-west1
TEAM=team3
URL=https://team3-fraud-api-ueiaychpgq-ew.a.run.app
APP_REPO=DeJongnick/td2-fraud-api-albertschool
MODEL_ID=5677326090998120448
ALERT=projects/$PROJECT/alertPolicies/13752530996358291967
DECISION=gs://advanced-cloud-ai-models/runs/team3/decisions/20261118T190159634910Z-20261118T185924Z6e84b7.json
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1   # chemins relatifs à la racine du fork
START=${1:-1}
STAMP=$(date +%H%M%S)
TX_ID=demo-$STAMP
POISON_ID=poison-$STAMP
STATE=${TMPDIR:-/tmp}/team3-demo.env   # garde les tx_id si on reprend à une étape

B=$'\033[1m'; G=$'\033[32m'; C=$'\033[36m'; Y=$'\033[33m'; N=$'\033[0m'

pause() { [ "${DEMO_AUTO:-0}" = 1 ] || read -r -p "${Y}  ⏎ ${N}" _; }
etape() { # numéro, qui, titre
  CUR=$1
  [ "$1" -ge "$START" ] || return 1
  printf '\n%s━━━ %s. %s  %s(%s)%s\n' "$B" "$1" "$3" "$C" "$2" "$N"
  return 0
}
dire() { printf '%s  » %s%s\n' "$G" "$*" "$N"; }
run()  { printf '%s$ %s%s\n' "$C" "$*" "$N"; eval "$@"; }
logs() { # filtre, format, fraîcheur
  gcloud logging read "resource.type=\"cloud_run_revision\" $1" --project "$PROJECT" \
    --freshness="${3:-15m}" --limit 10 --format="$2"
}

# Petits programmes Python qui mettent en forme les sorties JSON.
read -r -d '' PY_SCORED <<'PY'
import json, sys
for e in json.load(sys.stdin):
    p = e["jsonPayload"]
    print("  %s UTC  %s  tx_id=%s  score=%.6f" % (e["timestamp"][11:19], p["message"], p["tx_id"], p["score"]))
    print("  source=%s  features_ms=%s  delivery_attempt=%s" % (p["source"], p["features_ms"], p["delivery_attempt"]))
    print("  subscription=%s" % p["subscription"].split("/")[-1])
PY
read -r -d '' PY_DEAD <<'PY'
import base64, json, os, sys, time
for m in json.load(sys.stdin):
    data = base64.b64decode(m["message"]["data"]).decode()
    if os.environ["POISON_ID"] and os.environ["POISON_ID"] in data:
        a = m["message"].get("attributes", {})
        err = sys.stderr
        print("  tx_id lu : %s" % json.loads(data)["TX_ID"], file=err)
        print("  abonnement d'origine : %s" % a.get("CloudPubSubDeadLetterSourceSubscription", "?"), file=err)
        print("  tentatives : %s" % a.get("CloudPubSubDeadLetterSourceDeliveryCount", "?"), file=err)
        t0 = int(os.environ["POISON_AT"])
        if t0:
            print("  arrivé %d s après la publication" % (int(time.time()) - t0), file=err)
        print(m["ackId"])
PY
read -r -d '' PY_DECISION <<'PY'
import json, sys
d = json.load(sys.stdin)
r = d["regle"]
print("  règle : %s (marge %s, %s tirages bootstrap)" % (r["accepté si"], r["margin"], r["bootstrap"]))
print("  rang_lecture_test : %s   n_test : %s" % (d["rang_lecture_test"], d["n_test"]))
print("  AP candidat / champion : %s / %s" % (d["ap"]["candidat"], d["ap"]["champion"]))
print("  écart : %s   IC 95 %% : %s   → %s" % (d["delta_ap"], d["delta_ap_ci95"], d["verdict"]))
PY
read -r -d '' PY_VALID <<'PY'
import json, sys
d = json.loads(sys.stdin.read().split(" ", 1)[1])
g = d["global"]
print("  global : %s contre %s, écart %+.4f, IC %s" % (g["ap_candidat"], g["ap_champion"], g["ecart"], g["ic95"]))
# Le fichier est en ASCII : les accents et les signes ≥, – y sont devenus des « ? ».
fix = lambda t: t.replace("activit?", "activité").replace(" ? ", " ≥ ").replace("?", "–")
for s in d["segments"]:
    print("  %-28s écart %+.4f  IC %s  concluant=%s" % (fix(s["segment"]), s["ecart"], s["ic95"], s["concluant"]))
print("  segment le plus faible : %s" % fix(d["segment_le_plus_faible"]))
PY

# Reprise à une étape : on retrouve les tx_id publiés plus tôt.
if [ "$START" -gt 1 ] && [ -f "$STATE" ]; then . "$STATE"; fi

printf '%sDémo team3 — projet %s, région %s%s\n' "$B" "$PROJECT" "$REGION" "$N"
TOKEN=$(gcloud auth print-identity-token 2>/dev/null) || { echo "Lancer d'abord : gcloud auth login"; exit 1; }

# ── Léo : le service privé, la transaction en direct, la mémoire ─────────────────────────────

if etape 1 Léo "Le service est privé (TD2, TD3 compétence 1)"; then
  dire "Sans jeton : refusé par Cloud Run avant même d'atteindre le code."
  run "curl -s -o /dev/null -w 'HTTP %{http_code}\n' $URL/health"
  dire "Avec un jeton d'identité d'un des quatre membres de l'équipe :"
  run "curl -s -w '\nHTTP %{http_code}\n' -H \"Authorization: Bearer \$TOKEN\" $URL/health"
  dire "Qui sert le trafic : la révision du TD4 (100 %), et celle de la CI, taguée livraison, sans trafic."
  run "gcloud run services describe $TEAM-fraud-api --region $REGION --project $PROJECT --flatten='status.traffic[]' \
--format='table(status.traffic.revisionName,status.traffic.tag,status.traffic.percent)'"
  SERVING=$(gcloud run services describe "$TEAM-fraud-api" --region "$REGION" --project "$PROJECT" \
    --flatten='status.traffic[]' --format='value(status.traffic.revisionName,status.traffic.percent)' | awk '$2 == 100 {print $1}')
  run "gcloud run revisions describe $SERVING --region $REGION --project $PROJECT \
--format='value(spec.containers[0].image.basename(),spec.containers[0].env.filter(name=FEATURE_SOURCE))' | sed -E 's/(@sha256:.{12})[^[:space:]]*/\\1…/'"
  pause
fi

if etape 2 Léo "Une transaction publiée maintenant, suivie jusqu'au score"; then
  dire "On publie $TX_ID dans team3-demo ; Pub/Sub la pousse vers /pubsub avec le jeton de team3-push."
  MSG="{\"TX_ID\":\"$TX_ID\",\"TX_TS\":\"2026-10-02 10:00:00\",\"CUSTOMER_ID\":\"7697141589194972\",\"TERMINAL_ID\":\"73436130\",\"TX_AMOUNT\":90.33}"
  run "gcloud pubsub topics publish $TEAM-demo --project $PROJECT --message '$MSG'"
  echo "TX_ID=$TX_ID" > "$STATE"
  dire "Le service lit les compteurs J-1 à J-14 dans Firestore, score, écrit le log, puis répond 204."
  for _ in $(seq 1 15); do
    OUT=$(logs "resource.labels.service_name=\"$TEAM-fraud-api\" jsonPayload.tx_id=\"$TX_ID\"" json 5m)
    [ "$OUT" != "[]" ] && [ -n "$OUT" ] && break
    sleep 3
  done
  printf '%s$ gcloud logging read … jsonPayload.tx_id="%s"%s\n' "$C" "$TX_ID" "$N"
  echo "$OUT" | python3 -c "$PY_SCORED"
  dire "Choix de Léo : Firestore (13,9 / 38,3 ms) plutôt que BigQuery (370 / 758 ms) ou parquet (figé)."
  pause
fi

if etape 3 Léo "La mémoire : historique BigQuery et compteurs (TD4)"; then
  dire "Le flux ff-replay est écrit dans tx_history par un abonnement BigQuery, sans code."
  dire "Deux rejeux le 16/11 : chaque transaction y est deux fois (note du compte rendu TD4)."
  Q="SELECT COUNT(*) AS lignes, COUNT(DISTINCT TX_ID) AS transactions, COUNT(DISTINCT message_id) AS messages FROM \\\`$TEAM.tx_history\\\`"
  run "bq query --project_id=$PROJECT --location=$REGION --use_legacy_sql=false --format=pretty \"$Q\""
  dire "Octets lus avec puis sans le filtre de partition (estimation, rien n'est facturé) :"
  run "bq query --project_id=$PROJECT --location=$REGION --use_legacy_sql=false --dry_run \"$Q WHERE TX_TS >= TIMESTAMP '2026-10-01'\" | tail -1"
  run "bq query --project_id=$PROJECT --location=$REGION --use_legacy_sql=false --dry_run \"$Q\" | tail -1"
  dire "Une seule partition (1er octobre) : le filtre n'écarte rien et lit TX_TS en plus."
  dire "check.sql : nos compteurs égaux à ceux de référence, sans doublon ni fuite. Attendu : 0 et 0."
  run "sed 's/team1\\./$TEAM./g' docs/seance-4/check.sql | bq query --project_id=$PROJECT \
--location=$REGION --use_legacy_sql=false --format=pretty"
  pause
fi

# ── Pierre : le push authentifié et la file de messages morts ────────────────────────────────

if etape 4 Pierre "Un message empoisonné, publié maintenant (TD3)"; then
  dire "TX_AMOUNT = -1 : le service le refuse. On le relira dans la file de messages morts à l'étape 6."
  MSG="{\"TX_ID\":\"$POISON_ID\",\"TX_TS\":\"2026-10-02 10:00:00\",\"CUSTOMER_ID\":\"7697141589194972\",\"TERMINAL_ID\":\"73436130\",\"TX_AMOUNT\":-1}"
  run "gcloud pubsub topics publish $TEAM-demo --project $PROJECT --message '$MSG'"
  echo "POISON_ID=$POISON_ID" >> "$STATE"
  echo "POISON_AT=$(date +%s)" >> "$STATE"
  POISON_AT=$(date +%s)
  dire "Pendant ce temps : la livraison. Endpoint, identité, relivraison, lettre morte."
  run "gcloud pubsub subscriptions describe $TEAM-tx-push --project $PROJECT \
--format='yaml(topic,pushConfig.pushEndpoint,pushConfig.oidcToken.serviceAccountEmail,ackDeadlineSeconds,retryPolicy,deadLetterPolicy)'"
  dire "team3-push n'a qu'un droit : appeler ce service."
  run "gcloud run services get-iam-policy $TEAM-fraud-api --region $REGION --project $PROJECT \
--flatten=bindings --format='table(bindings.role,bindings.members)'"
  dire "Le service répond 204 seulement après avoir scoré et écrit le log : un échec avant, et Pub/Sub relivre."
  pause
fi

if etape 5 Pierre "Les tentatives du message empoisonné"; then
  dire "Chaque refus est relivré, de 10 à 60 s plus tard ; delivery_attempt augmente."
  FILTRE="resource.labels.service_name=\"$TEAM-fraud-api\" jsonPayload.tx_id=\"${POISON_ID:-}\""
  for _ in $(seq 1 10); do   # les logs arrivent avec quelques secondes de retard
    [ -n "$(logs "$FILTRE" 'value(timestamp)')" ] && break; sleep 3
  done
  run "logs '$FILTRE' 'table(timestamp.date(\"%H:%M:%S\"):label=HEURE,jsonPayload.message,jsonPayload.delivery_attempt:label=TENTATIVE)'"
  pause
fi

if etape 6 Pierre "Le message dans la file de messages morts"; then
  dire "Après 5 tentatives, Pub/Sub le déplace dans team3-tx-dead. On l'attend (≈ 1 min 45 au total)."
  printf '%s$ gcloud pubsub subscriptions pull %s-tx-dead-pull …%s\n' "$C" "$TEAM" "$N"
  ACK=""
  for _ in $(seq 1 30); do
    ACK=$(gcloud pubsub subscriptions pull "$TEAM-tx-dead-pull" --project "$PROJECT" --limit 20 --format=json \
      | POISON_ID="${POISON_ID:-}" POISON_AT="${POISON_AT:-0}" python3 -c "$PY_DEAD")
    [ -n "$ACK" ] && break
    printf '.'; sleep 6
  done
  if [ -n "$ACK" ]; then
    gcloud pubsub subscriptions ack "$TEAM-tx-dead-pull" --project "$PROJECT" --ack-ids "$ACK" >/dev/null 2>&1
    dire "Acquitté : la file reste vide pour la prochaine démo."
  else
    dire "Pas encore arrivé : montrer le tx_id du TD3, poison-20261116 (17:57:46 → 17:59:21, 5 livraisons)."
  fi
  dire "Charge du 16/11 : suivi jusqu'à ≈ 530 msg/s ; au-delà, file à 81 038 messages, vidée en 2 min, aucune perte."
  pause
fi

# ── Nicolas : réentraîner, chercher en parallèle, décider ────────────────────────────────────

if etape 7 Nicolas "La recherche à 1, 4 et 8 workers, puis la décision (TD5)"; then
  dire "Même étude (40 essais) à 1, 4 et 8 tâches Cloud Run : 1 584 s, 448 s, 266 s."
  run "gcloud run jobs executions list --job $TEAM-train --region $REGION --project $PROJECT --limit 7 \
--format='table(name,spec.taskCount:label=TACHES,status.startTime.date(\"%d/%m %H:%M\"):label=DEBUT,status.completionTime.date(\"%H:%M:%S\"):label=FIN)'"
  dire "Le fichier de décision : la règle écrite, le test lu une seule fois, le verdict."
  run "gcloud storage cat $DECISION | python3 -c \"\$PY_DECISION\""
  dire "Le registre : la version 2 est entrée, puis est devenue champion."
  run "gcloud ai models list-version $MODEL_ID --region $REGION --project $PROJECT \
--format='table(versionId,versionAliases.list(),versionCreateTime.date(\"%d/%m %H:%M\"))' 2>/dev/null"
  pause
fi

# ── Richard : valider, mettre en service par paliers, la panne ───────────────────────────────

if etape 8 Richard "Valider sur les segments et en ombre, avant tout trafic (TD6)"; then
  dire "validation.txt : le verdict regarde chaque segment, pas seulement la moyenne."
  run "python3 -c \"\$PY_VALID\" < docs/seance-6/validation.txt"
  dire "Ombre (20/11) : 4 773 transactions communes, désaccord 4,34 %, p95 2,32 ms contre 2,58 ms."
  dire "Le trafic de team3-scorer aujourd'hui (lecture seule) :"
  run "gcloud run services describe $TEAM-scorer --region $REGION --project $PROJECT --flatten='status.traffic[]' \
--format='table(status.traffic.revisionName,status.traffic.tag,status.traffic.percent)'"
  pause
fi

if etape 9 Richard "La panne de la version next, et le retour"; then
  dire "Paliers 10 / 50 / 100 % : 0 % d'erreur. Puis next à 10 % : 100 % d'erreurs, /health toujours à 200."
  run "logs 'resource.labels.service_name=\"$TEAM-scorer\" jsonPayload.error:\"Feature shape mismatch\"' \
'value(timestamp.date(\"%d/%m %H:%M:%S\"),resource.labels.revision_name,jsonPayload.error)' 10d | head -3"
  dire "Cause : le modèle attend 22 features, le service en envoie 20. Retour vers candidate : 0 % d'erreur, p95 2,1 ms."
  pause
fi

# ── Fin : ce que l'incident a changé ─────────────────────────────────────────────────────────

if etape 10 "Pierre ou Léo" "Ce que la panne a changé : l'alerte et le test de fumée, en code"; then
  dire "L'alerte qui aurait vu la panne : plus de 10 échecs par minute et par révision pendant 60 s."
  run "gcloud monitoring policies describe $ALERT \
--format='value(displayName,enabled,conditions[0].conditionThreshold.thresholdValue,conditions[0].conditionThreshold.duration)'"
  dire "Le test de fumée bloquant : avec le modèle next, le workflow s'arrête avant tout trafic."
  run "gh run view 45189954111 -R $APP_REPO --json conclusion,createdAt,jobs \
--jq '\"  \" + .conclusion + \"  \" + .createdAt + \"  étape en échec : \" + ([.jobs[].steps[]|select(.conclusion==\"failure\")|.name]|join(\", \"))'"
  run "gh run view 45190412288 -R $APP_REPO --json conclusion,createdAt --jq '\"  \" + .conclusion + \"  \" + .createdAt'"
  dire "Terraform décrit l'infrastructure, la CI choisit la version : le plan ne voit aucun écart."
  run "terraform -chdir=infra plan -no-color 2>&1 | grep -E 'No changes|Plan:'"
  pause
fi

printf '\n%sFin de la démo.%s Limites : docs/soutenance.md, section 6.\n' "$B" "$N"
