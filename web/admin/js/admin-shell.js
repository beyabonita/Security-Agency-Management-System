if (!window.appDialog && !document.querySelector('script[data-sentinel-experience]')) {
    var experienceScript = document.createElement('script');
    experienceScript.src = '../js/app-dialogs.js';
    experienceScript.dataset.sentinelExperience = 'true';
    document.head.appendChild(experienceScript);
}

function adminLogout() {
    if (typeof auth !== 'undefined') {
        auth.signOut().then(function() { window.location.href = '../staff/login.html'; });
    } else {
        window.location.href = '../staff/login.html';
    }
}

function setAdminUserName(name) {
    var el = document.getElementById('axUserName');
    if (!el) return;
    el.textContent = typeof name === 'string' ? name.trim() : '';
    el.hidden = !el.textContent;
}

function adminProfileName(profile) {
    var clean = value => typeof value === 'string' ? value.trim() : '';
    var first = clean(profile.first_name), last = clean(profile.last_name);
    var middle = clean(profile.middle_initial).replace(/\.+$/, '');
    return [first, middle ? middle + '.' : '', last].filter(Boolean).join(' ');
}

function initAdminIdentity() {
    var chip = document.getElementById('axUserName');
    var client = window.appSupabase;
    if (!chip || chip.dataset.identityStarted || !client || !window.firebase?.auth) return;
    chip.dataset.identityStarted = 'true';
    var userId = null, generation = 0, timer, controller, stopped = false;
    function cancel() {
        generation++;
        clearTimeout(timer);
        controller?.abort();
        controller = null;
    }
    async function load(attempt = 0) {
        if (!userId || stopped) return;
        var currentId = userId, currentGeneration = generation;
        var requestController = new AbortController();
        controller = requestController;
        var timeout;
        try {
            var request = client.from('profiles')
                .select('first_name,middle_initial,last_name,role,active').eq('id', currentId).single();
            if (typeof request.abortSignal === 'function') request = request.abortSignal(requestController.signal);
            var deadline = new Promise((_, reject) => {
                requestController.signal.addEventListener('abort', () => reject(new Error('Name request cancelled')), {once:true});
                timeout = setTimeout(() => requestController.abort(), 10000);
            });
            var result = await Promise.race([request, deadline]);
            if (stopped || currentGeneration !== generation || currentId !== userId) return;
            if (result.error) throw result.error;
            if (!result.data?.active || result.data.role !== 'admin') { setAdminUserName(''); return; }
            setAdminUserName(adminProfileName(result.data) || 'Name unavailable');
        } catch (_) {
            if (stopped || currentGeneration !== generation || currentId !== userId) return;
            // Preserve this account's loaded name through a brief network failure.
            if (attempt < 2) timer = setTimeout(() => load(attempt + 1), 1500 * (attempt + 1));
            else if (!chip.textContent) setAdminUserName('Name unavailable');
        } finally {
            clearTimeout(timeout);
            if (controller === requestController) controller = null;
        }
    }
    var unsubscribe = window.firebase.auth().onAuthStateChanged(user => {
        var nextId = user?.uid || null;
        cancel();
        if (nextId !== userId || !nextId) setAdminUserName('');
        userId = nextId;
        // Keep the profile query outside the auth notification/refresh callback.
        if (userId) timer = setTimeout(() => load(), 0);
    });
    function retry() {
        if (!stopped && userId && !document.hidden && !controller) {
            clearTimeout(timer);load();
        }
    }
    window.addEventListener('online', retry);
    window.addEventListener('focus', retry);
    window.addEventListener('pagehide', () => {
        stopped = true;cancel();unsubscribe?.();
        window.removeEventListener('online', retry);window.removeEventListener('focus', retry);
    }, {once:true});
}

function finishPageLoading() {
    var loading = document.getElementById('loadingScreen');
    if (!loading || loading.hidden) return;
    loading.classList.add('sl-loading-out');
    window.setTimeout(function() { loading.hidden = true; }, 230);
}

function markAdminNavigation() {
    var currentPage = window.location.pathname.split('/').pop() || 'dashboard.html';
    document.querySelectorAll('.ax-nav a[href]').forEach(function(link) {
        var targetPage = new URL(link.href, window.location.href).pathname.split('/').pop();
        if (targetPage === currentPage) link.setAttribute('aria-current', 'page');
        else link.removeAttribute('aria-current');
    });
}

function initAdminShell() {
    initAdminIdentity();
    if (window.SENTINEL_LIVE_TRACKING_ENABLED && !document.querySelector('.ax-nav a[href="live-tracking.html"]')) {
        const link = document.createElement('a'); link.href = 'live-tracking.html';
        link.innerHTML = '<svg class="ax-nav-icon" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true" focusable="false"><path d="m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3Z"/><path d="M9 3v15M15 6v15"/><circle cx="15" cy="11" r="2" fill="currentColor"/></svg><span>Live guard map</span>'; document.querySelector('.ax-nav')?.append(link);
    }
    if (!document.querySelector('.ax-nav a[href="records.html"]')) {
        const link = document.createElement('a'); link.href = 'records.html';
        link.innerHTML = '<span class="ax-nav-icon material-symbols-rounded" aria-hidden="true">description</span> Records';
        document.querySelector('.ax-nav')?.append(link);
    }
    markAdminNavigation();
    var toggle = document.getElementById('axMenuToggle');
    var sidebar = document.querySelector('.ax-sidebar');
    if (toggle && sidebar) {
        var backdrop = document.createElement('button');
        backdrop.type = 'button';
        backdrop.className = 'ax-sidebar-backdrop';
        backdrop.setAttribute('aria-label', 'Close navigation');
        document.body.appendChild(backdrop);
        function closeNavigation() {
            sidebar.classList.remove('ax-open');
            backdrop.classList.remove('is-visible');
            document.body.classList.remove('ax-menu-open');
            toggle.setAttribute('aria-expanded', 'false');
            toggle.setAttribute('aria-label', 'Open navigation');
        }
        function openNavigation() {
            sidebar.classList.add('ax-open');
            backdrop.classList.add('is-visible');
            document.body.classList.add('ax-menu-open');
            toggle.setAttribute('aria-expanded', 'true');
            toggle.setAttribute('aria-label', 'Close navigation');
        }
        toggle.setAttribute('aria-controls', sidebar.id || 'admin-navigation');
        if (!sidebar.id) sidebar.id = 'admin-navigation';
        toggle.setAttribute('aria-expanded', 'false');
        toggle.addEventListener('click', function() {
            if (sidebar.classList.contains('ax-open')) closeNavigation();
            else openNavigation();
        });
        backdrop.addEventListener('click', closeNavigation);
        sidebar.querySelectorAll('a').forEach(function(link) {
            link.addEventListener('click', closeNavigation);
        });
        document.addEventListener('keydown', function(event) {
            if (event.key === 'Escape') closeNavigation();
        });
        window.addEventListener('resize', function() {
            if (window.innerWidth > 900) closeNavigation();
        });
    }
}

document.addEventListener('DOMContentLoaded', initAdminShell);
