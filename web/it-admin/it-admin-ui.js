(() => {
  const sidebar = document.getElementById('itSidebar');
  const toggle = document.querySelector('[data-it-nav-toggle]');
  if (!sidebar || !toggle) return;

  const currentPage = window.location.pathname.split('/').pop() || 'dashboard.html';
  sidebar.querySelectorAll('a[href]').forEach((link) => {
    const targetPage = new URL(link.href, window.location.href).pathname.split('/').pop();
    if (targetPage === currentPage) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  });

  const backdrop = document.createElement('button');
  backdrop.type = 'button';
  backdrop.className = 'ax-sidebar-backdrop';
  backdrop.setAttribute('aria-label', 'Close navigation');
  document.body.append(backdrop);

  const close = () => {
    sidebar.classList.remove('ax-open');
    backdrop.classList.remove('is-visible');
    document.body.classList.remove('ax-menu-open');
    toggle.setAttribute('aria-expanded', 'false');
    toggle.setAttribute('aria-label', 'Open navigation');
  };
  const open = () => {
    sidebar.classList.add('ax-open');
    backdrop.classList.add('is-visible');
    document.body.classList.add('ax-menu-open');
    toggle.setAttribute('aria-expanded', 'true');
    toggle.setAttribute('aria-label', 'Close navigation');
  };

  toggle.addEventListener('click', () => {
    if (sidebar.classList.contains('ax-open')) close();
    else open();
  });
  backdrop.addEventListener('click', close);
  sidebar.querySelectorAll('a').forEach((link) => link.addEventListener('click', close));
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') close();
  });
  window.addEventListener('resize', () => {
    if (window.innerWidth > 1024) close();
  });
})();
