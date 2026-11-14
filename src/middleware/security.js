"use strict";
const { timingSafeEqual } = require("node:crypto");
module.exports = (config) => (req, res, next) => {
  res.set({
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store",
  });
  const expected = config.publicOrigin || `http://${req.headers.host}`;
  if (
    (req.headers.origin && req.headers.origin !== expected) ||
    req.headers["sec-fetch-site"] === "cross-site"
  )
    return res
      .status(403)
      .json({ error: "Origin not allowed", code: "FORBIDDEN" });
  if (
    config.host === "127.0.0.1" &&
    !["127.0.0.1", "localhost", "[::1]"].includes(
      (req.headers.host || "").replace(/:\d+$/, ""),
    )
  )
    return res
      .status(403)
      .json({ error: "Host not allowed", code: "FORBIDDEN" });
  if (!config.adminToken) {
    req.role = "admin";
    return next();
  }
  const auth = req.headers.authorization || "";
  const matches = (token) => {
    const a = Buffer.from(auth),
      b = Buffer.from(`Bearer ${token}`);
    return a.length === b.length && timingSafeEqual(a, b);
  };
  req.role = matches(config.adminToken)
    ? "admin"
    : config.cashierToken && matches(config.cashierToken)
      ? "cashier"
      : null;
  if (!req.role)
    return res
      .status(401)
      .json({ error: "Authentication required", code: "UNAUTHORIZED" });
  next();
};
