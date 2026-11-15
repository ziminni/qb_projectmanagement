# Phase 2 wire contract — projects, assignments, schedule, daily reports, documents

**Status:** Rulings applied for the 2.1 build (revisable — update here first if building proves it wrong).
**Rulings source:** [decision 06](../decisions/06-phase-2-contract-rulings.md). Where decision 06 and an earlier line of this contract differ, **decision 06 wins**; the earlier line is rewritten below and the matching Open question / risky rule is closed with a pointer.
**Source of truth for shapes:** the Flutter models in `flutter/lib/data/models/` (`project.dart`, `project_assignment.dart`, `category.dart`, `todo.dart`, `daily_report.dart`, `report_manpower.dart`, `report_material_usage.dart`, `report_photo.dart`, `equipment_log.dart`, `issue.dart`, `document.dart`) and the interfaces `project_repository.dart`, `schedule_repository.dart`, `daily_report_repository.dart`, `document_repository.dart`. Business rules come from the mocks and `data/services/{project_rules,schedule_rules,daily_report_rules,progress_calculator}.dart`. Backend serves these exact keys; Flutter is not reshaped to fit the backend.

All routes under `/api/v1/`. JSON keys are snake_case. Timestamps ISO-8601 UTC; date-only fields `yyyy-MM-dd`; decimals may be strings (`JsonUtils.toDouble` accepts both, `models/json_utils.dart:4-8`). Active role comes from `X-Active-Role` exactly as in Phase 1; every rule below that names a role means the **active** role, checked through `apps/users/capabilities.py` (`ALL_PROJECTS_ROLES`, `FINANCE_ROLES`, `sees_all_projects()`, `sees_finance()`), never by comparing strings in views.

Citation shorthand: `models/…`, `repositories/…`, `services/…` are under `flutter/lib/data/`; `features/…` is under `flutter/lib/`.

## Error conventions

- Business-rule refusal → `400 {"detail": "<exact mock text>"}`. `HttpXRepository` rethrows `detail` as `BusinessRuleException` / `ScheduleRuleException` so the same text shows as today.
- In scope but the active role may not do it → `403 {"detail": "<exact mock text>"}` (or the proposed text, marked *proposed*, where the mock has none).
- Object outside the caller's project scope → `404 {"detail": "Not found."}`, even where the mock has its own text ("This request is not yours.", "Project not found."). No existence leaks across projects.
- Wrong `X-Active-Role` → Phase 1 `403 {"code": "ROLE_NOT_HELD"}`.

### 403 texts 2.1 added (*proposed* — the mock had no text)

| Route | Text |
|---|---|
| `POST projects/` | "Only a project manager can create a project." |
| `PATCH projects/{id}/` | "Only the owner running this project can edit it." |
| `projects/{id}/status/` | "Only the owner can move a project to {to.label}." (mock text, now a real 403) |
| `projects/{id}/resend/` | "Only the owner running this project can send it again." |
| `projects/{id}/assignments/` | POST: "Only the owner running this project can add people to it."; GET (client): "Only the project team can see who is on the project." |
| `project-assignments/{id}/` DELETE | "Only the owner running this project can remove people from it." |
| `project-assignments/?user=` | "You can only see your own assignments." |
| `users/{id}/assignments/` | "Admin role required." |
| `categories` and `todos` writes | "Only the owner running this project can change its schedule." |
| `todos/{id}/verify/`, `unverify/` | "Only the owner running this project can verify to-dos." |
| `todos/{id}/done/` | "Only the site engineer or owner assigned to this project can tick to-dos." |
| `clients/` | "Client records are staff-only." |
| `POST projects/{id}/status/` with an unknown/`declined` value | `400` "Choose a valid status." |

## Project scoping (every project-scoped queryset)

"In scope" = the project is visible to the caller in the active role. Implemented once (e.g. `apps/projects/scoping.py::projects_for(user, role)`) and reused by every viewset, mirroring `repositories/mock_project_repository.dart:41-51`.

| Active role | Projects in scope | Reads | Writes |
|---|---|---|---|
| `admin` | all (`ALL_PROJECTS_ROLES`) | everything except `contract` documents (admin is not a finance role) | user assignments (`users/{id}/assignments/`), unassign. No schedule/report/status writes. |
| `accountant` | all (`ALL_PROJECTS_ROLES`) | everything, incl. finance keys and contracts | none in Phase 2 |
| `owner` (PM) | projects with an **accepted** `owner` assignment for the caller | everything, incl. finance keys | create project; edit/status/resend/team on assigned projects; schedule CRUD; verify/unverify; approve/return reports; upload/delete documents |
| `site_engineer` | projects with an **accepted** `site_engineer` assignment | projects (redacted), schedule (redacted), reports, documents except `contract` | mark to-dos done; daily report drafts/submit; photo + document upload |
| `client` | projects with an **accepted** `client` assignment | portal reads only: own projects (client redaction), categories/to-dos (progress), approved report photos, own pending requests | respond to own request only |

- Pending / `not_sent` / declined / `changes_requested` assignments grant **no** scope (`models/project_assignment.dart:55`, `repositories/project_repository.dart:21-24`). An invitee sees the project only through `project-requests/`.
- Scope is by assignment, not `projects.client_id` (the mock never reads `client_id` for access) — decision 06 #4.

## Finance redaction (server-side, per active role)

`seesFinance` = `owner`, `accountant` (`models/app_role.dart:19-22`). Redacted keys are **omitted** from the JSON (Phase 1 convention). A non-finance role cannot write a redacted key (security check 5 explains what 2.1 actually returns).

| Model.key | owner / accountant | admin | site_engineer | client |
|---|---|---|---|---|
| `Project.contract_amount` | ✔ | omit | omit | ✔ *(their own contract; shown at `features/client_portal/views/client_variation_order_detail_page.dart:113`; Q2)* |
| `Project.down_payment_pct` | ✔ | omit | omit | ✔ *(Q2)* |
| `Project.retention_pct` | ✔ | omit | omit | ✔ *(Q2)* |
| `Category.budget` | ✔ | omit | omit | omit |
| `Document` rows with `doc_type = contract` | ✔ | row hidden | row hidden | no document access (Q5) |

