"use strict";
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  vm = require("node:vm"),
  fs = require("node:fs");
const source = fs.readFileSync("public/app.js", "utf8");
test("low stock includes the threshold and zero, and clears after restock", () => {
  const { run } = browser();
  assert.equal(run('stockStatus({stock: 5, reorder_level: 5})'), "Low Stock");
  assert.equal(run('stockStatus({stock: 6, reorder_level: 5})'), "");
  assert.equal(run('stockStatus({stock: null, reorder_level: 5})'), "");
  assert.equal(run('stockStatus({stock: 0, reorder_level: null})'), "Out of Stock");
});
function browser(t) {
  const elements = new Map(),
    documentEvents = {},
    calls = [],
    stored = new Map();
  function element(id) {
    if (elements.has(id)) return elements.get(id);
    const classes = new Set(
      [
        "inventory-view",
        "dashboard-view",
        "receipt-modal",
        "product-modal",
        "error-banner",
      ].includes(id)
        ? ["hidden"]
        : [],
    );
    const el = {
      value: "",
      disabled: false,
      hidden: false,
      innerHTML: "",
      textContent: "",
      style: {},
      tagName: "INPUT",
      listeners: {},
      classList: {
        contains: (c) => classes.has(c),
        add: (c) => classes.add(c),
        remove: (c) => classes.delete(c),
      },
      addEventListener: (name, fn) => {
        el.listeners[name] = fn;
      },
      focus() {
        doc.activeElement = el;
      },
      matches: () => true,
    };
    elements.set(id, el);
    return el;
  }
  const doc = {
    getElementById: element,
    addEventListener: (name, fn) => (documentEvents[name] = fn),
    activeElement: null,
  };
  const context = {
    document: doc,
    console: { ...console, warn() {}, error() {} },
    setTimeout: () => 1,
    clearTimeout() {},
    sessionStorage: {
      getItem: (k) => stored.get(k) || null,
      setItem: (k, v) => stored.set(k, v),
      removeItem: (k) => stored.delete(k),
    },
    crypto: require("node:crypto").webcrypto,
    structuredClone,
    Date,
    prompt: () => "",
    alert() {},
    confirm: () => true,
    location: { reload() {} },
    window: {
      addEventListener() {},
      fetch: async (url, options) => {
        calls.push({ url, options });
        return {
          status: 200,
          ok: true,
          json: async () =>
            url === "/api/session"
              ? { role: "admin" }
              : {
                  id: 1,
                  barcode_string: "001",
                  name: "<img src=x onerror=alert(1)>",
                  price: 100,
                },
        };
      },
    },
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  return {
    context,
    e: element,
    calls,
    events: documentEvents,
    run: (code) => vm.runInContext(code, context),
  };
}
test("manual scanning encodes path, ignores repeat Enter and safely renders names", async (t) => {
  const { e, calls, run } = browser(t);
  e("barcode-input").value = "001";
  e("barcode-input").listeners.keydown({ key: "Enter", repeat: true });
  assert.equal(
    calls.filter((c) => c.url.startsWith("/api/products")).length,
    0,
  );
  e("barcode-input").listeners.keydown({ key: "Enter", repeat: false });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(calls.filter((c) => c.url === "/api/products/001").length, 1);
  assert.ok(e("cart-body").innerHTML.includes("&lt;img"));
  assert.ok(!e("cart-body").innerHTML.includes("<img"));
  await run("handleBarcodeScan('00/1?#')");
  assert.ok(calls.some((c) => c.url === "/api/products/00%2F1%3F%23"));
});

test('definite checkout rejection refreshes prices and unlocks payment', async t => {
  const {run,e}=browser(t);run("addToCart({id:1,name:'Egg',barcode_string:'001',price:100})");e('amount-tendered').value='2.00';
  run("apiFetch = async url => url === '/api/sales' ? {ok:false,status:409,json:async()=>({error:'Price changed',code:'CONFLICT'})} : {ok:true,json:async()=>[{id:1,name:'Egg',barcode_string:'001',price:300}]} ");
  await run('handleCheckout()');assert.equal(run('pendingCheckout'),null);assert.equal(e('amount-tendered').disabled,false);assert.equal(run('cart[0].product.price'),300);assert.equal(e('checkout-btn').disabled,true);
});

test('unknown barcode preserves unrelated cart and encoded name cannot inject handlers', async t => {
  const {run,e}=browser(t);run("addToCart({id:1,name:'Egg',barcode_string:'001',price:100})");
  run("apiFetch = async () => ({ok:false,status:404,json:async()=>({error:'Unknown'})})");await run("handleBarcodeScan('missing')");
  assert.equal(run('cart.length'),1);assert.equal(e('error-message').textContent,'Unknown');assert.ok(!e('cart-body').innerHTML.includes('onclick='));
});

test('checkout refuses to submit if its retry key cannot be persisted', async t => {
  const {run,e,context}=browser(t);run("addToCart({id:1,name:'Egg',barcode_string:'001',price:100})");e('amount-tendered').value='2.00';
  context.sessionStorage.setItem=()=>{throw new Error('storage denied');};let sent=false;context.send=()=>{sent=true;};run('apiFetch = async () => { send(); }');await run('handleCheckout()');
  assert.equal(sent,false);assert.equal(run('checkoutBusy'),false);assert.equal(run('pendingCheckout'),null);
});
test("global scanner never intercepts product editing or non-POS views", async (t) => {
  const { context, e, calls, events } = browser(t);
  context.document.activeElement = e("form-product-name");
  for (const key of ["1", "2", "3", "Enter"]) events.keydown({ key });
  context.document.activeElement = { matches: () => false };
  e("pos-view").classList.add("hidden");
  for (const key of ["1", "2", "3", "Enter"]) events.keydown({ key });
  assert.equal(
    calls.filter((c) => c.url.startsWith("/api/products")).length,
    0,
  );
});
test("checkout suppresses double click, uses committed receipt and clears sold cart", async (t) => {
  const { context, e, run } = browser(t);
  run("addToCart({id:1,name:'Old',barcode_string:'001',price:100})");
  e("amount-tendered").value = "5.00";
  let finish;
  context.window.fetch = undefined; // apiFetch already captured the native stub; override for this scenario.
  context.nativeSaleResponse = new Promise((resolve) => {
    finish = resolve;
  });
  run("apiFetch = async () => await nativeSaleResponse");
  const first = run("handleCheckout()");
  await run("handleCheckout()");
  finish({
    ok: true,
    status: 200,
    json: async () => ({
      sale_id: 1,
      total_amount: 200,
      items: [
        {
          product_id: 1,
          product_name: "Saved",
          barcode_string: "001",
          price: 200,
          quantity: 1,
        },
      ],
    }),
  });
  await first;
  assert.equal(e("receipt-total").textContent, "₱2.00");
  assert.ok(e("receipt-items").innerHTML.includes("Saved"));
  assert.equal(run("cart.length"), 0);
  assert.equal(run("checkoutBusy"), false);
  e("cancel-receipt-btn").listeners.click();
  assert.equal(run("cart.length"), 0);
});
test("failed network checkout retains key and cart for retry", async (t) => {
  const { run, e } = browser(t);
  run("addToCart({id:1,name:'Egg',barcode_string:'001',price:100})");
  e("amount-tendered").value = "2.00";
  run("apiFetch = async () => { throw new Error('offline'); }");
  await run("handleCheckout()");
  const key = run("pendingCheckout.key");
  assert.equal(run("cart.length"), 1);
  assert.equal(run("checkoutBusy"), false);
  await run("handleCheckout()");
  assert.equal(run("pendingCheckout.key"), key);
});
test("product search is case-insensitive, prioritizes first-letter matches and generates preview", () => {
  const { run, e } = browser();
  run(`inventoryProducts = [
    { id: 1, name: "Egg", barcode_string: "001", price: 100, stock: 10 },
    { id: 2, name: "Hotdog", barcode_string: "002", price: 200, stock: 5 },
    { id: 3, name: "Cheese Dog", barcode_string: "003", price: 250, stock: 2 }
  ]`);

  // Lowercase first letter 'e'
  e("manual-barcode").value = "e";
  run("updateSearchPreview()");
  assert.equal(run("previewMatches[0].name"), "Egg");
  assert.ok(e("search-preview-dropdown").innerHTML.includes("search-match"));
  assert.ok(e("search-preview-dropdown").innerHTML.includes("<mark class=\"search-match\">E</mark>gg"));

  // Uppercase first letter 'E'
  e("manual-barcode").value = "E";
  run("updateSearchPreview()");
  assert.equal(run("previewMatches[0].name"), "Egg");

  // First letter 'h' matches 'Hotdog'
  e("manual-barcode").value = "h";
  run("updateSearchPreview()");
  assert.equal(run("previewMatches[0].name"), "Hotdog");

  // Uppercase 'H' matches 'Hotdog'
  e("manual-barcode").value = "H";
  run("updateSearchPreview()");
  assert.equal(run("previewMatches[0].name"), "Hotdog");

  // Enter adds the top preview match to cart
  run("manualBarcode.value = 'e'; updateSearchPreview()");
  e("manual-barcode").listeners.keydown({ key: "Enter" });
  assert.equal(run("cart.length"), 1);
  assert.equal(run("cart[0].product.name"), "Egg");
});

test("cash shortage automatically prompts shortage modal with debtor matching and updates existing debtor without duplicate", async (t) => {
  const { run, e, calls } = browser(t);

  // Setup product in cart: ₱50.00
  run("addToCart({ id: 1, name: 'Rice 1kg', barcode_string: '001', price: 5000 })");

  // Cashier tenders ₱20.00, so shortage is ₱30.00
  e("amount-tendered").value = "20.00";
  run("calculateChange()");
  assert.equal(e("summary-change").textContent, "-₱30.00");
  assert.equal(e("checkout-btn").textContent, "Complete Sale (Short)");

  // Mock debtor list returned from backend
  run(`apiFetch = async (url, opts) => {
    if (url === '/api/debts/customers') {
      return {
        ok: true,
        status: 200,
        json: async () => [{ id: 10, name: 'Juan dela Cruz', balance: 1500 }]
      };
    }
    if (url === '/api/sales') {
      const body = JSON.parse(opts.body);
      return {
        ok: true,
        status: 200,
        json: async () => ({
          sale_id: 99,
          total_amount: body.total_amount,
          payment_type: 'debt',
          customer_id: body.customer_id,
          customer_name: 'Juan dela Cruz',
          customer_balance: 4500, // 1500 + 3000
          cash_paid: body.tendered_amount,
          debt_amount: 3000,
          items: [{ product_id: 1, product_name: 'Rice 1kg', barcode_string: '001', price: 5000, quantity: 1 }]
        })
      };
    }
    return { ok: true, json: async () => [] };
  }`);

  // Cashier clicks Complete Sale with shortage
  await run("handleCheckout()");

  // Shortage modal pops up automatically!
  assert.equal(e("shortage-modal").classList.contains("hidden"), false);
  assert.equal(e("shortage-total-due").textContent, "₱50.00");
  assert.equal(e("shortage-cash-paid").textContent, "₱20.00");
  assert.equal(e("shortage-amount-due").textContent, "₱30.00");

  // Cashier enters debtor name in different casing: "juan dela cruz"
  e("shortage-customer-input").value = "juan dela cruz";
  run("updateShortageCustomerMatch()");

  // Existing customer is matched case-insensitively, preventing duplicates!
  assert.equal(run("selectedShortageDebtor.id"), 10);
  assert.equal(run("selectedShortageDebtor.name"), "Juan dela Cruz");
  assert.ok(e("shortage-match-banner").innerHTML.includes("Existing Customer"));
  assert.ok(e("shortage-match-banner").innerHTML.includes("No duplicate will be created"));
  assert.equal(e("confirm-shortage-btn").disabled, false);

  // Confirming shortage checkout submits sale linked to existing debtor
  await run("confirmShortageCheckout()");

  // Modal closes and receipt modal displays shortage & debt breakdown
  assert.equal(e("shortage-modal").classList.contains("hidden"), true);
  assert.equal(e("receipt-total").textContent, "₱50.00");
  assert.equal(e("receipt-debtor-name").textContent, "Juan dela Cruz");
  assert.equal(e("receipt-debt-charged").textContent, "₱30.00");
  assert.equal(e("receipt-debt-balance").textContent, "₱45.00");
  assert.equal(run("cart.length"), 0);
});

test("debt status tabs filter active debts vs fully paid debtors and display counts", async (t) => {
  const { run, e, context } = browser(t);
  const debtsCode = fs.readFileSync("public/debts.js", "utf8");

  run(`apiFetch = async (url) => {
    if (url === '/api/debts/summary') {
      return { ok: true, json: async () => ({ total_debt: 17000, active_debtors: 2, total_customers: 3 }) };
    }
    if (url === '/api/debts/customers') {
      return {
        ok: true,
        json: async () => [
          { id: 1, name: 'Aling Nena', balance: 5000 },
          { id: 2, name: 'Mang Juan', balance: 0 },
          { id: 3, name: 'Pedro Penduko', balance: 12000 }
        ]
      };
    }
    return { ok: true, json: async () => [] };
  }; window.apiFetch = apiFetch;`);

  // Run debts script in context
  vm.runInContext(debtsCode, context);

  // Load summary and debtors
  await run("window.debts.reload()");

  // Check tab count badges
  assert.equal(e("count-active-debts").textContent, 2);
  assert.equal(e("count-paid-debts").textContent, 1);
  assert.equal(e("count-all-debts").textContent, 3);

  // Default filter is 'active': should render only Aling Nena and Pedro Penduko (balance > 0)
  assert.equal(e("debtors-count-badge").textContent, "2 Active Debtors");
  assert.ok(e("debtors-table-body").innerHTML.includes("Aling Nena"));
  assert.ok(e("debtors-table-body").innerHTML.includes("Pedro Penduko"));
  assert.ok(!e("debtors-table-body").innerHTML.includes("Mang Juan"));

  // Switch to 'paid' (Fully Paid) filter: should render only Mang Juan (balance === 0)
  run("window.debts.setStatusFilter('paid')");
  assert.equal(e("debtors-count-badge").textContent, "1 Fully Paid");
  assert.ok(e("debtors-table-body").innerHTML.includes("Mang Juan"));
  assert.ok(!e("debtors-table-body").innerHTML.includes("Aling Nena"));
  assert.ok(!e("debtors-table-body").innerHTML.includes("Pedro Penduko"));

  // Switch to 'all' filter: should render all 3 debtors
  run("window.debts.setStatusFilter('all')");
  assert.equal(e("debtors-count-badge").textContent, "3 Total Debtors");
  assert.ok(e("debtors-table-body").innerHTML.includes("Aling Nena"));
  assert.ok(e("debtors-table-body").innerHTML.includes("Mang Juan"));
  assert.ok(e("debtors-table-body").innerHTML.includes("Pedro Penduko"));
});
