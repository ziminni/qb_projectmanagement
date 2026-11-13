# Frontend plus verified review

**Status:** Locked planning baseline.
**Choice:** Frontend + review. (by: me — user selected this option)

Use teammate's Flutter desktop workflows on `frontendend-progress` at `39da4ff` as starting scope. Preserve useful UI; adapt backend models and contracts where justified rather than force UI onto the legacy backend.

This does not approve every mock business rule. Resolve conflicting permissions, project states, progress calculations and accounting explicitly. Initial CPMS schema and manuscript audits remain requirements evidence; verify source before marking a feature implemented.

## Verified discrepancies to resolve

- Frontend multi-role Admin/Owner/Site Engineer/Accountant/Client versus backend single-role Admin/Project Manager/Site Supervisor/Engineer.
- Category/Todo verification versus Phase/Milestone progress; quantity-based BOQ missing.
- Daily reports, documents/media, labor/payroll, variation orders and retention lack matching complete backend workflows.
- Procurement own-store/external branches cannot both be mapped blindly to POS requisition CRUD.
- Delivery/payroll/equipment-derived costs versus backend approved-expense sums require one authoritative posting policy.
- Frontend progress billing is richer than backend collectibles/payment ledger.

## First prerequisite

Settle role, project assignment and finance visibility rules; close existing self-service role escalation before exposing backend. Replace mock repositories incrementally after contracts are settled.

## Verification boundary

Code inspection only. No runtime, migration, desktop packaging or two-backend E2E success asserted. Implementation checklist and ownership tags will be finalized once the map's open decisions are resolved.
