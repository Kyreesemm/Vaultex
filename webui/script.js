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

// Полноэкранный просмотр / Markdown-редактор заметок
const noteFullscreenView = document.querySelector('#noteFullscreenView');
const noteViewBackBtn = document.querySelector('#noteViewBackBtn');
const noteViewSaveBtn = document.querySelector('#noteViewSaveBtn');
const noteViewDeleteBtn = document.querySelector('#noteViewDeleteBtn');
const noteViewTitleInput = document.querySelector('#noteViewTitleInput');
const noteMetaModified = document.querySelector('#noteMetaModified');
const noteMetaWords = document.querySelector('#noteMetaWords');
const noteMetaChars = document.querySelector('#noteMetaChars');
const noteRenderedView = document.querySelector('#noteRenderedView');
const noteLiveEditor = document.querySelector('#noteLiveEditor');
const noteRawTextarea = document.querySelector('#noteRawTextarea');
const noteViewError = document.querySelector('#noteViewError');
const noteSaveStatus = document.querySelector('#noteSaveStatus');
const noteSaveStatusText = document.querySelector('#noteSaveStatusText');
const noteModeTabs = document.querySelectorAll('.mode-tab');

// Модальное окно подтверждения удаления
const deleteConfirmModal = document.querySelector('#deleteConfirmModal');
const deleteModalDescription = document.querySelector('#deleteModalDescription');
const deleteModalCancelBtn = document.querySelector('#deleteModalCancelBtn');
const deleteModalConfirmBtn = document.querySelector('#deleteModalConfirmBtn');

const MAX_TEXT_BYTES = 1024 * 1024;
let records = [];
let editing = null;
let sessionGeneration = 0;
let operationPending = false;
let activePage = 'overview';

// Состояние полноэкранного редактора заметок
let activeNoteId = null;
let activeNoteMode = 'view'; // 'view' | 'live' | 'raw'
let isNoteDirty = false;
let noteBlocks = [];
let activeBlockIndex = -1;
let noteOriginalContent = '';
let deleteTarget = null; // { id, title }

function openDrawer() { drawer.classList.add('open'); scrim.classList.add('open'); }
function closeDrawer() { drawer.classList.remove('open'); scrim.classList.remove('open'); }

function clearSensitiveUi() {
  sessionGeneration += 1;
  records = [];
  editing = null;
  activeNoteId = null;
  isNoteDirty = false;
  noteBlocks = [];
  activeBlockIndex = -1;
  deleteTarget = null;
  notesList.replaceChildren();
  secretsList.replaceChildren();
  recentRecords.replaceChildren();
  titleInput.value = '';
  contentInput.value = '';
  editorError.textContent = '';
  editor.hidden = true;
  if (noteFullscreenView) noteFullscreenView.hidden = true;
  if (deleteConfirmModal) deleteConfirmModal.hidden = true;
  if (noteViewTitleInput) noteViewTitleInput.value = '';
  if (noteRawTextarea) noteRawTextarea.value = '';
  if (noteRenderedView) noteRenderedView.replaceChildren();
  if (noteLiveEditor) noteLiveEditor.replaceChildren();
  masterPassword.value = '';
  createMasterPassword.value = '';
}

function showPage(page) {
  if (!pages.includes(page)) return;
  activePage = page;
  pages.forEach(name => document.querySelector(`#page-${name}`)?.classList.toggle('active', name === page));
  editor.hidden = true;
  if (noteFullscreenView) noteFullscreenView.hidden = true;
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
  return ({
    invalid_request: 'Проверьте введённые данные.',
    vault_locked: 'Сначала разблокируйте хранилище.',
    storage_io: 'Не удалось сохранить файл хранилища.',
    unlock_failed: 'Не удалось разблокировать хранилище. Проверьте мастер-пароль.',
    IPC_UNAVAILABLE: 'Операции доступны только в приложении Vaultex.'
  })[code] || 'Операция не выполнена.';
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
  return {
    title: parsed.title,
    content: parsed.content,
    updatedAt: parsed.updatedAt || parsed.modifiedAt || null
  };
}

function encodeRecord(title, content, updatedAt = new Date().toISOString()) {
  return utf8Encode(JSON.stringify({ title, content, updatedAt }));
}

