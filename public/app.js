// API tokens stay in memory. Refresh/logout removes credentials. No cookie sessions.
let apiToken = "";
const nativeFetch = window.fetch.bind(window);
async function apiFetch(url, options = {}) {
  const send = () =>
    nativeFetch(url, {
      ...options,
      headers: {
        ...options.headers,
        ...(apiToken ? { Authorization: "Bearer " + apiToken } : {}),
      },
    });
  let response = await send();
  if (response.status === 401) {
    apiToken = prompt("Enter your StoreEase access token") || "";
    if (apiToken) response = await send();
  }
  return response;
}
const escapeHTML = (value) =>
  String(value).replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
let checkoutBusy = false;
let pendingCheckout = null;
try {
  pendingCheckout = JSON.parse(
    sessionStorage.getItem("storeease-checkout") || "null",
  );
} catch {
  sessionStorage.removeItem("storeease-checkout");
}
if (
  pendingCheckout &&
  (typeof pendingCheckout.key !== "string" ||
    typeof pendingCheckout.tendered !== "string" ||
    !Array.isArray(pendingCheckout.cart) ||
    !pendingCheckout.cart.length ||
    pendingCheckout.cart.some(
      (item) =>
        !item ||
        !item.product ||
        !Number.isSafeInteger(item.product.id) ||
        !Number.isSafeInteger(item.product.price) ||
        item.product.price < 0 ||
        !Number.isSafeInteger(item.quantity) ||
        item.quantity < 1,
    ))
) {
  pendingCheckout = null;
  sessionStorage.removeItem("storeease-checkout");
}
let currentRole = "cashier";
let scanRequests = 0;

// Constants

// State
let cart = []; // Array of { product: {id, barcode_string, name, price}, quantity }
let errorTimeout = null;
let inventoryProducts = []; // Array of all products loaded from database

// DOM Elements
const barcodeInput = document.getElementById("barcode-input");
const cartBody = document.getElementById("cart-body");
const emptyCartMessage = document.getElementById("empty-cart-message");
const subtotalEl = document.getElementById("summary-subtotal");
const totalEl = document.getElementById("summary-total");
const checkoutBtn = document.getElementById("checkout-btn");
const errorBanner = document.getElementById("error-banner");
const errorMessage = document.getElementById("error-message");
const amountTenderedInput = document.getElementById("amount-tendered");
const changeEl = document.getElementById("summary-change");

const manualBarcode = document.getElementById("manual-barcode");
const manualAddBtn = document.getElementById("manual-add-btn");

const receiptModal = document.getElementById("receipt-modal");
const receiptItems = document.getElementById("receipt-items");
const receiptTotal = document.getElementById("receipt-total");
const closeReceiptBtn = document.getElementById("close-receipt-btn");
const cancelReceiptBtn = document.getElementById("cancel-receipt-btn");
const toggleScannerBtn = document.getElementById("toggle-scanner-btn");

// Navigation & View elements
const navPos = document.getElementById("nav-pos");
const navInventory = document.getElementById("nav-inventory");
const posView = document.getElementById("pos-view");
const inventoryView = document.getElementById("inventory-view");

// Inventory elements
const inventoryBody = document.getElementById("inventory-body");
const inventorySearch = document.getElementById("inventory-search");
const inventoryCountBadge = document.getElementById("inventory-count-badge");
const emptyInventoryMessage = document.getElementById(
  "empty-inventory-message",
);
const addProductBtn = document.getElementById("add-product-btn");

// Product Form Modal elements
const productModal = document.getElementById("product-modal");
const productModalTitle = document.getElementById("product-modal-title");
const closeProductModalBtn = document.getElementById("close-product-modal-btn");
const productForm = document.getElementById("product-form");
const formProductId = document.getElementById("form-product-id");
const formProductBarcode = document.getElementById("form-product-barcode");
const formProductName = document.getElementById("form-product-name");
const formProductPrice = document.getElementById("form-product-price");
const formGenBarcode = document.getElementById("form-gen-barcode");
const cancelProductBtn = document.getElementById("cancel-product-btn");

