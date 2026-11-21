#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TOKEN=""
HOSTNAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token) TOKEN="${2:-}"; shift 2 ;;
    --hostname) HOSTNAME="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

ENV_FILE="$REPO_ROOT/tunnel/cloudflared.env"

if [[ -n "$TOKEN" ]]; then
  mkdir -p "$REPO_ROOT/tunnel"
  {
    echo "CLOUDFLARE_TUNNEL_TOKEN=$TOKEN"
    [[ -n "$HOSTNAME" ]] && echo "CLOUDFLARE_TUNNEL_HOSTNAME=$HOSTNAME"
  } > "$ENV_FILE"
  echo "Saved Named Tunnel settings to tunnel/cloudflared.env (gitignored)."
fi

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  TOKEN="${TOKEN:-${CLOUDFLARE_TUNNEL_TOKEN:-}}"
  HOSTNAME="${HOSTNAME:-${CLOUDFLARE_TUNNEL_HOSTNAME:-}}"
fi

if [[ -n "$TOKEN" ]]; then
  export CLOUDFLARE_TUNNEL_TOKEN="$TOKEN"
  export CLOUDFLARED_TUNNEL_ARGS="run"
  echo "Starting CPMS stack + Cloudflare Named Tunnel..."
else
  export CLOUDFLARE_TUNNEL_TOKEN=""
  export CLOUDFLARED_TUNNEL_ARGS="--url http://backend:8001"
  echo "Starting CPMS stack + Cloudflare Quick Tunnel (temporary URL)..."
fi

docker compose --profile tunnel up -d --build

PUBLIC_URL=""
if [[ -n "$TOKEN" ]]; then
  if [[ -n "$HOSTNAME" ]]; then
    PUBLIC_URL="https://${HOSTNAME#https://}"
    PUBLIC_URL="${PUBLIC_URL#http://}"
  else
    PUBLIC_URL="https://<your-cloudflare-cpms-hostname>"
  fi
else
  echo "Waiting for Quick Tunnel URL from cpms_cloudflared..."
  for _ in $(seq 1 30); do
    PUBLIC_URL="$(docker logs cpms_cloudflared 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -n 1 || true)"
    [[ -n "$PUBLIC_URL" ]] && break
    sleep 1
  done
fi

echo ""
echo "============================================================"
echo " CPMS Backend Online URL:"
if [[ -n "$PUBLIC_URL" ]]; then
  echo "   $PUBLIC_URL"
  echo ""
  echo " Run CPMS Flutter app from ANY computer:"
  echo "   cd flutter"
  echo "   flutter run -d macos   --dart-define=API_BASE_URL=${PUBLIC_URL}/api/v1"
  echo "   flutter run -d windows --dart-define=API_BASE_URL=${PUBLIC_URL}/api/v1"
  echo "   flutter run -d chrome  --dart-define=API_BASE_URL=${PUBLIC_URL}/api/v1"
else
  echo "   (Timed out waiting for URL; run 'docker logs cpms_cloudflared')"
fi
echo "============================================================"
echo ""
echo "Checking CPMS -> POS connection (manage.py check_pos)..."
docker compose exec backend python manage.py check_pos
