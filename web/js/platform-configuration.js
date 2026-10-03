/* Public presentation settings only. Never read the protected settings/audit tables here. */
(function () {
  'use strict';
  const client = window.appSupabase;
  if (window.platformConfiguration || !client || typeof client.rpc !== 'function') return;
  let generation = 0;
  let lastAttempt = 0;

  function openSupport(email, mailto) {
    const content = document.createElement('div');
    content.className = 'sl-support-details';
    const label = document.createElement('label');
    label.htmlFor = 'sl-support-email';
    label.textContent = 'Support email';
    const address = document.createElement('input');
    address.id = 'sl-support-email';
    address.type = 'text';
    address.readOnly = true;
    address.value = email;
    address.addEventListener('click', () => address.select());
    const actions = document.createElement('div');
    actions.className = 'sl-support-actions';
    const copy = document.createElement('button');
    copy.type = 'button';
    copy.className = 'sl-dialog-btn';
    copy.textContent = 'Copy email';
    const compose = document.createElement('a');
    compose.className = 'sl-dialog-btn sl-dialog-btn-primary';
    compose.href = mailto;
    compose.textContent = 'Open email app';
    const feedback = document.createElement('p');
    feedback.className = 'sl-support-feedback';
    feedback.setAttribute('role', 'status');
    feedback.textContent = 'No email app configured? Copy the address into your email service.';
    let copying = false;
    copy.addEventListener('click', async () => {
      if (copying) return;
      copying = true;
      copy.setAttribute('aria-busy', 'true');
      try {
        if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
        await navigator.clipboard.writeText(email);
        feedback.textContent = 'Email address copied.';
      } catch (_) {
        address.focus();
        address.select();
        feedback.textContent = 'Copy is unavailable. The address is selected so you can copy it manually.';
      } finally { copying = false; copy.removeAttribute('aria-busy'); }
    });
    compose.addEventListener('click', () => {
      feedback.textContent = 'If your email app does not open, use Copy email instead.';
    });
    actions.append(copy, compose);
    content.append(label, address, actions, feedback);
    void window.appDialog.open({
      title: 'Contact support', icon: 'help', content,
      cancelText: null, confirmText: 'Done', dismissOnEscape: true,
    });
  }

  function renderAnnouncement(value) {
    const target = document.querySelector('.ax-content, .ix-content, .login-panel-inner, .system-login-card');
    if (!target) return;
    let notice = target.querySelector('[data-platform-announcement]');
    const message = typeof value === 'string' ? value.trim() : '';
    if (!message) { if (notice) notice.remove(); return; }
    if (!notice) {
      notice = document.createElement('div');
      notice.className = 'sl-platform-announcement';
      notice.dataset.platformAnnouncement = 'true';
      notice.setAttribute('role', 'status');
      const label = document.createElement('strong');
      label.textContent = 'System notice';
      notice.append(label, document.createElement('span'));
      target.prepend(notice);
    }
    notice.lastElementChild.textContent = message;
  }

  function renderSupport(value) {
    if (document.body.dataset.itPage === 'controls') {
      document.querySelectorAll('[data-platform-support]').forEach(node => node.remove());
      return;
    }
    const target = document.querySelector('.login-footer, .system-login-card, .ax-content, .ix-content');
    if (!target) return;
    let support = target.querySelector('[data-platform-support]');
    const email = typeof value === 'string' ? value.trim() : '';
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { if (support) support.remove(); return; }
    if (!support) {
      support = document.createElement('div');
      support.className = 'sl-platform-support';
      support.dataset.platformSupport = 'true';
      const link = document.createElement('a');
      link.textContent = 'Contact support';
      link.setAttribute('aria-haspopup', 'dialog');
      link.addEventListener('click', event => {
        // Keep mailto as a progressive fallback if the shared dialog failed to load.
        if (!window.appDialog?.open) return;
        event.preventDefault();
        openSupport(link.dataset.supportEmail, link.href);
      });
      support.appendChild(link);
      target.appendChild(support);
    }
    const link = support.firstElementChild;
    // Encode URI delimiters so a configured address cannot inject mail headers.
    link.href = 'mailto:' + encodeURIComponent(email).replace('%40', '@');
    link.dataset.supportEmail = email;
    link.title = email;
    link.setAttribute('aria-label', 'Contact support: ' + email);
  }

  async function refresh() {
    const request = ++generation;
    lastAttempt = Date.now();
    const results = await Promise.allSettled([
      client.rpc('current_platform_announcement'),
      client.rpc('current_platform_support_email'),
    ]);
    if (request !== generation) return false;
    const renderers = [renderAnnouncement, renderSupport];
    results.forEach((result, index) => {
      if (result.status === 'fulfilled' && !result.value.error) renderers[index](result.value.data);
    });
    return results.every(result => result.status === 'fulfilled' && !result.value.error);
  }

  function refreshWhenVisible() {
    if (!document.hidden && Date.now() - lastAttempt > 5000) void refresh();
  }
  window.platformConfiguration = { refresh };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => { void refresh(); }, { once: true });
  else void refresh();
  // Also update portals open on the other domain, without exposing settings to Realtime.
  window.addEventListener('focus', refreshWhenVisible);
  document.addEventListener('visibilitychange', refreshWhenVisible);
  const interval = setInterval(refreshWhenVisible, 60000);
  window.addEventListener('pagehide', () => clearInterval(interval), { once: true });
})();
