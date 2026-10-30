# BuildPro CPMS — Construction Project Management System

- `django-backend/`: Django REST API.
- `flutter/`: Flutter frontend (`buildpro_frontend`).

## Backend

Optionally copy `django-backend/.env.example` to `django-backend/.env` and adjust the settings, then start the API and PostgreSQL from the repository root:

```sh
docker compose up --build
```

The API runs on port 8001.

## Frontend

With Flutter installed:

```sh
cd flutter
flutter pub get
flutter run
```

The app targets desktop: run `flutter run -d macos` on a Mac or `flutter run -d windows` on Windows (needs Visual Studio with the "Desktop development with C++" workload). It also runs in Chrome with `flutter run -d chrome`.

Validate the frontend with:

```sh
cd flutter
flutter analyze
flutter test
```

The frontend runs on mock repositories (`flutter/lib/data/repositories/mock_*.dart`); API integration is not configured yet. Sign in with any demo account listed on the login screen (password `password123`):

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
