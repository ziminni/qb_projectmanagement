# CPMS backend integration and POS connection

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
|---|---|---|---|
| Planning | Verify source; settle contracts and boundaries | [01](./decisions/01-deployment-boundary.md), [02](./decisions/02-scope-baseline.md), [03](./decisions/03-roles-and-access.md), [04](./decisions/04-pos-sync-and-connectivity.md), [05](./decisions/05-wbs-costing-and-pos-bridge.md) | ✅ Done (Revisable) |
| Phase 1 — Auth, RBAC, Master Data & Desktop HTTP | 5-role email auth, user management, company/master lists, Dio client + JWT storage | None | ✅ Done 2026-11-14 — 1.1–1.4 built + reviewed; close gates backend 164 OK + check clean + no drift, Flutter analyze clean + 190 passed (`../temp/cpms/phase1-close/`); live API QA (`../temp/cpms/phase1-qa/report.md`) all pass after one Medium fix (failed logins for inactive/no-role now audited; unknown email → hashed `cpms.security` log). Not yet proven: desktop UI with `USE_API=true`, `libsecret` on Linux (Phase 5). Committed locally, owner pushes. Branch `feat/cpms-integration-phase-1`; contract [phase-1-auth-and-admin](./contracts/phase-1-auth-and-admin.md); baseline 57 backend tests OK, Flutter analyze clean + 135 passed (`../temp/cpms/baseline/`); disposable test stack `cpms_test_backend`/`cpms_test_db` on private network `cpms_test_net` (no published ports; POS QA owns host 8001) |
| Phase 2 — Projects, Assignments, WBS & Daily Reports | Projects, client/engineer acceptance, Categories/Todos, Daily Reports & Documents | None | [ ] Pending |
| Phase 3 — Procurement, Deliveries & POS Bridge | Material requests, Own-Store vs External POs, Deliveries, Site Inventory, POS `/integration/cpms/*` client + retry queue | None | [ ] Pending |
| Phase 4 — Labor, Billing, VOs, Retention & Client Portal | Workers/Attendance/Payroll, Progress Billing, VOs, Retention, Derived Costs, Client Portal, Notifications | None | [ ] Pending |
| Phase 5 — E2E Verification & Deployment | Seed parity with MockData, Flutter repository swap, POS↔CPMS live bridge test, desktop build & tunnel config | None | [ ] Pending |

## Destination

Align `django-backend/` in `qb_project_management_system` with the teammate's Flutter desktop workflows (`39da4ff`), replace the mock repositories in `service_locator.dart` with real HTTP repositories, and wire the CPMS-to-POS `/api/v1/integration/cpms/*` bridge with a durable retry queue.

> **Living Plan Policy:** Every architectural decision lives in its own file under `planning/backend-integration/decisions/`. If any mismatch, bug, or better approach is discovered during building or testing, update the specific decision file and this `MAP.md` table in place before/while adjusting the code.

## Notes & Invariants

- **Separate repositories, APIs, and databases:** `qb_pos_inventory_system` (Local store server/LAN) and `qb_project_management_system` (Cloud/standalone server). No cross-database foreign keys.
- **Both clients are Flutter desktop apps:** No frontend web hosting required. POS service credentials (`POS_API_SERVICE_USERNAME` / `PASSWORD` or rotating JWT) live strictly on the CPMS Django server, never in the Flutter desktop client.
- **Canonical CPMS backend directory:** `django-backend/` (referenced by `docker-compose.yml`). Do not recreate the deleted `backend/` directory.
- **Preserve teammate's Flutter UI & domain rules:** Adapt Django models/serializers/views to serve the exact JSON contracts expected by `flutter/lib/data/models/*.dart` and `flutter/lib/data/repositories/*_repository.dart`. Retain the teammate's existing file structure and UI; only make minimal, targeted UI additions when required for integration, and record every addition in session/decision docs.
- **Security-by-Design in every phase:** Enforce authentication hardening, object-level authorization (IDOR prevention via `project_assignments`), server-side financial redaction (`seesFinance`), upload MIME/size validation, and audit logging inside each phase as it is built — never defer security to post-dev.
- **Forward-compatible POS bridge:** `MaterialItem.pos_code`, `PurchaseOrder.pos_request_id`/`pos_token`/`pos_sync_status`/`pos_expected_amount`, and `SupplierPayment.receipt_photo_url` are included now so upgrading to POS Phase 1c later is purely additive.

## Decisions So Far

