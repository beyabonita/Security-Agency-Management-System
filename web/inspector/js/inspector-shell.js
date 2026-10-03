/** Shared sidebar layout and Inspector-only navigation. */
if (!window.appDialog && !document.querySelector('script[data-sentinel-experience]')) {
    var experienceScript = document.createElement('script');
    experienceScript.src = '../js/app-dialogs.js';
    experienceScript.dataset.sentinelExperience = 'true';
    document.head.appendChild(experienceScript);
}

function inspectorLogout() {
    if (typeof auth !== 'undefined') {
        auth.signOut().then(function() { window.location.href = '../staff/login.html'; });
    } else {
        window.location.href = '../staff/login.html';
    }
}

function finishPageLoading() {
    var loading = document.getElementById('loadingScreen');
    if (!loading || loading.hidden) return;
    loading.classList.add('sl-loading-out');
    window.setTimeout(function() { loading.hidden = true; }, 230);
}

function markInspectorNavigation() {
    var currentPage = window.location.pathname.split('/').pop() || 'dashboard.html';
    document.querySelectorAll('.ax-nav a[href]').forEach(function(link) {
        var targetPage = new URL(link.href, window.location.href).pathname.split('/').pop();
        if (targetPage === currentPage) link.setAttribute('aria-current', 'page');
        else link.removeAttribute('aria-current');
    });
}

function initInspectorShell() {
    markInspectorNavigation();
    var toggle = document.getElementById('ixMenuToggle');
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
        toggle.setAttribute('aria-controls', sidebar.id || 'inspector-navigation');
        if (!sidebar.id) sidebar.id = 'inspector-navigation';
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

document.addEventListener('DOMContentLoaded', initInspectorShell);

function setInspectorUserName(name) {
    var el = document.getElementById('ixUserName');
    if (el) { el.textContent = typeof name === 'string' ? name.trim() : ''; el.hidden = !el.textContent; }
}

// Re-read authorization-filtered data after team assignments change. RLS remains
// authoritative for every request; refreshing also removes stale open panels.
function watchInspectorAssignments(refresh) {
    let running = false;
    async function refreshVisible() {
        if (document.hidden || running) return;
        running = true;
        try { await refresh(); }
        catch (error) { console.warn('Assigned Guard data could not be refreshed.', error); }
        finally { running = false; }
    }
    const timer = window.setInterval(refreshVisible, 60000);
    document.addEventListener('visibilitychange', refreshVisible);
    window.addEventListener('pagehide', () => {
        window.clearInterval(timer);
        document.removeEventListener('visibilitychange', refreshVisible);
    }, { once: true });
}
