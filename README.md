# BuildPro CPMS — Construction Project Management System

Construction project management system for Queen Builders, paired with the BuildPro POS / Inventory System (`qb_pos_inventory_system`).

- `django-backend/`: Django REST API + supervised POS outbox worker.
- `flutter/`: Flutter desktop/web client (`buildpro_frontend`).

## 1. Quick Start (Backend & POS Bridge)

### Option A: Same PC with BuildPro POS (Zero Configuration)

When both `qb_pos_inventory_system` (port `8000`) and `qb_project_management_system` (port `8001`) run in Docker on the same machine, no `.env` file or manual customer ID lookup is required:

1. Start the POS stack first (`docker compose up -d --build` in `qb_pos_inventory_system`).
2. Start PostgreSQL (`5434`), the CPMS API (`8001`), and the supervised POS outbox worker from this repository root:

```sh
docker compose up -d --build
```

On startup, `docker compose` automatically:
- Applies all Django migrations (`python manage.py migrate --noinput`).
- Seeds the demo accounts and projects (`python manage.py seed_demo --auto-pos-payer`).
- Connects to POS at `http://host.docker.internal:8000` using `cpms_service` / `demo1234` and links the seeded POS contractor customer (`Queen Builders Construction`) automatically. Even if POS is started after CPMS, the outbox worker (`run_pos_worker`) automatically discovers and links the POS contractor customer ID on the first requisition sync.

### Option B: Two Different PCs via Cloudflare Quick Tunnel

When POS runs on Store PC A and CPMS runs on Office PC B:

1. On **Store PC A (`qb_pos_inventory_system`)**, start POS and run the included Cloudflare Quick Tunnel script:
   - **Windows PowerShell:** `.\scripts\start-tunnel.ps1`
   - **Linux / macOS:** `./scripts/start-tunnel.sh`
2. Copy the `https://<random-name>.trycloudflare.com` URL printed by `cloudflared`.
3. On **Office PC B (`qb_project_management_system`)**, copy `django-backend/.env.example` to `django-backend/.env` and set:

```env
POS_API_BASE_URL=https://<random-name>.trycloudflare.com
POS_API_SERVICE_USERNAME=cpms_service
POS_API_SERVICE_PASSWORD=demo1234
```

4. Restart CPMS (`docker compose up -d`).

See [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) for production/tunnel hardening (`DJANGO_DEBUG=False`, Cloudflare Quick Tunnel, database + `private_media/` backups) and [`docs/HANDOFF.md`](docs/HANDOFF.md) for verification status.

## 2. Run the Flutter Client

```sh
cd flutter
flutter pub get
```

### Live API mode (Default on `flutter run`)

`flutter run` connects to the live Django API at `http://127.0.0.1:8001/api/v1` by default (`USE_API` defaults to `true` outside `flutter test`):

```sh
# Windows (PowerShell, requires Visual Studio with "Desktop development with C++")
flutter run -d windows

# Linux (requires clang, cmake, ninja-build, pkg-config, libgtk-3-dev, libsecret-1-dev + keyring)
flutter run -d linux

# Chrome
flutter run -d chrome
```

To point to a different API URL, pass `--dart-define=API_BASE_URL=http://<host>:8001/api/v1` (include `/api/v1`).

### Offline mock mode & automated tests

Pass `--dart-define=USE_API=false` to run the UI against in-memory mock repositories (`flutter/lib/data/repositories/mock_*.dart`). `flutter test` automatically defaults to mock mode unless `--dart-define=USE_API=true` is passed:

```sh
cd flutter
flutter analyze
flutter test
```

## 3. Demo Accounts (Password: `password123`)

Seeded automatically on `docker compose up -d` (and present in mock mode):

| Role | Account | Job |
| --- | --- | --- |
| Owner / Project manager | `ramon@example.ph` | Runs projects end to end: plans, verifies, orders, bills |
| Owner / PM + site engineer | `elena@example.ph` | A partner who also works a site |
| Site engineer / foreman | `ana@example.ph` | Daily reports, attendance, material requests, deliveries |
| Accountant | `liza@example.ph` | Payroll, client and supplier payments, retention |
| Client | `mark@example.ph` | Progress, photos, billings and VOs for their project |
| System admin | `maria@example.ph` | Users, company profile, master lists, settings |

Company finances are confidential: only the owner and the accountant see peso amounts. The client sees only what they are billed. The access rules live in `AppRole.seesFinance`, `RoleNavigation` and `ProjectTab`, and are enforced by the Django API.

## 4. End-to-End POS ↔ CPMS Workflows

- **Material Request & Own-Store Fulfilment:** Site engineer (`ana@example.ph`) submits a material requisition → Owner/PM (`ramon@example.ph`) approves and routes own-store items to Queen Builders Hardware Store → CPMS outbox worker pushes the request to POS (`POST /api/v1/integration/cpms/requisitions/`) and pulls live catalogue/stock and release status (`GET /api/v1/projects/<id>/pos-requests/`).
- **Per-Category Store Material Cost Attribution:** Own-store charges from POS (`GET /api/v1/projects/<id>/pos-payables/`) include `by_category`, attributing released/delivered store materials directly to each WBS / BOQ category in `ProjectCostService` while keeping unallocated store balance in `storeMaterials` without double-counting.
- **Online Payment Receipts to Store (Phase 1c):** From **Financials → Store Balance**, the owner or accountant can click **Submit payment receipt** (reference number, amount, Bank Transfer / GCash / Cheque, notes) to send a payment receipt to POS (`POST /api/v1/projects/<id>/pos-payment-receipts/`). Once the POS store manager approves the receipt in **Sales → Receivables**, the CPMS store balance updates automatically.
- **Statutory Payroll Deductions:** Generating a payroll period (`POST /api/v1/payroll-periods/generate/`) computes employee statutory deductions (`SSS` 5%, `PhilHealth` 2.5%, `Pag-IBIG` 2% capped at ₱100/period) alongside cash-advance deductions under `deductions_policy = 'configured'`.
