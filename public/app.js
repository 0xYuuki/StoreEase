// Constants

// State
let cart = []; // Array of { product: {id, barcode_string, name, price}, quantity }
let errorTimeout = null;
let inventoryProducts = []; // Array of all products loaded from database

// DOM Elements
const barcodeInput = document.getElementById('barcode-input');
const cartBody = document.getElementById('cart-body');
const emptyCartMessage = document.getElementById('empty-cart-message');
const subtotalEl = document.getElementById('summary-subtotal');
const totalEl = document.getElementById('summary-total');
const checkoutBtn = document.getElementById('checkout-btn');
const errorBanner = document.getElementById('error-banner');
const errorMessage = document.getElementById('error-message');
const amountTenderedInput = document.getElementById('amount-tendered');
const changeEl = document.getElementById('summary-change');

const manualBarcode = document.getElementById('manual-barcode');
const manualAddBtn = document.getElementById('manual-add-btn');

const receiptModal = document.getElementById('receipt-modal');
const receiptItems = document.getElementById('receipt-items');
const receiptTotal = document.getElementById('receipt-total');
const closeReceiptBtn = document.getElementById('close-receipt-btn');
const cancelReceiptBtn = document.getElementById('cancel-receipt-btn');
const toggleScannerBtn = document.getElementById('toggle-scanner-btn');

// Navigation & View elements
const navPos = document.getElementById('nav-pos');
const navInventory = document.getElementById('nav-inventory');
const posView = document.getElementById('pos-view');
const inventoryView = document.getElementById('inventory-view');

// Inventory elements
const inventoryBody = document.getElementById('inventory-body');
const inventorySearch = document.getElementById('inventory-search');
const inventoryCountBadge = document.getElementById('inventory-count-badge');
const emptyInventoryMessage = document.getElementById('empty-inventory-message');
const addProductBtn = document.getElementById('add-product-btn');

// Product Form Modal elements
const productModal = document.getElementById('product-modal');
const productModalTitle = document.getElementById('product-modal-title');
const closeProductModalBtn = document.getElementById('close-product-modal-btn');
const productForm = document.getElementById('product-form');
const formProductId = document.getElementById('form-product-id');
const formProductBarcode = document.getElementById('form-product-barcode');
const formProductName = document.getElementById('form-product-name');
const formProductPrice = document.getElementById('form-product-price');
const formGenBarcode = document.getElementById('form-gen-barcode');
const cancelProductBtn = document.getElementById('cancel-product-btn');

// Dashboard elements
const navDashboard = document.getElementById('nav-dashboard');
const dashboardView = document.getElementById('dashboard-view');
const kpiToday = document.getElementById('kpi-today');
const kpiWeek = document.getElementById('kpi-week');
const kpiMonth = document.getElementById('kpi-month');
const kpiYear = document.getElementById('kpi-year');
const popularItemsBody = document.getElementById('popular-items-body');
const emptyPopularMessage = document.getElementById('empty-popular-message');

let salesChartInstance = null;

// --- Initialization & Event Listeners ---

// Always keep focus on the hidden barcode input, unless typing in manual entry or modal forms
document.addEventListener('click', (e) => {
    // Only focus if the POS view is active and we are not interacting with form elements
    const isRegisterActive = !posView.classList.contains('hidden');
    if (isRegisterActive) {
        const clickedFormField = e.target.tagName === 'INPUT' || e.target.tagName === 'BUTTON' || e.target.closest('.modal-content') || e.target.closest('.qty-control');
        if (!clickedFormField) {
            barcodeInput.focus();
        }
    }
});

// Listen for "Enter" key on the barcode input
barcodeInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        const val = barcodeInput.value.trim(); // Trim whitespace and hidden characters
        if (val) {
            handleBarcodeScan(val);
        }
        barcodeInput.value = ''; // Reset for next scan
    }
});

// Manual entry fallback
manualAddBtn.addEventListener('click', () => {
    const val = manualBarcode.value.trim();
    if (val) {
        handleBarcodeScan(val);
        manualBarcode.value = '';
    }
    barcodeInput.focus();
});
manualBarcode.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        const val = manualBarcode.value.trim();
        if (val) {
            handleBarcodeScan(val);
            manualBarcode.value = '';
        }
        barcodeInput.focus();
    }
});

