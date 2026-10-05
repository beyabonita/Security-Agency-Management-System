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
            tbody.innerHTML = `<tr><td colspan="11" class="records-empty"><span class="material-symbols-rounded">group_off</span><p>No matching personnel records found.</p></td></tr>`;
            return;
        }

        tbody.innerHTML = data.map(p => {
            const empBadgeClass = p.employmentStatus === 'Active' ? 'rec-badge-active' : (p.employmentStatus === 'Archived' || p.employmentStatus === 'Resigned' ? 'rec-badge-resigned' : 'rec-badge-expired');
            const contBadgeClass = p.contractStatus === 'Active' ? 'rec-badge-active' : (p.contractStatus === 'Pending' ? 'rec-badge-pending' : 'rec-badge-expired');
            const dutyClass = p.dutyCategory.toLowerCase() === 'regular' ? 'rec-badge-regular' : 'rec-badge-reliever';

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
            const statusClass = inc.isArchived ? 'rec-badge-expired' : (inc.status === 'resolved' ? 'rec-badge-resolved' : (inc.status === 'acknowledged' ? 'rec-badge-acknowledged' : 'rec-badge-open'));
            const statusText = inc.isArchived ? 'Archived' : inc.status;
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
                if (inc.isArchived || inc.status.toLowerCase() !== status) return false;
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
    }

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
        if (statusSel) statusSel.value = inc.status || incItem.status || 'open';

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
