const { ApiError } = require("../utils/validation");
// SQLite sums are read as BigInts so totals cannot be silently rounded by JS.
function safeRows(statement, parameters) {
  statement.setReadBigInts(true);
  return statement.all(...parameters).map((row) =>
    Object.fromEntries(
      Object.entries(row).map(([key, value]) => {
        if (typeof value !== "bigint") return [key, value];
        if (value > BigInt(Number.MAX_SAFE_INTEGER) || value < 0n)
          throw new ApiError(500, "Analytics total exceeds supported range");
        return [key, Number(value)];
      }),
    ),
  );
}
module.exports = (db) => ({
  total(start, end) {
    return safeRows(
      db.prepare(
        "SELECT COALESCE(SUM(total_amount),0) total FROM Sales WHERE julianday(timestamp)>=julianday(?) AND julianday(timestamp)<julianday(?)",
      ),
      [start, end],
    )[0].total;
  },
  chart(start, end) {
    return safeRows(
      db.prepare(
        "SELECT date(timestamp,'+8 hours') sale_date,SUM(total_amount) total FROM Sales WHERE julianday(timestamp)>=julianday(?) AND julianday(timestamp)<julianday(?) GROUP BY sale_date",
      ),
      [start, end],
    );
  },
  popular() {
    return safeRows(
      db.prepare(
        "SELECT product_name name,SUM(quantity) times_sold,SUM(line_total) revenue FROM SaleItems GROUP BY product_id,product_name ORDER BY times_sold DESC,name ASC LIMIT 5",
      ),
      [],
    );
  },
});
