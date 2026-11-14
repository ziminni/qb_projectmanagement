# Phase 1 wire contract — auth, users, roles, audit, notifications, company

**Status:** Draft for Phase 1 build (revisable — update here first if building proves it wrong).
**Source of truth for shapes:** the Flutter models in `flutter/lib/data/models/` (`user.dart`, `user_role.dart`, `app_role.dart`, `audit_log.dart`, `app_notification.dart`, `company.dart`). Backend serves these exact keys; Flutter is not reshaped to fit the backend.

All routes under `/api/v1/`. JSON keys are snake_case. Timestamps ISO-8601.

## Roles and capabilities

- Role codes (`user_roles.role`): `admin`, `owner`, `site_engineer`, `accountant`, `client`. One user holds one or more.
- Agreed labels: `admin` = Admin / Owner (system admin plus full owner oversight); `owner` = Project Manager; `site_engineer` = Site Engineer / Foreman; `accountant` = Accountant; `client` = Client.
- The Admin / Owner account holds **both** `admin` and `owner` so the existing Owner/PM screens work through the role switcher with no frontend change.
- Capability rules live in **one backend module** (`apps/users/capabilities.py`) so splitting Owner from Admin later is a one-file change:
  - `ALL_PROJECTS_ROLES = {admin, accountant}` — a user holding any of these sees every project; everyone else is scoped by project assignment (Phase 2).
  - `FINANCE_ROLES = {owner, accountant}` — the active role sees internal peso figures (mirrors `AppRole.seesFinance`). Admin/Owner reaches finances through the `owner` role it also holds.
- Active role: request header `X-Active-Role: <code>`. Header absent → the user's first role in the fixed order admin, owner, accountant, site_engineer, client. Header naming a role the user does not hold → `403 {"code": "ROLE_NOT_HELD"}`.

## Shapes

- **User** `{id, company_id, full_name, email, phone, is_active, created_at, updated_at}` — never `password`, `is_staff`, `is_superuser`.
- **UserRole** `{id, user_id, role, created_at, updated_at}`.
- **AuditLog** `{id, user_id, action, entity, entity_id, details, created_at, updated_at}`.
- **AppNotification** `{id, user_id, type, message, link, is_read, created_at, updated_at}`.
- **Company** `{id, name, address, tin, pcab_license_no, pcab_license_expiry, logo_url, created_at, updated_at}` (model in Phase 1.1 because users reference it; endpoints in Phase 1.2).

## Auth

| Method | Path | Who | Body → Response |
|---|---|---|---|
| POST | `auth/login/` | anyone (throttled) | `{email, password}` → `200 {user, roles, access, refresh}`. Wrong email or password → `400 {"detail": "Incorrect email or password."}` (same text for both, no enumeration). Inactive → `403` "This account is deactivated. Contact your system admin." No roles → `403` "This account has no role yet. Contact your system admin." |
| POST | `auth/refresh/` | anyone | `{refresh}` → `{access, refresh}` (rotation + blacklist) |
| POST | `auth/logout/` | signed in | `{refresh}` → blacklists it |
| GET | `auth/me/` | signed in | `{user, roles}` |
| PATCH | `auth/me/` | signed in | only `full_name`, `phone`; any other key → `400` |
| POST | `auth/change-password/` | signed in | `{current_password, new_password}`; wrong current → `400`; new must be ≥8 chars with a letter and a digit, pass Django validators, differ from current |
| POST | `auth/password-reset-request/` | anyone (throttled) | `{email}` → always `204`; if an active user matches, active admins get a notification. No email is sent. |
| — | `auth/register/` | — | **removed** (404). Accounts are created by an admin only. |

## Users and roles (admin writes; reads scoped)

| Method | Path | Who | Notes |
|---|---|---|---|
| GET | `users/` | staff roles (not client) | filters `?role=<code>`, `?is_active=true` |
| GET | `users/{id}/` | staff roles; a client may read only themself | |
| POST | `users/` | admin | `{full_name, email, phone, is_active, roles: [...]}` → `201 {user, roles, temporary_password}`; email unique case-insensitive, stored lower-case; ≥1 valid role |
| PATCH/PUT | `users/{id}/` | admin | same fields; `roles` replaces the set |
| POST | `users/{id}/reset-password/` | admin | → `{temporary_password}` |
| DELETE | `users/{id}/` | — | `405`; deactivate instead |
| GET | `user-roles/` | staff roles | `?user=<id>` |

