// Creates a fresh development database; never removes an existing file.
const fs = require("node:fs"),
  path = require("node:path"),
  filename = process.env.DB_PATH;
if (
  process.env.NODE_ENV !== "development" ||
  process.env.CONFIRM_RESET !== "CREATE_EMPTY_DEV_DATABASE" ||
  !filename ||
  !path.basename(filename).endsWith(".dev.sqlite") ||
  fs.existsSync(filename)
) {
  console.error(
    "Requires NODE_ENV=development, CONFIRM_RESET=CREATE_EMPTY_DEV_DATABASE and nonexistent DB_PATH ending .dev.sqlite",
  );
  process.exitCode = 1;
} else {
  // Reserve a new filename atomically so a second process cannot replace it.
  fs.closeSync(fs.openSync(filename, "wx"));
  require("./migrate");
}
