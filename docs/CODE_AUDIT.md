# StoreEase code audit and implementation record

Audited the actual fetched repository on branch `codex/storeease-reliability`,
not just the supplied leads. The workspace initially contained only an empty `.git`;
source was fetched directly from `https://github.com/0xYuuki/StoreEase` without
configuring or changing a remote. No commits, pushes, or history rewrites were made.
Implementation and verification completed across November 8–9, 2026 (Asia/Manila).

## Scope and prioritized implementation plan

Inspected the original `server.js`, `init_db.js`, `package.json`, lockfile, all three
frontend files (`public/index.html`, `app.js`, `style.css`), tracked-file inventory,
SQLite schema, integrity, foreign keys, record counts, and header/item totals.
Dependency internals were assessed via the lockfile and npm advisories rather than
claiming a line-by-line review of every third-party library.

| Priority | Work | Outcome |
| --- | --- | --- |
| P0 | Eliminate reset/data-loss paths; inspect and back up database | Non-destructive migration, explicit new-file-only development reset, verified backup. |
| P0 | Correct authoritative money and transaction/idempotency behavior | Trusted prices, safe centavos, atomic writes, replay keys and concurrency tests. |
| P1 | Preserve historical data and enforce SQLite integrity | Product deactivation, receipt snapshots, constraints/PRAGMAs/indexes, original-column comparison. |
| P1 | Protect network deployments and unsafe frontend rendering | Role credentials, exact origins, safe errors/headers, escaped text and no inline script handlers. |
| P1 | Repair scanner, receipt, retry and date behavior | Guarded events, confirmed receipts, recoverable retry state, fixed Manila/Sunday calendars. |
| P2 | Add minimal compatible stock support and modular structure | Optional counts with adjustment reasons; routes/controllers/services/repositories separated. |
| P2 | Verify and document operation | Temporary-database tests, browser smoke checks, setup/API/database/testing docs. |

## Confirmed defects and fixes

### 1. Critical — destructive initialization

- **Affected:** original `init_db.js`, `initialize()`; `npm run init-db`.
- **Reproduction:** only on a disposable copy, initialize a populated database, then
  invoke the old init command. It unconditionally drops SaleItems, Sales and Products.
- **Expected / actual:** initialization should preserve data; it deleted the entire store history.
- **Root cause / impact:** schema setup and development reset were the same procedure.
- **Fix:** safe migration entry point, pre-migration SQLite backup, atomic schema/data
  verification, and a separate command that refuses existing development targets.
  The destructive original script was never executed in this work.

### 2. Critical — client controls financial records

- **Affected:** original `server.js`, POST `/api/sales`.
- **Reproduction:** submit a valid product ID with `price: 0` and a forged/negative
  `total_amount`; the old handler saved those client values.
- **Expected / actual:** database prices should determine money; arbitrary browser
  values became accounting records.
- **Root cause / impact:** no trusted lookup, quantity validation, safe range check or server total.
- **Fix:** validate and canonicalize cart; fetch active product prices; compute line/header
  totals in safe integer centavos; ignore submitted prices/totals; optionally validate payment.

### 3. High — incomplete transaction lifecycle and concurrency races

- **Affected:** original checkout `db.serialize`, nested callbacks and `db.run('COMMIT')`.
- **Reproduction:** issue simultaneous checkout requests, introduce an item insert error,
  or force COMMIT failure in a disposable environment. Success was sent without waiting
  for COMMIT, and asynchronously scheduled steps could interleave on the shared connection.
- **Expected / actual:** one atomic sale after confirmed commit; partial/racy or falsely
  acknowledged completion was possible.
- **Root cause / impact:** serialization of initial scheduling was mistaken for an async mutex.
- **Fix:** synchronous transaction body under `BEGIN IMMEDIATE`; checked commit/rollback,
  connection closure on rollback failure, busy timeout and retryable 503. Tests cover
  concurrent HTTP requests, independent SQLite connections, forced insert and commit failures.

### 4. High — duplicate checkout and receipt replay

- **Affected:** original `public/app.js`, `handleCheckout`, receipt controls; sales endpoint.
- **Reproduction:** double-click checkout, retry a lost response, or close the receipt with
  its cancel control and check out the retained cart again.
