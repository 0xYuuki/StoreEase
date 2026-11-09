module.exports = (err, req, res, next) => {
  const constraint = String(err.message).includes("UNIQUE constraint");
  const busy = String(err.message).includes("database is locked");
  const status = err.status || (constraint ? 409 : busy ? 503 : 500);
  if (status >= 500) console.error("Request failed:", err.code || err.message);
  let message = err.message;
  if (status >= 500)
    message = busy
      ? "Database busy; retry with the same key"
      : "Internal server error";
  else if (err.type === "entity.parse.failed") message = "Invalid JSON body";
  else if (constraint) message = "Barcode already exists";
  res
    .status(status)
    .json({
      error: message,
      code:
        err.publicCode ||
        (status === 400
          ? "INVALID_INPUT"
          : status === 409
            ? "CONFLICT"
            : `HTTP_${status}`),
    });
};
