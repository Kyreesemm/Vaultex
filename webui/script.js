const pages = ['overview', 'notes', 'secrets', 'collections', 'settings'];
const drawer = document.querySelector('#drawer');
const scrim = document.querySelector('#scrim');
const toast = document.querySelector('#toast');
const toastText = document.querySelector('#toastText');

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
document.querySelector('#lockButton').addEventListener('click', () => showToast('Хранилище заблокировано — демо-режим'));

// Подключение к Rust-команде Tauri не обязательно для веб-просмотра UI.
if (window.__TAURI__?.core?.invoke) {
  window.__TAURI__.core.invoke('vault_status').catch(() => {});
}
