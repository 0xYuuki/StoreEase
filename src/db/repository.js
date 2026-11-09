"use strict";
module.exports = (db) => ({
  list: () =>
    db.prepare("SELECT * FROM Products WHERE active=1 ORDER BY name").all(),
  barcode: (code) =>
    db
      .prepare("SELECT * FROM Products WHERE barcode_string=? AND active=1")
      .get(code),
  product: (id) =>
    db.prepare("SELECT * FROM Products WHERE id=? AND active=1").get(id),
  create: (p) =>
    Number(
      db
        .prepare(
          "INSERT INTO Products(barcode_string,name,price) VALUES(?,?,?)",
        )
        .run(p.barcode_string, p.name, p.price).lastInsertRowid,
    ),
  update: (id, p) =>
    db
      .prepare(
        "UPDATE Products SET barcode_string=?,name=?,price=? WHERE id=? AND active=1",
      )
      .run(p.barcode_string, p.name, p.price, id),
  deactivate: (id) =>
    db.prepare("UPDATE Products SET active=0 WHERE id=? AND active=1").run(id),
  saleByKey: (key) =>
    db.prepare("SELECT * FROM Sales WHERE idempotency_key=?").get(key),
  receipt: (id) => ({
    success: true,
    sale_id: id,
    total_amount: db
      .prepare("SELECT total_amount FROM Sales WHERE id=?")
      .get(id).total_amount,
    items: db
      .prepare(
        "SELECT product_id,product_name,barcode_string,quantity,price,line_total FROM SaleItems WHERE sale_id=? ORDER BY id",
      )
      .all(id),
  }),
  insertSale: (total, key, hash) =>
    Number(
      db
        .prepare(
          "INSERT INTO Sales(total_amount,idempotency_key,request_hash) VALUES(?,?,?)",
        )
        .run(total, key, hash).lastInsertRowid,
    ),
  insertItem: (sale, p, qty, line) =>
    db
      .prepare(
        "INSERT INTO SaleItems(sale_id,product_id,quantity,price,product_name,barcode_string,line_total) VALUES(?,?,?,?,?,?,?)",
      )
      .run(sale, p.id, qty, p.price, p.name, p.barcode_string, line),
  stock: (id, value, delta, reason) => {
    db.prepare("UPDATE Products SET stock=? WHERE id=?").run(value, id);
    db.prepare(
      "INSERT INTO StockAdjustments(product_id,delta,resulting_stock,reason) VALUES(?,?,?,?)",
    ).run(id, delta, value, reason);
  },
});
