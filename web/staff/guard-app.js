(() => {
  'use strict';
  const template = document.getElementById('guardAppSetupTemplate');
  if (!template) return;
  let open = false;

  function showSetup() {
    if (!window.appDialog?.open) return false;
    if (open) return true;
    open = true;
    const content = template.content.firstElementChild.cloneNode(true);
    const userAgent = navigator.userAgent || '';
    const android = /Android/i.test(userAgent);
    const mobile = /Android|Mobi|iPad|iPhone|iPod/i.test(userAgent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    const unsupported = mobile && !android;
    content.dataset.platform = android ? 'android' : unsupported ? 'unsupported' : 'desktop';
    const download = content.querySelector('#androidDownload');
    const message = content.querySelector('#deviceMessage');
    const status = content.querySelector('[role="status"]');
    if (unsupported) {
      message.textContent = 'The Guard app currently supports Android devices only.';
      download.removeAttribute('href');
      download.removeAttribute('download');
      download.setAttribute('aria-disabled', 'true');
      status.textContent = 'Use an Android phone to scan the QR code or install the APK.';
    } else if (android) {
      message.textContent = 'Android detected. Download the APK, then open it to install.';
    }
    download.addEventListener('click', event => {
      if (unsupported) { event.preventDefault(); return; }
      // The browser owns the download; do not claim progress or successful installation.
      status.textContent = 'Check your browser’s Downloads. When the file finishes, open the APK to install.';
    });
    void window.appDialog.open({
      title: 'Install the Guard app', icon: 'android', content,
      cancelText: null, confirmText: 'Done', dismissOnEscape: true,
    }).finally(() => {
      open = false;
      if (location.hash === '#guard-app-setup') {
        history.replaceState(history.state, '', location.pathname + location.search);
      }
    });
    return true;
  }

  document.querySelectorAll('[data-guard-app-setup]').forEach(trigger => {
    trigger.addEventListener('click', event => {
      if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      if (showSetup()) event.preventDefault();
    });
  });
  // Preserve old setup bookmarks without retaining a second setup interface.
  if (location.hash === '#guard-app-setup') showSetup();
  window.addEventListener('hashchange', () => {
    if (location.hash === '#guard-app-setup') showSetup();
  });
})();
