(() => {
  const tabs = [...document.querySelectorAll('[data-control-tab]')];
  function select(name, focus = false) {
    if (!tabs.some(tab => tab.dataset.controlTab === name)) name = 'settings';
    for (const tab of tabs) {
      const active = tab.dataset.controlTab === name;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
      document.getElementById(tab.getAttribute('aria-controls')).hidden = !active;
      if (active && focus) tab.focus();
    }
  }
  function activate(tab) {
    const name = tab.dataset.controlTab;
    history.replaceState(null, '', '#' + name);
    select(name, true);
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => activate(tab));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      if (next !== undefined) { event.preventDefault(); activate(tabs[next]); }
    });
  });
  window.addEventListener('hashchange', () => select(location.hash.slice(1)));
  select(location.hash.slice(1));
})();
