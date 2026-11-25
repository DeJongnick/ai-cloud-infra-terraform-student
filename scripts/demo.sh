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
#   DEMO_PAGES=1 scripts/demo.sh # ouvre aussi, à chaque étape, les pages de la console et de GitHub
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
  pages "$1"
  return 0
}
dire() { printf '%s  » %s%s\n' "$G" "$*" "$N"; }
run()  { printf '%s$ %s%s\n' "$C" "$*" "$N"; eval "$@"; }
# Pages ouvertes dans le navigateur par défaut, seulement avec DEMO_PAGES=1. Lecture seule.
CONSOLE=https://console.cloud.google.com
GH=https://github.com
TF_REPO=DeJongnick/ai-cloud-infra-terraform-student
DASHBOARD=f9c7ae47-5c46-4cbb-bfa0-46fd30787c1d
R16='startTime=2026-11-16T17:00:00Z&endTime=2026-11-16T17:15:00Z'   # montée en charge, 18:00-18:15 Paris
R20='startTime=2026-11-20T12:20:00Z&endTime=2026-11-20T12:45:00Z'   # paliers et panne, 13:20-13:45 Paris
logs_url() { # filtre, plage (;duration=PT15M ou ;timeRange=début%2Ffin)
  printf '%s/logs/query;query=%s%s?project=%s' "$CONSOLE" "$(python3 -c \
    'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' \
    "resource.type=\"cloud_run_revision\" $1")" "$2" "$PROJECT"
}
pages_de() { # numéro d'étape → lignes « libellé|adresse »
  case $1 in
  1) echo "Cloud Run: team3-fraud-api revisions|$CONSOLE/run/detail/$REGION/$TEAM-fraud-api/revisions?project=$PROJECT" ;;
  2) echo "Logs Explorer: the scored line of $TX_ID (click Run query once it is published)|$(logs_url \
       "resource.labels.service_name=\"$TEAM-fraud-api\" jsonPayload.tx_id=\"$TX_ID\"" ';duration=PT15M')"
     echo "Firestore: the customer counters read at scoring time|$CONSOLE/firestore/databases/$TEAM/data/panel/customers/7697141589194972?project=$PROJECT" ;;
  3) echo "BigQuery: table team3.tx_history (Details tab: TX_TS partitioning)|$CONSOLE/bigquery?project=$PROJECT&ws=!1m5!1m4!4m3!1s$PROJECT!2s$TEAM!3stx_history" ;;
  4) echo "Pub/Sub: team3-tx-push subscription|$CONSOLE/cloudpubsub/subscription/detail/$TEAM-tx-push?project=$PROJECT" ;;
  5) echo "Logs Explorer: delivery attempts of the poison message|$(logs_url \
       "resource.labels.service_name=\"$TEAM-fraud-api\" jsonPayload.tx_id=\"${POISON_ID:-}\"" ';duration=PT15M')" ;;
  6) echo "Pub/Sub: team3-tx-push metrics on 16 Nov (the backlog builds up, then drains)|$CONSOLE/cloudpubsub/subscription/detail/$TEAM-tx-push?project=$PROJECT&tab=metrics&$R16"
     echo "Cloud Run: team3-fraud-api metrics on 16 Nov (capped at 3 instances)|$CONSOLE/run/detail/$REGION/$TEAM-fraud-api/metrics?project=$PROJECT&$R16" ;;
  7) echo "Cloud Run Jobs: team3-train executions|$CONSOLE/run/jobs/details/$REGION/$TEAM-train/executions?project=$PROJECT"
     echo "Speed-up curve (TD5)|$GH/$TF_REPO/blob/main/docs/seance-5/acceleration.png"
     echo "Vertex AI: fraud-scorer-team3 registry|$CONSOLE/vertex-ai/models/locations/$REGION/models/$MODEL_ID?project=$PROJECT" ;;
  8) echo "Cloud Run: team3-scorer revisions and traffic|$CONSOLE/run/detail/$REGION/$TEAM-scorer/revisions?project=$PROJECT" ;;
  9) echo "Monitoring: TD6 team3 dashboard, 20 Nov 13:20-13:45|$CONSOLE/monitoring/dashboards/builder/$DASHBOARD?project=$PROJECT&$R20"
     echo "Logs Explorer: Feature shape mismatch, 20 Nov|$(logs_url \
       "resource.labels.service_name=\"$TEAM-scorer\" jsonPayload.error:\"Feature shape mismatch\"" \
       ';timeRange=2026-11-20T12:20:00Z%2F2026-11-20T12:45:00Z')" ;;
  10) echo "Monitoring: team3-scorer-release alert policy|$CONSOLE/monitoring/alerting/policies/${ALERT##*/}?project=$PROJECT"
      echo "GitHub Actions: release failing on the smoke test|$GH/$APP_REPO/actions/runs/45189954111"
      echo "GitHub Actions: release succeeding|$GH/$APP_REPO/actions/runs/45190412288" ;;
  esac
}
# Chrome, piloté par AppleScript : on ouvre les onglets de l'étape dans la fenêtre au premier plan,
# on affiche le premier, puis on ferme ceux de l'étape précédente (par leur identifiant : les
# autres onglets ne sont pas touchés). Sans macOS, on ouvre seulement, sans fermer.
OUVERTS=""
read -r -d '' AS_OUVRIR <<'AS'
on run argv
  set ids to {}
  tell application "Google Chrome"
    if (count of windows) = 0 then make new window
    tell front window
      set premier to (count of tabs) + 1
      repeat with u in argv
        set t to make new tab with properties {URL:(u as text)}
        set end of ids to (id of t as text)
      end repeat
      if (count of argv) > 0 then set active tab index to premier
    end tell
    activate
  end tell
  set AppleScript's text item delimiters to " "
  return ids as text
