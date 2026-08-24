/** Top-nav mobile toggle + shared logout for inspector pages */
if (!window.appDialog && !document.querySelector('script[data-sentinel-experience]')) {
    var experienceScript = document.createElement('script');
    experienceScript.src = '../js/app-dialogs.js';
    experienceScript.dataset.sentinelExperience = 'true';
    document.head.appendChild(experienceScript);
}

function inspectorLogout() {
    if (typeof auth !== 'undefined') {
        auth.signOut().then(function() { window.location.href = 'login.html'; });
    } else {
        window.location.href = 'login.html';
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
    document.querySelectorAll('.ix-topnav a[href]').forEach(function(link) {
        var targetPage = new URL(link.href, window.location.href).pathname.split('/').pop();
        if (targetPage === currentPage) link.setAttribute('aria-current', 'page');
        else link.removeAttribute('aria-current');
    });
}

function initInspectorShell() {
    markInspectorNavigation();
    var toggle = document.getElementById('ixMenuToggle');
    var topnav = document.getElementById('ixTopnav');
    if (toggle && topnav) {
        toggle.setAttribute('aria-controls', 'ixTopnavLinks');
        toggle.setAttribute('aria-expanded', 'false');
        var links = topnav.querySelector('.ix-topnav-links');
        if (links && !links.id) links.id = 'ixTopnavLinks';
        function closeNavigation() {
            topnav.classList.remove('ix-open');
            toggle.setAttribute('aria-expanded', 'false');
            toggle.setAttribute('aria-label', 'Open navigation');
        }
        toggle.addEventListener('click', function() {
            topnav.classList.toggle('ix-open');
            toggle.setAttribute('aria-expanded', topnav.classList.contains('ix-open') ? 'true' : 'false');
            toggle.setAttribute('aria-label', topnav.classList.contains('ix-open') ? 'Close navigation' : 'Open navigation');
        });
        document.addEventListener('keydown', function(event) {
            if (event.key === 'Escape') closeNavigation();
        });
        topnav.querySelectorAll('a').forEach(function(link) {
            link.addEventListener('click', closeNavigation);
        });
    }
}

document.addEventListener('DOMContentLoaded', initInspectorShell);

function setInspectorUserName(name) {
    var el = document.getElementById('ixUserName');
    if (el && name) el.textContent = name;
}
