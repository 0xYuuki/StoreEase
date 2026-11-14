"use strict";
class ApiError extends Error {
  constructor(status, message, publicCode) {
    super(message);
    this.status = status;
    this.publicCode = publicCode;
  }
}
const fail = (message) => {
  throw new ApiError(400, message);
};
function integer(value, label, min = 1) {
  if (!Number.isSafeInteger(value) || value < min)
    fail(`${label} must be a safe integer >= ${min}`);
  return value;
}
function id(value) {
  if (!['string', 'number'].includes(typeof value)) fail('Invalid product ID');
  if (!/^[1-9]\d*$/.test(String(value))) fail("Invalid product ID");
  return integer(Number(value), "ID");
}
function text(value, label, max) {
  if (
    typeof value !== "string" ||
    !value.trim() ||
    value.trim().length > max ||
    /[\x00-\x1f\x7f]/.test(value)
  )
    fail(`Invalid ${label}`);
  return value.trim();
}
function money(value) {
  if (
    !["string", "number"].includes(typeof value) ||
    !/^\d+(\.\d{1,2})?$/.test(String(value))
  )
    fail("Price must be nonnegative pesos with at most two decimals");
  const [whole, fraction = ""] = String(value).split(".");
  const cents = BigInt(whole) * 100n + BigInt(fraction.padEnd(2, "0"));
  if (cents > BigInt(Number.MAX_SAFE_INTEGER)) fail("Price too large");
  return Number(cents);
}
function product(body) {
  return {
    barcode_string: text(body.barcode_string, "barcode", 128),
    name: text(body.name, "name", 200),
    price: money(body.price),
  };
}
module.exports = { ApiError, fail, integer, id, text, money, product };
