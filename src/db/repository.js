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
  sale: (id) => db.prepare(
    "SELECT id, strftime('%Y-%m-%dT%H:%M:%fZ', timestamp) AS timestamp, total_amount FROM Sales WHERE id=?",
  ).get(id),
  sales: (from, until, offset) => db.prepare(`
    SELECT id, strftime('%Y-%m-%dT%H:%M:%fZ', timestamp) AS timestamp, total_amount FROM Sales
    WHERE julianday(Sales.timestamp) >= julianday(?) AND julianday(Sales.timestamp) < julianday(?)
    ORDER BY julianday(Sales.timestamp) DESC, id DESC LIMIT 26 OFFSET ?
  `).all(from, until, offset),
  setReorderLevel: (id, level) => db.prepare(
    "UPDATE Products SET reorder_level=? WHERE id=? AND active=1 AND stock IS NOT NULL",
  ).run(level, id).changes,
  history: (id, offset) => db.prepare(`
    SELECT id, strftime('%Y-%m-%dT%H:%M:%fZ', timestamp) AS timestamp, delta, resulting_stock, reason, sale_id
    FROM StockAdjustments WHERE product_id=? ORDER BY id DESC LIMIT 26 OFFSET ?
  `).all(id, offset),
  hasProduct: (id) => db.prepare("SELECT 1 FROM Products WHERE id=?").get(id),
  receipt: (id) => {
    const sale = db
      .prepare("SELECT total_amount, payment_type, customer_id FROM Sales WHERE id=?")
      .get(id);
    let customerName = null;
    let customerBalance = null;
    let debtAmount = null;
    let cashPaid = null;
    if (sale && sale.customer_id) {
      const c = db.prepare("SELECT name, balance FROM Customers WHERE id=?").get(sale.customer_id);
      if (c) {
        customerName = c.name;
        customerBalance = c.balance;
      }
      const debtRow = db.prepare("SELECT amount FROM CustomerDebts WHERE sale_id=? AND type='debt'").get(id);
      if (debtRow) {
        debtAmount = debtRow.amount;
        cashPaid = Math.max(0, sale.total_amount - debtAmount);
      }
    }
    return {
      success: true,
      sale_id: id,
      total_amount: sale ? sale.total_amount : 0,
      payment_type: sale ? sale.payment_type : "cash",
      customer_id: sale ? sale.customer_id : null,
      customer_name: customerName,
      customer_balance: customerBalance,
      debt_amount: debtAmount,
      cash_paid: cashPaid,
      items: db
        .prepare(
          "SELECT product_id,product_name,barcode_string,quantity,price,line_total FROM SaleItems WHERE sale_id=? ORDER BY id",
        )
        .all(id),
    };
  },
  insertSale: (total, key, hash, paymentType = "cash", customerId = null) =>
    Number(
      db
        .prepare(
          "INSERT INTO Sales(total_amount,idempotency_key,request_hash,payment_type,customer_id) VALUES(?,?,?,?,?)",
        )
        .run(total, key, hash, paymentType, customerId).lastInsertRowid,
    ),
  insertItem: (sale, p, qty, line) =>
    db
      .prepare(
        "INSERT INTO SaleItems(sale_id,product_id,quantity,price,product_name,barcode_string,line_total) VALUES(?,?,?,?,?,?,?)",
      )
      .run(sale, p.id, qty, p.price, p.name, p.barcode_string, line),
  stock: (id, value, delta, reason, sale = null) => {
    db.prepare("UPDATE Products SET stock=? WHERE id=?").run(value, id);
    db.prepare(
      "INSERT INTO StockAdjustments(product_id,delta,resulting_stock,reason,sale_id) VALUES(?,?,?,?,?)",
    ).run(id, delta, value, reason, sale);
  },
  customers: (query) => {
    if (query && query.trim()) {
      const q = `%${query.trim()}%`;
      return db
        .prepare(
          "SELECT *, strftime('%Y-%m-%dT%H:%M:%fZ', updated_at) AS updated_at FROM Customers WHERE active=1 AND (name LIKE ? OR phone LIKE ?) ORDER BY balance DESC, name ASC",
        )
        .all(q, q);
    }
    return db
      .prepare(
        "SELECT *, strftime('%Y-%m-%dT%H:%M:%fZ', updated_at) AS updated_at FROM Customers WHERE active=1 ORDER BY balance DESC, name ASC",
      )
      .all();
  },
  customer: (id) =>
    db
      .prepare(
        "SELECT *, strftime('%Y-%m-%dT%H:%M:%fZ', updated_at) AS updated_at FROM Customers WHERE id=?",
      )
      .get(id),
  customerByName: (name) => {
    if (!name || typeof name !== "string") return null;
    const trimmed = name.trim();
    if (!trimmed) return null;
    return db
      .prepare(
        "SELECT *, strftime('%Y-%m-%dT%H:%M:%fZ', updated_at) AS updated_at FROM Customers WHERE LOWER(TRIM(name)) = LOWER(?) ORDER BY active DESC, id ASC LIMIT 1",
      )
      .get(trimmed);
  },
  reactivateCustomer: (id) =>
    db
      .prepare(
        "UPDATE Customers SET active=1, updated_at=CURRENT_TIMESTAMP WHERE id=?",
      )
      .run(id),
  createCustomer: (c) =>
    Number(
      db
        .prepare(
          "INSERT INTO Customers(name, phone, address, notes, balance) VALUES(?,?,?,?,?)",
        )
        .run(
          c.name,
          c.phone ?? null,
          c.address ?? null,
          c.notes ?? null,
          c.initial_debt || 0,
        ).lastInsertRowid,
    ),
  updateCustomer: (id, c) =>
    db
      .prepare(
        "UPDATE Customers SET name=?, phone=?, address=?, notes=?, updated_at=CURRENT_TIMESTAMP WHERE id=?",
      )
      .run(c.name, c.phone, c.address, c.notes, id),
  deleteCustomer: (id) =>
    db
      .prepare(
        "UPDATE Customers SET active=0, updated_at=CURRENT_TIMESTAMP WHERE id=? AND balance=0",
      )
      .run(id).changes,
  updateCustomerBalance: (id, balance) =>
    db
      .prepare(
        "UPDATE Customers SET balance=?, updated_at=CURRENT_TIMESTAMP WHERE id=?",
      )
      .run(balance, id),
  insertCustomerDebt: (customerId, type, amount, balanceAfter, notes, saleId = null) =>
    Number(
      db
        .prepare(
          "INSERT INTO CustomerDebts(customer_id, type, amount, balance_after, notes, sale_id) VALUES(?,?,?,?,?,?)",
        )
        .run(customerId, type, amount, balanceAfter, notes, saleId).lastInsertRowid,
    ),
  customerTransactions: (customerId, limit = 50, offset = 0) =>
    db
      .prepare(
        "SELECT id, customer_id, type, amount, balance_after, notes, sale_id, strftime('%Y-%m-%dT%H:%M:%fZ', timestamp) AS timestamp FROM CustomerDebts WHERE customer_id=? ORDER BY id DESC LIMIT ? OFFSET ?",
      )
      .all(customerId, limit, offset),
  debtsSummary: () =>
    db
      .prepare(
        "SELECT COALESCE(SUM(balance), 0) AS total_debt, COUNT(CASE WHEN balance > 0 THEN 1 END) AS active_debtors, COUNT(*) AS total_customers FROM Customers WHERE active=1",
      )
      .get(),
});
