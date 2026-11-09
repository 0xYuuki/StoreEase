"use strict";
const express = require("express");
const path = require("node:path");
function createApp(db, config = { host: "127.0.0.1" }) {
  const app = express();
  app.disable("x-powered-by");
  app.use((req, res, next) => {
    res.set({
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Referrer-Policy": "no-referrer",
      "Content-Security-Policy":
        "default-src 'self'; script-src 'self' https://cdn.jsdelivr.net https://unpkg.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
    });
    next();
  });
  app.use(
    "/api",
    require("./middleware/security")(config),
    express.json({ limit: "64kb" }),
  );
  app.use("/api", require("./modules/routes")(db));
  app.use(
    express.static(path.join(__dirname, "../public"), { dotfiles: "deny" }),
  );
  app.use((req, res) =>
    res.status(404).json({ error: "Not found", code: "NOT_FOUND" }),
  );
  app.use(require("./middleware/errorHandler"));
  return app;
}
module.exports = { createApp };
