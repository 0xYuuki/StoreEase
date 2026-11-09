"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path");
const { DatabaseSync } = require("node:sqlite");
const { openDatabase } = require("../src/db/connection");
function legacy(t, invalid = false) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "storeease-migrate-")),
    filename = path.join(dir, "legacy.sqlite");
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const db = new DatabaseSync(filename);
  db.exec(`CREATE TABLE Products(id INTEGER PRIMARY KEY AUTOINCREMENT,barcode_string TEXT UNIQUE NOT NULL,name TEXT NOT NULL,price INTEGER NOT NULL);
    CREATE TABLE Sales(id INTEGER PRIMARY KEY AUTOINCREMENT,timestamp TEXT DEFAULT CURRENT_TIMESTAMP,total_amount INTEGER NOT NULL);
    CREATE TABLE SaleItems(id INTEGER PRIMARY KEY AUTOINCREMENT,sale_id INTEGER NOT NULL REFERENCES Sales(id),product_id INTEGER NOT NULL REFERENCES Products(id) ON DELETE SET NULL,quantity INTEGER NOT NULL,price INTEGER NOT NULL);
    INSERT INTO Products VALUES(1,'000123','Old name',123);
    INSERT INTO Sales VALUES(1,'2026-01-01 15:59:59',999);
    INSERT INTO SaleItems VALUES(1,1,1,2,100);`);
  if (invalid) db.exec("UPDATE Products SET price=-1");
  db.close();
  return { dir, filename };
}
test("legacy migration backs up, preserves exact money, flags mismatch, and is repeatable", async (t) => {
  const { dir, filename } = legacy(t);
  let db = await openDatabase(filename);
  assert.equal(
    db.prepare("SELECT total_amount FROM Sales").get().total_amount,
    999,
  );
  assert.equal(db.prepare("SELECT price FROM SaleItems").get().price, 100);
  assert.equal(
    db.prepare("SELECT line_total FROM SaleItems").get().line_total,
    200,
  );
  assert.equal(
    db.prepare("SELECT snapshot_source FROM SaleItems").get().snapshot_source,
    "legacy-current-product",
  );
  assert.equal(db.prepare("PRAGMA user_version").get().user_version, 1);
  assert.deepEqual(db.prepare("PRAGMA foreign_key_check").all(), []);
  db.close();
  const backups = fs.readdirSync(dir).filter((x) => x.includes(".backup-"));
  assert.equal(backups.length, 1);
  const original = new DatabaseSync(path.join(dir, backups[0]), {
    readOnly: true,
  });
  assert.equal(original.prepare("PRAGMA user_version").get().user_version, 0);
  assert.equal(
    original.prepare("SELECT total_amount FROM Sales").get().total_amount,
    999,
  );
  original.close();
  db = await openDatabase(filename);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM Sales").get().n, 1);
  db.close();
  assert.equal(
    fs.readdirSync(dir).filter((x) => x.includes(".backup-")).length,
    1,
  );
});
test("malformed legacy data aborts without dropping or repairing rows", async (t) => {
  const { filename } = legacy(t, true);
  await assert.rejects(openDatabase(filename), /legacy price/);
  const db = new DatabaseSync(filename, { readOnly: true });
  assert.equal(db.prepare("SELECT price FROM Products").get().price, -1);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM SaleItems").get().n, 1);
  assert.equal(db.prepare("PRAGMA user_version").get().user_version, 0);
  db.close();
});
test("orphaned legacy records are reported and retained", async (t) => {
  const { filename } = legacy(t);
  const db = new DatabaseSync(filename);
  db.exec("PRAGMA foreign_keys=OFF; UPDATE SaleItems SET product_id=99");
  db.close();
  await assert.rejects(openDatabase(filename), /integrity errors/);
  const check = new DatabaseSync(filename, { readOnly: true });
  assert.equal(
    check.prepare("SELECT product_id FROM SaleItems").get().product_id,
    99,
  );
  check.close();
});

test("migration retains AUTOINCREMENT high water marks of deleted rows", async (t) => {
  const { filename } = legacy(t);
  const old = new DatabaseSync(filename);
  old.exec(
    "INSERT INTO Products VALUES(999,'deleted','Deleted product',10); DELETE FROM Products WHERE id=999",
  );
  old.close();
  const db = await openDatabase(filename);
  const result = db
    .prepare(
      "INSERT INTO Products(barcode_string,name,price) VALUES('new','New',10)",
    )
    .run();
  assert.equal(Number(result.lastInsertRowid), 1000);
  db.close();
});
