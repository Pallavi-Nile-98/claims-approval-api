'use strict';

// Demo users. There is no login: the chosen user is sent as the X-User-Id and
// X-User-Role headers on every API call, exactly as described in the README.
const USERS = [
  { id: 'alice', role: 'SUBMITTER' },
  { id: 'carol', role: 'SUBMITTER' },
  { id: 'bob', role: 'APPROVER' },
  { id: 'dana', role: 'APPROVER' },
];
const ROLE_LABELS = { SUBMITTER: 'Submitter', APPROVER: 'Approver' };
const STATUS_LABELS = { DRAFT: 'Draft', SUBMITTED: 'Submitted', APPROVED: 'Approved', REJECTED: 'Rejected' };
const USER_STORAGE_KEY = 'claims-ui.user';
const PAGE_SIZE = 10;

const state = {
  user: USERS[0],
  status: '', // '' = all statuses
  page: 0,
  listRequest: 0, // increments per list load, so a slow old response can't overwrite a newer one
};

const el = (id) => document.getElementById(id);

// ---------- API client ----------

// Carries the server's RFC 9457 problem details (title, detail, errors) to the UI.
class ApiError extends Error {
  constructor(status, problem) {
    super(problem?.detail ?? `Request failed (HTTP ${status})`);
    this.status = status;
    this.problem = problem;
  }
}

// The only place that talks to the API: adds the identity headers to every call and
// turns error responses into ApiError with the server's own message.
// Paths are relative, so the page works wherever the app is served from.
async function api(method, path, body) {
  const headers = { 'X-User-Id': state.user.id, 'X-User-Role': state.user.role };
  const options = { method, headers };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(body);
  }

  let response;
  try {
    response = await fetch(path, options);
  } catch {
    throw new ApiError(0, { title: 'Network error', detail: 'Could not reach the server.' });
  }

  // Problem details arrive as application/problem+json; a load balancer error page is HTML.
  const isJson = (response.headers.get('Content-Type') ?? '').includes('json');
  const data = isJson ? await response.json() : null;
  if (!response.ok) {
    throw new ApiError(response.status, data);
  }
  return data;
}

// ---------- Current user ----------

function userKey(user) {
  return `${user.id}:${user.role}`;
}

// Remember the chosen user across reloads. Storage can be unavailable (e.g. blocked
// in a private window), so failures fall back to the first user instead of breaking.
function restoreUser() {
  try {
    const saved = localStorage.getItem(USER_STORAGE_KEY);
    return USERS.find((user) => userKey(user) === saved) ?? USERS[0];
  } catch {
    return USERS[0];
  }
}

function rememberUser(user) {
  try {
    localStorage.setItem(USER_STORAGE_KEY, userKey(user));
  } catch {
    // Not essential: the page still works, it just won't remember the choice.
  }
}

function renderUserSelect() {
  const select = el('user-select');
  for (const user of USERS) {
    const option = document.createElement('option');
    option.value = userKey(user);
    option.textContent = `${user.id} (${ROLE_LABELS[user.role]})`;
    select.append(option);
  }
  select.value = userKey(state.user);

  select.addEventListener('change', () => {
    state.user = USERS.find((user) => userKey(user) === select.value);
    rememberUser(state.user);
    hideBanner();
    clearFieldErrors();
    onUserChanged();
  });
}

function onUserChanged() {
  // Lets the stylesheet and later sections react to the role.
  document.body.dataset.role = state.user.role;
  // Mirrors the server's rule, which is what actually enforces it.
  el('scope-note').textContent = state.user.role === 'APPROVER'
    ? 'Approvers see every claim.'
    : 'Submitters see only their own claims.';
  state.page = 0;
  loadClaims();
}

// ---------- Create claim ----------

const FORM_FIELDS = ['title', 'amount', 'description']; // same order as on the page

