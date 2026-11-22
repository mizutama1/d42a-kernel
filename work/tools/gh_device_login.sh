#!/usr/bin/env bash
# GitHub device-flow login (no browser automation, token kept local)
# 使い方: nohup bash gh_device_login.sh > /dev/null 2>&1 &
set -u
CLIENT_ID="178c6fc778ccc68e1d6a"   # GitHub CLI の公開 client_id
SCOPE="repo workflow"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_FILE="$DIR/device_code.txt"
TOKEN_FILE="$HOME/.d42a_gh_token"
POLL_LOG="$DIR/device_poll.log"

: > "$POLL_LOG"
: > "$CODE_FILE"

resp="$(curl -sS -X POST https://github.com/login/device/code \
  -H "Accept: application/json" \
  -d "client_id=$CLIENT_ID" -d "scope=$SCOPE")"
echo "device-code-response: $resp" >> "$POLL_LOG"

device_code="$(printf '%s' "$resp" | python -c "import sys,json;print(json.load(sys.stdin).get('device_code',''))")"
user_code="$(printf '%s' "$resp" | python -c "import sys,json;print(json.load(sys.stdin).get('user_code',''))")"
verif_uri="$(printf '%s' "$resp" | python -c "import sys,json;print(json.load(sys.stdin).get('verification_uri',''))")"
interval="$(printf '%s' "$resp" | python -c "import sys,json;print(json.load(sys.stdin).get('interval',5))")"

if [ -z "$device_code" ] || [ -z "$user_code" ]; then
  echo "ERROR: device code を取得できませんでした" >> "$POLL_LOG"
  exit 1
fi

printf 'URL=%s\nCODE=%s\nSTARTED=%s\n' "$verif_uri" "$user_code" "$(date -Iseconds)" > "$CODE_FILE"

for i in $(seq 1 180); do
  sleep "$interval"
  r="$(curl -sS -X POST https://github.com/login/oauth/access_token \
    -H "Accept: application/json" \
    -d "client_id=$CLIENT_ID" -d "device_code=$device_code" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:device_code")"
  err="$(printf '%s' "$r" | python -c "import sys,json;print(json.load(sys.stdin).get('error',''))" 2>/dev/null)"
  if [ -z "$err" ]; then
    printf '%s' "$r" | python -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE" 2>/dev/null || true
    echo "OK $(date -Iseconds)" >> "$POLL_LOG"
    printf 'URL=%s\nCODE=%s\nDONE=%s\n' "$verif_uri" "$user_code" "$(date -Iseconds)" > "$CODE_FILE"
    exit 0
  fi
  echo "$(date -Iseconds) poll: $err" >> "$POLL_LOG"
  if [ "$err" = "slow_down" ]; then interval=$((interval + 5)); fi
  if [ "$err" = "expired_token" ] || [ "$err" = "access_denied" ]; then
    echo "FAILED $err" >> "$POLL_LOG"
    printf 'URL=%s\nCODE=%s\nFAILED=%s\n' "$verif_uri" "$user_code" "$err" > "$CODE_FILE"
    exit 2
  fi
done
echo "TIMEOUT" >> "$POLL_LOG"
exit 3
