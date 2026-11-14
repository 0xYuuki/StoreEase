const path = require("node:path");
module.exports = (env = process.env) => {
  const host = env.HOST || "127.0.0.1";
  const port = Number(env.PORT || 3000);
  if (!Number.isInteger(port) || port < 0 || port > 65535)
    throw new Error("PORT must be an integer between 0 and 65535");
  const adminToken = env.ADMIN_TOKEN || undefined;
  const cashierToken = env.CASHIER_TOKEN || undefined;
  for (const token of [adminToken, cashierToken]) {
    if (token && !/^[A-Za-z0-9_-]{32,256}$/.test(token))
      throw new Error(
        "Tokens require 32 to 256 random letters, digits, underscores or hyphens",
      );
  }
  if (cashierToken && (!adminToken || cashierToken === adminToken))
    throw new Error("Cashier token needs a distinct admin token");
  let publicOrigin;
  if (env.PUBLIC_ORIGIN) {
    const url = new URL(env.PUBLIC_ORIGIN);
    if (
      !["http:", "https:"].includes(url.protocol) ||
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      url.pathname !== "/"
    )
      throw new Error(
        "PUBLIC_ORIGIN must be an HTTP(S) origin without credentials or a path",
      );
    publicOrigin = url.origin;
  }
  if (
    host !== "127.0.0.1" &&
    (!adminToken || !publicOrigin?.startsWith("https://"))
  )
    throw new Error(
      "Network binding requires ADMIN_TOKEN and HTTPS PUBLIC_ORIGIN; use an HTTPS reverse proxy",
    );
  const dbPath = path.resolve(
    env.DB_PATH || path.join(__dirname, "../database.sqlite"),
  );
  const publicPath = path.resolve(__dirname, "../public");
  const relative = path.relative(publicPath, dbPath);
  if (
    !relative ||
    (!relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative))
  )
    throw new Error("DB_PATH must be outside public/");
  return { host, port, adminToken, cashierToken, publicOrigin, dbPath };
};
