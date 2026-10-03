/**
 * Slide/fade transition when switching between Operations Head and Inspector login pages.
 */
(function () {
    var panel = document.body.getAttribute('data-login-panel');
    if (!panel) return;

    var EXIT_MS = 380;

    function markReady() {
        requestAnimationFrame(function () {
            requestAnimationFrame(function () {
                document.body.classList.add('login-ready');
            });
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', markReady);
    } else {
        markReady();
    }

    document.querySelectorAll('[data-login-switch]').forEach(function (link) {
        link.addEventListener('click', function (e) {
            e.preventDefault();
            var href = link.getAttribute('href');
            if (!href || document.body.classList.contains('login-pending-nav')) return;

            document.body.classList.remove('login-ready');
            document.body.classList.add('login-exit-' + panel);
            document.body.classList.add('login-pending-nav');

            setTimeout(function () {
                window.location.href = href;
            }, EXIT_MS);
        });
    });
})();
