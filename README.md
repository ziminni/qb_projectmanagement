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

To run the web app in Chrome, use `flutter run -d chrome`.

Validate the frontend with:

```sh
cd flutter
flutter analyze
flutter test
```

The frontend currently contains the generated Flutter starter app; API integration is not configured yet.