function formatRecordDate(isoString) {
  if (!isoString) return 'Недавно';
  try {
    const date = new Date(isoString);
    if (isNaN(date.getTime())) return 'Недавно';
    const now = new Date();
    const isToday = date.toDateString() === now.toDateString();
    const timeStr = date.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
    if (isToday) return `Сегодня, ${timeStr}`;
    const yesterday = new Date(now);
    yesterday.setDate(now.getDate() - 1);
    if (date.toDateString() === yesterday.toDateString()) return `Вчера, ${timeStr}`;
    return date.toLocaleDateString('ru-RU', {
      day: 'numeric',
      month: 'short',
      year: date.getFullYear() !== now.getFullYear() ? 'numeric' : undefined,
      hour: '2-digit',
      minute: '2-digit'
    });
  } catch {
    return 'Недавно';
  }
}

function escapeHtml(text) {
  return String(text ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/* ============================================================
   Markdown Parser (Безопасный рендеринг без сторонних библиотек)
   ============================================================ */
function parseInlineMarkdown(text) {
  let escaped = escapeHtml(text);
  // Встроенный код `code`
  escaped = escaped.replace(/`([^`]+)`/g, '<code>$1</code>');
  // Жирный + Курсив: ***text***
  escaped = escaped.replace(/\*\*\*([^*]+)\*\*\*/g, '<strong><em>$1</em></strong>');
  // Жирный: **text** или __text__
  escaped = escaped.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  escaped = escaped.replace(/__([^_]+)__/g, '<strong>$1</strong>');
  // Курсив: *text* или _text_
  escaped = escaped.replace(/\*([^*]+)\*/g, '<em>$1</em>');
  escaped = escaped.replace(/_([^_]+)_/g, '<em>$1</em>');
  // Зачёркнутый: ~~text~~
  escaped = escaped.replace(/~~([^~]+)~~/g, '<del>$1</del>');
  // Ссылки: [text](url) - только безопасные протоколы
  escaped = escaped.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+|mailto:[^\s)]+|#[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');
  return escaped;
}

function renderMarkdown(md) {
  if (!md || !md.trim()) {
    return '<p class="empty-note-placeholder">Заметка пока пуста. Нажмите для редактирования.</p>';
  }

  const lines = md.split('\n');
  let html = '';
  let inCode = false;
  let codeLang = '';
  let codeLines = [];
  let inList = false;
  let listType = null;
  let inTable = false;
  let inBlockquote = false;
  let bqLines = [];

  function flushBlockquote() {
    if (inBlockquote) {
      html += `<blockquote>${renderMarkdown(bqLines.join('\n'))}</blockquote>`;
      inBlockquote = false;
      bqLines = [];
    }
  }

  function flushList() {
    if (inList) {
      html += `</${listType}>`;
      inList = false;
      listType = null;
    }
  }

  function flushTable() {
    if (inTable) {
      html += '</tbody></table>';
      inTable = false;
    }
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Ограждения блоков кода ```
    if (line.trim().startsWith('```')) {
      flushList();
      flushTable();
      flushBlockquote();
      if (inCode) {
        const codeContent = escapeHtml(codeLines.join('\n'));
        const displayLang = escapeHtml(codeLang || 'код');
        html += `<div class="code-block-wrapper"><div class="code-block-header"><span class="code-lang">${displayLang}</span><button class="copy-code-btn" type="button" data-code="${encodeURIComponent(codeLines.join('\n'))}"><span class="material-symbols-rounded">content_copy</span>Копировать</button></div><pre><code class="language-${displayLang}">${codeContent}</code></pre></div>`;
        inCode = false;
        codeLang = '';
        codeLines = [];
      } else {
        inCode = true;
        codeLang = line.trim().slice(3).trim();
        codeLines = [];
      }
      continue;
    }

    if (inCode) {
      codeLines.push(line);
      continue;
    }

    // Цитаты >
    if (/^>\s?/.test(line)) {
      flushList();
      flushTable();
      inBlockquote = true;
      bqLines.push(line.replace(/^>\s?/, ''));
      continue;
    } else {
      flushBlockquote();
    }

    // Горизонтальный разделитель --- или ***
    if (/^(?:---|\*\*\*|___)\s*$/.test(line.trim())) {
      flushList();
      flushTable();
      html += '<hr />';
      continue;
    }

    // Таблицы | col | col |
    if (line.trim().startsWith('|') && line.trim().endsWith('|')) {
      flushList();
      const cells = line.split('|').slice(1, -1).map(c => c.trim());
      const isSeparator = cells.every(c => /^:?-+:?$/.test(c));
      if (isSeparator) {
        continue;
      }
      if (!inTable) {
        inTable = true;
        html += `<table><thead><tr>${cells.map(c => `<th>${parseInlineMarkdown(c)}</th>`).join('')}</tr></thead><tbody>`;
      } else {
        html += `<tr>${cells.map(c => `<td>${parseInlineMarkdown(c)}</td>`).join('')}</tr>`;
      }
      continue;
    } else {
      flushTable();
    }

    // Заголовки # H1 .. ###### H6
    const headingMatch = line.match(/^(#{1,6})\s+(.*)$/);
    if (headingMatch) {
      flushList();
      const level = headingMatch[1].length;
      html += `<h${level}>${parseInlineMarkdown(headingMatch[2])}</h${level}>`;
      continue;
    }

    // Чек-листы / Задачи: - [ ] или - [x]
    const taskMatch = line.match(/^([*-]|\d+\.)\s+\[([ xX])\]\s+(.*)$/);
    if (taskMatch) {
      const checked = taskMatch[2].toLowerCase() === 'x';
      if (!inList || listType !== 'ul') {
        flushList();
        inList = true;
        listType = 'ul';
        html += '<ul class="task-list">';
      }
      html += `<li class="task-item${checked ? ' checked' : ''}"><input type="checkbox" class="task-checkbox"${checked ? ' checked' : ''} disabled /><span>${parseInlineMarkdown(taskMatch[3])}</span></li>`;
      continue;
    }

    // Маркированные списки: - или * или +
    const ulMatch = line.match(/^[-*+]\s+(.*)$/);
    if (ulMatch) {
      if (!inList || listType !== 'ul') {
        flushList();
        inList = true;
        listType = 'ul';
        html += '<ul>';
      }
      html += `<li>${parseInlineMarkdown(ulMatch[1])}</li>`;
      continue;
    }

    // Нумерованные списки: 1.
    const olMatch = line.match(/^\d+\.\s+(.*)$/);
    if (olMatch) {
      if (!inList || listType !== 'ol') {
        flushList();
        inList = true;
        listType = 'ol';
        html += '<ol>';
      }
      html += `<li>${parseInlineMarkdown(olMatch[1])}</li>`;
      continue;
    }

    // Пустая строка
    if (!line.trim()) {
      flushList();
      continue;
    }

    // Обычный абзац
    flushList();
    html += `<p>${parseInlineMarkdown(line)}</p>`;
  }

  flushList();
  flushTable();
  flushBlockquote();

  return html;
}

// Привязка копирования кода
document.addEventListener('click', event => {
  const btn = event.target.closest('.copy-code-btn');
  if (btn && btn.dataset.code) {
    const raw = decodeURIComponent(btn.dataset.code);
    navigator.clipboard.writeText(raw).then(() => showToast('Код скопирован')).catch(() => {});
  }
});

/* ============================================================
   Live Markdown Editor (Obsidian Style Hybrid Engine)
   ============================================================ */
function splitMarkdownIntoBlocks(text) {
  if (!text || !text.trim()) {
    return [{ raw: '', type: 'paragraph' }];
  }
  const lines = text.split('\n');
  const blocks = [];
  let currentLines = [];
  let inCode = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const isCodeFence = line.trim().startsWith('```');

    if (isCodeFence) {
      if (inCode) {
        currentLines.push(line);
        blocks.push({ raw: currentLines.join('\n'), type: 'code' });
        currentLines = [];
        inCode = false;
        continue;
      } else {
        if (currentLines.length > 0) {
          blocks.push({ raw: currentLines.join('\n'), type: 'paragraph' });
          currentLines = [];
        }
        inCode = true;
        currentLines.push(line);
        continue;
      }
    }

    if (inCode) {
      currentLines.push(line);
      continue;
    }

    if (line.trim() === '') {
      if (currentLines.length > 0) {
        blocks.push({ raw: currentLines.join('\n'), type: 'paragraph' });
        currentLines = [];
      }
      continue;
    }

    const isHeading = /^#{1,6}\s+/.test(line);
    const isHr = /^(?:---|\*\*\*|___)\s*$/.test(line.trim());
    if (isHeading || isHr) {
      if (currentLines.length > 0) {
        blocks.push({ raw: currentLines.join('\n'), type: 'paragraph' });
        currentLines = [];
      }
      blocks.push({ raw: line, type: isHeading ? 'heading' : 'hr' });
      continue;
    }

    currentLines.push(line);
  }

  if (currentLines.length > 0) {
    blocks.push({ raw: currentLines.join('\n'), type: inCode ? 'code' : 'paragraph' });
  }

  if (blocks.length === 0) {
    blocks.push({ raw: '', type: 'paragraph' });
  }

  return blocks;
}

function reconstructContentFromBlocks() {
  return noteBlocks.map(b => b.raw).join('\n\n');
}

function autoResizeTextarea(el) {
  el.style.height = 'auto';
  el.style.height = `${Math.max(el.scrollHeight, 40)}px`;
}

function renderLiveEditor() {
  noteLiveEditor.replaceChildren();

  noteBlocks.forEach((block, index) => {
    const blockWrapper = document.createElement('div');
    blockWrapper.className = 'live-block';
    blockWrapper.dataset.index = String(index);

    if (index === activeBlockIndex) {
      const textarea = document.createElement('textarea');
      textarea.className = 'live-block-input';
      textarea.value = block.raw;
      textarea.rows = 1;
      textarea.spellcheck = false;

      textarea.addEventListener('input', () => {
        block.raw = textarea.value;
        autoResizeTextarea(textarea);
        markNoteDirty(true);
        updateNoteMetaStats();
      });

      textarea.addEventListener('keydown', event => {
        if (event.key === 'Enter' && !event.shiftKey && block.type !== 'code') {
          event.preventDefault();
          const start = textarea.selectionStart;
          const end = textarea.selectionEnd;
          const before = textarea.value.slice(0, start);
          const after = textarea.value.slice(end);

          block.raw = before;
          noteBlocks.splice(index + 1, 0, { raw: after, type: 'paragraph' });
          activeBlockIndex = index + 1;
          markNoteDirty(true);
          renderLiveEditor();
          return;
        }

        if (event.key === 'Backspace' && textarea.selectionStart === 0 && textarea.selectionEnd === 0) {
          if (textarea.value.trim() === '' && noteBlocks.length > 1) {
            event.preventDefault();
            noteBlocks.splice(index, 1);
            activeBlockIndex = Math.max(0, index - 1);
            markNoteDirty(true);
            renderLiveEditor();
            return;
          }
          if (index > 0 && textarea.value.trim() !== '') {
            event.preventDefault();
            const prevBlock = noteBlocks[index - 1];
            const prevLen = prevBlock.raw.length;
            prevBlock.raw = `${prevBlock.raw}\n${textarea.value}`;
            noteBlocks.splice(index, 1);
            activeBlockIndex = index - 1;
            markNoteDirty(true);
            renderLiveEditor();
            setTimeout(() => {
              const activeInput = noteLiveEditor.querySelector('.live-block-input');
              if (activeInput) {
                activeInput.focus();
                activeInput.setSelectionRange(prevLen, prevLen);
              }
            }, 0);
            return;
          }
        }

        if (event.key === 'ArrowUp' && textarea.selectionStart === 0 && index > 0) {
          event.preventDefault();
          activeBlockIndex = index - 1;
          renderLiveEditor();
          return;
        }

        if (event.key === 'ArrowDown' && textarea.selectionEnd === textarea.value.length && index < noteBlocks.length - 1) {
          event.preventDefault();
          activeBlockIndex = index + 1;
          renderLiveEditor();
          return;
        }
      });

      blockWrapper.append(textarea);
      noteLiveEditor.append(blockWrapper);

      setTimeout(() => {
        autoResizeTextarea(textarea);
        textarea.focus();
      }, 0);
    } else {
      const renderedDiv = document.createElement('div');
      renderedDiv.className = 'live-block-rendered';
      if (!block.raw.trim()) {
        renderedDiv.classList.add('empty');
        renderedDiv.textContent = 'Нажмите здесь, чтобы добавить текст...';
      } else {
        renderedDiv.innerHTML = renderMarkdown(block.raw);
      }

      renderedDiv.addEventListener('click', () => {
        activeBlockIndex = index;
        renderLiveEditor();
      });

      blockWrapper.append(renderedDiv);
      noteLiveEditor.append(blockWrapper);
    }
  });
}

function updateNoteMetaStats() {
  let content = '';
  if (activeNoteMode === 'live') {
    content = reconstructContentFromBlocks();
  } else if (activeNoteMode === 'raw') {
    content = noteRawTextarea.value;
  } else {
    content = noteOriginalContent;
  }
  const chars = content.length;
  const words = (content.trim().match(/\S+/g) || []).length;
  noteMetaChars.textContent = `${chars} симв.`;
  noteMetaWords.textContent = `${words} слов`;
}

function setNoteMode(mode) {
  if (!['view', 'live', 'raw'].includes(mode)) return;

  // Синхронизация текущего содержимого перед переключением
  let currentContent = '';
  if (activeNoteMode === 'live') {
    currentContent = reconstructContentFromBlocks();
  } else if (activeNoteMode === 'raw') {
    currentContent = noteRawTextarea.value;
  } else {
    currentContent = noteOriginalContent;
  }

  activeNoteMode = mode;
  noteOriginalContent = currentContent;

  noteModeTabs.forEach(tab => {
    tab.classList.toggle('active', tab.dataset.mode === mode);
  });

  noteRenderedView.hidden = mode !== 'view';
  noteLiveEditor.hidden = mode !== 'live';
  noteRawTextarea.hidden = mode !== 'raw';

  if (mode === 'view') {
    noteRenderedView.innerHTML = renderMarkdown(currentContent);
  } else if (mode === 'live') {
    noteBlocks = splitMarkdownIntoBlocks(currentContent);
    activeBlockIndex = noteBlocks.length > 0 ? 0 : -1;
    renderLiveEditor();
  } else if (mode === 'raw') {
    noteRawTextarea.value = currentContent;
    noteRawTextarea.focus();
  }

  updateNoteMetaStats();
}

function markNoteDirty(dirty) {
  isNoteDirty = dirty;
  noteSaveStatus.classList.toggle('dirty', dirty);
  noteSaveStatusText.textContent = dirty ? 'Не сохранено' : 'Сохранено';
}

noteModeTabs.forEach(tab => {
  tab.addEventListener('click', () => setNoteMode(tab.dataset.mode));
});

noteRenderedView.addEventListener('dblclick', () => setNoteMode('live'));

noteViewTitleInput.addEventListener('input', () => {
  markNoteDirty(true);
});

noteRawTextarea.addEventListener('input', () => {
  markNoteDirty(true);
  updateNoteMetaStats();
});

/* ============================================================
   Fullscreen Note View Lifecycle
   ============================================================ */
async function openNoteView(id = null) {
  if (!tauriInvoke) {
    showToast('Заметки доступны в приложении Vaultex');
    return;
  }

  noteViewError.textContent = '';
  activeNoteId = id;
  isNoteDirty = false;
  markNoteDirty(false);

  if (!id) {
    // Новая заметка
    noteViewTitleInput.value = '';
    noteOriginalContent = '';
    noteBlocks = [{ raw: '', type: 'paragraph' }];
    activeBlockIndex = 0;
    noteMetaModified.textContent = 'Новая запись';
    setNoteMode('live');
    noteFullscreenView.hidden = false;
    setTimeout(() => noteViewTitleInput.focus(), 50);
    return;
  }

  // Открытие существующей заметки
  const generation = sessionGeneration;
  try {
    const full = await invoke('record_read', { id });
    if (generation !== sessionGeneration) return;

    let parsed;
    try {
      parsed = decodeRecord(full.payload);
    } catch {
      showToast('Не удалось разобрать формат заметки');
      return;
    }

    noteViewTitleInput.value = parsed.title || '';
    noteOriginalContent = parsed.content || '';
    noteBlocks = splitMarkdownIntoBlocks(parsed.content || '');
    activeBlockIndex = -1;
    noteMetaModified.textContent = formatRecordDate(parsed.updatedAt);

    setNoteMode('view');
    noteFullscreenView.hidden = false;
  } catch (error) {
    showToast(errorMessage(error));
  }
}

function closeNoteView(force = false) {
  if (!force && isNoteDirty) {
    const confirmLeave = window.confirm('У вас есть несохранённые изменения. Закрыть заметку без сохранения?');
    if (!confirmLeave) return;
  }
  activeNoteId = null;
  isNoteDirty = false;
  noteFullscreenView.hidden = true;
  noteViewTitleInput.value = '';
  noteOriginalContent = '';
  noteBlocks = [];
  activeBlockIndex = -1;
  noteRenderedView.replaceChildren();
  noteLiveEditor.replaceChildren();
  noteRawTextarea.value = '';
}

noteViewBackBtn.addEventListener('click', () => closeNoteView());

async function saveCurrentNote() {
  if (operationPending) return;
  noteViewError.textContent = '';

  const title = noteViewTitleInput.value.trim();
  if (!title) {
    noteViewError.textContent = 'Укажите название заметки.';
    noteViewTitleInput.focus();
    return;
  }

  let content = '';
  if (activeNoteMode === 'live') {
    content = reconstructContentFromBlocks();
  } else if (activeNoteMode === 'raw') {
    content = noteRawTextarea.value;
  } else {
    content = noteOriginalContent;
  }

  let payload;
  try {
    payload = encodeRecord(title, content, new Date().toISOString());
  } catch {
    noteViewError.textContent = 'Размер заметки превышает лимит (1 МиБ).';
    return;
  }

  operationPending = true;
  noteViewSaveBtn.disabled = true;

  try {
    if (activeNoteId) {
      await invoke('record_update', { request: { id: activeNoteId, payload } });
    } else {
      const newId = await invoke('record_create', { request: { kind: 'note', payload } });
      activeNoteId = newId;
    }
    await invoke('vault_save');

    noteOriginalContent = content;
    markNoteDirty(false);
    noteMetaModified.textContent = formatRecordDate(new Date().toISOString());
    showToast('Заметка сохранена');
    await loadRecords();
  } catch (error) {
    noteViewError.textContent = errorMessage(error);
  } finally {
    operationPending = false;
    noteViewSaveBtn.disabled = false;
  }
}

noteViewSaveBtn.addEventListener('click', saveCurrentNote);

noteViewDeleteBtn.addEventListener('click', () => {
  if (activeNoteId) {
    openDeleteModal(activeNoteId, noteViewTitleInput.value.trim() || 'Без названия');
  } else {
    closeNoteView(true);
  }
});

// Горячая клавиша Ctrl+S / Cmd+S для сохранения
window.addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
    if (!noteFullscreenView.hidden) {
      event.preventDefault();
      saveCurrentNote();
    }
  }
  if (event.key === 'Escape') {
    if (!deleteConfirmModal.hidden) {
      closeDeleteModal();
    }
  }
});

