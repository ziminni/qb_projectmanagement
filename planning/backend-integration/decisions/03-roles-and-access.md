# Roles, authentication, project scope, and security-by-design

**Status:** Locked (revisable if build-time edge cases arise).
**Choice:** Use the 5-role multi-role architecture agreed with teammate (`Admin / Owner`, `Project Manager`, `Site Engineer / Foreman`, `Accountant`, `Client`), preserve the teammate's UI/file structure, keep the `user_roles` junction flexible so `Owner` and `Admin` can be separated or merged cleanly anytime, and enforce security inside every phase. (by: me)

## Agreed Role Model & Mapping to Teammate's Code (`39da4ff`)

| Agreed Role | Code Enum (`apiValue`) | Project Scope | Responsibilities & Visibility |
|---|---|---|---|
| **1. Admin (Owner + Admin)** | `AppRole.admin` (`'admin'`) — or account holding `admin` + `owner` in `user_roles` | **All company projects** (`sees_all_projects = true`) | Full system administration (Users, Master lists, Settings, Audit log) **plus** full Owner oversight across all projects and company finances. Designed via `user_roles` + capability helpers so pure `admin` vs `owner` can be split anytime without schema breakage. |
| **2. Project Manager** | `AppRole.owner` (`'owner'`) | **Assigned projects only** (`project_assignments`) | Runs assigned projects end-to-end (schedule, approvals, own/external purchasing, billings, variation orders). Sees finances (`seesFinance = true`) for their assigned projects. Scales cleanly when the firm has multiple Project Managers. |
| **3. Site Engineer (with Foreman integrated)** | `AppRole.siteEngineer` (`'site_engineer'`) | **Assigned projects only** (`project_assignments`) | Daily reports, attendance, to-do checklist, material counts & requests, delivery confirmation. **No internal peso figures** (`seesFinance = false`). |
| **4. Accountant** | `AppRole.accountant` (`'accountant'`) | **All company projects** (financial scope) | Payroll processing, client billings & payments, retention, supplier payables, expense reports (`seesFinance = true`). |
| **5. Client** | `AppRole.client` (`'client'`) | **Own assigned project(s) only** (`project_assignments` / `project.client_id`) | Private read/approval portal only (`/client/*`): project progress, client-shared photos, progress billings, and variation orders to approve. Cannot access internal staff routes or internal costs. |

## Flexibility & UI Preservation Rules

1. **Preserve teammate's UI and file layout:**
   - Do not reorganize or rewrite the teammate's `flutter/lib/features/*` screens unless strictly necessary for backend integration.
   - Any UI adjustments or new additions (e.g. POS sync status badge/retry button or Admin/Owner project visibility) must follow the teammate's existing widget/viewmodel structure and be logged in the session/decision docs.
2. **Easy future split of Admin vs. Owner:**
   - Because `user_roles` stores multiple roles per user (`UserRole(user, role)`), an Owner-Admin account can hold both `admin` and `owner` (or backend permissions check capability flags like `can_view_all_projects`, `can_manage_users`, `sees_finance`). Pulling `Owner` out from `Admin` or merging the sidebar later is a pure configuration/navigation change.

## Security-by-Design Requirements (Enforced in Every Phase, Never Post-Dev)

1. **Authentication & Session Security (Phase 1):**
   - Remove public self-registration role escalation (`POST /api/v1/auth/register/` disabled or restricted to `admin` user provisioning).
   - Lock `PATCH /api/v1/auth/me/` so authenticated users cannot modify `role`, `roles`, `is_staff`, `is_superuser`, or `is_active`.
   - Rate-limit login attempts, normalize emails, validate password strength, and rotate/blacklist JWT refresh tokens on logout.
2. **Object-Level Authorization / IDOR Prevention (Phases 2–4):**
   - Every project-scoped queryset (`Project`, `Category`, `Todo`, `DailyReport`, `ProjectDocument`, `MaterialRequest`, `PurchaseOrder`, `Delivery`, `PayrollPeriod`, `ProgressBilling`, `VariationOrder`) must filter by the authenticated user's role and active `ProjectAssignment` on the server — never rely on client-side filtering.
   - `Client` endpoints (`/client/*` or client-scoped reads/approvals) strictly enforce that the project belongs to that client user; clients cannot mutate internal schedule/procurement/labor data.
3. **Server-Side Financial Redaction (Phases 2–4):**
   - When the caller's active role does not have `seesFinance` (e.g. `site_engineer`), serializers omit or zero out confidential peso fields (`contract_amount`, `budget`, `unit_price`, `total_amount`, `daily_rate`, `gross_pay`).
4. **Cross-System Service Boundary & Upload Safety (Phases 2–3):**
   - POS service credentials (`CPMS Service` JWT) stay strictly on the CPMS Django server (`os.environ`), never sent to the Flutter desktop client.
   - Uploaded documents and receipt photos validate file extension, MIME type, and maximum size, and are served through authenticated/scoped endpoints rather than world-readable public buckets.
