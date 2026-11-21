# Own-store order: full store catalogue, locked store price, line-by-line matching, prompt delivery to POS

Date: 2026-11-20 · Systems: CPMS (`project_managemet/`) and POS (`hardware_store/`)

## Why

Ramon (CPMS project manager, Owner role) turns a site engineer's material request into an
order from the company's own hardware store. Today that screen gets in his way:

1. **Most store products are missing.** The store sells 15 products; Ramon sees 2. The
   catalogue (`pos-catalog/`) drops every store product that no CPMS material is linked to
   by `pos_code`, and only 2 of 12 CPMS materials are linked.
2. **The price can be typed over.** The store's price is the real price (owner decision
   2026-11-15, `docs/HANDOFF.md`), but the unit-price field is editable and the server
   saves whatever price the app sends.
3. **Matching is guesswork.** "Tick what this order covers" and "add from catalogue" are
   two unconnected lists; nothing says which product answers which requested line.
4. **The POS manager has to log out and back in to see the request.** CPMS hands the order
   to a background worker that sends it up to 30 s later, and the POS "Requests from
   projects" page and its sidebar count are read once when the screen opens and never again.

Success: Ramon matches each requested line to a store product in one place, at the store's
price, and the store manager sees the request appear on screen within seconds, no re-login.

## Goals / non-goals / anti-goals

- Goals: every store product orderable; store price shown read-only and enforced by the
  server; one row per requested item with its matched product; request visible in POS
  within ~15 s without any manual step.
- Non-goals: changing outside-store purchases (their price stays typed); categories in the
  store catalogue; push notifications or websockets; changing the POS accept/release flow.
- Anti-goals: an order saved at a price the store did not give; a CPMS write into the POS
  database (AGENTS invariant 4); a second, duplicate request in POS from sending it faster.

## Approaches considered (owner handed the choice to Claude; A chosen)

- **A. Match line by line (chosen).** Each requested item is a row with "Choose store
  product"; a search opens pre-filled with the item's words, best matches first; picking
  one adds the product with the requested quantity and store price and ticks the item
  covered. Clear one-to-one picture, works with free-typed request names.
- B. Keep two lists, add a "For: [requested item]" dropdown per order line. Smallest
  change but keeps the back-and-forth between lists.
- C. Auto-match everything by name, owner confirms. Fast when names agree, but site
  engineers type freely ("semento", "bar 16"), so wrong guesses slip through. Its ranking
  idea is kept inside A's search.

## Design

### 1. Every store product is orderable (CPMS backend)

`pos_catalog_view` links unlinked store products when it reads the catalogue (owner-only
endpoint, already the only caller):

- store code already on a CPMS material → use it (today's behaviour);
- else an unlinked CPMS material with the same name (case-insensitive, trimmed) → set its
  `pos_code` to the store code and use it;
- else create a `MaterialItem` (`name` = store product name, `unit` = store unit,
  `pos_code` and `store_sku` = store code, `default_unit_cost` = store price or 0);
  if the name is taken by a material linked to another code, name it
  `"<product> (<code>)"` so the case-insensitive unique name constraint holds.

Every row then carries a `material_id`. Done in one transaction; a race on the unique name
is retried once by re-reading. CPMS only writes its own database.

### 2. Store price is read-only and enforced (CPMS backend + Flutter)

- Flutter: on own-store lines the unit price is shown as text with a lock icon
  ("Store price"), not a field. Quantity stays editable. Outside-store forms unchanged.
- Server (`procurement_services`, own-store branch): ignore any `unit_price` the app sends;
  read the store catalogue once through `PosClient` and use the store's price for each line
  by `pos_code`. If the store is unreachable → refuse with "The store could not be reached,
  so its price could not be confirmed. Try again." If a product has no store price → refuse
  naming the product. The response returns the saved prices so the screen shows what was
  stored.

### 3. Line-by-line matching (CPMS Flutter, own-store order form)

Replaces the separate "Requested by the site engineer" checklist, "Store catalog" and
"Your order" cards on `own_store_order_form.dart` with one "Match requested items" card:

```
Portland cement, 20 bags
  → Holcim Cement 40kg · ₱265.00/bag 🔒 · in stock
    Qty [20] bag                          ₱5,300.00   [Change] ✕
16mm rebar, 50 pcs
  Not matched yet                         [Choose store product]
                                          Order total ₱5,300.00
```

- "Choose store product" opens a dialog: search field pre-filled with the requested
  item's description; results ranked by word overlap with that description (then name);
  each row shows name, code, unit, store price and stock status; an empty query lists all.
- Picking sets the line: product, quantity = requested quantity (editable), unit = store
  unit, store price (locked). The requested item is marked as covered by this order. One
  product per requested item; "Change" reopens the dialog, ✕ clears the match.
- Items already covered by an earlier order show as today ("Covered by PO-…"), no button.
- Unmatched items stay open and can go to an outside purchase later (existing flow); the
  confirm dialog already says when not everything is covered.
- If a unit differs from the request (request "bags", store "PC"), the row shows a small
  "Store sells per PC" note; no conversion.
- Category field, budget card, delivery address and Send button are unchanged.
- If the catalogue cannot be read the card says so with Retry, and Send is disabled (no
  price can be confirmed). The master-list fallback is no longer used for ordering.

### 4. Request shows up in POS without re-login

- CPMS: after an own-store order is saved, send it to the store right away (run that one
  outbox job inline after the transaction commits). If the send fails, the outbox job stays
  queued and the worker retries as today; the order is saved either way. The worker's pass
  interval drops from 30 s to 10 s as a backstop. The existing stable request identity
  keeps a retry from creating a duplicate in POS.
- POS Flutter: the "Requests from projects" page reloads its list every 15 s while open
  (skipped while a reload or a decision is in flight, stopped on dispose); the sidebar
  "waiting" badge re-reads on the same 15 s cadence while the shell is mounted. Errors in a
  background reload keep the rows on screen, as manual Refresh does today.

## Testing

- CPMS backend: catalogue links by code / by name / creates / name-collision; own-store
  order uses store price when the app sends another price; refuses when store unreachable
  or price missing; inline send called after commit and failure leaves job queued.
- CPMS Flutter: matching card (pre-filled search, pick fills qty/unit/price, change, clear,
  covered items), price not editable on own-store, Send disabled when catalogue fails.
- POS Flutter: page and badge re-read on the timer; timer stops on dispose; no overlapping
  reads.
- Live check through the tunnel: Ramon orders 2 products; POS manager already on the
  requests page sees it without touching anything.

## Calls made by Claude (please check)

- Linking happens when the catalogue is read, and an existing same-named CPMS material is
  linked rather than duplicated.
- One store product per requested item.
- 15 s POS refresh, 10 s CPMS worker backstop.
- Ordering is blocked when the store's price can't be confirmed (no fallback price).

## Left to the builder

Widget structure and names, ranking details, exact copy beyond the strings above, test
file layout.
