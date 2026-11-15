# CPMS backend — deployment & demo topology

How the Django backend (`django-backend/`) is run outside a developer's laptop.
Everything here is driven by environment variables; there is no code change
between dev and production except `DJANGO_DEBUG`.

---

## 1. Two modes, one switch

| | `DJANGO_DEBUG=True` (default) | `DJANGO_DEBUG=False` |
|---|---|---|
| `DJANGO_SECRET_KEY` | dev default accepted | **refused** if unset or still dev default |
| `DJANGO_ALLOWED_HOSTS` | `*` accepted | **refused** if `*` or empty |
| `CORS_ALLOW_ALL_ORIGINS` | `True` accepted | **refused** if true |
| Cookies | plain `http` OK | `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE` |
| HSTS | off | `SECURE_HSTS_SECONDS=31536000` (env-tunable) |
| Proxy TLS | ignored | `SECURE_PROXY_SSL_HEADER=('HTTP_X_FORWARDED_PROTO','https')` |

With `DJANGO_DEBUG=false` the settings module raises `ImproperlyConfigured` at
import time and lists **every** problem at once, so the container exits instead
of serving an open API. Proof lives in `config/tests_settings.py`.

> `SECURE_SSL_REDIRECT` is deliberately **not** enabled: the tunnel origin and
> the internal health probe (`/api/health/`) speak plain http, and a redirect
> would break both. TLS ends at Cloudflare.

Generation of the values you must supply:

```bash
python -c 'import secrets; print(secrets.token_urlsafe(64))'   # DJANGO_SECRET_KEY
python -c 'import secrets; print(secrets.token_urlsafe(24))'   # POSTGRES_PASSWORD
```

---

## 2. Demo topology (Cloudflare Quick Tunnel, no domain)

The Phase 5 demo runs with **no purchased domain and no inbound firewall
changes**: a Quick Tunnel publishes the local backend on a throwaway
`https://<random>.trycloudflare.com` host.

```
 Flutter desktop client  ──https──▶  Cloudflare edge (TLS terminated)
                                          │  https://<random>.trycloudflare.com
                                          ▼
                                    cloudflared (host or container)
                                          │  http://127.0.0.1:8001
                                          ▼
                        cpms_backend  (Django, DJANGO_DEBUG=False)
                                          │  sql
                                          ▼
                                    cpms_db (Postgres 15)

 cpms_pos_outbox ──http(s)──▶ POS API (Repo #1, host :8000 or its own tunnel)
```

Start the tunnel (host, no account needed):

```bash
cloudflared tunnel --url http://127.0.0.1:8001
```

Then set on the backend container:

```bash
DJANGO_DEBUG=False
DJANGO_SECRET_KEY=<generated>
DJANGO_ALLOWED_HOSTS=<random>.trycloudflare.com      # the printed host, no scheme
CORS_ALLOW_ALL_ORIGINS=False
CORS_ALLOWED_ORIGINS=https://<random>.trycloudflare.com
```

Notes and limits:

* The Quick Tunnel hostname changes on every restart — update
  `DJANGO_ALLOWED_HOSTS` and `CORS_ALLOWED_ORIGINS` (and the Flutter
  `--dart-define=API_BASE_URL=…`) at the same time.
* Cloudflare Quick Tunnels are **demo-only**: no uptime guarantee, no custom
  domain, the URL is public while it runs. Treat the demo data as public; do not
  load real customer records.
* Because the tunnel forwards `X-Forwarded-Proto: https`, the secure-cookie and
  CSRF checks work without extra configuration (see §1).

---

## 3. POS bridge (`POS_API_BASE_URL`)

The CPMS → POS client refuses an insecure origin unless you explicitly opt in:

| Situation | Configuration |
|---|---|
| POS is reachable over HTTPS (its own tunnel or real cert) | `POS_API_BASE_URL=https://pos.example.com` — nothing else needed |
| POS runs on the same host / LAN, plain http, **demo only** | `POS_API_BASE_URL=http://host.docker.internal:8000` **plus** `POS_API_ALLOW_INSECURE_LOCAL=True` |

The shipped default is `http://host.docker.internal:8000` with
`POS_API_ALLOW_INSECURE_LOCAL=False`, so an unconfigured deployment fails closed
(`PosConfigError`) rather than quietly sending credentials over plain http.

