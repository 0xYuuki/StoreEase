const fs = require("node:fs");
const { randomUUID } = require("node:crypto");
const { DatabaseSync, backup } = require("node:sqlite");
async function main() {
  const { dbPath } = require("../src/config")();
  if (!fs.existsSync(dbPath)) throw new Error("Database does not exist");
  const destination = `${dbPath}.backup-${Date.now()}-${randomUUID()}.sqlite`;
  const db = new DatabaseSync(dbPath, { readOnly: true });
  try {
    if (db.prepare("PRAGMA integrity_check").get().integrity_check !== "ok")
      throw new Error("Source integrity check failed");
    await backup(db, destination);
    console.log(`Backup created: ${destination}`);
  } finally {
    db.close();
  }
}
main().catch((err) => {
  console.error(err.message);
  process.exitCode = 1;
});
