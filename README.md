# BuildPro CPMS — Construction Project Management System

Construction project management system for Queen Builders, paired with the BuildPro POS / Inventory System (`qb_pos_inventory_system`).

- `django-backend/`: Django REST API + supervised POS outbox worker.
- `flutter/`: Flutter desktop/web client (`buildpro_frontend`).

## 1. Quick Start

On every `docker compose up -d`, the backend applies migrations and runs `seed_demo --auto-pos-payer`. That seeds the demo accounts and projects, and links the own-store supplier to the POS contractor. The POS bridge settings default to `django-backend/pos-bridge.defaults.env` (POS on the same computer); anything in `django-backend/.env` overrides them.

If an own-store order says **the store refused this order (UNKNOWN_PAYER)**, run `docker compose restart backend` (it relinks the payer on start), then press **Retry** on the order.

See [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) for hardening and backups, and [`docs/HANDOFF.md`](docs/HANDOFF.md) for verification status.

## 1a. Running POS and CPMS together (one computer or two laptops)

> This same guide is in both READMEs (`qb_pos_inventory_system` and `qb_project_management_system`).

**How the two systems connect.** Each system runs completely on its own computer: its Docker backend plus its Flutter app. Each app only talks to the backend on the same computer (`127.0.0.1`). The only link between them is **CPMS → POS**: CPMS sends material requests to the store, and reads prices, stock, what a project owes, and the status of payment receipts. POS never calls CPMS.

So in a two-laptop setup, **the POS laptop opens the tunnel** and **the CPMS laptop points at it**. It works either way round: POS on Windows with CPMS on the Mac, or the reverse.

| Setup | When | Tunnel? |
|---|---|---|
| **A. One computer** | You run both systems yourself | No |
| **B. Two laptops** (e.g. Windows + Mac) | Each teammate runs one system, e.g. for the adviser demo | Yes, started on the POS laptop |

### Setup A: both systems on one computer

1. Start POS **first**, in `qb_pos_inventory_system`: `docker compose up -d --build`
2. Then start CPMS, in `qb_project_management_system`: `docker compose up -d --build`
3. Check the link, in `qb_project_management_system`:
   ```sh
   docker compose exec backend python manage.py check_pos
   ```
   The last line should be `READY: own-store orders can be sent.`
4. Run both apps (see "Run the apps" below).

No `.env` file and no tunnel are needed. CPMS finds POS at `http://host.docker.internal:8000` and links itself to the POS contractor (Dela Cruz Construction in the demo data).

### Setup B: two laptops (Windows + Mac)

**Once, before demo day, on each laptop (needs a good internet connection; Docker downloads about 1–2 GB):**

| | Windows | Mac (Apple Silicon or Intel) |
|---|---|---|
| Docker | Docker Desktop (WSL 2 backend) | Docker Desktop for Mac |
| Flutter | Flutter SDK + Visual Studio 2022 with **Desktop development with C++** | Flutter SDK + Xcode (open it once and accept the licence) + `brew install cocoapods` |
| Check tools | `flutter doctor -v` | `flutter doctor -v` |

Then clone **your** system's repository and run `docker compose up -d --build` once in it, so everything is downloaded before the demo.

**Step 1: POS laptop.** Start POS, then the tunnel, from the `qb_pos_inventory_system` folder:

```powershell
docker compose up -d
.\scripts\start-tunnel.ps1     # Windows PowerShell
```
```sh
docker compose up -d
./scripts/start-tunnel.sh      # Mac
```

If PowerShell says scripts are disabled, run `Set-ExecutionPolicy -Scope Process Bypass` first, in the same window. The script prints four lines like:

```env
POS_API_BASE_URL=https://<random-name>.trycloudflare.com
POS_API_ALLOW_INSECURE_LOCAL=False
POS_API_GATEWAY_HEADER_NAME=X-QB-Gateway-Key
POS_API_GATEWAY_HEADER_VALUE=<48-character key>
```

Send these four lines to the CPMS laptop, for example in a private chat. The key works like a password: don't post it anywhere public. Only a small gateway is exposed, never the whole POS. It allows only the CPMS sign-in and the `/api/v1/integration/cpms/` routes, and only with that key.

**Step 2: CPMS laptop.** Create the file `qb_project_management_system/django-backend/.env`, paste the four lines, save it, then run this in `qb_project_management_system`:

```sh
docker compose up -d
```

How to create the file:
- **Mac:** `nano django-backend/.env`, paste, then Ctrl+O, Enter, Ctrl+X.
- **Windows:** Notepad → Save as → "All files (\*.\*)" → name it `.env`.

`docker compose up -d` restarts the CPMS backend and its outbox worker with the new settings.

**Step 3: CPMS laptop, check the link:**

```sh
docker compose exec backend python manage.py check_pos
```

`READY` means the material request flow will work. Otherwise it says exactly what's wrong (see Troubleshooting below).

**Step 4: both laptops.** Run your app (see "Run the apps").

**After the demo:**
- POS laptop: `docker compose --profile tunnel stop gateway cloudflared`
- CPMS laptop: delete the four lines from `django-backend/.env` and run `docker compose up -d`. That returns CPMS to one-computer mode.

