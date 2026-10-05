# Context Diagram (DFD Level 0): Security Agency Management System

## Overview

The **Context Diagram (Data Flow Diagram - Level 0)** defines the external boundary of the **Security Agency Management System (Sentinel Link)**. It illustrates the primary process (**Process 0**) and its bidirectional data exchanges with the four external human entities (terminators) interacting with the system across the web and mobile platforms:

1. **Super Admin** *(System / IT Administrator)*
2. **Operations Head** *(Agency Administrator / Management)*
3. **Inspector** *(Field Operations Supervisor)*
4. **Security Guard** *(Mobile App Operator / Field Guard)*

---

## 1. Context Diagram (Mermaid)

```mermaid
flowchart TD
    %% Center Process
    P0(["0<br/><b>Security Agency Management System</b><br/><i>(Web Administration & Mobile Platform)</i>"])

    %% External Entities
    SA["<b>Super Admin</b><br/><i>(IT Administrator)</i>"]
    OH["<b>Operations Head</b><br/><i>(Agency Administrator)</i>"]
    IN["<b>Inspector</b><br/><i>(Field Supervisor)</i>"]
    SG["<b>Security Guard</b><br/><i>(Mobile App User)</i>"]

    %% Super Admin Flows
    SA -->|1. Login Credentials & Auth Requests<br/>2. Privileged Account Provisioning<br/>3. Device Binding Resets & Permissions<br/>4. Security & Config Settings<br/>5. System Diagnostic Commands| P0
    P0 -->|1. Access Authorization & Session Status<br/>2. System Health & Diagnostic Logs<br/>3. Account Security & Audit Trail Records<br/>4. Privileged Account Lists & Activity| SA

    %% Operations Head Flows
    OH -->|1. Login Credentials & Account Updates<br/>2. Personnel Records (Duty Category, Contract Dates)<br/>3. Client Companies & Deployment Posts<br/>4. Geofence Coordinates & Radius Settings<br/>5. Duty Rosters & Shifts (Day/Night Assignments)<br/>6. Request Approvals (Relief, Swap, Overtime)<br/>7. DTR Adjustments & Incident Resolutions| P0
    P0 -->|1. Access Authorization & Role Permissions<br/>2. Real-Time Live Guard Map & Tracking Data<br/>3. Daily Time Records (DTR) & Attendance Logs<br/>4. Incident Reports with Photo/Video Evidence<br/>5. Guard Absence, Relief & Shift Swap Requests<br/>6. Deployment History & Accomplishment Reports| OH

    %% Inspector Flows
    IN -->|1. Login Credentials & Profile Updates<br/>2. Post Inspection Logs & Field Audit Remarks<br/>3. Compliance Checklists & Performance Notes<br/>4. Field Incident Notes & Verification<br/>5. Emergency Post Relocation Notes| P0
    P0 -->|1. Access Authorization & Scoped Permissions<br/>2. Assigned Guard Roster & Detachment Posts<br/>3. Authorized Live Guard Map (Inspector Scope)<br/>4. Real-Time Incident Alerts & Photo Evidence<br/>5. Guard Attendance Logs & DTR Summaries<br/>6. Inspection History & Audit Records| IN

    %% Security Guard Flows
    SG -->|1. Mobile Login & Device Hardware ID<br/>2. Attendance Punch (Time In / Time Out)<br/>3. Punch GPS Coordinates & Geofence Fix<br/>4. On-Duty Continuous Live GPS Stream<br/>5. Incident Reports & Photo Evidence<br/>6. Duty Requests (Relief, Swap, Overtime)| P0
    P0 -->|1. Authentication & Device Verification Status<br/>2. Assigned Post Details (Client Name, Location)<br/>3. Assigned Shift (Day / Night Shift) & Roster<br/>4. Geofence Attendance Validation Result<br/>5. Duty Request Approvals & Notifications<br/>6. Personal DTR & Duty Hours History| SG

    %% Styling
    classDef process fill:#f8fafc,stroke:#0f172a,stroke-width:2.5px,color:#0f172a;
    classDef entity fill:#ffffff,stroke:#1e293b,stroke-width:2px,color:#0f172a;
    class P0 process;
    class SA,OH,IN,SG entity;
```

---

## 2. Data Flow Dictionary

### Entity 1: Super Admin (`it_admin`)
| Direction | Data Flow Name | Description & Contents |
|---|---|---|
| **Inflow** (To System) | Login Credentials & Auth Requests | System administrator email, password, and session authentication tokens. |
| **Inflow** (To System) | Privileged Account Provisioning | Creation, role assignment, and suspension of Super Admin and Operations Head accounts. |
| **Inflow** (To System) | Device Binding Resets & Permissions | Authorizations to unlock or reset bound device hardware IDs for guard smartphones. |
| **Inflow** (To System) | Security & Config Settings | Global agency parameters, security session rules, and system configuration adjustments. |
| **Inflow** (To System) | System Diagnostic Commands | Diagnostics execution triggers, telemetry collection, and platform maintenance requests. |
| **Outflow** (From System) | Access Authorization Status | Verified access tokens, role permissions, and session validation states. |
| **Outflow** (From System) | System Health & Diagnostic Logs | Database health, live websocket channels, and edge connectivity metrics. |
| **Outflow** (From System) | Account Security & Audit Trail | Timestamped immutable audit logs recording privileged administrative actions and logins. |
| **Outflow** (From System) | Privileged Account Summaries | Comprehensive lists of authorized administrator profiles and account states. |

