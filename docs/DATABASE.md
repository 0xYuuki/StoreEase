# SQLite and data safety

## Schema version 2

Version 2 adds optional product reorder levels and receipt references on new sale
stock movements. Upgrading a version 1 database creates a backup before the
migration. Existing movements retain their reasons and balances. Their receipt
references are empty because version 1 recorded only free-text reasons.

`PRAGMA user_version` tracks the migration. New databases are empty. Existing databases
are never reseeded on startup.

| Table | Data and constraints |
| --- | --- |
| `Products` | Original ID, unique string barcode, name, nonnegative safe integer centavo price; `active` 0/1; nullable `stock` (untracked) or nonnegative safe integer. |
| `Sales` | Original ID, UTC timestamp, original nonnegative safe integer total; unique nullable idempotency key and request hash. Legacy sales have null keys. |
| `SaleItems` | Sale FK, nullable product FK, positive integer quantity, historical centavo price, name/barcode snapshots, safe integer `line_total=price*quantity`, snapshot provenance. Foreign keys restrict deletion. |
| `StockAdjustments` | Product FK, signed delta, nonnegative resulting stock, required reason and UTC timestamp. Sales record their own adjustment reason. |

Products are deactivated by the API, not physically removed. Their barcodes remain
reserved so an old barcode cannot silently identify a different product. Sale snapshots
survive later edits. For migrated items, names/barcodes can only be recovered from the
product as it exists at migration time; `snapshot_source='legacy-current-product'`
records that limitation. Original sale-time names cannot be reconstructed from missing data.
Original item prices and header totals are retained exactly, never derived from current prices.

Every application connection enables foreign keys, a 5-second busy timeout, WAL and
FULL synchronous durability. Barcode uniqueness creates its own lookup index. Additional
indexes cover sale timestamps and both sale-item relationships. Calendar expressions
may require scanning timestamp rows; benchmark before adding expression indexes for
large histories. The current design favors correctness and small-store simplicity.

## Migration procedure

1. Stop old servers/writers and make a backup. Use a local filesystem rather than an
   active cloud-sync/network folder for a running SQLite database.
2. Set `DB_PATH` outside `public/`, then run `npm run migrate`.
3. A legacy database is backed up through SQLite's backup API before migration. The
   backup is beside the source: `<DB_PATH>.backup-<timestamp>-<uuid>.sqlite`.
4. In one transaction, migration checks integrity, foreign keys, valid prices,
   quantities/text/timestamps and monetary limits. It reports header/item mismatches
   without modifying those amounts. Invalid/orphaned records abort migration for
   owner-approved repair of a copy; no rows are silently skipped.
5. New constrained tables are populated, original columns are compared row-for-row,
   foreign keys are checked, and AUTOINCREMENT high water marks are preserved. Only
   after these checks are temporary legacy tables removed within the transaction.
6. The version changes with the same commit. Subsequent runs verify integrity and
   do not rerun the migration or create redundant migration backups. Newer unsupported
   schema versions are refused.

The inspected database had 2 products, 6 sales, 9 sale items, `integrity_check=ok`,
no foreign-key violations, and all six header totals matched item totals. Its original
backup is **`database.sqlite.backup-1794153541371.sqlite`**. Tests use only synthetic
temporary databases. Keep the working backup private; it was untracked along with the
live database. Stopping Git tracking does not remove data from old Git commits.

## Backups

```powershell
npm run backup
```

This uses a read-only source connection and SQLite's online backup API, checks source
integrity, and creates a unique snapshot beside the database. It includes committed
WAL data. Do not copy only a live `.sqlite` file while ignoring its `-wal` file. Move
verified backups to a protected separate location and establish your own retention
schedule. Automatic backups occur only before legacy migration; they are not a
replacement for routine store backups.

## Restore without overwriting the current store

1. Stop all StoreEase processes and keep the current database plus its sidecars as evidence.
2. Copy the chosen backup to a **new** filename outside `public/`, for example
   `C:\StoreEaseData\restored.sqlite`; refuse/choose another path if it already exists.
3. Set `DB_PATH` to that new file and run `npm run migrate` to check/upgrade it. A legacy
   backup receives a fresh migration backup before changes.
4. Compare product/sale/item counts, totals, integrity and receipts against expectations.
5. Start StoreEase using the new path only after verification. Preserve the previous
   files until the owner has approved the restored result.

Do not run development resets or SQL repair statements against the only copy of store data.
The application does not offer destructive downgrade or automatic financial repair.

## Development database creation

`npm run reset:dev` requires `NODE_ENV=development`,
`CONFIRM_RESET=CREATE_EMPTY_DEV_DATABASE`, and a nonexistent `DB_PATH` ending
`.dev.sqlite`. It atomically reserves a new file and runs migrations. It never deletes
or truncates an existing target. This intentional safeguard replaces the old reset.