/* ============================================================
   Модальное окно подтверждения удаления
   ============================================================ */
function openDeleteModal(id, title) {
  deleteTarget = { id, title };
  deleteModalDescription.textContent = `Вы действительно хотите удалить заметку «${title || 'Без названия'}»? Данные будут безвозвратно удалены из зашифрованного хранилища.`;
  deleteConfirmModal.hidden = false;
}

function closeDeleteModal() {
  deleteTarget = null;
  deleteConfirmModal.hidden = true;
}

deleteModalCancelBtn.addEventListener('click', closeDeleteModal);
deleteConfirmModal.addEventListener('click', event => {
  if (event.target === deleteConfirmModal) closeDeleteModal();
});

deleteModalConfirmBtn.addEventListener('click', async () => {
  if (!deleteTarget?.id || operationPending) return;
  const targetId = deleteTarget.id;
  operationPending = true;
  deleteModalConfirmBtn.disabled = true;

  try {
    await invoke('record_delete', { id: targetId });
    await invoke('vault_save');
    closeDeleteModal();
    if (activeNoteId === targetId) {
      closeNoteView(true);
    }
    await loadRecords();
    showToast('Заметка удалена');
  } catch (error) {
    showToast(errorMessage(error));
  } finally {
    operationPending = false;
    deleteModalConfirmBtn.disabled = false;
  }
});

