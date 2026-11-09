"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { DatabaseSync } = require("node:sqlite");
const { openDatabase } = require("../src/db/connection");
const { createApp } = require("../src/app");
const v = require("../src/utils/validation");
async function fixture(t, config) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "storeease-"));
  const db = await openDatabase(path.join(dir, "test.sqlite"));
  const server = createApp(db, config).listen(0, "127.0.0.1");
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
        headers: { "Content-Type": "application/json", ...headers },
        body: body === undefined ? undefined : JSON.stringify(body),
      },
    );
    return { status: response.status, body: await response.json() };
  };
  const service = require("../src/modules/service")(db);
  return { db, request, service, baseURL: `http://127.0.0.1:${server.address().port}` };
}
const product = (code = "001") => ({
  barcode_string: code,
  name: "Egg <fresh>",
  price: "12.05",
});
const sale = (id, quantity = 1) => ({
  total_amount: -1,
  items: [{ product_id: id, quantity, price: 0 }],
});
test("strict exact monetary and ID validation", () => {
  for (const value of [
    "1x",
    "1.001",
    "NaN",
    "Infinity",
    -1,
    "1e3",
    "",
    null,
    {},
    "90071992547410",
  ])
    assert.throws(() => v.money(value));
  assert.equal(v.money("0.29"), 29);
  assert.equal(v.money("0"), 0);
  assert.equal(v.money(12.05), 1205);
  for (const value of ["0", "1x", "1.1", -1, Number.MAX_SAFE_INTEGER + 1, [1], true])
    assert.throws(() => v.id(value));
});

test('malformed/oversized JSON, headers and private files', async t => {
  const {baseURL}=await fixture(t);
  const invalid=await fetch(baseURL+'/api/products',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"secret":"never echo",bad}'});
  assert.equal(invalid.status,400);assert.equal((await invalid.json()).error,'Invalid JSON body');
  const large=await fetch(baseURL+'/api/products',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'x'.repeat(70000)})});
  assert.equal(large.status,413);
  for (const file of ['/database.sqlite','/.env','/server.js','/package.json']) assert.equal((await fetch(baseURL+file)).status,404);
  const page=await fetch(baseURL+'/');assert.equal(page.status,200);assert.equal(page.headers.get('x-content-type-options'),'nosniff');assert.ok(!page.headers.get('content-security-policy').includes("script-src 'self' 'unsafe-inline'"));
});

