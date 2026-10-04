(function () {
  'use strict';

  const SUPABASE_ORIGIN = 'https://syyofdcynuzgergqlaqj.supabase.co';
  const VIDEO_BUCKET = 'incident-videos';
  const VIDEO_PATH_PATTERN = /^[0-9a-f-]{36}\/[A-Za-z0-9._-]+$/i;
  let renderSequence = 0;

  function escapeHtml(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function normalizedStatus(status) {
    return ['under_investigation', 'escalated', 'acknowledged', 'resolved', 'open'].includes(status) ? status : 'open';
  }

  function statusBadge(status) {
    const value = normalizedStatus(status);
    let cssClass = 'badge-open';
    let label = 'Open';
    if (value === 'resolved') {
      cssClass = 'badge-resolved';
      label = 'Resolved';
    } else if (value === 'under_investigation') {
      cssClass = 'badge-investigating';
      label = 'Under investigation';
    } else if (value === 'escalated') {
      cssClass = 'badge-escalated';
      label = 'Escalated';
    } else if (value === 'acknowledged') {
      cssClass = 'badge-ack';
      label = 'Acknowledged';
    }
    return `<span class="badge-status ${cssClass}">${label}</span>`;
  }

  function pauseCurrentVideo() {
    const player = document.getElementById('incidentEvidenceVideo');
    if (!player) return;
    try {
      player.pause();
      player.removeAttribute('src');
      player.load();
    } catch (_) {}
  }

  let miniMapInstance = null;
  let leafletLoadingPromise = null;

  function destroyMiniMap() {
    if (miniMapInstance) {
      try {
        miniMapInstance.remove();
      } catch (_) {}
      miniMapInstance = null;
    }
  }

  function loadLeaflet() {
    if (window.L) return Promise.resolve(window.L);
    if (leafletLoadingPromise) return leafletLoadingPromise;
    leafletLoadingPromise = new Promise((resolve) => {
      if (!document.querySelector('link[href*="leaflet"]')) {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
        document.head.appendChild(link);
      }
      const script = document.createElement('script');
      script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
      script.onload = () => resolve(window.L || null);
      script.onerror = () => resolve(null);
      document.head.appendChild(script);
    });
    return leafletLoadingPromise;
  }

  function mountMiniMap(target, latitude, longitude, locationLabel, coordinates, requestId) {
    loadLeaflet().then((L) => {
      if (!L || requestId !== renderSequence) return;
      const container = target.querySelector('#incidentMiniMap');
      if (!container || !container.isConnected) return;

      destroyMiniMap();

      try {
        const map = L.map(container, {
          center: [latitude, longitude],
          zoom: 16,
          zoomControl: false,
          scrollWheelZoom: false,
          attributionControl: false
        });

        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
          maxZoom: 19
        }).addTo(map);

        L.control.zoom({ position: 'bottomright' }).addTo(map);

        const pinIcon = L.divIcon({
          className: 'sl-location-marker',
          html: '<span class="sl-location-marker__pin" aria-hidden="true"></span>',
          iconSize: [30, 30],
          iconAnchor: [15, 30],
          popupAnchor: [0, -28]
        });

        const marker = L.marker([latitude, longitude], { icon: pinIcon }).addTo(map);
        if (locationLabel) {
          marker.bindPopup(`<strong>${escapeHtml(locationLabel)}</strong><br><span style="font-size:0.75rem;color:var(--sl-muted,#64748b);">${escapeHtml(coordinates)}</span>`);
        }

        miniMapInstance = map;

        const modalEl = target.closest('.modal') || document.getElementById('detailModal');
        if (modalEl) {
          modalEl.addEventListener('shown.bs.modal', () => {
            if (requestId === renderSequence && miniMapInstance) {
              miniMapInstance.invalidateSize();
            }
          }, { once: true });
        }

        requestAnimationFrame(() => {
          if (requestId === renderSequence && miniMapInstance) {
            miniMapInstance.invalidateSize();
          }
        });
        setTimeout(() => {
          if (requestId === renderSequence && miniMapInstance) {
            miniMapInstance.invalidateSize();
          }
        }, 300);
      } catch (err) {
        console.warn('Incident mini map initialization failed:', err);
      }
    }).catch(() => {});
  }

  function safeSignedVideoUrl(value) {
    try {
      const url = new URL(String(value || ''), SUPABASE_ORIGIN);
      const expectedPrefix = `/storage/v1/object/sign/${VIDEO_BUCKET}/`;
      return url.protocol === 'https:'
        && url.origin === SUPABASE_ORIGIN
        && url.pathname.startsWith(expectedPrefix)
        ? url.href
        : null;
    } catch (_) {
      return null;
    }
  }

  function evidenceSummary(incident, photoSrc) {
    const parts = [];
    if (photoSrc) parts.push('Photo');
    if (incident.videoPath) parts.push(`${Number(incident.videoDurationSeconds) || 15}s video`);
    return parts.length ? parts.join(' + ') : 'No media';
  }

  function reviewHistoryMarkup(incident, formatWhen) {
    const history = Array.isArray(incident.reviewHistory) ? incident.reviewHistory : [];
    const roles = { inspector: 'Inspector', admin: 'Operations Head', operations_head: 'Operations Head', it_admin: 'IT Admin', user: 'Guard', guard: 'Guard' };
    if (!history.length) {
      return '<div class="incident-response-block"><span class="incident-response-label">Reviewer</span><p class="incident-report-copy">'
        + (incident.updatedBy ? 'Reviewer details not recorded for this earlier update.' : 'No recorded review yet.') + '</p></div>';
    }
    return history.slice().reverse().filter(entry => entry && typeof entry === 'object').map(entry => {
      const action = entry.status === 'under_investigation'
        ? 'Under investigation by'
        : entry.status === 'escalated'
        ? 'Escalated by'
        : entry.status === 'acknowledged'
        ? 'Acknowledged by'
        : entry.status === 'resolved'
        ? 'Resolved by'
        : 'Noted by';
      const name = entry.reviewer_name || 'Name not recorded';
      const role = roles[entry.reviewer_role] || 'Staff';
      const date = new Date(entry.reviewed_at || '');
      const when = Number.isNaN(date.getTime()) ? 'Time not recorded' : formatWhen({ toDate: () => date });
      return `<div class="incident-response-block">
        <span class="incident-response-label">${action}</span>
        <p class="incident-report-copy"><strong>${escapeHtml(name)} · ${escapeHtml(role)}</strong><br>${escapeHtml(when)}</p>
        ${entry.note ? `<p class="incident-report-copy">${escapeHtml(entry.note)}</p>` : ''}
      </div>`;
    }).join('');
  }

  function render(target, options) {
    pauseCurrentVideo();
    const requestId = ++renderSequence;
    const incident = options.incident || {};
    const categoryLabel = options.categoryLabel || incident.category || 'Incident';
    const formatWhen = options.formatWhen || (() => '—');
    const photoSrc = options.photoSrc || null;
    const guardName = incident.guardName || 'Unknown guard';
    const guardEmail = incident.guardEmail && !incident.guardEmail.toLowerCase().endsWith('.auth') ? incident.guardEmail : 'Email not added';
    const capturedAt = formatWhen(incident.capturedAt || incident.createdAt);
    const filedAt = formatWhen(incident.filedAt || incident.createdAt);
    const updatedAt = incident.updatedAt ? formatWhen(incident.updatedAt) : 'No review update';
    const narrative = incident.detailedNarrative || incident.description || 'No narrative supplied.';
    const immediateAction = incident.immediateAction || 'Emergency alert filed through the Security Agency Management System.';
    const statusNote = incident.statusNote || 'No reviewer note yet.';
    const locationLabel = incident.locationLabel || 'No site label recorded';
    const hasCoordinates = incident.latitude != null && incident.longitude != null
      && Number.isFinite(Number(incident.latitude)) && Number.isFinite(Number(incident.longitude));
    const latitude = hasCoordinates ? Number(incident.latitude) : null;
    const longitude = hasCoordinates ? Number(incident.longitude) : null;
    const coordinates = hasCoordinates ? `${latitude.toFixed(5)}, ${longitude.toFixed(5)}` : 'Not recorded';
    const reference = String(incident.id || '').slice(0, 8).toUpperCase() || 'PENDING';
    const duration = Math.max(1, Math.min(15, Number(incident.videoDurationSeconds) || 15));
    const photoMarkup = photoSrc
      ? `<img src="${escapeHtml(photoSrc)}" class="incident-report-photo" alt="Incident evidence captured by ${escapeHtml(guardName)}">`
      : '<div class="incident-evidence-empty">No incident photo is available.</div>';
    const videoMarkup = incident.videoPath
      ? `<div class="incident-evidence-block">
          <div class="incident-evidence-label"><span>Evidence video</span><span>${duration} seconds</span></div>
          <div id="incidentVideoEvidence" data-video-path="${escapeHtml(incident.videoPath)}">
            <div class="incident-video-loading" role="status">Preparing secure video playback…</div>
          </div>
        </div>`
      : `<div class="incident-evidence-block">
          <div class="incident-evidence-label"><span>Evidence video</span><span>Not recorded</span></div>
          <div class="incident-evidence-empty">No video was attached to this incident.</div>
        </div>`;

    target.innerHTML = `
      <div class="incident-report-summary">
        <div class="incident-report-summary-main">
          <span class="badge-cat">${escapeHtml(categoryLabel)}</span>
          ${statusBadge(incident.status)}
        </div>
        <span class="incident-report-reference">REPORT #${escapeHtml(reference)}</span>
      </div>
      <div class="incident-report-grid">
        <section class="incident-report-card" aria-labelledby="incidentEvidenceHeading">
          <div class="incident-report-card-head">
            <h3 id="incidentEvidenceHeading">Captured evidence</h3>
            <span>${escapeHtml(evidenceSummary(incident, photoSrc))}</span>
          </div>
          <div class="incident-report-card-body incident-evidence-stack">
            ${photoSrc || !incident.videoPath ? `<div class="incident-evidence-block">
              <div class="incident-evidence-label"><span>Incident photo</span><span>Captured evidence</span></div>
              ${photoMarkup}
            </div>` : ''}
            ${videoMarkup}
          </div>
        </section>
        <div class="incident-report-column">
          <section class="incident-report-card" aria-labelledby="incidentDetailsHeading">
            <div class="incident-report-card-head"><h3 id="incidentDetailsHeading">Report details</h3><span>Filed record</span></div>
            <div class="incident-report-card-body">
              <div class="incident-meta-grid">
                <div class="incident-meta-item"><span class="incident-meta-label">Guard</span><span class="incident-meta-value">${escapeHtml(guardName)}</span></div>
                <div class="incident-meta-item"><span class="incident-meta-label">Incident type</span><span class="incident-meta-value">${escapeHtml(categoryLabel)}</span></div>
                <div class="incident-meta-item is-wide"><span class="incident-meta-label">Guard account</span><span class="incident-meta-value" data-guard-email>${escapeHtml(guardEmail)}</span></div>
                <div class="incident-meta-item"><span class="incident-meta-label">Captured</span><span class="incident-meta-value">${escapeHtml(capturedAt)}</span></div>
                <div class="incident-meta-item"><span class="incident-meta-label">Filed</span><span class="incident-meta-value">${escapeHtml(filedAt)}</span></div>
                <div class="incident-meta-item is-wide"><span class="incident-meta-label">Deployment site</span><span class="incident-meta-value">${escapeHtml(locationLabel)}</span></div>
                <div class="incident-meta-item is-wide"><span class="incident-meta-label">Coordinates</span><span class="incident-meta-value">${escapeHtml(coordinates)}</span></div>
              </div>
              ${hasCoordinates ? `<div class="incident-mini-map-wrap"><div id="incidentMiniMap" class="incident-mini-map" role="region" aria-label="Incident location map"></div></div>` : ''}
            </div>
          </section>
          <section class="incident-report-card" aria-labelledby="incidentNarrativeHeading">
            <div class="incident-report-card-head"><h3 id="incidentNarrativeHeading">Incident narrative</h3><span>Guard statement</span></div>
            <div class="incident-report-card-body"><p class="incident-report-copy">${escapeHtml(narrative)}</p></div>
          </section>
          <section class="incident-report-card" aria-labelledby="incidentResponseHeading">
            <div class="incident-report-card-head"><h3 id="incidentResponseHeading">Response and review</h3><span>${escapeHtml(updatedAt)}</span></div>
            <div class="incident-report-card-body">
              <div class="incident-response-block"><span class="incident-response-label">Immediate action</span><p class="incident-report-copy">${escapeHtml(immediateAction)}</p></div>
              ${Array.isArray(incident.reviewHistory) && incident.reviewHistory.length ? '' : `<div class="incident-response-block"><span class="incident-response-label">Reviewer note</span><p class="incident-report-copy">${escapeHtml(statusNote)}</p></div>`}
              ${reviewHistoryMarkup(incident, formatWhen)}
            </div>
          </section>
        </div>
      </div>`;
    destroyMiniMap();
    if (hasCoordinates) {
      mountMiniMap(target, latitude, longitude, locationLabel, coordinates, requestId);
    }
    if (guardEmail === 'Email not added' && incident.userId && window.appSupabase?.from) {
      Promise.resolve().then(() => window.appSupabase.from('profiles').select('email').eq('id', incident.userId).maybeSingle()).then(result => {
        if (requestId !== renderSequence || result.error) return;
        const email = result.data?.email;
        const field = target.querySelector('[data-guard-email]');
        if (field && email && !email.toLowerCase().endsWith('.auth')) field.textContent = email;
      }).catch(() => {});
    }
    return requestId;
  }

  function renderVideoError(host, incident, requestId, message) {
    if (requestId !== renderSequence || !host.isConnected) return;
    host.innerHTML = `<div class="incident-video-feedback is-error">${escapeHtml(message)}</div>
      <div class="incident-video-actions"><button type="button" class="incident-evidence-action" data-retry-video>Retry video</button></div>`;
    host.querySelector('[data-retry-video]')?.addEventListener('click', () => loadVideo(incident, requestId));
  }

  async function loadVideo(incident, requestId) {
    const host = document.getElementById('incidentVideoEvidence');
    const path = String(incident?.videoPath || '');
    if (!host || requestId !== renderSequence || !VIDEO_PATH_PATTERN.test(path)) {
      if (host) renderVideoError(host, incident, requestId, 'The saved video reference is invalid.');
      return;
    }
    host.innerHTML = '<div class="incident-video-loading" role="status">Preparing secure video playback…</div>';
    try {
      const { data, error } = await window.appSupabase.storage
        .from(VIDEO_BUCKET)
        .createSignedUrl(path, 900);
      if (requestId !== renderSequence || !host.isConnected) return;
      if (error) throw error;
      const signedUrl = safeSignedVideoUrl(data?.signedUrl);
      if (!signedUrl) throw new Error('Invalid signed video URL');

      host.innerHTML = `<div class="incident-video-frame">
          <video id="incidentEvidenceVideo" controls playsinline preload="metadata" src="${escapeHtml(signedUrl)}">
            Your browser does not support HTML video playback.
          </video>
        </div>
        <div class="incident-video-feedback" id="incidentVideoFeedback">Secure evidence link ready for 15 minutes.</div>
        <div class="incident-video-actions">
          <a class="incident-evidence-action" href="${escapeHtml(signedUrl)}" target="_blank" rel="noopener">Open video separately</a>
        </div>`;
      const player = document.getElementById('incidentEvidenceVideo');
      const feedback = document.getElementById('incidentVideoFeedback');
      player?.addEventListener('loadedmetadata', () => {
        if (feedback) feedback.textContent = 'Video ready. Use the controls to play, pause, seek, or enter full screen.';
      }, { once: true });
      player?.addEventListener('error', () => {
        if (!feedback) return;
        feedback.classList.add('is-error');
        feedback.textContent = 'The browser could not play this recording. Try opening the video separately.';
      }, { once: true });
    } catch (error) {
      console.warn('Incident video playback unavailable', { name: error?.name, status: error?.status });
      renderVideoError(host, incident, requestId, 'Video playback is temporarily unavailable or you do not have access.');
    }
  }

  function close() {
    renderSequence += 1;
    pauseCurrentVideo();
    destroyMiniMap();
  }

  async function refreshEmails(records) {
    const legacy = records.filter(row => row.userId && (!row.guardEmail || row.guardEmail.toLowerCase().endsWith('.auth')));
    const ids = [...new Set(legacy.map(row => row.userId))];
    try {
      const emails = new Map();
      for (let offset = 0; offset < ids.length; offset += 100) {
        const result = await window.appSupabase.from('profiles').select('id,email').in('id', ids.slice(offset, offset + 100));
        if (result.error) return;
        for (const profile of result.data || []) if (profile.email && !profile.email.toLowerCase().endsWith('.auth')) emails.set(profile.id, profile.email);
      }
      for (const row of legacy) if (emails.has(row.userId)) row.guardEmail = emails.get(row.userId);
    } catch (_) { /* Keep the report accessible if profile lookup is unavailable. */ }
  }
  window.incidentReportView = Object.freeze({ render, loadVideo, close, refreshEmails });
})();