end run
AS
read -r -d '' AS_FERMER <<'AS'
on run argv
  tell application "Google Chrome"
    repeat with w in windows
      repeat with i from (count of tabs of w) to 1 by -1
        if ((id of tab i of w) as text) is in argv then close tab i of w
      end repeat
    end repeat
  end tell
end run
AS
pages() { # numéro d'étape
  [ "${DEMO_PAGES:-0}" = 1 ] || return 0
  local lignes adresses=() libelle adresse
  lignes=$(pages_de "$1")
  while IFS='|' read -r libelle adresse; do
    [ -n "$adresse" ] || continue
    printf '%s  ↗ %s%s\n' "$C" "$libelle" "$N"
    adresses+=("$adresse")
  done <<< "$lignes"
  if ! command -v osascript >/dev/null 2>&1; then
    for adresse in "${adresses[@]}"; do xdg-open "$adresse" >/dev/null 2>&1 & done
    return 0
  fi
  local nouveaux
  nouveaux=$(osascript -e "$AS_OUVRIR" "${adresses[@]}")
  # shellcheck disable=SC2086  # liste d'identifiants séparés par des espaces
  [ -z "$OUVERTS" ] || osascript -e "$AS_FERMER" $OUVERTS >/dev/null
  OUVERTS=$nouveaux
}
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
        print("  tx_id read: %s" % json.loads(data)["TX_ID"], file=err)
        print("  source subscription: %s" % a.get("CloudPubSubDeadLetterSourceSubscription", "?"), file=err)
        print("  delivery attempts: %s" % a.get("CloudPubSubDeadLetterSourceDeliveryCount", "?"), file=err)
        t0 = int(os.environ["POISON_AT"])
        if t0:
            print("  arrived %d s after publishing" % (int(time.time()) - t0), file=err)
        print(m["ackId"])
PY
read -r -d '' PY_DECISION <<'PY'
import json, sys
d = json.load(sys.stdin)
r = d["regle"]
print("  rule: lower bound of the 95 %% CI of (AP candidate - AP champion) > margin (margin %s, %s bootstrap draws)"
      % (r["margin"], r["bootstrap"]))