test('independent SQLite connections serialize the same checkout key', async t => {
  const {db,service}=await fixture(t);const p=service.create(product());service.adjust(p.id,{delta:1,reason:'Initial count'});
  const {Worker}=require('node:worker_threads');
  const filename=db.prepare('PRAGMA database_list').get().file;
  const workerCode=`const {parentPort,workerData}=require('node:worker_threads'); (async()=>{const db=await require(workerData.connection).openDatabase(workerData.filename);try{const service=require(workerData.service)(db);parentPort.postMessage(service.checkout({items:[{product_id:workerData.id,quantity:1}]},'shared-key'));}finally{db.close();}})().catch(err=>{throw err;});`;
  const run=()=>new Promise((resolve,reject)=>{
    const worker=new Worker(workerCode,{eval:true,workerData:{filename,id:p.id,connection:require.resolve('../src/db/connection'),service:require.resolve('../src/modules/service')}});
    let receipt;worker.on('message',value=>{receipt=value;});worker.once('error',reject);worker.once('exit',code=>code?reject(new Error('Worker failed')):resolve(receipt));
  });
  const [first,second]=await Promise.all([run(),run()]);assert.equal(first.sale_id,second.sale_id);assert.equal(service.list()[0].stock,0);assert.equal(db.prepare('SELECT COUNT(*) n FROM Sales').get().n,1);
});
test("products CRUD, barcode strings, validation, stock adjustment", async (t) => {
  const { request } = await fixture(t);
  for (const body of [
    { ...product(), barcode_string: " " },
    { ...product(), name: " " },
    { ...product(), price: "1garbage" },
    { ...product(), barcode_string: 123 },
  ])
    assert.equal((await request("/products", "POST", body)).status, 400);
  const p = (await request("/products", "POST", product())).body;
  assert.equal(p.price, 1205);
  assert.equal((await request("/products/001")).body.id, p.id);
  assert.equal((await request("/products", "POST", product())).status, 409);
  assert.equal(
    (await request("/products/999", "PUT", product("002"))).status,
    404,
  );
  assert.equal((await request("/products/nope", "DELETE")).status, 400);
  assert.equal(
    (await request(`/products/${p.id}`, "PUT", { ...product(), price: "0" }))
      .body.price,
    0,
  );
  assert.equal(
    (
      await request(`/products/${p.id}/stock`, "POST", {
        delta: 2,
        reason: "Initial count",
      })
    ).body.stock,
    2,
  );
  assert.equal(
    (
      await request(`/products/${p.id}/stock`, "POST", {
        delta: -3,
        reason: "Correction",
      })
    ).status,
    400,
  );
  assert.equal((await request(`/products/${p.id}`, "DELETE")).status, 200);
  assert.equal((await request("/products/001")).status, 404);
  assert.deepEqual((await request("/products")).body, []);
  assert.equal((await request(`/products/${p.id}`, "DELETE")).status, 404);
});
test("authoritative checkout, replay, conflict, snapshots and foreign keys", async (t) => {
  const { request, db, service } = await fixture(t);
  const p = service.create(product());
  assert.equal((await request("/sales", "POST", sale(p.id))).status, 400);
  const key = { "Idempotency-Key": "abc" },
    first = await request("/sales", "POST", sale(p.id, 2), key);
  assert.equal(first.body.total_amount, 2410);
  assert.deepEqual(await request("/sales", "POST", sale(p.id, 2), key), first);
  assert.equal(
    (await request("/sales", "POST", sale(p.id, 3), key)).status,
    409,
  );
  service.update(p.id, { ...product(), name: "Changed", price: "99" });
  service.deactivate(p.id);
  assert.deepEqual(
    (await request("/sales", "POST", sale(p.id, 2), key)).body,
    first.body,
  );
  assert.equal(first.body.items[0].product_name, "Egg <fresh>");
  assert.equal(db.prepare("PRAGMA foreign_keys").get().foreign_keys, 1);
  assert.throws(
    () => db.prepare("DELETE FROM Products WHERE id=?").run(p.id),
    /FOREIGN KEY/,
  );
  assert.throws(
    () =>
      db
        .prepare(
          "INSERT INTO SaleItems(sale_id,product_id,quantity,price,product_name,barcode_string,line_total) VALUES(999,999,1,1,'a','a',1)",
        )
        .run(),
    /FOREIGN KEY/,
  );
});
test("invalid quantities, missing products, overflow and insert failure roll back", async (t) => {
  const { request, db, service } = await fixture(t);
  const p = service.create(product());
  for (const qty of [0, -1, 1.5, "2", null, Number.MAX_SAFE_INTEGER])
    assert.equal(
      (
        await request("/sales", "POST", sale(p.id, qty), {
          "Idempotency-Key": "bad" + qty,
        })
      ).status,
      400,
    );
  assert.equal(
    (
      await request("/sales", "POST", sale(999), {
        "Idempotency-Key": "missing",
      })
    ).status,
    404,
  );
  db.exec(
    "CREATE TRIGGER fail_item BEFORE INSERT ON SaleItems BEGIN SELECT RAISE(ABORT,'forced failure'); END;",
  );
  assert.equal(
    (await request("/sales", "POST", sale(p.id), { "Idempotency-Key": "fail" }))
      .status,
    500,
  );
  assert.equal(db.prepare("SELECT COUNT(*) n FROM Sales").get().n, 0);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM SaleItems").get().n, 0);
  db.exec("DROP TRIGGER fail_item");
  assert.equal(
    (await request("/sales", "POST", sale(p.id), { "Idempotency-Key": "fail" }))
      .status,
    200,
  );
});
test("simultaneous checkouts and stock changes are atomic", async (t) => {
  const { request, db, service } = await fixture(t);
  const p = service.create(product());
  service.adjust(p.id, { delta: 5, reason: "Restock" });
  const repeated = await Promise.all(
    Array.from({ length: 12 }, () =>
      request("/sales", "POST", sale(p.id), { "Idempotency-Key": "same" }),
    ),
  );
  assert.equal(new Set(repeated.map((r) => r.body.sale_id)).size, 1);
  const results = await Promise.all(
    Array.from({ length: 8 }, (_, i) =>
      request("/sales", "POST", sale(p.id), {
        "Idempotency-Key": "different" + i,
      }),
    ),
  );
  assert.equal(results.filter((r) => r.status === 200).length, 4);
  assert.equal(results.filter((r) => r.status === 409).length, 4);
  assert.equal(service.list()[0].stock, 0);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM Sales").get().n, 5);
});
test("busy database returns retryable failure without partial sale", async (t) => {
  const { db, request, service } = await fixture(t);
  const p = service.create(product());
  const filename = db.prepare("PRAGMA database_list").get().file,
    other = new DatabaseSync(filename);
  db.exec("PRAGMA busy_timeout=20");
  other.exec("BEGIN IMMEDIATE");
  try {
    assert.equal(
      (
        await request("/sales", "POST", sale(p.id), {
          "Idempotency-Key": "busy",
        })
      ).status,
      503,
    );
  } finally {
    other.exec("ROLLBACK");
    other.close();
  }
  assert.equal(db.prepare("SELECT COUNT(*) n FROM Sales").get().n, 0);
  assert.equal(
    (await request("/sales", "POST", sale(p.id), { "Idempotency-Key": "busy" }))
      .status,
    200,
  );
});
test("Manila midnight, Sunday, month and year boundaries", async (t) => {
  const { db } = await fixture(t);
  db.exec(
    "INSERT INTO Sales(timestamp,total_amount) VALUES('2025-12-31 15:59:59',100),('2025-12-31 16:00:00',200),('2026-01-03 16:00:00',300),('2026-01-04 16:00:00',999)",
  );
  const a = require("../src/modules/analytics")(
    db,
    new Date("2026-01-04T15:59:59Z"),
  );
  assert.deepEqual(a.kpis, { today: 300, week: 300, month: 500, year: 500 });
  assert.equal(a.chartData.labels.at(-1), "2026-01-04");
  assert.equal(a.chartData.data.at(-1), 300);
});
test("authentication, roles, origin and safe errors", async (t) => {
  const admin = "a".repeat(32),
    cashier = "c".repeat(32),
    { request } = await fixture(t, {
      host: "127.0.0.1",
      adminToken: admin,
      cashierToken: cashier,
    });
  assert.equal((await request("/products")).status, 401);
  const headers = { Authorization: "Bearer " + cashier };
  assert.equal(
    (await request("/products", "GET", undefined, headers)).status,
    200,
  );
  assert.equal(
    (await request("/products", "POST", product(), headers)).status,
    403,
  );
  assert.equal(
    (await request("/analytics", "GET", undefined, headers)).status,
    403,
  );
  assert.equal(
    (await request("/ANALYTICS/", "GET", undefined, headers)).status,
    403,
  );
  assert.equal(
    (await request("/Products/", "POST", product(), headers)).status,
    403,
  );
  assert.equal(
    (
      await request("/products", "POST", product(), {
        Authorization: "Bearer " + admin,
      })
    ).status,
    200,
  );
  assert.equal(
    (
      await request("/products", "GET", undefined, {
        ...headers,
        Origin: "https://evil.example",
      })
    ).status,
    403,
  );
  assert.equal(
    (await request("/unknown", "GET", undefined, headers)).status,
    404,
  );
});