- **Expected / actual:** one sale per intended transaction; independent duplicate sales were created.
- **Root cause / impact:** no busy guard, no idempotency identity, sold cart retained.
- **Fix:** persisted UUID before submission, unique server key plus canonical hash,
  guarded cart/submission, committed receipt snapshots and sold-cart clearing. Definite
  rejection unlocks edits; uncertain failures retain the same retry key.

### 5. High — permissive price/quantity and weak input validation

- **Affected:** original product handlers and checkout payload validation.
- **Reproduction:** create/update with `price: '1junk'`, whitespace-only text, negative or
  fractional quantities, malformed IDs, or values beyond safe integer range.
- **Expected / actual:** strict valid input or 4xx; parseFloat accepted trailing garbage,
  prices were rounded ambiguously, and checkout used unvalidated values.
- **Root cause / impact:** permissive coercion and truthiness checks instead of contracts.
- **Fix:** strict decimal grammar, exact BigInt boundary conversion, safe integer arithmetic,
  trimmed bounded string validation, positive quantities/IDs and appropriate 400/404/409 errors.

### 6. High — sale history depends on mutable/deleted products

- **Affected:** original SaleItems schema, DELETE product, analytics popular-items join.
- **Reproduction:** sell an item, then rename or delete it. Popular history changed its
  name or became unknown. Enabling FKs exposed `NOT NULL` vs `ON DELETE SET NULL` conflict.
- **Expected / actual:** receipts remain stable; names/references were unstable or deletion failed.
- **Root cause / impact:** no name/barcode snapshots and incompatible FK design.
- **Fix:** soft deactivation, nullable/restricted product references, immutable sale-time
  snapshots and provenance for reconstructed legacy names. Historical prices/totals retained.

### 7. High — APIs exposed without deployment controls

- **Affected:** original `app.listen(PORT)`, wildcard `cors()`, all management/sales routes.
- **Reproduction:** access a network-bound old instance from another computer or origin;
  no credential/role check prevented product edits, deletion, checkout or analytics access.
- **Expected / actual:** trusted local operation or authenticated network access; all callers allowed.
- **Root cause / impact:** no deployment/auth/origin model.
- **Fix:** localhost default, validated network config requiring admin token and HTTPS origin,
  optional cashier token, route-level admin checks including case/trailing-slash variants,
  no wildcard CORS, origin/Fetch Metadata and local Host checks. No default credentials.

### 8. High — stored XSS through product text

- **Affected:** original cart, inventory, receipt and popular-item template strings in `public/app.js`.
- **Reproduction:** save a product name containing an HTML tag with an event handler, then
  view the corresponding table or receipt.
- **Expected / actual:** display literal text; untrusted text entered innerHTML unescaped.
- **Root cause / impact:** mixed trusted markup and raw product content, enabling script execution.
- **Fix:** encode dynamic string values, delegate button events instead of inline scripts,
  CSP without inline JavaScript and security headers. Regression tests assert escaped output.

### 9. High — database integrity not enabled/configured

- **Affected:** original database connection and schema.
- **Reproduction:** open through the original server and inspect `PRAGMA foreign_keys`,
  or insert an invalid relationship through an unchecked connection.
- **Expected / actual:** enforced relationships and bounded quantities/prices; enforcement
  was off and monetary/quantity CHECK constraints were absent.
- **Root cause / impact:** default SQLite connection settings and minimal schema.
- **Fix:** foreign keys on each application connection, busy timeout, WAL/FULL durability,
  constrained schema and relationship/timestamp indexes, migration and startup integrity checks.

### 10. High — dependency advisories and tracked runtime data

- **Affected:** original package lock, tracked `node_modules/` and `database.sqlite`.
- **Reproduction:** inspect `git ls-files`; 1,815 dependency files and a populated database
  were tracked. npm audit during the compatible upgrade identified body-parser, proxy-addr
  and qs advisories.
- **Expected / actual:** reproducible installs without store data; dependencies/live sales
  were committed and vulnerable transitive versions remained locked.
- **Root cause / impact:** missing ignore rules and outdated resolved packages. Old commits
  may disclose store information; no claim is made that its sensitivity has been fully classified.
- **Fix:** `.gitignore`, `git rm --cached` without history rewriting, Express 4.22.3 and
  compatible transitive updates, removal of unused cors/native sqlite3 dependency chains.
  Final npm advisory results are recorded in TESTING.md. **Owner review of old committed
  data remains required; history cleanup was not authorized or performed.**

### 11. Medium — host-local and UTC calendar mismatches

