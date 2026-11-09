# Architecture

StoreEase remains one Node process and one SQLite file. No frontend framework or
microservice was introduced. Node 24's built-in `node:sqlite` replaces `sqlite3`,
eliminating native-addon installation/ABI issues. Express stays on major version 4.

## Files and responsibilities

| Location | Responsibility |
| --- | --- |
| `server.js` | Compatibility startup entry point; reports fatal startup failure. |
| `src/server.js` | Opens the database before listening, handles listen failures and shutdown signals. |
| `src/config.js` | Validates host, port, tokens, public origin and database location. |
| `src/app.js` | Composes security headers, API middleware, routes, static files, and error handling. Does not listen on import. |
| `src/modules/routes.js` | Maps URLs and applies admin authorization to management/analytics handlers. |
| `src/modules/controller.js` | Converts HTTP inputs to service calls, sends JSON results, forwards exceptions. |
| `src/modules/service.js` | Product rules, stock adjustments, authoritative checkout, idempotency and transaction boundaries. |
| `src/modules/analytics.js` | Converts Manila calendar boundaries to UTC and constructs dashboard responses. |
| `src/db/repository.js` | Parameterized product, sale, receipt and stock SQL. |
| `src/db/analytics.repository.js` | Aggregate SQL and lossless integer read/conversion checks. |
| `src/db/connection.js` | Connection PRAGMAs, migration backup, integrity checks and transaction helper. |
| `src/db/migrations/` | Versioned schema changes and preservation checks. |
| `src/middleware/` | Authentication/origin checks, per-route admin authorization, consistent safe errors. |
| `src/utils/validation.js` | Strict IDs, text, safe integers and exact peso-to-centavo conversion. |
| `public/` | Existing POS, inventory, dashboard and scanner views. Only this folder is served. |
| `scripts/` | Migration, online backup, safeguarded development database creation. |
| `tests/` | Isolated HTTP/database tests and frontend event/state tests. |

The small domain uses a shared service and repository instead of duplicating nearly
identical controller/service scaffolding for every entity. Split those files by
domain when they materially grow. There are no placeholder modules.

## Checkout flow

1. Browser stores a UUID, cart snapshot, and tendered amount in session storage before
   submitting. While a checkout is pending, cart changes are blocked.
2. Middleware validates origin and authentication. Controller passes the payload and
   `Idempotency-Key` to the service.
3. Service validates IDs and quantities, merges repeated product lines, sorts the
   cart, and hashes its authoritative identity (product IDs and quantities).
4. `BEGIN IMMEDIATE` obtains the SQLite write lock. An existing key returns the exact
   stored receipt or a conflict if used for a different cart.
5. Database prices determine line and header totals. All arithmetic is safe integer
   centavos. Optional tendered amount and tracked stock are checked before writing.
6. Header, item snapshots, stock decrements and adjustment records are written together.
   Success is returned only after synchronous `COMMIT` completes. Any failure attempts
   rollback; a rollback failure closes the unsafe connection.
7. Browser displays the stored receipt and clears the sold cart. Network/5xx uncertainty
   retains the key for a safe retry. Definite validation/stock/payment rejection unlocks
   the cart and refreshes product prices.

Synchronous SQLite operations cannot interleave callbacks within a transaction.
Separate processes/connections serialize through SQLite's write lock, a 5-second busy
timeout and the unique idempotency-key constraint. Long database work can block the
event loop; this is a deliberate small-store tradeoff. Scale testing, a worker queue,
or another database would be appropriate for a high-throughput deployment.

## Security model

The default is a trusted localhost operator. Network binding requires a random admin
token and HTTPS public origin. Optional cashier tokens have narrower route permissions.
Credentials travel in Authorization headers, remain only in browser memory, and are
never placed in URLs or browser persistent storage. There are no cookie sessions to
expire or CSRF cookie credentials to replay. Exact origin and Fetch Metadata checks
also reject cross-site browser requests, and localhost mode validates Host to reduce
DNS-rebinding exposure. No CORS access is granted to other browser origins.

Scripts use external files and delegated DOM events. The CSP does not allow inline
scripts; dynamic text is HTML-escaped in templates. Inline styles remain permitted
to preserve the existing UI. Version-pinned chart/scanner CDN scripts remain trusted
third parties. HTTPS termination, firewalling, token distribution/revocation and
filesystem permissions remain deployment responsibilities.

## Time and API boundaries

Sales use SQLite UTC timestamps. Naive legacy timestamps are interpreted as UTC,
matching the original `CURRENT_TIMESTAMP` default. All store periods use Asia/Manila
(UTC+08:00, no daylight saving), with Sunday as the first day of the week to match the
existing UI. ISO chart dates use those same local dates, independently of host timezone.

Product create/update accepts decimal pesos; product reads and sale/analytics values
are integer centavos. A future Flutter client can use the same JSON API and bearer
authentication; it must persist retry keys before submission just like the browser.
