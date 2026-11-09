# Verification and test instructions

## Automated suite

```powershell
npm ci
npm test
```

Uses Node's built-in test runner and assertions. HTTP tests listen on temporary loopback
ports. Every database fixture is created under the OS temporary directory and cleaned
up afterward. No tests open the working store database. Frontend tests execute the
actual browser script in a VM with a minimal DOM/network model, not a full browser engine.

Coverage includes:

- Product create/read/update/deactivation; duplicate/missing/leading-zero barcodes;
  whitespace, malformed monetary input, zero prices, invalid/missing IDs and safe bounds.
- Exact peso-to-centavo conversion and server-side recalculation despite forged totals/prices.
- Canonical retry keys, conflicting reuse, repeated requests and simultaneous checkouts.
- Two independent SQLite connections replaying one checkout without duplicate stock deductions.
- Forced item insert failure, database locking, commit failure and rollback behavior.
- Foreign keys, snapshot integrity after edits/deactivation, nonnegative counted stock
  and recorded adjustments.
- Manila midnight, Sunday week, month/year boundaries and oversized analytics aggregates.
- Authentication, admin/cashier authorization including URL variants, origin denial,
  malformed/oversized JSON, security headers and non-exposure of private files.
- Synthetic legacy migration, exact original financial values, backup contents,
  repeatability, malformed/orphan refusal, and AUTOINCREMENT high water marks.
- Scanner Enter repeat, form/view isolation, encoded barcode paths, unknown lookup
  preserving the cart, safe HTML rendering, double checkout, authoritative receipt,
  network retry state, rejection recovery and unavailable browser storage.

Expected intentional failures can log `Request failed: ERR_SQLITE_ERROR` during the
forced database-failure tests. A legacy mismatch fixture prints its preserved sale ID.
Those logs are assertions of failure handling, not test-run failures.

## Executed results

On November 9, 2026 (Asia/Manila), Node **24.22.1**:

- `node --test`: **25 tests passed, 0 failed** after the final behavioral changes.
- Initial sandbox execution could not connect to its own loopback test ports (EACCES).
  The suite was rerun with local HTTP access enabled; all tests passed.
- `node scripts/migrate.js`: schema up to date; original migration created the listed
  backup and retained the inspected store records.
- npm compatible update/audit: Express remains major version 4; the previous audit's
  body-parser/proxy-addr/qs advisories were addressed without force upgrades.
  Final `npm audit --omit=dev` reported **0 vulnerabilities**. Clean `npm ci`
  installed 68 packages from the lockfile in a separate directory.
- `node --check public/app.js`: syntax passed during implementation.
- Browser smoke checks: app loaded; Inventory listed both retained products and stock
  as untracked; Sales Chart showed retained historical totals; manual barcode `1`
  added the existing product to the cart. No real sale was created by those checks.
- A second browser smoke check used a disposable synthetic database. Barcode `000123`
  displayed intact, delegated quantity buttons worked, checkout displayed the server
  receipt, and selling two units reduced stock from two to zero.
- Startup/shutdown smoke check on a temporary DB confirmed listening, graceful stop,
  port conflict and DB-open failure handling, repeated migration, creation of an online
  backup and refusal to reset an existing development target.

Final command details and data comparisons are also recorded in [delivery notes](DELIVERY.md).

## Manual acceptance (use an isolated database)

Create a new test file; this command intentionally refuses an existing target:

```powershell
$env:NODE_ENV = 'development'
$env:CONFIRM_RESET = 'CREATE_EMPTY_DEV_DATABASE'
$env:DB_PATH = Join-Path $PWD 'manual.dev.sqlite'
npm run reset:dev
npm start
```

Close the test server and remove those shell environment variables before returning
to the store database. Do not delete a test database unless its resolved path has
been verified as the disposable file.

1. Create a product with barcode `000123`, name containing literal `<`/`>` and price
   `12.05`. Confirm inventory displays text, preserves zeros, and rejects duplicates.
2. Look it up manually and with a physical Enter-suffix scanner. Scan repeatedly on
   purpose (each real scan increments quantity). Hold Enter and type in edit/payment
   forms; these must not create extra unrelated scans. Unknown barcode keeps the cart.
3. With an actual camera, grant permission yourself, scan once, verify cooldown, stop
   the camera, switch views during startup and confirm it stops outside Cart.
4. Set stock to two via ± with a reason. Sell one, retry the exact checkout, and confirm
   stock only dropped once. Attempt quantity above remaining stock and confirm no sale.
5. Double-click Complete Checkout. Verify one receipt; close it with either control;
   the old cart must remain empty.
6. Change a product price in another tab while its cart is open. Insufficient payment
   must reject and refresh price. Adjust payment and confirm the new server receipt.
7. Disconnect during checkout, retain the tab, reconnect and retry. Confirm one sale
   and the original receipt. Refresh while pending; the stored cart/key must recover.
8. Edit/deactivate the sold product. Replaying the saved checkout key must still show
   original receipt text/prices. The barcode must remain reserved after deactivation.
9. Test independent admin/cashier tokens. Cashier must not see management controls or
   analytics, and direct management requests must return 403.
10. At narrow screen widths, check table scrolling, payment entry, navigation and dialogs.
    Simulate unavailable CDN assets; manual/keyboard lookup should still work and the
    camera/chart should report their unavailable libraries.

Physical camera/scanner, production HTTPS proxy, real power-loss recovery and sustained
load testing remain deployment acceptance work; they are not reported as completed tests.
