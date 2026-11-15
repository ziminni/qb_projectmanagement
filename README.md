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
- Connects to POS at `http://host.docker.internal:8000` as `cpms_service` / `demo1234` (demo defaults in `django-backend/pos-bridge.defaults.env`; anything in `django-backend/.env` overrides them) and links the own-store supplier to the POS contractor customer (**Dela Cruz Construction** in the POS demo seed). If POS starts after CPMS, the outbox worker (`run_pos_outbox`) makes that link on the first request it pushes.

### Option B: POS on a different computer (Cloudflare tunnel)

1. On the **store PC**, in `qb_pos_inventory_system`, run `docker compose up -d`, then the tunnel helper:
   - **Windows PowerShell:** `.\scripts\start-tunnel.ps1`
   - **Linux / macOS:** `./scripts/start-tunnel.sh`

   This exposes only a key-protected gateway (CPMS sign-in and the `/api/v1/integration/cpms/` routes), never the whole POS. The script prints four lines.
2. On **this PC**, paste those four lines into `django-backend/.env` (create the file if needed):

```env
POS_API_BASE_URL=https://<random-name>.trycloudflare.com
POS_API_ALLOW_INSECURE_LOCAL=False
POS_API_GATEWAY_HEADER_NAME=X-QB-Gateway-Key
POS_API_GATEWAY_HEADER_VALUE=<key printed by the script>
```

3. Run `docker compose up -d` here again.

The Quick Tunnel URL changes every time the tunnel restarts. When it does, rerun the script on the store PC and update `POS_API_BASE_URL`. Until then, CPMS keeps unsent requests in its outbox and retries them. The POS README (section 6) has the full guide.

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

- **Material Request & Own-Store Fulfilment:** Site engineer (`ana@example.ph`) submits a material request. The owner/PM (`ramon@example.ph`) orders it from our own store (an own-store purchase order with live POS prices and stock status). The CPMS outbox worker pushes it to POS (`POST /api/v1/integration/cpms/requests/`). In POS, the **Store Manager** accepts it, and the **cashier** finds it under **Release materials**, releases it with one click and prints the official receipt. CPMS shows the store's status on the order (`GET /api/v1/purchase-orders/<id>/pos-status/`), and the charge appears under **Financials → Owed to the store**.
- **Per-Category Store Material Cost Attribution:** Own-store charges from POS (`GET /api/v1/projects/<id>/pos-payables/`) include `by_category`, attributing released/delivered store materials directly to each WBS / BOQ category in `ProjectCostService` while keeping unallocated store balance in `storeMaterials` without double-counting.
- **Online Payment Receipts to Store (Phase 1c):** From the **Owed to the store** card on **Financials**, the owner or accountant clicks **Submit payment receipt** (reference number, amount, Bank Transfer / GCash / Cheque, notes) to send a payment receipt to POS (`POST /api/v1/projects/<id>/pos-payment-receipts/`). Once the POS store manager approves the receipt in **Sales → Receivables**, the CPMS store balance updates automatically.
- **Payroll Deductions:** Each payroll line deducts SSS 5%, PhilHealth 2.5% and Pag-IBIG 2% (capped at ₱100 per period) plus cash advances. These are **simplified flat rates for the demo, not the official SSS/PhilHealth/Pag-IBIG contribution tables**, so check them before real payouts.
