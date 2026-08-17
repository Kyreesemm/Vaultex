<script>
  let theme = 'dark';
  let language = 'en';
  let activeSection = 'overview';
  let accent = '#9284ff';
  let uiScale = 1.1;
  let showSettings = false;

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
    },
  };

  $: t = copy[language];

  const navItems = [
    { id: 'overview', icon: '⌂', key: 'overview' },
    { id: 'vault', icon: '▣', key: 'vault' },
    { id: 'generator', icon: '✦', key: 'generator' },
    { id: 'identities', icon: '◎', key: 'identities' },
  ];

  const recentItems = [
    { icon: '◈', title: 'Personal email', detail: 'alex@proton.me', color: 'violet' },
    { icon: '◉', title: 'GitHub', detail: 'alex_dev', color: 'blue' },
    { icon: '◇', title: 'Private notes', detail: 'Updated today', color: 'amber' },
  ];
</script>

<svelte:head>
  <title>Vaultex — {t.overview}</title>
</svelte:head>

<div class:light={theme === 'light'} class="app-shell" style={`--accent: ${accent}; --ui-scale: ${uiScale}`}>
  <header class="brand-bar" role="toolbar" tabindex="0" aria-label="Window title bar" on:mousedown={handleTitlebarMouseDown}>
    <div class="brand-mark"><span></span></div>
    <div class="brand-name">Vaultex</div>
    <div class="brand-status"><span class="status-dot"></span>{t.protected}</div>
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
        <button class="icon-button more-button" aria-label="More options">•••</button>
      </div>

      <nav aria-label="Main navigation">
        <div class="nav-label">Workspace</div>
        {#each navItems as item}
          <button class:active={activeSection === item.id} class="nav-item" on:click={() => activeSection = item.id}>
            <span class="nav-icon">{item.icon}</span>
            <span>{t[item.key]}</span>
            {#if item.id === 'vault'}<span class="nav-count">12</span>{/if}
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
          <button class="round-button" aria-label="Notifications">♢<i></i></button>
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

      <section class="hero">
        <div>
          <div class="eyebrow"><span class="sparkle">✦</span> {t.welcome}</div>
          <h1>{t.greeting}</h1>
          <p>{t.subtitle}</p>
        </div>
        <div class="hero-orbit"><div class="orbit-ring ring-one"></div><div class="orbit-ring ring-two"></div><div class="orbit-core">✦</div></div>
      </section>

      <section class="stats-grid">
        <article class="stat-card accent-violet"><div class="stat-icon">▣</div><span>{t.vault}</span><strong>12 <small>{t.items}</small></strong><div class="stat-line"></div></article>
        <article class="stat-card accent-blue"><div class="stat-icon">✦</div><span>{t.generator}</span><strong>∞ <small>possibilities</small></strong><div class="stat-line"></div></article>
        <article class="stat-card accent-amber"><div class="stat-icon">◷</div><span>{t.lastSync}</span><strong>100% <small>offline</small></strong><div class="stat-line"></div></article>
      </section>

      <section class="lower-grid">
        <article class="panel recent-panel">
          <div class="panel-heading"><div><h2>{t.recent}</h2><span>Protected items from your vault</span></div><button class="text-button">{t.seeAll} <b>↗</b></button></div>
          <div class="recent-list">
            {#each recentItems as item}
              <button class="recent-item"><div class="item-icon {item.color}">{item.icon}</div><div class="item-copy"><strong>{item.title}</strong><span>{item.detail}</span></div><span class="item-arrow">›</span></button>
            {/each}
          </div>
        </article>

        <article class="panel actions-panel">
          <div class="panel-heading"><div><h2>{t.quickActions}</h2><span>Keep your workflow moving</span></div></div>
          <div class="action-list">
            <button class="action-button primary"><span class="action-symbol">＋</span><span><strong>{t.addEntry}</strong><small>Save a new secret</small></span><b>→</b></button>
            <button class="action-button"><span class="action-symbol">✦</span><span><strong>{t.generate}</strong><small>Strong by default</small></span><b>→</b></button>
            <button class="action-button"><span class="action-symbol">◎</span><span><strong>{t.identity}</strong><small>Names, aliases and more</small></span><b>→</b></button>
          </div>
        </article>
      </section>
    </main>
  </div>
</div>
