"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { openDatabase } = require("../src/db/connection");
const { createApp } = require("../src/app");

async function fixture(t, config) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "storeease-debts-"));
  const db = await openDatabase(path.join(dir, "test.sqlite"));
  const adminToken = "a".repeat(32);
  const server = createApp(db, { host: "127.0.0.1", adminToken, ...config }).listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    db.close();
    fs.rmSync(dir, { recursive: true, force: true });
  });
  const request = async (url, method = "GET", body, headers = {}) => {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/api${url}`,
      {
        method,
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${adminToken}`,
          ...headers,
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      },
    );
    return { status: response.status, body: await response.json() };
  };
  const service = require("../src/modules/service")(db);
  return { db, request, service };
}

test("debts: customer management, debt additions, payments, and ledger accuracy", async (t) => {
  const { request, service } = await fixture(t);

  // 1. Create product for checkout tests
  const p = service.create({
    barcode_string: "B001",
    name: "Sardinas",
    price: "22.50",
  });

  // 2. Initial state: summary should be zeros
  const s0 = await request("/debts/summary");
  assert.equal(s0.status, 200);
  assert.equal(s0.body.total_debt, 0);
  assert.equal(s0.body.active_debtors, 0);
  assert.equal(s0.body.total_customers, 0);

  // 3. Create customer without initial debt
  const c1Res = await request("/debts/customers", "POST", {
    name: "Mang Juan",
    phone: "09181112222",
    address: "Zone 4",
    notes: "Regular customer",
  });
  assert.equal(c1Res.status, 200);
  assert.equal(c1Res.body.name, "Mang Juan");
  assert.equal(c1Res.body.balance, 0);
  const juanId = c1Res.body.id;

  // 4. Create customer with initial debt
  const c2Res = await request("/debts/customers", "POST", {
    name: "Aling Maria",
    phone: "09173334444",
    address: "Block 2 Lot 8",
    notes: "Neighbor",
    initial_debt: "100.00",
  });
  assert.equal(c2Res.status, 200);
  assert.equal(c2Res.body.balance, 10000); // 10000 cents = ₱100.00
  const mariaId = c2Res.body.id;

  // 5. Summary reflects Aling Maria's debt
  const s1 = await request("/debts/summary");
  assert.equal(s1.body.total_debt, 10000);
  assert.equal(s1.body.active_debtors, 1);
  assert.equal(s1.body.total_customers, 2);

  // 6. Search filtering: by name and phone
  const searchName = await request("/debts/customers?q=Juan");
  assert.equal(searchName.body.length, 1);
  assert.equal(searchName.body[0].name, "Mang Juan");

  const searchPhone = await request("/debts/customers?q=333");
  assert.equal(searchPhone.body.length, 1);
  assert.equal(searchPhone.body[0].name, "Aling Maria");

  // 7. Add manual debt to Mang Juan
  const addDebt = await request(`/debts/customers/${juanId}/debt`, "POST", {
    amount: "45.00",
    notes: "2 noodles + 1 coffee",
  });
  assert.equal(addDebt.status, 200);
  assert.equal(addDebt.body.balance, 4500);

  // Now both are active debtors
  const s2 = await request("/debts/summary");
  assert.equal(s2.body.total_debt, 14500); // 10000 + 4500
  assert.equal(s2.body.active_debtors, 2);

  // 8. POS checkout charged to Mang Juan's debt
  const posDebtSale = await request(
    "/sales",
    "POST",
    {
      items: [{ product_id: p.id, quantity: 2 }],
      payment_type: "debt",
      customer_id: juanId,
    },
    { "Idempotency-Key": "pos-debt-sale-1" },
  );
  assert.equal(posDebtSale.status, 200);
  assert.equal(posDebtSale.body.success, true);
  assert.equal(posDebtSale.body.payment_type, "debt");
  assert.equal(posDebtSale.body.customer_name, "Mang Juan");

  // Mang Juan's balance was 4500, + (2 * 2250 = 4500) = 9000
  const juanAfterSale = await request(`/debts/customers/${juanId}`);
  assert.equal(juanAfterSale.body.balance, 9000);

  // 9. Partial debt payment by Mang Juan
  const pay1 = await request(`/debts/customers/${juanId}/payment`, "POST", {
    amount: "50.00",
    notes: "Partial payment in cash",
  });
  assert.equal(pay1.status, 200);
  assert.equal(pay1.body.balance, 4000); // 9000 - 5000 = 4000

  // 10. Ledger check for Mang Juan
  const ledger = await request(`/debts/customers/${juanId}/transactions`);
  assert.equal(ledger.status, 200);
  assert.equal(ledger.body.entries.length, 3);
  assert.equal(ledger.body.entries[0].type, "payment");
  assert.equal(ledger.body.entries[0].amount, 5000);
  assert.equal(ledger.body.entries[0].balance_after, 4000);
  assert.equal(ledger.body.entries[1].type, "debt");
  assert.equal(ledger.body.entries[1].amount, 4500);
  assert.equal(ledger.body.entries[1].balance_after, 9000);
  assert.equal(ledger.body.entries[2].type, "debt");
  assert.equal(ledger.body.entries[2].amount, 4500);
  assert.equal(ledger.body.entries[2].balance_after, 4500);

  // 11. Overpayment rejection
  const overpay = await request(`/debts/customers/${juanId}/payment`, "POST", {
    amount: "50.00", // current balance is 40.00
  });
  assert.equal(overpay.status, 400);

  // 12. Deletion blocked when balance > 0
  const delBlocked = await request(`/debts/customers/${juanId}`, "DELETE");
  assert.equal(delBlocked.status, 400);

  // 13. Settle full remaining balance
  const fullPay = await request(`/debts/customers/${juanId}/payment`, "POST", {
    amount: "40.00",
    notes: "Full settlement",
  });
  assert.equal(fullPay.status, 200);
  assert.equal(fullPay.body.balance, 0);

  // 14. Deletion allowed when balance is 0
  const delSuccess = await request(`/debts/customers/${juanId}`, "DELETE");
  assert.equal(delSuccess.status, 200);
  assert.equal(delSuccess.body.success, true);

  // 15. Deleted customer no longer returned in customer list
  const custsAfter = await request("/debts/customers");
  assert.equal(custsAfter.body.some((c) => c.id === juanId), false);

  // Summary now only has Maria
  const finalSummary = await request("/debts/summary");
  assert.equal(finalSummary.body.total_debt, 10000);
  assert.equal(finalSummary.body.active_debtors, 1);
  assert.equal(finalSummary.body.total_customers, 1);
});

