# Phase 2 contract rulings

**Status:** Locked as defaults, revisable — owner may overrule any line before Phase 2 builds.
**Choice:** Apply the safest default to each open question raised while drafting [the Phase 2 contract](../contracts/phase-2-projects-and-site.md). (by: delegated — owner said "continue it for me since my hands are tied"; owner's standing rule: follow the frontend unless it is really not good)

## Rulings

| # | Question | Ruling | Why |
|---|---|---|---|
| 1 | Finance keys omitted → `Project.fromJson` crashes for non-finance roles | `Project.fromJson` treats an absent `contract_amount` / `down_payment_pct` / `retention_pct` as 0 (one-line model change, recorded as a frontend addition) | Screens already hide these for non-finance roles; the server still never sends them |
| 2 | Client sees contract amount and percentages? | Yes, on their own project only | Client portal already shows them; it is their contract |
| 3 | Hidden `Category.budget` gives non-finance roles different progress | Server sends a computed `weight` (0–1) on every category for all roles; `budget` stays finance-only | Same progress % everywhere without leaking pesos |
| 4 | Project scope for clients; `client_id` lock; who builds `Client` | Scope = active assignment (matches the mock). `client_id` locks once the client accepts. `Client` model is added to task 2.1 | Assignment drives every other role's scope; one rule |
| 5 | Client document access | Phase 2 shares approved report photos only; `Document` rows remain staff-only, with no `client_visible` flag. Revisit explicit document sharing only if later requested. | Delegated clarification after final review: matches the contract's client → 403 document routes and teammate portal's photos-only UI; not separately owner-approved. Private system; least privilege |
| 6 | Owner self-assignment on create | Server creates the creator's owner assignment in the same atomic create; drop the Flutter self-assign call | Avoids "Already on this project." and half-created projects |
| 7 | Upload limits and types | Documents ≤ 25 MB, photos ≤ 10 MB; PDF/JPEG/PNG/WebP checked by content (magic bytes) + extension; DWG/DXF by extension + size only, always served as download (`Content-Disposition: attachment`), never inline; no HEIC | Desktop app; safe defaults; no executable/inline-render risk |
| 8 | File picker + `DocumentRepository.upload` signature change | Allowed in 2.3; record as a UI addition in the phase notes | Real uploads need bytes; teammate's mock only passed a filename |
| 9 | Pure admin (not also owner) sees finance/contract documents? | No — follows `FINANCE_ROLES`; the Admin/Owner account reaches them through its `owner` role | Keeps the future Owner/Admin split a one-file change |
| 10 | Where daily reports live; `EquipmentLog` name clash | New app `apps/site_reports`; the site-inventory `EquipmentLog` stays until Phase 4 decides | No rename churn on existing tables |
| 11 | "No future report date" clock | Server time in `Asia/Manila` | Desktop clocks are not trusted |

## Risky frontend rules (R1–R13) — defaults

- **Client decline hard-deletes the project → changed to soft decline** (status `declined`, hidden from lists, audit kept). Data-loss protection; this is a "really not good" item — **owner should confirm**.
- Project save/assign/unassign, the contract-amount lock and "site engineer edits only own drafts" are **enforced on the server** (the mock only enforced them in the UI).
- Owner marking a to-do done and then verifying it: **allowed but audited** (demo partner account holds owner + site_engineer). **Owner should confirm** whether to require a different verifier later.

## Correction to earlier decision

[WBS categories, verified to-do progress, and derived project costing](./05-wbs-costing-and-pos-bridge.md) listed to-do keys `done_report_id` and `verification_note`; Flutter uses `daily_report_id` and has no `verification_note`. Flutter wins; decision 05 is corrected in place.
