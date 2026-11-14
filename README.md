# Helen's Store

A small-store POS with barcode lookup, product management, optional stock counts,
atomic sales, and Philippine calendar sales analytics. The existing vanilla HTML,
CSS, and JavaScript interface is retained; the backend is a small Express modular
monolith backed by SQLite.

## Requirements and installation

- Node.js **24 or newer**, with npm. Use a maintained Node 24 release.
- A current browser. Camera scanning requires localhost or HTTPS and camera permission.
- A writable database folder outside `public/`. Use a local disk, rather than an actively
  synchronized OneDrive/network folder, for a running store database.

```powershell
npm ci
Copy-Item .env.example .env
npm run migrate
npm start
```

Open [Helen's Store](http://127.0.0.1:3000). `npm run dev` restarts the server after source
changes. Environment files are loaded by the npm scripts; direct `node server.js`
uses already exported environment variables. A fresh installation creates an empty
database. It does not seed an account, products, or sales.

The default uses `database.sqlite` in the project folder for compatibility with
existing installations. Set `DB_PATH` to an absolute local-disk path for a store.
Stop every old StoreEase process before upgrading or moving the database. Startup
performs safe, versioned migrations; `npm run init-db` is now an alias for migration.
It never runs the former destructive initializer.

## Existing data

Migration backs up an existing legacy database before any schema change, rejects
malformed or orphaned records, and verifies exact preservation of the original
columns. It retains historical header totals and item prices, even when they disagree.
Those disagreements are reported for owner review, never silently recalculated.

The supplied working database was migrated with **2 products, 6 sales, and 9 items**
retained. Its original backup is
`database.sqlite.backup-1794153541371.sqlite`. Do not commit this backup or live data.
See [database operations](docs/DATABASE.md) before restoring or repairing data.

## Access and deployment

Default binding is **127.0.0.1**, with local operator access and no password. This is
for a trusted, single-user computer. To require login locally, set `ADMIN_TOKEN`.
There are no built-in credentials.

For network use, configure a TLS reverse proxy, an exact HTTPS `PUBLIC_ORIGIN`, and
an independent random `ADMIN_TOKEN`. Then explicitly configure `HOST` for the proxy
or LAN interface. The server refuses non-loopback binding without these settings.
Do not expose the Node HTTP port directly to the Internet; restrict it to the proxy
or trusted network. HTTPS is also needed for remote browser UUID generation and cameras.

Generate each token yourself; this prints a new secret to your own terminal:

```powershell
node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

Use separate generated values for `ADMIN_TOKEN` and optional `CASHIER_TOKEN` in `.env`.
The browser prompts for the token and keeps it only in memory. Refreshing or clicking
Sign out forgets it. Tokens are shared role credentials for a small store, not
individual user accounts; revoke/rotate them by changing the environment and restarting.
Admin can manage products, adjust stock, sell, and see analytics. Cashier can look up
products and sell. The API enforces permissions independently of hidden UI controls.
No cookie sessions or wildcard CORS are used.

## Store workflows

- Scan with a keyboard-wedge scanner followed by Enter, enter a barcode manually,
  or start the camera. Barcodes remain strings, including leading zeros.
- Inventory allows product creation/editing and deactivation. Deactivation hides the
  product from selling while preserving receipts; its barcode remains reserved.
- Existing and new products initially show **Stock: Untracked**. Sales do not invent
  stock counts. The inventory **±** button enables tracking with the first counted
  quantity, then records signed adjustments with a reason. Negative stock is refused.
- Checkout uses database prices and integer centavos. A price increase above payment
  rejects the sale and refreshes displayed prices; correct the cart/payment and retry.
- A failed or uncertain checkout retains its key and cart in the same tab's session
  storage. Retry there to retrieve the original receipt. Do not clear browser storage
  or start a replacement sale while its outcome is uncertain.
- Closing a completed receipt leaves an empty cart; it cannot resell the old cart.

## Commands and verification

```powershell
npm test
npm audit --omit=dev
npm run backup
```

Tests create isolated temporary databases; they never use the store database.
`reset:dev` deliberately creates a **new** empty `.dev.sqlite` file and refuses an
existing target. Required settings are documented in [testing](docs/TESTING.md).

Chart.js and html5-qrcode are version-pinned CDN scripts. If they cannot load, chart
or camera functionality is unavailable; product entry and keyboard scanning still
work. Core checkout needs a connection to the StoreEase server and does not queue
new sales offline.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| `npm` not recognized | Install Node with npm and reopen the terminal. In the Codex verification environment a temporary CLI was used under ignored `.tools/`; ordinary installations need standard npm. |
| Startup refuses migration | Read the reported integrity/validation error. Work on a backup copy and obtain an explicit repair decision; never run a reset against store data. |
| `EADDRINUSE` | Stop the previous server or set another `PORT`. |
| Database busy / HTTP 503 | Close competing writers, wait, and retry checkout using the **same** idempotency key. |
| 401 / 403 | Check the token, role, HTTPS origin and proxy configuration. Origin is exact, including any port. |
| Camera unavailable | Check HTTPS/localhost, camera permissions, and whether the pinned scanner library loaded. Use manual or keyboard entry. |
| Uncertain checkout after connection loss | Reopen/retry in the same browser tab. Keep its pending key; server replay returns the committed receipt. |
| Browser storage unavailable | Enable session storage before checkout; the browser refuses to submit without saving a retry key. |

## Further documentation

- [Architecture and data flow](docs/ARCHITECTURE.md)
- [Database, migrations, backup and restore](docs/DATABASE.md)
- [API contracts and intentional changes](docs/API.md)
- [Confirmed audit findings and remaining risks](docs/CODE_AUDIT.md)
- [Automated and manual tests](docs/TESTING.md)
- [Delivery and verification record](docs/DELIVERY.md)

Individual staff accounts, receipt reprints, refunds, inventory audit views and fully
offline asset packaging are possible future additions, outside this reliability update.