// Dashboard elements
const navDashboard = document.getElementById("nav-dashboard");
const dashboardView = document.getElementById("dashboard-view");
const kpiToday = document.getElementById("kpi-today");
const kpiWeek = document.getElementById("kpi-week");
const kpiMonth = document.getElementById("kpi-month");
const kpiYear = document.getElementById("kpi-year");
const popularItemsBody = document.getElementById("popular-items-body");
const emptyPopularMessage = document.getElementById("empty-popular-message");

let salesChartInstance = null;

// --- Initialization & Event Listeners ---

// Always keep focus on the hidden barcode input, unless typing in manual entry or modal forms
document.addEventListener("click", (e) => {
  // Only focus if the POS view is active and we are not interacting with form elements
  const isRegisterActive = !posView.classList.contains("hidden");
  if (isRegisterActive) {
    const clickedFormField =
      e.target.tagName === "INPUT" ||
      e.target.tagName === "BUTTON" ||
      e.target.closest(".modal-content") ||
      e.target.closest(".qty-control");
    if (!clickedFormField) {
      barcodeInput.focus();
    }
  }
});

// Listen for "Enter" key on the barcode input
barcodeInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.repeat && !e.isComposing) {
    const val = barcodeInput.value.trim(); // Trim whitespace and hidden characters
    if (val) {
      handleBarcodeScan(val);
    }
    barcodeInput.value = ""; // Reset for next scan
  }
});

// Manual entry fallback
manualAddBtn.addEventListener("click", () => {
  const val = manualBarcode.value.trim();
  if (val) {
    handleBarcodeScan(val);
    manualBarcode.value = "";
  }
  barcodeInput.focus();
});
manualBarcode.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    const val = manualBarcode.value.trim();
    if (val) {
      handleBarcodeScan(val);
      manualBarcode.value = "";
    }
    barcodeInput.focus();
  }
});

// Checkout process
checkoutBtn.addEventListener("click", handleCheckout);

// Payment calculations
amountTenderedInput.addEventListener("input", calculateChange);

// Close Receipt
closeReceiptBtn.addEventListener("click", () => {
  receiptModal.classList.add("hidden");
  barcodeInput.focus();
});

// Both receipt controls close an already completed transaction.
cancelReceiptBtn.addEventListener("click", () => {
  receiptModal.classList.add("hidden");
  barcodeInput.focus();
});

// --- Core Logic ---

async function handleBarcodeScan(barcode) {
  if (
    checkoutBusy ||
    pendingCheckout ||
    !receiptModal.classList.contains("hidden") ||
    posView.classList.contains("hidden")
  )
    return;
  scanRequests++;
  checkoutBtn.disabled = true;
  hideError();
  try {
    const response = await apiFetch(
      `/api/products/${encodeURIComponent(barcode)}`,
    );
    if (!response.ok) {
      const errData = await response.json();
      throw new Error(errData.error || "Item Not Found");
    }
    const product = await response.json();
    addToCart(product);
    playBeep(); // Satisfying barcode success beep
  } catch (error) {
    showError(error.message);
  } finally {
    scanRequests--;
    calculateChange();
  }
}

function addToCart(product) {
  // Check if item already in cart
  const existingItem = cart.find((item) => item.product.id === product.id);

  if (existingItem) {
    existingItem.quantity += 1;
  } else {
    cart.push({ product, quantity: 1 });
  }

  updateCartUI();
}

function parsePesos(value) {
  if (!/^\d+(\.\d{1,2})?$/.test(value)) return NaN;
  const [whole, fraction = ""] = value.split(".");
  const cents = BigInt(whole) * 100n + BigInt(fraction.padEnd(2, "0"));
  return cents <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(cents) : NaN;
}

function formatCurrency(cents) {
  return "₱" + (cents / 100).toFixed(2);
}

function calculateChange() {
  let totalCents = 0;
  cart.forEach((item) => {
    totalCents += item.product.price * item.quantity;
  });

  const tenderedVal = amountTenderedInput.value.trim();
  if (!tenderedVal) {
    changeEl.textContent = "₱0.00";
    changeEl.classList.remove("insufficient-funds");
    checkoutBtn.disabled = true;
    return;
  }

  const tenderedCents = parsePesos(tenderedVal);
  const changeCents = tenderedCents - totalCents;

  amountTenderedInput.disabled = checkoutBusy || !!pendingCheckout;
  if (!Number.isSafeInteger(changeCents) || !Number.isSafeInteger(totalCents)) {
    changeEl.textContent = "₱0.00";
    changeEl.classList.remove("insufficient-funds");
    checkoutBtn.disabled = true;
  } else if (changeCents < 0) {
    changeEl.textContent = formatCurrency(changeCents);
    changeEl.classList.add("insufficient-funds");
    checkoutBtn.disabled = true;
  } else {
    changeEl.textContent = formatCurrency(changeCents);
    changeEl.classList.remove("insufficient-funds");
    checkoutBtn.disabled =
      checkoutBusy || scanRequests > 0 || cart.length === 0;
  }
}