- [Local POS, cloud CPMS](./decisions/01-deployment-boundary.md): POS runs locally at the store so counter sales survive internet outages; CPMS runs online; cross-system sync queues during outages.
- [Frontend plus verified review](./decisions/02-scope-baseline.md): Teammate's Flutter desktop (`39da4ff`) is the primary functional baseline; backend models adapt to match it while closing security flaws.
- [Roles, authentication, project scope, and security-by-design](./decisions/03-roles-and-access.md): Agreed 5 roles (`Admin / Owner` seeing all projects, `Project Manager` mapped to `owner` enum seeing assigned projects, `Site Engineer / Foreman`, `Accountant`, `Client` portal-only), flexible `user_roles` junction so Owner and Admin can be split later, and security-by-design across all phases.
- [Own-store PO sync to POS and HTTPS/tunnel connectivity](./decisions/04-pos-sync-and-connectivity.md): Own-store `PurchaseOrder` mints UUID token and syncs to POS `/api/v1/integration/cpms/requests/` over HTTPS (LAN or Cloudflare Tunnel / Tailscale) with a durable retry queue; external POs stay in CPMS.
- [Phase 2 contract rulings](./decisions/06-phase-2-contract-rulings.md): delegated revisable defaults for the [Phase 2 contract](./contracts/phase-2-projects-and-site.md) — server-computed category `weight`, client sees own contract amount, client-visible documents only, soft client decline (owner to confirm), self-verify allowed but audited (owner to confirm), new `apps/site_reports`, `Client` model in 2.1.
- [WBS categories, verified to-do progress, and derived project costing](./decisions/05-wbs-costing-and-pos-bridge.md): Budget-weighted `Category` + Owner-verified `Todo` progress, actual costs derived from confirmed Deliveries + processed Payroll + approved Equipment logs, and barcode mapping + POS read-back.

## Active Frontier (Open & Unblocked)

*(All core planning decisions resolved. Ready for Phase 1 execution; any new questions discovered during build re-enter here.)*

## Blocked

*(None.)*

## Fog of War (Not Yet Specified)

*(None — graduated into the Phased Implementation Roadmap below.)*

## Phased Implementation Roadmap

