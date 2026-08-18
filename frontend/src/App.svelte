<script>
  import { onMount } from 'svelte';
  import { invoke } from '@tauri-apps/api/core';

  let theme = 'dark';
  let language = 'en';
  let activeSection = 'overview';
  let accent = '#9284ff';
  let uiScale = 1.1;
  let showSettings = false;
  let vaultExists = false;
  let unlocked = false;
  let entries = [];
  let modal = null;
  let masterPassword = '';
  let entryForm = { title: '', username: '', password: '', notes: '' };
  let generatedPassword = '';
  let errorMessage = '';
  let busy = false;

  async function windowAction(action) {
    try {
      const { getCurrentWindow } = await import('@tauri-apps/api/window');
      const appWindow = getCurrentWindow();
      if (action === 'minimize') await appWindow.minimize();
      if (action === 'maximize') await appWindow.toggleMaximize();
      if (action === 'close') await appWindow.close();
    } catch {
      return undefined;
    }
  }

  async function handleTitlebarMouseDown(event) {
    if (event.button !== 0 || event.target.closest('.window-button')) return;
    try {
      const { getCurrentWindow } = await import('@tauri-apps/api/window');
      const appWindow = getCurrentWindow();
      if (event.detail === 2) await appWindow.toggleMaximize();
      else await appWindow.startDragging();
    } catch {
      return undefined;
    }
  }

  function syncVault(status) {
    vaultExists = status.exists;
    unlocked = status.unlocked;
    entries = status.entries || [];
  }

  async function loadVaultStatus() {
    try { syncVault(await invoke('vault_status')); }
    catch (error) { errorMessage = String(error); }
  }

  async function submitVault() {
    errorMessage = '';
    busy = true;
    try {
      const command = vaultExists ? 'unlock_vault' : 'create_vault';
      syncVault(await invoke(command, { password: masterPassword }));
      masterPassword = '';
      modal = null;
    } catch (error) { errorMessage = String(error); }
    finally { busy = false; }
  }

  async function lockVault() {
    await invoke('lock_vault');
    unlocked = false;
    entries = [];
  }

  async function saveEntry() {
    errorMessage = '';
    busy = true;
    try {
      syncVault(await invoke('add_entry', { entry: {
        title: entryForm.title,
        username: entryForm.username || null,
        password: entryForm.password || null,
        notes: entryForm.notes || null,
      }}));
      entryForm = { title: '', username: '', password: '', notes: '' };
      modal = null;
    } catch (error) { errorMessage = String(error); }
    finally { busy = false; }
  }

  async function removeEntry(id) {
    try { syncVault(await invoke('delete_entry', { id })); }
    catch (error) { errorMessage = String(error); }
  }

  async function makePassword() {
    try { generatedPassword = await invoke('generate_password', { length: 20 }); }
    catch (error) { errorMessage = String(error); }
  }

  onMount(loadVaultStatus);

  const copy = {
    en: {
      greeting: 'Good evening, Alex',
      subtitle: 'Your private space is calm and secure.',
      overview: 'Overview',
      vault: 'Vault',
      generator: 'Generator',
      identities: 'Identities',
      recent: 'Recent items',
      seeAll: 'View all',
      quickActions: 'Quick actions',
      addEntry: 'Add entry',
      generate: 'Generate password',
      identity: 'Create identity',
      protected: 'Protected locally',
      items: 'items',
      lastSync: 'Last saved just now',
      welcome: 'Everything important, in one quiet place.',
      secure: 'Your vault is encrypted and locked to this device.',
      settings: 'Settings',
      accentColor: 'Accent color',
      interfaceScale: 'Interface scale',
      comingSoon: 'In development',
      locked: 'Vault locked',
    },
    ru: {
      greeting: 'Добрый вечер, Алекс',
      subtitle: 'Ваше личное пространство спокойно и защищено.',
      overview: 'Обзор',
      vault: 'Хранилище',
      generator: 'Генератор',
      identities: 'Личности',
      recent: 'Последние записи',
      seeAll: 'Все записи',
      quickActions: 'Быстрые действия',
      addEntry: 'Добавить запись',
      generate: 'Создать пароль',
      identity: 'Создать личность',
      protected: 'Защищено локально',
      items: 'записей',
      lastSync: 'Сохранено только что',
      welcome: 'Всё важное — в одном спокойном месте.',
      secure: 'Хранилище зашифровано и привязано к этому устройству.',
      settings: 'Настройки',
      accentColor: 'Акцентный цвет',
      interfaceScale: 'Масштаб интерфейса',
      comingSoon: 'В разработке',
      locked: 'Хранилище заблокировано',
    },
  };

  $: t = copy[language];

  const navItems = [
    { id: 'overview', icon: '⌂', key: 'overview', available: true },
    { id: 'vault', icon: '▣', key: 'vault', available: true },
    { id: 'generator', icon: '✦', key: 'generator', available: true },
    { id: 'identities', icon: '◎', key: 'identities', available: false },
  ];

  function selectSection(item) {
    if (item.available) activeSection = item.id;
  }