print("  times the test set was read: %s   n_test: %s" % (d["rang_lecture_test"], d["n_test"]))
print("  AP candidate / champion: %s / %s" % (d["ap"]["candidat"], d["ap"]["champion"]))
verdict = {"accepté": "accepted", "refusé": "rejected"}.get(d["verdict"], d["verdict"])
print("  delta: %s   95 %% CI: %s   → %s" % (d["delta_ap"], d["delta_ap_ci95"], verdict))
PY
read -r -d '' PY_VALID <<'PY'
import json, sys
d = json.loads(sys.stdin.read().split(" ", 1)[1])
g = d["global"]
print("  overall: %s vs %s, delta %+.4f, CI %s" % (g["ap_candidat"], g["ap_champion"], g["ecart"], g["ic95"]))
# Le fichier est en ASCII : les accents et les signes ≥, – y sont devenus des « ? ».
fix = lambda t: (t.replace("activit? client 7 j", "customer activity 7 d").replace("montant", "amount")
                 .replace(" ? ", " ≥ ").replace("?", "–"))
for s in d["segments"]:
    print("  %-28s delta %+.4f  CI %s  conclusive=%s" % (fix(s["segment"]), s["ecart"], s["ic95"], s["concluant"]))
print("  weakest segment: %s" % fix(d["segment_le_plus_faible"]))
PY

# Reprise à une étape : on retrouve les tx_id publiés plus tôt.
if [ "$START" -gt 1 ] && [ -f "$STATE" ]; then . "$STATE"; fi

printf '%steam3 demo — project %s, region %s%s\n' "$B" "$PROJECT" "$REGION" "$N"
TOKEN=$(gcloud auth print-identity-token 2>/dev/null) || { echo "Run this first: gcloud auth login"; exit 1; }

# ── Léo : le service privé, la transaction en direct, la mémoire ─────────────────────────────

if etape 1 Léo "The service is private (TD2, TD3 skill 1)"; then
  dire "Without a token: Cloud Run rejects the call before it even reaches our code."
  run "curl -s -o /dev/null -w 'HTTP %{http_code}\n' $URL/health"
  dire "With an identity token from one of the four team members:"
  run "curl -s -w '\nHTTP %{http_code}\n' -H \"Authorization: Bearer \$TOKEN\" $URL/health"
  dire "Who serves traffic: the TD4 revision (100 %), plus the CI revision, tagged livraison, with no traffic."
  run "gcloud run services describe $TEAM-fraud-api --region $REGION --project $PROJECT --flatten='status.traffic[]' \
--format='table(status.traffic.revisionName,status.traffic.tag,status.traffic.percent)'"
  SERVING=$(gcloud run services describe "$TEAM-fraud-api" --region "$REGION" --project "$PROJECT" \
    --flatten='status.traffic[]' --format='value(status.traffic.revisionName,status.traffic.percent)' | awk '$2 == 100 {print $1}')
  run "gcloud run revisions describe $SERVING --region $REGION --project $PROJECT \
--format='value(spec.containers[0].image.basename(),spec.containers[0].env.filter(name=FEATURE_SOURCE))' | sed -E 's/(@sha256:.{12})[^[:space:]]*/\\1…/'"
  pause
fi

if etape 2 Léo "A transaction published now, followed all the way to its score"; then
  dire "We publish $TX_ID to team3-demo; Pub/Sub pushes it to /pubsub with a team3-push token."
  MSG="{\"TX_ID\":\"$TX_ID\",\"TX_TS\":\"2026-10-02 10:00:00\",\"CUSTOMER_ID\":\"7697141589194972\",\"TERMINAL_ID\":\"73436130\",\"TX_AMOUNT\":90.33}"
  run "gcloud pubsub topics publish $TEAM-demo --project $PROJECT --message '$MSG'"
  echo "TX_ID=$TX_ID" > "$STATE"
  dire "The service reads the D-1 to D-14 counters from Firestore, scores, writes the log, then returns 204."
  for _ in $(seq 1 15); do
    OUT=$(logs "resource.labels.service_name=\"$TEAM-fraud-api\" jsonPayload.tx_id=\"$TX_ID\"" json 5m)
    [ "$OUT" != "[]" ] && [ -n "$OUT" ] && break
    sleep 3
  done
  printf '%s$ gcloud logging read … jsonPayload.tx_id="%s"%s\n' "$C" "$TX_ID" "$N"
  echo "$OUT" | python3 -c "$PY_SCORED"
  dire "Léo's choice: Firestore (13.9 / 38.3 ms, p50 / p99) over BigQuery (370 / 758 ms) or parquet (frozen)."
  pause