// Checkout process
checkoutBtn.addEventListener('click', handleCheckout);

// Payment calculations
amountTenderedInput.addEventListener('input', calculateChange);

// Close Receipt
closeReceiptBtn.addEventListener('click', () => {
    receiptModal.classList.add('hidden');
    cart = [];
    amountTenderedInput.value = '';
    updateCartUI();
    barcodeInput.focus();
});

// Close Receipt modal but keep cart intact (allows adding more items to the current transaction)
cancelReceiptBtn.addEventListener('click', () => {
    receiptModal.classList.add('hidden');
    barcodeInput.focus();
});


// --- Core Logic ---

async function handleBarcodeScan(barcode) {
    hideError();
    try {
        const response = await fetch(`/api/products/${barcode}`);
        if (!response.ok) {
            const errData = await response.json();
            throw new Error(errData.error || 'Item Not Found');
        }
        const product = await response.json();
        addToCart(product);
        playBeep(); // Satisfying barcode success beep
    } catch (error) {
        showError(error.message);
    }
}

function addToCart(product) {
    // Check if item already in cart
    const existingItem = cart.find(item => item.product.id === product.id);

    if (existingItem) {
        existingItem.quantity += 1;
    } else {
        cart.push({ product, quantity: 1 });
    }

    updateCartUI();
}

function formatCurrency(cents) {
    return '₱' + (cents / 100).toFixed(2);
}

function calculateChange() {
    let totalCents = 0;
    cart.forEach(item => {
        totalCents += item.product.price * item.quantity;
    });

    const tenderedVal = amountTenderedInput.value.trim();
    if (!tenderedVal) {
        changeEl.textContent = '₱0.00';
        changeEl.classList.remove('insufficient-funds');
        checkoutBtn.disabled = true;
        return;
    }

    const tenderedCents = Math.round(parseFloat(tenderedVal) * 100);
    const changeCents = tenderedCents - totalCents;

    if (isNaN(changeCents)) {
        changeEl.textContent = '₱0.00';
        changeEl.classList.remove('insufficient-funds');
        checkoutBtn.disabled = true;
    } else if (changeCents < 0) {
        changeEl.textContent = formatCurrency(changeCents);
        changeEl.classList.add('insufficient-funds');
        checkoutBtn.disabled = true;
    } else {
        changeEl.textContent = formatCurrency(changeCents);
        changeEl.classList.remove('insufficient-funds');
        checkoutBtn.disabled = false;
    }
}

function updateCartUI() {
    // Render Cart Items
    if (cart.length === 0) {
        cartBody.innerHTML = '';
        emptyCartMessage.style.display = 'block';
        checkoutBtn.disabled = true;
        amountTenderedInput.value = '';
        amountTenderedInput.disabled = true;
        changeEl.textContent = '₱0.00';
        changeEl.classList.remove('insufficient-funds');
    } else {
        emptyCartMessage.style.display = 'none';
        amountTenderedInput.disabled = false;

        cartBody.innerHTML = cart.map(item => {
            // Price is stored in cents, do math in cents before formatting
            const itemSubtotalCents = item.product.price * item.quantity;

            return `
                <tr>
                    <td>
                        <div class="item-name">${item.product.name}</div>
                        <div class="item-barcode">${item.product.barcode_string}</div>
                    </td>
                    <td>
                        <div class="qty-control">
                            <button class="qty-btn" onclick="updateQty(${item.product.id}, ${item.quantity - 1})" title="Decrease quantity">−</button>
                            <span class="qty-val">${item.quantity}</span>
                            <button class="qty-btn" onclick="updateQty(${item.product.id}, ${item.quantity + 1})" title="Increase quantity">+</button>
                        </div>
                    </td>
                    <td>${formatCurrency(item.product.price)}</td>
                    <td>${formatCurrency(itemSubtotalCents)}</td>
                    <td style="text-align: center;">
                        <button class="delete-btn" onclick="removeItem(${item.product.id})" title="Remove item">
                            <svg viewBox="0 0 24 24">
                                <path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/>
                            </svg>
                        </button>
                    </td>
                </tr>
            `;
        }).join('');
    }

    // Calculate Totals using exact integer math (cents)
    let totalCents = 0;
    cart.forEach(item => {
        totalCents += item.product.price * item.quantity;
    });

    // Update Summary UI
    subtotalEl.textContent = formatCurrency(totalCents);
    totalEl.textContent = formatCurrency(totalCents);

    calculateChange();
}

