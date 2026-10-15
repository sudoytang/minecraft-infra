#!/bin/bash
# Post a failure notice to the Grok Bot routine webhook.
# Env (from /etc/minecraft-notify.env):
#   WEBHOOK_URL  — required
#   WEBHOOK_KEY  — optional; sent as Authorization: Bearer <key> and X-Webhook-Key
set -u

UNIT="${MONITOR_UNIT:-unknown}"
HOST="$(hostname -f 2>/dev/null || hostname)"
WHEN="$(date -Is)"

log_err() { printf '%s\n' "$*" >&2; }

if [[ -z "${WEBHOOK_URL:-}" ]]; then
  log_err "minecraft-notify-failure: WEBHOOK_URL unset; skip notify for unit=${UNIT}"
  exit 0
fi

SNIPPET="$(journalctl -u "$UNIT" -n 30 --no-pager -o short-iso 2>/dev/null || true)"
# Keep payload small for webhook limits
if ((${#SNIPPET} > 3500)); then
  SNIPPET="${SNIPPET: -3500}"
  SNIPPET="…[truncated]…"$'\n'"$SNIPPET"
fi

# JSON-escape via python3 (available on Debian)
PAYLOAD="$(UNIT="$UNIT" HOST="$HOST" WHEN="$WHEN" SNIPPET="$SNIPPET" python3 - << 'PY'
import json, os
print(json.dumps({
    "event": "systemd_onfailure",
    "hostname": os.environ.get("HOST", ""),
    "unit": os.environ.get("UNIT", ""),
    "time": os.environ.get("WHEN", ""),
    "journal_snippet": os.environ.get("SNIPPET", ""),
}, ensure_ascii=False))
PY
)"

auth_args=()
if [[ -n "${WEBHOOK_KEY:-}" ]]; then
  auth_args+=(-H "Authorization: Bearer ${WEBHOOK_KEY}" -H "X-Webhook-Key: ${WEBHOOK_KEY}")
fi

post_once() {
  curl -fsS -X POST \
    -H "Content-Type: application/json" \
    "${auth_args[@]}" \
    --data "$PAYLOAD" \
    --max-time 20 \
    "$WEBHOOK_URL"
}

if ! post_once; then
  log_err "minecraft-notify-failure: curl failed for unit=${UNIT}; retrying once"
  sleep 2
  if ! post_once; then
    log_err "minecraft-notify-failure: curl failed again for unit=${UNIT}; giving up (exit 0)"
  fi
fi

exit 0