fi

if etape 3 Léo "The memory: BigQuery history and counters (TD4)"; then
  dire "The ff-replay stream is written to tx_history by a BigQuery subscription, with no code."
  dire "Two replays on 16 Nov: every transaction is in there twice (see the note in the TD4 report)."
  Q="SELECT COUNT(*) AS lignes, COUNT(DISTINCT TX_ID) AS transactions, COUNT(DISTINCT message_id) AS messages FROM \\\`$TEAM.tx_history\\\`"
  run "bq query --project_id=$PROJECT --location=$REGION --use_legacy_sql=false --format=pretty \"$Q\""
  dire "Bytes read with, then without, the partition filter (dry run, nothing is billed):"
  run "bq query --project_id=$PROJECT --location=$REGION --use_legacy_sql=false --dry_run \"$Q WHERE TX_TS >= TIMESTAMP '2026-10-01'\" | tail -1"
  run "bq query --project_id=$PROJECT --location=$REGION --use_legacy_sql=false --dry_run \"$Q\" | tail -1"
  dire "A single partition (1 October): the filter prunes nothing and reads TX_TS on top."
  dire "check.sql: our counters match the reference ones, no duplicates, no leakage. Expected: 0 and 0."
  run "sed 's/team1\\./$TEAM./g' docs/seance-4/check.sql | bq query --project_id=$PROJECT \
--location=$REGION --use_legacy_sql=false --format=pretty"
  pause
fi

# ── Pierre : le push authentifié et la file de messages morts ────────────────────────────────

if etape 4 Pierre "A poison message, published now (TD3)"; then
  dire "TX_AMOUNT = -1: the service rejects it. We will read it back from the dead-letter queue in step 6."
  MSG="{\"TX_ID\":\"$POISON_ID\",\"TX_TS\":\"2026-10-02 10:00:00\",\"CUSTOMER_ID\":\"7697141589194972\",\"TERMINAL_ID\":\"73436130\",\"TX_AMOUNT\":-1}"
  run "gcloud pubsub topics publish $TEAM-demo --project $PROJECT --message '$MSG'"
  echo "POISON_ID=$POISON_ID" >> "$STATE"
  echo "POISON_AT=$(date +%s)" >> "$STATE"
  POISON_AT=$(date +%s)
  dire "Meanwhile, the delivery setup: endpoint, identity, retries, dead letter."
  run "gcloud pubsub subscriptions describe $TEAM-tx-push --project $PROJECT \
--format='yaml(topic,pushConfig.pushEndpoint,pushConfig.oidcToken.serviceAccountEmail,ackDeadlineSeconds,retryPolicy,deadLetterPolicy)'"
  dire "team3-push has a single permission: invoking this service."
  run "gcloud run services get-iam-policy $TEAM-fraud-api --region $REGION --project $PROJECT \
--flatten=bindings --format='table(bindings.role,bindings.members)'"
  dire "The service returns 204 only after scoring and logging: any failure before that, and Pub/Sub redelivers."
  pause
fi

if etape 5 Pierre "Delivery attempts of the poison message"; then
  dire "Each rejection is redelivered 10 to 60 s later; delivery_attempt goes up."
  FILTRE="resource.labels.service_name=\"$TEAM-fraud-api\" jsonPayload.tx_id=\"${POISON_ID:-}\""
  for _ in $(seq 1 10); do   # les logs arrivent avec quelques secondes de retard
    [ -n "$(logs "$FILTRE" 'value(timestamp)')" ] && break; sleep 3
  done
  run "logs '$FILTRE' 'table(timestamp.date(\"%H:%M:%S\"):label=HEURE,jsonPayload.message,jsonPayload.delivery_attempt:label=TENTATIVE)'"
  pause
fi