function updateCartUI() {
  // Render Cart Items
  if (cart.length === 0) {
    cartBody.innerHTML = "";
    emptyCartMessage.style.display = "block";
    checkoutBtn.disabled = true;
    amountTenderedInput.value = "";
    amountTenderedInput.disabled = true;
    changeEl.textContent = "₱0.00";
    changeEl.classList.remove("insufficient-funds");
  } else {
    emptyCartMessage.style.display = "none";
    amountTenderedInput.disabled = checkoutBusy || !!pendingCheckout;

    cartBody.innerHTML = cart
      .map((item) => {
        // Price is stored in cents, do math in cents before formatting
        const itemSubtotalCents = item.product.price * item.quantity;

        return `
                <tr>
                    <td>
                        <div class="item-name">${escapeHTML(item.product.name)}</div>
                        <div class="item-barcode">${escapeHTML(item.product.barcode_string)}</div>
                    </td>
                    <td>
                        <div class="qty-control">
                            <button class="qty-btn" data-action="decrease" data-id="${item.product.id}" title="Decrease quantity">−</button>
                            <span class="qty-val">${item.quantity}</span>
                            <button class="qty-btn" data-action="increase" data-id="${item.product.id}" title="Increase quantity">+</button>
                        </div>
                    </td>
                    <td>${formatCurrency(item.product.price)}</td>
                    <td>${formatCurrency(itemSubtotalCents)}</td>
                    <td style="text-align: center;">
                        <button class="delete-btn" data-action="remove" data-id="${item.product.id}" title="Remove item">
                            <svg viewBox="0 0 24 24">
                                <path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/>
                            </svg>
                        </button>
                    </td>
                </tr>
            `;
      })
      .join("");
  }

  // Calculate Totals using exact integer math (cents)
  let totalCents = 0;
  cart.forEach((item) => {
    totalCents += item.product.price * item.quantity;
  });

  // Update Summary UI
  subtotalEl.textContent = formatCurrency(totalCents);
  totalEl.textContent = formatCurrency(totalCents);

  calculateChange();
}

