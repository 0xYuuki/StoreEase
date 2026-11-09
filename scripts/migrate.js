async function migrate() {
  const { dbPath } = require("../src/config")();
  const db = await require("../src/db/connection").openDatabase(dbPath);
  db.close();
  console.log("Schema up to date");
}
migrate().catch((err) => {
  console.error(err.message);
  process.exitCode = 1;
});
