const pages = ['overview', 'notes', 'secrets', 'collections', 'settings'];
const drawer = document.querySelector('#drawer');
const scrim = document.querySelector('#scrim');
const toast = document.querySelector('#toast');
const toastText = document.querySelector('#toastText');
const unlockScreen = document.querySelector('#unlockScreen');
const unlockError = document.querySelector('#unlockError');
const vaultDirectory = document.querySelector('#vaultDirectory');
const vaultPicker = document.querySelector('#vaultPicker');
const vaultSelectButton = document.querySelector('#vaultSelectButton');
const vaultSelectLabel = document.querySelector('#vaultSelectLabel');
const vaultSelectMenu = document.querySelector('#vaultSelectMenu');
let selectedVaultPath = '';
const masterPassword = document.querySelector('#masterPassword');
const createVaultDirectory = document.querySelector('#createVaultDirectory');
const createVaultName = document.querySelector('#createVaultName');
const createMasterPassword = document.querySelector('#createMasterPassword');
const openVaultButton = document.querySelector('#openVaultButton');
const newVaultButton = document.querySelector('#newVaultButton');
const createVaultButton = document.querySelector('#createVaultButton');
const backToOpenButton = document.querySelector('#backToOpenButton');
const openView = document.querySelector('#openView');
const createView = document.querySelector('#createView');
const tauriInvoke = window.__TAURI__?.core?.invoke;

function openDrawer() { drawer.classList.add('open'); scrim.classList.add('open'); }
function closeDrawer() { drawer.classList.remove('open'); scrim.classList.remove('open'); }
function showPage(page) {
  if (!pages.includes(page)) return;
  pages.forEach(name => document.querySelector(`#page-${name}`)?.classList.toggle('active', name === page));
  document.querySelectorAll('[data-page]').forEach(item => item.classList.toggle('active', item.dataset.page === page));
  closeDrawer();
  window.scrollTo({ top: 0, behavior: 'smooth' });
}
function showToast(message) {
  toastText.textContent = message;
  toast.classList.add('show');
  clearTimeout(window.toastTimer);
  window.toastTimer = setTimeout(() => toast.classList.remove('show'), 2600);
}

document.querySelector('#menuButton').addEventListener('click', openDrawer);
document.querySelector('#closeDrawer').addEventListener('click', closeDrawer);
scrim.addEventListener('click', closeDrawer);
document.querySelectorAll('[data-page]').forEach(item => item.addEventListener('click', () => showPage(item.dataset.page)));
document.querySelectorAll('[data-page-link]').forEach(item => item.addEventListener('click', () => showPage(item.dataset.pageLink)));
document.querySelectorAll('[data-action="new"]').forEach(item => item.addEventListener('click', () => showToast('Редактор будет доступен в следующей версии')));
document.querySelectorAll('.reveal').forEach(item => item.addEventListener('click', () => showToast('Подтвердите доступ к секрету')));
async function invoke(command, args = {}) {
  if (!tauriInvoke) throw new Error('Tauri IPC is unavailable');
  return tauriInvoke(command, args);
}

function setLocked(locked) {
  unlockScreen.hidden = !locked;
  document.querySelector('.app-shell').classList.toggle('session-active', !locked);
}

function showUnlockError(message) {
  unlockError.textContent = message;
}

function setUnlockMode(mode) {
  const creating = mode === 'create';
  openView.hidden = creating;
  createView.hidden = !creating;
  showUnlockError('');
  (creating ? createVaultDirectory : vaultDirectory).focus();
}