- **Affected:** original analytics SQL (`localtime`, weekday calculation) and JS `toISOString` labels.
- **Reproduction:** run in a non-Manila host timezone, inspect sales across Manila midnight,
  or query Sunday. Original SQL used host-local dates, labels used UTC, and week logic
  disagreed with the UI's Sunday-start label.
- **Expected / actual:** one Philippine calendar; KPIs/chart dates/week boundaries disagreed.
- **Root cause / impact:** multiple timezones and inconsistent week definitions.
- **Fix:** explicit Manila boundaries and matching ISO chart dates; UTC timestamp storage,
  Sunday-start week, calendar month/year and boundary tests independent of host timezone.

### 12. Medium — scanner interferes with forms and mishandles events/resources

- **Affected:** original global keyboard handler, camera callback lifecycle and `playBeep()`.
- **Reproduction:** type quickly in product/payment inputs, repeat Enter, switch views during
  scanning or repeatedly create AudioContexts. The global buffer could consume unrelated
  typing; camera stop/restart promises competed and beep contexts were not closed.
- **Expected / actual:** scanning limited to selling context, independent form typing and
  released resources; duplicate/unrelated scans and resource leaks were possible.
- **Root cause / impact:** global interception without view/focus guards and unmanaged lifecycle.
- **Fix:** view/modal/editable/repeat/composition guards, buffer expiration, encoded barcode
  URLs, camera transition guard/cooldown, closed audio contexts and missing-library feedback.

### 13. Medium — stale and ambiguous frontend states

- **Affected:** original checkout receipt rendering, form submissions, inventory/dashboard loading.
- **Reproduction:** edit a product price while a cart is open, disconnect during checkout,
  or fail a dashboard reload. Browser estimates were used for receipts, failed requests
  lacked recoverable checkout identity, and old values remained visually current.
- **Expected / actual:** authoritative receipt, safe retry and clear state; misleading values
  and accidental repeats were possible.
- **Root cause / impact:** no transactional client state and incomplete loading/failure handling.
- **Fix:** committed server receipt, persisted pending cart, guarded submissions, refresh after
  definite rejection, loading/unavailable messages, offline notice and responsive layout fixes.

### 14. Medium — startup/error/configuration responsibilities mixed

- **Affected:** original monolithic `server.js`, connection callback and startup sequence.
- **Reproduction:** make DB open fail; the original server could still listen after logging
  the error. Importing the module also started the network listener.
- **Expected / actual:** fail before serving or allow isolated tests; startup and queries were coupled.
- **Root cause / impact:** routes, SQL, rules, initialization and startup shared one module.
- **Fix:** validated config, database open before listen, startup failure handling, graceful
  shutdown, isolated app factory and routes/controller/service/repository modules.

## Confirmed absence and conservative extension

The original inventory screen managed a product catalog only; there was no quantity
column, restocking logic or stock deduction. Optional stock was added with null meaning
untracked. Existing products remain sellable, counted products cannot oversell, and
sale deductions/adjustment reasons commit with the sale. This is deliberately smaller
than supplier, purchasing or warehouse modules.

## Possible risks and remaining operational work

These are limitations or risks, not claims of defects observed in the inspected data:

- Shared role tokens do not identify individual staff and require manual rotation.
  Add accounts/session expiry only when per-person audit/revocation is needed.
- Physical barcode scanner and camera decoding depend on actual hardware/permissions.
  Automated event tests and browser lookup do not replace a real-device acceptance test.
- Version-pinned CDN scripts remain third-party dependencies and need network access.
  Bundle and review those assets for fully offline installations.
- Synchronous SQLite and calendar aggregate scans suit a small store, not a large
  high-throughput service. Large-history performance and power-loss recovery were not
  benchmarked. Busy waits can block the Node event loop for up to the configured timeout.
- The current workspace is under OneDrive. Move the active DB to a local, unsynchronized
  folder before production use; no data relocation was performed without the owner.
- A lost/cleared browser tab can lose its client retry key. Pending checkout state must
  be reconciled with saved sales before starting a replacement transaction.
- Legacy product names/barcodes are reconstructed as of migration, with explicit
  provenance. Historical original names cannot be recovered where never recorded.
- HTTP-only LAN exposure is refused by configuration unless an HTTPS origin is provided;
  actual TLS termination/firewall enforcement remains the deployer's responsibility.

No unrelated redesign, real-store seed data, hardcoded password, remote setting change,
public deployment, push, or destructive reset was performed.