async function handleCheckout() {
  if (checkoutBusy || scanRequests) return;
  if (pendingCheckout) {
    cart = pendingCheckout.cart;
    amountTenderedInput.value = pendingCheckout.tendered;
  }
  if (!Number.isSafeInteger(parsePesos(amountTenderedInput.value))) {
    showError("Enter a valid payment amount.");
    return;
  }
  if (cart.length === 0 || checkoutBusy || scanRequests) return;
  checkoutBusy = true;
  checkoutBtn.disabled = true;

  let totalCents = 0;
  cart.forEach((item) => {
    totalCents += item.product.price * item.quantity;
  });

  try {
    if (!pendingCheckout) {
      pendingCheckout = {
        key: crypto.randomUUID(),
        cart: structuredClone(cart),
        tendered: amountTenderedInput.value,
      };
      try {
        sessionStorage.setItem(
          "storeease-checkout",
          JSON.stringify(pendingCheckout),
        );
      } catch {
        pendingCheckout = null;
        throw new Error(
          "Browser storage is unavailable. Enable session storage before checkout.",
        );
      }
    }
    // Prepare checkout transaction payload
    const itemsPayload = cart.map((item) => ({
      product_id: item.product.id,
      quantity: item.quantity,
      price: item.product.price, // Display estimate only; server prices are authoritative.
    }));

    const response = await apiFetch("/api/sales", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": pendingCheckout.key,
      },
      body: JSON.stringify({
        total_amount: totalCents,
        tendered_amount: parsePesos(amountTenderedInput.value),
        items: itemsPayload,
      }),
    });

    const data = await response.json();
    if (!response.ok) {
      if (
        [400, 404, 409].includes(response.status) &&
        data.code !== "IDEMPOTENCY_CONFLICT"
      ) {
        pendingCheckout = null;
        sessionStorage.removeItem("storeease-checkout");
        // Refresh displayed prices after a definite rejection. No sale committed.
        const latest = await apiFetch("/api/products");
        if (latest.ok) {
          const products = await latest.json();
          cart = cart.map((item) => ({
            ...item,
            product:
              products.find((p) => p.id === item.product.id) || item.product,
          }));
          updateCartUI();
        }
      }
      throw new Error(data.error || "Failed to record transaction.");
    }

    // Always render the committed server snapshot, including price changes.
    cart = data.items.map((item) => ({
      product: {
        id: item.product_id,
        name: item.product_name,
        barcode_string: item.barcode_string,
        price: item.price,
      },
      quantity: item.quantity,
    }));
    totalCents = data.total_amount;
    // Build Receipt on successful checkout capture
    receiptItems.innerHTML = cart
      .map(
        (item) => `
            <div class="receipt-row">
                <span>${item.quantity}x ${escapeHTML(item.product.name)}</span>
                <span>${formatCurrency(item.product.price * item.quantity)}</span>
            </div>
        `,
      )
      .join("");

    const tenderedVal = amountTenderedInput.value.trim();
    const tenderedCents = parsePesos(tenderedVal);
    const changeCents = tenderedCents - totalCents;

    receiptTotal.textContent = formatCurrency(totalCents);
    document.getElementById("receipt-tendered").textContent =
      formatCurrency(tenderedCents);
    document.getElementById("receipt-change").textContent =
      formatCurrency(changeCents);

    // Show Receipt
    receiptModal.classList.remove("hidden");
    pendingCheckout = null;
    sessionStorage.removeItem("storeease-checkout");
    cart = [];
    updateCartUI();
  } catch (err) {
    console.error("Checkout recording failure:", err);
    alert("Checkout error: " + err.message);
  } finally {
    checkoutBusy = false;
    calculateChange();
  }
}

function showError(msg) {
  errorMessage.textContent = msg;
  errorBanner.classList.remove("hidden");
  if (posView.classList.contains("hidden")) alert(msg);

  // Auto-hide after 5 seconds
  if (errorTimeout) clearTimeout(errorTimeout);
  errorTimeout = setTimeout(hideError, 5000);
}

function hideError() {
  errorBanner.classList.add("hidden");
}

function updateQty(productId, newQty) {
  if (checkoutBusy || pendingCheckout || !Number.isSafeInteger(newQty)) return;
  if (newQty <= 0) {
    removeItem(productId);
    return;
  }
  const item = cart.find((item) => item.product.id === productId);
  if (item) {
    item.quantity = newQty;
    updateCartUI();
  }
}

function removeItem(productId) {
  if (checkoutBusy || pendingCheckout) return;
  cart = cart.filter((item) => item.product.id !== productId);
  updateCartUI();
}

// --- Barcode Scanner Systems ---

// 1. Synthesize scanner beep sound using Web Audio API (no external assets needed)
function playBeep() {
  try {
    const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const oscillator = audioCtx.createOscillator();
    const gainNode = audioCtx.createGain();

    oscillator.connect(gainNode);
    gainNode.connect(audioCtx.destination);

    oscillator.type = "sine";
    oscillator.frequency.value = 1000; // Standard scanner frequency (1kHz)
    gainNode.gain.setValueAtTime(0.12, audioCtx.currentTime); // Volume

    oscillator.start();
    oscillator.stop(audioCtx.currentTime + 0.08);
    oscillator.onended = () => audioCtx.close(); // Short 80ms beep
  } catch (err) {
    console.warn("Unable to play beep sound:", err);
  }
}

// 2. Global hardware barcode scanner key interceptor
let barcodeBuffer = "";
let lastKeyTime = Date.now();

