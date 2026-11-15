# Phase 4 billing contract — slice 4.2a: client-facing billing

Status: implementation brief. Delegated, revisable defaults — **not** owner-confirmed
production finance policy. Baseline: `feat/cpms-labor-foundation` (`c2bce8c`).
Branch: `feat/cpms-billing-foundation`.

## Boundary

Build the **client-facing billing** half of Phase 4 in `django-backend/apps/financials/`:

- `ProgressBilling` (draft → sent → client answer → paid/withdrawn),
- `ClientPayment` (the client's money against one billing),
- `VariationOrder` (proposal → owner pricing → client approval, applied to the
  project contract amount and target end date),
- `RetentionRelease` (retention withheld on approved billings, paid back after
  completion).

Deliberately **excluded** from this slice:

- Derived `ProjectCosts` / expense aggregation (`materials` from deliveries,
  `labor` from payroll, `equipment` from daily reports). Procurement valuation
  (Phase 3 blockers 1–2) and payroll processing policy are unresolved, so any
  aggregate would be invented money.
- POS collectibles, supplier payables, progress-billing tax/VAT lines.

The legacy tables already in `apps/financials/` (`ProjectBudget`, `ExpenseLog`,
`Collectible`, `CollectiblePayment`) and their routes stay as they are: additive
migrations only, no row destroyed, no route renamed.

Authoritative frontend shapes:
`flutter/lib/data/models/{progress_billing,payment,variation_order,retention_release,payment_method}.dart`,
`data/repositories/{billing_repository,mock_billing_repository}.dart`,
`data/services/{billing_rules,billing_calculator,progress_calculator}.dart`.
Existing backend active-role, capabilities and accepted-project-assignment rules
remain authoritative; the mock's authorization is **not** copied.

## Wire shapes

`ProgressBilling` — `id, project_id, billing_no, period_end, pct_accomplished,
gross_earned, less_previous, less_dp_recoupment, less_retention, net_due,
status, created_at, updated_at`.

- `billing_no` is server-assigned, per project, `max + 1`.
- `pct_accomplished` is cumulative 0–1 (6 dp); all money is `Decimal(14,2)`.
- `status` ∈ `draft, pending_client, disputed, approved, paid, rejected`.
- `this_period` is not stored; the detail/preview payload also carries the
  derived `this_period` (= `gross_earned - less_previous`) so the Flutter model's
  getter and the server cannot disagree.

`ClientPayment` — `id, progress_billing_id, amount, paid_on, method,
reference_no, created_at, updated_at`. `method` ∈ `cash, check, bank_transfer,
e_wallet`. `received_by` is server-owned, recorded in the audit row only.

`VariationOrder` — `id, project_id, vo_no, type, description, amount,
days_impact, status, approved_by_owner, approved_by_client, created_at,
updated_at`. `type` ∈ `additive, deductive, change`; `amount` is **signed**
(deductive is negative); `vo_no` is server-assigned per project (`VO-01`, …);
`status` ∈ `proposed, pending_client, approved, rejected`, and
`approved_by_owner` / `approved_by_client` are user ids or null.

`RetentionRelease` — `id, project_id, amount, released_on, method,
reference_no, created_at, updated_at`.

## Routes (all under `/api/v1/`)

Billings:

- `GET progress-billings/?project=&status=` — house pagination; newest period first.
- `GET progress-billings/{id}/` — the row plus `payments` and `history`
  (audit rows for `entity='progress_billing'`), matching `BillingDetail`.
- `GET progress-billings/preview/?project=ID&period_end=YYYY-MM-DD` — what a
  billing for that period would show, nothing saved.
- `POST progress-billings/` `{project_id, period_end}` → `201` draft.
- `POST progress-billings/{id}/submit/` — draft/disputed → `pending_client`.
- `POST progress-billings/{id}/withdraw/` — draft/disputed → `rejected`.
- `POST progress-billings/{id}/client-approve/` — `pending_client` → `approved`.
- `POST progress-billings/{id}/client-dispute/` `{reason}` — `pending_client` →
  `disputed`.
- `POST progress-billings/{id}/payments/` `{amount, paid_on, method,
  reference_no}` → `201` payment, and the billing flips to `paid` when full.

Payments and summary:

- `GET client-payments/?project=` — newest paid-on first.
- `GET billing-summary/?project=` — `{billed, collected}` (`billed` = sum of
  `net_due` over **billed** statuses, `collected` = sum of payments).

Variation orders:

- `GET variation-orders/?project=&status=`
- `GET variation-orders/{id}/` — row plus `history` (`entity='variation_order'`).
- `POST variation-orders/` `{project_id, type, description, amount, days_impact}`
- `PATCH variation-orders/{id}/` — a **proposed** VO only.
- `POST variation-orders/{id}/submit/` — owner prices and sends it to the client.
- `POST variation-orders/{id}/owner-reject/` `{reason}`
- `POST variation-orders/{id}/client-approve/` — applies the VO to the project.
- `POST variation-orders/{id}/client-reject/` `{reason}`

Retention:

- `GET retention/?project=` — `{held, released, available}`.
- `GET retention-releases/?project=`
- `POST retention-releases/` `{project_id, amount, released_on, method,
  reference_no}`

Every write answers `400 {"detail": "<text>"}` for a business refusal and
`403 {"detail": "<text>"}` for a wrong active role; an out-of-scope project is
always `404` (never a `403` that leaks its existence).

## Permissions and delegated defaults

- Active role is always `capabilities.active_role(request)`; held roles are
  never unioned. A dual-role user acting as `site_engineer` gets the
  site-engineer answer, not the owner's.
- Scope is always `projects.scoping.projects_for()` / `project_or_404()`;
  only an **accepted** assignment in the active role grants anything.
- Billing reads, preview, create, submit, withdraw: active `owner` **or**
  `accountant` (`capabilities.sees_finance`) with project scope; create/submit/
  withdraw additionally require an accepted owner assignment on the project
  (decision: accountant may read and record money, the owner of the project
  prepares the billing). *(Delegated default — accountant cannot create a
  billing. Owner confirmation open: §Open policy questions 1.)*
- Client approve/dispute: active `client` role **and** an accepted client
  assignment on that project.
- Payment recording and `billing-summary`/`client-payments` reads: active
  `owner` or `accountant` — the client reads payments only through the
  `payments` list of its own billing detail, and `GET client-payments/` is `403`
  for `client`. *(Delegated default: the mock repository has no explicit fence
  on `recordPayment`, and its only payments screen, `ProjectFinancialsPage`,
  is gated to `AppRole.owner, AppRole.accountant`.)*
- Client visibility: only **billed** statuses (`pending_client, disputed,
  approved, paid`) on the client's own accepted projects; `draft` and
  `rejected` are `404` for the client, exactly as `ClientBillingsViewModel`
  filters `status.isBilled`.
- Variation order reads and proposal: active `owner` or `site_engineer` with
  project scope; proposal needs an accepted owner **or** site-engineer
  assignment. Owner-only: submit, owner-reject, pricing the amount. Client:
  own project's VOs **with `approved_by_owner` set** (`ClientVariationOrders
  ViewModel` filter), and approve/reject only while `pending_client`.
  *(Superseded 2026-11-15, see Open policy question 2: the accountant now reads VOs read-only. Original default: the accountant had no variation-order route — the mock
  and `role_navigation.dart` give that screen to owner/site engineer/client
  only. Owner confirmation open: §Open policy questions 2.)*
- Site engineer never sends a VO amount: the server stores `0.00` for a new VO
  they propose (`0` is not an authoritative price) and leaves an existing
  amount untouched when they edit one. Site engineers cannot read billing
  routes at all (`403`).
- Retention summary/release: active `owner` or `accountant` with project scope.
  The client never reads retention endpoints (it sees `less_retention` inside
  its own billing row, which is already money it is being billed).
- Admin (`admin` role) has **no** billing route. Finance money stays with
  owner/accountant, matching `capabilities.FINANCE_ROLES`.

## Billing rules (mirrors `billing_rules.dart` / `billing_calculator.dart`)

Progress (server-side, `billing_math.project_progress`): a project's progress as
of `period_end` is the budget-weighted share of **verified** to-dos, counting a
to-do only when `is_verified` and (`verified_at` is null or its **local
(Asia/Manila) date** is `<= period_end`), with weights from
`projects.serializers.category_weights` (budget share when every category has a
budget, else equal shares). The local date is what the mock compares
(`_dateOnly(verifiedAt.toLocal())`), and Django sets the Postgres session
`TimeZone` to `TIME_ZONE`, so `verified_at::date` is the same date.

Money:

- `gross_earned = round2(progress × contract_amount)`
- `less_previous` = the highest `gross_earned` among the project's billings
  whose status is not `draft` and not `rejected`
- `this_period = gross_earned - less_previous`
- `less_dp_recoupment = round2(this_period × down_payment_pct / 100)`
- `less_retention = round2(this_period × retention_pct / 100)`
- `net_due = this_period - less_dp_recoupment - less_retention`

Rounding is half-up to 2 dp **per line**, as the mock's `_round` does.
Payment tolerances move from the mock's float `0.005` epsilon to exact
`Decimal` comparison on 2-dp values (deviation, not a behaviour change for
legal amounts).

Refusals (mock texts, reused verbatim where they exist):

- billable only when the project is `ongoing` or `completed`;
- `down_payment_pct + retention_pct < 100` (else `net_due <= 0` could never be
  paid while the `approved` billing blocks the project); checked at create and
  again at client approval;
- one in-progress billing per project (not `paid`, not `rejected`);
- `period_end` not in the future, and strictly after the previous billing's
  period end (rejected billings excluded);
- cumulative accomplishment ≤ 100 % and `this_period > 0.005` (new verified
  work required);
- only `draft`/`disputed` billings may be submitted or withdrawn;
- only a `pending_client` billing can be approved/disputed;
- payments only on an `approved` billing, `0 < amount ≤ balance`;
- a billing becomes `paid` when payments reach `net_due`;
- retention is released only when the project is `completed` or `closed`, and
  `0 < amount ≤ held - released`;
- a VO needs a description; an additive/deductive VO needs a positive cost
  impact before it is sent; a deductive VO may not reduce the contract below
  the amount already billed.

State machine (server-enforced, never a generic status write):

```text
draft ──submit──▶ pending_client ──client-approve──▶ approved ──paid-in-full──▶ paid
  │                     │
  │ withdraw            └──client-dispute──▶ disputed ──submit──▶ pending_client
  ▼                                          │
rejected ◀───────────────────withdraw───────┘
```

VO state machine:

```text
proposed ──submit──▶ pending_client ──client-approve──▶ approved (contract applied)
   │  │                     └──client-reject──▶ rejected
   │  └──owner-reject──▶ rejected
   └──edit (PATCH) while proposed only
```

## Concurrency, locks and database constraints

- **Lock order is always project row first, then the billing/VO row it
  changes.** `save_vo`, `create_billing`, `release_retention` and
  `variation-orders/{id}/client-approve/` all follow it, so no two writes can
  take the same pair in opposite orders.
- All writes run in one `transaction.atomic()`; the audit row is written inside
  it, so a refused change leaves no row, no audit and no half-applied money.
- Create billing locks the project row, then re-checks the in-progress rule and
  the numbering; `UniqueConstraint(project, billing_no)` plus a **partial**
  unique constraint on `(project)` for in-progress statuses are the DB backstop.
  A second constraint, partial unique `(project, period_end)` where status is
  not `rejected`, stops two billings for one period.
- `POST progress-billings/{id}/payments/` locks the billing row
  (`select_for_update`), re-reads the payment sum inside the transaction and
  refuses an overpayment; two simultaneous payments can never exceed
  `net_due`. `CHECK (amount > 0)` backs the amount rule.
- `POST variation-orders/{id}/client-approve/` locks the **project** row, then
  the VO row, re-checks `pending_client` on the freshly read VO, re-validates
  the contract after the VO, then writes status, `approved_by_client`,
  `contract_amount` and `target_end_date` in the same transaction. A double
  approval is a `400` and leaves the contract changed once.
- Retention release locks the project row and re-reads held/released before
  validating; `CHECK (amount > 0)` backs the amount rule.
- Integer/bool body values are strictly parsed (`true` is not `1`); non-finite
  JSON numbers (`NaN`, `Infinity`) are refused as `400`, never a `500`.
- No hard delete anywhere: billings are withdrawn (`rejected`), VOs rejected,
  payments and releases are append-only.

## Audit

`users.services.record()` inside the writing transaction, `entity` =
`progress_billing` / `variation_order` / `project`, action names as in the mock
(`billing_created`, `billing_submitted`, `billing_withdrawn`,
`billing_client_approved`, `billing_client_disputed`, `billing_payment_recorded`,
`billing_paid`, `vo_proposed`, `vo_updated`, `vo_submitted`,
`vo_owner_rejected`, `vo_client_approved`, `vo_client_rejected`,
`retention_released`). Details carry only what the mock's audit text carries: a
trimmed `reason` and — for `billing_payment_recorded` / `retention_released` —
`amount`. No bank reference, no payment method, no free-form request body, no
other money. Actor and timestamps are server-owned.

## Required focused tests

Active-role fences (dual-role user never unions), accepted-assignment scoping /
IDOR, client sees only its own billed rows and gets `404` for a draft, client
and site-engineer refusals, accountant project scope; the full billing state
machine including illegal transitions and the one-in-progress rule; overbilling
and no-new-accomplishment refusals; overpayment refusal and at least one true
**concurrent payment race** on the disposable PostgreSQL stack; retention math
(gross/previous/dp/retention/net due exact to the cent), retention summary and
release bounds; VO approval atomicity (contract amount + target end applied
once, refused when it would fall below billed, refused on double approval) and
site-engineer pricing redaction; audit rows carrying no money beyond the mock's
`amount` keys.

Only the disposable `cpms_test_backend` / `cpms_test_db` stack; CPMS backend
suites serialized under `/tmp/qb-cpms-backend-tests.lock`. No dev database
migration, no POS mutation, no commit or push in this slice.

## Open policy questions (owner must confirm)

1. **Who prepares a billing?** Mock: only the project's owner
   (`createBilling`/`submitBilling` require `AppRole.owner`). Default applied:
   accountant may read and record payments but not create/submit/withdraw. If
   the accountant is meant to bill, this is a one-line capability change.
2. **Does the accountant see variation orders?** Resolved 2026-11-15: yes, **read-only**. The project Financials tab (open to owner and accountant) lists VOs and their approved total, and a real-API probe showed the accountant's page erroring without it. Writes stay owner/site-engineer/client; admin still has no VO route.
3. **Down-payment recoupment basis.** The mock recoups `down_payment_pct` of
   every period's gross, forever, so total recouped can exceed any down payment
   actually collected. No cap is implemented; production needs either a DP
   amount ledger or a cap on cumulative recoupment.
4. **Retention release trigger and authority.** Default applied: project
   `completed`/`closed` only, released by owner/accountant. A real defects
   liability/retention period (date-based), client consent, or a release cap per
   period is not modelled.
5. **`dp_pct + retention_pct > 100 %`** could make `net_due` negative. The mock
   allows it and the Project API validates each percentage separately (0–100).
   **Decided in this slice (default):** refused at billing create and at client
   approval, so a `net_due <= 0` billing can never be issued — it could never be
   paid while blocking the project as in-progress. A carried-forward negative
   remains open if finance wants it.
6. **Rounding.** Half-up per line as the mock does; cumulative rounding drift
   across periods is not reconciled against the contract amount.
7. **No reversal path.** Bounced checks/refunds have no route: payments and
   releases are append-only, so a mistake is corrected only by a new offsetting
   row (which does not exist yet) or by hand. Needs an accountant workflow.
8. **Tax.** No VAT/percentage-tax/withholding line exists anywhere in the mock
   or this slice. Real PH billing needs those and is out of scope here.
9. **`period_end` vs verified work.** Progress is "as of" the period end, so a
   to-do verified after the period end is excluded even if it was finished
   before it. Confirm this is the intended billing basis (it is what the mock
   computes).
10. **Payment methods** are the four the Flutter enum has; online transfer
    references are free text with no uniqueness (double-recorded payments are
    prevented only by the balance lock).

## Next slices

Flutter HTTP billing repository + client portal verification (4.3), derived
`ProjectCosts` after procurement valuation and payroll policy land (blocked),
payroll periods/processing (4.1), notifications for billing/VO events (no new
notification scheme in this slice; the `users.services.notify` helper exists and
is unused here).
