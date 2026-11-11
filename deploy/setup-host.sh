#!/usr/bin/env bash
# Deploy ideationmax.com next to PolyDial on a host that already runs nginx + certbot.
# Run from the project root on the server:   sudo ./deploy/setup-host.sh
# Safe to re-run: it rebuilds the container and only touches ideationmax.com's own nginx file.
set -euo pipefail

DOMAIN="ideationmax.com"
DOMAINS=(-d ideationmax.com -d www.ideationmax.com)
PORT="${PORT:-8081}"
CONF_SRC="$(cd "$(dirname "$0")" && pwd)/ideationmax.com.conf"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run with sudo."
cd "$(dirname "$0")/.."

for bin in docker nginx certbot; do
  command -v "$bin" >/dev/null || fail "'$bin' is not installed on this server."
done
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 ('docker compose') is required."

# 1. Port check: 8081 must be free, or already ours
say "Checking port $PORT"
if ss -tln | grep -qE "127\.0\.0\.1:$PORT |0\.0\.0\.0:$PORT |\[::\]:$PORT |\*:$PORT "; then
  if ! docker ps --format '{{.Names}} {{.Ports}}' | grep -q "^ideationmax-web .*:$PORT->"; then
    fail "Port $PORT is used by something else. Re-run with another port, e.g.: sudo PORT=8082 ./deploy/setup-host.sh"
  fi
fi

# 2. Build and start the site container
say "Building and starting the ideationmax-web container"
PORT="$PORT" docker compose up -d --build
for i in {1..15}; do
  curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 && break
  sleep 1
  [[ $i -eq 15 ]] && fail "Container did not become healthy. Check: docker logs ideationmax-web"
done
echo "Container is up on 127.0.0.1:$PORT"

# 3. Install the nginx site (Debian/Ubuntu sites-enabled, or conf.d on Amazon Linux/RHEL)
say "Installing nginx config for $DOMAIN"
if [[ -d /etc/nginx/sites-available ]]; then
  TARGET=/etc/nginx/sites-available/$DOMAIN
  LINK=/etc/nginx/sites-enabled/$DOMAIN
else
  TARGET=/etc/nginx/conf.d/$DOMAIN.conf
  LINK=""
fi

if [[ -f "$TARGET" ]] && grep -q "managed by Certbot" "$TARGET"; then
  echo "$TARGET already has HTTPS from certbot; leaving it as is (only the upstream port is updated)."
  sed -i "s|server 127.0.0.1:[0-9]*;|server 127.0.0.1:$PORT;|" "$TARGET"
else
  [[ -f "$TARGET" ]] && cp "$TARGET" "$TARGET.bak.$(date +%s)"
  sed "s|server 127.0.0.1:8081;|server 127.0.0.1:$PORT;|" "$CONF_SRC" > "$TARGET"
fi
[[ -n "$LINK" ]] && ln -sf "$TARGET" "$LINK"

nginx -t || fail "nginx config test failed; nothing was reloaded. PolyDial is unaffected."
systemctl reload nginx
echo "nginx reloaded"

# 4. DNS check before asking Let's Encrypt for a certificate
say "Checking DNS"
SERVER_IP="$(curl -fsS --max-time 5 https://checkip.amazonaws.com || true)"
DNS_OK=1
for name in ideationmax.com www.ideationmax.com; do
  resolved="$(getent ahostsv4 "$name" | awk 'NR==1{print $1}')"
  printf '  %-22s -> %-16s (this server: %s)\n' "$name" "${resolved:-not found}" "${SERVER_IP:-unknown}"
  [[ -n "$SERVER_IP" && "$resolved" != "$SERVER_IP" ]] && DNS_OK=0
done
if [[ $DNS_OK -eq 0 ]]; then
  fail "DNS does not point at this server yet. Update the A records, wait for them to propagate, then re-run this script."
fi

# 5. HTTPS certificate (reuses the certbot account already set up for PolyDial)
say "Requesting HTTPS certificate"
certbot --nginx "${DOMAINS[@]}" --redirect --non-interactive --keep-until-expiring

nginx -t && systemctl reload nginx

say "Done"
echo "https://ideationmax.com is live. Certificate renewal is handled by certbot's existing timer, same as PolyDial."