test("insufficient tendered amount rejects stale prices without a sale", async (t) => {
  const { request, service, db } = await fixture(t);
  const p = service.create(product());
  assert.equal(
    (
      await request(
        "/sales",
        "POST",
        { ...sale(p.id), tendered_amount: 1 },
        { "Idempotency-Key": "payment" },
      )
    ).status,
    409,
  );
  assert.equal(db.prepare("SELECT COUNT(*) n FROM Sales").get().n, 0);
  assert.equal(
    (
      await request(
        "/sales",
        "POST",
        { ...sale(p.id), tendered_amount: 1205 },
        { "Idempotency-Key": "payment" },
      )
    ).status,
    200,
  );
});

test("configuration prevents unsafe network binding and public database paths", () => {
  const config = require("../src/config");
  assert.throws(() => config({ HOST: "0.0.0.0" }), /Network binding/);
  assert.throws(
    () => config({ DB_PATH: path.join(__dirname, "../public/data.sqlite") }),
    /outside public/,
  );
  assert.throws(() => config({ PORT: "wrong" }), /PORT/);
  assert.throws(() => config({ ADMIN_TOKEN: "short" }), /Tokens/);
  assert.throws(
    () => config({ PUBLIC_ORIGIN: "https://example.com/path" }),
    /origin/,
  );
  assert.equal(config({}).host, "127.0.0.1");
});

test("commit failure never returns a result and attempts rollback", () => {
  const commands = [];
  const db = {
    exec(sql) {
      commands.push(sql);
      if (sql === "COMMIT") throw new Error("disk full");
    },
  };
  assert.throws(
    () =>
      require("../src/db/connection").transaction(db, () => ({
        success: true,
      })),
    /disk full/,
  );
  assert.deepEqual(commands, ["BEGIN IMMEDIATE", "COMMIT", "ROLLBACK"]);
});

test("analytics refuses aggregate values beyond safe JSON integers", async (t) => {
  const { db } = await fixture(t);
  db.prepare("INSERT INTO Sales(total_amount) VALUES(?)").run(
    Number.MAX_SAFE_INTEGER,
  );
  db.prepare("INSERT INTO Sales(total_amount) VALUES(?)").run(1);
  assert.throws(
    () => require("../src/modules/analytics")(db),
    /supported range/,
  );
});