document.addEventListener("keydown", (e) => {
  if (
    e.repeat ||
    e.isComposing ||
    e.ctrlKey ||
    e.altKey ||
    e.metaKey ||
    posView.classList.contains("hidden") ||
    !receiptModal.classList.contains("hidden") ||
    !productModal.classList.contains("hidden") ||
    document.activeElement?.matches("input,textarea,select,[contenteditable]")
  ) {
    barcodeBuffer = "";
    return;
  }
  // Skip if focus is inside either the manual barcode field or the hidden barcode input (to prevent double scans)
  if (
    document.activeElement === manualBarcode ||
    document.activeElement === barcodeInput
  ) {
    return;
  }

  const now = Date.now();
  const diff = now - lastKeyTime;
  lastKeyTime = now;
  if (diff > 100) barcodeBuffer = "";

  // Detect Enter suffix (usually sent by hardware scanners at the end of EAN/UPC reads)
  if (e.key === "Enter") {
    const val = barcodeBuffer.trim();
    if (val) {
      handleBarcodeScan(val);
      barcodeBuffer = "";
      e.preventDefault();
    }
    return;
  }

  // Ignore modifier keys
  if (
    e.key === "Shift" ||
    e.key === "Control" ||
    e.key === "Alt" ||
    e.key === "Meta"
  ) {
    return;
  }

  // Hardware scanners type extremely fast (< 40ms between keys).
  // Reset the buffer if there's a slow manual human keyboard entry.
  const isInputFocused =
    document.activeElement &&
    (document.activeElement.tagName === "INPUT" ||
      document.activeElement.tagName === "TEXTAREA");
  if (diff > 50) {
    barcodeBuffer = "";
  }

  // Buffer the alphanumeric keys
  if (e.key.length === 1 && /^[a-zA-Z0-9]$/.test(e.key)) {
    barcodeBuffer += e.key;
  }
});

// 3. Camera Barcode Scanner via html5-qrcode
let html5QrcodeScanner = null;
let cameraBusy = false;
let lastCameraScan = 0;
async function startCameraScanner() {
  if (cameraBusy || html5QrcodeScanner) return;
  if (!window.Html5Qrcode) {
    showError(
      "Camera library unavailable. Use manual entry or a keyboard scanner.",
    );
    return;
  }
  cameraBusy = true;
  try {
    html5QrcodeScanner = new Html5Qrcode("reader");
    await html5QrcodeScanner.start(
      { facingMode: "environment" },
      { fps: 15, qrbox: { width: 250, height: 120 } },
      (code) => {
        if (Date.now() - lastCameraScan < 1800) return;
        lastCameraScan = Date.now();
        handleBarcodeScan(code);
      },
    );
    toggleScannerBtn.textContent = "Stop Camera Scanner";
    toggleScannerBtn.classList.add("active");
    if (posView.classList.contains("hidden")) {
      cameraBusy = false;
      await stopCameraScanner();
    }
  } catch (err) {
    html5QrcodeScanner = null;
    showError("Unable to access camera. Check permissions.");
  } finally {
    cameraBusy = false;
  }
}
async function stopCameraScanner() {
  if (cameraBusy) return;
  cameraBusy = true;
  try {
    if (html5QrcodeScanner?.isScanning) await html5QrcodeScanner.stop();
    if (html5QrcodeScanner) await html5QrcodeScanner.clear();
    html5QrcodeScanner = null;
    toggleScannerBtn.textContent = "Start Camera Scanner";
    toggleScannerBtn.classList.remove("active");
  } catch (err) {
    showError("Unable to stop camera. Please retry.");
  } finally {
    cameraBusy = false;
  }
}
toggleScannerBtn.addEventListener("click", () =>
  html5QrcodeScanner ? stopCameraScanner() : startCameraScanner(),
);

// --- Navigation Tab Switching ---

function showStoreView(name) {
  for (const view of ["pos", "inventory", "dashboard", "sales"]) {
    document.getElementById(view + "-view").classList.toggle("hidden", view !== name);
    document.getElementById("nav-" + view).classList.toggle("active", view === name);
  }
  if (name === "pos") barcodeInput.focus();
  else stopCameraScanner();
}

navPos.addEventListener("click", () => showStoreView("pos"));
navInventory.addEventListener("click", () => {
  showStoreView("inventory");
  loadInventory();
});
navDashboard.addEventListener("click", () => {
  showStoreView("dashboard");
  loadDashboardAnalytics();
});

// --- Inventory Manager AJAX CRUD Operations ---