Lock-out guards: an admin cannot remove their own `admin` role or deactivate themself, and the last active admin can never lose `admin` or be deactivated (`400`).

## Audit and notifications

- Audit rows are written **by the server** inside the same transaction as the change (login success/failure, user create/update/activate/role change, password reset/change, reset request). No client `POST` — the desktop cannot forge audit entries.
- `GET audit-logs/` — admin only; filters `?entity=&entity_id=`; newest first, paginated.
- Notifications are created **by the server**. `GET notifications/` returns only the caller's own; `POST notifications/{id}/read/` (own only, else 404); `POST notifications/read-all/`.

## Security checks this phase must prove with tests

Role escalation via `auth/me/` and `users/` by non-admins refused; no user enumeration on login or reset request; throttling on login and reset request; another user's notification → 404; client cannot list users; unknown `X-Active-Role` → 403; passwords never serialized.

## Company, settings and master lists (task 1.2)

**Status:** built in task 1.2 (`apps/company` + new `apps/master_data`).
**Source of truth for shapes:** `models/{company,company_settings,material_item,supplier,trade,equipment}.dart`, interfaces `repositories/{company_repository,master_data_repository}.dart`, rules `services/master_data_rules.dart`, mocks `repositories/{mock_company_repository,mock_master_data_repository,mock_company_data}.dart`. Citations are relative to `flutter/lib/`.

Route prefix: master lists are mounted under `master-data/` so `master-data/equipment/` does not collide with the legacy site-inventory `equipment/` route (`django-backend/apps/site_inventory/urls.py:17`). `apps/site_inventory` is untouched.

**"License" is not a separate entity.** `MAP.md` 1.2 lists `License`; the Flutter Settings screen's "Licenses and compliance" section edits the same Company row's `pcab_license_no` / `pcab_license_expiry` (`features/user_management/views/settings_page.dart:19-22`, `features/user_management/widgets/settings_company_section.dart:16-24,51-58,97-104`). Task 1.2 therefore adds no `License` model.

### Shapes

- **Company** `{id, name, address, tin, pcab_license_no, pcab_license_expiry, logo_url, created_at, updated_at}` (`models/company.dart:47-62`). `name`, `address`, `tin`, `pcab_license_no` are non-null strings; `logo_url` nullable. `pcab_license_expiry` is parsed with the **non-null** `JsonUtils.toDate` (`models/company.dart:56`, `models/json_utils.dart:12`), so the API must always send a `yyyy-MM-dd` date. `logo_url` stays a URL field this phase (`models/company.dart:12,57` — the model has no upload/file key; Settings types it as a link, `features/user_management/widgets/settings_company_section.dart:36,58`).
- **CompanySettings** `{id, company_id, default_retention_pct, default_down_payment_pct, behind_schedule_threshold_pct, created_at, updated_at}` (`models/company_settings.dart:44-62`). All three percentages are non-null doubles, 0–100.
- **MaterialItem** `{id, name, unit, default_unit_cost, store_sku, pos_code, created_at, updated_at}` (`models/material_item.dart:40-51`). Decision 05 says "`unit_price`"; the Flutter key is **`default_unit_cost`** — Flutter wins. `store_sku` is nullable (the page prints `' · SKU …'` only when non-null, `features/user_management/views/master_lists_page.dart:76`), so a blank SKU is serialized as `null`.
- **Supplier** `{id, name, contact_person, phone, address, is_own_store, pos_payer_id, created_at, updated_at}` (`models/supplier.dart:48-60`). `contact_person`/`phone`/`address` nullable, `is_own_store` non-null bool (defaults `false`).
- **Trade** `{id, name, created_at, updated_at}` (`models/trade.dart:18-24`).
- **EquipmentItem** `{id, name, ownership, rate, rate_unit, created_at, updated_at}` (`models/equipment.dart:65-82`). `ownership` ∈ `owned, rented`; `rate_unit` ∈ `hour, day`; unknown enum values are a client error (`models/json_utils.dart:38-44`), so both are sent always. Backend model is `apps.master_data.EquipmentItem` — **not** `apps.site_inventory.Equipment` (that is serialized per-site asset tracking with `asset_code`/`site`/`status`, P1D), and no `hourly_rate` field: the Flutter master carries `rate` + `rate_unit` and derives cost per hour as `rate / 8` for day rates (`models/equipment.dart:56-60`).