---

### Entity 2: Operations Head (`admin`)
| Direction | Data Flow Name | Description & Contents |
|---|---|---|
| **Inflow** (To System) | Login Credentials & Profile Updates | Operations Head authentication credentials and profile information. |
| **Inflow** (To System) | Personnel Management | Guard and inspector profiles, duty categories (Contract vs. Regular), contract periods, and inspector pairings. |
| **Inflow** (To System) | Client Companies & Duty Posts | Client enterprise names, deployment post labels, physical addresses, and contact persons. |
| **Inflow** (To System) | Geofence Coordinates & Radius | GPS boundary center coordinates (latitude/longitude) and allowed attendance radius (in meters). |
| **Inflow** (To System) | Duty Rosters & Shift Deployments | Monthly/weekly schedule matrices, post assignments, and shift designations (Day Shift / Night Shift). |
| **Inflow** (To System) | Request Approvals & Decisions | Decisions on guard absence, shift swap, relief/coverage, time-out, and overtime submissions. |
| **Inflow** (To System) | DTR & Incident Corrections | Official DTR remarks, duty time adjustments, and resolution notes for submitted incidents. |
| **Outflow** (From System) | Access Authorization Status | Administrative role validation and access permissions to agency operational portals. |
| **Outflow** (From System) | Real-Time Live Guard Map | Live GPS positions of currently clocked-in guards, post locations, geofence rings, and breadcrumbs. |
| **Outflow** (From System) | Daily Time Records (DTR) & Attendance | Computed regular hours, overtime, cut-off summaries, and signed PDF timesheet layouts. |
| **Outflow** (From System) | Incident Reports with Evidence | Field incident submissions featuring timestamps, categories, narratives, and photographic evidence. |
| **Outflow** (From System) | Duty Requests & Swaps | Real-time queue of guard relief, exchange, overtime, and time-out requests requiring action. |
| **Outflow** (From System) | Accomplishment & Audit Reports | Aggregated agency operational summaries, attendance reliability metrics, and historical deployments. |

---

### Entity 3: Inspector (`inspector`)
| Direction | Data Flow Name | Description & Contents |
|---|---|---|
| **Inflow** (To System) | Login Credentials & Profile Updates | Field Inspector authentication credentials and personal profile information. |
| **Inflow** (To System) | Post Inspection Logs & Audit Remarks | On-site detachment inspection checklists, uniform/equipment compliance, and audit evaluations. |
| **Inflow** (To System) | Field Incident Notes & Verification | Firsthand observations, post incident verification comments, and on-site assessments. |
| **Inflow** (To System) | Emergency Relocation Notes | Endorsements for immediate post coverages or field incident escalations. |
| **Outflow** (From System) | Access Authorization Status | Scoped role verification granting access only to assigned posts and subordinate personnel. |
| **Outflow** (From System) | Assigned Guard Roster & Posts | Detailed roster of security guards and deployment posts assigned under the inspector's jurisdiction. |
| **Outflow** (From System) | Live Guard Map (Inspector Scope) | Real-time location stream and active duty status of guards assigned to the inspector. |
| **Outflow** (From System) | Incident Alerts & Reports | Filtered incident alerts and evidence logged within the inspector's detachment posts. |
| **Outflow** (From System) | Guard Attendance & DTR Logs | View-only daily time records and punch logs for supervised guards. |

---

### Entity 4: Security Guard (`user` - Flutter Mobile App)
| Direction | Data Flow Name | Description & Contents |
|---|---|---|
| **Inflow** (To System) | Mobile Login & Device Hardware ID | Guard credentials paired with unique hardware identifier (UUID) for single-device binding. |
| **Inflow** (To System) | Attendance Punch (Time In / Out) | Timestamped clock-in and clock-out punch submissions. |
| **Inflow** (To System) | Punch GPS Coordinates | High-precision GPS latitude and longitude captured at the moment of clocking in/out. |
| **Inflow** (To System) | Continuous Live GPS Stream | Background/foreground location updates transmitted periodically while on active duty. |
| **Inflow** (To System) | Incident Reports & Photo Evidence | Incident reports composed on mobile with category, title, description, and attached photos. |
| **Inflow** (To System) | Duty Requests | Applications for shift swap, emergency relief/coverage, scheduled absence, and overtime. |
| **Outflow** (From System) | Authentication & Device Binding | Login approval, registered device confirmation, or device mismatch restriction warnings. |
| **Outflow** (From System) | Assigned Post & Shift Details | Assigned detachment post (Client Company name, location address) and shift (Day Shift / Night Shift). |
| **Outflow** (From System) | Geofence Validation Result | Immediate attendance verification response (Confirmed within perimeter or Out-of-Bounds alert). |
| **Outflow** (From System) | Duty Request Status Updates | Push/in-app notifications of approval or rejection on filed swaps, relief, and overtime. |
| **Outflow** (From System) | Personal DTR & Duty Hours History | Guard's personal record of verified duty hours, attendance logs, and completed shifts. |

---

## 3. High-Resolution Vector Graphic (SVG)

A publication-ready vector graphic of this Context Diagram is available at:
`docs/context-diagram.svg`