if etape 6 Pierre "The message in the dead-letter queue"; then
  dire "After 5 attempts, Pub/Sub moves it to team3-tx-dead. We wait for it (≈ 1 min 45 s in total)."
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
    dire "Acknowledged: the queue stays empty for the next demo."
  else
    dire "Not there yet: show the TD3 one instead, poison-20261116 (17:57:46 → 17:59:21, 5 deliveries)."
  fi
  dire "Load test on 16 Nov: kept up to ≈ 530 msg/s; beyond that, a backlog of 81,038 messages, drained in 2 min, nothing lost."
  pause
fi

# ── Nicolas : réentraîner, chercher en parallèle, décider ────────────────────────────────────

if etape 7 Nicolas "The search with 1, 4 and 8 workers, then the decision (TD5)"; then
  dire "Same study (40 trials) with 1, 4 and 8 Cloud Run tasks: 1,584 s, 448 s, 266 s."
  run "gcloud run jobs executions list --job $TEAM-train --region $REGION --project $PROJECT --limit 7 \
--format='table(name,spec.taskCount:label=TACHES,status.startTime.date(\"%d/%m %H:%M\"):label=DEBUT,status.completionTime.date(\"%H:%M:%S\"):label=FIN)'"
  dire "The decision file: the written rule, the test set read only once, the verdict."
  run "gcloud storage cat $DECISION | python3 -c \"\$PY_DECISION\""
  dire "The registry: version 2 got in, then became champion."
  run "gcloud ai models list-version $MODEL_ID --region $REGION --project $PROJECT \
--format='table(versionId,versionAliases.list(),versionCreateTime.date(\"%d/%m %H:%M\"))' 2>/dev/null"
  pause
fi

# ── Richard : valider, mettre en service par paliers, la panne ───────────────────────────────

if etape 8 Richard "Validate on segments and in shadow, before any traffic (TD6)"; then
  dire "validation.txt: the verdict looks at every segment, not just the average."
  run "python3 -c \"\$PY_VALID\" < docs/seance-6/validation.txt"
  dire "Shadow (20 Nov): 4,773 shared transactions, 4.34 % disagreement, p95 2.32 ms vs 2.58 ms."
  dire "team3-scorer traffic today (read-only):"
  run "gcloud run services describe $TEAM-scorer --region $REGION --project $PROJECT --flatten='status.traffic[]' \
--format='table(status.traffic.revisionName,status.traffic.tag,status.traffic.percent)'"
  pause
fi

if etape 9 Richard "The next version outage, and the rollback"; then
  dire "Steps at 10 / 50 / 100 %: 0 % errors. Then next at 10 %: 100 % errors, while /health still returned 200."
  run "logs 'resource.labels.service_name=\"$TEAM-scorer\" jsonPayload.error:\"Feature shape mismatch\"' \
'value(timestamp.date(\"%d/%m %H:%M:%S\"),resource.labels.revision_name,jsonPayload.error)' 10d | head -3"
  dire "Root cause: the model expects 22 features, the service sends 20. Rolled back to candidate: 0 % errors, p95 2.1 ms."
  pause
fi

# ── Fin : ce que l'incident a changé ─────────────────────────────────────────────────────────

if etape 10 "Pierre or Léo" "What the outage changed: the alert and the smoke test, as code"; then
  dire "The alert that would have caught it: more than 10 failures per minute per revision for 60 s."
  run "gcloud monitoring policies describe $ALERT \
--format='value(displayName,enabled,conditions[0].conditionThreshold.thresholdValue,conditions[0].conditionThreshold.duration)'"
  dire "The blocking smoke test: with the next model, the workflow stops before any traffic."
  run "gh run view 45189954111 -R $APP_REPO --json conclusion,createdAt,jobs \
--jq '\"  \" + .conclusion + \"  \" + .createdAt + \"  étape en échec : \" + ([.jobs[].steps[]|select(.conclusion==\"failure\")|.name]|join(\", \"))'"
  run "gh run view 45190412288 -R $APP_REPO --json conclusion,createdAt --jq '\"  \" + .conclusion + \"  \" + .createdAt'"
  dire "Terraform describes the infrastructure, CI picks the version: the plan shows no drift."
  run "terraform -chdir=infra plan -no-color 2>&1 | grep -E 'No changes|Plan:'"
  pause
fi

printf '\n%sEnd of the demo.%s Limitations: docs/soutenance.md, section 6.\n' "$B" "$N"