async function handleCheckout() {
    if (cart.length === 0) return;

    let totalCents = 0;
    cart.forEach(item => { totalCents += item.product.price * item.quantity; });

    // Prepare checkout transaction payload
    const itemsPayload = cart.map(item => ({
        product_id: item.product.id,
        quantity: item.quantity,
        price: item.product.price // Capture historical price
    }));

    try {
        const response = await fetch('/api/sales', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                total_amount: totalCents,
                items: itemsPayload
            })
        });

        const data = await response.json();
        if (!response.ok) {
            throw new Error(data.error || 'Failed to record transaction.');
        }

        // Build Receipt on successful checkout capture
        receiptItems.innerHTML = cart.map(item => `
            <div class="receipt-row">
                <span>${item.quantity}x ${item.product.name}</span>
                <span>${formatCurrency(item.product.price * item.quantity)}</span>
            </div>
        `).join('');

        const tenderedVal = amountTenderedInput.value.trim();
        const tenderedCents = tenderedVal ? Math.round(parseFloat(tenderedVal) * 100) : totalCents;
        const changeCents = tenderedCents - totalCents;

        receiptTotal.textContent = formatCurrency(totalCents);
        document.getElementById('receipt-tendered').textContent = formatCurrency(tenderedCents);
        document.getElementById('receipt-change').textContent = formatCurrency(changeCents);

        // Show Receipt
        receiptModal.classList.remove('hidden');
    } catch (err) {
        console.error('Checkout recording failure:', err);
        alert('Checkout error: ' + err.message);
    }
}

function showError(msg) {
    errorMessage.textContent = msg;
    errorBanner.classList.remove('hidden');

    // Auto-hide after 5 seconds
    if (errorTimeout) clearTimeout(errorTimeout);
    errorTimeout = setTimeout(hideError, 5000);
}

function hideError() {
    errorBanner.classList.add('hidden');
}

function updateQty(productId, newQty) {
    if (newQty <= 0) {
        removeItem(productId);
        return;
    }
    const item = cart.find(item => item.product.id === productId);
    if (item) {
        item.quantity = newQty;
        updateCartUI();
    }
}

function removeItem(productId) {
    cart = cart.filter(item => item.product.id !== productId);
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

        oscillator.type = 'sine';
        oscillator.frequency.value = 1000; // Standard scanner frequency (1kHz)
        gainNode.gain.setValueAtTime(0.12, audioCtx.currentTime); // Volume

        oscillator.start();
        oscillator.stop(audioCtx.currentTime + 0.08); // Short 80ms beep
    } catch (err) {
        console.warn('Unable to play beep sound:', err);
    }
}

// 2. Global hardware barcode scanner key interceptor
let barcodeBuffer = '';
let lastKeyTime = Date.now();

document.addEventListener('keydown', (e) => {
    // Skip if focus is inside either the manual barcode field or the hidden barcode input (to prevent double scans)
    if (document.activeElement === manualBarcode || document.activeElement === barcodeInput) {
        return;
    }

    const now = Date.now();
    const diff = now - lastKeyTime;
    lastKeyTime = now;

    // Detect Enter suffix (usually sent by hardware scanners at the end of EAN/UPC reads)
    if (e.key === 'Enter') {
        const val = barcodeBuffer.trim();
        if (val) {
            handleBarcodeScan(val);
            barcodeBuffer = '';
            e.preventDefault();
        }
        return;
    }

    // Ignore modifier keys
    if (e.key === 'Shift' || e.key === 'Control' || e.key === 'Alt' || e.key === 'Meta') {
        return;
    }

    // Hardware scanners type extremely fast (< 40ms between keys).
    // Reset the buffer if there's a slow manual human keyboard entry.
    const isInputFocused = document.activeElement && (document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'TEXTAREA');
    if (isInputFocused && diff > 50) {
        barcodeBuffer = '';
    }

    // Buffer the alphanumeric keys
    if (e.key.length === 1 && /^[a-zA-Z0-9]$/.test(e.key)) {
        barcodeBuffer += e.key;
    }
});

// 3. Camera Barcode Scanner via html5-qrcode
let html5QrcodeScanner = null;

