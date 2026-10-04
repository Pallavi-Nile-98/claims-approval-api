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
const USER_STORAGE_KEY = 'claims-ui.user';

const state = {
  user: USERS[0],
};

const el = (id) => document.getElementById(id);

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
    onUserChanged();
  });
}

function onUserChanged() {
  // Lets the stylesheet and later sections react to the role.
  document.body.dataset.role = state.user.role;
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

// ---------- Start ----------

function init() {
  state.user = restoreUser();
  renderUserSelect();
  el('banner-close').addEventListener('click', hideBanner);
  onUserChanged();
}

init();
