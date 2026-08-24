(function () {
  'use strict';

  if (window.sentinelNotifications) return;

  const state = {
    user: null,
    profile: null,
    items: [],
    channel: null,
    root: null,
    drawer: null,
    backdrop: null,
    bell: null,
    badge: null,
    list: null,
    summary: null,
    criticalLayer: null,
    initializedFor: null,
  };

  const iconByKind = {
    emergency: '🚨',
    incident_status: '🛡️',
    schedule: '📅',
    assignment: '📍',
    shift_request: '🔁',
    accomplishment: '📝',
    account: '👤',
    system: '📢',
  };

  const roleLabels = {
    it_admin: 'IT Admin',
    admin: 'HR / Operations Head',
    inspector: 'Inspector',
    user: 'Guard',
  };

  function client() {
    return window.appSupabase;
  }

  function formatTime(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const difference = Date.now() - date.getTime();
    const minutes = Math.floor(difference / 60000);
    if (minutes < 1) return 'Just now';
    if (minutes < 60) return minutes + ' min ago';
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return hours + ' hr ago';
    const days = Math.floor(hours / 24);
    if (days < 7) return days + ' day' + (days === 1 ? '' : 's') + ' ago';
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: 'medium',
      timeStyle: 'short',
    }).format(date);
  }

  function create(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function actionUrl(item) {
    const role = state.profile && state.profile.role;
    const maps = {
      admin: {
        emergency: 'incidents.html',
        schedule: 'schedule.html',
        personnel: 'users.html',
        shift_request: 'swaps.html',
        accomplishment: 'users.html',
        system: 'dashboard.html',
      },
      inspector: {
        emergency: 'incidents.html',
        schedule: 'dashboard.html',
        personnel: 'users.html',
        shift_request: 'swaps.html',
        accomplishment: 'users.html',
        system: 'dashboard.html',
      },
      it_admin: {
        emergency: 'dashboard.html',
        schedule: 'dashboard.html',
        personnel: 'users.html',
        shift_request: 'dashboard.html',
        accomplishment: 'dashboard.html',
        system: 'clients.html',
      },
    };
    return (maps[role] && maps[role][item.action_key]) || null;
  }

  function unreadCount() {
    return state.items.filter((item) => !item.read_at).length;
  }

  function pendingCritical() {
    return state.items.filter((item) =>
      item.priority === 'critical' && item.requires_ack && !item.acknowledged_at
    );
  }

  function updateBadge() {
    if (!state.badge || !state.bell) return;
    const unread = unreadCount();
    const critical = pendingCritical().length;
    state.badge.hidden = unread === 0 && critical === 0;
    state.badge.textContent = critical > 0 ? '!' : unread > 99 ? '99+' : String(unread);
    state.badge.dataset.critical = critical > 0 ? 'true' : 'false';
    state.bell.classList.toggle('sl-notification-bell-critical', critical > 0);
    state.bell.setAttribute(
      'aria-label',
      critical > 0
        ? critical + ' emergency notification' + (critical === 1 ? '' : 's') + ' awaiting acknowledgement'
        : unread + ' unread notification' + (unread === 1 ? '' : 's')
    );
    if (state.summary) {
      state.summary.textContent = critical > 0
        ? critical + ' critical alert' + (critical === 1 ? '' : 's') + ' awaiting acknowledgement'
        : unread > 0
          ? unread + ' unread notification' + (unread === 1 ? '' : 's')
          : 'You are all caught up';
    }
  }

  function notificationItem(item) {
    const wrapper = create('article', 'sl-notification-item');
    wrapper.dataset.priority = item.priority;
    wrapper.dataset.read = item.read_at ? 'true' : 'false';

    const icon = create('div', 'sl-notification-item-icon', iconByKind[item.kind] || '🔔');
    icon.setAttribute('aria-hidden', 'true');
    const content = create('div', 'sl-notification-item-content');
    const heading = create('div', 'sl-notification-item-heading');
    const title = create('strong', 'sl-notification-item-title', item.title);
    const time = create('time', 'sl-notification-item-time', formatTime(item.created_at));
    time.dateTime = item.created_at;
    heading.append(title, time);
    const message = create('p', 'sl-notification-item-message', item.message);
    const tags = create('div', 'sl-notification-item-tags');
    tags.appendChild(create('span', 'sl-notification-priority', item.priority));
    if (item.requires_ack && !item.acknowledged_at) {
      tags.appendChild(create('span', 'sl-notification-ack-label', 'Acknowledgement required'));
    }
    content.append(heading, message, tags);

    const actions = create('div', 'sl-notification-item-actions');
    const url = actionUrl(item);
    if (item.requires_ack && !item.acknowledged_at) {
      const acknowledge = create('button', 'sl-notification-action sl-notification-action-primary', 'Acknowledge');
      acknowledge.type = 'button';
      acknowledge.addEventListener('click', async function () {
        acknowledge.disabled = true;
        try {
          await acknowledgeItem(item.id);
        } catch (error) {
          notifyError(error, 'Could not acknowledge the alert.');
        } finally {
          acknowledge.disabled = false;
        }
      });
      actions.appendChild(acknowledge);
    }
    if (url) {
      const view = create('button', 'sl-notification-action', item.kind === 'emergency' ? 'Open alert' : 'View');
      view.type = 'button';
      view.addEventListener('click', async function () {
        await markRead(item.id, false);
        location.href = url;
      });
      actions.appendChild(view);
    } else if (!item.read_at) {
      const read = create('button', 'sl-notification-action', 'Mark read');
      read.type = 'button';
      read.addEventListener('click', function () { markRead(item.id, true); });
      actions.appendChild(read);
    }

    wrapper.append(icon, content);
    if (actions.childElementCount) wrapper.appendChild(actions);
    if (!item.read_at) {
      const unreadDot = create('span', 'sl-notification-unread-dot');
      unreadDot.setAttribute('aria-label', 'Unread');
      wrapper.appendChild(unreadDot);
    }
    return wrapper;
  }

  function render() {
    if (!state.list) return;
    state.list.replaceChildren();
    if (!state.items.length) {
      const empty = create('div', 'sl-notification-empty');
      empty.append(
        create('span', 'sl-notification-empty-icon', '🔔'),
        create('strong', '', 'No notifications yet'),
        create('p', '', 'Emergency alerts and operational updates will appear here.')
      );
      state.list.appendChild(empty);
    } else {
      state.items.forEach((item) => state.list.appendChild(notificationItem(item)));
    }
    updateBadge();
  }

  function openDrawer() {
    if (!state.drawer) return;
    state.drawer.hidden = false;
    state.backdrop.hidden = false;
    requestAnimationFrame(function () {
      state.drawer.classList.add('sl-notification-drawer-open');
      state.backdrop.classList.add('sl-notification-backdrop-open');
    });
    document.body.classList.add('sl-notifications-open');
    state.drawer.querySelector('.sl-notification-close').focus();
  }

  function closeDrawer() {
    if (!state.drawer || state.drawer.hidden) return;
    state.drawer.classList.remove('sl-notification-drawer-open');
    state.backdrop.classList.remove('sl-notification-backdrop-open');
    document.body.classList.remove('sl-notifications-open');
    setTimeout(function () {
      state.drawer.hidden = true;
      state.backdrop.hidden = true;
    }, 220);
    if (state.bell) state.bell.focus();
  }

  function mount() {
    if (state.root) return;
    const host = document.querySelector('.ax-topbar-right')
      || document.querySelector('.ix-shell-actions')
      || document.querySelector('.ax-topbar');
    if (!host) return;

    state.root = create('div', 'sl-notification-root');
    state.bell = create('button', 'sl-notification-bell');
    state.bell.type = 'button';
    state.bell.innerHTML = '<span aria-hidden="true">🔔</span>';
    state.badge = create('span', 'sl-notification-badge', '0');
    state.badge.hidden = true;
    state.bell.appendChild(state.badge);
    state.bell.addEventListener('click', openDrawer);
    state.root.appendChild(state.bell);

    const logout = host.querySelector('.ax-btn-logout, .ix-btn-logout');
    if (logout && logout.parentElement === host) host.insertBefore(state.root, logout);
    else host.appendChild(state.root);

    state.backdrop = create('button', 'sl-notification-backdrop');
    state.backdrop.type = 'button';
    state.backdrop.hidden = true;
    state.backdrop.setAttribute('aria-label', 'Close notifications');
    state.backdrop.addEventListener('click', closeDrawer);

    state.drawer = create('aside', 'sl-notification-drawer');
    state.drawer.hidden = true;
    state.drawer.setAttribute('aria-label', 'Notifications');
    const head = create('div', 'sl-notification-head');
    const headText = create('div');
    headText.append(
      create('span', 'sl-notification-eyebrow', 'Sentinel Link'),
      create('h2', '', 'Notifications')
    );
    const close = create('button', 'sl-notification-close', '×');
    close.type = 'button';
    close.setAttribute('aria-label', 'Close notifications');
    close.addEventListener('click', closeDrawer);
    head.append(headText, close);

    const toolbar = create('div', 'sl-notification-toolbar');
    state.summary = create('span', 'sl-notification-summary', 'Loading notifications…');
    const toolbarActions = create('div', 'sl-notification-toolbar-actions');
    const desktopButton = create('button', 'sl-notification-text-button', 'Enable desktop alerts');
    desktopButton.type = 'button';
    desktopButton.dataset.notificationPermission = 'true';
    desktopButton.addEventListener('click', requestDesktopPermission);
    if (!('Notification' in window) || Notification.permission === 'denied') desktopButton.hidden = true;
    if ('Notification' in window && Notification.permission === 'granted') desktopButton.textContent = 'Desktop alerts on';
    const markAll = create('button', 'sl-notification-text-button', 'Mark all read');
    markAll.type = 'button';
    markAll.addEventListener('click', markAllRead);
    toolbarActions.append(desktopButton, markAll);
    toolbar.append(state.summary, toolbarActions);

    if (state.profile && ['admin', 'it_admin'].includes(state.profile.role)) {
      const compose = create('button', 'sl-notification-compose', '＋ Send notice');
      compose.type = 'button';
      compose.addEventListener('click', composeNotice);
      toolbar.appendChild(compose);
    }

    state.list = create('div', 'sl-notification-list');
    state.drawer.append(head, toolbar, state.list);
    document.body.append(state.backdrop, state.drawer);
    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') closeDrawer();
    });
    render();
  }

  async function load() {
    if (!state.user) return;
    const result = await client()
      .from('user_notifications')
      .select('id,kind,priority,title,message,action_key,entity_type,entity_id,metadata,requires_ack,read_at,acknowledged_at,created_at,expires_at')
      .eq('recipient_id', state.user.id)
      .order('created_at', { ascending: false })
      .limit(75);
    if (result.error) throw result.error;
    state.items = (result.data || []).filter((item) => !item.expires_at || new Date(item.expires_at) > new Date());
    render();
    showPendingCritical();
  }

  async function markRead(id, shouldRender) {
    const item = state.items.find((entry) => entry.id === id);
    if (!item || item.read_at) return;
    const result = await client().rpc('mark_notification_read', { p_notification_id: id });
    if (result.error) throw result.error;
    item.read_at = new Date().toISOString();
    if (shouldRender !== false) render();
    else updateBadge();
  }

  async function acknowledgeItem(id) {
    const result = await client().rpc('acknowledge_notification', { p_notification_id: id });
    if (result.error) throw result.error;
    const item = state.items.find((entry) => entry.id === id);
    if (item) {
      item.read_at = item.read_at || new Date().toISOString();
      item.acknowledged_at = new Date().toISOString();
    }
    closeCritical();
    render();
    showPendingCritical();
  }

  async function markAllRead() {
    try {
      const result = await client().rpc('mark_all_notifications_read');
      if (result.error) throw result.error;
      const now = new Date().toISOString();
      state.items.forEach((item) => { if (!item.read_at) item.read_at = now; });
      render();
    } catch (error) {
      notifyError(error, 'Could not mark notifications as read.');
    }
  }

  function notifyError(error, fallback) {
    const message = (error && error.message) || fallback;
    if (window.appDialog) window.appDialog.toast(message, { tone: 'danger' });
    else console.error(message);
  }

  async function requestDesktopPermission() {
    if (!('Notification' in window)) return;
    try {
      const permission = await Notification.requestPermission();
      const button = document.querySelector('[data-notification-permission]');
      if (button) {
        button.textContent = permission === 'granted' ? 'Desktop alerts on' : 'Desktop alerts unavailable';
        button.hidden = permission === 'denied';
      }
      if (permission === 'granted' && window.appDialog) {
        window.appDialog.toast('Desktop alerts enabled.', { tone: 'success' });
      }
    } catch (error) {
      notifyError(error, 'Desktop alerts could not be enabled.');
    }
  }

  function playCriticalSignal() {
    if (navigator.vibrate) navigator.vibrate([260, 120, 260, 120, 500]);
    try {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      if (!AudioContext) return;
      const audio = new AudioContext();
      const oscillator = audio.createOscillator();
      const gain = audio.createGain();
      oscillator.type = 'square';
      oscillator.frequency.setValueAtTime(740, audio.currentTime);
      oscillator.frequency.setValueAtTime(920, audio.currentTime + 0.22);
      gain.gain.setValueAtTime(0.0001, audio.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.08, audio.currentTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, audio.currentTime + 0.65);
      oscillator.connect(gain);
      gain.connect(audio.destination);
      oscillator.start();
      oscillator.stop(audio.currentTime + 0.7);
      oscillator.addEventListener('ended', function () { audio.close(); });
    } catch (_) {
      // Browsers may block audio until the page has received a user gesture.
    }
  }

  function showDesktop(item) {
    if (!('Notification' in window) || Notification.permission !== 'granted') return;
    if (!document.hidden && item.priority !== 'critical') return;
    try {
      const notification = new Notification(item.title, {
        body: item.message,
        icon: '../favicon.png',
        tag: item.id,
        requireInteraction: item.priority === 'critical',
      });
      notification.onclick = function () {
        window.focus();
        const url = actionUrl(item);
        if (url) location.href = url;
        notification.close();
      };
    } catch (_) {
      // The in-app notification remains available when OS alerts are blocked.
    }
  }

  function closeCritical() {
    if (!state.criticalLayer) return;
    state.criticalLayer.remove();
    state.criticalLayer = null;
    document.body.classList.remove('sl-critical-open');
  }

  function showPendingCritical() {
    if (state.criticalLayer) return;
    const item = pendingCritical()[0];
    if (!item) return;
    const layer = create('div', 'sl-critical-layer');
    const backdrop = create('div', 'sl-critical-backdrop');
    const dialog = create('section', 'sl-critical-dialog');
    dialog.setAttribute('role', 'alertdialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-labelledby', 'sl-critical-title');
    const siren = create('div', 'sl-critical-siren', '🚨');
    siren.setAttribute('aria-hidden', 'true');
    const eyebrow = create('div', 'sl-critical-eyebrow', 'IMMEDIATE ATTENTION');
    const title = create('h2', '', item.title);
    title.id = 'sl-critical-title';
    const message = create('p', 'sl-critical-message', item.message);
    const time = create('time', 'sl-critical-time', formatTime(item.created_at));
    const actions = create('div', 'sl-critical-actions');
    const acknowledge = create('button', 'sl-critical-acknowledge', 'Acknowledge alert');
    acknowledge.type = 'button';
    acknowledge.addEventListener('click', async function () {
      acknowledge.disabled = true;
      try {
        await acknowledgeItem(item.id);
      } catch (error) {
        acknowledge.disabled = false;
        notifyError(error, 'Could not acknowledge the emergency alert.');
      }
    });
    const url = actionUrl(item);
    if (url) {
      const view = create('button', 'sl-critical-view', 'Open incident report');
      view.type = 'button';
      view.addEventListener('click', async function () {
        try {
          await acknowledgeItem(item.id);
          location.href = url;
        } catch (error) {
          notifyError(error, 'Could not open the emergency alert.');
        }
      });
      actions.append(acknowledge, view);
    } else {
      actions.appendChild(acknowledge);
    }
    dialog.append(siren, eyebrow, title, message, time, actions);
    layer.append(backdrop, dialog);
    document.body.appendChild(layer);
    document.body.classList.add('sl-critical-open');
    state.criticalLayer = layer;
    acknowledge.focus();
  }

  async function composeNotice() {
    closeDrawer();
    if (!window.appDialog) {
      notifyError(null, 'The notice form is still loading. Try again.');
      return;
    }
    const isItAdmin = state.profile.role === 'it_admin';
    const audiences = isItAdmin
      ? [
          { value: 'all', label: 'Everyone' },
          { value: 'operations_heads', label: 'HR / Operations Heads' },
          { value: 'platform_admins', label: 'IT Admins' },
        ]
      : [
          { value: 'field', label: 'All field personnel' },
          { value: 'guards', label: 'Guards only' },
          { value: 'inspectors', label: 'Inspectors only' },
          { value: 'organization', label: 'Entire organization' },
        ];
    const values = await window.appDialog.form({
      title: 'Send notification',
      message: isItAdmin
        ? 'Publish a platform or maintenance notice.'
        : 'Send an operational notice to TwentyTwenty personnel.',
      icon: '🔔',
      confirmText: 'Send notification',
      busyText: 'Sending…',
      fields: [
        { name: 'audience', label: 'Audience', type: 'select', options: audiences, value: audiences[0].value, required: true },
        { name: 'priority', label: 'Priority', type: 'select', options: [
          { value: 'normal', label: 'Normal' },
          { value: 'high', label: 'High priority' },
          { value: 'critical', label: 'Critical — acknowledgement required' },
        ], value: 'normal', required: true },
        { name: 'title', label: 'Title', type: 'text', placeholder: 'Short notification title', required: true },
        { name: 'message', label: 'Message', type: 'textarea', placeholder: 'Clear instructions or important details', required: true },
      ],
      validate: function (form) {
        if (form.title.trim().length < 3) return 'Use a title of at least 3 characters.';
        if (form.message.trim().length < 5) return 'Use a message of at least 5 characters.';
        return null;
      },
    });
    if (!values) return;
    try {
      const result = await client().rpc('send_broadcast_notification', {
        p_audience: values.audience,
        p_title: values.title.trim(),
        p_message: values.message.trim(),
        p_priority: values.priority,
        p_requires_ack: values.priority === 'critical',
      });
      if (result.error) throw result.error;
      window.appDialog.toast(
        'Notification sent to ' + Number(result.data || 0) + ' recipient' + (Number(result.data || 0) === 1 ? '' : 's') + '.',
        { tone: 'success', duration: 5200 }
      );
    } catch (error) {
      notifyError(error, 'Could not send the notification.');
    }
  }

  function announce(item) {
    showDesktop(item);
    if (item.priority === 'critical') {
      playCriticalSignal();
      showPendingCritical();
    } else if (window.appDialog) {
      window.appDialog.toast(item.title + ': ' + item.message, {
        tone: item.priority === 'high' ? 'warning' : 'info',
        duration: item.priority === 'high' ? 7000 : 4800,
      });
    }
  }

  function subscribe() {
    if (state.channel) client().removeChannel(state.channel);
    state.channel = client()
      .channel('sentinel-notifications-' + state.user.id)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'user_notifications',
        filter: 'recipient_id=eq.' + state.user.id,
      }, function (payload) {
        if (payload.eventType === 'INSERT') {
          if (!state.items.some((item) => item.id === payload.new.id)) {
            state.items.unshift(payload.new);
            render();
            announce(payload.new);
          }
          return;
        }
        const index = state.items.findIndex((item) => item.id === (payload.new && payload.new.id));
        if (index >= 0) {
          state.items[index] = payload.new;
          render();
        }
      })
      .subscribe();
  }

  async function initialize(user) {
    if (!user || state.initializedFor === user.id) return;
    state.initializedFor = user.id;
    state.user = user;
    try {
      const profileResult = await client()
        .from('profiles')
        .select('id,role,active,organization_id')
        .eq('id', user.id)
        .maybeSingle();
      if (profileResult.error) throw profileResult.error;
      if (!profileResult.data || profileResult.data.active === false) return;
      state.profile = profileResult.data;
      mount();
      await load();
      subscribe();
    } catch (error) {
      state.initializedFor = null;
      console.error('Sentinel Link notifications could not start:', error);
    }
  }

  function stop() {
    if (state.channel && client()) client().removeChannel(state.channel);
    state.channel = null;
    state.initializedFor = null;
    state.user = null;
    state.items = [];
    closeCritical();
  }

  window.sentinelNotifications = {
    open: openDrawer,
    refresh: load,
    compose: composeNotice,
  };

  if (!client()) {
    console.error('Sentinel Link notifications require the Supabase client.');
    return;
  }

  client().auth.getSession().then(function (result) {
    const user = result.data && result.data.session && result.data.session.user;
    if (user) initialize(user);
  });
  client().auth.onAuthStateChange(function (event, session) {
    if (event === 'SIGNED_OUT') stop();
    else if (session && session.user) initialize(session.user);
  });
})();
