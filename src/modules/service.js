"use strict";
const { createHash } = require("node:crypto");
const v = require("../utils/validation");
const { transaction } = require("../db/connection");
module.exports = (db) => {
  const repo = require("../db/repository")(db);
  const find = (id) => {
    const p = repo.product(id);
    if (!p) throw new v.ApiError(404, "Product not found");
    return p;
  };
  return {
    list: repo.list,
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
        if (
          body.tendered_amount !== undefined &&
          v.integer(body.tendered_amount, "tendered_amount", 0) < total
        )
          throw new v.ApiError(
            409,
            "Prices changed or payment is insufficient. Review the cart and tendered amount.",
          );
        const sale = repo.insertSale(total, key, hash);
        for (const { p, quantity, line } of lines) {
          repo.insertItem(sale, p, quantity, line);
          if (p.stock !== null)
            repo.stock(p.id, p.stock - quantity, -quantity, `Sale ${sale}`);
        }
        return repo.receipt(sale);
      });
    },
  };
};