UI evidence for the split: `features/projects/views/project_overview_page.dart:103-131` (contract amount, earned value, down payment, retention only if `seesFinance`), `features/schedule/viewmodels/schedule_viewmodel.dart:64` + `features/schedule/widgets/schedule_category_card.dart:132-137` (budgets), `features/documents/viewmodels/project_documents_viewmodel.dart:46-55` (contracts "carry the contract price").

**Resolved — Q1 (decision 06 #1):** keys stay omitted; `Project.fromJson` is changed in 2.3 to read an absent `contract_amount` / `down_payment_pct` / `retention_pct` as `0` (`?? 0`), recorded as a frontend addition. The server never sends them to `admin` or `site_engineer`.
**Resolved — Q3 (decision 06 #3):** every `Category` payload carries a server-computed `weight` (0–1) for **all** roles, so progress matches across roles; `budget` stays finance-only. Weight = `budget / total budget` when every category of the project has a positive budget, else `1 / N` — exactly `computeProjectProgress`'s rule (`services/progress_calculator.dart:117-152`). 2.3 uses `weight` when `budget` is absent.

No other Phase 2 model carries pesos. Material/equipment rates live on Phase 1.2 masters. Daily-report rows carry only ids, quantities and hours.

## Shapes

- **Project** `{id, code, name, location, latitude, longitude, client_id, contract_amount, down_payment_pct, retention_pct, start_date, target_end_date, actual_end_date, status, created_at, updated_at}`. `status` ∈ `requested, changes_requested, site_engineer_pending, accepted, ongoing, completed, closed, on_hold` (`models/project.dart:3-16`). `client_id` → `clients.id` (a client record, not a user; Q4).
- **ProjectAssignment** `{id, project_id, user_id, role_on_project, response, note, responded_at, created_at, updated_at}`. `role_on_project` ∈ `owner, site_engineer, client` (`services/project_rules.dart:8-12`). `response` ∈ `not_sent, pending, accepted, changes_requested, declined` (`models/project_assignment.dart:6-14`). Always sent (Flutter defaults a missing one to `accepted`, `:79-81`, which must never happen silently).
- **ProjectRequest** (wire wrapper for `repositories/project_repository.dart:6-11`) `{project, assignment}`. `project` is redacted for the invitee's role.
- **Category** `{id, project_id, name, budget, weight, sort_order, created_at, updated_at}`. `budget` is nullable and finance-only; `weight` is computed per request for every role (decision 06 #3 — see Finance redaction). Progress and status are never stored (`models/category.dart:3-4`).
- **Client** `{id, name, contact_person, email, phone, address, user_id, created_at, updated_at}` (`models/client.dart`). `user_id` is the portal login this client record is linked to, or `null` when none exists yet.
- **Project status `declined`:** a client decline keeps the project row with `status = declined` (decision 06, R1). `declined` is **never serialized** — such projects are excluded from every list and every scoped read, so no Flutter enum ever has to parse it.
- **Todo** `{id, category_id, title, start_date, end_date, is_done, done_by, done_at, is_verified, verified_by, verified_at, daily_report_id, created_at, updated_at}` (`models/todo.dart:88-103`). Note: decision 05 lists `done_report_id` / `verification_note`; the Flutter keys are `daily_report_id` with no `verification_note`. **Flutter wins**, and the unverify reason goes to the audit log only (`repositories/mock_schedule_repository.dart:242-248`). Update decision 05.
- **DailyReport** `{id, project_id, report_date, weather, status, submitted_by, reviewed_by, remarks, toolbox_meeting_held, created_at, updated_at}`. `weather` ∈ `sunny, cloudy, light_rain, heavy_rain, typhoon`; `status` ∈ `draft, submitted, approved, returned` (`models/daily_report.dart:3-40`). `submitted_by` = the author (set on create, not on submit).
- **ReportManpower** `{id, daily_report_id, trade, headcount, created_at, updated_at}`. `trade` is a trade **name** string, not an FK (`models/report_manpower.dart:16`).
- **ReportMaterialUsage** `{id, daily_report_id, material_id, quantity, created_at, updated_at}`. `material_id` → Phase 1.2 `MaterialItem`.
- **EquipmentLog** `{id, equipment_id, project_id, log_date, hours_used, daily_report_id, created_at, updated_at}`. `equipment_id` → Phase 1.2 `EquipmentItem`; `log_date` = the report date (`repositories/mock_daily_report_repository.dart:191-199`).
- **Issue** `{id, project_id, daily_report_id, type, reason, description, days_lost, created_at, updated_at}`. `type` ∈ `delay, safety, other`; `reason` ∈ `rain_typhoon, material, labor, client, other` (`models/issue.dart:3-35`).
- **ReportPhoto** `{id, daily_report_id, file_url, caption, latitude, longitude, taken_at, created_at, updated_at}`. `file_url` is a scoped API URL (see Uploads).
- **DailyReportDetail** `{report, manpower[], materials[], equipment[], issues[], photos[], todos[]}`. `todos` = to-dos with `daily_report_id == report.id` (`repositories/daily_report_repository.dart:10-29`, `mock_daily_report_repository.dart:67-83`).
- **Document** `{id, project_id, name, doc_type, file_url, uploaded_by, created_at, updated_at}`. `doc_type` ∈ `contract, plan, permit, as_built, other` (`models/document.dart:3-8`). Flutter derives the displayed file name from the **last path segment** of `file_url` (`models/document.dart:44`), so the download URL must end in the sanitized original file name.

## Projects (`ProjectRepository`)

| Method | Path | Who | Body → Response / refusals |
|---|---|---|---|
| GET | `projects/` | any role (scoped) | → `[Project]` scoped + redacted. Serves `getProjects()` and `getProjectsFor(userId, role)`: the server always scopes by caller and active role and ignores client-sent ids. Admin user-management (`features/user_management/viewmodels/user_form_viewmodel.dart:79`) gets all projects through `ALL_PROJECTS_ROLES`. |
| GET | `projects/{id}/` | any role (scoped) | → `Project`, or `404`. |
| GET | `clients/`, `clients/{id}/` | staff roles | → `[Client]` / `Client` (*new*, needed so the project form can pick `client_id`; read-only in 2.1 — no client write route is specified yet). |
| POST | `projects/` | `owner` | `{code, name, location, latitude, longitude, client_id, contract_amount, down_payment_pct, retention_pct, start_date, target_end_date}` → `201 Project` with `status = requested` (client-sent `status` ignored, `mock_project_repository.dart:410-419`). In the same transaction the server creates the caller's `owner` assignment (`accepted`) so the project is in scope for the follow-up calls (Q6 / decision 06 #6). A non-`owner` active role → `403` "Only a project manager can create a project." (*proposed*). Refusals `400`: "Enter the project code." / "Enter the project name." (`:384-389`); "Enter the contract amount." / "Contract amount must be greater than 0." (`services/project_rules.dart:15-16`); "Choose the start and target end dates." / "Target end date must be after the start date." (`:21-26`); "The down payment must be 0–100%." / "The retention must be 0–100%." (`:30-34`, labels from `mock_project_repository.dart:397-400`); "Another project already uses this code." (`:403-407`; the code is trimmed and upper-cased, `:402`, and the check is case-insensitive unique). Client checks (`features/projects/viewmodels/project_form_viewmodel.dart:77-83`): "Choose the client." / "This client has no app login yet. Ask the admin to create one." |
| PATCH | `projects/{id}/` | `owner` assigned (`features/projects/viewmodels/project_overview_viewmodel.dart:74`) | Same fields and validations. `status`, `actual_end_date`, `created_at` are read-only (`mock_project_repository.dart:421-429`). In scope but not the assigned `owner` → `403` "Only the owner running this project can edit it." (*proposed*). **Server-enforced** (today UI-only, `project_form_viewmodel.dart:89-98`): once the status is `ongoing/on_hold/completed/closed`, a changed `contract_amount` → `400` "Once work starts the contract amount changes only through approved variation orders." (*proposed text*); once the client has accepted (any status past `requested`/`changes_requested`), a changed `client_id` → `400` "The client cannot be changed once the client has accepted the project." (*proposed*, decision 06 #4). |
| POST | `projects/{id}/status/` | `owner` assigned | `{status}` → `Project`. Allowed moves (`services/project_rules.dart:39-51`): accepted→ongoing; ongoing→completed / on_hold; on_hold→ongoing; completed→closed. Request statuses have no manual moves. Refusals: `400` "A project cannot move from {from.label} to {to.label}." (`:75-77`); `403` "Only the owner can move a project to {to.label}." (`:78-80`). Moving to `completed` sets `actual_end_date` = today (`mock_project_repository.dart:447-449`). Server writes audit `project_status_changed {from,to}` and notifies every other **accepted** member: `project_status`, "{code} {name} is now {label}." (`:452-467`). |
| POST | `projects/{id}/resend/` | `owner` assigned | → `Project`. Only from `changes_requested`, else `400` "Only a project the client asked to change is sent again." (`:303-307`); not the assigned owner → `403` "Only the owner running this project can send it again." (`:308-312`). Effects: status → `requested`; client assignments in `changes_requested` → `pending`, `responded_at` cleared, request notification re-sent; audit `project_request_resent` (`:313-331`). |
| — | *(applyVariation)* | — | **No public route.** Contract amount and target end change only server-side when a VO is approved (Phase 4, called from `mock_billing_repository.dart:490`). |

### Assignments and requests

| Method | Path | Who | Body → Response / refusals |
|---|---|---|---|
| GET | `projects/{id}/assignments/` | staff roles (scoped); client → `403` "Only the project team can see who is on the project." (*proposed*) | → `[ProjectAssignment]`, all responses incl. pending/declined (`repositories/project_repository.dart:26-27`). |
| GET | `project-assignments/?user={id}` | `admin`, or the caller for themself (anyone else → `403` "You can only see your own assignments." (*proposed*)) | → `[ProjectAssignment]` (`getAssignmentsForUser`). Filters `project`, `role_on_project`, `response`. A non-numeric `user`/`project` → `400` "The {user,project} filter must be a number." (*new*; review 2.1 minor 3). `HttpProjectRepository.isAssigned` = this list filtered to `response=accepted` (or derive from `GET projects/` for the caller). |
| PUT | `users/{id}/assignments/` | `admin` | `{assignments: [{project_id, role}]}` → `[ProjectAssignment]`. Replaces the user's set; kept (project, role) pairs keep their row and response; new rows get the first response below and send their request (`mock_project_repository.dart:72-106`). Role not held → `400` "The user does not hold the {role.label} role." (`:76-83`). |
| POST | `projects/{id}/assignments/` | `owner` assigned (`project_overview_viewmodel.dart:75`) | `{user_id, role_on_project}` → `201 ProjectAssignment`. Role not held → `400` "The user does not hold the {role.label} role." (`:341-345`). A declined row for the same (project, user, role) is replaced (`:346-353`). Any other existing row → `400` "Already on this project." (`:354-361`). |
| DELETE | `project-assignments/{id}/` | `owner` assigned to that project, or `admin` | → `204` (`:375-377`). See R7. |
| GET | `project-requests/` | any role | → `[ProjectRequest]` = the caller's assignments in the active role with `response = pending` (`:158-166`). |
| POST | `project-assignments/{id}/respond/` | the assignee (else `404`) | `{response, note}` → `ProjectAssignment`. Not pending → `400` "You already answered this request." (`:181-183`). `response` `pending`/`not_sent` → `400` "Accept, decline or ask for changes." (`:197-200`). `changes_requested` by a non-client → `403` "Only the client can ask for changes." (`:190-195`). `declined`/`changes_requested` with a blank note → `400` "Add a note so the owner knows why." (`services/project_rules.dart:54-57`). The note is trimmed and stored, or null on accept (`:202`). Audit `project_request_{response}` `{role, note}` (`:212-218`). |

First response on assign (`mock_project_repository.dart:108-122`): `owner` → `accepted` at once. `client` → `pending`. `site_engineer` → `not_sent` while the project is `requested`/`changes_requested`, otherwise `pending`. A row created as `pending` sends a `project_request` notification (`:124-139`).

## Schedule (`ScheduleRepository`)

| Method | Path | Who | Body → Response / refusals |
|---|---|---|---|
| GET | `projects/{id}/categories/` | any role (scoped) | → `[Category]` by `sort_order` (`mock_schedule_repository.dart:33-36`); `budget` redacted per table. |
| GET | `projects/{id}/todos/` | any role (scoped) | → `[Todo]` for the project's categories (`:38-45`). The client needs these for progress (`features/client_portal/viewmodels/client_progress_viewmodel.dart:54-55`). |
| POST | `projects/{id}/categories/` | `owner` assigned (`schedule_viewmodel.dart:60`) | `{name, budget, sort_order}` → `201 Category`. Refusals: "Enter a category name." (`services/schedule_rules.dart:14-15`); "Budget cannot be negative." (`:17-18`); "Total category budgets (₱{total}) would exceed the contract amount (₱{contract})." (`:22-33`, the other categories' total excludes this one, `mock_schedule_repository.dart:55-64`). |
| PATCH | `categories/{id}/` | `owner` assigned | Same fields and rules. `project_id` is immutable (the mock lets the body move it, `:80-86`; R5). |
| DELETE | `categories/{id}/` | `owner` assigned | → `204`; cascades its to-dos (`:96-97`). Any verified to-do → `400` "This category has verified to-dos and cannot be deleted." (`services/schedule_rules.dart:72-75`). |
| POST | `todos/` | `owner` assigned to the category's project | `{category_id, title, start_date, end_date}` → `201 Todo` with done/verified flags false (`mock_schedule_repository.dart:117-128`). Refusals: "Enter a to-do title." (`schedule_rules.dart:49-50`); "Choose start and end dates." / "End date must be on or after the start date." / "Dates must fall within the project schedule ({start} to {target_end})." (`:54-69`). |
| PATCH | `todos/{id}/` | `owner` assigned | Only `title, start_date, end_date, category_id` (`mock_schedule_repository.dart:130-139`). Done/verify fields are read-only here. A new `category_id` must belong to the **same project** (`404` otherwise; R5). |
| DELETE | `todos/{id}/` | `owner` assigned | → `204`. Verified → `400` "A verified to-do cannot be deleted. Un-verify it first." (`schedule_rules.dart:77-79`). |
| POST | `todos/{id}/done/` | `site_engineer` or `owner` assigned (`schedule_viewmodel.dart:62-63`) | `{done}` → `Todo`. Un-done while verified → `400` "This to-do is verified. The owner must un-verify it first." (`schedule_rules.dart:81-83`). A no-op when unchanged (`mock_schedule_repository.dart:160`). Sets/clears `done_by`, `done_at`. Audit `todo_marked_done`/`todo_marked_not_done`. On done, notifies the project's owners: `todo_done`, "\"{title}\" was marked done on {code}. Verify it." (`:162-189`). |
| POST | `todos/{id}/verify/` | `owner` assigned (`schedule_viewmodel.dart:61`) | → `Todo`. "This to-do is already verified." / "Only to-dos marked done can be verified." (`schedule_rules.dart:85-89`). Sets `is_verified`, `verified_by`, `verified_at`; audit `todo_verified` (`mock_schedule_repository.dart:205-224`). |
| POST | `todos/{id}/unverify/` | `owner` assigned | `{reason}` → `Todo`. "This to-do is not verified." / "Enter a reason for un-verifying." (`schedule_rules.dart:91-97`). Clears the verify fields; audit `todo_unverified {reason}` (`mock_schedule_repository.dart:227-250`). |
| — | *(setReportLink)* | — | **No public route.** Linking happens only inside the daily-report save (below). `HttpScheduleRepository.setReportLink` throws `UnsupportedError`; its only caller is the mock report repo (`mock_daily_report_repository.dart:238,240`). |

Every `Category` payload also carries the server-computed `weight` (decision 06 #3), so a redacted `budget` never changes the progress a role sees. Progress stays client-computed by `computeProjectProgress` (decision 05): only verified to-dos count, budget weights apply when **every** category has a positive budget, otherwise equal weights (`services/progress_calculator.dart:117-152`), and `as_of` counts only to-dos verified on or before that date (`:192-197`). Redaction interacts with this; see Q3.

## Daily reports (`DailyReportRepository`)

| Method | Path | Who | Body → Response / refusals |
|---|---|---|---|
| GET | `daily-reports/?project=1,2&status=&from=&to=` | staff roles (scoped); client → `403` | → `[DailyReport]` newest first (`mock_daily_report_repository.dart:50-64`). `project` ids outside scope are dropped silently, never trusted. |
| GET | `daily-reports/{id}/` | staff roles (scoped) | → `DailyReportDetail`, or `404`. |
| POST | `daily-reports/` | `site_engineer` assigned to `project_id`, in the active role | Draft body (below) → `201 DailyReport` (`status = draft`, `submitted_by = caller`). A caller acting as another role (e.g. `owner` while also holding `site_engineer`) → `403` "Only the site engineer assigned to this project can file its reports." |
| PUT | `daily-reports/{id}/` | the report's author (R6), in the active `site_engineer` role | Same body; replaces every child list; `project_id` immutable. |
| POST | `daily-reports/{id}/submit/` | the author, in the active `site_engineer` role | → `DailyReport`. |
| POST | `daily-reports/{id}/approve/` | `owner` assigned | → `DailyReport`. |
| POST | `daily-reports/{id}/return/` | `owner` assigned | `{remarks}` → `DailyReport`. |
| GET | `projects/{id}/approved-material-usage/` | staff roles (scoped) | → `[ReportMaterialUsage]` from approved reports only (`:359-371`). |
| GET | `projects/{id}/approved-equipment-logs/` | staff roles (scoped) | → `[EquipmentLog]` from approved reports only (`:373-377`). |
| GET | `report-photos/approved/?project=1,2` | any role (scoped; client included) | → `[{photo, report}]` newest by `taken_at`, falling back to the report date (`:379-398`); used by `features/client_portal/viewmodels/client_photos_viewmodel.dart:44`. |

**Draft body** (from `DailyReportDraft`, `repositories/daily_report_repository.dart:65-91`): `{project_id, report_date, weather, toolbox_meeting_held, manpower: [{trade, headcount}], materials: [{material_id, quantity}], equipment: [{equipment_id, hours_used}], issues: [{type, reason, description, days_lost}], photos: [{id, caption}], todo_ids: [int]}`. `photos` lists **existing** photo ids to keep (and their captions); omitted photo ids are deleted. New photo files go through the upload route below.

**Draft refusals** (in mock order): project not `ongoing` → `400` "Daily reports can be added only while the project is Ongoing (it is {status.label})." (`services/project_rules.dart:86-90`, `mock_daily_report_repository.dart:94`); caller not the assigned site engineer → `403` "Only the site engineer assigned to this project can file its reports." (`:95-103`); "Choose the report date." / "A daily report cannot be dated in the future." (`services/daily_report_rules.dart:9-15`, using the server's local date); duplicate (project, date) → `400` "There is already a report for this project on this date." (`:108-117`; also a DB unique constraint); "Headcount must be greater than 0." (`daily_report_rules.dart:17-19`); "Choose a trade for each manpower row." (`mock_daily_report_repository.dart:120-124`); "Quantity must be greater than 0." (`daily_report_rules.dart:21-22`); "Hours must be greater than 0." / "Hours cannot exceed 24 in a day." (`:24-28`); "Describe each issue." (`mock_daily_report_repository.dart:133-135`); "Days lost cannot be negative." (`daily_report_rules.dart:30-31`); updating a non-editable report → "This report is {status} and can no longer be edited." (`:34-37`); a chosen to-do already done and linked elsewhere → "\"{title}\" is already done." (`mock_daily_report_repository.dart:231-242`). Unknown `material_id` / `equipment_id`, or a `todo_ids` entry from another project → `400` (*new*, IDOR guard).

**To-do linking on save** (`:231-242`): chosen to-dos get `daily_report_id = report.id`. To-dos no longer chosen that are still not done are unlinked.

**Submit** (`:246-288`): "Only draft or returned reports can be submitted." (`daily_report_rules.dart:39-41`); not the author → `403` "Only the site engineer who wrote this report can submit it." (`:251-255`). Effects in one transaction: every linked not-done to-do → done (same side effects as `todos/{id}/done/`), status `submitted`, audit `daily_report_submitted`, notify the project's owners `report_submitted` "Daily report for {code} on {date} is waiting for your approval."

**Approve** (`:290-321`): "Only submitted reports can be approved or returned." (`daily_report_rules.dart:43-46`); not the assigned owner → `403` "Only the owner of this project can review its reports." (`mock_daily_report_repository.dart:400-406`). Effects: linked done, unverified to-dos → verified by the approver (audit `todo_verified` each), status `approved`, `reviewed_by` set, `remarks` cleared, audit `daily_report_approved`, notify the author `report_approved` "Your daily report for {date} was approved." Approved usage and equipment hours now feed site inventory and costing (decision 05).

**Return** (`:323-357`): same review guards plus "Add remarks so the site engineer knows what to fix." (`daily_report_rules.dart:49-52`). Effects: status `returned`, `reviewed_by`, `remarks` trimmed, audit `daily_report_returned {remarks}`, notify the author `report_returned` "Your daily report for {date} was returned: {remarks}".

## Documents (`DocumentRepository`)

| Method | Path | Who | Body → Response / refusals |
|---|---|---|---|
| GET | `projects/{id}/documents/` | staff roles (scoped); client → `403` (Q5) | → `[Document]` newest first (`mock_document_repository.dart:74-79`). `contract` rows only for finance roles (`features/documents/viewmodels/project_documents_viewmodel.dart:46-55`). |
| POST | `projects/{id}/documents/` | `owner` or `site_engineer` assigned | `multipart/form-data` `{name, doc_type, file}` → `201 Document`. Others → `403` "Only the project's owner or site engineer can upload." (`mock_document_repository.dart:94-97`). "Enter the document name." (`:99-100`). Bad extension → `400` "Choose a file of type pdf, dwg, dxf, jpg, jpeg, png, doc, docx, xls, xlsx." (`:102-108`). Same (project, type, name) case-insensitive → `400` "A document with this name already exists in this section." (`:109-118`). `doc_type = contract` by a non-finance role → `403` "Only the owner or accountant can file contracts." (*proposed*; today UI-only, `project_documents_viewmodel.dart:47-50`). |
| DELETE | `documents/{id}/` | the uploader, or the assigned `owner` | → `204`; else `403` "Only the uploader or the owner can delete this document." (`mock_document_repository.dart:133-146`). Removes the stored file too. |
| GET | `documents/{id}/file/{file_name}` | same as list (scoped + type visibility) | Streams the file (see Uploads). |

## Uploads

- Multipart only, through Django's storage on a **private** `MEDIA_ROOT` that is **never** mounted under a public URL (no `static()`/`MEDIA_URL` serving, no public bucket). Files are stored under a random name (`uuid4` + extension); the original name is kept sanitized in the DB.
- **Documents:** extensions `pdf, dwg, dxf, jpg, jpeg, png, doc, docx, xls, xlsx` (`mock_document_repository.dart:13-24`). Content is sniffed by magic bytes against the extension (PDF `%PDF`, JPEG `FFD8FF`, PNG `89504E47`, OOXML zip `PK\x03\x04`, OLE `D0CF11E0` for doc/xls, DWG `AC10`, DXF text). Max **25 MB** (*proposed*).
- **Report photos:** `POST daily-reports/{id}/photos/` multipart `{file, caption, latitude, longitude, taken_at}` → `201 ReportPhoto`. Only the author, only while the report is `draft`/`returned` (same edit refusal text). `jpg, jpeg, png, webp` only (decision 06 #7), magic-byte checked — WebP is a RIFF container, so both `RIFF` at byte 0 **and** `WEBP` at byte 8 are required (an arbitrary RIFF file or a truncated header is refused) — max **10 MB** (*proposed*). `taken_at` defaults to now (`mock_daily_report_repository.dart:226`). Delete through the draft's `photos` list.
- **Serving:** `file_url` = absolute `…/api/v1/documents/{id}/file/{sanitized_name}` or `…/api/v1/report-photos/{id}/file/{sanitized_name}`. The endpoint re-checks JWT + active-role scope (+ contract visibility), and responds with `Content-Disposition: attachment` (inline for photos), `X-Content-Type-Options: nosniff`, the stored MIME type, and `Cache-Control: private, no-store`. Flutter must fetch these through the Dio client (with `Authorization` + `X-Active-Role`), not `Image.network`.
- **Rollback safety:** removing a photo or a document deletes the stored file only after the database change commits (`transaction.on_commit`), so a failed save or audit never leaves a row pointing at a deleted file; a new upload whose transaction fails has its just-written file removed rather than orphaned.
- Oversize requests are refused before the body is read (`DATA_UPLOAD_MAX_MEMORY_SIZE` / `FILE_UPLOAD_MAX_MEMORY_SIZE` plus a per-view size check) → `413` / `400` "The file is larger than {N} MB." (*proposed*).

## State machines

**Project status** (`services/project_rules.dart:39-51`, `mock_project_repository.dart`):

```
create ─▶ requested ──client accepts──▶ site_engineer_pending ──SE accepted & nobody pending──▶ accepted
            ▲   │                                   │ (SE declines: stays; owner assigns another SE)
            │   └─client changes_requested─▶ changes_requested ──owner resend──▶ requested
            │
 client declines (from requested) ─▶ project status = declined, HIDDEN from lists (kept + audited)   (R1 / decision 06)
accepted ─▶ ongoing ⇄ on_hold ;  ongoing ─▶ completed (actual_end_date = today) ─▶ closed
```

- Client accept (`:242-260`): project → `site_engineer_pending`; every `not_sent` assignment → `pending` and its request is sent; notify owners "{who} accepted {code}. The site engineer has been sent the request."; then `_acceptIfReady`.
- `_acceptIfReady` (`:277-297`): from `site_engineer_pending` only. Becomes `accepted` when ≥1 site-engineer assignment is accepted and no client/SE assignment is still `pending`; notify owners "{code} is accepted by the client and the site engineer. Start it when work begins."
- Client changes requested (`:233-241`): project → `changes_requested`; notify owners "{who} asked for changes on {code}: {note}".
- Client declined (decision 06, R1 — **soft decline**): the client assignment becomes `declined` with the note, the project's `status` becomes `declined`, and the row is **kept** with everything it owns. Declined projects are excluded from `projects/`, every scoped read and every `?project=` filter, so any route touching one answers `404`; only the audit log still shows it. Audit `project_request_declined {role, note}` plus a `project_status_changed {from, to}` row (from = the status it had), and notify owners "{who} declined {code} {name}. Reason: {note}" (*proposed text — the mock's "so it was deleted" is no longer true*).
- SE declined (`:265-270`): notify owners "{who} declined {code}: {note} Choose another site engineer." Project status unchanged. SE accepted: notify "{who} accepted {code}." then `_acceptIfReady`.

**Assignment response:** `not_sent → pending` (client accepts) `→ accepted | declined | changes_requested(client only)`; `changes_requested → pending` (owner resend); `declined` row is replaced on re-assign. `owner` rows start `accepted`.

**To-do:** `open → done` (SE/owner, or report submit) `→ verified` (owner, or report approve); `verified → done` (owner unverify + reason); `done → open` only while unverified. The owner who marked a to-do done may also verify it — **allowed but audited** (decision 06 #R4), so the audit trail always shows both rows.

**Daily report:** `draft → submitted → approved` (locked) ; `submitted → returned → submitted`. Editable only in `draft`/`returned` (`models/daily_report.dart:15-17`).

## Audit and notifications

Server-written in the same transaction, as in Phase 1. No client `POST`. Audit actions: `project_request_{accepted|declined|changes_requested}`, `project_request_resent`, `project_status_changed`, `todo_marked_done`, `todo_marked_not_done`, `todo_verified`, `todo_unverified`, `daily_report_submitted`, `daily_report_approved`, `daily_report_returned`. Add `project_created`, `project_updated`, `assignment_created`, `assignment_removed`, `user_assignments_set`, `document_uploaded`, `document_deleted` (*new*; the mock has none, but these are security-relevant). `assignment_removed` uses the **assignment id** as `entity_id` (the row is gone, the id is still the subject) and keeps the member id in `details.user`. A client decline writes `project_request_declined` **and** `project_status_changed {from: requested, to: declined}` (the row is kept, decision 06 R1). Category and to-do CRUD writes no audit row of its own; to-do done/verify/unverify do. Notification types and texts are as quoted above (`project_request`, `project_status`, `todo_done`, `report_submitted`, `report_approved`, `report_returned`). Recipient sets must use **accepted** assignments only (R8). Notification `link` values are Flutter route strings (`AppRoutes.*`); the server stores the same strings.

## Security checks this phase must prove with tests

1. **IDOR across projects:** an owner, site engineer and client each assigned to project A get `404` on every project-B object route: `projects/{B}`, its assignments, categories, todos, documents and document file, daily-report detail, photo file, approved-photo/usage/equipment lists, plus every write (`PATCH`, `status`, `resend`, `todos/{id}/done|verify`, `daily-reports/{id}/approve`, `documents/{id}` delete). `?project=A,B` list filters return A rows only.
2. **Pending / declined / not_sent assignees** have no scope (`404` on the project), but see it in `project-requests/`.
3. **Client writes refused:** a client gets `403`/`404` on project create/patch/status, assignments, categories, todos (incl. `done`), daily reports, document upload/delete and photo upload. A client may only `respond` to their own pending request.
4. **Role/action matrix:** a site engineer cannot verify/unverify or approve/return; an owner not assigned to the project cannot; an admin cannot do schedule or report writes; an SE cannot edit or submit another SE's report; `X-Active-Role: site_engineer` on a user who also holds `owner` gets SE rights only.
5. **Redaction:** for `admin` and `site_engineer`, `contract_amount`, `down_payment_pct`, `retention_pct` and `Category.budget` are absent from list, detail, `project-requests/` and nested responses; for `client`, `budget` is absent; contract documents are hidden from the list and their file URL returns `404` for non-finance roles. Non-finance writes of these keys → `400`.
   *Built as:* in Phase 2 no non-finance role may write these keys at all — every such write is refused earlier with the role `403` above (only `owner` edits a project, only finance roles see or set budgets). A future non-finance write path must return the `400`.
6. **Uploads:** wrong extension, extension/magic-byte mismatch (e.g. `.pdf` holding HTML/EXE), oversize, path-traversal file names (`../../x.pdf`) are refused; stored names are random; files are unreachable without a JWT and in-scope role; `MEDIA_URL` returns `404`.
7. **Server-only state:** `status`, `submitted_by`, `reviewed_by`, `is_done`/`is_verified`/`verified_by`, `uploaded_by`, `response` cannot be set through create/update bodies. The contract amount is locked once a project is ongoing. There is no public `applyVariation` route.
8. **Transitions:** every refusal text above has a test; client decline hides the project without deleting anything (decision 06, R1).
9. **Category weight:** every role gets the same `weight` for the same category (`budget / total` when all budgets are positive, else `1 / N`), and `budget` itself is only present for finance roles.

## Backend today vs. Phase 2 (`django-backend/apps/projects/`)

Built in 2.1 unless a row says 2.2.

| Was today | Phase 2 result |
|---|---|
| `Site` — referenced by `site_inventory` (`SiteStock`, `Tool`, `Equipment`, `EquipmentLog`) and `requisitions.MaterialRequest` | **Kept** (`sites/` route unchanged, still `IsAdminOrReadOnly`); its fate is a Phase 3 decision. `Project.site` stays as a **nullable** FK so those apps' fixtures keep working; Flutter never sends it. |
| `Project`: `site`, `manager`, `description`, `budget_amount`, upper-case status | **Rebuilt** to the Flutter shape: `location`, `latitude`, `longitude`, `client` FK, `contract_amount`, `down_payment_pct`, `retention_pct`, date fields and the lower-case status set (`declined` included in the DB only). `manager`, `budget_amount` and `description` are **kept as legacy columns, unexposed** (they are not in any serializer); the pre-2.1 status code is kept verbatim in the new `legacy_status` column. `code` is trimmed/upper-cased and unique case-insensitively. `financials`/`requisitions` only reference `Project` by FK and keep working; `requisitions/tests.py` moved from `ProjectStatus.IN_PROGRESS` to `ProjectStatus.ONGOING`. |
| `Contract` | **Kept as a legacy table, unexposed** (no route). Its unambiguous values are folded into `Project.contract_amount`/`retention_pct` + a `Client` record by migration `0005`; the row itself is never changed or deleted. The `contracts/` route is gone, so the API exposes only the folded columns. |
| `ProjectPhase`, `Milestone` | **Kept as legacy tables, unexposed** (no route), replaced functionally by `Category` + `Todo` (decision 05). No `Category`/`Todo` is derived from them: a phase has no provable category name, and a milestone has only a due date where a `Todo` needs a start date, so deriving rows would invent data. |
| Viewsets (`views.py`) all `IsAdminOrReadOnly`, unscoped, no redaction; routes `contracts/`, `project-phases/`, `milestones/` | **Rewritten** with `projects_for()` scoping + redaction; those three routes are gone. |
| — | **Added in 2.1**: `Client`, `ProjectAssignment` (unique `(project, user, role_on_project)`), `Category`, `Todo`, `apps/projects/scoping.py` (`projects_for`, object-scope helpers), `apps/projects/rules.py` (refusal texts + transition map), `apps/projects/services.py` (atomic writes, audit, notifications), and a `clients/` read route. |
| — | **2.2 still adds**: `DailyReport` (unique `(project, report_date)`), `ReportManpower`, `ReportMaterialUsage`, `EquipmentLog`, `Issue`, `ReportPhoto`, `Document`, upload validators, private media storage — in the new `apps/site_reports` app (decision 06 #10). `Todo.daily_report_id` is a plain nullable id in 2.1 and becomes an FK when 2.2 lands. |
| `site_inventory.EquipmentLog` (movement history: `event_type/site/note`) | **Name clash stays** until Phase 4/2.2 lands the daily-report hours model under a distinct name. |

## Legacy data preservation (migrations 0004 / 0005)

Rule: **0004 only adds.** It creates `Client`, `ProjectAssignment`, `Category`, `Todo` and the new `Project` columns and drops nothing that holds a pre-2.1 record (the only removal left is the old `(status, site)` index — an index, not data). `0005_legacy_project_data` copies the provable values forward and keeps every original row and column. Test: `apps/projects/tests_migration.py` (`MigrationExecutor`, pre-0004 fixtures → latest, asserts all rows/columns retained and the mapping below).

What is folded (source → destination, original preserved):

| Legacy | New | Why it is provable |
|---|---|---|
| `Project.status` | `status` + `legacy_status` | `IN_PROGRESS`→`ongoing`, `SUSPENDED`→`on_hold`, `COMPLETED`→`completed`, `CANCELLED`→`closed`; `PLANNING`/`MOBILIZATION`→`accepted`. The old code stays verbatim in `legacy_status`. |
| `Project.manager` | accepted `owner` `ProjectAssignment` | One manager = the project's owner/PM; without it the project would have no scope in the Phase 2 API. `manager` itself stays. |
| single `Contract` | `Project.contract_amount`, `retention_pct`, `client_id` (+ `Client` from `client_name`/`client_contact`) | Exactly one contract, so its `amount`/`retention_percent` are the project's terms. Only fills a column that is still `0.00`/null. |

What is **not** folded (the rows stay; this is the remaining reconciliation):

- A project with **two or more** contracts: `contract_amount`/`retention_pct` stay `0.00` and `client_id` stays null — which contract is "the" one is not provable, so nothing is guessed (or summed). The `Contract` rows remain in `apps_projects_contract` for finance to resolve by hand.
- `budget_amount` → `Category.budget`: needs a category name the source does not have. `budget_amount` stays on the project.
- `ProjectPhase`/`Milestone` → `Category`/`Todo`: not derivable (see the table row above).
- `down_payment_pct`: no legacy source; stays `0.00` until the owner/accountant enters it.
- Contract dates (`signed_date`, `completion_date`) and `notes`: no Phase 2 column; they stay in the `Contract` row.
- A project with **no** manager and no owner assignment still has no scope until someone is assigned (admin/accountant can see it).

Statuses outside both code sets (should not exist) become `requested` so the row stays parseable; `legacy_status` still carries the original.

**Hard gate:** any database that already ran the previous destructive `0004` (before this fix) has lost those columns/tables at the SQL level; the columns come back empty and the data must be restored from a backup. No live deployment was authorized (decision 01), so this applies only to a disposable dev/test database, which is recreated by re-running migrations from `0003`.

## Flutter rules that look wrong or risky (flagged; decided by [decision 06](../decisions/06-phase-2-contract-rulings.md))

- **R1 — RESOLVED (soft decline, decision 06):** a client decline deletes nothing. The project keeps its row with `status = declined`, disappears from every list and scoped read, and the decline is audited. See State machines.
- **R2 — RESOLVED (server enforces):** role checks on `saveProject`, `assign` and `unassign` are enforced on the server; the UI is no longer the only gate.
- **R3 — RESOLVED (server enforces):** the contract-amount lock after work starts is a `400` on the server (see the PATCH row).
- **R4 — RESOLVED (allowed but audited, decision 06):** the owner may mark a to-do done and verify it; both actions write audit rows, so progress earned through self-verification stays traceable. The owner may later require a different verifier.
- **R5 — RESOLVED (server rejects):** `project_id` on a category and `category_id` on a to-do cannot move a row across projects (`404`).
- **R6 — RESOLVED (server enforces the author):** 2.2 implements "only the author edits/submits their report".
- **R7 — OPEN (no ruling yet):** unassigning can still remove the only accepted owner or the last site engineer. 2.1 ships without a guard (the owner can always re-assign); tracked as Q12 below.
- **R8 — RESOLVED (server):** notification recipient sets are built from **accepted** assignments only.
- **R9 — OPEN for 2.2** (returning a report leaves its to-dos marked done).
- **R10 — RESOLVED by design:** project create is one atomic request; `client_id` is part of the project body and the owner's own assignment is created server-side. 2.3 no longer self-assigns (decision 06 #6).
- **R11 — RESOLVED (server scopes):** every list and detail route scopes server-side and ignores caller-sent ids.
- **R12 — RESOLVED (2.3 files):** the file-picker UI addition and the `DocumentRepository.upload` signature change are approved for 2.3 (decision 06 #7/#8).
- **R13 — RESOLVED by contract:** the server always sends `response` on an assignment, so the Flutter default never decides scope. A row with a missing `response` is a server bug.

## Open questions

All earlier questions are closed by [decision 06](../decisions/06-phase-2-contract-rulings.md); this table maps each one to its ruling so nothing is re-litigated later.

| Was | Now (decision 06 #) |
|---|---|
| Q1 redaction vs `Project.fromJson` | #1 — keys stay omitted; Flutter reads an absent key as `0` |
| Q2 client sees contract terms | #2 — yes, own project only |
| Q3 redacted `budget` changes progress | #3 — server sends `weight` to every role |
| Q4 scope / `client_id` lock / who builds `Client` | #4 — scope = active assignment; `client_id` locks after the client accepts; `Client` is built in 2.1 |
| Q5 client document access | #5 — approved report photos only; project Document rows remain staff-only (no visibility flag) |
| Q6 owner self-assignment on create | #6 — server creates it; Flutter drops its self-assign call |
| Q7 upload caps and types | #7 — 25 MB documents / 10 MB photos, magic bytes, DWG/DXF by extension, no HEIC |
| Q8 file picker + `upload` signature | #8 — approved for 2.3, recorded as a UI addition |
| Q9 pure admin vs finance | #9 — admin is not a finance role; the Admin/Owner account switches to `owner` |
| Q10 app placement / `EquipmentLog` clash | #10 — new `apps/site_reports` in 2.2; the old `site_inventory.EquipmentLog` stays until Phase 4 |
| Q11 report-date clock | #11 — server `timezone.localdate()` in `Asia/Manila` |

**Q12 (new, open — owner's call):** should unassigning refuse to remove the last accepted `owner` (and, once a project is `accepted`, the last accepted `site_engineer`)? 2.1 ships without the guard (R7). Default: allow — the owner can re-assign and nothing else breaks.

## Addendum — client writes (5.3, delegated revisable defaults)

- `POST /api/v1/clients/`, `PATCH /api/v1/clients/{id}/`, `POST /api/v1/clients/{id}/link-user/` and `.../unlink-user/`. No DELETE (405). Reads stay staff-only, unchanged.
- Writers: active owner or admin only (`scoping.require_client_writer`); accountant and others read-only.
- A linked user must hold the client role; one user per client; double link refused with a clean 400 using the mock's texts.
- Audit details carry the client name (and a user id on link); no contact details.
- Known limit: `Client.name` uniqueness is an application-level case-insensitive check, not a DB constraint, so a true simultaneous duplicate create can slip through. Add a constraint once legacy contract-folded names are reconciled.
- The user form saves the user first and links afterwards; a refused link leaves the saved user and shows the error.
