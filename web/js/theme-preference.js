/* Persisted light/dark theme preference shared by every portal. */
(function () {
  'use strict';

  const storageKey = 'sentinel-link-theme';
  const root = document.documentElement;
  const prefersDark = window.matchMedia?.('(prefers-color-scheme: dark)');

  function savedTheme() {
    try {
      const value = window.localStorage.getItem(storageKey);
      return value === 'light' || value === 'dark' ? value : null;
    } catch (_) {
      return null;
    }
  }

  function currentTheme() {
    return root.dataset.theme === 'dark' ? 'dark' : 'light';
  }

  function updateButtons(theme) {
    document.querySelectorAll('[data-theme-toggle]').forEach((button) => {
      const dark = theme === 'dark';
      const label = dark ? 'Light mode' : 'Dark mode';
      button.setAttribute('aria-label', `Switch to ${label.toLowerCase()}`);
      button.setAttribute('title', `Switch to ${label.toLowerCase()}`);
      button.setAttribute('aria-pressed', dark ? 'true' : 'false');
      const icon = button.querySelector('.sl-theme-toggle-icon');
      const text = button.querySelector('.sl-theme-toggle-label');
      if (icon) icon.textContent = dark ? '☀' : '☾';
      if (text) text.textContent = label;
    });
  }

  function apply(theme, persist) {
    const next = theme === 'dark' ? 'dark' : 'light';
    root.dataset.theme = next;
    root.style.colorScheme = next;
    if (document.body) document.body.dataset.theme = next;
    if (persist) {
      try { window.localStorage.setItem(storageKey, next); } catch (_) { /* storage is optional */ }
    }
    updateButtons(next);
    window.dispatchEvent(new CustomEvent('sentinel-theme-change', { detail: { theme: next } }));
  }

  function createToggle() {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'sl-theme-toggle';
    button.dataset.themeToggle = '';
    button.innerHTML = '<span class="sl-theme-toggle-icon" aria-hidden="true"></span><span class="sl-theme-toggle-label"></span>';
    button.addEventListener('click', () => apply(currentTheme() === 'dark' ? 'light' : 'dark', true));
    return button;
  }

  function mount() {
    const hosts = [...document.querySelectorAll('[data-theme-toggle-host]')];
    if (!hosts.length) {
      const fallback = document.querySelector('.ax-topbar-right, .ix-shell-actions, .download-nav');
      if (fallback) hosts.push(fallback);
    }
    hosts.forEach((host) => {
      if (!host.querySelector('[data-theme-toggle]')) host.append(createToggle());
    });
    updateButtons(currentTheme());
  }

  apply(savedTheme() || (prefersDark?.matches ? 'dark' : 'light'), false);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount, { once: true });
  else mount();

  if (prefersDark) {
    prefersDark.addEventListener?.('change', (event) => {
      if (!savedTheme()) apply(event.matches ? 'dark' : 'light', false);
    });
  }

  window.sentinelTheme = Object.freeze({
    get: currentTheme,
    set: (theme) => apply(theme, true),
    toggle: () => apply(currentTheme() === 'dark' ? 'light' : 'dark', true),
  });
}());
