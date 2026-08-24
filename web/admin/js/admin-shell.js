if (!window.appDialog && !document.querySelector('script[data-sentinel-experience]')) {
    var experienceScript = document.createElement('script');
    experienceScript.src = '../js/app-dialogs.js';
    experienceScript.dataset.sentinelExperience = 'true';
    document.head.appendChild(experienceScript);
}

function adminLogout() {
    if (typeof auth !== 'undefined') {
        auth.signOut().then(function() { window.location.href = 'login.html'; });
    } else {
        window.location.href = 'login.html';
    }
}

function setAdminUserName(name) {
    var el = document.getElementById('axUserName');
    if (el && name) el.textContent = name;
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
