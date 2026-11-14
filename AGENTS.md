# QB Project Management System (CPMS) — Agent Routing

| Need | Read First |
|---|---|
| Active integration plan & roadmap | `planning/backend-integration/MAP.md` |
| Locked architectural decisions (revisable) | `planning/backend-integration/decisions/01-*.md` through `05-*.md` |
| Flutter desktop models & repositories | `flutter/lib/data/models/`, `flutter/lib/data/repositories/`, `flutter/lib/core/di/service_locator.dart` |
| Django backend (`django-backend/`) | `django-backend/config/urls.py`, `django-backend/apps/{users,projects,site_inventory,requisitions,financials}/` |
| POS counterpart integration contract | `../qb_pos_inventory_system/backend_django/apps/integration/{urls,views,serializers}.py` |

## Invariants

1. **Canonical backend path:** `django-backend/` (do not recreate `backend/`).
2. **Living Plan:** If any discrepancy or better approach is found during building, update the relevant decision file in `planning/backend-integration/decisions/` and `planning/backend-integration/MAP.md` in place.
3. **Desktop-first:** Both CPMS and POS are Flutter desktop apps. POS service credentials stay strictly on the CPMS backend (`django-backend/`), never in Flutter.
4. **POS isolation:** Do not mutate the POS dev database (`buildpro_db`).
5. **Agent limits (avoid machine crashes):** at most 3 dev agents per project; at most 1 read-only reviewer per project; at most 1 QA agent across both projects, started only after that phase's builders and suites finish. Reviewers never run suites. Backend test runs are serialized per database (`cpms_test_backend` here; POS uses its own QA container).
