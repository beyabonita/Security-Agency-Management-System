/**
 * Records & Reports Module Controller
 * Handles Personnel Masterlist, Summary of Incident Report, and Monthly Attendance Summary.
 */
(function() {
    'use strict';

    let client = null;
    let currentTab = 'personnel';

    // In-memory caches for fast filtering
    let allPersonnel = [];
    let allLocations = [];
    let allIncidents = [];
    let allSchedules = [];
    let allSessions = [];

    const MONTH_NAMES = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    ];

    const INCIDENT_CATEGORIES = {
        theft: 'Theft',
        trespassing: 'Trespassing',
        medical: 'Medical Emergency',
        disturbance: 'Disturbance',
        property_damage: 'Property Damage',
        suspicious_activity: 'Suspicious Activity',
        fire_hazard: 'Fire Hazard',
        other: 'Other Incident'
    };

    function escapeHtml(str) {
        if (str === null || str === undefined) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    function formatDate(val) {
        if (!val) return '—';
        try {
            const d = new Date(val);
            if (isNaN(d.getTime())) return '—';
            return d.toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' });
        } catch (_) {
            return '—';
        }
    }

    function formatTime(val) {
        if (!val) return '';
        try {
            const d = new Date(val);
            if (isNaN(d.getTime())) return '';
            return d.toLocaleTimeString('en-PH', { hour: '2-digit', minute: '2-digit', hour12: true });
        } catch (_) {
            return '';
        }
    }

    // ==========================================
    // Tab Navigation
    // ==========================================
    function setupTabs() {
        const tabBtns = document.querySelectorAll('.records-tab-btn');
        tabBtns.forEach(btn => {
            btn.addEventListener('click', function() {
                const target = this.dataset.tab;
                switchTab(target);
            });
        });

        // URL hash support
        const hash = window.location.hash.replace('#', '');
        if (['personnel', 'incidents', 'attendance'].includes(hash)) {
            switchTab(hash);
        }
    }

    function switchTab(tabName) {
        currentTab = tabName;
        window.location.hash = tabName;

        document.querySelectorAll('.records-tab-btn').forEach(btn => {
            btn.classList.toggle('is-active', btn.dataset.tab === tabName);
        });

        document.querySelectorAll('.records-panel').forEach(panel => {
            panel.classList.toggle('is-active', panel.id === `panel-${tabName}`);
        });
    }

    // ==========================================
    // Dropdown Population
    // ==========================================
    function populateDropdowns() {
        // Personnel dropdowns in all 3 sections
        const personnelSelectors = [
            document.getElementById('pmFilterPersonnel'),
            document.getElementById('irFilterPersonnel'),
            document.getElementById('attFilterPersonnel')
        ];

        personnelSelectors.forEach(select => {
            if (!select) return;
            const currentVal = select.value;
            select.innerHTML = '<option value="">All Personnel</option>';
            allPersonnel.forEach(p => {
                const opt = document.createElement('option');
                opt.value = p.id;
                opt.textContent = p.fullName;
                select.appendChild(opt);
            });
            select.value = currentVal;
        });

        // Location / Post dropdowns in all 3 sections
        const locationSelectors = [
            document.getElementById('pmFilterPost'),
            document.getElementById('irFilterLocation'),
            document.getElementById('attFilterLocation')
        ];

        locationSelectors.forEach(select => {
            if (!select) return;
            const currentVal = select.value;
            select.innerHTML = '<option value="">All Posts / Sites</option>';
            allLocations.forEach(loc => {
                const opt = document.createElement('option');
                opt.value = loc.id;
                opt.textContent = loc.label;
                select.appendChild(opt);
            });
            select.value = currentVal;
        });

        // Attendance Month & Year dropdowns
        const monthSelect = document.getElementById('attFilterMonth');
        const yearSelect = document.getElementById('attFilterYear');
        const now = new Date();

        if (monthSelect) {
            monthSelect.innerHTML = '';
            MONTH_NAMES.forEach((name, idx) => {
                const opt = document.createElement('option');
                opt.value = String(idx + 1).padStart(2, '0');
                opt.textContent = name;
                if (idx === now.getMonth()) opt.selected = true;
                monthSelect.appendChild(opt);
            });
        }

        if (yearSelect) {
            yearSelect.innerHTML = '';
            const currentYear = now.getFullYear();
            for (let y = currentYear; y >= currentYear - 3; y--) {
                const opt = document.createElement('option');
                opt.value = String(y);
                opt.textContent = String(y);
                if (y === currentYear) opt.selected = true;
                yearSelect.appendChild(opt);
            }
        }
    }

    // ==========================================
    // SECTION 1: Personnel Masterlist
    // ==========================================
    function renderPersonnelTable(data) {
        const tbody = document.getElementById('pmTableBody');
        const countBadge = document.getElementById('pmCount');
        if (!tbody) return;

        if (countBadge) countBadge.textContent = `${data.length} records`;

        if (!data.length) {
            tbody.innerHTML = `<tr><td colspan="12" class="records-empty"><span class="material-symbols-rounded">group_off</span><p>No matching personnel records found.</p></td></tr>`;
            return;
        }

        tbody.innerHTML = data.map(p => {
            const empBadgeClass = p.employmentStatus === 'Active' ? 'rec-badge-active' : (p.employmentStatus === 'Archived' || p.employmentStatus === 'Resigned' ? 'rec-badge-resigned' : 'rec-badge-expired');
            const contBadgeClass = p.contractStatus === 'Active' ? 'rec-badge-active' : (p.contractStatus === 'Pending' ? 'rec-badge-pending' : 'rec-badge-expired');
            const dutyClass = p.dutyCategory.toLowerCase() === 'regular' ? 'rec-badge-regular' : 'rec-badge-reliever';
            const deviceHtml = p.registeredDeviceId
                ? `<div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;">
                     <span class="rec-badge rec-badge-active" style="font-size:0.68rem;" title="${escapeHtml(p.registeredDeviceInfo || '')}">
                       <span class="material-symbols-rounded" style="font-size:12px;vertical-align:-2px;">smartphone</span>
                       ${escapeHtml(p.registeredDeviceId)}
                     </span>
                     <button type="button" class="records-btn-reset" style="padding:2px 6px;font-size:10px;" onclick="window.resetGuardDeviceBinding('${p.id}', '${escapeHtml(p.fullName)}')" title="Reset bound phone if guard changed device">Reset</button>
                   </div>`
                : '<span class="col-muted" style="font-size:0.75rem;">Not bound yet</span>';

            return `<tr${p.isArchived ? ' class="opacity-75"' : ''}>
                <td class="col-id">${escapeHtml(p.personnelId)}</td>
                <td class="col-primary">${escapeHtml(p.fullName)}</td>
                <td>${escapeHtml(p.gender)}</td>
                <td>${escapeHtml(p.contactNumber)}</td>
                <td><span class="rec-badge ${dutyClass}">${escapeHtml(p.dutyCategory)}</span></td>
                <td><span class="rec-badge ${empBadgeClass}">${escapeHtml(p.employmentStatus)}</span></td>
                <td><span class="rec-badge ${contBadgeClass}">${escapeHtml(p.contractStatus)}</span></td>
                <td>${escapeHtml(p.dateHired)}</td>
                <td class="col-muted">${p.dateEnded
                    ? (p.dateEndedExpired
                        ? `<span class="rec-badge rec-badge-expired" style="font-size:0.7rem;">${escapeHtml(p.dateEnded)}</span>`
                        : escapeHtml(p.dateEnded))
                    : '<span class="rec-badge rec-badge-active" style="font-size:0.7rem;opacity:0.75;">Still Active</span>'}</td>
                <td>${escapeHtml(p.assignedPost)}</td>
                <td>${escapeHtml(p.shift)}</td>
                <td>${deviceHtml}</td>
            </tr>`;
        }).join('');
    }

    function applyPersonnelFilter() {
        const personnelId = document.getElementById('pmFilterPersonnel')?.value || '';
        const dutyCategory = (document.getElementById('pmFilterCategory')?.value || '').toLowerCase();
        const empStatus = (document.getElementById('pmFilterEmpStatus')?.value || '').toLowerCase();
        const contractStatus = (document.getElementById('pmFilterContractStatus')?.value || '').toLowerCase();
        const post = document.getElementById('pmFilterPost')?.value || '';

        const filtered = allPersonnel.filter(p => {
            if (personnelId && p.id !== personnelId) return false;
            if (dutyCategory && p.dutyCategory.toLowerCase() !== dutyCategory) return false;
            if (empStatus && p.employmentStatus.toLowerCase() !== empStatus) return false;
            if (contractStatus === 'no_active_contract') {
                if (p.contractStatus.toLowerCase() === 'active') return false;
            } else if (contractStatus && p.contractStatus.toLowerCase() !== contractStatus) {
                return false;
            }
            if (post && p.locationId !== post && !p.assignedPost.toLowerCase().includes(post.toLowerCase())) return false;
            return true;
        });

        renderPersonnelTable(filtered);
    }

    function resetPersonnelFilter() {
        document.getElementById('pmFilterPersonnel').value = '';
        document.getElementById('pmFilterCategory').value = '';
        document.getElementById('pmFilterEmpStatus').value = '';
        document.getElementById('pmFilterContractStatus').value = '';
        document.getElementById('pmFilterPost').value = '';
        renderPersonnelTable(allPersonnel);
    }

    // ==========================================
    // SECTION 2: Summary of Incident Report
    // ==========================================
    function renderIncidentTable(data) {
        const tbody = document.getElementById('irTableBody');
        const countBadge = document.getElementById('irCount');
        if (!tbody) return;

        if (countBadge) countBadge.textContent = `${data.length} reports`;

        if (!data.length) {
            tbody.innerHTML = `<tr><td colspan="6" class="records-empty"><span class="material-symbols-rounded">policy</span><p>No matching incident reports found.</p></td></tr>`;
            return;
        }

        tbody.innerHTML = data.map(inc => {
            const statusClass = inc.isArchived ? 'rec-badge-expired' : (inc.status === 'resolved' ? 'rec-badge-resolved' : (inc.status === 'escalated' ? 'rec-badge-escalated' : (inc.status === 'acknowledged' ? 'rec-badge-acknowledged' : 'rec-badge-investigating')));
            const statusText = inc.isArchived ? 'Archived' : (inc.status === 'escalated' ? 'Escalated' : (inc.status === 'acknowledged' ? 'Acknowledged' : (inc.status === 'resolved' ? 'Resolved' : 'Under investigation')));
            return `<tr onclick="openIncidentDetail('${inc.id}')" style="cursor:pointer;" title="Click to view full incident details">
                <td class="col-id">${escapeHtml(inc.displayId)}</td>
                <td class="col-primary">
                    <div>${escapeHtml(inc.clientPost)}</div>
                    <div style="font-size:11.5px; color:var(--brand-text-muted,#64748b);">${escapeHtml(inc.categoryLabel)}</div>
                </td>
                <td><span class="rec-badge ${statusClass}">${escapeHtml(statusText)}</span></td>
                <td>${escapeHtml(inc.reportedBy)}</td>
                <td style="max-width:260px; white-space:normal;">${escapeHtml(inc.responseSummary)}</td>
                <td>${escapeHtml(inc.evidenceSummary)}</td>
            </tr>`;
        }).join('');
    }

    function applyIncidentFilter() {
        const dateFrom = document.getElementById('irFilterDateFrom')?.value || '';
        const dateTo = document.getElementById('irFilterDateTo')?.value || '';
        const personnelId = document.getElementById('irFilterPersonnel')?.value || '';
        const category = document.getElementById('irFilterCategory')?.value || '';
        const status = (document.getElementById('irFilterStatus')?.value || '').toLowerCase();
        const locationId = document.getElementById('irFilterLocation')?.value || '';

        const filtered = allIncidents.filter(inc => {
            if (dateFrom && inc.rawDate < dateFrom) return false;
            if (dateTo && inc.rawDate > dateTo) return false;
            if (personnelId && inc.userId !== personnelId) return false;
            if (category && inc.rawCategory !== category) return false;

            if (status === 'archived') {
                if (!inc.isArchived) return false;
            } else if (status === 'all') {
                // Return both active and archived
            } else if (status) {
                const incStatus = (inc.status || '').toLowerCase();
                const effectiveStatus = (incStatus === 'open') ? 'under_investigation' : incStatus;
                if (inc.isArchived || effectiveStatus !== status) return false;
            } else {
                // Default "" (All active statuses): exclude archived
                if (inc.isArchived) return false;
            }

            if (locationId) {
                const locObj = allLocations.find(l => l.id === locationId);
                const locLabel = locObj ? locObj.label.toLowerCase() : '';
                if (!inc.clientPost.toLowerCase().includes(locLabel)) return false;
            }
            return true;
        });

        renderIncidentTable(filtered);
    }

    function resetIncidentFilter() {
        document.getElementById('irFilterDateFrom').value = '';
        document.getElementById('irFilterDateTo').value = '';
        document.getElementById('irFilterPersonnel').value = '';
        document.getElementById('irFilterCategory').value = '';
        document.getElementById('irFilterStatus').value = '';
        document.getElementById('irFilterLocation').value = '';
        renderIncidentTable(allIncidents);
    }

    // ==========================================
    // SECTION 3: Monthly Attendance Summary
    // ==========================================
    function calculateAttendanceSummary(monthStr, yearStr) {
        // monthStr is 01..12, yearStr is 2026
        const targetPrefix = `${yearStr}-${monthStr}`;

        // Group schedules for that month by guard
        const monthSchedules = allSchedules.filter(s => (s.duty_date || '').startsWith(targetPrefix));
        const monthSessions = allSessions.filter(s => (s.clock_in_at || '').startsWith(targetPrefix));

        return allPersonnel.map(guard => {
            const guardSchedules = monthSchedules.filter(s => s.user_id === guard.id);
            const guardSessions = monthSessions.filter(s => s.user_id === guard.id);

            const totalScheduledDays = new Set(guardSchedules.map(s => s.duty_date)).size;

            let totalPresent = 0;
            let totalLate = 0;
            let totalOvertimeMins = 0;

            guardSessions.forEach(sess => {
                if (sess.clock_in_at) {
                    totalPresent++;
                    // Check if late compared to scheduled start
                    const sched = guardSchedules.find(s => s.id === sess.schedule_id);
                    if (sched && sched.start_at && new Date(sess.clock_in_at) > new Date(sched.start_at)) {
                        totalLate++;
                    }
                }
                if (sess.overtime_minutes && sess.overtime_minutes > 0) {
                    totalOvertimeMins += Number(sess.overtime_minutes);
                }
            });

            // Estimated absence: scheduled days without attendance punch
            const totalAbsent = Math.max(0, totalScheduledDays - totalPresent);
            const totalOtHours = (totalOvertimeMins / 60).toFixed(1);

            return {
                guardId: guard.id,
                personnel: guard.fullName,
                assignedPost: guard.assignedPost,
                locationId: guard.locationId,
                totalScheduled: totalScheduledDays,
                totalPresent,
                totalAbsent,
                totalLate,
                totalOvertimeHours: Number(totalOtHours) > 0 ? `${totalOtHours} hrs` : '0.0 hrs',
                status: totalAbsent > 0 ? 'With Absences' : (totalPresent > 0 ? 'Complete' : 'Incomplete')
            };
        });
    }

    function renderAttendanceTable(data) {
        const tbody = document.getElementById('attTableBody');
        const countBadge = document.getElementById('attCount');
        if (!tbody) return;

        if (countBadge) countBadge.textContent = `${data.length} records`;

        if (!data.length) {
            tbody.innerHTML = `<tr><td colspan="6" class="records-empty"><span class="material-symbols-rounded">event_busy</span><p>No attendance records found for this period.</p></td></tr>`;
            return;
        }

        tbody.innerHTML = data.map(att => {
            return `<tr>
                <td class="col-primary">${escapeHtml(att.personnel)}</td>
                <td style="text-align:center; font-weight:600;">${att.totalScheduled}</td>
                <td style="text-align:center; color:#166534; font-weight:600;">${att.totalPresent}</td>
                <td style="text-align:center; color:${att.totalAbsent > 0 ? '#991b1b' : 'inherit'}; font-weight:600;">${att.totalAbsent}</td>
                <td style="text-align:center; color:${att.totalLate > 0 ? '#b45309' : 'inherit'}; font-weight:600;">${att.totalLate}</td>
                <td style="text-align:center;">${escapeHtml(att.totalOvertimeHours)}</td>
            </tr>`;
        }).join('');
    }

    function applyAttendanceFilter() {
        const month = document.getElementById('attFilterMonth')?.value || '10';
        const year = document.getElementById('attFilterYear')?.value || '2026';
        const locationId = document.getElementById('attFilterLocation')?.value || '';
        const personnelId = document.getElementById('attFilterPersonnel')?.value || '';
        const status = document.getElementById('attFilterStatus')?.value || '';

        const fullMonthlyData = calculateAttendanceSummary(month, year);

        const filtered = fullMonthlyData.filter(att => {
            if (personnelId && att.guardId !== personnelId) return false;
            if (locationId && att.locationId !== locationId) return false;
            if (status && att.status.toLowerCase() !== status.toLowerCase()) return false;
            return true;
        });

        renderAttendanceTable(filtered);
        renderForceAttendanceVerificationQueue(month, year, personnelId, locationId);
    }

    function haversineMeters(lat1, lon1, lat2, lon2) {
        if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return null;
        const R = 6371000;
        const toRad = d => (Number(d) * Math.PI) / 180;
        const dLat = toRad(lat2 - lat1);
        const dLon = toRad(lon2 - lon1);
        const a = Math.sin(dLat / 2) ** 2 +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
        return Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
    }

    function renderForceAttendanceVerificationQueue(month, year, personnelId, locationId) {
        const tbody = document.getElementById('forceAttTableBody');
        const countBadge = document.getElementById('forceAttCount');
        if (!tbody) return;

        const targetPrefix = `${year}-${month}`;
        const matchingSessions = (allSessions || []).filter(s => {
            const dutyPrefix = (s.duty_date || s.clock_in_at || '').slice(0, 7);
            if (dutyPrefix && dutyPrefix !== targetPrefix && !s.force_attendance_requested) return false;
            if (personnelId && s.user_id !== personnelId) return false;
            if (locationId && s.location_id !== locationId) return false;
            return s.force_attendance_requested || s.clock_in_face_photo || s.device_id || s.distance_from_post_meters != null || s.clock_in_latitude != null;
        }).sort((a, b) => new Date(b.clock_in_at || 0) - new Date(a.clock_in_at || 0)).slice(0, 25);

        if (countBadge) countBadge.textContent = `${matchingSessions.length} sessions`;

        if (!matchingSessions.length) {
            tbody.innerHTML = `<tr><td colspan="7" class="records-empty"><span class="material-symbols-rounded">check_circle</span><p>No Force Attendance or proximity verification sessions for this filter.</p></td></tr>`;
            return;
        }

        tbody.innerHTML = matchingSessions.map(sess => {
            const guard = allPersonnel.find(p => p.id === sess.user_id);
            const guardName = guard ? guard.fullName : 'Guard';
            const postObj = allLocations.find(l => l.id === sess.location_id);
            const postName = (sess.location_label || postObj?.label || 'Assigned Post').split(' · ')[0];

            const distPost = sess.distance_from_post_meters != null
                ? Math.round(Number(sess.distance_from_post_meters))
                : (postObj ? haversineMeters(postObj.latitude, postObj.longitude, sess.clock_in_latitude, sess.clock_in_longitude) : null);

            const dualDist = sess.dual_point_distance_meters != null
                ? Math.round(Number(sess.dual_point_distance_meters))
                : haversineMeters(sess.clock_in_latitude, sess.clock_in_longitude, sess.clock_out_latitude, sess.clock_out_longitude);

            const proximityHtml = `
                <div style="font-size:11.5px; line-height:1.35;">
                    <div><strong>Post Offset:</strong> ${distPost != null ? `${distPost} m` : 'In Geofence'}</div>
                    <div style="color:#64748b;"><strong>In↔Out Drift:</strong> ${dualDist != null ? `${dualDist} m` : '—'}</div>
                </div>`;

            const devId = sess.device_id || guard?.registeredDeviceId || '';
            const devInfo = sess.device_info || guard?.registeredDeviceInfo || '';
            const devVerified = sess.device_verified !== false;
            const deviceHtml = devId
                ? `<span class="rec-badge ${devVerified ? 'rec-badge-active' : 'rec-badge-expired'}" style="font-size:0.68rem;" title="${escapeHtml(devInfo)}">
                     <span class="material-symbols-rounded" style="font-size:12px;vertical-align:-2px;">smartphone</span>
                     ${escapeHtml(devId)}
                   </span>`
                : '<span class="col-muted" style="font-size:11px;">Standard Mobile</span>';

            const faceHtml = sess.clock_in_face_photo
                ? `<button type="button" class="records-btn-export" style="padding:3px 8px;font-size:11px;" onclick="window.previewAttendanceFacePhoto('${sess.id}')">
                     <span class="material-symbols-rounded" style="font-size:13px;">person</span> View Geotagged Face
                   </button>`
                : '<span class="col-muted" style="font-size:11px;">Verified on Device</span>';

            let statusHtml = '<span class="rec-badge rec-badge-active">Within Geofence</span>';
            if (sess.force_attendance_requested) {
                const st = (sess.force_attendance_status || 'pending').toLowerCase();
                const badgeCls = st === 'approved' ? 'rec-badge-active' : (st === 'rejected' ? 'rec-badge-expired' : 'rec-badge-pending');
                statusHtml = `<div><span class="rec-badge ${badgeCls}">Force: ${escapeHtml(st.toUpperCase())}</span></div>
                    ${sess.force_attendance_reason ? `<div style="font-size:11px;color:#64748b;margin-top:2px;">Reason: ${escapeHtml(sess.force_attendance_reason)}</div>` : ''}`;
            }

            const canDecide = sess.force_attendance_requested && (sess.force_attendance_status || 'pending') === 'pending';
            const actionsHtml = canDecide
                ? `<div style="display:flex;gap:6px;">
                     <button type="button" class="records-btn-apply" style="padding:4px 8px;font-size:11px;background:#16a34a;" onclick="window.decideForceAttendanceSession('${sess.id}', 'approved')">Approve</button>
                     <button type="button" class="records-btn-reset" style="padding:4px 8px;font-size:11px;color:#dc2626;border-color:#dc2626;" onclick="window.decideForceAttendanceSession('${sess.id}', 'rejected')">Reject</button>
                   </div>`
                : '<span class="col-muted" style="font-size:11px;">—</span>';

            return `<tr>
                <td>
                    <div class="col-primary">${escapeHtml(guardName)}</div>
                    <div style="font-size:11px;color:#64748b;">${escapeHtml(postName)}</div>
                </td>
                <td style="font-size:12px;">
                    <div>${escapeHtml(formatDate(sess.duty_date || sess.clock_in_at))}</div>
                    <div style="color:#64748b;">In: ${escapeHtml(formatTime(sess.clock_in_at) || '—')} • Out: ${escapeHtml(formatTime(sess.clock_out_at) || 'Open')}</div>
                </td>
                <td>${proximityHtml}</td>
                <td>${deviceHtml}</td>
                <td>${faceHtml}</td>
                <td>${statusHtml}</td>
                <td>${actionsHtml}</td>
            </tr>`;
        }).join('');
    }

    window.decideForceAttendanceSession = async function(sessionId, decision) {
        if (!client || !sessionId) return;
        const note = window.prompt(
            decision === 'approved'
                ? 'Optional approval note for this Force Attendance (e.g. Verified Seminar / Off-Site Duty):'
                : 'Reason for rejecting this Force Attendance:',
            decision === 'approved' ? 'Approved by Operations Head' : ''
        );
        if (note === null) return;
        try {
            const { error } = await client.rpc('decide_force_attendance', {
                p_session_id: sessionId,
                p_decision: decision,
                p_note: note
            });
            if (error) throw error;
            const sess = allSessions.find(s => s.id === sessionId);
            if (sess) {
                sess.force_attendance_status = decision;
                sess.force_attendance_review_note = note;
            }
            applyAttendanceFilter();
            if (window.appDialog?.toast) {
                window.appDialog.toast(`Force Attendance ${decision}.`, { tone: decision === 'approved' ? 'success' : 'warning' });
            }
        } catch (err) {
            alert(err?.message || 'Could not update Force Attendance status.');
        }
    };

    window.previewAttendanceFacePhoto = function(sessionId) {
        const sess = allSessions.find(s => s.id === sessionId);
        if (!sess || !sess.clock_in_face_photo) return;
        const w = window.open('', '_blank', 'width=540,height=640');
        if (!w) return;
        w.document.write(`<!DOCTYPE html><html><head><title>Geotagged Attendance Face Photo</title></head>
            <body style="margin:0;background:#0f172a;color:#f8fafc;font-family:system-ui,sans-serif;display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:100vh;padding:16px;box-sizing:border-box;">
                <h3 style="margin:0 0 10px;font-size:15px;">Geotagged Face &amp; Device Verification</h3>
                <img src="${sess.clock_in_face_photo}" alt="Geotagged Face Verification" style="max-width:100%;max-height:78vh;border-radius:12px;border:2px solid #dc2626;" />
                <p style="margin:10px 0 0;font-size:12px;color:#94a3b8;">Device: ${escapeHtml(sess.device_info || '')} (${escapeHtml(sess.device_id || 'Bound')})</p>
            </body></html>`);
        w.document.close();
    };

    window.resetGuardDeviceBinding = async function(guardId, guardName) {
        if (!client || !guardId) return;
        const ok = confirm(`Reset the registered mobile phone binding for ${guardName}? Their next login/punch will bind their new phone.`);
        if (!ok) return;
        try {
            const { error } = await client.rpc('reset_guard_registered_device', { p_guard_id: guardId });
            if (error) throw error;
            const p = allPersonnel.find(item => item.id === guardId);
            if (p) {
                p.registeredDeviceId = null;
                p.registeredDeviceInfo = null;
            }
            applyPersonnelFilter();
            if (window.appDialog?.toast) {
                window.appDialog.toast(`Device binding reset for ${guardName}.`, { tone: 'success' });
            }
        } catch (err) {
            alert(err?.message || 'Could not reset device binding.');
        }
    };

    function resetAttendanceFilter() {
        const now = new Date();
        document.getElementById('attFilterMonth').value = String(now.getMonth() + 1).padStart(2, '0');
        document.getElementById('attFilterYear').value = String(now.getFullYear());
        document.getElementById('attFilterLocation').value = '';
        document.getElementById('attFilterPersonnel').value = '';
        document.getElementById('attFilterStatus').value = '';
        applyAttendanceFilter();
    }

    // ==========================================
    // Export Data Helper
    // ==========================================
    window.exportTableToCSV = function(tableId, filename) {
        const table = document.getElementById(tableId);
        if (!table) return;

        const rows = Array.from(table.querySelectorAll('tr'));
        const csvContent = rows.map(row => {
            const cells = Array.from(row.querySelectorAll('th, td'));
            return cells.map(cell => {
                let text = cell.innerText.replace(/"/g, '""').trim();
                return `"${text}"`;
            }).join(',');
        }).join('\n');

        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = filename || 'records_export.csv';
        link.click();
    };

    // ==========================================
    // Data Loading & Initialization
    // ==========================================
    async function loadData() {
        client = window.appSupabase;
        if (!client) return;

        try {
            // Load Profiles (Personnel)
            const profRes = await client.from('profiles')
                .select('*')
                .order('last_name', { ascending: true });

            const profiles = profRes.data || [];

            // Load Locations
            const locRes = await client.from('locations').select('*');
            allLocations = locRes.data || [];

            // Load Schedules
            const schedRes = await client.from('schedules').select('*');
            allSchedules = schedRes.data || [];

            // Load Attendance Sessions
            const sessRes = await client.from('attendance_sessions').select('*');
            allSessions = sessRes.data || [];

            // Load Incidents
            const incRes = await client.from('incidents').select('*').order('created_at', { ascending: false });
            const incidents = incRes.data || [];

            // Normalize Personnel Records
            allPersonnel = profiles.filter(p => p.role === 'user' || p.role === 'guard').map((p, idx) => {
                const latestSched = allSchedules
                    .filter(s => s.user_id === p.id)
                    .sort((a, b) => new Date(b.start_at || 0) - new Date(a.start_at || 0))[0];

                const fullName = [p.first_name, p.middle_name || p.middle_initial, p.last_name]
                    .filter(Boolean).join(' ') || p.username || 'Guard';

                const personnelId = p.personnel_id || `SEC-${new Date(p.created_at || Date.now()).getFullYear()}-${String(idx + 1).padStart(4, '0')}`;
                const gender = p.gender || (idx % 2 === 0 ? 'Male' : 'Female');
                const contactNumber = p.mobile_number || '—';
                const dutyCategory = p.employment_category || p.duty_category || latestSched?.duty_category || 'Regular';
                const employmentStatus = p.removed_at ? 'Archived' : (p.active ? 'Active' : 'Inactive');
                const contractStatus = p.contract_status || (p.active ? 'Active' : 'Expired');
                const dateHired = formatDate(p.date_hired || p.created_at);

                // Date Ended logic:
                // 1. Archived guard → show removal date
                // 2. Contract guard with past end date → show contract end date (expired)
                // 3. Still active → null (renders as "Still Active" badge)
                let dateEnded = null;
                let dateEndedExpired = false;
                if (p.removed_at) {
                    dateEnded = formatDate(p.removed_at);
                } else if (p.contract_end_date) {
                    const today = new Date();
                    today.setHours(0, 0, 0, 0);
                    const contractEnd = new Date(p.contract_end_date);
                    if (contractEnd < today) {
                        dateEnded = formatDate(p.contract_end_date);
                        dateEndedExpired = true;
                    }
                }

                let assignedPost = 'Unassigned';
                let locationId = '';
                if (latestSched && latestSched.location_label) {
                    assignedPost = latestSched.location_label.split(' · ')[0];
                    locationId = latestSched.location_id || '';
                }

                let shift = '—';
                if (latestSched && latestSched.start_at && latestSched.end_at) {
                    shift = `${formatTime(latestSched.start_at)} – ${formatTime(latestSched.end_at)}`;
                }

                return {
                    id: p.id,
                    personnelId,
                    fullName,
                    gender,
                    contactNumber,
                    dutyCategory: dutyCategory.charAt(0).toUpperCase() + dutyCategory.slice(1),
                    employmentStatus,
                    contractStatus,
                    dateHired,
                    dateEnded,
                    dateEndedExpired,
                    assignedPost,
                    locationId,
                    shift,
                    registeredDeviceId: p.registered_device_id || null,
                    registeredDeviceInfo: p.registered_device_info || null,
                    isArchived: !!p.removed_at
                };
            });

            // Normalize Incident Records
            allIncidents = incidents.map((inc, idx) => {
                const displayId = `INC-${new Date(inc.created_at || Date.now()).getFullYear()}-${String(idx + 1).padStart(3, '0')}`;
                const clientPost = inc.location_label ? inc.location_label.split(' · ')[0] : 'Deployment Post';
                const rawDate = (inc.created_at || '').split('T')[0];
                const rawCategory = inc.category || 'other';
                const categoryLabel = INCIDENT_CATEGORIES[rawCategory] || rawCategory;

                let evidenceSummary = 'None';
                if (inc.video_path) {
                    evidenceSummary = `Video (${inc.video_duration_seconds || 15}s)${inc.photo_data ? ' + Photo' : ''}`;
                } else if (inc.photo_data) {
                    evidenceSummary = 'Photo Attached';
                }

                return {
                    id: inc.id,
                    displayId,
                    clientPost,
                    status: (inc.status || 'open').toLowerCase(),
                    reportedBy: inc.guard_name || 'Guard',
                    responseSummary: inc.status_note || inc.description || 'No summary notes.',
                    evidenceSummary,
                    rawDate,
                    rawCategory,
                    categoryLabel,
                    userId: inc.user_id,
                    isArchived: !!inc.archived_at,
                    archivedAt: inc.archived_at,
                    raw: inc
                };
            });

            // Populate UI dropdowns
            populateDropdowns();

            // Initial Renders
            renderPersonnelTable(allPersonnel);
            renderIncidentTable(allIncidents);
            applyAttendanceFilter();

        } catch (err) {
            console.error('Error loading records:', err);
        }
    }

    // ==========================================
    // Incident Detail Modal Handler
    // ==========================================
    let selectedId = null;
    let detailModal = null;

    function openIncidentDetail(id) {
        selectedId = id;
        const incItem = allIncidents.find(i => i.id === id);
        if (!incItem) return;
        const inc = incItem.raw || incItem;
        const categoryLabel = INCIDENT_CATEGORIES[inc.category || incItem.rawCategory] || inc.category || incItem.categoryLabel || 'Incident';

        const modalTitleEl = document.getElementById('modalTitle');
        if (modalTitleEl) modalTitleEl.textContent = 'Incident report — ' + (inc.guard_name || inc.guardName || incItem.reportedBy || 'Guard');

        const photoSrc = inc.photo_data
            ? (inc.photo_data.startsWith('data:') ? inc.photo_data : 'data:image/jpeg;base64,' + inc.photo_data)
            : (inc.photoData || '');

        if (window.incidentReportView && document.getElementById('modalBody')) {
            const requestId = window.incidentReportView.render(document.getElementById('modalBody'), {
                incident: {
                    ...inc,
                    guardName: inc.guard_name || inc.guardName || incItem.reportedBy,
                    guardEmail: inc.guard_email || inc.guardEmail,
                    createdAt: inc.created_at || inc.createdAt,
                    capturedAt: inc.captured_at || inc.capturedAt,
                    filedAt: inc.filed_at || inc.filedAt,
                    videoPath: inc.video_path || inc.videoPath,
                    videoDurationSeconds: inc.video_duration_seconds || inc.videoDurationSeconds,
                    statusNote: inc.status_note || inc.statusNote,
                    reviewHistory: inc.review_history || inc.reviewHistory || [],
                    detailedNarrative: inc.detailed_narrative || inc.description,
                    locationLabel: inc.location_label || inc.locationLabel || incItem.clientPost,
                    archivedAt: inc.archived_at || inc.archivedAt
                },
                categoryLabel,
                photoSrc,
                formatWhen: function(ts) {
                    if (!ts) return '—';
                    const d = typeof ts === 'string' ? new Date(ts) : (ts.toDate ? ts.toDate() : new Date(ts));
                    if (isNaN(d.getTime())) return '—';
                    return d.toLocaleString('en-PH', {
                        month: 'short', day: 'numeric', year: 'numeric',
                        hour: 'numeric', minute: '2-digit', hour12: true
                    });
                }
            });

            if (inc.video_path || inc.videoPath) {
                window.incidentReportView.loadVideo({
                    ...inc,
                    videoPath: inc.video_path || inc.videoPath
                }, requestId);
            }
        }

        const statusSel = document.getElementById('statusSelect');
        if (statusSel) {
            const rawStatus = inc.status || incItem.status || '';
            statusSel.value = (rawStatus && rawStatus !== 'open') ? rawStatus : 'under_investigation';
        }

        const statusNoteEl = document.getElementById('statusNote');
        if (statusNoteEl) statusNoteEl.value = inc.status_note || inc.statusNote || '';

        const archiveBtn = document.getElementById('archiveIncidentBtn');
        if (archiveBtn) archiveBtn.textContent = incItem.isArchived ? 'Unarchive report' : 'Archive report';

        const modalEl = document.getElementById('detailModal');
        if (modalEl && window.bootstrap?.Modal) {
            if (!detailModal) detailModal = new window.bootstrap.Modal(modalEl);
            detailModal.show();
        }
    }

    window.openIncidentDetail = openIncidentDetail;

    // ==========================================
    // Event Listeners Binding
    // ==========================================
    function bindEvents() {
        document.getElementById('pmBtnApply')?.addEventListener('click', applyPersonnelFilter);
        document.getElementById('pmBtnReset')?.addEventListener('click', resetPersonnelFilter);

        document.getElementById('irBtnApply')?.addEventListener('click', applyIncidentFilter);
        document.getElementById('irBtnReset')?.addEventListener('click', resetIncidentFilter);

        document.getElementById('attBtnApply')?.addEventListener('click', applyAttendanceFilter);
        document.getElementById('attBtnReset')?.addEventListener('click', resetAttendanceFilter);

        document.getElementById('archiveIncidentBtn')?.addEventListener('click', async function() {
            if (!selectedId || !client) return;
            const incItem = allIncidents.find(i => i.id === selectedId);
            if (!incItem) return;
            const isArchived = incItem.isArchived;

            const confirmed = window.appDialog ? await window.appDialog.confirm(
                isArchived ? 'Restore this incident report to active status?' : 'Archive this incident report? It will be safely stored in records.',
                { title: isArchived ? 'Restore emergency report?' : 'Archive emergency report?', confirmText: isArchived ? 'Restore report' : 'Archive report' }
            ) : confirm(isArchived ? 'Restore this report?' : 'Archive this report?');

            if (!confirmed) return;

            try {
                const { error } = await client.rpc('archive_incident_report', { p_incident_id: selectedId, p_archive: !isArchived });
                if (error) throw new Error(error.message || 'Archiving failed');

                incItem.isArchived = !isArchived;
                incItem.archivedAt = !isArchived ? new Date().toISOString() : null;
                if (incItem.raw) incItem.raw.archived_at = incItem.archivedAt;

                if (detailModal) detailModal.hide();
                applyIncidentFilter();
                if (window.appDialog) window.appDialog.toast(isArchived ? 'Report restored to active.' : 'Report archived successfully.', { tone: 'success' });
            } catch (err) {
                if (window.appDialog) window.appDialog.toast(err.message, { tone: 'danger' });
                else alert(err.message);
            }
        });

        document.getElementById('saveStatusBtn')?.addEventListener('click', async function() {
            if (!selectedId || !client) return;
            const nextStatus = document.getElementById('statusSelect')?.value;
            const statusNote = (document.getElementById('statusNote')?.value || '').trim();

            if (nextStatus === 'resolved' && statusNote.length < 5) {
                if (window.appDialog) window.appDialog.toast('Add a resolution note of at least 5 characters before closing.', { tone: 'warning' });
                return;
            }

            try {
                const { error } = await client.rpc('update_incident_status', {
                    p_incident_id: selectedId,
                    p_status: nextStatus,
                    p_status_note: statusNote
                });
                if (error) throw new Error(error.message || 'Status update failed.');

                const incItem = allIncidents.find(i => i.id === selectedId);
                if (incItem) {
                    incItem.status = nextStatus;
                    if (incItem.raw) {
                        incItem.raw.status = nextStatus;
                        incItem.raw.status_note = statusNote;
                    }
                }

                if (detailModal) detailModal.hide();
                applyIncidentFilter();
                if (window.appDialog) window.appDialog.toast('Incident status updated successfully.', { tone: 'success' });
            } catch (err) {
                if (window.appDialog) window.appDialog.toast(err.message, { tone: 'danger' });
                else alert(err.message);
            }
        });
    }

    // Initialize on DOM ready
    window.addEventListener('DOMContentLoaded', async () => {
        setupTabs();
        bindEvents();
        await loadData();
    });

})();
