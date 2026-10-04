(function () {
  'use strict';

  let activeDialog = null;
  let lastFocused = null;
  const buttonBusyState = new WeakMap();

  function escapeHtml(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function materialIcon(value, tone) {
    const aliases = {
      '!': 'error',
      '?': 'help',
      'i': 'info',
      '✓': 'check_circle',
      '🔔': 'notifications_active',
      '🚨': 'emergency',
    };
    const requested = String(value == null ? '' : value).trim();
    if (aliases[requested]) return aliases[requested];
    if (/^[a-z][a-z0-9_]{1,39}$/.test(requested)) return requested;
    return { danger: 'error', warning: 'warning', success: 'check_circle' }[tone] || 'info';
  }

  function ensureToastRegion() {
    let region = document.querySelector('.sl-toast-region');
    if (!region) {
      region = document.createElement('div');
      region.className = 'sl-toast-region';
      region.setAttribute('role', 'status');
      region.setAttribute('aria-live', 'polite');
      document.body.appendChild(region);
    }
    return region;
  }

  function resolveButton(target) {
    if (!target) return null;
    if (typeof target === 'string') return document.querySelector(target);
    if (target.currentTarget) return target.currentTarget;
    return target;
  }

  function setBusy(target, busy, options) {
    const button = resolveButton(target);
    if (!button || button.tagName !== 'BUTTON') return null;
    const opts = options || {};
    if (busy) {
      if (buttonBusyState.has(button)) return button;
      const bounds = button.getBoundingClientRect();
      buttonBusyState.set(button, {
        html: button.innerHTML,
        disabled: button.disabled,
        minWidth: button.style.minWidth
      });
      if (bounds.width > 0) button.style.minWidth = Math.ceil(bounds.width) + 'px';
      button.disabled = true;
      button.classList.add('sl-button-busy');
      button.setAttribute('aria-busy', 'true');
      button.textContent = opts.label || button.dataset.busyLabel || 'Working…';
      return button;
    }

    const previous = buttonBusyState.get(button);
    if (!previous) return button;
    button.innerHTML = previous.html;
    button.disabled = previous.disabled;
    button.style.minWidth = previous.minWidth;
    button.classList.remove('sl-button-busy');
    button.removeAttribute('aria-busy');
    buttonBusyState.delete(button);
    return button;
  }

  async function runBusy(target, operation, options) {
    setBusy(target, true, options);
    try {
      return await (typeof operation === 'function' ? operation() : operation);
    } finally {
      setBusy(target, false);
    }
  }

  function toast(message, options) {
    const opts = options || {};
    const tone = opts.tone || 'info';
    const icons = { success: 'check_circle', danger: 'error', warning: 'warning', info: 'info' };
    const item = document.createElement('div');
    item.className = 'sl-toast';
    item.dataset.tone = tone;
    item.setAttribute('role', tone === 'danger' ? 'alert' : 'status');
    item.innerHTML = '<span class="sl-toast-icon material-symbols-rounded" aria-hidden="true">' + (icons[tone] || 'info') + '</span><span>' + escapeHtml(message) + '</span><button type="button" class="sl-toast-close" aria-label="Dismiss notification"><span class="material-symbols-rounded" aria-hidden="true">close</span></button>';
    ensureToastRegion().appendChild(item);
    let dismissed = false;
    function dismiss() {
      if (dismissed) return;
      dismissed = true;
      item.classList.add('sl-toast-out');
      setTimeout(function () { item.remove(); }, 240);
    }
    item.querySelector('.sl-toast-close').addEventListener('click', dismiss);
    const duration = Number(opts.duration || 3800);
    setTimeout(function () {
      dismiss();
    }, duration);
    return item;
  }

  function closeDialog(result) {
    if (!activeDialog) return;
    const current = activeDialog;
    activeDialog = null;
    current.layer.remove();
    document.body.style.overflow = current.previousOverflow;
    document.body.classList.remove('sl-dialog-open');
    document.removeEventListener('keydown', current.onKeyDown);
    if (lastFocused && typeof lastFocused.focus === 'function') lastFocused.focus();
    current.resolve(result);
  }

  function fieldMarkup(field, index) {
    const id = 'sl-dialog-field-' + index;
    const required = field.required ? ' required' : '';
    const placeholder = field.placeholder ? ' placeholder="' + escapeHtml(field.placeholder) + '"' : '';
    const value = escapeHtml(field.value == null ? '' : field.value);
    let control = '';
    if (field.type === 'select') {
      control = '<select id="' + id + '" name="' + escapeHtml(field.name) + '"' + required + '>' +
        (field.options || []).map(function (option) {
          const optionValue = typeof option === 'string' ? option : option.value;
          const optionLabel = typeof option === 'string' ? option : option.label;
          const disabled = option && option.disabled ? ' disabled' : '';
          return '<option value="' + escapeHtml(optionValue) + '"' + (String(optionValue) === String(field.value) ? ' selected' : '') + disabled + '>' + escapeHtml(optionLabel) + '</option>';
        }).join('') + '</select>';
    } else if (field.type === 'textarea') {
      control = '<textarea id="' + id + '" name="' + escapeHtml(field.name) + '"' + required + placeholder + '>' + value + '</textarea>';
    } else {
      control = '<input id="' + id + '" name="' + escapeHtml(field.name) + '" type="' + escapeHtml(field.type || 'text') + '" value="' + value + '"' + required + placeholder + (field.autocomplete ? ' autocomplete="' + escapeHtml(field.autocomplete) + '"' : '') + '>';
    }
    const hintMarkup = field.hint ? '<p class="sl-dialog-hint">' + escapeHtml(field.hint) + '</p>' : '';
    return '<div class="sl-dialog-field"><label for="' + id + '">' + escapeHtml(field.label || field.name) + (field.required ? ' *' : '') + '</label>' + control + hintMarkup + '</div>';
  }

  function open(options) {
    const opts = options || {};
    if (activeDialog) closeDialog(null);
    lastFocused = document.activeElement;
    return new Promise(function (resolve) {
      const layer = document.createElement('div');
      layer.className = 'sl-dialog-layer';
      layer.setAttribute('role', 'presentation');
      const fields = opts.fields || [];
      const tone = opts.tone || (opts.danger ? 'danger' : 'info');
      const icon = materialIcon(opts.icon, tone);
      layer.innerHTML =
        '<div class="sl-dialog-backdrop" data-dialog-cancel></div>' +
        '<section class="sl-dialog" role="dialog" aria-modal="true" aria-labelledby="sl-dialog-title"' + (opts.message ? ' aria-describedby="sl-dialog-message"' : '') + '>' +
          '<div class="sl-dialog-head">' +
            '<span class="sl-dialog-icon material-symbols-rounded" data-tone="' + escapeHtml(tone) + '" aria-hidden="true">' + escapeHtml(icon) + '</span>' +
            '<div><h2 class="sl-dialog-title" id="sl-dialog-title">' + escapeHtml(opts.title || 'Security Agency Management System') + '</h2>' +
            (opts.message ? '<p class="sl-dialog-message" id="sl-dialog-message">' + escapeHtml(opts.message) + '</p>' : '') + '</div>' +
            (opts.hideClose ? '' : '<button class="sl-dialog-close" type="button" aria-label="Close" data-dialog-cancel><span class="material-symbols-rounded" aria-hidden="true">close</span></button>') +
          '</div>' +
          (fields.length ? '<form class="sl-dialog-form"><div class="sl-dialog-fields">' + fields.map(fieldMarkup).join('') + '</div><p class="sl-dialog-error" aria-live="polite"></p></form>' : '') +
          '<div class="sl-dialog-actions">' +
            (opts.cancelText === null ? '' : '<button class="sl-dialog-btn" type="button" data-dialog-cancel>' + escapeHtml(opts.cancelText || 'Cancel') + '</button>') +
            '<button class="sl-dialog-btn ' + (opts.danger ? 'sl-dialog-btn-danger' : 'sl-dialog-btn-primary') + '" type="button" data-dialog-confirm>' + escapeHtml(opts.confirmText || 'Continue') + '</button>' +
          '</div>' +
        '</section>';

      // Optional caller-built content stays DOM-only; never interpret it as HTML.
      if (opts.content instanceof HTMLElement) {
        layer.querySelector('.sl-dialog').insertBefore(opts.content, layer.querySelector('.sl-dialog-actions'));
        if (!opts.message) {
          opts.content.id = opts.content.id || 'sl-dialog-content';
          layer.querySelector('.sl-dialog').setAttribute('aria-describedby', opts.content.id);
        }
      }

      const previousOverflow = document.body.style.overflow;
      document.body.style.overflow = 'hidden';
      document.body.classList.add('sl-dialog-open');
      document.body.appendChild(layer);

      function collectValues() {
        const values = {};
        fields.forEach(function (field, index) {
          const input = layer.querySelector('#sl-dialog-field-' + index);
          values[field.name] = input ? input.value : '';
        });
        return values;
      }

      let confirmationInProgress = false;
      async function confirmSelection() {
        if (confirmationInProgress) return;
        const form = layer.querySelector('.sl-dialog-form');
        if (form && !form.reportValidity()) return;
        const confirmButton = layer.querySelector('[data-dialog-confirm]');
        confirmationInProgress = true;
        setBusy(confirmButton, true, {
          label: opts.busyText || (fields.length ? 'Checking…' : 'Confirming…')
        });
        const values = collectValues();
        const errorEl = layer.querySelector('.sl-dialog-error');
        try {
          if (typeof opts.validate === 'function') {
            const validation = await opts.validate(values);
            // A cancelled or replaced dialog must never confirm the next one
            // when its asynchronous validation eventually finishes.
            if (activeDialog?.layer !== layer) return;
            if (validation) {
              if (errorEl) errorEl.textContent = validation;
              return;
            }
          }
          if (activeDialog?.layer === layer) closeDialog(fields.length ? values : true);
        } catch (error) {
          if (errorEl) errorEl.textContent = error && error.message ? error.message : 'Please try again.';
        } finally {
          confirmationInProgress = false;
          if (confirmButton.isConnected) {
            setBusy(confirmButton, false);
          }
        }
      }

      const onKeyDown = function (event) {
        if (event.key === 'Escape' && (opts.cancelText !== null || opts.dismissOnEscape)) closeDialog(null);
        if (event.key === 'Tab') {
          const focusable = Array.from(layer.querySelectorAll('button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [href]'));
          if (!focusable.length) return;
          const first = focusable[0];
          const last = focusable[focusable.length - 1];
          if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last.focus();
          } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first.focus();
          }
          return;
        }
        // Let links and buttons activate natively, including caller-built content.
        // Enter in a dialog form field still submits the dialog's confirmation.
        if (event.key === 'Enter' && !event.shiftKey &&
            event.target.matches('.sl-dialog-form input')) {
          event.preventDefault();
          confirmSelection();
        }
      };
      activeDialog = { layer: layer, resolve: resolve, previousOverflow: previousOverflow, onKeyDown: onKeyDown };
      document.addEventListener('keydown', onKeyDown);
      layer.querySelectorAll('[data-dialog-cancel]').forEach(function (button) {
        button.addEventListener('click', function () { closeDialog(null); });
      });
      layer.querySelector('[data-dialog-confirm]').addEventListener('click', confirmSelection);
      const focusTarget = layer.querySelector('input, select, textarea, [data-dialog-confirm]');
      // The layer is already attached. A delayed focus can steal focus from a
      // user's first action (for example Cancel or Copy email).
      if (focusTarget) focusTarget.focus({ preventScroll: true });
    });
  }

  const appDialog = {
    open: open,
    toast: toast,
    setBusy: setBusy,
    runBusy: runBusy,
    alert: function (message, options) {
      const opts = Object.assign({ title: 'Security Agency Management System', cancelText: null, confirmText: 'Got it', icon: 'info' }, options || {}, { message: message });
      return open(opts);
    },
    confirm: function (message, options) {
      return open(Object.assign({ title: 'Please confirm', confirmText: 'Confirm', icon: 'help' }, options || {}, { message: message }));
    },
    form: function (options) { return open(options); }
  };

  window.appDialog = appDialog;
  window.alert = function (message) {
    const text = String(message == null ? '' : message);
    const isError = /error|failed|could not|unable|denied/i.test(text);
    appDialog.toast(text, { tone: isError ? 'danger' : 'info', duration: 4500 });
  };

  function addSkipLink() {
    if (document.querySelector('.sl-skip-link')) return;
    const target = document.querySelector('.ax-content, .ix-content, .simple-card');
    if (!target) return;
    if (!target.id) target.id = 'main-content';
    const link = document.createElement('a');
    link.className = 'sl-skip-link';
    link.href = '#' + target.id;
    link.textContent = 'Skip to main content';
    document.body.prepend(link);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', addSkipLink);
  else addSkipLink();

  document.addEventListener('click', function (event) {
    const link = event.target.closest('a[href]');
    if (!link || event.defaultPrevented || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (link.target === '_blank' || link.hasAttribute('download')) return;
    const url = new URL(link.href, location.href);
    if (url.origin !== location.origin || url.href === location.href || url.hash) return;
    event.preventDefault();
    document.body.classList.add('sl-page-leaving');
    setTimeout(function () { location.href = url.href; }, 190);
  });
})();
