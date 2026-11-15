# CPMS backend integration: handoff

State on 2026-11-15. Nothing here is pushed. History is linear, so the tip branch contains every earlier branch.

## What to push

Tip branch: `feat/cpms-clients-write` (commit `bfcdd72`). It is built on `frontendend-progress` (origin is one commit behind: the planning docs commit `55db64e`).

```bash
cd qb_project_management_system
git push -u origin feat/cpms-clients-write
```

Open ONE pull request, base `frontendend-progress`, compare `feat/cpms-clients-write`. The intermediate branches (`feat/cpms-integration-phase-1..3`, `feat/cpms-labor-foundation`, `feat/cpms-billing-foundation`, `feat/cpms-payroll-periods`, `feat/cpms-phase5-prep`) are only checkpoints on the same line; do not push them separately. Review by commit, in this order:

| Commit | What |
|---|---|
| `d653984` | Phase 1: email auth, five roles with active-role switching, company and master lists, Dio client |
| `625bd07` | Phase 2: projects, assignments, WBS, daily reports, private documents |
| `f58a9d6`, `7747973` | Phase 3: procurement, durable POS sync outbox, status panel |
| `c2bce8c` | Workers and attendance, HTTP labor adapter |
| `5b68518` | Progress billing, client payments, variation orders, retention |
| `35f0d57` | Payroll periods (statutory deductions unconfigured) |
| `a136c43` | `seed_demo` and deployment hardening |
| `60220f2` | Client create/link API |
| `6375fb5`, `bfcdd72` | Seed maps real POS barcodes; import order |

## Verified (all on disposable stacks)

- Backend 631 tests OK, `check` clean, no migration drift. Flutter analyze clean, 375 tests OK.
- Independent reviews approved for labor, billing, payroll (after fixes). Runtime API QA found no confirmed defects for billing, labor and payroll.
- Live HTTP bridge CPMS to POS passed (catalog, own-store import with token, manager accept, cashier partial release, read-back, cancel/close, retry with stable identity, `CPMS_SCOPE` fence, external PO isolation). Report: `temp/cpms/5.2/report.md` (local only).

## NOT verified

- The Flutter app has not been run against the real API by a person. Mocks are still the default; API mode is `--dart-define=USE_API=true --dart-define=API_BASE_URL=...`.
- No tunnel run with the real stack; no Windows/desktop packaging; `libsecret` on Linux untested.
- Derived project costs and supplier payables are unavailable in API mode.

## Needs an owner decision (nothing invented)

1. Payroll statutory deductions (SSS, PhilHealth, Pag-IBIG): rates, caps, frequency. Payroll shows `deductions_policy = unconfigured` and zero deductions until decided.
2. Invoice valuation and who owns debt/payments between POS and CPMS (blocks payables and derived costs).
3. Negative-net payroll handling; multi-project deductions.
4. Unconfirmed defaults recorded in `planning/backend-integration/decisions/06-phase-2-contract-rulings.md` and the phase 4 contracts.

## Setting up a demo

See `docs/DEPLOYMENT.md`. After `seed_demo`, map materials to the live POS catalogue and run `seed_demo --pos-payer-id <POS customer id>` or own-store orders will be refused.
