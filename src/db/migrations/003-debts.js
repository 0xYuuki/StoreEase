"use strict";

module.exports = (db) => {
  db.exec(`
    CREATE TABLE IF NOT EXISTS Customers(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 200),
      phone TEXT CHECK(phone IS NULL OR length(trim(phone)) <= 50),
      address TEXT CHECK(address IS NULL OR length(trim(address)) <= 255),
      notes TEXT CHECK(notes IS NULL OR length(trim(notes)) <= 500),
      balance INTEGER NOT NULL DEFAULT 0 CHECK(typeof(balance)='integer' AND balance >= 0 AND balance <= 9007199254740991),
      active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS CustomerDebts(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL REFERENCES Customers(id) ON DELETE RESTRICT,
      type TEXT NOT NULL CHECK(type IN ('debt', 'payment')),
      amount INTEGER NOT NULL CHECK(typeof(amount)='integer' AND amount > 0 AND amount <= 9007199254740991),
      balance_after INTEGER NOT NULL CHECK(typeof(balance_after)='integer' AND balance_after >= 0 AND balance_after <= 9007199254740991),
      notes TEXT CHECK(notes IS NULL OR length(trim(notes)) <= 500),
      sale_id INTEGER REFERENCES Sales(id) ON DELETE SET NULL,
      timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS customer_debts_customer ON CustomerDebts(customer_id, id);
    CREATE INDEX IF NOT EXISTS customers_name ON Customers(name);
  `);

  const cols = db.prepare("PRAGMA table_info(Sales)").all().map((c) => c.name);
  if (!cols.includes("payment_type")) {
    db.exec("ALTER TABLE Sales ADD COLUMN payment_type TEXT DEFAULT 'cash' CHECK(payment_type IN ('cash', 'debt'));");
  }
  if (!cols.includes("customer_id")) {
    db.exec("ALTER TABLE Sales ADD COLUMN customer_id INTEGER REFERENCES Customers(id);");
  }

  const custCols = db.prepare("PRAGMA table_info(Customers)").all().map((c) => c.name);
  if (!custCols.includes("active")) {
    db.exec("ALTER TABLE Customers ADD COLUMN active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1));");
  }

  db.exec("PRAGMA user_version=3;");
};
