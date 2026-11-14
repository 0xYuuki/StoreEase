require("./src/server")
  .start()
  .catch((err) => {
    console.error("Startup failed:", err.message);
    process.exitCode = 1;
  });
