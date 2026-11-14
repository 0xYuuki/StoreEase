"use strict";

const historyElement = (id) => document.getElementById(id);
const salesFilters = historyElement("sales-filters");
const historicalReceipt = historyElement("historical-receipt");
const stockPanel = historyElement("stock-history-panel");
const salesDateFormat = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Asia/Manila", year: "numeric", month: "2-digit", day: "2-digit",
});
const manilaDateTime = new Intl.DateTimeFormat("en-PH", {
  timeZone: "Asia/Manila", dateStyle: "medium", timeStyle: "short",
});
let salesPage = 1;
let salesRequest = 0;
let receiptRequest = 0;
let movementRequest = 0;
let movementPage = 1;
let historyProductId;

async function historyJson(url, options) {
  const response = await apiFetch(url, options);
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || "Request failed");
  return body;
}

async function browseSales(page = 1) {
  const request = ++salesRequest;
  const status = historyElement("sales-status");
  const results = historyElement("sales-results");
  const pagination = historyElement("sales-pagination");
  pagination.hidden = true;
  results.innerHTML = "";
  status.textContent = "Loading sales…";
  const filters = new URLSearchParams(new FormData(salesFilters));
  filters.set("page", page);
  try {
    const data = await historyJson("/api/sales?" + filters);
    if (request !== salesRequest) return;
    salesPage = page;
    status.textContent = data.entries.length ? "" : "No sales in this date range.";
    results.innerHTML = data.entries.map((sale) => `
      <li>
        <button type="button" class="nav-tab" data-receipt="${sale.id}">Receipt #${sale.id}</button>
        <span>${manilaDateTime.format(new Date(sale.timestamp))}</span>
        <strong>${formatCurrency(sale.total_amount)}</strong>
      </li>`).join("");
    pagination.hidden = page === 1 && !data.has_more;
    historyElement("sales-page").textContent = "Page " + page;
    historyElement("sales-prev").disabled = page === 1;
    historyElement("sales-next").disabled = !data.has_more;
  } catch (error) {
    if (request === salesRequest) status.textContent = error.message;
  }
}

async function showHistoricalReceipt(id) {
  const request = ++receiptRequest;
  const status = historyElement("receipt-status");
  historicalReceipt.hidden = true;
  status.textContent = "Loading receipt…";
  try {
    const receipt = await historyJson("/api/sales/" + encodeURIComponent(id));
    if (request !== receiptRequest) return;
    const title = historyElement("historical-receipt-title");
    title.textContent = "Receipt #" + receipt.sale_id;
    historyElement("historical-receipt-date").textContent =
      manilaDateTime.format(new Date(receipt.timestamp)) + " (Manila)";
    historyElement("historical-receipt-items").innerHTML = receipt.items.map((item) => `
      <li>
        <span>${escapeHTML(item.product_name)}</span>
        <span>${item.quantity} × ${formatCurrency(item.price)}</span>
        <strong>${formatCurrency(item.line_total)}</strong>
      </li>`).join("");
    historyElement("historical-receipt-total").textContent =
      "Total " + formatCurrency(receipt.total_amount);
    historicalReceipt.hidden = false;
    status.textContent = "";
    if (!historyElement("sales-view").classList.contains("hidden")) title.focus();
  } catch (error) {
    if (request === receiptRequest) status.textContent = error.message;
  }
}

historyElement("nav-sales").addEventListener("click", () => {
  showStoreView("sales");
  if (currentRole === "admin") browseSales();
});
const today = Object.fromEntries(salesDateFormat.formatToParts(new Date())
  .map(({ type, value }) => [type, value]));
salesFilters.elements.from.value = salesFilters.elements.to.value =
  `${today.year}-${today.month}-${today.day}`;
salesFilters.addEventListener("submit", (event) => {
  event.preventDefault();
  browseSales();
});
historyElement("receipt-search").addEventListener("submit", (event) => {
  event.preventDefault();
  showHistoricalReceipt(event.currentTarget.elements.receipt.value);
});
historyElement("sales-results").addEventListener("click", (event) => {
  const button = event.target.closest("[data-receipt]");
  if (button) showHistoricalReceipt(button.dataset.receipt);
});
historyElement("sales-prev").addEventListener("click", () => browseSales(salesPage - 1));
historyElement("sales-next").addEventListener("click", () => browseSales(salesPage + 1));
historyElement("print-historical-receipt").addEventListener("click", () => {
  document.body.classList.add("printing-receipt");
  window.print();
});
window.addEventListener("afterprint", () => document.body.classList.remove("printing-receipt"));

async function editReorderLevel(id) {
  const product = inventoryProducts.find((item) => item.id === id);
  const input = prompt("Enter a nonnegative reorder level, or leave blank to turn it off.", product.reorder_level ?? "");
  if (input === null) return;
  const value = input.trim();
  const level = value === "" ? null : Number(value);
  if (value !== "" && (!/^\d+$/.test(value) || !Number.isSafeInteger(level))) {
    alert("Enter a nonnegative whole number.");
    return;
  }
  try {
    await historyJson(`/api/products/${id}/reorder-level`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ reorder_level: level }),
    });
    await loadInventory();
  } catch (error) {
    alert(error.message);
  }
}

async function openStockHistory(id, page = 1) {
  const request = ++movementRequest;
  const title = historyElement("stock-history-title");
  const status = historyElement("stock-history-status");
  const list = historyElement("stock-movements");
  const more = historyElement("stock-more");
  historyProductId = id;
  if (page === 1) {
    list.innerHTML = "";
    title.textContent = "Stock history · " + inventoryProducts.find((item) => item.id === id).name;
    stockPanel.hidden = false;
    title.focus();
  }
  more.hidden = true;
  status.textContent = "Loading movements…";
  try {
    const data = await historyJson(`/api/products/${id}/stock-history?page=${page}`);
    if (request !== movementRequest) return;
    list.insertAdjacentHTML("beforeend", data.entries.map((move) => `
      <li>
        <span>${manilaDateTime.format(new Date(move.timestamp))}</span>
        <strong>${move.delta > 0 ? "+" : ""}${move.delta} → ${move.resulting_stock} remaining</strong>
        <span>${escapeHTML(move.reason)}</span>
        ${move.sale_id === null ? "" : `<button type="button" class="nav-tab" data-receipt="${move.sale_id}">Receipt #${move.sale_id}</button>`}
      </li>`).join(""));
    movementPage = page;
    more.hidden = !data.has_more;
    status.textContent = data.entries.length ? "" : "No recorded movements.";
  } catch (error) {
    if (request !== movementRequest) return;
    status.textContent = error.message;
    more.hidden = page === 1;
  }
}

historyElement("stock-more").addEventListener("click", () =>
  openStockHistory(historyProductId, movementPage + 1));
historyElement("stock-movements").addEventListener("click", (event) => {
  const button = event.target.closest("[data-receipt]");
  if (!button) return;
  showStoreView("sales");
  showHistoricalReceipt(button.dataset.receipt);
});
