# BuildPro CPMS — Construction Project Management System

- `django-backend/`: Django REST API.
- `flutter/`: Flutter frontend (`buildpro_frontend`).

## Backend & POS Bridge

1. Copy `django-backend/.env.example` to `django-backend/.env`. To connect to a local POS stack on port `8000`, set:

```env
POS_API_BASE_URL=http://host.docker.internal:8000
POS_API_ALLOW_INSECURE_LOCAL=True
POS_API_SERVICE_USERNAME=cpms_service
POS_API_SERVICE_PASSWORD=demo1234
```

2. Start PostgreSQL (`5434`), the CPMS API (`8001`), and the supervised POS outbox worker from the repository root:

```sh
docker compose up -d --build
```

3. For a fresh demo database, seed demo accounts/projects and link the POS contractor payer ID (`GET http://127.0.0.1:8000/api/v1/integration/cpms/customers/` on a seeded POS):

```sh
docker compose exec backend python manage.py seed_demo --pos-payer-id <POS_CUSTOMER_ID>
```

See [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) for production/tunnel hardening (`DJANGO_DEBUG=False`, Cloudflare Quick Tunnel, database + `private_media/` backups) and [`docs/HANDOFF.md`](docs/HANDOFF.md) for verification status.

## Frontend

With Flutter installed:

```sh
cd flutter
flutter pub get
```

### Live API mode (`USE_API=true`)

Pass `--dart-define=USE_API=true` and `--dart-define=API_BASE_URL=http://127.0.0.1:8001/api/v1` (note the `/api/v1` suffix):

```sh
# Windows (PowerShell, requires Visual Studio with "Desktop development with C++")
flutter run -d windows --dart-define=USE_API=true --dart-define=API_BASE_URL=http://127.0.0.1:8001/api/v1

# Linux (requires clang, cmake, ninja-build, pkg-config, libgtk-3-dev, libsecret-1-dev + keyring)
flutter run -d linux --dart-define=USE_API=true --dart-define=API_BASE_URL=http://127.0.0.1:8001/api/v1

# Chrome
flutter run -d chrome --dart-define=USE_API=true --dart-define=API_BASE_URL=http://127.0.0.1:8001/api/v1
```

### Offline mock mode (default when `USE_API` is omitted)

Running `flutter run` without `--dart-define=USE_API=true` uses in-memory mock repositories (`flutter/lib/data/repositories/mock_*.dart`), which is also how unit/widget tests run by default:

```sh
cd flutter
flutter analyze
flutter test
```

### Demo Accounts (seeded by `seed_demo` and present in mock mode, password `password123`)

| Role | Account | Job |
| --- | --- | --- |
| Owner / Project manager | `ramon@example.ph` | Runs projects end to end: plans, verifies, orders, bills |
| Owner / PM + site engineer | `elena@example.ph` | A partner who also works a site |
| Site engineer / foreman | `ana@example.ph` | Daily reports, attendance, material requests, deliveries |
| Accountant | `liza@example.ph` | Payroll, client and supplier payments, retention |
| Client | `mark@example.ph` | Progress, photos, billings and VOs for their project |
| System admin | `maria@example.ph` | Users, company profile, master lists, settings |

Company finances are confidential: only the owner and the accountant see peso amounts. The client sees only what they are billed. The access rules live in `AppRole.seesFinance`, `RoleNavigation` and `ProjectTab`; a real backend must enforce the same rules.

Feature modules live in `flutter/lib/features/` (auth, user_management, projects, schedule, dashboard, daily_reports, procurement, labor, billing, documents, client_portal). Project progress is computed in one place, `flutter/lib/data/services/progress_calculator.dart`, and every progress figure in the app reads from it.
