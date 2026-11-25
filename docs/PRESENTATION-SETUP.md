# BuildPro presentation — Windows Docker Desktop

Both backends run on the Windows presentation PC. No Contabo. Use a disposable presentation database; both reset modes **erase existing database rows**, and the POS scripts remove its PostgreSQL volume. Back up both databases first if you need their data. CPMS leaves files in `django-backend/private_media` untouched; do not use a production upload directory for a presentation.

| Mode | POS | CPMS |
| --- | --- | --- |
| Fresh | Six accounts, Store/Bodega, standard units, Walk-in Customer and a contractor payer. No products, sales or POs. | Six sign-ins in the demo dropdown, with an empty company shell/default settings required for sign-in. No projects, workers, clients, suppliers, materials or transactions. |
| Demo | Sample hardware, stock, sales, returns and project requests. | Four sample projects, master lists, workers and an own-store supplier matched to the seeded POS customer. |

## Before the presentation

Open Docker Desktop. Update POS `master` and CPMS `main` on Windows. For a same-PC demo without internet, set these in **`project_managemet/django-backend/.env`** (this file overrides Docker defaults):

```dotenv
POS_API_BASE_URL=http://host.docker.internal:8000
POS_API_ALLOW_INSECURE_LOCAL=True
POS_API_SERVICE_USERNAME=cpms_service
POS_API_SERVICE_PASSWORD=demo1234
POS_API_GATEWAY_HEADER_NAME=
POS_API_GATEWAY_HEADER_VALUE=
```

These are demo credentials. Do not expose either demo backend on a public tunnel. CPMS reset and the POS `-LocalOnly` option leave public tunnels stopped. If presenting on a separate client device, use a trusted network.

## Reset POS first, then CPMS

Run **one** POS reset from the `hardware_store` checkout:

```powershell
cd "$HOME\Yaji\projects\capstone\DEVELOPMENT_FOLDER\hardware_store"
.\scripts\reset-fresh-empty.ps1 -LocalOnly -ConfirmReset
# For Demo instead: .\scripts\reset-seeded-demo.ps1 -LocalOnly -ConfirmReset
```

Run the matching CPMS mode from `project_managemet`:

```powershell
cd "$HOME\Yaji\projects\capstone\DEVELOPMENT_FOLDER\project_managemet"
.\scripts\reset-presentation.ps1 -Mode Fresh -ConfirmReset  # OR change Fresh to Demo
```

Confirm both health endpoints answer after startup:

```powershell
curl.exe -fsS http://127.0.0.1:8000/api/health/
curl.exe -fsS http://127.0.0.1:8001/api/health/
```

**Demo only**, in `project_managemet`:

```powershell
docker compose exec backend python manage.py check_pos
```

Expect `READY`, including 2 of 2 mapped materials. In **Fresh**, not ready is expected: create and link an own-store supplier and map materials before sending orders.

## Launch both desktops

Open two PowerShell tabs:

```powershell
cd "$HOME\Yaji\projects\capstone\DEVELOPMENT_FOLDER\hardware_store\flutter"
flutter pub get
flutter run -d windows
```

```powershell
cd "$HOME\Yaji\projects\capstone\DEVELOPMENT_FOLDER\project_managemet\flutter"
flutter pub get
flutter run -d windows --dart-define=USE_API=true --dart-define=SHOW_DEMO_LOGINS=true
```

CPMS defaults to `http://127.0.0.1:8001/api/v1`. Pick one of the six accounts from the login dropdown (`password123`); use Elena to demonstrate switching roles. POS accounts use `demo1234`.

On presentation day, keep the rehearsed data: open Docker Desktop, start services if needed, and launch the apps. Do not run a reset again unless intentionally discarding your rehearsal changes.
