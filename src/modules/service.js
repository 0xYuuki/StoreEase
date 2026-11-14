"use strict";
const { createHash } = require("node:crypto");
const v = require("../utils/validation");
const { transaction } = require("../db/connection");
function manilaMidnight(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value))
    v.fail("Use a date in YYYY-MM-DD format");
  const date = new Date(value + "T00:00:00Z");
  if (!Number.isFinite(+date) || date.toISOString().slice(0, 10) !== value)
    v.fail("Invalid calendar date");
  return +date - 8 * 3600000;
}
function pageOf(rows) {
  return { entries: rows.slice(0, 25), has_more: rows.length > 25 };
}
function pageOffset(page = "1") {
  const offset = (v.id(page) - 1) * 25;
  return v.integer(offset, "page offset", 0);
}
module.exports = (db) => {
  const repo = require("../db/repository")(db);
  const find = (id) => {
    const p = repo.product(id);
    if (!p) throw new v.ApiError(404, "Product not found");
    return p;
  };
  return {
    list: repo.list,
    sales({ from, to, page }) {
      const start = manilaMidnight(from);
      const end = manilaMidnight(to);
      if (end < start) v.fail("End date must follow start date");
      return pageOf(repo.sales(
        new Date(start).toISOString(),
        new Date(end + 86400000).toISOString(),
        pageOffset(page),
      ));
    },
    receipt(raw) {
      const id = v.id(raw);
      const sale = repo.sale(id);
      if (!sale) throw new v.ApiError(404, "Receipt not found");
      return { ...repo.receipt(id), timestamp: sale.timestamp };
    },
    reorder(raw, body) {
      const id = v.id(raw);
      find(id);
      const level = body.reorder_level === null ? null :
        v.integer(body.reorder_level, "reorder level", 0);
      if (!repo.setReorderLevel(id, level))
        throw new v.ApiError(409, "Enable stock tracking first");
      return find(id);
    },
    stockHistory(raw, page) {
      const id = v.id(raw);
      if (!repo.hasProduct(id)) throw new v.ApiError(404, "Product not found");
      return pageOf(repo.history(id, pageOffset(page)));
    },
    lookup(code) {
      const p = repo.barcode(v.text(code, "barcode", 128));
      if (!p) throw new v.ApiError(404, "Item not found");
      return p;
    },
    create(body) {
      const p = v.product(body);
      return { id: repo.create(p), ...p, stock: null, active: 1 };
    },
    update(raw, body) {
      const id = v.id(raw);
      find(id);
      repo.update(id, v.product(body));
      return find(id);
    },
    deactivate(raw) {
      const id = v.id(raw);
      find(id);
      repo.deactivate(id);
      return { success: true };
    },
    adjust(raw, body) {
      return transaction(db, () => {
        const p = find(v.id(raw)),
          delta = v.integer(body.delta, "delta", -Number.MAX_SAFE_INTEGER),
          reason = v.text(body.reason, "reason", 300);
        const value = v.integer((p.stock ?? 0) + delta, "resulting stock", 0);
        repo.stock(p.id, value, delta, reason);
        return find(p.id);
      });
    },
    checkout(body, key) {
      key = v.text(key, "Idempotency-Key (required)", 128);
      if (
        !Array.isArray(body.items) ||
        !body.items.length ||
        body.items.length > 500
      )
        v.fail("Cart must contain 1 to 500 lines");
      const quantities = new Map();
      for (const item of body.items) {
        if (!item || typeof item !== "object") v.fail("Invalid item");
        const id = v.id(item.product_id),
          qty = v.integer(item.quantity, "quantity");
        quantities.set(
          id,
          v.integer((quantities.get(id) || 0) + qty, "quantity"),
        );
      }
      const items = [...quantities].sort((a, b) => a[0] - b[0]);
      const hash = createHash("sha256")
        .update(JSON.stringify(items))
        .digest("hex");
      return transaction(db, () => {
        const prior = repo.saleByKey(key);
        if (prior) {
          if (prior.request_hash !== hash)
            throw new v.ApiError(
              409,
              "Idempotency key used for another cart",
              "IDEMPOTENCY_CONFLICT",
            );
          return repo.receipt(prior.id);
        }
        let total = 0;
        const lines = items.map(([id, quantity]) => {
          const p = find(id),
            line = v.integer(p.price * quantity, "line total", 0);
          total = v.integer(total + line, "total", 0);
          if (p.stock !== null && quantity > p.stock)
            throw new v.ApiError(409, `Insufficient stock: ${p.name}`);
          return { p, quantity, line };
        });
        const isDebt =
          body.payment_type === "debt" ||
          Boolean(body.customer_id) ||
          (typeof body.customer_name === "string" && body.customer_name.trim().length > 0);
        let debtor = null;
        let debtAmount = 0;
        let cashTendered = 0;
        if (isDebt) {
          if (body.customer_id) {
            debtor = repo.customer(v.id(body.customer_id));
            if (!debtor) throw new v.ApiError(404, "Customer not found for debt checkout");
          } else if (typeof body.customer_name === "string" && body.customer_name.trim()) {
            const trimmed = body.customer_name.trim();
            let existing = repo.customerByName(trimmed);
            if (existing) {
              if (!existing.active) {
                repo.reactivateCustomer(existing.id);
                existing = repo.customer(existing.id);
              }
              debtor = existing;
            } else {
              const newId = repo.createCustomer({ name: trimmed });
              debtor = repo.customer(newId);
            }
          } else {
            throw new v.ApiError(400, "Customer is required for debt checkout");
          }

          if (
            body.tendered_amount !== undefined &&
            body.tendered_amount !== null &&
            body.tendered_amount !== ""
          ) {
            const tVal = v.integer(body.tendered_amount, "tendered_amount", 0);
            cashTendered = Math.min(tVal, total);
          }
          debtAmount = v.integer(total - cashTendered, "debt amount", 0);
        } else if (
          body.tendered_amount !== undefined &&
          v.integer(body.tendered_amount, "tendered_amount", 0) < total
        ) {
          throw new v.ApiError(
            409,
            "Prices changed or payment is insufficient. Review the cart and tendered amount.",
          );
        }
        const sale = repo.insertSale(
          total,
          key,
          hash,
          isDebt ? "debt" : "cash",
          debtor ? debtor.id : null,
        );
        for (const { p, quantity, line } of lines) {
          repo.insertItem(sale, p, quantity, line);
          if (p.stock !== null)
            repo.stock(p.id, p.stock - quantity, -quantity, `Sale ${sale}`, sale);
        }
        if (debtor && debtAmount > 0) {
          const newBalance = v.integer(debtor.balance + debtAmount, "customer balance", 0);
          repo.updateCustomerBalance(debtor.id, newBalance);
          const note =
            cashTendered > 0
              ? `POS Sale #${sale} (Short: ₱${(debtAmount / 100).toFixed(2)}, Paid: ₱${(cashTendered / 100).toFixed(2)})`
              : `POS Sale #${sale}`;
          repo.insertCustomerDebt(debtor.id, "debt", debtAmount, newBalance, note, sale);
        }
        return repo.receipt(sale);
      });
    },
    debtsSummary() {
      return repo.debtsSummary();
    },
    customers(query) {
      const q = query && query.q ? String(query.q) : undefined;
      return repo.customers(q);
    },
    customer(rawId) {
      const id = v.id(rawId);
      const c = repo.customer(id);
      if (!c) throw new v.ApiError(404, "Customer not found");
      return c;
    },
    createCustomer(body) {
      const c = v.customer(body);
      return transaction(db, () => {
        const id = repo.createCustomer(c);
        if (c.initial_debt > 0) {
          repo.insertCustomerDebt(
            id,
            "debt",
            c.initial_debt,
            c.initial_debt,
            "Initial debt balance",
          );
        }
        return repo.customer(id);
      });
    },
    updateCustomer(rawId, body) {
      const id = v.id(rawId);
      const c = v.customer(body);
      return transaction(db, () => {
        const existing = repo.customer(id);
        if (!existing) throw new v.ApiError(404, "Customer not found");
        repo.updateCustomer(id, c);
        return repo.customer(id);
      });
    },
    deleteCustomer(rawId) {
      const id = v.id(rawId);
      return transaction(db, () => {
        const existing = repo.customer(id);
        if (!existing) throw new v.ApiError(404, "Customer not found");
        if (existing.balance > 0) {
          throw new v.ApiError(400, "Cannot delete customer with active debt balance");
        }
        repo.deleteCustomer(id);
        return { success: true };
      });
    },
    customerTransactions(rawId, query = {}) {
      const id = v.id(rawId);
      const existing = repo.customer(id);
      if (!existing) throw new v.ApiError(404, "Customer not found");
      const page = query.page ? v.integer(Number(query.page), "page", 1) : 1;
      const limit = 25;
      const offset = (page - 1) * limit;
      const entries = repo.customerTransactions(id, limit + 1, offset);
      return {
        customer: existing,
        entries: entries.slice(0, limit),
        has_more: entries.length > limit,
        page,
      };
    },
    addDebt(rawId, body) {
      const id = v.id(rawId);
      const amount = v.money(body.amount);
      if (amount <= 0) throw new v.ApiError(400, "Debt amount must be positive");
      const notes = v.optionalText(body.notes, "notes", 500) || "Manual debt added";
      return transaction(db, () => {
        const c = repo.customer(id);
        if (!c) throw new v.ApiError(404, "Customer not found");
        const newBalance = v.integer(c.balance + amount, "customer balance", 0);
        repo.updateCustomerBalance(id, newBalance);
        repo.insertCustomerDebt(id, "debt", amount, newBalance, notes);
        return repo.customer(id);
      });
    },
    recordPayment(rawId, body) {
      const id = v.id(rawId);
      const amount = v.money(body.amount);
      if (amount <= 0) throw new v.ApiError(400, "Payment amount must be positive");
      const notes = v.optionalText(body.notes, "notes", 500) || "Debt payment";
      return transaction(db, () => {
        const c = repo.customer(id);
        if (!c) throw new v.ApiError(404, "Customer not found");
        if (amount > c.balance) {
          throw new v.ApiError(
            400,
            `Payment amount cannot exceed outstanding debt of ₱${(c.balance / 100).toFixed(2)}`,
          );
        }
        const newBalance = v.integer(c.balance - amount, "customer balance", 0);
        repo.updateCustomerBalance(id, newBalance);
        repo.insertCustomerDebt(id, "payment", amount, newBalance, notes);
        return repo.customer(id);
      });
    },
  };
};