// Load all products from SQLite via backend REST API
async function loadInventory() {
  try {
    const response = await apiFetch("/api/products");
    if (!response.ok) {
      throw new Error("Failed to retrieve inventory list.");
    }
    inventoryProducts = await response.json();
    renderInventoryTable();
  } catch (err) {
    inventoryBody.innerHTML = "";
    inventoryCountBadge.textContent = "Unavailable";
    console.error("Inventory load error:", err);
    showError(err.message);
  }
}

// Render inventory array to view table, with search query filtering
function stockStatus(product) {
  if (product.stock === 0) return "Out of Stock";
  if (product.stock !== null && product.reorder_level != null &&
      product.stock <= product.reorder_level) return "Low Stock";
  return "";
}

function renderInventoryTable() {
  const query = inventorySearch.value.trim().toLowerCase();

  const filtered = inventoryProducts.filter((p) => {
    if (document.getElementById("low-stock-only").checked && !stockStatus(p)) return false;
    return (
      p.name.toLowerCase().includes(query) ||
      p.barcode_string.toLowerCase().includes(query)
    );
  });

  // Update product quantity badge
  inventoryCountBadge.textContent =
    `${inventoryProducts.length} Product` +
    (inventoryProducts.length === 1 ? "" : "s");

  if (filtered.length === 0) {
    inventoryBody.innerHTML = "";
    emptyInventoryMessage.classList.remove("hidden");
  } else {
    emptyInventoryMessage.classList.add("hidden");
    inventoryBody.innerHTML = filtered
      .map((p) => {
        const formattedPrice = "₱" + (p.price / 100).toFixed(2);
        return `
                <tr>
                    <td style="font-family: monospace; font-size: 0.95rem; font-weight: 500;">${escapeHTML(p.barcode_string)}</td>
                    <td>${escapeHTML(p.name)}</td>
                    <td style="font-weight: 600;">${formattedPrice}<br><small>Stock: ${p.stock === null ? "Untracked" : p.stock}</small> ${stockStatus(p) ? `<span class="stock-badge">${stockStatus(p)}</span>` : ""} <button ${currentRole !== "admin" ? "hidden" : ""} class="action-btn" data-action="stock" data-id="${p.id}" title="Adjust stock">±</button></td>
                    <td>
                        <div class="action-btn-group" ${currentRole !== "admin" ? "hidden" : ""}>
                            <button class="nav-tab" data-action="history" data-id="${p.id}">Stock History</button>
                            ${p.stock !== null ? `<button class="nav-tab" data-action="reorder" data-id="${p.id}">Reorder Level: ${p.reorder_level ?? "Off"}</button>` : ""}
                            <button class="action-btn edit-btn" data-action="edit" data-id="${p.id}" title="Edit Product">
                                <svg viewBox="0 0 24 24" style="width: 16px; height: 16px; fill: currentColor;"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>
                            </button>
                            <button class="action-btn delete-btn-inv" data-action="deactivate" data-id="${p.id}" title="Delete Product">
                                <svg viewBox="0 0 24 24" style="width: 16px; height: 16px; fill: currentColor;"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
                            </button>
                        </div>
                    </td>
                </tr>
            `;
      })
      .join("");
  }
}

// Attach filter input listener
inventorySearch.addEventListener("input", renderInventoryTable);
document.getElementById("low-stock-only").addEventListener("change", renderInventoryTable);

// Form modal controls
addProductBtn.addEventListener("click", () => {
  productForm.reset();
  formProductId.value = "";
  productModalTitle.textContent = "Add New Product";
  productModal.classList.remove("hidden");
  formProductBarcode.disabled = false;
});

closeProductModalBtn.addEventListener("click", () => {
  productModal.classList.add("hidden");
});

cancelProductBtn.addEventListener("click", () => {
  productModal.classList.add("hidden");
});

// Generate random barcode strings
formGenBarcode.addEventListener("click", () => {
  let randomCode = "";
  for (let i = 0; i < 12; i++) {
    randomCode += Math.floor(Math.random() * 10);
  }
  formProductBarcode.value = randomCode;
});