**Server-side only additions (no Flutter key; the client ignores unknown keys and never sends them):**

- `MaterialItem.pos_code` — nullable POS selling-unit barcode (decision 05 §3, `MAP.md` 1.2). Populated in Phase 3 from POS `GET /api/v1/integration/cpms/materials/`; the POS side keys items by `variant_uom.barcode_qr`.
- `Supplier.pos_payer_id` — nullable POS **customer** id (`PositiveBigIntegerField`), the payer an own-store PO bills. POS validates it as an active payer-type customer id (`qb_pos_inventory_system/backend_django/apps/requisitions/services.py:603-611`, `apps/integration/serializers.py:58`), so it is an integer, never a name.
- `Supplier.is_own_store` is **not** server-only — it round-trips today (`models/supplier.dart:12,33,58`) and picks the own-store PO path (decision 04).

### Routes

| Method | Path | Repository method | Who (active role) |
|---|---|---|---|
| GET | `company/` | `getCompany()` | any signed-in role, **including `client`** (the PDF footer prints the company name, `shared/widgets/app_pdf_button.dart:27`, and the client portal renders billings) |
| PATCH | `company/` | `saveCompany()` | `admin` only (Settings is an admin-only route, `core/layout/role_navigation.dart:36-41`) |
| GET | `company-settings/` | `getSettings()` | staff roles (not `client`) |
| PATCH | `company-settings/` | `saveSettings()` | `admin` only |
| GET | `master-data/materials/` | `getMaterials()` | staff roles |
| POST | `master-data/materials/` | `saveMaterial()` (id 0) | `admin`, `owner` |
| GET/PATCH | `master-data/materials/{id}/` | `saveMaterial()` | read: staff; write: `admin`, `owner` |
| GET | `master-data/suppliers/` | `getSuppliers()` | staff roles |
| POST | `master-data/suppliers/` | `saveSupplier()` (id 0) | `admin`, `owner` |
| GET/PATCH | `master-data/suppliers/{id}/` | `saveSupplier()` | read: staff; write: `admin`, `owner` |
| GET | `master-data/trades/` | `getTrades()` | staff roles |
| POST | `master-data/trades/` | `saveTrade()` (id 0) | `admin`, `owner` |
| GET/PATCH | `master-data/trades/{id}/` | `saveTrade()` | read: staff; write: `admin`, `owner` |
| DELETE | `master-data/trades/{id}/` | `deleteTrade()` | `admin`, `owner` |
| GET | `master-data/equipment/` | `getEquipment()` | staff roles |
| POST | `master-data/equipment/` | `saveEquipment()` (id 0) | `admin`, `owner` |
| GET/PATCH | `master-data/equipment/{id}/` | `saveEquipment()` | read: staff; write: `admin`, `owner` |

- `company/` and `company-settings/` are singletons of `request.user.company` — no id in the path, and a `{id}` path never accepts another company's row.
- Save = `POST` for a new record, `PATCH` for an existing one (the desktop sends the whole object either way).
- Lists stay paginated (`PAGE_SIZE` 50, `{count, next, previous, results}`); `jsonRows()` unwraps `results` (`core/network/api_client.dart:151-157`).
- Master lists are ordered by name, suppliers own-store first then name (`repositories/mock_master_data_repository.dart:41-46,66-67`).

**Who reaches the screens:** `admin` → "Master lists" + "Settings" (`core/layout/role_navigation.dart:36-41`); `owner` (PM) → "Price lists", the same page (`:79-84`); `accountant` and `site_engineer` have no route there but consume the lists — materials/trades/equipment in the daily-report form (`features/daily_reports/viewmodels/daily_report_form_viewmodel.dart:84-86`), suppliers in procurement (`features/procurement/viewmodels/procurement_lookups.dart:52-53`), trades for workers (`features/labor/viewmodels/workers_viewmodel.dart:40`). `client` reads none of them (403).

