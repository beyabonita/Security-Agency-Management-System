(function () {
  'use strict';
  const roles = { it_admin: 'Superadmin', admin: 'Operations Head', operations_head: 'Operations Head', inspector: 'Inspector', user: 'Guard' };
  const safe = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
  const when = value => value ? new Date(value).toLocaleString('en-PH', { dateStyle: 'medium', timeStyle: 'short' }) : '—';
  window.mountAccountActivity = function (host) {
    if (!host || host.dataset.mounted) return;
    host.dataset.mounted = 'true';
    let accountsPage = 0, historyPage = 0, revision = 0, debounce;
    let accountsTotal = 0, historyTotal = 0, fetching = false;
    host.innerHTML = `<section class="it-card">
      <div class="it-toolbar"><h2>Account activity · All roles</h2><button class="ax-btn" type="button" data-refresh>Refresh activity</button></div>
      <div class="it-form">
        <div><label>Search name or email<input type="search" data-search maxlength="160"></label></div>
        <div><label>Role<select data-role><option value="">All roles</option><option value="it_admin">Superadmin</option><option value="admin">Operations Head</option><option value="inspector">Inspector</option><option value="user">Guard</option></select></label></div>
        <div><label>Connection<select data-status><option value="">All connections</option><option value="online">Online</option><option value="offline">Offline</option></select></label></div>
      </div>
      <p data-feedback role="status">Loading account activity…</p>
      <div class="sl-table-frame"><table class="it-table"><thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Connection</th><th>Last seen</th></tr></thead><tbody data-accounts></tbody></table></div>
      <div class="it-form-actions"><button class="it-btn" data-prev-accounts>Previous</button><span data-accounts-page></span><button class="it-btn" data-next-accounts>Next</button></div>
    </section>
    <section class="it-card"><h2>Login history</h2>
      <div class="sl-table-frame"><table class="it-table"><thead><tr><th>Name</th><th>Role</th><th>Client</th><th>Signed in</th><th>Last seen</th><th>Session ended</th><th>Status</th></tr></thead><tbody data-history></tbody></table></div>
      <div class="it-form-actions"><button class="it-btn" data-prev-history>Previous</button><span data-history-page></span><button class="it-btn" data-next-history>Next</button></div>
    </section>`;
    const el = name => host.querySelector(`[data-${name}]`);
    function pages() {
      for (const [name, page, total] of [['accounts', accountsPage, accountsTotal], ['history', historyPage, historyTotal]]) {
        el(`${name}-page`).textContent = `Page ${page + 1} of ${Math.max(1, Math.ceil(total / 50))} · ${total} records`;
        el(`prev-${name}`).disabled = page === 0;
        el(`next-${name}`).disabled = (page + 1) * 50 >= total;
      }
    }
    async function refresh() {
      const request = ++revision;
      fetching = true;
      const controller = new AbortController();
      let timeout;
      try {
        let operation = window.appSupabase.rpc('it_account_activity', {
          p_search: el('search').value.trim(), p_role: el('role').value, p_status: el('status').value,
          p_accounts_page: accountsPage, p_history_page: historyPage,
        });
        if (operation.abortSignal) operation = operation.abortSignal(controller.signal);
        const { data, error } = await Promise.race([operation, new Promise((_, reject) => {
          timeout = setTimeout(() => { controller.abort(); reject(new Error('Connection timed out.')); }, 8000);
        })]);
        if (request !== revision || !host.isConnected) return;
        if (error) throw error;
        if (!data?.accounts || !data?.history) throw new Error('Account activity is unavailable.');
        accountsTotal = data.accounts.total; historyTotal = data.history.total;
        el('accounts').innerHTML = data.accounts.rows.map(person => `<tr>
          <td>${safe(person.name)}</td><td>${safe(displayLoginId(person))}</td><td>${safe(roles[person.role] || person.role)}</td>
          <td><span class="ax-badge ${person.online ? 'ax-badge-ok' : 'ax-badge-off'}">${person.online ? 'Online' : 'Offline'}</span>${person.account_enabled === false ? ' · Account disabled' : ''}</td><td>${safe(when(person.last_seen_at))}</td>
        </tr>`).join('') || '<tr><td colspan="5">No matching accounts.</td></tr>';
        el('history').innerHTML = data.history.rows.map(session => `<tr><td>${safe(session.name)}</td><td>${safe(roles[session.role] || session.role)}</td>
          <td>${safe(session.client_kind === 'app' ? 'App' : session.client_kind === 'web' ? 'Web' : '—')}</td>
          <td>${safe(when(session.signed_in_at))}</td><td>${safe(when(session.last_seen_at))}</td><td>${safe(when(session.signed_out_at))}</td><td>${safe(session.status)}</td></tr>`).join('') || '<tr><td colspan="7">No login history recorded yet.</td></tr>';
        el('feedback').textContent = `Updated ${when(data.checked_at)}. Online means recently connected; a lost connection expires after 90 seconds.`;
        pages();
      } catch (error) {
        if (request !== revision) return;
        el('feedback').textContent = 'Status unavailable. ' + (error.message || 'Retry when connected.');
        el('accounts').innerHTML = '<tr><td colspan="5">Online status could not be verified.</td></tr>';
        el('history').innerHTML = '<tr><td colspan="7">History could not be loaded.</td></tr>';
      } finally { clearTimeout(timeout); if (request === revision) fetching = false; }
    }
    el('refresh').onclick = refresh;
    for (const name of ['search', 'role', 'status']) el(name).addEventListener(name === 'search' ? 'input' : 'change', () => {
      ++revision; accountsPage = 0; historyPage = 0;
      clearTimeout(debounce); debounce = setTimeout(refresh, name === 'search' ? 300 : 0);
    });
    for (const name of ['accounts', 'history']) for (const direction of ['prev', 'next']) el(`${direction}-${name}`).onclick = () => {
      const step = direction === 'next' ? 1 : -1;
      if (name === 'accounts') accountsPage = Math.max(0, accountsPage + step);
      else historyPage = Math.max(0, historyPage + step);
      void refresh();
    };
    const timer = setInterval(() => { if (!document.hidden && !fetching) void refresh(); }, 10000);
    window.addEventListener('pagehide', () => clearInterval(timer), { once: true });
    document.addEventListener('visibilitychange', () => { if (!document.hidden) void refresh(); });
    pages(); void refresh();
  };
})();