async function createClaim(event) {
  event.preventDefault();
  clearFieldErrors();
  hideBanner();

  // No client-side rules: the API validates and its messages are shown per field.
  const amountText = el('amount').value.trim();
  const body = {
    title: el('title').value.trim(),
    description: el('description').value.trim() || null,
    amount: amountText === '' ? null : Number(amountText),
  };

  setBusy(el('create-btn'), true);
  try {
    const claim = await api('POST', 'api/claims', body);
    el('create-form').reset();
    showBanner(`Claim #${claim.id} created as a draft. Submit it for review when ready.`, 'success');
    // Show the new claim: it is the newest, so it appears first on page 1 of "All".
    state.status = '';
    el('status-filter').value = '';
    state.page = 0;
    await loadClaims();
  } catch (error) {
    if (error.status === 400 && Array.isArray(error.problem?.errors)) {
      showFieldErrors(error.problem.errors);
    } else {
      showError(error);
    }
  } finally {
    setBusy(el('create-btn'), false);
  }
}

function showFieldErrors(errors) {
  for (const { field, message } of errors) {
    if (!FORM_FIELDS.includes(field)) {
      continue;
    }
    el(`${field}-error`).textContent = message;
    el(`${field}-error`).hidden = false;
    el(field).setAttribute('aria-invalid', 'true');
  }
  showBanner('Please fix the highlighted fields.', 'error');
  // Focus the first invalid field in form order (the API's error order is arbitrary).
  FORM_FIELDS.map(el).find((input) => input.getAttribute('aria-invalid') === 'true')?.focus();
}

function clearFieldErrors() {
  for (const field of FORM_FIELDS) {
    el(`${field}-error`).hidden = true;
    el(field).removeAttribute('aria-invalid');
  }
}

function setBusy(button, busy) {
  button.disabled = busy;
  button.setAttribute('aria-busy', String(busy));
}

// ---------- Claims list ----------

async function loadClaims() {
  const request = ++state.listRequest;
  const params = new URLSearchParams({ page: state.page, size: PAGE_SIZE });
  if (state.status) {
    params.set('status', state.status);
  }

  try {
    const page = await api('GET', `api/claims?${params}`);
    if (request !== state.listRequest) {
      return; // the user changed filter or identity meanwhile; a newer load is on its way
    }
    // E.g. the last claim on the last page changed status: step back to a page that exists.
    if (page.content.length === 0 && state.page > 0 && page.totalPages > 0) {
      state.page = page.totalPages - 1;
      return loadClaims();
    }
    renderClaims(page);
  } catch (error) {
    if (request === state.listRequest) {
      showError(error);
    }
  }
}

function renderClaims(page) {
  el('claims-body').replaceChildren(...page.content.map(claimRow));

  const empty = page.content.length === 0;
  el('claims-empty').hidden = !empty;
  if (empty) {
    el('claims-empty').textContent = state.status
      ? `No ${STATUS_LABELS[state.status].toLowerCase()} claims.`
      : 'No claims yet.';
  }

  el('pager').hidden = page.totalElements === 0;
  el('page-info').textContent =
    `Page ${page.page + 1} of ${page.totalPages} · ${page.totalElements} claim${page.totalElements === 1 ? '' : 's'}`;
  el('prev-btn').disabled = page.page === 0;
  el('next-btn').disabled = page.page + 1 >= page.totalPages;
}

function claimRow(claim) {
  const row = document.createElement('tr');
  row.append(
    cell('ID', `#${claim.id}`),
    titleCell(claim),
    cell('Amount', formatAmount(claim.amount), 'num'),
    statusCell(claim.status),
    cell('Submitter', claim.submitterId),
    cell('Approver', claim.approverId ?? '—'),
    cell('Updated', formatDate(claim.updatedAt)),
    actionsCell(claim),
  );
  return row;
}

// ---------- Claim actions ----------

const ACTION_RESULTS = { submit: 'submitted for review', approve: 'approved', reject: 'rejected' };