Bridge credentials come from `POS_API_SERVICE_USERNAME` /
`POS_API_SERVICE_PASSWORD` (the POS `CPMS Service` account). There is no static
`POS_API_TOKEN`.

### The outbox worker must be supervised

`manage.py run_pos_outbox` (loop mode) **exits** on an unusable POS
configuration, so something has to restart it:

* **docker-compose (default here):** service `pos_outbox` with
  `restart: unless-stopped`. The restart policy is the supervisor.
* **systemd** (bare-metal/host install):

  ```ini
  # /etc/systemd/system/cpms-pos-outbox.service
  [Unit]
  Description=CPMS POS outbox worker
  After=network-online.target

  [Service]
  WorkingDirectory=/srv/cpms/django-backend
  EnvironmentFile=/srv/cpms/django-backend/.env
  ExecStart=/srv/cpms/.venv/bin/python manage.py run_pos_outbox
  Restart=always
  RestartSec=30

  [Install]
  WantedBy=multi-user.target
  ```

* **cron alternative (`--once`):** one pass then exit, exit code is the answer:

  ```cron
  * * * * * cd /srv/cpms/django-backend && ./.venv/bin/python manage.py run_pos_outbox --once >> /var/log/cpms-outbox.log 2>&1
  ```

Job accounting: `pos-status/` reports `stale` when the last read-back is older
than `POS_STATUS_STALE_AFTER_SECONDS` (default 300) — a stopped worker shows up
there. Never run loop mode and the cron form against the same database at the
same time.

---

## 4. Backups before migrations

`docker-compose.yml` runs `manage.py migrate` on start, so a backup must exist
**before** the new image/container starts.

```bash
# 1. Dump (compressed custom format keeps indexes/sequences restorable)
docker exec cpms_db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc \
  > "cpms-$(date -u +%Y%m%dT%H%M%SZ).dump"

# 2. Verify the dump is readable before you migrate
pg_restore --list cpms-*.dump | head -20     # or: docker exec -i cpms_db pg_restore --list

# 3. Migrate
docker compose up -d backend

# 4. Restore if the migration must be rolled back
docker exec -i cpms_db pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists \
  < cpms-20260101T000000Z.dump
```

Also copy `private_media/` (project documents, report photos) — it is **not** in
the database dump. Schedule both (`cron` daily) and keep them off the demo host.

---

## 5. Never expose DEBUG

`DJANGO_DEBUG=True` on a reachable host leaks settings, SQL and tracebacks, and
turns on the wildcard-host/CORS convenience. Rules:

* Production/demo `.env` starts from `django-backend/.env.example` with
  `DJANGO_DEBUG=False`; the fail-closed checks in §1 make the container refuse
  to boot with the dev defaults.
* `python manage.py check --deploy` should show no security warnings on a
  production configuration.
* After the demo, stop `cloudflared` and `docker compose down` — a Quick Tunnel
  URL left running is a public door.

---

## 6. Verification

```bash
# Settings fail closed under DJANGO_DEBUG=False (subprocess-per-case)
docker exec -w /app cpms_test_backend python manage.py test config.tests_settings --noinput

# Auth throttles (per IP and per account) + the rest of the users app
docker exec -w /app cpms_test_backend python manage.py test apps.users --noinput

# Config/drift gates
docker exec -w /app cpms_test_backend python manage.py check
docker exec -w /app cpms_test_backend python manage.py makemigrations --check --dry-run
```

## Linking the demo seed to the live POS catalogue

`seed_demo` maps only the two CPMS materials that have a real POS equivalent (Portland cement 40 kg to `QB000001-7`, Tile adhesive 25 kg bag to `QB000010-9`); every other material has no `pos_code`, so an own-store order for it is refused with `MISSING_POS_CODE`. POS barcodes come from the POS database ids, so they are only right on a freshly seeded POS. Before a demo:

1. Run the POS seed, then compare with `GET /api/v1/integration/cpms/materials/` and fix any `pos_code` that differs (Master data, Materials).
2. Find the POS customer that represents this CPMS company (`GET /api/v1/integration/cpms/customers/`) and run `python manage.py seed_demo --pos-payer-id <customer id>`. Without it the own-store supplier has no payer and POS refuses the import with a payer error. POS customer ids are not stable, so it is never defaulted.