// Open product edit modal
window.openEditProductModal = function (id) {
  const p = inventoryProducts.find((prod) => prod.id === id);
  if (!p) return;

  formProductId.value = p.id;
  formProductBarcode.value = p.barcode_string;
  formProductBarcode.disabled = false; // Allow modifying barcode too!
  formProductName.value = p.name;
  formProductPrice.value = (p.price / 100).toFixed(2);

  productModalTitle.textContent = "Edit Product";
  productModal.classList.remove("hidden");
};

// Form submission for Add / Update
productForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  if (pendingCheckout || checkoutBusy) return;

  const saveBtn = document.getElementById("save-product-btn");
  if (saveBtn.disabled) return;
  const id = formProductId.value;
  const barcode_string = formProductBarcode.value.trim();
  const name = formProductName.value.trim();
  const priceVal = formProductPrice.value;

  if (!barcode_string || !name || !/^\d+(\.\d{1,2})?$/.test(priceVal)) {
    alert("Please fill out all product details correctly.");
    return;
  }

  const payload = { barcode_string, name, price: priceVal };
  const method = id ? "PUT" : "POST";
  const url = id ? `/api/products/${id}` : "/api/products";

  saveBtn.disabled = true;
  try {
    const response = await apiFetch(url, {
      method: method,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || "Failed to save product details.");
    }

    productModal.classList.add("hidden");
    loadInventory();

    // Update product in active POS sales cart if it was modified
    if (id) {
      const numId = parseInt(id);
      cart = cart.map((item) => {
        if (item.product.id === numId) {
          item.product.name = name;
          item.product.price = data.price; // backend returns cents integer
          item.product.barcode_string = barcode_string;
        }
        return item;
      });
      updateCartUI();
    }
  } catch (err) {
    console.error(err);
    alert(err.message);
  } finally {
    saveBtn.disabled = false;
  }
});

// Delete Product from Database
window.deleteProductFromInventory = async function (id) {
  if (pendingCheckout || checkoutBusy) return;
  if (!confirm("Deactivate this product? Historical receipts are preserved.")) {
    return;
  }

  try {
    const response = await apiFetch(`/api/products/${id}`, {
      method: "DELETE",
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.error || "Failed to remove product from database.");
    }

    loadInventory();

    // Also clean up from active checkout cart if that item was present
    const numId = parseInt(id);
    cart = cart.filter((item) => item.product.id !== numId);
    updateCartUI();
  } catch (err) {
    console.error(err);
    alert(err.message);
  }
};

// --- Sales Analytics Dashboard Functions ---

// Fetch analytics from backend and load dashboard
async function loadDashboardAnalytics() {
  try {
    const response = await apiFetch("/api/analytics");
    if (!response.ok) {
      throw new Error("Failed to retrieve sales analytics.");
    }

    const analytics = await response.json();

    // Update KPIs
    kpiToday.textContent = formatCurrency(analytics.kpis.today);
    kpiWeek.textContent = formatCurrency(analytics.kpis.week);
    kpiMonth.textContent = formatCurrency(analytics.kpis.month);
    kpiYear.textContent = formatCurrency(analytics.kpis.year);

    // Render Popular Items Table
    if (analytics.popularItems.length === 0) {
      popularItemsBody.innerHTML = "";
      emptyPopularMessage.classList.remove("hidden");
    } else {
      emptyPopularMessage.classList.add("hidden");
      popularItemsBody.innerHTML = analytics.popularItems
        .map((item) => {
          const name = item.name || "Unknown Item";
          const formattedRevenue = formatCurrency(item.revenue);
          return `
                    <tr>
                        <td style="font-weight: 500;">${escapeHTML(name)}</td>
                        <td style="font-weight: 600;"><span class="qty-badge">${item.times_sold}</span></td>
                        <td style="font-weight: 600;">${formattedRevenue}</td>
                    </tr>
                `;
        })
        .join("");
    }

    // Draw Line Chart
    renderSalesChart(analytics.chartData.labels, analytics.chartData.data);
  } catch (err) {
    for (const element of [kpiToday, kpiWeek, kpiMonth, kpiYear])
      element.textContent = "Unavailable";
    console.error("Analytics load error:", err);
    showError(err.message);
  }
}