function startCameraScanner() {
    // Explicitly configure supported formats to focus decoding on 1D barcodes and QR codes
    const formats = window.Html5QrcodeSupportedFormats ? [
        Html5QrcodeSupportedFormats.EAN_13,
        Html5QrcodeSupportedFormats.EAN_8,
        Html5QrcodeSupportedFormats.UPC_A,
        Html5QrcodeSupportedFormats.UPC_E,
        Html5QrcodeSupportedFormats.CODE_128,
        Html5QrcodeSupportedFormats.CODE_39,
        Html5QrcodeSupportedFormats.CODE_93,
        Html5QrcodeSupportedFormats.ITF,
        Html5QrcodeSupportedFormats.QR_CODE
    ] : [];

    html5QrcodeScanner = new Html5Qrcode("reader", {
        formatsToSupport: formats,
        experimentalFeatures: {
            useBarCodeDetectorIfSupported: true
        }
    });

    const qrCodeSuccessCallback = (decodedText) => {
        // Stop scanning temporarily on success, process, and auto-resume after a delay
        stopCameraScanner();
        handleBarcodeScan(decodedText);

        // Auto-resume camera scanning after a 1.8 second cooldown (prevents duplicate reading)
        setTimeout(() => {
            if (toggleScannerBtn.classList.contains("active")) {
                startCameraScanner();
            }
        }, 1800);
    };

    const config = {
        fps: 15,
        qrbox: (width, height) => {
            // Rectangular guidance window optimized for 1D grocery barcodes
            return { width: Math.min(width * 0.85, 300), height: Math.min(height * 0.45, 130) };
        },
        // Request higher camera resolution (HD 720p) so thin barcode lines are extremely sharp and decodable
        videoConstraints: {
            width: { min: 640, ideal: 1280, max: 1920 },
            height: { min: 480, ideal: 720, max: 1080 },
            facingMode: "environment"
        }
    };

    html5QrcodeScanner.start({ facingMode: "environment" }, config, qrCodeSuccessCallback)
        .then(() => {
            toggleScannerBtn.textContent = "Stop Camera Scanner";
            toggleScannerBtn.classList.add("active");
        })
        .catch(err => {
            console.error("Camera scanner startup failed:", err);
            showError("Unable to access camera. Verify device permissions.");
        });
}

function stopCameraScanner() {
    if (html5QrcodeScanner && html5QrcodeScanner.isScanning) {
        html5QrcodeScanner.stop().then(() => {
            html5QrcodeScanner.clear();
            html5QrcodeScanner = null;
            toggleScannerBtn.textContent = "Start Camera Scanner";
            toggleScannerBtn.classList.remove("active");
        }).catch(err => {
            console.error("Error stopping scanner:", err);
        });
    } else {
        toggleScannerBtn.textContent = "Start Camera Scanner";
        toggleScannerBtn.classList.remove("active");
    }
}

toggleScannerBtn.addEventListener('click', () => {
    if (html5QrcodeScanner && html5QrcodeScanner.isScanning) {
        stopCameraScanner();
    } else {
        startCameraScanner();
    }
});

// --- Navigation Tab Switching ---

navPos.addEventListener('click', () => {
    navPos.classList.add('active');
    navInventory.classList.remove('active');
    navDashboard.classList.remove('active');
    posView.classList.remove('hidden');
    inventoryView.classList.add('hidden');
    dashboardView.classList.add('hidden');
    barcodeInput.focus();
});

navInventory.addEventListener('click', () => {
    navInventory.classList.add('active');
    navPos.classList.remove('active');
    navDashboard.classList.remove('active');
    inventoryView.classList.remove('hidden');
    posView.classList.add('hidden');
    dashboardView.classList.add('hidden');
    // Pause the camera barcode scanner to save CPU and camera resources when switching tabs
    stopCameraScanner();
    loadInventory();
});

navDashboard.addEventListener('click', () => {
    navDashboard.classList.add('active');
    navPos.classList.remove('active');
    navInventory.classList.remove('active');
    dashboardView.classList.remove('hidden');
    posView.classList.add('hidden');
    inventoryView.classList.add('hidden');
    stopCameraScanner();
    loadDashboardAnalytics();
});

// --- Inventory Manager AJAX CRUD Operations ---