</script>

<svelte:head>
  <title>Vaultex — {t.overview}</title>
</svelte:head>

<div class:light={theme === 'light'} class="app-shell" style={`--accent: ${accent}; --ui-scale: ${uiScale}`}>
  <header class="brand-bar" role="toolbar" tabindex="0" aria-label="Window title bar" on:mousedown={handleTitlebarMouseDown}>
    <div class="brand-mark"><span></span></div>
    <div class="brand-name">Vaultex</div>
    <div class="brand-status"><span class:locked={!unlocked} class="status-dot"></span>{unlocked ? t.protected : t.locked}</div>
    <div class="window-controls">
      <button class="window-button" aria-label="Minimize" on:click|stopPropagation={() => windowAction('minimize')}>
        <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2 6h8" /></svg>
      </button>
      <button class="window-button" aria-label="Maximize" on:click|stopPropagation={() => windowAction('maximize')}>
        <svg viewBox="0 0 12 12" aria-hidden="true"><rect x="2.5" y="2.5" width="7" height="7" rx=".6" /></svg>
      </button>
      <button class="window-button close" aria-label="Close" on:click|stopPropagation={() => windowAction('close')}>
        <svg viewBox="0 0 12 12" aria-hidden="true"><path d="m3 3 6 6M9 3 3 9" /></svg>
      </button>
    </div>
  </header>

  <div class="workspace">
    <aside class="sidebar">
      <div class="profile-card">
        <div class="avatar">A</div>
        <div>
          <strong>Alex Morgan</strong>
          <span>Personal vault</span>
        </div>
        <button class="icon-button more-button" aria-label="Lock vault" on:click={lockVault}>⌁</button>
      </div>

      <nav aria-label="Main navigation">
        <div class="nav-label">Workspace</div>
        {#each navItems as item}
          <button class:active={activeSection === item.id} class="nav-item" class:unavailable={!item.available} disabled={!item.available} title={!item.available ? t.comingSoon : ''} on:click={() => selectSection(item)}>
            <span class="nav-icon">{item.icon}</span>
            <span>{t[item.key]}</span>
            {#if item.id === 'vault'}<span class="nav-count">{entries.length}</span>{/if}
            {#if !item.available}<span class="nav-soon">Soon</span>{/if}
          </button>
        {/each}
      </nav>

      <div class="sidebar-bottom">
        <button class="nav-item" class:active={showSettings} on:click={() => showSettings = !showSettings}><span class="nav-icon">⚙</span><span>{t.settings}</span></button>
        <div class="security-note">
          <span class="shield">✦</span>
          <div><strong>AES-256-GCM</strong><small>End-to-end encrypted</small></div>
        </div>
      </div>
    </aside>

    <main class="content">
      <div class="topbar">
        <div class="breadcrumbs"><span>Workspace</span><b>/</b><strong>{t[activeSection] || t.overview}</strong></div>
        <div class="top-actions">
          <button class="round-button" aria-label="Notifications" disabled title={t.comingSoon}>♢<i></i></button>
          <div class="segmented-control" aria-label="Language selection">
            <button class:chosen={language === 'en'} on:click={() => language = 'en'}>EN</button>
            <button class:chosen={language === 'ru'} on:click={() => language = 'ru'}>RU</button>
          </div>
          <button class="theme-toggle" aria-label="Toggle theme" on:click={() => theme = theme === 'dark' ? 'light' : 'dark'}>
            <span class:chosen={theme === 'dark'}>☾</span><span class:chosen={theme === 'light'}>☼</span>
          </button>
        </div>
      </div>

      {#if showSettings}
        <div class="settings-popover">
          <div class="settings-row"><span>{t.accentColor}</span><div class="accent-options">
            {#each ['#9284ff', '#5fa9e8', '#62c49b', '#e5a85f', '#e77c9e'] as color}
              <button class:selected={accent === color} class="accent-option" style={`--option: ${color}`} aria-label={color} on:click={() => accent = color}></button>
            {/each}
          </div></div>
          <div class="settings-row"><span>{t.interfaceScale}</span><div class="scale-options">
            {#each [1, 1.1, 1.2] as scale}
              <button class:selected={uiScale === scale} on:click={() => uiScale = scale}>{Math.round(scale * 100)}%</button>
            {/each}
          </div></div>
        </div>
      {/if}

      {#if activeSection === 'overview'}
        <section class="hero">
          <div>
            <div class="eyebrow"><span class="sparkle">✦</span> {t.welcome}</div>
            <h1>{t.greeting}</h1>
            <p>{t.subtitle}</p>
          </div>
          <div class="hero-orbit"><div class="orbit-ring ring-one"></div><div class="orbit-ring ring-two"></div><div class="orbit-core">✦</div></div>
        </section>

        <section class="stats-grid">
          <button class="stat-card accent-violet" on:click={() => activeSection = 'vault'}><div class="stat-icon">▣</div><span>{t.vault}</span><strong>{entries.length} <small>{t.items}</small></strong><div class="stat-line"></div></button>
          <button class="stat-card accent-blue" on:click={() => activeSection = 'generator'}><div class="stat-icon">✦</div><span>{t.generator}</span><strong>∞ <small>possibilities</small></strong><div class="stat-line"></div></button>
          <article class="stat-card accent-amber"><div class="stat-icon">◷</div><span>{t.lastSync}</span><strong>100% <small>offline</small></strong><div class="stat-line"></div></article>
        </section>

        <section class="lower-grid">
          <article class="panel recent-panel">
            <div class="panel-heading"><div><h2>{t.recent}</h2><span>Protected items from your vault</span></div><button class="text-button" on:click={() => activeSection = 'vault'}>{t.seeAll} <b>↗</b></button></div>
            <div class="recent-list">
              {#if entries.length === 0}<div class="empty-state">{unlocked ? 'Your vault is empty.' : 'Unlock your vault to see entries.'}</div>{/if}
              {#each entries.slice(0, 4) as item, index}
                <div class="recent-item"><div class="item-icon {['violet', 'blue', 'amber'][index % 3]}">◈</div><div class="item-copy"><strong>{item.title}</strong><span>{item.username || 'No username'}</span></div><button class="item-delete" aria-label="Delete entry" on:click={() => removeEntry(item.id)}>×</button></div>
              {/each}
            </div>
          </article>

          <article class="panel actions-panel">
            <div class="panel-heading"><div><h2>{t.quickActions}</h2><span>Keep your workflow moving</span></div></div>
            <div class="action-list">
              <button class="action-button primary" disabled={!unlocked} on:click={() => modal = 'entry'}><span class="action-symbol">＋</span><span><strong>{t.addEntry}</strong><small>Save a new secret</small></span><b>→</b></button>
              <button class="action-button" on:click={() => { modal = 'generator'; makePassword(); }}><span class="action-symbol">✦</span><span><strong>{t.generate}</strong><small>Strong by default</small></span><b>→</b></button>
              <button class="action-button unavailable" disabled title={t.comingSoon}><span class="action-symbol">◎</span><span><strong>{t.identity}</strong><small>{t.comingSoon}</small></span><b>→</b></button>
            </div>
          </article>
        </section>
      {:else if activeSection === 'vault'}
        <section class="page-heading"><div><div class="eyebrow"><span class="sparkle">▣</span> {t.vault}</div><h1>All protected entries</h1><p>Stored locally and encrypted with your master password.</p></div><button class="primary-button" disabled={!unlocked} on:click={() => modal = 'entry'}>＋ {t.addEntry}</button></section>
        <section class="panel vault-list-panel">
          {#if entries.length === 0}<div class="empty-state">{unlocked ? 'Your vault is empty. Add your first entry.' : 'Unlock your vault to see entries.'}</div>{/if}
          {#each entries as item, index}
            <div class="vault-row"><div class="item-icon {['violet', 'blue', 'amber'][index % 3]}">◈</div><div class="item-copy"><strong>{item.title}</strong><span>{item.username || 'No username'}{item.notes ? ` · ${item.notes}` : ''}</span></div><button class="item-delete" aria-label="Delete entry" on:click={() => removeEntry(item.id)}>Delete</button></div>
          {/each}
        </section>
      {:else if activeSection === 'generator'}
        <section class="page-heading"><div><div class="eyebrow"><span class="sparkle">✦</span> {t.generator}</div><h1>Secure password generator</h1><p>Generate passwords using the Rust cryptographic backend.</p></div></section>
        <section class="panel generator-panel"><div class="generated-password large">{generatedPassword || 'Generate a password to begin'}</div><div class="generator-actions"><button class="primary-button" on:click={makePassword}>✦ {t.generate}</button><button class="secondary-button" disabled={!generatedPassword} on:click={() => navigator.clipboard?.writeText(generatedPassword)}>Copy password</button></div></section>
      {:else}
        <section class="unavailable-page"><div class="unavailable-icon">◎</div><h1>{t.identities}</h1><p>{t.comingSoon}. This section will be enabled when identity records are supported by the core.</p><span class="availability-badge">{t.comingSoon}</span></section>
      {/if}
    </main>
  </div>

  {#if !vaultExists || !unlocked}
    <div class="modal-backdrop">
      <form class="modal-card" on:submit|preventDefault={submitVault}>
        <div class="modal-symbol">✦</div>
        <h2>{vaultExists ? 'Unlock your vault' : 'Create your vault'}</h2>
        <p>{vaultExists ? 'Enter your master password to decrypt the local vault.' : 'Your encrypted vault will be stored locally on this device.'}</p>
        <input type="password" bind:value={masterPassword} placeholder="Master password" autocomplete="current-password" />
        {#if errorMessage}<div class="error-message">{errorMessage}</div>{/if}
        <button class="modal-submit" disabled={busy || !masterPassword}>{busy ? 'Working…' : (vaultExists ? 'Unlock vault' : 'Create vault')}</button>
      </form>
    </div>
  {:else if modal === 'entry'}
    <div class="modal-backdrop">
      <form class="modal-card entry-form" on:submit|preventDefault={saveEntry}>
        <button type="button" class="modal-close" aria-label="Close" on:click={() => modal = null}>×</button>
        <h2>{t.addEntry}</h2>
        <input bind:value={entryForm.title} placeholder="Title" required />
        <input bind:value={entryForm.username} placeholder="Username or email" />
        <input bind:value={entryForm.password} placeholder="Password" />
        <textarea bind:value={entryForm.notes} placeholder="Notes"></textarea>
        {#if errorMessage}<div class="error-message">{errorMessage}</div>{/if}
        <button class="modal-submit" disabled={busy || !entryForm.title}>{busy ? 'Saving…' : 'Save entry'}</button>
      </form>
    </div>
  {:else if modal === 'generator'}
    <div class="modal-backdrop">
      <div class="modal-card">
        <button type="button" class="modal-close" aria-label="Close" on:click={() => modal = null}>×</button>
        <h2>{t.generate}</h2>
        <p>A cryptographically random password generated by the Rust core.</p>
        <div class="generated-password">{generatedPassword || 'Generating…'}</div>
        <button class="modal-submit" on:click={makePassword}>Generate again</button>
      </div>
    </div>
  {/if}
</div>
