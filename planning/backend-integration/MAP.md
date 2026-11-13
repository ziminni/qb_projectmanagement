# CPMS backend integration and POS connection

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
|---|---|---|---|
| Planning | Verify source; settle contracts and boundaries | [01](./decisions/01-deployment-boundary.md), [02](./decisions/02-scope-baseline.md), [03](./decisions/03-roles-and-access.md), [04](./decisions/04-pos-sync-and-connectivity.md), [05](./decisions/05-wbs-costing-and-pos-bridge.md) | ✅ Done (Revisable) |
| Phase 1 — Auth, RBAC, Master Data & Desktop HTTP | 5-role email auth, user management, company/master lists, Dio client + JWT storage | None | [ ] Pending |
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
- [WBS categories, verified to-do progress, and derived project costing](./decisions/05-wbs-costing-and-pos-bridge.md): Budget-weighted `Category` + Owner-verified `Todo` progress, actual costs derived from confirmed Deliveries + processed Payroll + approved Equipment logs, and barcode mapping + POS read-back.

## Active Frontier (Open & Unblocked)

*(All core planning decisions resolved. Ready for Phase 1 execution; any new questions discovered during build re-enter here.)*

## Blocked

*(None.)*

## Fog of War (Not Yet Specified)

*(None — graduated into the Phased Implementation Roadmap below.)*

## Phased Implementation Roadmap

### Phase 1 — Auth, RBAC, Master Data & Desktop HTTP Foundation
- [ ] **1.1 — 🤖 Backend Users, Multi-Role & Auth Hardening (`django-backend/apps/users/`):** Email login (`POST /api/v1/auth/login/`), `UserRole` model (`admin`, `owner`, `site_engineer`, `accountant`, `client`), Admin-only user CRUD + password reset, self password change, remove public role-escalation on `/auth/register/` and `/auth/me/`, and add `AuditLog` + `Notification` endpoints.
- [ ] **1.2 — 🤖 Backend Company Profile, Settings & Master Lists:** Endpoints for `CompanyProfile`, `License`, `CompanySettings`, `MaterialItem` (with nullable `pos_code`), `EquipmentItem`, and `Supplier` (with `is_own_store` + nullable `pos_payer_id`).
- [ ] **1.3 — 🤝 Flutter Desktop HTTP Client & Auth/Admin Repositories (`flutter/lib/core/network/`, `data/repositories/`):** Configure `Dio` client with `API_BASE_URL` (`--dart-define=API_BASE_URL=...`), JWT refresh interceptor, `X-Active-Role` header, and HTTP implementations of `AuthRepository`, `UserRepository`, `CompanyRepository`, `MasterDataRepository`, `AuditLogRepository`, and `NotificationRepository`.

### Phase 2 — Projects, Assignments, WBS Schedule & Daily Site Operations
- [ ] **2.1 — 🤖 Backend Projects, Assignments & WBS (`django-backend/apps/projects/`):** Align `Project`, `ProjectAssignment` (with `pending` / `not_sent` / `accepted` / `declined` / `changes_requested` flow), `Category` (budget, sort_order), and `Todo` (done + owner verification) with Flutter JSON contracts and role-scoped querysets + `seesFinance` redaction.
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
