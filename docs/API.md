# StoreEase API

Same-origin JSON under `/api`. No wildcard CORS is enabled. Requests containing bodies
use `Content-Type: application/json`; bodies are limited to 64 KiB. IDs and quantities
are positive safe integers. Barcodes are nonempty strings up to 128 characters,
trimmed at the boundary, with leading zeros preserved and control characters refused.
Names are trimmed, nonempty, and at most 200 characters. URL-encode barcode path values.

## Authentication and roles

Trusted localhost mode permits operator/admin access. If `ADMIN_TOKEN` is configured,
send `Authorization: Bearer <token>` on every API request. `CASHIER_TOKEN` is optional
and must differ from the admin token. Tokens are 32–256 random letters/digits/`_`/`-`;
there are no default credentials. Network startup additionally requires an HTTPS
`PUBLIC_ORIGIN` and explicit `HOST`. Use HTTPS termination and restrict backend access.

The server uses stateless bearer authentication, not cookies. The browser keeps a token
in memory only and forgets it on refresh/sign out. Environment rotation plus restart
revokes a token; there are no per-user sessions or separate login endpoints.

| Method and endpoint | Role | Result |
| --- | --- | --- |
| GET `/session` | Either | `{ "role": "admin" }` or `cashier`. |
| GET `/products` | Either | Active product array, alphabetically ordered. |
| GET `/products/:barcode` | Either | Active product or 404. This path is a barcode, not an ID. |
| POST `/products` | Admin | Created product, HTTP 200 for compatibility. |
| PUT `/products/:id` | Admin | Updated active product or 404. |
| DELETE `/products/:id` | Admin | Soft deactivation, `{ "success": true }`; unknown/inactive ID is 404. |
| POST `/products/:id/stock` | Admin | Product with updated stock. |
| POST `/sales` | Either | Confirmed committed receipt or replay. |
| GET `/analytics` | Admin | KPI totals, popular items, seven local-date chart points. |

## Money contract

**Product write `price` is decimal pesos**, preferably an exact decimal string. A JSON
number is accepted if its string representation meets the same grammar. Zero is allowed;
negative, exponent notation strings, trailing junk, excess precision and unsafe values
are rejected. `"12.05"` becomes 1205 centavos. Do not send an integer centavo read value
back as a write price without converting it to pesos.

**All read prices, sales totals, tendered_amount, line totals and analytics revenue are
integer centavos**, bounded by JavaScript's safe integer maximum 9,007,199,254,740,991.
Overflowing lines/totals are refused before a sale is written. Oversized aggregate
analytics fail safely instead of returning rounded numbers.

```json
{ "barcode_string": "000123", "name": "Egg", "price": "12.05" }
```

A product read also includes `id`, `price: 1205`, `active: 1`, and `stock: null` (untracked)
or an integer. `PUT` requires all three write fields. Barcode duplicates, including
reserved barcodes of inactive products, return 409.

## Stock

```json
{ "delta": 10, "reason": "Initial shelf count" }
```

Send to `/products/1/stock`. The first adjustment starts tracking from zero; subsequent
deltas can be positive or negative but cannot produce negative/unsafe stock. Reason is
required, trimmed and at most 300 characters. All adjustments and sale decrements are
recorded. Products with null stock remain sellable without count enforcement. There is
currently no API for switching a counted product back to untracked.

## Checkout

Send a unique `Idempotency-Key` header, up to 128 characters; browser clients use UUIDs.
Persist it before the request. Reuse it on retries; never generate a replacement key
merely because the response was lost.

```json
{
  "items": [ { "product_id": 1, "quantity": 2 } ],
  "tendered_amount": 3000
}
```

`items` requires 1–500 lines. Repeated product IDs are merged and sorted for canonical
request identity. Optional legacy `total_amount` and item `price` fields are ignored.
Database prices determine all totals. Optional integer `tendered_amount` must cover the
computed total; it is validated but not stored as accounting/payment data.

```json
{
  "success": true,
  "sale_id": 42,
  "total_amount": 2410,
  "items": [
    {
      "product_id": 1,
      "product_name": "Egg",
      "barcode_string": "000123",
      "quantity": 2,
      "price": 1205,
      "line_total": 2410
    }
  ]
}
```

Same key and canonical cart returns the original committed receipt, including after
product edits/deactivation. A different cart with the same key returns 409 and code
`IDEMPOTENCY_CONFLICT`. Keys are currently global across roles, with no expiry. Do not
use guessable/order-number-only keys. Validation, missing products, insufficient stock,
payment failure or failed writes never leave a partial sale. A busy database returns
503; retry using the same key. Replays do not decrement stock again.

## Analytics

Response preserves the existing shape:

```json
{
  "kpis": { "today": 0, "week": 0, "month": 0, "year": 0 },
  "popularItems": [],
  "chartData": { "labels": ["2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07", "2026-11-08", "2026-11-09"], "data": [0,0,0,0,0,0,0] }
}
```

Periods use Manila calendar days, Sunday-start weeks, calendar months and years.
KPI periods end at the next local midnight; chart has seven continuous local dates.
Popular items are lifetime quantities/revenue grouped by product and snapshot name,
so renamed products can appear as separate historical labels. Financial header KPIs
use stored Sales totals; popular revenue uses stored item lines. Legacy discrepancies
are intentionally preserved and may make these figures differ.

## Errors and intentional compatibility changes

Errors always have `{ "error": "Readable message", "code": "MACHINE_CODE" }`.
Status codes include 400 invalid input/JSON, 401 missing token, 403 origin/role denial,
404 missing resource, 409 duplicate barcode/stock/payment/idempotency conflict,
413 oversized body, 500 internal failure and 503 database busy. Internal stack traces
and SQL are not returned. Clients should use status/code rather than matching messages.

Intentional changes: checkout now requires an idempotency header; unsafe product values
are rejected; duplicate barcodes return 409; deletion deactivates products; network API
access requires configured credentials; chart labels are ISO Manila dates rather than
host-local formatted strings. Existing routes and normal JSON shapes remain compatible,
with added stock/receipt fields. Product response price units remain centavos.