async function unlockVault(command) {
  showUnlockError('');
  const creating = command === 'vault_create';
  const directory = (creating ? createVaultDirectory : vaultDirectory).value.trim();
  const path = creating ? directory : selectedVaultPath;
  const password = (creating ? createMasterPassword : masterPassword).value;
  const name = creating ? createVaultName.value.trim() : '';
  if (!directory || !path || !password || (creating && !name)) {
    showUnlockError(creating ? 'Укажите папку, название и мастер-пароль.' : 'Выберите папку, хранилище и введите мастер-пароль.');
    return;
  }
  openVaultButton.disabled = true;
  createVaultButton.disabled = true;
  try {
    await invoke(command, creating ? { directory, name, password } : { path, password });
    masterPassword.value = '';
    createMasterPassword.value = '';
    createVaultName.value = '';
    setLocked(false);
    showToast(command === 'vault_create' ? 'Хранилище создано' : 'Хранилище разблокировано');
  } catch (error) {
    showUnlockError(error?.message || 'Не удалось открыть хранилище.');
  } finally {
    openVaultButton.disabled = false;
    createVaultButton.disabled = false;
  }
}

function updateVaultCatalog(catalog) {
  if (catalog.android) {
    document.querySelectorAll('.unlock-field').forEach(field => {
      if (field.querySelector('#vaultDirectory, #createVaultDirectory')) field.hidden = true;
    });
  }
  const directory = catalog.directories[0] || '';
  vaultDirectory.value = directory;
  createVaultDirectory.value = directory;
  vaultSelectMenu.replaceChildren();
  selectedVaultPath = '';
  vaultSelectLabel.textContent = catalog.vaults.length ? 'Выберите хранилище' : 'Хранилища не найдены';
  catalog.vaults.forEach(vault => {
    const option = document.createElement('button');
    option.type = 'button';
    option.className = 'select-option';
    option.textContent = vault.name;
    option.dataset.path = vault.path;
    option.addEventListener('click', () => selectVault(vault.path, vault.name));
    vaultSelectMenu.append(option);
  });
  const remembered = catalog.vaults.find(vault => vault.path === catalog.last_vault);
  selectVault((remembered || catalog.vaults[0])?.path || '', (remembered || catalog.vaults[0])?.name || 'Хранилища не найдены');
}

function selectVault(path, name) {
  selectedVaultPath = path;
  vaultSelectLabel.textContent = name;
  vaultPicker.classList.remove('open');
}

vaultSelectButton.addEventListener('click', () => vaultPicker.classList.toggle('open'));
document.addEventListener('click', event => {
  if (!vaultPicker.contains(event.target)) vaultPicker.classList.remove('open');
});

let catalogTimer;
function refreshCatalog() {
  clearTimeout(catalogTimer);
  catalogTimer = setTimeout(() => {
    invoke('vault_catalog', { directory: vaultDirectory.value.trim() || null })
      .then(updateVaultCatalog)
      .catch(() => {});
  }, 250);
}

document.querySelector('#lockButton').addEventListener('click', async () => {
  if (!tauriInvoke) {
    showToast('Хранилище заблокировано — демо-режим');
    return;
  }
  try {
    await invoke('vault_lock');
    setLocked(true);
    showToast('Хранилище заблокировано');
  } catch (error) {
    showToast(error?.message || 'Не удалось заблокировать хранилище');
  }
});

openVaultButton.addEventListener('click', () => unlockVault('vault_open'));
vaultDirectory.addEventListener('input', refreshCatalog);
newVaultButton.addEventListener('click', () => setUnlockMode('create'));
createVaultButton.addEventListener('click', () => unlockVault('vault_create'));
backToOpenButton.addEventListener('click', () => setUnlockMode('open'));
masterPassword.addEventListener('keydown', event => {
  if (event.key === 'Enter') unlockVault('vault_open');
});
createMasterPassword.addEventListener('keydown', event => {
  if (event.key === 'Enter') unlockVault('vault_create');
});

if (tauriInvoke) {
  invoke('vault_catalog').then(updateVaultCatalog).catch(() => {});
  invoke('vault_status')
    .then(status => setLocked(status.locked))
    .catch(() => setLocked(true));
} else {
  unlockScreen.hidden = true;
  document.querySelector('.app-shell').classList.add('session-active');
}
