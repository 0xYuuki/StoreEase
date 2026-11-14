# StoreEase reliability delivery

Changes are in the working repository on `codex/storeease-reliability`. The source
repository's history and remote settings were left intact. Nothing was committed or
pushed. The existing frontend and its three views remain in place.

## What changed

| Files | Purpose |
| --- | --- |
| `server.js`, `init_db.js`, `src/server.js`, `src/config.js` | Preserve entry points, validate configuration, open/migrate before listening and shut down safely. |
| `src/app.js`, `src/modules/`, `src/middleware/`, `src/utils/` | Separate HTTP mapping and business rules; enforce permissions; validate inputs and return safe, consistent errors. |
| `src/db/` | SQLite connection/migration/backup, authoritative queries, atomic stock and sales, immutable receipts and Manila calendar aggregates. |
| `public/` | Retain POS, inventory and dashboard; fix scanner, loading, payment and retry behavior; show stock and committed receipts; render text safely. |
| `package.json`, `package-lock.json` | Node 24+, maintained Express 4 dependency chain, built-in SQLite, repeatable commands. |
| `.gitignore`, `.env.example` | Exclude live data, dependencies, backups and secrets; document safe defaults. |
| `scripts/`, `tests/`, `README.md`, `docs/` | Backups and migration tools, isolated verification, operation and API reference. |

The most serious root causes were a destructive initializer, trusting browser money,
asynchronous transaction steps sharing one connection, no retry identity, and mixing
mutable products with sales history. Unprotected network APIs and unsafe HTML interpolation
also exposed data and operations. The [audit](CODE_AUDIT.md) gives the reproduction,
expected/actual behavior, impact and fix for each confirmed defect.

## Data preservation

- Original SQLite backup: `database.sqlite.backup-1794153541371.sqlite`, created before
  the working file's v0 → v1 migration. Keep it with your protected backups.
- A read-only comparison confirmed exact equality for original `Products` columns
  (2 rows), `Sales` columns (6 rows), and `SaleItems` columns (9 rows), including all
  IDs, timestamps, prices, quantities and totals.
- The migrated database reports schema version 1, `integrity_check=ok`, and zero
  `foreign_key_check` violations. No original financial total was recalculated.
- Both the live DB and backup remain local. Git's index no longer tracks the DB or
  dependency directory. Old Git commits can still contain store information; review
  them with the owner before any future publication or history cleanup.

## Verification

| Check | Observed result |
| --- | --- |
| `node --test` | 25 passed, 0 failed on Node 24.22.1. Uses temporary DBs; loopback access was needed outside the sandbox. |
| Clean `npm ci` | 68 packages installed in a separate directory from the lockfile. The first offline attempt had a cache miss; the registry-backed retry succeeded. |
| `npm audit --omit=dev` | 0 reported vulnerabilities for the final dependency tree. |
| `node --check public/app.js` | Passed. |
| Lifecycle and CLI smoke checks | Startup, port conflict and DB failure handling, graceful shutdown, repeated migration, backup creation, new development file creation and existing-file refusal passed. |
| Browser, existing records | Cart, Inventory and Sales Chart loaded; manual barcode lookup worked. Read-only against store records. |
| Browser, synthetic data | Leading-zero lookup, quantity button, tender/change, checkout receipt and stock decrement worked. No store sale was made. |
| Read-only SQLite comparison | Every original row matched the pre-migration backup. Integrity and FK checks passed. |
| `git diff --check` | No whitespace errors. |

The npm CLI was absent from the Codex runtime PATH; verification used a temporary CLI
under ignored `.tools/`. On a normal Node/npm installation use the README commands.

## Run and follow-up

With Node 24+ and npm, run `npm ci`, `npm run migrate`, and `npm start`; visit
`http://127.0.0.1:3000`. See [README](../README.md) for `.env` and network setup and
[DATABASE](DATABASE.md) for backup and restore before switching a production path.

Before a store rollout, test actual camera and scanner hardware, move the live database
off active cloud sync, and confirm TLS and proxy configuration if serving other devices.
Possible later improvements include per-person staff accounts, receipt search/reprints,
local asset packaging for offline use, and large-history analytics indexing if measured
performance warrants it. These are separate from completed checkout/data-safety fixes.