// Load all products from SQLite via backend REST API
async function loadInventory() {
    try {
        const response = await fetch('/api/products');
        if (!response.ok) {
            throw new Error('Failed to retrieve inventory list.');
        }
        inventoryProducts = await response.json();
        renderInventoryTable();
    } catch (err) {
        console.error('Inventory load error:', err);
        showError(err.message);
    }
}

// Render inventory array to view table, with search query filtering
function renderInventoryTable() {
    const query = inventorySearch.value.trim().toLowerCase();
    
    const filtered = inventoryProducts.filter(p => {
        return p.name.toLowerCase().includes(query) || p.barcode_string.toLowerCase().includes(query);
    });

    // Update product quantity badge
    inventoryCountBadge.textContent = `${inventoryProducts.length} Product` + (inventoryProducts.length === 1 ? '' : 's');

    if (filtered.length === 0) {
        inventoryBody.innerHTML = '';
        emptyInventoryMessage.classList.remove('hidden');
    } else {
        emptyInventoryMessage.classList.add('hidden');
        inventoryBody.innerHTML = filtered.map(p => {
            const formattedPrice = '₱' + (p.price / 100).toFixed(2);
            return `
                <tr>
                    <td style="font-family: monospace; font-size: 0.95rem; font-weight: 500;">${p.barcode_string}</td>
                    <td>${p.name}</td>
                    <td style="font-weight: 600;">${formattedPrice}</td>
                    <td>
                        <div class="action-btn-group">
                            <button class="action-btn edit-btn" onclick="openEditProductModal(${p.id})" title="Edit Product">
                                <svg viewBox="0 0 24 24" style="width: 16px; height: 16px; fill: currentColor;"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>
                            </button>
                            <button class="action-btn delete-btn-inv" onclick="deleteProductFromInventory(${p.id})" title="Delete Product">
                                <svg viewBox="0 0 24 24" style="width: 16px; height: 16px; fill: currentColor;"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
                            </button>
                        </div>
                    </td>
                </tr>
            `;
        }).join('');
    }
}

// Attach filter input listener
inventorySearch.addEventListener('input', renderInventoryTable);

// Form modal controls
addProductBtn.addEventListener('click', () => {
    productForm.reset();
    formProductId.value = '';
    productModalTitle.textContent = "Add New Product";
    productModal.classList.remove('hidden');
    formProductBarcode.disabled = false;
});

closeProductModalBtn.addEventListener('click', () => {
    productModal.classList.add('hidden');
});

cancelProductBtn.addEventListener('click', () => {
    productModal.classList.add('hidden');
});

// Generate random barcode strings
formGenBarcode.addEventListener('click', () => {
    let randomCode = '';
    for (let i = 0; i < 12; i++) {
        randomCode += Math.floor(Math.random() * 10);
    }
    formProductBarcode.value = randomCode;
});

// Open product edit modal
window.openEditProductModal = function(id) {
    const p = inventoryProducts.find(prod => prod.id === id);
    if (!p) return;

    formProductId.value = p.id;
    formProductBarcode.value = p.barcode_string;
    formProductBarcode.disabled = false; // Allow modifying barcode too!
    formProductName.value = p.name;
    formProductPrice.value = (p.price / 100).toFixed(2);
    
    productModalTitle.textContent = "Edit Product";
    productModal.classList.remove('hidden');
};

