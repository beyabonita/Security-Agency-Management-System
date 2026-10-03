/*
 * Compatibility facade for the legacy Operations Head/Inspector markup.
 *
 * The underlying client is the official Supabase browser SDK: it owns session
 * persistence, refresh, PostgREST, Edge Function, Storage, and Realtime
 * behavior. This small facade is deliberately temporary; it keeps old
 * Firebase-shaped page calls working while page modules are migrated one by
 * one to window.appSupabase.
 */
(function () {
  'use strict';

  // Only the loopback development server may inject an alternate backend.
  const localConfig = ['localhost','127.0.0.1','[::1]'].includes(location.hostname)
    ? window.SENTINEL_LOCAL_SUPABASE : null;
  const URL = localConfig?.url || 'https://uqtupmpofjqrnefgrexm.supabase.co';
  const KEY = localConfig?.key || 'sb_publishable_WhymBQujSZgXctoTe0hwCA_Q4DRCPcw';
  const SESSION_KEY = localConfig ? 'sentinel_local_supabase_session' : 'security_time_tracker_supabase_session';
  // Every portal page loads the version-pinned official UMD SDK immediately
  // before this bridge. Keeping loading in markup avoids runtime injection and
  // guarantees the legacy inline scripts below it see firebase.auth() ready.
  if (!window.supabase?.createClient) {
    console.error('Security Agency Management System could not load the official Supabase client. Check the network and reload.');
    return;
  }

  const client = window.supabase.createClient(URL, KEY, {
    auth: {
      storageKey: SESSION_KEY,
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  });
  window.appSupabase = client;
  if (document.currentScript?.src) {
    const presenceScript = document.createElement('script');
    presenceScript.src = new globalThis.URL('account-presence.js', document.currentScript.src).href;
    document.head.appendChild(presenceScript);
  }
  window.SENTINEL_LIVE_TRACKING_ENABLED = true;

  const toLegacyUser = (session) => session?.user
    ? { uid: session.user.id, email: session.user.email }
    : null;
  const authListeners = new Set();
  let currentUser = null;
  let initialSessionResolved = false;
  let resolveInitialSession;
  const initialSession = new Promise((resolve) => { resolveInitialSession = resolve; });

  function notifyAuth() {
    for (const listener of authListeners) listener(currentUser);
  }

  // Register this immediately after createClient so the SDK handles the
  // INITIAL_SESSION, refresh, sign-in, and sign-out events consistently.
  client.auth.onAuthStateChange((_event, session) => {
    currentUser = toLegacyUser(session);
    if (!initialSessionResolved) {
      initialSessionResolved = true;
      resolveInitialSession(currentUser);
    }
    notifyAuth();
  });

  const tables = {
    users: 'profiles',
    schedules: 'schedules',
    locations: 'locations',
    incidents: 'incidents',
  };

  const toDb = (collection, data) => {
    const keys = {
      userId: 'user_id', organizationId: 'organization_id', locationId: 'location_id',
      locationLabel: 'location_label', locationAddress: 'location_address',
      startAt: 'start_at', endAt: 'end_at', dutyCategory: 'duty_category',
      dutyDays: 'duty_days', dtrPeriod: 'dtr_period', dutyDate: 'duty_date', markedDone: 'marked_done', completedAt: 'completed_at',
      completedBy: 'completed_by', firstName: 'first_name', middleInitial: 'middle_initial',
      lastName: 'last_name', deviceId: 'device_id', deviceLocked: 'device_locked',
      createdAt: 'created_at', updatedAt: 'updated_at', updatedBy: 'updated_by',
      photoData: 'photo_data', radius: 'radius_meters', name: 'guard_name',
    };
    const allowed = {
      users: ['id', 'username', 'email', 'first_name', 'middle_initial', 'last_name', 'role', 'organization_id', 'active', 'device_id', 'device_locked', 'created_at'],
      locations: ['id', 'label', 'address', 'latitude', 'longitude', 'radius_meters', 'active', 'created_at'],
      schedules: ['id', 'user_id', 'location_id', 'location_label', 'location_address', 'guard_name', 'start_at', 'end_at', 'duty_date', 'dtr_period', 'duty_category', 'duty_days', 'approval_status', 'marked_done', 'completed_at', 'completed_by', 'created_at'],
      incidents: ['id', 'user_id', 'guard_name', 'guard_email', 'category', 'description', 'photo_data', 'latitude', 'longitude', 'location_label', 'status', 'status_note', 'created_at', 'updated_at', 'updated_by', 'deletion_requested_at'],
    };
    return Object.fromEntries(
      Object.entries(data)
        .filter(([, value]) => value !== undefined)
        .map(([key, value]) => [
          keys[key] || key,
          value instanceof Date
            ? value.toISOString()
            : value && value.__serverTimestamp
              ? new Date().toISOString()
              : value,
        ])
        .filter(([key]) => !allowed[collection] || allowed[collection].includes(key)),
    );
  };

  const fromDb = (row) => {
    const keys = {
      user_id: 'userId', organization_id: 'organizationId', location_id: 'locationId',
      assigned_location_id: 'assignedLocationId', inspector_id: 'inspectorId',
      employment_category: 'employmentCategory', duty_days_total: 'dutyDaysTotal',
      contract_start_date: 'contractStartDate', contract_end_date: 'contractEndDate',
      duty_days: 'dutyDays', duty_date: 'dutyDate', dtr_period: 'dtrPeriod', location_label: 'locationLabel', location_address: 'locationAddress',
      start_at: 'startAt', end_at: 'endAt', marked_done: 'markedDone',
      completed_at: 'completedAt', completed_by: 'completedBy', first_name: 'firstName',
      middle_initial: 'middleInitial', last_name: 'lastName', device_id: 'deviceId',
      device_locked: 'deviceLocked', created_at: 'createdAt', updated_at: 'updatedAt',
      updated_by: 'updatedBy', captured_at: 'capturedAt', filed_at: 'filedAt',
      photo_data: 'photoData', radius_meters: 'radius', guard_name: 'guardName',
      guard_email: 'guardEmail', incident_title: 'incidentTitle',
      detailed_narrative: 'detailedNarrative', immediate_action: 'immediateAction',
      status_note: 'statusNote', review_history: 'reviewHistory', video_path: 'videoPath',
      video_duration_seconds: 'videoDurationSeconds',
    };
    const timeKey = /(_at|createdAt|updatedAt|startAt|endAt|completedAt|capturedAt|filedAt)$/;
    return Object.fromEntries(Object.entries(row).map(([key, value]) => {
      const mapped = keys[key] || key;
      return [mapped, timeKey.test(mapped) && typeof value === 'string'
        ? { toDate: () => new Date(value) }
        : value];
    }));
  };

  const snapshot = (rows) => ({
    docs: rows.map((row) => ({ id: String(row.id), exists: true, data: () => fromDb(row) })),
    empty: !rows.length,
    size: rows.length,
    forEach(fn) { this.docs.forEach(fn); },
  });
  const docSnapshot = (row) => ({
    id: row ? String(row.id) : '',
    exists: !!row,
    data: () => row ? fromDb(row) : undefined,
  });

  class Query {
    constructor(collection, id, filters = [], limit = null, order = null) {
      this.collectionName = collection;
      this.id = id;
      this.filters = filters;
      this.take = limit;
      this.order = order;
    }

    where(key, op, value) {
      return new Query(this.collectionName, this.id, [...this.filters, [key, op, value]], this.take, this.order);
    }
    limit(count) { return new Query(this.collectionName, this.id, this.filters, count, this.order); }
    orderBy(key, direction) { return new Query(this.collectionName, this.id, this.filters, this.take, [key, direction]); }
    doc(id) { return new Query(this.collectionName, id); }
    collection(name) {
      return name === 'records'
        ? new Query('attendance_punches', null, [['user_id', '==', this.id]])
        : new Query(name);
    }

    async _rows() {
      let query = client.from(tables[this.collectionName] || this.collectionName).select();
      for (const [key, op, value] of this.filters) {
        const column = Object.keys(toDb('', { [key]: value }))[0];
        if (op === '==') query = query.eq(column, value);
      }
      if (this.id) query = query.eq('id', this.id);
      if (this.collectionName === 'attendance_punches' && this.filters.some(([key]) => key === 'user_id')) {
        query = query.order('punch_date', { ascending: false });
      }
      if (this.order) {
        const column = Object.keys(toDb('', { [this.order[0]]: null }))[0];
        query = query.order(column, { ascending: this.order[1] !== 'desc' });
      }
      if (this.take) query = query.limit(this.take);
      const { data, error } = await query;
      if (error) throw error;
      return data || [];
    }

    async get() {
      const rows = await this._rows();
      if (this.collectionName === 'attendance_punches') {
        const grouped = {};
        rows.forEach((row) => {
          const day = row.punch_date;
          grouped[day] ||= { id: day };
          grouped[day][row.punch_type] = {
            time: { toDate: () => new Date(row.punched_at) },
            latitude: row.latitude,
            longitude: row.longitude,
            withinGeofence: row.within_geofence,
            locationLabel: row.location_label,
          };
        });
        return snapshot(Object.values(grouped));
      }
      return this.id ? docSnapshot(rows[0]) : snapshot(rows);
    }

    onSnapshot(fn, fail) {
      this.get().then(fn).catch(fail);
      const table = tables[this.collectionName];
      if (!table || this.id || this.collectionName === 'attendance_punches') return () => {};
      const channel = client.channel(`legacy-${table}-${Math.random()}`)
        .on('postgres_changes', { event: '*', schema: 'public', table }, () => this.get().then(fn).catch(fail))
        .subscribe();
      return () => client.removeChannel(channel);
    }

    async add(data) {
      const { data: row, error } = await client
        .from(tables[this.collectionName] || this.collectionName)
        .insert(toDb(this.collectionName, data))
        .select()
        .single();
      if (error) throw error;
      return { id: row.id };
    }
    async set(data) {
      const { error } = await client
        .from(tables[this.collectionName] || this.collectionName)
        .upsert({ id: this.id, ...toDb(this.collectionName, data) });
      if (error) throw error;
    }
    async update(data) {
      if (this.collectionName === 'incidents') {
        const { error } = await client.rpc('update_incident_status', {
          p_incident_id: this.id,
          p_status: data.status,
          p_status_note: data.statusNote || '',
        });
        if (error) throw error;
        return;
      }
      const { error } = await client
        .from(tables[this.collectionName] || this.collectionName)
        .update(toDb(this.collectionName, data))
        .eq('id', this.id);
      if (error) throw error;
    }
    async delete() {
      const { error } = await client
        .from(tables[this.collectionName] || this.collectionName)
        .delete()
        .eq('id', this.id);
      if (error) throw error;
    }
  }

  const auth = {
    get currentUser() { return currentUser; },
    onAuthStateChanged(listener) {
      authListeners.add(listener);
      if (initialSessionResolved) queueMicrotask(() => listener(currentUser));
      else initialSession.then((user) => {
        if (authListeners.has(listener)) listener(user);
      });
      return () => authListeners.delete(listener);
    },
    async signInWithEmailAndPassword(email, password) {
      const { data, error } = await client.auth.signInWithPassword({ email, password });
      if (error) throw error;
      return { user: toLegacyUser(data.session || { user: data.user }) };
    },
    async signOut() {
      const { error } = await client.auth.signOut();
      if (error) throw error;
    },
  };

  const secondaryAuth = {
    async createUserWithEmailAndPassword(email, password) {
      const { data, error } = await client.functions.invoke('admin-create-user', { body: { email, password } });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      return { user: { uid: data.id, email } };
    },
    async signOut() {},
  };
  const secondaryApp = { auth: () => secondaryAuth };

  window.firebase = {
    initializeApp(_config, name) { return name ? secondaryApp : { auth: () => auth }; },
    app(name) { return name === 'secondary' ? secondaryApp : { auth: () => auth }; },
    auth: () => auth,
    firestore: () => ({ collection: (name) => new Query(name) }),
  };
  window.firebase.firestore = () => ({ collection: (name) => new Query(name) });
  window.firebase.firestore.FieldValue = { serverTimestamp: () => ({ __serverTimestamp: true }) };
  window.firebase.firestore.Timestamp = { fromDate: (date) => date };
  window.auth = auth;
  window.db = { collection: (name) => new Query(name) };
  window.applyAdminRoleNavigation = () => {};

})();
