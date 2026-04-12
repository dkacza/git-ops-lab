const BACKEND_URL = window.BACKEND_URL || '';

async function apiFetch(path, options = {}) {
  const res = await fetch(BACKEND_URL + path, options);
  if (res.status === 204) return null;
  return res.json();
}

// --- State ---
let transactions = [];
let limits = {};
let categories = [];

// --- Init ---
async function init() {
  await Promise.all([loadTransactions(), loadLimits(), loadCategories()]);
  await loadSummary();
  renderAll();
}

async function loadTransactions() {
  transactions = await apiFetch('/api/transactions');
}

async function loadLimits() {
  limits = await apiFetch('/api/limits');
}

async function loadCategories() {
  categories = await apiFetch('/api/categories');
  const selects = document.querySelectorAll('.category-select');
  selects.forEach(sel => {
    const current = sel.value;
    sel.innerHTML = categories.map(c => `<option value="${c}">${c}</option>`).join('');
    if (current) sel.value = current;
  });
}

async function loadSummary() {
  const summary = await apiFetch('/api/summary');
  renderSummary(summary);
}

// --- Render ---
function renderAll() {
  renderTransactions();
  renderLimits();
}

function renderSummary(s) {
  document.getElementById('balance').textContent = formatAmount(s.balance);
  document.getElementById('balance').className = 'stat-value ' + (s.balance >= 0 ? 'positive' : 'negative');
  document.getElementById('total-income').textContent = formatAmount(s.totalIncome);
  document.getElementById('total-expenses').textContent = formatAmount(s.totalExpenses);
  document.getElementById('savings-rate').textContent = s.savingsRate.toFixed(1) + '%';

  if (s.largestExpense) {
    document.getElementById('largest-expense').textContent =
      `${s.largestExpense.description} (${formatAmount(s.largestExpense.amount)})`;
  } else {
    document.getElementById('largest-expense').textContent = '—';
  }

  const breakdown = document.getElementById('category-breakdown');
  breakdown.innerHTML = '';
  const entries = Object.entries(s.byCategory).sort((a, b) => b[1] - a[1]);
  entries.forEach(([cat, amount]) => {
    const limit = limits[cat];
    const over = limit && amount > limit;
    breakdown.innerHTML += `
      <div class="breakdown-row ${over ? 'over-limit' : ''}">
        <span class="breakdown-cat">${cat}</span>
        <span class="breakdown-amount">${formatAmount(amount)}${limit ? ` / ${formatAmount(limit)}` : ''}</span>
        ${over ? '<span class="badge-over">Over limit</span>' : ''}
      </div>`;
  });

  const alerts = document.getElementById('overspend-alerts');
  alerts.innerHTML = '';
  if (s.overspend && s.overspend.length > 0) {
    alerts.innerHTML = s.overspend.map(a =>
      `<div class="alert">⚠ ${a.category}: over by ${formatAmount(a.excess)} (${formatAmount(a.spent)} / ${formatAmount(a.limit)})</div>`
    ).join('');
  }
}

function renderTransactions() {
  const tbody = document.getElementById('transactions-body');
  tbody.innerHTML = '';
  if (transactions.length === 0) {
    tbody.innerHTML = '<tr><td colspan="5" class="empty">No transactions yet.</td></tr>';
    return;
  }
  [...transactions].reverse().forEach(t => {
    const row = document.createElement('tr');
    row.innerHTML = `
      <td>${t.date}</td>
      <td>${t.description}</td>
      <td>${t.category}</td>
      <td class="${t.type === 'income' ? 'positive' : 'negative'}">${t.type === 'income' ? '+' : '-'}${formatAmount(t.amount)}</td>
      <td><button class="btn-delete" onclick="deleteTransaction('${t.id}')">✕</button></td>`;
    tbody.appendChild(row);
  });
}

function renderLimits() {
  const container = document.getElementById('limits-list');
  container.innerHTML = '';
  const entries = Object.entries(limits);
  if (entries.length === 0) {
    container.innerHTML = '<p class="empty">No limits set.</p>';
    return;
  }
  entries.forEach(([cat, limit]) => {
    container.innerHTML += `
      <div class="limit-row">
        <span>${cat}</span>
        <span>${formatAmount(limit)}</span>
        <button class="btn-delete" onclick="removeLimit('${cat}')">✕</button>
      </div>`;
  });
}

// --- Actions ---
async function addTransaction(e) {
  e.preventDefault();
  const form = e.target;
  await apiFetch('/api/transactions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      description: form.description.value.trim(),
      amount: parseFloat(form.amount.value),
      category: form.category.value,
      type: form.type.value,
      date: form.date.value,
    }),
  });
  form.reset();
  form.date.value = today();
  await loadTransactions();
  await loadSummary();
  renderAll();
}

async function deleteTransaction(id) {
  await apiFetch(`/api/transactions/${id}`, { method: 'DELETE' });
  await loadTransactions();
  await loadSummary();
  renderAll();
}

async function setLimit(e) {
  e.preventDefault();
  const form = e.target;
  await apiFetch('/api/limits', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      category: form.limitCategory.value,
      limit: parseFloat(form.limitAmount.value),
    }),
  });
  form.reset();
  await loadLimits();
  await loadSummary();
  renderAll();
}

async function removeLimit(category) {
  await apiFetch('/api/limits', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ category, limit: 0 }),
  });
  await loadLimits();
  await loadSummary();
  renderAll();
}

// --- Helpers ---
function formatAmount(n) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(n);
}

function today() {
  return new Date().toISOString().split('T')[0];
}

document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('date').value = today();
  document.getElementById('transaction-form').addEventListener('submit', addTransaction);
  document.getElementById('limit-form').addEventListener('submit', setLimit);
  init();
});