// Only offers the actions the API would allow. This is a convenience, not security:
// the server checks every rule again and its error is shown if anything changed meanwhile.
function actionsCell(claim) {
  const td = cell('Actions', '', 'actions');
  const { id, role } = state.user;

  if (role === 'SUBMITTER' && claim.status === 'DRAFT' && claim.submitterId === id) {
    td.append(actionButton(claim, 'submit', 'Submit', 'btn-primary'));
  }
  if (role === 'APPROVER' && claim.status === 'SUBMITTED') {
    td.append(
      actionButton(claim, 'approve', 'Approve', 'btn-primary'),
      actionButton(claim, 'reject', 'Reject', 'btn-danger'),
    );
  }
  return td;
}

function actionButton(claim, action, label, style) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = `btn ${style}`;
  button.textContent = label;
  // Screen readers hear which claim the button acts on, not just "Approve".
  button.setAttribute('aria-label', `${label} claim #${claim.id}: ${claim.title}`);
  button.addEventListener('click', () => runAction(claim, action, button));
  return button;
}

async function runAction(claim, action, button) {
  hideBanner();
  // Prevent double clicks while the request is in flight.
  button.closest('td').querySelectorAll('button').forEach((b) => setBusy(b, true));
  try {
    const updated = await api('POST', `api/claims/${claim.id}/${action}`);
    showBanner(`Claim #${updated.id} ${ACTION_RESULTS[action]}.`, 'success');
  } catch (error) {
    // e.g. 409 when another approver acted first: the server's message explains it.
    showError(error);
  }
  // Refresh either way, so the table shows the claim's real current state.
  await loadClaims();
}

// Everything from the API is inserted with textContent, never as HTML, so a claim titled
// "<img src=x onerror=...>" is shown as plain text instead of running (no XSS).
function cell(label, text, className) {
  const td = document.createElement('td');
  td.dataset.label = label; // shown as the column name in the stacked phone layout
  td.textContent = text;
  if (className) {
    td.className = className;
  }
  return td;
}

function titleCell(claim) {
  const td = cell('Title', '');
  const wrapper = document.createElement('div');
  const title = document.createElement('div');
  title.className = 'claim-title';
  title.textContent = claim.title;
  wrapper.append(title);
  if (claim.description) {
    const description = document.createElement('div');
    description.className = 'claim-desc';
    description.textContent = claim.description;
    wrapper.append(description);
  }
  td.append(wrapper);
  return td;
}

function statusCell(status) {
  const td = cell('Status', '');
  const badge = document.createElement('span');
  badge.className = `badge badge-${status.toLowerCase()}`;
  badge.textContent = STATUS_LABELS[status] ?? status;
  td.append(badge);
  return td;
}

// The API has no currency field, so amounts are shown as plain numbers with 2 decimals.
function formatAmount(amount) {
  return Number(amount).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatDate(iso) {
  return new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
}

// ---------- Messages ----------

function showBanner(message, kind = 'info') {
  el('banner-text').textContent = message;
  el('banner').dataset.kind = kind;
  el('banner').hidden = false;
}

function hideBanner() {
  el('banner').hidden = true;
}

function showError(error) {
  const title = error.problem?.title ?? 'Error';
  showBanner(`${title}: ${error.message}`, 'error');
}

// ---------- Start ----------

function init() {
  state.user = restoreUser();
  renderUserSelect();
  el('banner-close').addEventListener('click', hideBanner);
  el('create-form').addEventListener('submit', createClaim);

  el('status-filter').addEventListener('change', (event) => {
    state.status = event.target.value;
    state.page = 0;
    loadClaims();
  });
  el('refresh-btn').addEventListener('click', loadClaims);
  el('prev-btn').addEventListener('click', () => {
    state.page -= 1;
    loadClaims();
  });
  el('next-btn').addEventListener('click', () => {
    state.page += 1;
    loadClaims();
  });

  onUserChanged();
}

init();
