"use strict";
const { transaction } = require("../connection");
module.exports = (db) =>
  transaction(db, () => {
    const existing = db
      .prepare("SELECT 1 FROM sqlite_master WHERE name='Products'")
      .get();
    const sequences = existing
      ? db.prepare("SELECT name,seq FROM sqlite_sequence").all()
      : [];
    if (existing) {
      if (
        db.prepare("PRAGMA integrity_check").get().integrity_check !== "ok" ||
        db.prepare("PRAGMA foreign_key_check").all().length
      )
        throw new Error(
          "Legacy integrity errors; restore/repair a copy before migration",
        );
      for (const row of db.prepare("SELECT * FROM Products").all()) {
        const v = require("../../utils/validation");
      v.integer(row.id, 'legacy product ID');
        if (
          v.text(row.name, "name", 200) !== row.name ||
          v.text(row.barcode_string, "barcode", 128) !== row.barcode_string
        )
          throw new Error("Legacy whitespace needs explicit repair");
        v.integer(row.price, "legacy price", 0);
      }
      const invalid = db
        .prepare(
          `SELECT id FROM Sales WHERE typeof(total_amount)!='integer' OR total_amount<0 OR total_amount>9007199254740991 OR julianday(timestamp) IS NULL`,
        )
        .get();
      const badItem = db
        .prepare(
          `SELECT id FROM SaleItems WHERE typeof(quantity)!='integer' OR quantity<1 OR quantity>9007199254740991 OR typeof(price)!='integer' OR price<0 OR price>9007199254740991 OR quantity*price>9007199254740991`,
        )
        .get();
      if (invalid || badItem)
        throw new Error("Malformed legacy financial data; no rows changed");
      const mismatches = db
        .prepare(
          "SELECT s.id FROM Sales s LEFT JOIN SaleItems i ON i.sale_id=s.id GROUP BY s.id HAVING COUNT(i.id)=0 OR s.total_amount!=SUM(i.price*i.quantity)",
        )
        .all();
      if (mismatches.length)
        console.warn(
          "Legacy totals preserved without recalculation; review sale IDs:",
          mismatches.map((r) => r.id),
        );
      db.exec(
        "ALTER TABLE SaleItems RENAME TO LegacySaleItems; ALTER TABLE Sales RENAME TO LegacySales; ALTER TABLE Products RENAME TO LegacyProducts;",
      );
    }
    db.exec(`
    CREATE TABLE Products(id INTEGER PRIMARY KEY AUTOINCREMENT, barcode_string TEXT NOT NULL UNIQUE CHECK(length(trim(barcode_string)) BETWEEN 1 AND 128), name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 200), price INTEGER NOT NULL CHECK(typeof(price)='integer' AND price BETWEEN 0 AND 9007199254740991), active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)), stock INTEGER CHECK(stock IS NULL OR (typeof(stock)='integer' AND stock BETWEEN 0 AND 9007199254740991)));
    CREATE TABLE Sales(id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK(julianday(timestamp) IS NOT NULL), total_amount INTEGER NOT NULL CHECK(typeof(total_amount)='integer' AND total_amount BETWEEN 0 AND 9007199254740991), idempotency_key TEXT UNIQUE, request_hash TEXT);
    CREATE TABLE SaleItems(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL REFERENCES Sales(id) ON DELETE RESTRICT, product_id INTEGER REFERENCES Products(id) ON DELETE RESTRICT, quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity BETWEEN 1 AND 9007199254740991), price INTEGER NOT NULL CHECK(typeof(price)='integer' AND price BETWEEN 0 AND 9007199254740991), product_name TEXT NOT NULL, barcode_string TEXT NOT NULL, line_total INTEGER NOT NULL CHECK(typeof(line_total)='integer' AND line_total BETWEEN 0 AND 9007199254740991 AND line_total=price*quantity), snapshot_source TEXT NOT NULL DEFAULT 'checkout');
    CREATE TABLE StockAdjustments(id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES Products(id), delta INTEGER NOT NULL, resulting_stock INTEGER NOT NULL CHECK(resulting_stock>=0), reason TEXT NOT NULL, timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE INDEX sales_timestamp ON Sales(timestamp);
    CREATE INDEX items_sale ON SaleItems(sale_id);
    CREATE INDEX items_product ON SaleItems(product_id);
  `);
    if (existing) {
      db.exec(`
    INSERT INTO Products(id,barcode_string,name,price) SELECT id,barcode_string,name,price FROM LegacyProducts;
    INSERT INTO Sales(id,timestamp,total_amount) SELECT id,timestamp,total_amount FROM LegacySales;
    INSERT INTO SaleItems(id,sale_id,product_id,quantity,price,product_name,barcode_string,line_total,snapshot_source) SELECT i.id,i.sale_id,i.product_id,i.quantity,i.price,p.name,p.barcode_string,i.quantity*i.price,'legacy-current-product' FROM LegacySaleItems i JOIN Products p ON p.id=i.product_id;
  `);
      for (const [table, columns] of [
        ["Products", "id,barcode_string,name,price"],
        ["Sales", "id,timestamp,total_amount"],
        ["SaleItems", "id,sale_id,product_id,quantity,price"],
      ]) {
        const oldTable =
          table === "SaleItems" ? "LegacySaleItems" : `Legacy${table}`;
        const before = db
          .prepare(`SELECT ${columns} FROM ${oldTable} ORDER BY id`)
          .all();
        const after = db
          .prepare(`SELECT ${columns} FROM ${table} ORDER BY id`)
          .all();
        if (JSON.stringify(before) !== JSON.stringify(after))
          throw new Error(`Migration changed legacy ${table}; rolled back`);
      }
      db.exec(
        "DROP TABLE LegacySaleItems; DROP TABLE LegacySales; DROP TABLE LegacyProducts;",
      );
      for (const row of sequences) {
        if (!["Products", "Sales", "SaleItems"].includes(row.name)) continue;
        const current = db
          .prepare("SELECT seq FROM sqlite_sequence WHERE name=?")
          .get(row.name);
        if (current)
          db.prepare(
            "UPDATE sqlite_sequence SET seq=MAX(seq,?) WHERE name=?",
          ).run(row.seq, row.name);
        else
          db.prepare("INSERT INTO sqlite_sequence(name,seq) VALUES(?,?)").run(
            row.name,
            row.seq,
          );
      }
    }
    if (db.prepare("PRAGMA foreign_key_check").all().length)
      throw new Error("Migration foreign key verification failed");
    db.exec("PRAGMA user_version=1");
  });