// Draw/Update Chart.js line graph
function renderSalesChart(labels, data) {
  const canvas = document.getElementById("sales-chart-canvas");
  if (!canvas) return;
  if (!window.Chart) {
    showError("Chart library unavailable; totals remain available.");
    return;
  }

  const ctx = canvas.getContext("2d");

  // Destroy previous Chart instance to prevent rendering glitches on hover
  if (salesChartInstance) {
    salesChartInstance.destroy();
  }


  salesChartInstance = new Chart(ctx, {
    type: "line",
    data: {
      labels: labels,
      datasets: [
        {
          label: "Sales Revenue (₱)",
          data: data.map((cents) => cents / 100), // Convert cents to decimal pesos
          borderColor: "#245bbd",
          borderWidth: 3,
          backgroundColor: "rgba(36, 91, 189, 0.08)",
          fill: true,
          tension: 0.35, // Smooth curves
          pointBackgroundColor: "#245bbd",
          pointBorderColor: "#fff",
          pointBorderWidth: 2,
          pointRadius: 5,
          pointHoverRadius: 7,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          display: false,
        },
        tooltip: {
          backgroundColor: "#ffffff",
          titleColor: "#172438",
          bodyColor: "#172438",
          borderColor: "#dce3ec",
          borderWidth: 1,
          padding: 12,
          displayColors: false,
          callbacks: {
            label: function (context) {
              return "Revenue: ₱" + context.parsed.y.toFixed(2);
            },
          },
        },
      },
      scales: {
        x: {
          grid: {
            color: "#e5ebf3",
            borderColor: "transparent",
          },
          ticks: {
            color: "#47576d",
            font: {
              family: "'Inter', sans-serif",
              size: 11,
            },
          },
        },
        y: {
          grid: {
            color: "#e5ebf3",
            borderColor: "transparent",
          },
          ticks: {
            color: "#47576d",
            font: {
              family: "'Inter', sans-serif",
              size: 11,
            },
            callback: function (value) {
              return "₱" + value;
            },
          },
        },
      },
    },
  });
}

// Initial setup
barcodeInput.focus();
updateCartUI();

window.adjustStock = async (id) => {
  if (pendingCheckout || checkoutBusy) return;
  const delta = prompt(
    "Quantity adjustment (first adjustment enables tracking from zero)",
  );
  if (delta === null) return;
  const reason = prompt("Reason for adjustment");
  if (!/^-?\d+$/.test(delta) || !reason?.trim()) {
    alert("Enter an integer and reason.");
    return;
  }
  try {
    const response = await apiFetch("/api/products/" + id + "/stock", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ delta: Number(delta), reason }),
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error);
    await loadInventory();
  } catch (err) {
    alert(err.message);
  }
};
if (pendingCheckout) {
  cart = pendingCheckout.cart;
  updateCartUI();
  amountTenderedInput.value = pendingCheckout.tendered;
  calculateChange();
  showError(
    "A checkout needs confirmation. Retry checkout to retrieve its result before changing the cart.",
  );
}
document.getElementById("logout-btn").addEventListener("click", () => {
  apiToken = "";
  location.reload();
});
window.addEventListener("offline", () =>
  showError("Offline. Your cart is retained; retry checkout when connected."),
);

(async () => {
  try {
    const response = await apiFetch("/api/session");
    const data = await response.json();
    if (!response.ok) throw new Error(data.error);
    currentRole = data.role;
    addProductBtn.hidden = currentRole !== "admin";
    navDashboard.hidden = currentRole !== "admin";
    document.getElementById("sales-filters").hidden = currentRole !== "admin";
    renderInventoryTable();
  } catch (err) {
    showError(err.message);
  }
})();

cartBody.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  const id = Number(button.dataset.id);
  const item = cart.find((row) => row.product.id === id);
  if (!item) return;
  if (button.dataset.action === "remove") removeItem(id);
  else
    updateQty(
      id,
      item.quantity + (button.dataset.action === "increase" ? 1 : -1),
    );
});
inventoryBody.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button || currentRole !== "admin") return;
  const id = Number(button.dataset.id);
  if (button.dataset.action === "stock") window.adjustStock(id);
  else if (button.dataset.action === "history") openStockHistory(id);
  else if (button.dataset.action === "reorder") editReorderLevel(id);
  else if (button.dataset.action === "edit") window.openEditProductModal(id);
  else if (button.dataset.action === "deactivate")
    window.deleteProductFromInventory(id);
});