/* ============================================================
   Отображение карточек и списков
   ============================================================ */
function renderRecords() {
  notesList.replaceChildren();
  secretsList.replaceChildren();
  recentRecords.replaceChildren();

  const notes = records.filter(record => record.kind === 'note');
  const secrets = records.filter(record => record.kind === 'secret');
  document.querySelector('#noteCount').textContent = String(notes.length);
  document.querySelector('#secretCount').textContent = String(secrets.length);

  const query = document.querySelector('#noteSearch').value.trim().toLocaleLowerCase();

  for (const record of notes) {
    let parsed;
    try {
      parsed = decodeRecord(record.payload);
    } catch {
      continue;
    }

    if (query && !`${parsed.title} ${parsed.content}`.toLocaleLowerCase().includes(query)) {
      continue;
    }

    // Современная карточка заметки
    const card = document.createElement('article');
    card.className = 'note-card';

    // Заголовок карточки и кнопка удаления
    const header = document.createElement('div');
    header.className = 'note-card-header';

    const titleGroup = document.createElement('div');
    titleGroup.className = 'note-card-title-group';

    const icon = document.createElement('span');
    icon.className = 'material-symbols-rounded note-card-icon';
    icon.textContent = 'description';

    const titleEl = document.createElement('h3');
    titleEl.className = 'note-card-title';
    titleEl.textContent = parsed.title || 'Без названия';

    titleGroup.append(icon, titleEl);

    const deleteBtn = document.createElement('button');
    deleteBtn.type = 'button';
    deleteBtn.className = 'note-card-delete-btn';
    deleteBtn.title = 'Удалить заметку';
    deleteBtn.setAttribute('aria-label', 'Удалить заметку');
    deleteBtn.innerHTML = '<span class="material-symbols-rounded">delete</span>';
    deleteBtn.addEventListener('click', event => {
      event.stopPropagation();
      openDeleteModal(record.id, parsed.title);
    });

    header.append(titleGroup, deleteBtn);

    // Размытое превью содержимого для конфиденциальности
    const body = document.createElement('div');
    body.className = 'note-card-body';

    const blurredSnippet = document.createElement('div');
    blurredSnippet.className = 'note-snippet-blurred';
    const plainSnippet = parsed.content.replace(/[#*`~_>\-[\]|]/g, ' ').replace(/\s+/g, ' ').trim();
    blurredSnippet.textContent = plainSnippet.slice(0, 160) || 'Нет дополнительного текста';

    const snippetFade = document.createElement('div');
    snippetFade.className = 'note-snippet-fade';

    body.append(blurredSnippet, snippetFade);

    // Подвал карточки с датой изменения
    const footer = document.createElement('div');
    footer.className = 'note-card-footer';

    const meta = document.createElement('div');
    meta.className = 'note-card-meta';
    meta.innerHTML = `<span class="material-symbols-rounded">schedule</span><span>${formatRecordDate(parsed.updatedAt)}</span>`;

    const action = document.createElement('div');
    action.className = 'note-card-action';
    action.innerHTML = '<span>Открыть</span><span class="material-symbols-rounded">arrow_forward</span>';

    footer.append(meta, action);

    card.append(header, body, footer);
    card.addEventListener('click', () => openNoteView(record.id));
    notesList.append(card);

    if (recentRecords.childElementCount < 3) {
      const recent = document.createElement('article');
      recent.className = 'entry-card';

      const recentIcon = document.createElement('div');
      recentIcon.className = 'entry-symbol purple';
      recentIcon.innerHTML = '<span class="material-symbols-rounded">description</span>';

      const recentCopy = document.createElement('div');
      recentCopy.className = 'entry-copy';
      const recentTitle = document.createElement('strong');
      recentTitle.textContent = parsed.title || 'Без названия';
      const recentDate = document.createElement('p');
      recentDate.textContent = `Изменено: ${formatRecordDate(parsed.updatedAt)}`;
      recentCopy.append(recentTitle, recentDate);

      const recentArrow = document.createElement('span');
      recentArrow.className = 'material-symbols-rounded more';
      recentArrow.textContent = 'arrow_forward';

      recent.append(recentIcon, recentCopy, recentArrow);
      recent.addEventListener('click', () => openNoteView(record.id));
      recentRecords.append(recent);
    }
  }

  for (const record of secrets) {
    const row = document.createElement('article');
    row.className = 'secret-row';
    const title = document.createElement('strong');
    title.textContent = `Секрет · ${record.id.slice(0, 8)}`;
    const preview = document.createElement('p');
    preview.textContent = 'Содержимое скрыто';
    const revealed = document.createElement('pre');
    revealed.hidden = true;
    const reveal = document.createElement('button');
    reveal.type = 'button';
    reveal.className = 'reveal';
    reveal.textContent = 'Показать';
    reveal.addEventListener('click', async () => {
      if (!revealed.hidden) {
        revealed.textContent = '';
        revealed.hidden = true;
        reveal.textContent = 'Показать';
        return;
      }
      const generation = sessionGeneration;
      try {
        const full = await invoke('record_read', { id: record.id });
        if (generation !== sessionGeneration) return;
        revealed.textContent = decodeRecord(full.payload).content;
        revealed.hidden = false;
        reveal.textContent = 'Скрыть';
      } catch (error) {
        showToast(errorMessage(error));
      }
    });

    const editBtn = document.createElement('button');
    editBtn.type = 'button';
    editBtn.className = 'text-button';
    editBtn.textContent = 'Изменить';
    editBtn.addEventListener('click', () => openEditor(record.id, 'secret'));

    row.append(title, preview, reveal, editBtn, revealed);
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
    } catch {
      loaded.push({ ...summary, invalid: true });
    }
  }
  if (generation !== sessionGeneration) return;
  records = loaded.filter(record => record.kind !== 'note' || record.payload);
  renderRecords();
}

/* ============================================================
   Редактор для секретов (Record Editor)
   ============================================================ */
function openEditor(id = null, kind = 'secret') {
  if (!tauriInvoke) { showToast('Записи доступны в приложении Vaultex'); return; }
  if (kind === 'note') {
    openNoteView(id);
    return;
  }
  editing = id ? records.find(record => record.id === id) : { kind };
  if (!editing) return;
  const generation = sessionGeneration;
  const load = id ? invoke('record_read', { id }) : Promise.resolve(null);
  load.then(full => {
    if (generation !== sessionGeneration || !editing) return;
    let value = { title: '', content: '' };
    try {
      if (full) value = decodeRecord(full.payload);
    } catch {
      editorError.textContent = 'Формат записи не поддерживается; редактирование отменено.';
      return;
    }
    titleInput.value = value.title;
    contentInput.value = value.content;
    document.querySelector('#editorKind').textContent = 'Секрет';
    document.querySelector('#editorHeading').textContent = id ? 'Изменить секрет' : 'Новый секрет';
    deleteButton.hidden = !id;
    editor.hidden = false;
    editor.scrollIntoView({ behavior: 'smooth', block: 'start' });
    titleInput.focus();
  }).catch(error => showToast(errorMessage(error)));
}

function closeEditor() {
  editing = null;
  titleInput.value = '';
  contentInput.value = '';
  editorError.textContent = '';
  editor.hidden = true;
}

async function saveRecord() {
  if (operationPending || !editing) return;
  editorError.textContent = '';
  const title = titleInput.value.trim();
  if (!title) { editorError.textContent = 'Укажите название записи.'; return; }
  let payload;
  try {
    payload = encodeRecord(title, contentInput.value);
  } catch {
    editorError.textContent = 'Размер содержимого превышает 1 МиБ.';
    return;
  }
  operationPending = true;
  try {
    if (editing.id) await invoke('record_update', { request: { id: editing.id, payload } });
    else await invoke('record_create', { request: { kind: editing.kind, payload } });
    await invoke('vault_save');
    closeEditor();
    await loadRecords();
    showToast('Изменения сохранены');
  } catch (error) {
    editorError.textContent = `${errorMessage(error)} Попробуйте ещё раз.`;
  } finally {
    operationPending = false;
  }
}

async function deleteRecord() {
  if (operationPending || !editing?.id || !window.confirm('Удалить эту запись?')) return;
  operationPending = true;
  try {
    await invoke('record_delete', { id: editing.id });
    await invoke('vault_save');
    closeEditor();
    await loadRecords();
    showToast('Запись удалена');
  } catch (error) {
    editorError.textContent = errorMessage(error);
  } finally {
    operationPending = false;
  }
}

document.querySelectorAll('[data-action="new-note"]').forEach(item => item.addEventListener('click', () => openNoteView(null)));
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
    if (!noteFullscreenView.hidden && isNoteDirty) {
      const decision = window.confirm('Закрыть редактор и заблокировать хранилище? Несохранённые изменения будут утеряны.');
      if (!decision) return;
    } else if (editor.hidden === false && editing && (titleInput.value || contentInput.value)) {
      const decision = window.confirm('Закрыть редактор и заблокировать хранилище? Несохранённый черновик будет удалён.');
      if (!decision) return;
    }
    clearSensitiveUi();
    await invoke('vault_lock');
    setLocked(true);
    showToast('Хранилище заблокировано');
  } catch (error) {
    showToast(`${errorMessage(error)} Хранилище остаётся открытым.`);
    try { await loadRecords(); } catch { showToast('Хранилище открыто, но список записей не удалось обновить.'); }
  } finally {
    operationPending = false;
  }
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
