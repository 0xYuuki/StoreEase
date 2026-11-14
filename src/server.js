"use strict";
const { openDatabase } = require("./db/connection");
async function start() {
  const config = require("./config")();
  const db = await openDatabase(config.dbPath);
  let server;
  try {
    server = require("./app")
      .createApp(db, config)
      .listen(config.port, config.host);
    await new Promise((resolve, reject) => {
      server.once("listening", resolve);
      server.once("error", reject);
    });
  } catch (err) {
    db.close();
    throw err;
  }
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  console.log("StoreEase: http://" + config.host + ":" + server.address().port);
  let closing = false;
  const stop = () => {
    if (closing) return;
    closing = true;
    server.close(() => db.close());
    server.closeIdleConnections();
  };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);
  return { server, db, stop };
}
module.exports = { start };
