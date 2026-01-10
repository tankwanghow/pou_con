# Central Farm Monitoring System - Future Plan

This document outlines the architecture, implementation plan, and ideas for building a central monitoring system to aggregate data from multiple PouCon instances across a poultry farm.

## Table of Contents

1. [Overview](#overview)
2. [WiFi Network Setup](#wifi-network-setup)
3. [Central Application Architecture](#central-application-architecture)
4. [Database Design](#database-design)
5. [Implementation Phases](#implementation-phases)
6. [Feature Ideas](#feature-ideas)
7. [Hardware Requirements](#hardware-requirements)
8. [Security Considerations](#security-considerations)

---

## Overview

### Current State

Each poultry house runs an independent PouCon instance on a Raspberry Pi with:
- Local SQLite database
- Real-time equipment monitoring
- Flock management
- Task tracking
- 30-day event retention, 365-day summaries

### Goal

Create a unified farm management system that:
- Aggregates data from all houses in real-time
- Provides farm-wide dashboards and reports
- Enables cross-house analysis and comparisons
- Stores long-term historical data
- Sends alerts for farm-wide issues

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            FARM OFFICE                                   │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                FarmMonitor Central Application                     │  │
│  │           (Phoenix LiveView + PostgreSQL + TimescaleDB)            │  │
│  │                                                                    │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │  │
│  │  │Dashboard │  │ Reports  │  │  Alerts  │  │ Analytics│          │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘          │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                │                                         │
│                    [Router] ── [AP-0 Office]                            │
│                                                                          │
└────────────────────────────────┼─────────────────────────────────────────┘
                                 │
                               300m (via relay AP)
                                 │
┌────────────────────────────────┼─────────────────────────────────────────┐
│                            FARM AREA                                      │
│                                                                           │
│  BACK ROW A    [B1]────[B2]────[B3]────[B4]────[B5]                      │
│                  │                               │                        │
│  ROW A         H1    H2    H3    H4 ... H16    (16 houses)               │
│               [Pi]  [Pi]  [Pi]  [Pi]   [Pi]                              │
│                .101  .102  .103  .104   .116                             │
│                  │                               │                        │
│  ROAD          [F1]════[F2]════[F3]════[F4]════[F5]  (Mesh APs)          │
│                  │                               │                        │
│  ROW B         H17   H18   H19   H20 ... H32   (16 houses)               │
│               [Pi]  [Pi]  [Pi]  [Pi]   [Pi]                              │
│                .117  .118  .119  .120   .132                             │
│                  │                               │                        │
│  BACK ROW B    [B6]────[B7]────[B8]────[B9]────[B10]                     │
│                                                                           │
│  All 32 PouCon Pis expose:                                               │
│    /api/status  - Real-time equipment and sensor status                  │
│    /api/sync/*  - Data synchronization endpoints                         │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## WiFi Network Setup

### Farm Layout

The farm consists of 32 poultry houses arranged in 2 rows of 16, with house fronts facing each other across a central road.

#### Farm Specifications

| Specification | Value |
|---------------|-------|
| Total houses | 32 (2 rows × 16 houses) |
| House dimensions | 100m (length) × 14m (width) |
| Gap between houses | 10m |
| Central road width | 20m |
| Farm office distance | 300m from first house |
| Farm total width | ~374m |
| Farm total depth | ~240m |

#### House Construction

| Area | Material | WiFi Penetration |
|------|----------|------------------|
| Front | Curtains (open) | Excellent |
| Back | Metal wall with exhaust fan openings | Good (through openings) |
| Roof | Metal | Blocked |
| Pi location | Front of house (facing road) | - |

#### Physical Layout

```
                              FARM OFFICE
                                  │
                               300 meters
                                  │
                                  ▼
◄─────────────────────────────── 374m ───────────────────────────────►

BACK ROW A (exhaust fans + metal wall with openings)
═══════════════════════════════════════════════════════════════════════════
    ┌──────┐    ┌──────┐    ┌──────┐    ┌──────┐           ┌──────┐
    │      │    │      │    │      │    │      │           │      │
    │  H1  │    │  H2  │    │  H3  │    │  H4  │    ...    │ H16  │    100m
    │      │    │      │    │      │    │      │           │      │    depth
    │ [Pi] │    │ [Pi] │    │ [Pi] │    │ [Pi] │           │ [Pi] │
    └──┬───┘    └──┬───┘    └──┬───┘    └──┬───┘           └──┬───┘
       │           │           │           │                  │
     FRONT       FRONT       FRONT       FRONT              FRONT
     curtain     curtain     curtain     curtain            curtain
       │           │           │           │                  │
═══════╪═══════════╪═══════════╪═══════════╪══════════════════╪═══════════
       │                                                      │
       │                    20m ROAD                          │
       │         (Pis on both sides face the road)            │
       │                                                      │
═══════╪═══════════╪═══════════╪═══════════╪══════════════════╪═══════════
       │           │           │           │                  │
     FRONT       FRONT       FRONT       FRONT              FRONT
     curtain     curtain     curtain     curtain            curtain
       │           │           │           │                  │
    ┌──┴───┐    ┌──┴───┐    ┌──┴───┐    ┌──┴───┐           ┌──┴───┐
    │ [Pi] │    │ [Pi] │    │ [Pi] │    │ [Pi] │           │ [Pi] │
    │      │    │      │    │      │    │      │           │      │
    │ H17  │    │ H18  │    │ H19  │    │ H20  │    ...    │ H32  │    100m
    │      │    │      │    │      │    │      │           │      │    depth
    │      │    │      │    │      │    │      │           │      │
    └──────┘    └──────┘    └──────┘    └──────┘           └──────┘
═══════════════════════════════════════════════════════════════════════════
BACK ROW B (exhaust fans + metal wall with openings)
```

### Wireless Mesh Network Design (Roof-Mounted)

The design uses **UniFi 6 Mesh Pro** access points mounted on house rooftops (6m height) with wireless mesh backhaul. This eliminates the need for separate poles within the farm.

#### Network Topology

```
                    ┌─────────────┐
                    │ FARM OFFICE │
                    │   [AP-0]    │ ◄── Office AP (roof/wall mount)
                    └──────┬──────┘
                           │
                         150m (line of sight)
                           │
                         [AP-R] ◄── Relay AP (only pole needed, in field)
                           │
                         150m (line of sight)
                           │
═══════════════════════════╪════════════════════════════════════════════════

BACK ROW A (mounted on back roof tips, 6m high)
    [B1]──────────[B2]──────────[B3]──────────[B4]──────────[B5]
     H1            H4            H8           H12           H16
      │             │             │             │             │
      │   ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐   ┌───┐ ┌───┐ ┌───┐  │
      │   │ 1 │ │ 2 │ │ 3 │ │ 4 │ │ 5 │...│14 │ │15 │ │16 │  │   ROW A
      │   │Pi │ │Pi │ │Pi │ │Pi │ │Pi │   │Pi │ │Pi │ │Pi │  │   Houses
      │   └─┬─┘ └─┬─┘ └─┬─┘ └─┬─┘ └─┬─┘   └─┬─┘ └─┬─┘ └─┬─┘  │
      │     │     │     │     │     │       │     │     │    │
    [F1]════╪═════╪═══[F2]════╪═════╪═════[F3]════╪═══[F4]═══╪═══[F5]
     H1     │     │    H4     │     │      H8     │   H12    │   H16
            │     │           │     │             │          │
═══════════════════════════════════════════════════════════════════════
                              20m ROAD
                    (All 32 Pis connect to Road APs)
═══════════════════════════════════════════════════════════════════════
            │     │           │     │             │          │
      │     │     │     │     │     │       │     │     │    │
      │   ┌─┴─┐ ┌─┴─┐ ┌─┴─┐ ┌─┴─┐ ┌─┴─┐   ┌─┴─┐ ┌─┴─┐ ┌─┴─┐  │
      │   │Pi │ │Pi │ │Pi │ │Pi │ │Pi │   │Pi │ │Pi │ │Pi │  │   ROW B
      │   │17 │ │18 │ │19 │ │20 │ │21 │...│30 │ │31 │ │32 │  │   Houses
      │   └───┘ └───┘ └───┘ └───┘ └───┘   └───┘ └───┘ └───┘  │
      │             │             │             │             │
    [B6]──────────[B7]──────────[B8]──────────[B9]──────────[B10]
    H17           H20           H24           H28           H32
BACK ROW B (mounted on back roof tips, 6m high)

═══════════════════════════════════════════════════════════════════════
```

#### Mesh Path (All Line of Sight)

```
[AP-0] Office
   │
 150m (open field)
   │
[AP-R] Relay (pole in field)
   │
 150m (to first house roof)
   │
   ▼
[F1]════[F2]════[F3]════[F4]════[F5]  Road APs (Row A front roofs)
 │                                │
 │  ~75m spacing, line of sight   │
 │                                │
 ├──around house end──┐           │
 │                    │           │
[B1]────[B2]────[B3]────[B4]────[B5]  Back Row A (same houses, back roofs)
                                  │
                            ┌─around─┘
                            │
[B6]────[B7]────[B8]────[B9]────[B10] Back Row B (Row B house back roofs)


All connections have clear line of sight at 6m roof height.
Signal travels AROUND houses at ends, never THROUGH metal roofs.
```

#### AP Placement Summary

| Location | House # | APs | Names |
|----------|---------|-----|-------|
| Office | - | 1 | AP-0 |
| Relay (field) | - | 1 | AP-R |
| Row A Front Roofs | H1, H4, H8, H12, H16 | 5 | F1-F5 |
| Row A Back Roofs | H1, H4, H8, H12, H16 | 5 | B1-B5 |
| Row B Back Roofs | H17, H20, H24, H28, H32 | 5 | B6-B10 |
| **Total** | | **17** | |

**Houses with 2 APs (front + back):** H1, H4, H8, H12, H16
**Houses with 1 AP (back only):** H17, H20, H24, H28, H32

#### Why Road APs Cover Both Rows

Since house fronts face each other across only 20m, the Road APs (F1-F5) on Row A roofs cover both Row A and Row B fronts:

```
                     [Road AP on H1 front roof]
                               │
                ┌──────────────┼──────────────┐
                │              │              │
                ▼              ▼              ▼
           ┌────────┐    ═══════════    ┌────────┐
           │   H1   │      20m ROAD     │  H17   │
           │  [Pi]  │◄────────┼────────►│  [Pi]  │
           │  .101  │         │         │  .117  │
           └────────┘         │         └────────┘
                ▲             │              ▲
                │             │              │
                └─────────────┴──────────────┘
                     One AP covers BOTH rows!
```

#### Indoor Coverage

Signal enters houses through:
- **Front:** Curtains (excellent penetration)
- **Back:** Exhaust fan openings in metal wall (good penetration)

```
                     [Back AP - B1]
                          │
                          │ Signal through exhaust fan openings
                          ▼
╔══════════════════════════════════════════════════════════════════╗
║  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓   Back 40m: Strong           ║
║  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   Middle 20m: Overlapping    ║
║  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓   Front 40m: Strong          ║
╚══════════════════════════════════════════════════════════════════╝
                          ▲
                          │ Signal through curtains
                          │
                     [Road AP - F1]
```

No indoor APs required - outdoor APs provide full coverage through curtains and fan openings.

### Equipment List

| Item | Qty | Unit Price | Total |
|------|-----|------------|-------|
| **UniFi 6 Mesh Pro** | 17 | $200 | $3,400 |
| **6m steel pole** (relay only) | 1 | $80 | $80 |
| **Roof mounting brackets** | 15 | $15 | $225 |
| **PoE injectors** | 17 | $15 | $255 |
| **Weatherproof accessories** | 15 | $10 | $150 |
| **Electrical runs to APs** | - | - | ~$500 |
| **Total** | | | **~$4,610** |

### IP Address Scheme

| Range | Devices |
|-------|---------|
| 192.168.1.1 | Main router (gateway, DHCP) |
| 192.168.1.10 | Central monitoring server |
| 192.168.1.20 | AP-0 (Office) |
| 192.168.1.21 | AP-R (Relay) |
| 192.168.1.31-35 | F1-F5 (Road APs) |
| 192.168.1.41-45 | B1-B5 (Back Row A) |
| 192.168.1.46-50 | B6-B10 (Back Row B) |
| **192.168.1.101-116** | **PouCon Pis H1-H16 (Row A)** |
| **192.168.1.117-132** | **PouCon Pis H17-H32 (Row B)** |
| 192.168.1.240-254 | Reserved for future use |

### Roof Mounting Detail

```
                         HOUSE WITH 2 APs (Front + Back)

                              ◄────── 100m ──────►

        BACK                                                    FRONT
       (metal)                                               (curtains)
          │                                                      │
          ▼                                                      ▼
    ══════╪══════════════════════════════════════════════════════╪══════
          │                    ROOF LINE (6m height)             │
          │                       ╱╲                             │
       [Back AP]                 ╱  ╲                        [Front AP]
          │╲                    ╱    ╲                          ╱│
          │ ╲                  ╱      ╲                        ╱ │
          │  ╲________________╱________╲______________________╱  │
          │                                                      │
          │                  HOUSE INTERIOR                      │
          │                                                      │
    ══════╪══════════════════════════════════════════════════════╪══════
```

### Installation Checklist

- [ ] Install office AP (AP-0) on office roof or wall
- [ ] Install relay pole (6m) at 150m from office, with clear line of sight
- [ ] Install relay AP (AP-R) on pole
- [ ] Install front roof APs on houses H1, H4, H8, H12, H16 (Row A)
- [ ] Install back roof APs on houses H1, H4, H8, H12, H16 (Row A)
- [ ] Install back roof APs on houses H17, H20, H24, H28, H32 (Row B)
- [ ] Run electrical power to all AP locations
- [ ] Configure UniFi Controller for mesh network
- [ ] Assign static IPs to all PouCon Pis
- [ ] Test connectivity from central server to all 32 houses
- [ ] Verify indoor coverage in houses (front, middle, back)
- [ ] Document all IP addresses and credentials

### Alternative: Point-to-Point Bridges

For farms with different layouts or longer distances, point-to-point bridges remain an option:

| Equipment | Range | Price | Use Case |
|-----------|-------|-------|----------|
| **Ubiquiti NanoStation 5AC Loco** | 500m+ | ~$50/pair | Best value |
| **Ubiquiti LiteBeam 5AC Gen2** | 1km+ | ~$80/pair | Longer distances |
| **Mikrotik SXTsq 5 ac** | 500m+ | ~$60/pair | Multi-point setups |

---

## Central Application Architecture

### Technology Stack

| Component | Technology | Reason |
|-----------|------------|--------|
| **Backend** | Phoenix/Elixir | Same as PouCon, team expertise |
| **Frontend** | Phoenix LiveView | Real-time updates, no JS framework needed |
| **Database** | PostgreSQL | Better for multi-tenant, aggregations |
| **Time-series** | TimescaleDB (optional) | Efficient sensor data storage |
| **Caching** | ETS / Redis | Fast dashboard queries |
| **Background Jobs** | Oban | Reliable sync scheduling |

### Application Structure

```
farm_monitor/
├── lib/
│   ├── farm_monitor/
│   │   ├── houses/                    # House registry and status
│   │   │   ├── house.ex               # House schema
│   │   │   ├── house_client.ex        # HTTP client for PouCon API
│   │   │   └── house_monitor.ex       # GenServer for health checks
│   │   │
│   │   ├── sync/                      # Data synchronization
│   │   │   ├── sync_cursor.ex         # Track sync progress
│   │   │   ├── syncer.ex              # Main sync GenServer
│   │   │   └── workers/               # Oban workers per table
│   │   │       ├── equipment_events_worker.ex
│   │   │       ├── sensor_snapshots_worker.ex
│   │   │       └── ...
│   │   │
│   │   ├── equipment/                 # Aggregated equipment data
│   │   │   ├── schemas/
│   │   │   │   ├── farm_equipment_event.ex
│   │   │   │   ├── farm_sensor_snapshot.ex
│   │   │   │   └── farm_daily_summary.ex
│   │   │   └── equipment.ex           # Context module
│   │   │
│   │   ├── flocks/                    # Aggregated flock data
│   │   │   ├── schemas/
│   │   │   │   ├── farm_flock.ex
│   │   │   │   └── farm_flock_log.ex
│   │   │   └── flocks.ex
│   │   │
│   │   ├── tasks/                     # Aggregated task data
│   │   │   └── ...
│   │   │
│   │   ├── alerts/                    # Farm-wide alerting
│   │   │   ├── alert.ex               # Alert schema
│   │   │   ├── alert_rules.ex         # Rule definitions
│   │   │   ├── alert_engine.ex        # Rule evaluation
│   │   │   └── notifiers/             # Notification channels
│   │   │       ├── email_notifier.ex
│   │   │       ├── sms_notifier.ex
│   │   │       └── push_notifier.ex
│   │   │
│   │   ├── analytics/                 # Data analysis
│   │   │   ├── production_analyzer.ex
│   │   │   ├── trend_detector.ex
│   │   │   └── anomaly_detector.ex
│   │   │
│   │   └── reports/                   # Report generation
│   │       ├── daily_farm_report.ex
│   │       ├── weekly_summary.ex
│   │       └── export/
│   │           ├── csv_exporter.ex
│   │           └── excel_exporter.ex
│   │
│   └── farm_monitor_web/
│       ├── live/
│       │   ├── dashboard/             # Main farm dashboard
│       │   │   ├── index.ex
│       │   │   └── components/
│       │   │       ├── house_card.ex
│       │   │       ├── production_chart.ex
│       │   │       └── alert_panel.ex
│       │   │
│       │   ├── houses/                # Per-house detail views
│       │   │   ├── index.ex           # House list
│       │   │   ├── show.ex            # House detail
│       │   │   └── compare.ex         # Side-by-side comparison
│       │   │
│       │   ├── reports/               # Report views
│       │   │   ├── daily.ex
│       │   │   ├── weekly.ex
│       │   │   └── custom.ex
│       │   │
│       │   ├── alerts/                # Alert management
│       │   │   ├── index.ex
│       │   │   └── rules.ex
│       │   │
│       │   └── admin/                 # System configuration
│       │       ├── houses.ex          # House registration
│       │       └── settings.ex
│       │
│       └── components/
│           ├── charts.ex
│           ├── tables.ex
│           └── stats.ex
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     FarmMonitor Central                          │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │ HouseMonitor │    │    Syncer    │    │ AlertEngine  │       │
│  │  (GenServer) │    │  (GenServer) │    │  (GenServer) │       │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘       │
│         │                   │                   │                │
│         │ Poll /api/status  │ Sync /api/sync/*  │ Evaluate       │
│         │ every 10 seconds  │ every 5 minutes   │ on new data    │
│         │                   │                   │                │
│         ▼                   ▼                   ▼                │
│  ┌──────────────────────────────────────────────────────┐       │
│  │                    PostgreSQL                         │       │
│  │                                                       │       │
│  │  houses │ sync_cursors │ farm_* tables │ alerts      │       │
│  └──────────────────────────────────────────────────────┘       │
│         │                                                        │
│         │ PubSub broadcasts                                      │
│         ▼                                                        │
│  ┌──────────────────────────────────────────────────────┐       │
│  │                  LiveView Dashboard                   │       │
│  │                                                       │       │
│  │  Real-time updates • Charts • Alerts • Reports       │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Database Design

### Core Tables

```sql
-- House registry
CREATE TABLE houses (
    id SERIAL PRIMARY KEY,
    house_id VARCHAR(50) UNIQUE NOT NULL,      -- "h1", "h2", etc.
    name VARCHAR(255) NOT NULL,                 -- "Layer House 1"
    ip_address VARCHAR(45) NOT NULL,            -- "192.168.1.101"
    api_key_encrypted BYTEA NOT NULL,           -- Encrypted API key
    status VARCHAR(20) DEFAULT 'unknown',       -- online/offline/error
    last_seen_at TIMESTAMPTZ,
    last_sync_at TIMESTAMPTZ,
    sync_enabled BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}',                -- Extra config
    inserted_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

-- Sync progress tracking
CREATE TABLE sync_cursors (
    id SERIAL PRIMARY KEY,
    house_id VARCHAR(50) NOT NULL,
    table_name VARCHAR(100) NOT NULL,           -- "equipment_events", etc.
    last_synced_at TIMESTAMPTZ,
    last_record_id BIGINT DEFAULT 0,
    records_synced BIGINT DEFAULT 0,
    last_error TEXT,
    inserted_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    UNIQUE(house_id, table_name)
);

-- Aggregated equipment events (from all houses)
CREATE TABLE farm_equipment_events (
    id BIGSERIAL PRIMARY KEY,
    house_id VARCHAR(50) NOT NULL,
    source_id BIGINT NOT NULL,                  -- Original ID from PouCon
    equipment_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    from_value VARCHAR(255),
    to_value VARCHAR(255) NOT NULL,
    mode VARCHAR(20) NOT NULL,
    triggered_by VARCHAR(50) NOT NULL,
    metadata JSONB,
    recorded_at TIMESTAMPTZ NOT NULL,           -- Original inserted_at
    inserted_at TIMESTAMPTZ NOT NULL,
    UNIQUE(house_id, source_id)
);

-- Indexes for common queries
CREATE INDEX idx_fee_house_recorded ON farm_equipment_events(house_id, recorded_at);
CREATE INDEX idx_fee_equipment_recorded ON farm_equipment_events(equipment_name, recorded_at);
CREATE INDEX idx_fee_event_type ON farm_equipment_events(event_type, recorded_at);

-- Aggregated sensor snapshots
CREATE TABLE farm_sensor_snapshots (
    id BIGSERIAL PRIMARY KEY,
    house_id VARCHAR(50) NOT NULL,
    source_id BIGINT NOT NULL,
    equipment_name VARCHAR(255) NOT NULL,
    temperature DECIMAL(5,2),
    humidity DECIMAL(5,2),
    dew_point DECIMAL(5,2),
    recorded_at TIMESTAMPTZ NOT NULL,
    inserted_at TIMESTAMPTZ NOT NULL,
    UNIQUE(house_id, source_id)
);

-- TimescaleDB hypertable for efficient time-series queries (optional)
-- SELECT create_hypertable('farm_sensor_snapshots', 'recorded_at');

-- Aggregated flock data
CREATE TABLE farm_flocks (
    id SERIAL PRIMARY KEY,
    house_id VARCHAR(50) NOT NULL,
    source_id BIGINT NOT NULL,
    name VARCHAR(255) NOT NULL,
    date_of_birth DATE NOT NULL,
    quantity INTEGER NOT NULL,
    breed VARCHAR(255),
    notes TEXT,
    active BOOLEAN DEFAULT false,
    sold_date DATE,
    inserted_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    UNIQUE(house_id, source_id)
);

CREATE TABLE farm_flock_logs (
    id BIGSERIAL PRIMARY KEY,
    house_id VARCHAR(50) NOT NULL,
    source_id BIGINT NOT NULL,
    flock_source_id BIGINT NOT NULL,
    log_date DATE NOT NULL,
    deaths INTEGER DEFAULT 0,
    eggs INTEGER DEFAULT 0,
    notes TEXT,
    recorded_at TIMESTAMPTZ NOT NULL,
    inserted_at TIMESTAMPTZ NOT NULL,
    UNIQUE(house_id, source_id)
);

-- Farm-level daily summaries (computed nightly)
CREATE TABLE farm_daily_summaries (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL UNIQUE,
    total_eggs INTEGER DEFAULT 0,
    total_deaths INTEGER DEFAULT 0,
    total_birds INTEGER DEFAULT 0,
    avg_temperature DECIMAL(5,2),
    min_temperature DECIMAL(5,2),
    max_temperature DECIMAL(5,2),
    avg_humidity DECIMAL(5,2),
    total_water_liters DECIMAL(10,2),
    total_feed_kg DECIMAL(10,2),
    house_data JSONB NOT NULL,                  -- Per-house breakdown
    inserted_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

-- Alerts
CREATE TABLE alerts (
    id SERIAL PRIMARY KEY,
    house_id VARCHAR(50),                       -- NULL for farm-wide alerts
    alert_type VARCHAR(100) NOT NULL,
    severity VARCHAR(20) NOT NULL,              -- info/warning/critical
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    status VARCHAR(20) DEFAULT 'active',        -- active/acknowledged/resolved
    acknowledged_at TIMESTAMPTZ,
    acknowledged_by VARCHAR(255),
    resolved_at TIMESTAMPTZ,
    inserted_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_alerts_status ON alerts(status, inserted_at);
CREATE INDEX idx_alerts_house ON alerts(house_id, status);
```

### Elixir Schemas

```elixir
defmodule FarmMonitor.Houses.House do
  use Ecto.Schema

  schema "houses" do
    field :house_id, :string
    field :name, :string
    field :ip_address, :string
    field :api_key_encrypted, :binary
    field :status, :string, default: "unknown"
    field :last_seen_at, :utc_datetime
    field :last_sync_at, :utc_datetime
    field :sync_enabled, :boolean, default: true
    field :metadata, :map, default: %{}

    timestamps()
  end

  # Virtual field for decrypted API key
  field :api_key, :string, virtual: true
end

defmodule FarmMonitor.Equipment.FarmEquipmentEvent do
  use Ecto.Schema

  schema "farm_equipment_events" do
    field :house_id, :string
    field :source_id, :integer
    field :equipment_name, :string
    field :event_type, :string
    field :from_value, :string
    field :to_value, :string
    field :mode, :string
    field :triggered_by, :string
    field :metadata, :map
    field :recorded_at, :utc_datetime

    timestamps(updated_at: false)
  end
end
```

---

## Implementation Phases

### Phase 1: Network Infrastructure (Week 1-2)

**Goal**: Establish reliable network connectivity between all houses.

#### Tasks

- [ ] Survey farm layout and measure distances between houses
- [ ] Select appropriate wireless bridge equipment
- [ ] Purchase networking equipment
- [ ] Install and configure wireless bridges
- [ ] Set up static IP addresses for all PouCon Pis
- [ ] Test connectivity and measure latency/reliability
- [ ] Document network topology and credentials

#### Deliverables

- Working network connecting all houses
- All PouCon instances accessible from central location
- Network documentation

### Phase 2: API Deployment (Week 2-3)

**Goal**: Deploy API endpoints to all PouCon instances.

#### Tasks

- [ ] Generate unique API keys for each house
- [ ] Deploy updated PouCon code with API endpoints
- [ ] Configure house identity files on each Pi
- [ ] Test API endpoints from central location
- [ ] Verify authentication works correctly
- [ ] Test sync endpoints with sample data

#### Deliverables

- All houses exposing `/api/status` and `/api/sync/*` endpoints
- API keys securely stored
- Verified connectivity from central location

### Phase 3: Central App - Foundation (Week 3-5)

**Goal**: Create basic central application with house monitoring.

#### Tasks

- [ ] Set up new Phoenix project (FarmMonitor)
- [ ] Configure PostgreSQL database
- [ ] Implement house registry (CRUD)
- [ ] Implement HouseMonitor GenServer for health checks
- [ ] Create basic dashboard showing house status
- [ ] Implement API client for fetching status
- [ ] Add real-time status updates via PubSub

#### Deliverables

- Central app showing online/offline status of all houses
- Basic dashboard with house cards
- Real-time status updates

### Phase 4: Data Synchronization (Week 5-7)

**Goal**: Implement reliable data sync from all houses.

#### Tasks

- [ ] Create sync cursor tracking system
- [ ] Implement Syncer GenServer
- [ ] Create Oban workers for each data type
- [ ] Handle pagination and incremental sync
- [ ] Implement error handling and retry logic
- [ ] Add sync status to dashboard
- [ ] Create sync monitoring/debugging tools

#### Deliverables

- Automated data sync from all houses
- Sync progress visible in dashboard
- Error notifications for sync failures

### Phase 5: Farm Dashboard (Week 7-9)

**Goal**: Build comprehensive farm-wide dashboard.

#### Tasks

- [ ] Design dashboard layout
- [ ] Implement production summary (eggs, deaths)
- [ ] Add environment overview (temp, humidity across houses)
- [ ] Create equipment status matrix
- [ ] Add flock overview section
- [ ] Implement task completion tracking
- [ ] Add charts for trends (7-day, 30-day)

#### Deliverables

- Full-featured farm dashboard
- Production charts and graphs
- Equipment status overview

### Phase 6: Alerting System (Week 9-11)

**Goal**: Implement farm-wide alerting and notifications.

#### Tasks

- [ ] Define alert rules and thresholds
- [ ] Implement AlertEngine GenServer
- [ ] Create alert management UI
- [ ] Implement email notifications
- [ ] Add SMS notifications (optional)
- [ ] Create alert history and analytics
- [ ] Implement alert acknowledgment workflow

#### Deliverables

- Working alert system
- Email notifications for critical alerts
- Alert management UI

### Phase 7: Reports & Analytics (Week 11-13)

**Goal**: Generate reports and provide analytics.

#### Tasks

- [ ] Daily farm report (automated email)
- [ ] Weekly summary report
- [ ] Custom date range reports
- [ ] Production trend analysis
- [ ] Cross-house comparison reports
- [ ] CSV/Excel export functionality
- [ ] Historical data visualization

#### Deliverables

- Automated daily reports
- Custom report generator
- Data export functionality

### Phase 8: Polish & Optimization (Week 13-14)

**Goal**: Optimize performance and improve UX.

#### Tasks

- [ ] Performance optimization (queries, caching)
- [ ] Mobile-responsive design improvements
- [ ] User feedback incorporation
- [ ] Documentation
- [ ] Backup and recovery procedures
- [ ] Monitoring and logging
- [ ] Security audit

#### Deliverables

- Production-ready central application
- Complete documentation
- Operational procedures

---

## Feature Ideas

### Dashboard Features

#### Farm Overview Card
```
┌─────────────────────────────────────────────────────────────┐
│  FARM OVERVIEW                                    Today     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Total Eggs        Total Deaths       Avg Temperature      │
│   ┌─────────┐       ┌─────────┐       ┌─────────┐          │
│   │  8,623  │       │    2    │       │  25.3°C │          │
│   │  ▲ 3.2% │       │  ▼ 50%  │       │  Normal │          │
│   └─────────┘       └─────────┘       └─────────┘          │
│                                                             │
│   Active Birds      Water Usage        Feed Usage           │
│   ┌─────────┐       ┌─────────┐       ┌─────────┐          │
│   │ 24,500  │       │ 2,450L  │       │  850kg  │          │
│   │ 3 flocks│       │  Normal │       │  Normal │          │
│   └─────────┘       └─────────┘       └─────────┘          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### House Status Cards
```
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ 🏠 House 1       │  │ 🏠 House 2       │  │ 🏠 House 3       │
│ ● Online         │  │ ● Online         │  │ ⚠ Warning        │
├──────────────────┤  ├──────────────────┤  ├──────────────────┤
│ Eggs: 2,845      │  │ Eggs: 2,901      │  │ Eggs: 2,877      │
│ Deaths: 1        │  │ Deaths: 0        │  │ Deaths: 1        │
│ Temp: 25.1°C     │  │ Temp: 24.8°C     │  │ Temp: 27.2°C ⚠   │
│ Humidity: 65%    │  │ Humidity: 62%    │  │ Humidity: 58%    │
├──────────────────┤  ├──────────────────┤  ├──────────────────┤
│ Fans: 4/6 ON     │  │ Fans: 3/6 ON     │  │ Fans: 6/6 ON     │
│ Pumps: 1/2 ON    │  │ Pumps: 1/2 ON    │  │ Pumps: 2/2 ON    │
│ Lights: OFF      │  │ Lights: OFF      │  │ Lights: OFF      │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

### Alert Rules

```elixir
# Example alert rule definitions
alert_rules = [
  %{
    name: "high_temperature",
    description: "Temperature exceeds threshold",
    condition: "temperature > 28",
    severity: :warning,
    cooldown_minutes: 30
  },
  %{
    name: "critical_temperature",
    description: "Temperature critically high",
    condition: "temperature > 32",
    severity: :critical,
    cooldown_minutes: 5
  },
  %{
    name: "house_offline",
    description: "House not responding",
    condition: "last_seen_at < now() - interval '5 minutes'",
    severity: :critical,
    cooldown_minutes: 1
  },
  %{
    name: "production_drop",
    description: "Egg production dropped significantly",
    condition: "today_eggs < yesterday_eggs * 0.8",
    severity: :warning,
    cooldown_minutes: 1440  # Once per day
  },
  %{
    name: "mortality_spike",
    description: "Unusual mortality rate",
    condition: "today_deaths > avg_7day_deaths * 3",
    severity: :warning,
    cooldown_minutes: 1440
  },
  %{
    name: "equipment_failure",
    description: "Equipment error detected",
    condition: "equipment.error != nil",
    severity: :warning,
    cooldown_minutes: 60
  },
  %{
    name: "cross_house_temp_variance",
    description: "Unusual temperature difference between houses",
    condition: "max(house_temps) - min(house_temps) > 5",
    severity: :info,
    cooldown_minutes: 60
  }
]
```

### Report Templates

#### Daily Farm Report (Email)
```
Subject: Daily Farm Report - January 10, 2026

PRODUCTION SUMMARY
==================
Total Eggs Collected: 8,623 (▲ 3.2% vs yesterday)
Total Mortality: 2 birds (▼ from 4 yesterday)
Active Bird Count: 24,500

BY HOUSE:
---------
House 1: 2,845 eggs, 1 death, 8,500 birds (yield: 33.5%)
House 2: 2,901 eggs, 0 deaths, 8,200 birds (yield: 35.4%)
House 3: 2,877 eggs, 1 death, 7,800 birds (yield: 36.9%)

ENVIRONMENT
===========
Average Temperature: 25.3°C (range: 24.1°C - 26.8°C)
Average Humidity: 62% (range: 58% - 68%)
Water Consumption: 2,450 liters
Feed Consumption: 850 kg

EQUIPMENT STATUS
================
All equipment operating normally.
Total Runtime: Fans 18.5 hours, Pumps 4.2 hours

ALERTS
======
- 09:15 House 3 temperature warning (27.2°C) - resolved at 09:45
- No critical alerts

TASKS COMPLETED
===============
- Egg collection (3x daily): ✓ All houses
- Feeding: ✓ All houses
- Water system check: ✓ All houses
- Mortality removal: ✓ All houses

---
Generated automatically by FarmMonitor
```

### Analytics Features

1. **Production Trends**
   - 7-day, 30-day, 90-day production charts
   - Year-over-year comparison
   - Seasonal pattern detection

2. **Flock Performance**
   - Yield percentage by age
   - Mortality curves
   - House-to-house comparison

3. **Environment Correlation**
   - Temperature vs production correlation
   - Humidity impact analysis
   - Optimal environment identification

4. **Equipment Analytics**
   - Runtime hours tracking
   - Maintenance prediction
   - Energy consumption estimation

5. **Anomaly Detection**
   - Statistical outlier detection
   - Pattern break alerts
   - Early warning indicators

### Mobile App (Future)

- Push notifications for alerts
- Quick status overview
- Remote equipment control (if enabled)
- Photo upload for record-keeping

---

## Hardware Requirements

### Central Server Options

#### Option 1: Raspberry Pi 4 (Budget)
- **Model**: Raspberry Pi 4 Model B (4GB or 8GB)
- **Storage**: 128GB+ SSD via USB 3.0
- **Cost**: ~$100-150 total
- **Pros**: Low power, familiar platform
- **Cons**: Limited processing power for heavy analytics

#### Option 2: Mini PC (Recommended)
- **Examples**: Intel NUC, Beelink, ASUS PN series
- **Specs**: Intel i3/i5, 8GB+ RAM, 256GB+ SSD
- **Cost**: ~$300-500
- **Pros**: More powerful, better reliability
- **Cons**: Higher cost, higher power consumption

#### Option 3: Used/Refurbished Desktop
- **Specs**: Any modern Intel/AMD, 8GB+ RAM, SSD
- **Cost**: ~$150-300
- **Pros**: Very cost-effective, easily upgradeable
- **Cons**: Larger, more power consumption

### Networking Equipment Budget

For 32-house farm with roof-mounted mesh WiFi:

| Item | Quantity | Unit Price | Total |
|------|----------|------------|-------|
| UniFi 6 Mesh Pro | 17 | $200 | $3,400 |
| 6m steel pole (relay) | 1 | $80 | $80 |
| Roof mounting brackets | 15 | $15 | $225 |
| PoE injectors | 17 | $15 | $255 |
| Weatherproof accessories | 15 | $10 | $150 |
| Electrical runs to APs | - | - | $500 |
| **Total** | | | **~$4,610** |

#### AP Distribution

| Location | Houses | APs |
|----------|--------|-----|
| Office | - | 1 (AP-0) |
| Relay (field, 150m from office) | - | 1 (AP-R) |
| Row A front roofs | H1, H4, H8, H12, H16 | 5 (F1-F5) |
| Row A back roofs | H1, H4, H8, H12, H16 | 5 (B1-B5) |
| Row B back roofs | H17, H20, H24, H28, H32 | 5 (B6-B10) |
| **Total** | | **17** |

### Power Backup

- UPS for central server and network equipment
- Minimum 30-minute runtime for graceful shutdown
- Recommended: APC Back-UPS 600VA or similar (~$80)

---

## Security Considerations

### Network Security

1. **VLAN Segmentation** (if router supports)
   - Separate automation network from office network
   - Limit access between VLANs

2. **Firewall Rules**
   - Block all inbound from internet
   - Only allow necessary ports between houses and central

3. **WiFi Security**
   - WPA3 or WPA2-Enterprise if possible
   - Strong, unique passwords for each bridge
   - Disable SSID broadcast on point-to-point links

### Application Security

1. **API Authentication**
   - Unique API keys per house
   - Keys stored encrypted in database
   - Regular key rotation schedule

2. **HTTPS**
   - Self-signed certificates for internal traffic
   - Let's Encrypt if external access needed

3. **Access Control**
   - Role-based access (admin, operator, viewer)
   - Audit logging for sensitive operations

4. **Data Protection**
   - Regular automated backups
   - Encrypted backup storage
   - Tested recovery procedures

### Physical Security

1. **Equipment Protection**
   - Locked enclosures for network equipment
   - Tamper-evident seals
   - Surge protection on all equipment

2. **Access Logs**
   - Monitor login attempts
   - Alert on unusual access patterns

---

## Appendix

### API Endpoints Reference (PouCon)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/status` | GET | Real-time equipment and sensor status |
| `/api/info` | GET | House identity and system information |
| `/api/sync/counts` | GET | Record counts for sync planning |
| `/api/sync/equipment_events` | GET | Equipment events (paginated) |
| `/api/sync/sensor_snapshots` | GET | Sensor readings (paginated) |
| `/api/sync/water_meter_snapshots` | GET | Water meter data (paginated) |
| `/api/sync/daily_summaries` | GET | Daily aggregations (paginated) |
| `/api/sync/flocks` | GET | All flocks |
| `/api/sync/flock_logs` | GET | Flock daily logs (paginated) |
| `/api/sync/task_categories` | GET | Task categories |
| `/api/sync/task_templates` | GET | Task templates |
| `/api/sync/task_completions` | GET | Task completions (paginated) |

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `since` | ISO8601 datetime | Only return records after this time |
| `limit` | integer | Max records (default 1000, max 10000) |
| `offset` | integer | Skip N records |
| `equipment_name` | string | Filter by equipment |
| `event_type` | string | Filter by event type |
| `flock_id` | integer | Filter by flock |

### Example API Calls

```bash
# Get current status
curl -H "Authorization: Bearer <api_key>" \
  http://192.168.1.101/api/status

# Get equipment events since last sync
curl -H "Authorization: Bearer <api_key>" \
  "http://192.168.1.101/api/sync/equipment_events?since=2026-01-10T00:00:00Z&limit=1000"

# Get sensor snapshots with pagination
curl -H "Authorization: Bearer <api_key>" \
  "http://192.168.1.101/api/sync/sensor_snapshots?limit=500&offset=500"
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-10 | Claude Code | Initial document |
| 1.1 | 2026-01-10 | Claude Code | Updated WiFi design for 32-house farm with roof-mounted mesh APs |

---

*This document is a living plan and should be updated as the project progresses.*