**Rehearse on one computer:** do Setup B with both systems on the same machine. The tunnel on the POS side, and the four lines in CPMS's `.env`. The traffic then goes out to Cloudflare and back, exactly as between two laptops.

### Setup C: CPMS Online + POS Local/Offline (Quick Test via Cloudflare Tunnel)

To expose the CPMS backend (`:8001`) online for a few hours so teammates can connect from any internet connection while POS stays local/offline-first:

1. **One-time secret setup:** Put the 4 POS tunnel lines (`POS_API_BASE_URL`, `POS_API_ALLOW_INSECURE_LOCAL`, `POS_API_GATEWAY_HEADER_NAME`, `POS_API_GATEWAY_HEADER_VALUE`) in `django-backend/.env` (gitignored — survives `git pull`).
2. **Start CPMS + Quick Tunnel** from `qb_project_management_system`:
   ```powershell
   .\scripts\start-tunnel.ps1     # Windows PowerShell
   ```
   ```sh
   ./scripts/start-tunnel.sh      # macOS / Linux
   ```
   *(Want a permanent Cloudflare Named Tunnel hostname later? Pass `-Token "<cf-token>" -Hostname "cpms-api.yourdomain.com"` / `--token ... --hostname ...`.)*
3. The script starts `db`, `backend`, `pos_outbox`, and `cloudflared`, checks `check_pos`, and prints the public `https://<random>.trycloudflare.com` URL.
4. **Teammates connect from anywhere** without running Docker:
   ```powershell
   cd flutter
   flutter run -d windows --dart-define=API_BASE_URL=https://<printed-url>/api/v1
   # or: -d macos / -d chrome
   ```
5. **Stop when done:**
   ```powershell
   docker compose --profile tunnel stop cloudflared
   ```

### Run the apps

Each app connects to the backend on its own computer; no settings are needed. From the repository's `flutter` folder:

| | Windows | Mac |
|---|---|---|
| First time | `flutter config --enable-windows-desktop` then `flutter pub get` | `flutter config --enable-macos-desktop` then `flutter pub get` |
| Run | `flutter run -d windows` | `flutter run -d macos` |

Logins: POS `manager`, `cashier`, `stocker`, `admin` (password `demo1234`). CPMS `ramon@example.ph` (owner/PM), `ana@example.ph` (site engineer), `liza@example.ph` (accountant), `maria@example.ph` (admin), `mark@example.ph` (client) (password `password123`).

### Demo script (about 5 minutes)

1. **CPMS, `ana`:** open project **QB-2026-014** → Material requests → new request: Portland cement 40 kg × 5.
2. **CPMS, `ramon`:** open the request → **Own hardware store**. The picker shows the store's live price and stock. Confirm the order. Within about a minute, the order says **Sent to store**, and its "At the store" panel says *Waiting for the store manager to accept*.
3. **POS, `manager`:** **Project requests** → the new request → **Accept**.
4. **POS, `cashier`:** open a shift if needed → **Release materials** → **Find accepted request** → select it → **Release materials** → print the receipt.
5. **CPMS, `ramon`:** within about a minute (or press **Check store now** on the order), the material request shows *Released — picked up from the store · released 5 of 5*. Project → **Financials** → **Owed to the store** shows the charge.
6. **CPMS, `liza`:** on **Owed to the store** → **Submit payment receipt**. Then **POS, `manager`:** **Receivables** → **CPMS receipts** → **Approve**. The CPMS balance goes down, and POS **Payment history** lists it as *CPMS receipt …*.

### Troubleshooting

| What you see | Fix |
|---|---|
| `check_pos`: *could not be reached* | The POS laptop is off, asleep or offline, or its tunnel stopped. Turn off sleep on the POS laptop for the demo, rerun the tunnel script, and copy the new URL. |
| It worked, then stopped after the POS laptop restarted | The tunnel URL changes on every restart. Rerun the script on the POS laptop, update `POS_API_BASE_URL` in CPMS's `.env`, then `docker compose up -d` on the CPMS laptop. The key stays the same. |
| `check_pos`: 403 / *refused* | The key in CPMS's `.env` doesn't match. Copy all four lines again. |
| `check_pos`: *payer … is not a contractor* | Run `docker compose restart backend` on the CPMS laptop; it relinks to the store's contractor on start. |
| `check_pos`: *material codes the store does not sell* | Fix those codes in CPMS **Master lists → Materials**, or use materials that are mapped. |
| School or office Wi-Fi blocks the tunnel | Put the POS laptop (or both laptops) on a phone hotspot. |
| Mac: `docker: command not found` / cannot connect | Open Docker Desktop first and wait until it says it is running. |
| Mac: the app opens but login doesn't stick | Pull the latest code; the CPMS Mac keychain fix is in the commit that added this guide. |
| CPMS order picker says *Store offline* | Same as "could not be reached": CPMS can't reach POS right now. Orders made while offline are sent automatically once it can. |

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

# macOS (requires Xcode + CocoaPods: brew install cocoapods)
flutter config --enable-macos-desktop
flutter run -d macos

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
