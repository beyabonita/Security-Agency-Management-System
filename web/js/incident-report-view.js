(function () {
  'use strict';

  const SUPABASE_ORIGIN = 'https://uqtupmpofjqrnefgrexm.supabase.co';
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
    return ['open', 'acknowledged', 'resolved'].includes(status) ? status : 'open';
  }

  function statusBadge(status) {
    const value = normalizedStatus(status);
    const cssClass = value === 'resolved'
      ? 'badge-resolved'
      : value === 'acknowledged' ? 'badge-ack' : 'badge-open';
    return `<span class="badge-status ${cssClass}">${value.charAt(0).toUpperCase() + value.slice(1)}</span>`;
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

  function render(target, options) {
    pauseCurrentVideo();
    const requestId = ++renderSequence;
    const incident = options.incident || {};
    const categoryLabel = options.categoryLabel || incident.category || 'Incident';
    const formatWhen = options.formatWhen || (() => '—');
    const photoSrc = options.photoSrc || null;
    const guardName = incident.guardName || 'Unknown guard';
    const guardEmail = incident.guardEmail || 'Not recorded';
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
    const mapUrl = hasCoordinates
      ? `https://www.google.com/maps?q=${encodeURIComponent(`${latitude},${longitude}`)}`
      : null;
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
            <div class="incident-evidence-block">
              <div class="incident-evidence-label"><span>Incident photo</span><span>Required capture</span></div>
              ${photoMarkup}
            </div>
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
                <div class="incident-meta-item is-wide"><span class="incident-meta-label">Guard account</span><span class="incident-meta-value">${escapeHtml(guardEmail)}</span></div>
                <div class="incident-meta-item"><span class="incident-meta-label">Captured</span><span class="incident-meta-value">${escapeHtml(capturedAt)}</span></div>
                <div class="incident-meta-item"><span class="incident-meta-label">Filed</span><span class="incident-meta-value">${escapeHtml(filedAt)}</span></div>
                <div class="incident-meta-item is-wide"><span class="incident-meta-label">Deployment site</span><span class="incident-meta-value">${escapeHtml(locationLabel)}</span></div>
                <div class="incident-meta-item is-wide"><span class="incident-meta-label">Coordinates</span><span class="incident-meta-value">${escapeHtml(coordinates)}</span></div>
              </div>
              ${mapUrl ? `<a class="incident-location-link" href="${escapeHtml(mapUrl)}" target="_blank" rel="noopener"><span>Open exact location in Maps</span><span aria-hidden="true">↗</span></a>` : ''}
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
              <div class="incident-response-block"><span class="incident-response-label">Reviewer note</span><p class="incident-report-copy">${escapeHtml(statusNote)}</p></div>
            </div>
          </section>
        </div>
      </div>`;
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
  }

  window.incidentReportView = Object.freeze({ render, loadVideo, close });
})();