### Refusal messages (mock text, verbatim)

`400 {"detail": "<text>"}`; `HttpXRepository` rethrows it as `BusinessRuleException`.

| Case | Text | Source |
|---|---|---|
| Material name taken (case-insensitive, trimmed) | `A material with this name already exists.` | `repositories/mock_master_data_repository.dart:32` |
| Supplier name taken | `A supplier with this name already exists.` | `:59` |
| Trade name taken | `This trade is already listed.` | `:80` |
| Required name | `Enter the material name.` / `Enter the supplier name.` / `Enter the trade name.` / `Enter the equipment name.` | `services/master_data_rules.dart:8-9` via `mock_master_data_repository.dart:22-23,53-54,76,102-103` |
| Required unit | `Enter the unit.` | `services/master_data_rules.dart:8-9` via `:25` |
| Missing / negative unit cost | `Enter the unit cost.` / `The unit cost cannot be negative.` | `services/master_data_rules.dart:25-29` via `:26-28` |
| Missing / negative equipment rate | `Enter the rate.` / `The rate cannot be negative.` | `services/master_data_rules.dart:25-29` via `:105-107` |
| Company name / address / PCAB no. | `Enter the company name.` / `Enter the address.` / `Enter the PCAB license number.` | `repositories/mock_company_repository.dart:16-25` |
| TIN | `Enter the TIN.` / `Use the format 000-000-000-000.` | `services/master_data_rules.dart:12-17` via `mock_company_repository.dart:22` |
| Settings percentages | `Enter the retention.` / `The retention must be 0–100%.` (same for `down payment`, `behind-schedule threshold`) | `services/master_data_rules.dart:31-35` via `mock_company_repository.dart:33-40` |

`403 {"detail": "…"}` for an active role that may not write: *proposed* texts (the mocks have no permission checks) — `Admin role required.` / `Project Manager or Admin role required.` from the existing permission classes in `django-backend/apps/users/permissions.py`.

### Finance redaction (server-side, per active role)

`seesFinance` = `owner`, `accountant` (`models/app_role.dart:19-22`, `apps/users/capabilities.py:FINANCE_ROLES`). A user holding both `admin` and `owner` (decision 03) sees prices only while acting as `owner`.

| Key | owner / accountant | admin | site_engineer | client |
|---|---|---|---|---|
| `MaterialItem.default_unit_cost` | ✔ | **`0`** | `0` | no access |
| `EquipmentItem.rate` | ✔ | **`0`** | `0` | no access |

- These two keys are **zeroed, not omitted** — `MaterialItem.fromJson` / `Equipment.fromJson` parse them with the non-null `JsonUtils.toDouble` (`models/material_item.dart:47`, `models/equipment.dart:74`), which throws `FormatException` on a missing key (`models/json_utils.dart:4-7`). This is the one place Phase 1 departs from the Phase 2 "omit" convention, and it matches the UI: the list prints `Unit: <unit>` and hides the peso amount (`features/user_management/views/master_lists_page.dart:75,239,239`), and the dialogs hide the price inputs (`features/user_management/widgets/user_management_material_dialog.dart:55,93`, `..._equipment_dialog.dart:50,89`).
- A non-finance write never touches a price: the incoming value is ignored and the stored one is kept (create → `0`), exactly as the dialogs re-send the untouched base value (`user_management_material_dialog.dart:55-57`).
- No other Phase 1.2 field is financial. `Company`/`CompanySettings` hold no peso amounts (percentages only), so they are readable by every staff role; writes stay admin-only.

### Uniqueness

- Case-insensitive after trimming, enforced by a DB constraint **and** a serializer check that returns the mock text: `MaterialItem.name`, `Supplier.name`, `Trade.name`. Blank/whitespace names are refused with the "required" message.
- `EquipmentItem.name` has **no** uniqueness rule — the mock has none (`repositories/mock_master_data_repository.dart:99-115`). Kept that way (see flags).
- Names are stored trimmed; leading/trailing spaces never create a duplicate.

