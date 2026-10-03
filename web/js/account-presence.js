(function () {
  'use strict';
  const client = window.appSupabase;
  if (!client?.auth || window.accountPresence) return;
  let userId = null, timer = null, pending = false, lastSent = 0, authRevision = 0;
  async function heartbeat(force = false) {
    if (!userId || pending || (!force && Date.now() - lastSent < 20000)) return;
    pending = true;
    lastSent = Date.now();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    try {
      await client.rpc('touch_account_presence', { p_client_kind: 'web' }).abortSignal(controller.signal);
    } catch (_) {
      // Reconnect automatically; a failed request must never keep a user online.
    } finally { clearTimeout(timeout); pending = false; }
  }
  function sessionChanged(session) {
    const next = session?.user?.id || null;
    if (next === userId && timer) return;
    userId = next;
    clearInterval(timer); timer = null;
    if (next) {
      void heartbeat(true);
      timer = setInterval(heartbeat, 30000);
    }
  }
  client.auth.onAuthStateChange((_event, session) => {
    const revision = ++authRevision;
    // Do not make Auth/REST calls while the Auth callback holds its lock.
    setTimeout(() => { if (revision === authRevision) sessionChanged(session); }, 0);
  });
  const initialRevision = authRevision;
  client.auth.getSession().then(({ data }) => {
    if (initialRevision === authRevision) sessionChanged(data.session);
  }).catch(() => {});
  window.addEventListener('online', () => heartbeat(true));
  document.addEventListener('visibilitychange', () => { if (!document.hidden) void heartbeat(true); });
  window.accountPresence = Object.freeze({ heartbeat });
})();