test("debts: automatic cash shortage checkout and duplicate customer prevention", async (t) => {
  const { request, service } = await fixture(t);

  const item1 = service.create({
    barcode_string: "ITEM-A",
    name: "Canned Tuna",
    price: "35.00",
  });
  const item2 = service.create({
    barcode_string: "ITEM-B",
    name: "Rice 1kg",
    price: "50.00",
  });

  // Pre-create customer 'Kardo Dalisay' with ₱20.00 initial debt
  const kardoRes = await request("/debts/customers", "POST", {
    name: "Kardo Dalisay",
    initial_debt: "20.00",
  });
  assert.equal(kardoRes.status, 200);
  assert.equal(kardoRes.body.balance, 2000); // ₱20.00
  const kardoId = kardoRes.body.id;

  // Scenario 1: Cart total is ₱85.00 (35 + 50). Cashier tenders ₱50.00.
  // Cash is short by ₱35.00. Checkout charged with customer_id.
  const shortSale1 = await request(
    "/sales",
    "POST",
    {
      items: [
        { product_id: item1.id, quantity: 1 },
        { product_id: item2.id, quantity: 1 },
      ],
      payment_type: "debt",
      customer_id: kardoId,
      tendered_amount: 5000, // ₱50.00 cash paid
    },
    { "Idempotency-Key": "short-sale-1" },
  );
  assert.equal(shortSale1.status, 200);
  assert.equal(shortSale1.body.total_amount, 8500);
  assert.equal(shortSale1.body.payment_type, "debt");
  assert.equal(shortSale1.body.cash_paid, 5000);
  assert.equal(shortSale1.body.debt_amount, 3500);
  assert.equal(shortSale1.body.customer_name, "Kardo Dalisay");
  // Balance was 2000, now 2000 + 3500 = 5500
  assert.equal(shortSale1.body.customer_balance, 5500);

  // Scenario 2: Same customer buys again. Cart total = ₱70.00 (2 * 35).
  // Cash tendered = ₱20.00. Shortage = ₱50.00.
  // Frontend sends customer_name with different casing: "  kardo dalisay  ".
  // MUST NOT create duplicate; MUST update existing Kardo Dalisay!
  const shortSale2 = await request(
    "/sales",
    "POST",
    {
      items: [{ product_id: item1.id, quantity: 2 }],
      payment_type: "debt",
      customer_name: "  kardo dalisay  ",
      tendered_amount: 2000,
    },
    { "Idempotency-Key": "short-sale-2" },
  );
  assert.equal(shortSale2.status, 200);
  assert.equal(shortSale2.body.customer_id, kardoId); // Same customer ID!
  assert.equal(shortSale2.body.cash_paid, 2000);
  assert.equal(shortSale2.body.debt_amount, 5000);
  // Balance was 5500, now 5500 + 5000 = 10500 (₱105.00)
  assert.equal(shortSale2.body.customer_balance, 10500);

  // Verify only 1 customer exists in database, no duplicate!
  const customersList = await request("/debts/customers");
  assert.equal(customersList.body.length, 1);
  assert.equal(customersList.body[0].id, kardoId);
  assert.equal(customersList.body[0].balance, 10500);

  // Scenario 3: Brand new person is short: "Elena Ramos"
  // Cart total = ₱50.00. Tendered = ₱0.00 (or empty). Full ₱50.00 charged to debt.
  const shortSale3 = await request(
    "/sales",
    "POST",
    {
      items: [{ product_id: item2.id, quantity: 1 }],
      payment_type: "debt",
      customer_name: "Elena Ramos",
      tendered_amount: 0,
    },
    { "Idempotency-Key": "short-sale-3" },
  );
  assert.equal(shortSale3.status, 200);
  assert.equal(shortSale3.body.customer_name, "Elena Ramos");
  assert.equal(shortSale3.body.debt_amount, 5000);
  assert.equal(shortSale3.body.cash_paid, 0);
  assert.equal(shortSale3.body.customer_balance, 5000);

  // Total customers is now 2
  const updatedCusts = await request("/debts/customers");
  assert.equal(updatedCusts.body.length, 2);

  // Check Kardo's ledger entries have proper notes for shortages
  const kardoLedger = await request(`/debts/customers/${kardoId}/transactions`);
  assert.equal(kardoLedger.status, 200);
  assert.ok(kardoLedger.body.entries[0].notes.includes("Short: ₱50.00, Paid: ₱20.00"));
  assert.ok(kardoLedger.body.entries[1].notes.includes("Short: ₱35.00, Paid: ₱50.00"));
});
