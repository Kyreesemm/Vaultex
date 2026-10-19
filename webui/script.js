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
const notesList = document.querySelector('#notesList');
const secretsList = document.querySelector('#secretsList');
const recentRecords = document.querySelector('#recentRecords');
const editor = document.querySelector('#recordEditor');
const titleInput = document.querySelector('#recordTitle');
const contentInput = document.querySelector('#recordContent');
const editorError = document.querySelector('#editorError');
const deleteButton = document.querySelector('#deleteRecordButton');
const MAX_TEXT_BYTES = 1024 * 1024;
let records = [];
let editing = null;
let sessionGeneration = 0;
let operationPending = false;
let activePage = 'overview';

function openDrawer() { drawer.classList.add('open'); scrim.classList.add('open'); }
function closeDrawer() { drawer.classList.remove('open'); scrim.classList.remove('open'); }
function clearSensitiveUi() {
  sessionGeneration += 1;
  records = [];
  editing = null;
  notesList.replaceChildren();
  secretsList.replaceChildren();
  recentRecords.replaceChildren();
  titleInput.value = '';
  contentInput.value = '';
  editorError.textContent = '';
  editor.hidden = true;
  masterPassword.value = '';
  createMasterPassword.value = '';
}
function showPage(page) {
  if (!pages.includes(page)) return;
  activePage = page;
  pages.forEach(name => document.querySelector(`#page-${name}`)?.classList.toggle('active', name === page));
  editor.hidden = true;
  hideRevealedSecrets();
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
async function invoke(command, args = {}) {
  if (!tauriInvoke) throw new Error('IPC_UNAVAILABLE');
  return tauriInvoke(command, args);
}
function errorMessage(error) {
  const code = error?.code || error?.message;
  return ({ invalid_request: 'Проверьте введённые данные.', vault_locked: 'Сначала разблокируйте хранилище.', storage_io: 'Не удалось сохранить файл хранилища.', unlock_failed: 'Не удалось разблокировать хранилище. Проверьте мастер-пароль.', IPC_UNAVAILABLE: 'Операции доступны только в приложении Vaultex.' })[code] || 'Операция не выполнена.';
}
function setLocked(locked) {
  unlockScreen.hidden = !locked;
  document.querySelector('.app-shell').classList.toggle('session-active', !locked);
  document.querySelector('#lockButton').disabled = locked;
  if (locked) clearSensitiveUi();
}
function showUnlockError(message) { unlockError.textContent = message; }
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
  if ((!directory && creating) || (!path && !creating) || !password || (creating && !name)) {
    showUnlockError(creating ? 'Укажите папку, название и мастер-пароль.' : 'Выберите хранилище и введите мастер-пароль.');
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
    await loadRecords();
    showToast(command === 'vault_create' ? 'Хранилище создано' : 'Хранилище разблокировано');
  } catch (error) {
    showUnlockError(errorMessage(error));
    if (!unlockScreen.hidden) setLocked(true);
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
document.addEventListener('click', event => { if (!vaultPicker.contains(event.target)) vaultPicker.classList.remove('open'); });
let catalogTimer;
function refreshCatalog() {
  clearTimeout(catalogTimer);
  catalogTimer = setTimeout(() => invoke('vault_catalog', { directory: vaultDirectory.value.trim() || null }).then(updateVaultCatalog).catch(() => {}), 250);
}
function utf8Encode(value) {
  const bytes = new TextEncoder().encode(value);
  if (bytes.length > MAX_TEXT_BYTES) throw new Error('LIMIT');
  return Array.from(bytes);
}
function decodeRecord(payload) {
  const bytes = Uint8Array.from(payload);
  const parsed = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  if (!parsed || typeof parsed.title !== 'string' || typeof parsed.content !== 'string') throw new Error('FORMAT');
  return parsed;
}
function encodeRecord(title, content) { return utf8Encode(JSON.stringify({ title, content })); }
function makeButton(label, className, action) {
  const button = document.createElement('button');
  button.type = 'button'; button.className = className; button.textContent = label;
  button.addEventListener('click', action);
  return button;
}
function renderRecords() {
  notesList.replaceChildren(); secretsList.replaceChildren(); recentRecords.replaceChildren();
  const notes = records.filter(record => record.kind === 'note');
  const secrets = records.filter(record => record.kind === 'secret');
  document.querySelector('#noteCount').textContent = String(notes.length);
  document.querySelector('#secretCount').textContent = String(secrets.length);
  const query = document.querySelector('#noteSearch').value.trim().toLocaleLowerCase();
  for (const record of notes) {
    let parsed;
    try { parsed = decodeRecord(record.payload); } catch { continue; }
    if (query && !`${parsed.title} ${parsed.content}`.toLocaleLowerCase().includes(query)) continue;
    const card = document.createElement('article'); card.className = 'note-tile';
    const title = document.createElement('h3'); title.textContent = parsed.title || 'Без названия';
    const body = document.createElement('p'); body.textContent = parsed.content.slice(0, 220);
    card.append(title, body, makeButton('Открыть', 'text-button', () => openEditor(record.id)));
    notesList.append(card);
    if (recentRecords.childElementCount < 3) {
      const recent = document.createElement('article'); recent.className = 'entry-card'; recent.append(title.cloneNode(true));
      recent.addEventListener('click', () => { showPage('notes'); openEditor(record.id); });
      recentRecords.append(recent);
    }
  }
  for (const record of secrets) {
    const row = document.createElement('article'); row.className = 'secret-row';
    const title = document.createElement('strong'); title.textContent = `Секрет · ${record.id.slice(0, 8)}`;
    const preview = document.createElement('p'); preview.textContent = 'Содержимое скрыто';
    const revealed = document.createElement('pre'); revealed.hidden = true;
    const reveal = makeButton('Показать', 'reveal', async () => {
      if (!revealed.hidden) { revealed.textContent = ''; revealed.hidden = true; reveal.textContent = 'Показать'; return; }
      const generation = sessionGeneration;
      try {
        const full = await invoke('record_read', { id: record.id });
        if (generation !== sessionGeneration) return;
        revealed.textContent = decodeRecord(full.payload).content;
        revealed.hidden = false; reveal.textContent = 'Скрыть';
      } catch (error) { showToast(errorMessage(error)); }
    });
    row.append(title, preview, reveal, makeButton('Изменить', 'text-button', () => openEditor(record.id)), revealed);
    secretsList.append(row);
  }
  if (!notesList.childElementCount) notesList.textContent = 'Заметок пока нет.';
  if (!secretsList.childElementCount) secretsList.textContent = 'Секретов пока нет.';
  if (!recentRecords.childElementCount) recentRecords.textContent = 'Записей пока нет.';
}
function hideRevealedSecrets() {
  secretsList.querySelectorAll('pre').forEach(item => { item.textContent = ''; item.hidden = true; });
  secretsList.querySelectorAll('.reveal').forEach(item => { item.textContent = 'Показать'; });
}
async function loadRecords() {
  const generation = sessionGeneration;
  const summaries = await invoke('record_list');
  const loaded = [];
  for (const summary of summaries) {
    if (!['note', 'secret'].includes(summary.kind)) continue;
    if (summary.kind === 'secret') { loaded.push(summary); continue; }
    try {
      const full = await invoke('record_read', { id: summary.id });
      if (generation !== sessionGeneration) return;
      loaded.push({ ...summary, payload: full.payload });
    } catch { loaded.push({ ...summary, invalid: true }); }
  }
  if (generation !== sessionGeneration) return;
  records = loaded.filter(record => record.kind !== 'note' || record.payload);
  renderRecords();
}
function openEditor(id = null, kind = 'note') {
  if (!tauriInvoke) { showToast('Записи доступны в приложении Vaultex'); return; }
  editing = id ? records.find(record => record.id === id) : { kind };
  if (!editing) return;
  const generation = sessionGeneration;
  const load = id ? invoke('record_read', { id }) : Promise.resolve(null);
  load.then(full => {
    if (generation !== sessionGeneration || !editing) return;
    let value = { title: '', content: '' };
    try { if (full) value = decodeRecord(full.payload); } catch { editorError.textContent = 'Формат записи не поддерживается; редактирование отменено.'; return; }
    titleInput.value = value.title;
    contentInput.value = value.content;
    document.querySelector('#editorKind').textContent = editing.kind === 'secret' ? 'Секрет' : 'Заметка';
    document.querySelector('#editorHeading').textContent = id ? 'Изменить запись' : 'Новая запись';
    deleteButton.hidden = !id;
    editor.hidden = false;
    editor.scrollIntoView({ behavior: 'smooth', block: 'start' });
    titleInput.focus();
  }).catch(error => showToast(errorMessage(error)));
}
function closeEditor() { editing = null; titleInput.value = ''; contentInput.value = ''; editorError.textContent = ''; editor.hidden = true; }
async function saveRecord() {
  if (operationPending || !editing) return;
  editorError.textContent = '';
  const title = titleInput.value.trim();
  if (!title) { editorError.textContent = 'Укажите название записи.'; return; }
  let payload;
  try { payload = encodeRecord(title, contentInput.value); } catch { editorError.textContent = 'Размер содержимого превышает 1 МиБ.'; return; }
  operationPending = true;
  try {
    if (editing.id) await invoke('record_update', { request: { id: editing.id, payload } });
    else await invoke('record_create', { request: { kind: editing.kind, payload } });
    await invoke('vault_save');
    closeEditor(); await loadRecords(); showToast('Изменения сохранены');
  } catch (error) {
    editorError.textContent = `${errorMessage(error)} Если запись уже внесена в память, повторно её не создавайте; попробуйте блокировку или сохранение ещё раз.`;
  } finally { operationPending = false; }
}
async function deleteRecord() {
  if (operationPending || !editing?.id || !window.confirm('Удалить эту запись?')) return;
  operationPending = true;
  try {
    await invoke('record_delete', { id: editing.id });
    await invoke('vault_save');
    closeEditor(); await loadRecords(); showToast('Запись удалена');
  } catch (error) { editorError.textContent = errorMessage(error); }
  finally { operationPending = false; }
}
document.querySelectorAll('[data-action="new-note"]').forEach(item => item.addEventListener('click', () => openEditor(null, 'note')));
document.querySelectorAll('[data-action="new-secret"]').forEach(item => item.addEventListener('click', () => openEditor(null, 'secret')));
document.querySelector('#saveRecordButton').addEventListener('click', saveRecord);
document.querySelector('#cancelRecordButton').addEventListener('click', closeEditor);
deleteButton.addEventListener('click', deleteRecord);
document.querySelector('#noteSearch').addEventListener('input', renderRecords);
document.querySelector('#lockButton').addEventListener('click', async () => {
  if (!tauriInvoke) { showToast('Хранилище доступно только в приложении Vaultex'); return; }
  if (operationPending) return;
  operationPending = true;
  try {
    if (editor.hidden === false && editing) {
      if (titleInput.value || contentInput.value) {
        const decision = window.confirm('Закрыть редактор и заблокировать хранилище? Несохранённый черновик будет удалён.');
        if (!decision) return;
      }
    }
    clearSensitiveUi();
    await invoke('vault_lock');
    setLocked(true);
    showToast('Хранилище заблокировано');
  } catch (error) {
    showToast(`${errorMessage(error)} Хранилище остаётся открытым.`);
    try { await loadRecords(); } catch { showToast('Хранилище открыто, но список записей не удалось обновить.'); }
  }
  finally { operationPending = false; }
});
openVaultButton.addEventListener('click', () => unlockVault('vault_open'));
vaultDirectory.addEventListener('input', refreshCatalog);
newVaultButton.addEventListener('click', () => setUnlockMode('create'));
createVaultButton.addEventListener('click', () => unlockVault('vault_create'));
backToOpenButton.addEventListener('click', () => setUnlockMode('open'));
masterPassword.addEventListener('keydown', event => { if (event.key === 'Enter') unlockVault('vault_open'); });
createMasterPassword.addEventListener('keydown', event => { if (event.key === 'Enter') unlockVault('vault_create'); });
if (tauriInvoke) {
  invoke('vault_catalog').then(updateVaultCatalog).catch(() => {});
  invoke('vault_status').then(async status => {
    setLocked(status.locked);
    if (!status.locked) await loadRecords();
  }).catch(() => setLocked(true));
} else {
  unlockScreen.hidden = true;
  document.querySelector('.app-shell').classList.add('session-active');
  document.querySelector('#lockButton').disabled = true;
  clearSensitiveUi();
}