### Phase 1 — Auth, RBAC, Master Data & Desktop HTTP Foundation
- [x] **1.1 — 🤖 Backend Users, Multi-Role & Auth Hardening (`django-backend/apps/users/`) — DONE: review APPROVED (`../temp/cpms/1.1/review.md`), controller 103 OK + check clean + no drift. Carry-forward minors: (a) file-wide pyright ignores added to 3 teammate test files — trim to per-line once the gitignored `django-backend/.venv` stubs are picked up by the checker; (b) dev-default SECRET/DEBUG/ALLOWED_HOSTS/CORS → Phase 5 hardening; (c) 3 legacy model convenience flags read role strings outside `capabilities.py` → fold into capabilities when touched; (d) throttles are per-IP only → add per-account in Phase 5.** Original scope: Email login (`POST /api/v1/auth/login/`), `UserRole` model (`admin`, `owner`, `site_engineer`, `accountant`, `client`), Admin-only user CRUD + password reset, self password change, remove public role-escalation on `/auth/register/` and `/auth/me/`, and add `AuditLog` + `Notification` endpoints.
- [x] **1.2 — 🤖 Backend Company Profile, Settings & Master Lists — DONE: review APPROVED (`../temp/cpms/1.2/review.md`), controller 156 OK + check clean + no drift; contract section appended to phase-1 contract; new `apps/master_data`. Minor fix round landed (pos_payer_id bigint cap → 400, duplicate-name race → 400 with mock text via savepoint, settings GET read-only + data migration `apps_company/0004` seeds the row). Open product calls for teammate: trade hard-delete (protect in Phase 4), exactly-one own-store supplier, pos_code uniqueness before Phase 3, equipment name uniqueness.** Original scope: Endpoints for `CompanyProfile`, `License`, `CompanySettings`, `MaterialItem` (with nullable `pos_code`), `EquipmentItem`, and `Supplier` (with `is_own_store` + nullable `pos_payer_id`).
- [x] **1.3 — 🤝→🤖 (delegated 2026-11-14: owner said "do it for me") Flutter Desktop HTTP Client & Auth/Admin Repositories (`flutter/lib/core/network/`, `data/repositories/`):** Configure `Dio` client with `API_BASE_URL` (`--dart-define=API_BASE_URL=...`), JWT refresh interceptor, `X-Active-Role` header, and HTTP implementations of `AuthRepository`, `UserRepository`, `AuditLogRepository`, and `NotificationRepository`. DONE: review APPROVED (`../temp/cpms/1.3/review.md`); fix round landed (DRF `next` pagination followed with a 200-page cap, failed sign-in clears tokens, refresh without `access` signs out cleanly, release builds refuse to start without `API_BASE_URL`, debug fallback `http://127.0.0.1:8001`); controller analyze clean + 174 passed. Open risk: `flutter_secure_storage` needs `libsecret` on Linux build hosts — prove at first desktop build (Phase 5). `CompanyRepository` and `MasterDataRepository` HTTP repos moved to **1.4** (they need 1.2's endpoints).
- [x] **1.4 — 🤖 Flutter HTTP Company & Master Data Repositories:** HTTP implementations of `CompanyRepository` and `MasterDataRepository` against the 1.2 contract section, wired behind `USE_API=true`. DONE: review APPROVED (`../temp/cpms/1.4/review.md`); controller analyze clean + 190 passed; `ApiClient.delete()` added for trade delete. Note: the contract's "drop client `AdminAudit.record()` calls" is satisfied by 1.3's no-op `HttpAuditLogRepository.record` (no duplicate server audit rows; viewmodels untouched).

### Phase 2 — Projects, Assignments, WBS Schedule & Daily Site Operations
- [ ] **2.1 — 🤖 Backend Projects, Assignments & WBS (`django-backend/apps/projects/`):** Contract: [phase-2-projects-and-site](./contracts/phase-2-projects-and-site.md). Add `Client`; align `Project`, `ProjectAssignment` (with `pending` / `not_sent` / `accepted` / `declined` / `changes_requested` flow), `Category` (budget, sort_order), and `Todo` (done + owner verification) with Flutter JSON contracts and role-scoped querysets + `seesFinance` redaction.
- [ ] **2.2 — 🤖 Backend Daily Reports & Project Documents:** Endpoints for `DailyReport` (draft/submitted/approved/returned, `MaterialUsage`, `EquipmentLog`, photo attachments) and `ProjectDocument` (multipart file upload + type/visibility filtering).
- [ ] **2.3 — 🤖 Flutter HTTP Repositories for Projects, Schedule, Daily Reports & Documents:** Implement and wire `HttpProjectRepository`, `HttpScheduleRepository`, `HttpDailyReportRepository`, and `HttpDocumentRepository`.

### Phase 3 — Procurement, Deliveries, Site Inventory & POS Bridge
- [ ] **3.1 — 🤝 Backend Procurement & POS `/api/v1/integration/cpms/*` Client (`django-backend/apps/requisitions/`):** Implement `MaterialRequest`, `MaterialRequestItem`, `SiteCount`, `PurchaseOrder`, `PurchaseOrderItem`, `Delivery`, `DeliveryItem`, and `SupplierPayment`. Rewrite `PosAPIClient` to authenticate as `CPMS Service` (rotating JWT) and call `/api/v1/integration/cpms/{customers,materials,requests,projects/.../payables}` with durable `pos_sync_status` (`pending_sync` / `synced` / `failed`) and idempotent retry.
- [ ] **3.2 — 🤖 Flutter HTTP Procurement Repository & POS Sync Status UI:** Implement `HttpProcurementRepository` (requests, own-store vs external POs, delivery confirmation, site inventory, payables) and surface POS sync/read-back status cleanly.

### Phase 4 — Labor, Payroll, Progress Billing, VOs, Retention & Client Portal
- [ ] **4.1 — 🤖 Backend Labor & Payroll (`django-backend/apps/labor/`):** Endpoints for `Worker`, `Attendance`, `PayrollPeriod`, and `PayrollEntry` with project labor cost aggregation.
- [ ] **4.2 — 🤖 Backend Financials: Progress Billing, VOs, Retention & Derived Costing (`django-backend/apps/financials/`):** Endpoints for `ProgressBilling`, `ClientPayment`, `VariationOrder`, `RetentionRelease`, and server-backed `ProjectCosts` (`materials` from deliveries + `labor` from payroll + `equipment` from approved daily reports).
- [ ] **4.3 — 🤖 Flutter HTTP Repositories for Labor & Billing + Client Portal Verification:** Implement `HttpLaborRepository` and `HttpBillingRepository`; verify Client Portal views (`client_projects`, `client_progress`, `client_photos`, `client_billings`, `client_variation_orders`).

### Phase 5 — Seed Parity, End-to-End POS↔CPMS Verification & Desktop Packaging
- [ ] **5.1 — 🤖 Backend `seed_demo` Command Matching `MockData`:** Seed the demo accounts (`maria@example.ph`, `ramon@example.ph`, `ana@example.ph`, `liza@example.ph`, `mark@example.ph`, `elena@example.ph`, password `password123`), sample projects, categories/todos, and POS barcode mappings (`QB000001-7`, etc.).
- [ ] **5.2 — 🤝 Service Locator Switch & Full Test Gate:** Switch `service_locator.dart` from `Mock*Repository` to `Http*Repository` (keeping mocks for unit tests), run `python manage.py test` + `flutter analyze` + `flutter test`, and run live POS↔CPMS integration verification (catalog pull, own-store PO import into POS, store review, partial release, read-back, and payables balance).

## Out of Scope

- Native mobile APK/iOS build variation for Foreman (`site_engineer`) — deferred until after desktop integration is complete.
- Shared database between POS and CPMS or direct cross-system DB connections.
- Rewriting teammate's Flutter screens when backend adaptation solves the contract gap.