### Delete semantics

- `Trade` is the only list with `deleteTrade()` (`repositories/master_data_repository.dart:19`) → `DELETE master-data/trades/{id}/` hard-deletes and answers `204`.
- Materials, suppliers and equipment have no delete in the interface → `405` on `DELETE` (edit instead; the UI shows only an edit affordance, `features/user_management/views/master_lists_page.dart:73-84`).
- No soft-delete/`is_active` flag is added: no Flutter model carries one (`models/material_item.dart:16-24`, `models/supplier.dart:14-26`, `models/equipment.dart:44-53`), so a hidden row could not be distinguished by the desktop.

### Audit (server-written, inside the same transaction)

The views write the row; the desktop's own `AdminAudit.record()` calls (`features/user_management/viewmodels/{company_profile_viewmodel,settings_viewmodel,master_lists_viewmodel}.dart`) become duplicates once task 1.3/2.3 swap the repositories — they must be dropped then. Actions/entities keep today's names so the audit log reads the same:

Failed logins: wrong password, inactive account, and no-role account each write one `login_failed` row against that user (`{reason: incorrect_password|inactive|no_role}`); an unknown email writes no row because `AuditLog.user_id` is non-null (the Flutter `AuditLog` model parses it as a non-null int) and instead emits a WARNING on the `cpms.security` logger with the sha256 of the normalized email plus the client IP, so failures stay auditable without either faking a user or logging a raw address of a non-user.

| Action | Entity | Details |
|---|---|---|
| `company_profile_updated` | `company` | `{name}` |
| `settings_updated` | `company_settings` | `{retention_pct, down_payment_pct, behind_schedule_pct}` |
| `material_created` / `material_updated` | `material` | `{name}` |
| `supplier_created` / `supplier_updated` | `supplier` | `{name}` |
| `trade_created` / `trade_updated` / `trade_deleted` | `trade` | `{name}` |
| `equipment_created` / `equipment_updated` | `equipment` | `{name}` |

### Security checks this section must prove with tests

Client refused on every master list and on settings; `site_engineer` and `accountant` read lists but cannot write; `default_unit_cost` / `rate` are `0` for `admin` and `site_engineer` and real for `owner`; a non-finance write leaves an existing price unchanged; duplicate names (any case, with padding) refused with the exact mock text; `DELETE` on a material/supplier/equipment → `405`; trade delete writes an audit row and is refused for `site_engineer`; `pcab_license_expiry` always a date; every write writes exactly one audit row and no client-supplied audit row is honoured.

### Flagged, not decided (needs owner input)

1. **`EquipmentItem` has no uniqueness in the mock** — two mixers with the same name are accepted. Kept as-is; adding a constraint later is a one-line migration plus a new refusal message.
2. **`Trade` hard delete** — Phase 4 `Worker.trade` / `ReportManpower.trade` are trade *names* (`models/report_manpower.dart:16`); once those exist, deleting a trade leaves history pointing at a name no longer listed. Suggest `PROTECT` or a snapshot then (Phase 4 decision).
3. **`pcab_license_expiry` is required by Flutter but optional in the DB** — a deployment without a PCAB license cannot serialize a company. Task 1.2 seeds a placeholder date on the existing row (mock uses `2026-12-15`, `repositories/mock_company_data.dart:15-22`) and requires the field on write. A real fix needs a product decision (nullable + client change, or a "no license yet" flag).
4. **`MaterialItem.default_unit_cost` is `0` for `admin`** — an Admin/Owner account reading the page as `admin` sees "Unit: bag" instead of a price, because `FINANCE_ROLES` excludes `admin` (decision 03: finances arrive through the `owner` role). If that is unwanted, the fix belongs in `apps/users/capabilities.py`, not here.
5. **`is_own_store` is a plain flag** — nothing stops two own-store suppliers or zero of them. The own-store PO path (decision 04) should refuse `0`/`>1` at PO creation; not enforced in 1.2.
6. **`default_unit_cost` at zero** — a material legitimately priced `0` is indistinguishable from a redacted one; property lists only show prices to finance roles, so this is display-only today, but Phase 3 costing must not treat `0` as "unknown".
