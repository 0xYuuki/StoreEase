"use strict";
const { DatabaseSync, backup } = require("node:sqlite");
const fs = require("node:fs");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
async function openDatabase(filename) {
  if (filename !== ":memory:")
    fs.mkdirSync(path.dirname(path.resolve(filename)), { recursive: true });
  const db = new DatabaseSync(filename);
  try {
    db.exec("PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;");
    const version = db.prepare("PRAGMA user_version").get().user_version;
    if (version > 1)
      throw new Error("Database schema newer than this application");
    if (!version) {
      if (
        db.prepare("SELECT 1 FROM sqlite_master WHERE name='Products'").get() &&
        filename !== ":memory:"
      ) {
        const destination = `${filename}.backup-${Date.now()}-${randomUUID()}.sqlite`;
        await backup(db, destination);
        console.log(`Pre-migration backup: ${destination}`);
      }
      require("./migrations/001-reliability")(db);
    }
    if (
      db.prepare("PRAGMA integrity_check").get().integrity_check !== "ok" ||
      db.prepare("PRAGMA foreign_key_check").all().length
    )
      throw new Error("Database integrity check failed");
    db.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;");
    return db;
  } catch (err) {
    db.close();
    throw err;
  }
}
// Synchronous transaction bodies cannot yield between BEGIN and COMMIT. All requests
// on this connection execute atomically; separate processes serialize through SQLite.
function transaction(db, work) {
  db.exec("BEGIN IMMEDIATE");
  try {
    const result = work();
    db.exec("COMMIT");
    return result;
  } catch (err) {
    try {
      db.exec("ROLLBACK");
    } catch (rollback) {
      console.error(
        "Rollback failed; closing unsafe connection",
        rollback.code,
      );
      try {
        db.close();
      } catch {
        /* The connection may already be closed. */
      }
    }
    throw err;
  }
}
module.exports = { openDatabase, transaction };