// Form submission for Add / Update
productForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    const id = formProductId.value;
    const barcode_string = formProductBarcode.value.trim();
    const name = formProductName.value.trim();
    const priceVal = parseFloat(formProductPrice.value);

    if (!barcode_string || !name || isNaN(priceVal) || priceVal <= 0) {
        alert('Please fill out all product details correctly.');
        return;
    }

    const payload = { barcode_string, name, price: priceVal };
    const method = id ? 'PUT' : 'POST';
    const url = id ? `/api/products/${id}` : '/api/products';

    try {
        const response = await fetch(url, {
            method: method,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.error || 'Failed to save product details.');
        }

        productModal.classList.add('hidden');
        loadInventory();
        
        // Update product in active POS sales cart if it was modified
        if (id) {
            const numId = parseInt(id);
            cart = cart.map(item => {
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
    }
});

// Delete Product from Database
window.deleteProductFromInventory = async function(id) {
    if (!confirm('Are you sure you want to delete this product from database inventory? This is permanent.')) {
        return;
    }

    try {
        const response = await fetch(`/api/products/${id}`, {
            method: 'DELETE'
        });

        const data = await response.json();
        if (!response.ok) {
            throw new Error(data.error || 'Failed to remove product from database.');
        }

        loadInventory();

        // Also clean up from active checkout cart if that item was present
        const numId = parseInt(id);
        cart = cart.filter(item => item.product.id !== numId);
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
        const response = await fetch('/api/analytics');
        if (!response.ok) {
            throw new Error('Failed to retrieve sales analytics.');
        }
        
        const analytics = await response.json();
        
        // Update KPIs
        kpiToday.textContent = formatCurrency(analytics.kpis.today);
        kpiWeek.textContent = formatCurrency(analytics.kpis.week);
        kpiMonth.textContent = formatCurrency(analytics.kpis.month);
        kpiYear.textContent = formatCurrency(analytics.kpis.year);

        // Render Popular Items Table
        if (analytics.popularItems.length === 0) {
            popularItemsBody.innerHTML = '';
            emptyPopularMessage.classList.remove('hidden');
        } else {
            emptyPopularMessage.classList.add('hidden');
            popularItemsBody.innerHTML = analytics.popularItems.map(item => {
                const name = item.name || 'Unknown Item';
                const formattedRevenue = formatCurrency(item.revenue);
                return `
                    <tr>
                        <td style="font-weight: 500;">${name}</td>
                        <td style="font-weight: 600;"><span class="qty-badge" style="background: rgba(59, 130, 246, 0.15); color: #60a5fa;">${item.times_sold}</span></td>
                        <td style="font-weight: 600;">${formattedRevenue}</td>
                    </tr>
                `;
            }).join('');
        }

        // Draw Line Chart
        renderSalesChart(analytics.chartData.labels, analytics.chartData.data);
    } catch (err) {
        console.error('Analytics load error:', err);
        showError(err.message);
    }
}

// Draw/Update Chart.js line graph
function renderSalesChart(labels, data) {
    const canvas = document.getElementById('sales-chart-canvas');
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    
    // Destroy previous Chart instance to prevent rendering glitches on hover
    if (salesChartInstance) {
        salesChartInstance.destroy();
    }

    // Create a beautiful blue gradient for line chart fill
    const gradient = ctx.createLinearGradient(0, 0, 0, 300);
    gradient.addColorStop(0, 'rgba(59, 130, 246, 0.45)');
    gradient.addColorStop(1, 'rgba(59, 130, 246, 0.0)');

    salesChartInstance = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Sales Revenue (₱)',
                data: data.map(cents => cents / 100), // Convert cents to decimal pesos
                borderColor: '#3b82f6',
                borderWidth: 3,
                backgroundColor: gradient,
                fill: true,
                tension: 0.35, // Smooth curves
                pointBackgroundColor: '#3b82f6',
                pointBorderColor: '#fff',
                pointBorderWidth: 2,
                pointRadius: 5,
                pointHoverRadius: 7
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                },
                tooltip: {
                    backgroundColor: '#0f172a',
                    titleColor: '#f8fafc',
                    bodyColor: '#f8fafc',
                    borderColor: 'rgba(255, 255, 255, 0.1)',
                    borderWidth: 1,
                    padding: 12,
                    displayColors: false,
                    callbacks: {
                        label: function(context) {
                            return 'Revenue: ₱' + context.parsed.y.toFixed(2);
                        }
                    }
                }
            },
            scales: {
                x: {
                    grid: {
                        color: 'rgba(255, 255, 255, 0.05)',
                        borderColor: 'transparent'
                    },
                    ticks: {
                        color: '#94a3b8',
                        font: {
                            family: "'Inter', sans-serif",
                            size: 11
                        }
                    }
                },
                y: {
                    grid: {
                        color: 'rgba(255, 255, 255, 0.05)',
                        borderColor: 'transparent'
                    },
                    ticks: {
                        color: '#94a3b8',
                        font: {
                            family: "'Inter', sans-serif",
                            size: 11
                        },
                        callback: function(value) {
                            return '₱' + value;
                        }
                    }
                }
            }
        }
    });
}

// Initial setup
barcodeInput.focus();
updateCartUI();
