"use strict";

(function () {
  const el = (id) => document.getElementById(id);
  const escape = window.escapeHTML || ((s) =>
    String(s).replace(
      /[&<>"']/g,
      (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c],
    ));
  const format = window.formatCurrency || ((c) => "₱" + (Number(c) / 100).toFixed(2));
  const parse = window.parsePesos || ((val) => {
    if (!/^\d+(\.\d{1,2})?$/.test(val)) return NaN;
    const [whole, fraction = ""] = val.split(".");
    return Number(BigInt(whole) * 100n + BigInt(fraction.padEnd(2, "0")));
  });

  const manilaDateTime = new Intl.DateTimeFormat("en-PH", {
    timeZone: "Asia/Manila",
    dateStyle: "medium",
    timeStyle: "short",
  });

  let debtors = [];
  let summary = { total_debt: 0, active_debtors: 0, total_customers: 0 };
  let currentLedgerDebtor = null;
  let currentStatusFilter = "active"; // "active", "paid", "all"

  async function api(url, options = {}) {
    if (window.apiFetch) return window.apiFetch(url, options);
    return fetch(url, options);
  }

  async function loadSummary() {
    try {
      const res = await api("/api/debts/summary");
      if (!res.ok) return;
      summary = await res.json();
      const totalEl = el("debt-kpi-total");
      const activeCountEl = el("debt-kpi-active-count");
      const totalCustEl = el("debt-kpi-total-customers");
      if (totalEl) totalEl.textContent = format(summary.total_debt);
      if (activeCountEl) activeCountEl.textContent = summary.active_debtors;
      if (totalCustEl) totalCustEl.textContent = summary.total_customers;
    } catch (err) {
      console.error("Debt summary fetch error:", err);
    }
  }

  async function loadDebtors() {
    const statusEl = el("debtors-status");
    if (statusEl) statusEl.textContent = "Loading debtors...";
    try {
      const res = await api("/api/debts/customers");
      if (!res.ok) throw new Error("Failed to load customer list");
      const data = await res.json();
      debtors = Array.isArray(data) ? data : [];
      if (statusEl) statusEl.textContent = "";
      renderTable();
      updateDebtorDropdown();
    } catch (err) {
      if (statusEl) statusEl.textContent = err.message;
      console.error("Debtors fetch error:", err);
    }
  }

  function renderTable() {
    const tbody = el("debtors-table-body");
    const emptyMsg = el("empty-debtors-message");
    const countBadge = el("debtors-count-badge");
    const searchVal = el("debtor-search") ? el("debtor-search").value.trim().toLowerCase() : "";

    // Count statistics for the filter tabs
    const activeCount = debtors.filter((d) => d.balance > 0).length;
    const paidCount = debtors.filter((d) => d.balance <= 0).length;
    const allCount = debtors.length;

    const countActiveEl = el("count-active-debts");
    const countPaidEl = el("count-paid-debts");
    const countAllEl = el("count-all-debts");
    if (countActiveEl) countActiveEl.textContent = activeCount;
    if (countPaidEl) countPaidEl.textContent = paidCount;
    if (countAllEl) countAllEl.textContent = allCount;

    if (!tbody) return;

    let filtered = debtors.filter((d) => {
      if (currentStatusFilter === "active" && d.balance <= 0) return false;
      if (currentStatusFilter === "paid" && d.balance > 0) return false;
      if (!searchVal) return true;
      return d.name.toLowerCase().includes(searchVal);
    });

    if (countBadge) {
      if (currentStatusFilter === "active") {
        countBadge.textContent = `${filtered.length} Active Debtor${filtered.length === 1 ? "" : "s"}`;
      } else if (currentStatusFilter === "paid") {
        countBadge.textContent = `${filtered.length} Fully Paid`;
      } else {
        countBadge.textContent = `${filtered.length} Total Debtor${filtered.length === 1 ? "" : "s"}`;
      }
    }

    if (filtered.length === 0) {
      tbody.innerHTML = "";
      if (emptyMsg) {
        emptyMsg.classList.remove("hidden");
        const titleEl = emptyMsg.querySelector(".empty-cart-title");
        const descEl = emptyMsg.querySelector(".empty-cart-desc");
        if (titleEl) {
          titleEl.textContent =
            currentStatusFilter === "active"
              ? "No active debts found"
              : currentStatusFilter === "paid"
                ? "No fully paid customers found"
                : "No debtors found";
        }
        if (descEl) {
          descEl.textContent = searchVal
            ? "No results matching your search"
            : currentStatusFilter === "active"
              ? "All customer debts are currently settled"
              : "Customers who have settled their accounts will appear here";
        }
      }
      return;
    }

    if (emptyMsg) emptyMsg.classList.add("hidden");

    tbody.innerHTML = filtered
      .map((d) => {
        const hasDebt = d.balance > 0;
        const statusBadge = hasDebt
          ? `<span class="debt-badge badge-active-debt">Active Debt</span>`
          : `<span class="debt-badge badge-settled">Fully Paid</span>`;
        const balanceDisplay = `<strong class="${hasDebt ? "text-danger" : "text-success"}">${format(d.balance)}</strong>`;

        return `
          <tr data-id="${d.id}">
            <td>
              <strong>${escape(d.name)}</strong>
            </td>
            <td style="text-align: right;">${balanceDisplay}</td>
            <td style="text-align: center;">${statusBadge}</td>
            <td style="text-align: right;">
              <div class="action-btn-group">
                <button type="button" class="btn-action-primary" data-action="pay" data-id="${d.id}" ${!hasDebt ? "disabled title='No outstanding balance'" : "title='Record Payment'"}>
                  <svg viewBox="0 0 24 24" aria-hidden="true" style="width: 13px; height: 13px; fill: currentColor;"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>
                  <span>Pay</span>
                </button>
                <button type="button" class="btn-subtle" data-action="add-debt" data-id="${d.id}" title="Add manual debt">
                  <svg viewBox="0 0 24 24" aria-hidden="true" style="width: 13px; height: 13px; fill: currentColor;"><path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/></svg>
                  <span>Debt</span>
                </button>
                <button type="button" class="btn-subtle" data-action="ledger" data-id="${d.id}" title="View Transaction Ledger">
                  <svg viewBox="0 0 24 24" aria-hidden="true" style="width: 13px; height: 13px; fill: currentColor;"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-5 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z"/></svg>
                  <span>Ledger</span>
                </button>
                <button type="button" class="action-btn edit-btn" data-action="edit" data-id="${d.id}" title="Edit customer details">
                  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>
                </button>
                <button type="button" class="action-btn delete-btn-inv" data-action="delete" data-id="${d.id}" ${hasDebt ? "disabled title='Cannot delete customer with unpaid debt balance'" : "title='Delete customer'"}>
                  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
                </button>
              </div>
            </td>
          </tr>
        `;
      })
      .join("");
  }

  function updateDebtorDropdown() {
    const select = el("checkout-debtor-select");
    if (!select) return;
    const currentVal = select.value;
    select.innerHTML = `<option value="">-- Choose customer --</option>` +
      debtors
        .map((d) => `<option value="${d.id}" data-balance="${d.balance}" ${String(d.id) === currentVal ? "selected" : ""}>${escape(d.name)} (Balance: ${format(d.balance)})</option>`)
        .join("");

    const selectedOpt = select.selectedOptions?.[0];
    const balanceInfo = el("selected-debtor-info");
    const balanceVal = el("selected-debtor-balance");
    if (selectedOpt && selectedOpt.dataset.balance !== undefined && balanceInfo && balanceVal) {
      balanceInfo.classList.remove("hidden");
      balanceVal.textContent = format(Number(selectedOpt.dataset.balance));
    } else if (balanceInfo) {
      balanceInfo.classList.add("hidden");
    }
  }

  function openAddDebtorModal() {
    const modal = el("debtor-modal");
    const title = el("debtor-modal-title");
    const form = el("debtor-form");
    const initialGroup = el("form-debtor-initial-group");
    if (!modal || !form) return;

    form.reset();
    el("form-debtor-id").value = "";
    if (title) title.textContent = "Add New Debtor";
    if (initialGroup) initialGroup.style.display = "";
    modal.classList.remove("hidden");
    el("form-debtor-name")?.focus();
  }

  function openEditDebtorModal(id) {
    const d = debtors.find((x) => x.id === id);
    if (!d) return;
    const modal = el("debtor-modal");
    const title = el("debtor-modal-title");
    const form = el("debtor-form");
    const initialGroup = el("form-debtor-initial-group");
    if (!modal || !form) return;

    form.reset();
    el("form-debtor-id").value = d.id;
    el("form-debtor-name").value = d.name || "";
    if (title) title.textContent = "Edit Debtor Name";
    if (initialGroup) initialGroup.style.display = "none";
    modal.classList.remove("hidden");
    el("form-debtor-name")?.focus();
  }

  async function handleSaveDebtor(e) {
    e.preventDefault();
    const id = el("form-debtor-id").value;
    const name = el("form-debtor-name").value.trim();

    if (!name) {
      alert("Customer name is required.");
      return;
    }

    const payload = { name };

    try {
      let res;
      if (id) {
        res = await api(`/api/debts/customers/${encodeURIComponent(id)}`, {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
      } else {
        const initialVal = el("form-debtor-initial") ? el("form-debtor-initial").value.trim() : "";
        if (initialVal) payload.initial_debt = initialVal;
        res = await api("/api/debts/customers", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
      }

      const body = await res.json();
      if (!res.ok) throw new Error(body.error || "Failed to save customer");

      el("debtor-modal").classList.add("hidden");
      await loadSummary();
      await loadDebtors();

      // If user came from POS, auto select new customer
      if (!id && el("checkout-debtor-select")) {
        el("checkout-debtor-select").value = String(body.id);
        const event = new Event("change");
        el("checkout-debtor-select").dispatchEvent(event);
      }
    } catch (err) {
      alert("Error: " + err.message);
    }
  }

  function openPaymentModal(id) {
    const d = debtors.find((x) => x.id === id);
    if (!d) return;
    const modal = el("debt-payment-modal");
    const form = el("debt-payment-form");
    if (!modal || !form) return;

    form.reset();
    el("payment-debtor-id").value = d.id;
    el("payment-debtor-name").textContent = d.name;
    el("payment-current-balance").textContent = format(d.balance);
    const amtInput = el("payment-amount");
    amtInput.max = (d.balance / 100).toFixed(2);
    amtInput.placeholder = (d.balance / 100).toFixed(2);
    modal.classList.remove("hidden");
    amtInput.focus();
  }

  async function handleRecordPayment(e) {
    e.preventDefault();
    const id = el("payment-debtor-id").value;
    const amountVal = el("payment-amount").value.trim();
    const notesVal = el("payment-notes").value.trim();

    if (!amountVal || Number(amountVal) <= 0) {
      alert("Please enter a valid payment amount greater than zero.");
      return;
    }

    try {
      const res = await api(`/api/debts/customers/${encodeURIComponent(id)}/payment`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          amount: amountVal,
          notes: notesVal || undefined,
        }),
      });

      const body = await res.json();
      if (!res.ok) throw new Error(body.error || "Payment recording failed");

      el("debt-payment-modal").classList.add("hidden");
      await loadSummary();
      await loadDebtors();
      if (currentLedgerDebtor && currentLedgerDebtor.id === Number(id)) {
        openLedger(Number(id));
      }
    } catch (err) {
      alert("Payment error: " + err.message);
    }
  }

  function openAddDebtModal(id) {
    const d = debtors.find((x) => x.id === id);
    if (!d) return;
    const modal = el("debt-add-modal");
    const form = el("debt-add-form");
    if (!modal || !form) return;

    form.reset();
    el("add-debt-debtor-id").value = d.id;
    el("add-debt-debtor-name").textContent = d.name;
    el("add-debt-current-balance").textContent = format(d.balance);
    modal.classList.remove("hidden");
    el("add-debt-amount").focus();
  }

  async function handleAddDebt(e) {
    e.preventDefault();
    const id = el("add-debt-debtor-id").value;
    const amountVal = el("add-debt-amount").value.trim();
    const notesVal = el("add-debt-notes").value.trim();

    if (!amountVal || Number(amountVal) <= 0) {
      alert("Please enter a valid debt amount greater than zero.");
      return;
    }
    if (!notesVal) {
      alert("Please provide items or reason for the debt.");
      return;
    }

    try {
      const res = await api(`/api/debts/customers/${encodeURIComponent(id)}/debt`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          amount: amountVal,
          notes: notesVal,
        }),
      });

      const body = await res.json();
      if (!res.ok) throw new Error(body.error || "Adding debt failed");

      el("debt-add-modal").classList.add("hidden");
      await loadSummary();
      await loadDebtors();
      if (currentLedgerDebtor && currentLedgerDebtor.id === Number(id)) {
        openLedger(Number(id));
      }
    } catch (err) {
      alert("Debt recording error: " + err.message);
    }
  }

  async function openLedger(id) {
    const d = debtors.find((x) => x.id === id);
    if (!d) return;
    currentLedgerDebtor = d;

    const modal = el("debt-ledger-modal");
    const title = el("debt-ledger-title");
    const subtitle = el("debt-ledger-subtitle");
    const balance = el("debt-ledger-balance");
    const status = el("debt-ledger-status");
    const list = el("debt-ledger-list");

    if (!modal) return;
    modal.classList.remove("hidden");
    if (title) title.textContent = `Ledger: ${d.name}`;
    if (subtitle) subtitle.textContent = "";
    if (balance) balance.textContent = format(d.balance);
    if (status) status.textContent = "Loading ledger transactions...";
    if (list) list.innerHTML = "";

    try {
      const res = await api(`/api/debts/customers/${encodeURIComponent(id)}/transactions`);
      const body = await res.json();
      if (!res.ok) throw new Error(body.error || "Failed to load transactions");

      if (status) status.textContent = body.entries.length ? "" : "No ledger transactions found.";

      if (list) {
        list.innerHTML = body.entries
          .map((tx) => {
            const isDebt = tx.type === "debt";
            const dateStr = manilaDateTime.format(new Date(tx.timestamp));
            const tag = isDebt
              ? `<span class="ledger-tag tag-debt">+ Utang</span>`
              : `<span class="ledger-tag tag-payment">Payment</span>`;
            const amountStr = isDebt
              ? `<span class="text-danger">+${format(tx.amount)}</span>`
              : `<span class="text-success">-${format(tx.amount)}</span>`;
            const notes = tx.notes ? escape(tx.notes) : "—";
            const saleLink = tx.sale_id
              ? ` <button type="button" class="btn-subtle" data-receipt="${tx.sale_id}" style="padding: 1px 6px; font-size: 0.72rem; margin-left: 6px; cursor: pointer;" title="View Sale Receipt">View Receipt #${tx.sale_id}</button>`
              : "";

            return `
              <li class="${isDebt ? "ledger-entry-debt" : "ledger-entry-payment"}">
                <span class="ledger-date">${dateStr}</span>
                <span>${tag}</span>
                <strong>${amountStr}</strong>
                <span class="ledger-notes">${notes}${saleLink}</span>
                <span class="ledger-after-balance">Bal: ${format(tx.balance_after)}</span>
              </li>
            `;
          })
          .join("");
      }
    } catch (err) {
      if (status) status.textContent = err.message;
    }
  }

  function closeLedger() {
    const modal = el("debt-ledger-modal");
    if (modal) modal.classList.add("hidden");
    currentLedgerDebtor = null;
  }

  async function deleteDebtor(id) {
    const d = debtors.find((x) => x.id === id);
    if (!d) return;
    if (d.balance > 0) {
      alert(`Cannot delete ${d.name}. Outstanding balance of ${format(d.balance)} must be settled first.`);
      return;
    }

    if (!confirm(`Are you sure you want to delete customer record for "${d.name}"?`)) {
      return;
    }

    try {
      const res = await api(`/api/debts/customers/${encodeURIComponent(id)}`, {
        method: "DELETE",
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body.error || "Failed to delete customer");

      await loadSummary();
      await loadDebtors();
      if (currentLedgerDebtor && currentLedgerDebtor.id === id) {
        closeLedger();
      }
    } catch (err) {
      alert("Delete error: " + err.message);
    }
  }

  // --- Wire Up DOM Listeners ---
  const navDebts = el("nav-debts");
  if (navDebts) {
    navDebts.addEventListener("click", () => {
      if (window.showStoreView) window.showStoreView("debts");
      loadSummary();
      loadDebtors();
    });
  }

  const searchInput = el("debtor-search");
  if (searchInput) searchInput.addEventListener("input", renderTable);

  const statusTabs = typeof document.querySelectorAll === "function" ? document.querySelectorAll(".debt-status-tab") : [];
  if (statusTabs && typeof statusTabs.forEach === "function") {
    statusTabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        statusTabs.forEach((t) => t.classList?.remove?.("active"));
        tab.classList?.add?.("active");
        currentStatusFilter = tab.dataset?.status || tab.getAttribute?.("data-status") || "all";
        renderTable();
      });
    });
  }

  const addDebtorBtn = el("add-debtor-btn");
  if (addDebtorBtn) addDebtorBtn.addEventListener("click", openAddDebtorModal);

  const closeDebtorModalBtn = el("close-debtor-modal-btn");
  if (closeDebtorModalBtn) closeDebtorModalBtn.addEventListener("click", () => el("debtor-modal")?.classList.add("hidden"));

  const cancelDebtorBtn = el("cancel-debtor-btn");
  if (cancelDebtorBtn) cancelDebtorBtn.addEventListener("click", () => el("debtor-modal")?.classList.add("hidden"));

  const debtorForm = el("debtor-form");
  if (debtorForm) debtorForm.addEventListener("submit", handleSaveDebtor);

  const closePaymentModalBtn = el("close-payment-modal-btn");
  if (closePaymentModalBtn) closePaymentModalBtn.addEventListener("click", () => el("debt-payment-modal")?.classList.add("hidden"));

  const cancelPaymentBtn = el("cancel-payment-btn");
  if (cancelPaymentBtn) cancelPaymentBtn.addEventListener("click", () => el("debt-payment-modal")?.classList.add("hidden"));

  const payFullBtn = el("pay-full-btn");
  if (payFullBtn) {
    payFullBtn.addEventListener("click", () => {
      const id = Number(el("payment-debtor-id").value);
      const d = debtors.find((x) => x.id === id);
      if (d && d.balance > 0) {
        el("payment-amount").value = (d.balance / 100).toFixed(2);
      }
    });
  }

  const paymentForm = el("debt-payment-form");
  if (paymentForm) paymentForm.addEventListener("submit", handleRecordPayment);

  const closeAddDebtModalBtn = el("close-add-debt-modal-btn");
  if (closeAddDebtModalBtn) closeAddDebtModalBtn.addEventListener("click", () => el("debt-add-modal")?.classList.add("hidden"));

  const cancelAddDebtBtn = el("cancel-add-debt-btn");
  if (cancelAddDebtBtn) cancelAddDebtBtn.addEventListener("click", () => el("debt-add-modal")?.classList.add("hidden"));

  const debtAddForm = el("debt-add-form");
  if (debtAddForm) debtAddForm.addEventListener("submit", handleAddDebt);

  const closeLedgerBtn = el("close-debt-ledger-btn");
  if (closeLedgerBtn) closeLedgerBtn.addEventListener("click", closeLedger);

  const closeLedgerFooterBtn = el("close-debt-ledger-footer-btn");
  if (closeLedgerFooterBtn) closeLedgerFooterBtn.addEventListener("click", closeLedger);

  const ledgerModal = el("debt-ledger-modal");
  if (ledgerModal) {
    ledgerModal.addEventListener("click", (e) => {
      if (e.target === ledgerModal) closeLedger();
    });
  }

  const ledgerList = el("debt-ledger-list");
  if (ledgerList) {
    ledgerList.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-receipt]");
      if (btn && btn.dataset.receipt && window.showHistoricalReceipt) {
        window.showHistoricalReceipt(btn.dataset.receipt);
      }
    });
  }

  const debtorsTableBody = el("debtors-table-body");
  if (debtorsTableBody) {
    debtorsTableBody.addEventListener("click", (e) => {
      const btn = e.target.closest("button[data-action]");
      if (!btn) return;
      const action = btn.dataset.action;
      const id = Number(btn.dataset.id);
      if (action === "pay") openPaymentModal(id);
      else if (action === "add-debt") openAddDebtModal(id);
      else if (action === "ledger") openLedger(id);
      else if (action === "edit") openEditDebtorModal(id);
      else if (action === "delete") deleteDebtor(id);
    });
  }

  // Expose global interface for coordination
  window.debts = {
    reload: async () => {
      await loadSummary();
      await loadDebtors();
    },
    loadDropdown: async () => {
      if (!debtors.length) await loadDebtors();
      else updateDebtorDropdown();
    },
    openAddDebtorModal,
    setStatusFilter: (status) => {
      currentStatusFilter = status;
      renderTable();
    },
    getStatusFilter: () => currentStatusFilter,
  };
})();
