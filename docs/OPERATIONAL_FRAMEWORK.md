# Operational Framework: Sentinel Link (Simplified & Panel-Aligned)

## Purpose

Sentinel Link connects security guards in the field and administrators in the office through a secure network and centralized cloud infrastructure. Security guards use an Android mobile application, while administrators manage operations through a web portal.

## Operational Framework Diagram (Figure 2)

```mermaid
flowchart LR
    SG[Security Guard] <--> AD[Android Device\n(Mobile App)]
    AD <--> NET[Network\n(Internet / Wi-Fi)]
    NET <--> SVR[Backend Server\n(Supabase)]
    SVR <--> DB[(PostgreSQL Database)]
    SVR <--> WP[Staff Web Portal]
    WP <--> ITA[IT Administrator]
    WP <--> OH[Operations Head]
    WP <--> IN[Field Inspector]
```

> **Vector Graphic Asset:** [`docs/operational-framework-updated.svg`](./operational-framework-updated.svg)  
> **Interactive Preview & One-Click Copy:** [`docs/operational-framework.html`](./operational-framework.html)

---

## Panel Corrections Applied

1. **`separate network w/ server`**: Divided the old single cloud into **Network** (Internet / Wi-Fi) and **Backend Server** (Supabase Cloud Server).
2. **`Postgres SQL`**: Explicitly labeled the database cylinder as **PostgreSQL Database**.
3. **`ANDROID DEVICE`**: Labeled the mobile phone client as **Android Device (Mobile App)**.
4. **Clean, Uncrowded Text**: Kept all arrow labels to short 1–2 lines (e.g., `Time-In / Time-Out`, `Duty Schedule`, `Store Records`, `Retrieve Records`) to keep the diagram clean, clear, and easy to read.

---

## Thesis Chapter III: Section 3.2 Narrative

```text
3.2 Operational Framework

The Operational Framework illustrates how the proposed security agency management system connects different user roles, devices, and software components. The system allows security guards in the field and administrators in the office to interact seamlessly through a secure network and centralized cloud infrastructure.

Figure 2
Operational Framework of Web-Based Security Agency Management System with Mobile Application for Real-Time Monitoring

As shown in Figure 2, security guards use an Android Device running the mobile application. The app allows guards to record their daily attendance through live camera face capture and GPS geofence validation, ensuring that time-in and time-out transactions occur only within their assigned post perimeters. Guards also use the mobile app to view duty schedules, submit duty requests such as absences or shift swaps, and send incident reports with photos. All mobile data is transmitted across the Network (cellular data or Wi-Fi) to the Backend Server powered by Supabase.

The backend server processes system requests, verifies geofence rules, and stores operational records in the PostgreSQL Database, which holds user accounts, shift rosters, attendance logs, GPS history, and incident reports. Administrative personnel access the system through the Staff Web Portal on their office computers. The IT Administrator manages system settings and accounts; the Operations Head creates shift rosters, approves duty requests, monitors active guards on the Guard Tracker map, and exports DTR attendance reports; and the Field Inspector conducts spot inspections, investigates incident reports, and reviews attendance. Through this framework, the system provides real-time monitoring, verified attendance tracking, and organized management of security operations.
```
