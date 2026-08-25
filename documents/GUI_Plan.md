Yes — **that is exactly how I’d do it**. Don’t rewrite the Brain. Build one new central GUI/controller file whose job is mostly to *assemble views* and call the existing modules.

I inspected the current `res(2).zip`, and the good news is the backend is already split into useful modules. The giant `epod_truck_distribution.lua` currently owns the window construction, but the actual mechanics already live elsewhere: `planner.lua` calculates targets, `dispatcher.lua` applies them, `vehicles.lua` knows fleet/capability state, `stations.lua` knows terminals/station data, `demand.lua` knows waiting cargo, `hub_registry.lua` knows managed hubs, and so on.

I’d give Claude a blueprint like this:

```text
DD CENTRAL MANAGER
========================================================

[ OVERVIEW ] [ HUBS ] [ SERVICES ] [ FLEET ]
[ TERMINALS ] [ CARGO ] [ ACTIVITY ] [ SETTINGS ]

Selected Hub: Hendon East
Auto Redistribute: ON
```

Then map each section to the code that already owns that information.

| GUI area                      | What appears there             | Existing source/module                                                  |
| ----------------------------- | ------------------------------ | ----------------------------------------------------------------------- |
| **Hub list**                  | Hendon East, other DD hubs     | `hub_registry.lua` → `getEnabledHubs()`                                 |
| **Selected hub name/details** | name, entity ID                | `stations.lua` → `getEntityName()`, `getStationGroup()`                 |
| **Managed services**          | all DD lines at hub            | `vehicles.lua` → `getManagedLinesForStation()` + `managed_registry.lua` |
| **Waiting cargo**             | per line / destination / cargo | `demand.lua` → `scan()`, cargo label/icon helpers                       |
| **Current truck count**       | trucks per service             | `vehicles.lua` → `getVehiclesForLine()`                                 |
| **Target truck count**        | planner recommendation         | `planner.lua` → `calculateTargetAllocation()`                           |
| **Apply/Redistribute**        | execute target plan            | `dispatcher.lua` → `applyPlan()`                                        |
| **Auto redistribute state**   | ON/OFF per hub                 | current logic in main file; eventually move to settings/state module    |
| **Cargo compatibility**       | vehicle capability profile     | `vehicles.lua` → `getAllCapacities()`, `getCompatibleCargoTypes()`      |
| **Loaded/empty state**        | available trucks               | `vehicles.lua` → `getCargoLoad()`, `isVehicleEmpty()`                   |
| **Terminals**                 | count / line assignment        | `stations.lua` + `terminal_allocator.lua`                               |
| **Rename fleet**              | `● Hendon East - Fleet xxx`    | `fleet_naming.lua`                                                      |
| **New-line adoption**         | detect/register new service    | `line_adopter.lua`                                                      |
| **Line ownership**            | which hub owns line            | `line_ownership.lua`                                                    |
| **Managed state**             | DD-managed yes/no              | `managed_registry.lua`                                                  |
| **Split initial line**        | first conversion               | `line_splitter.lua`                                                     |
| **Terminal organisation**     | spread services                | `terminal_allocator.lua`                                                |

Then I’d propose a **new file**:

```text
res/scripts/epod_td/gui_manager.lua
```

Its purpose:

```lua
-- GUI ONLY.
--
-- This module must NOT contain transport-management logic.
--
-- It may:
--   * read state from existing DD modules
--   * construct native TF2 GUI components
--   * call existing public module functions when buttons are pressed
--
-- It must NOT:
--   * calculate fleet allocations itself
--   * move vehicles itself
--   * inspect raw engine entities where an existing module already does it
--   * duplicate planner/dispatcher/demand logic
```

And I’d structure it roughly like this:

```lua
local M = {}

local demand = require("epod_td.demand")
local vehicles = require("epod_td.vehicles")
local stations = require("epod_td.stations")
local planner = require("epod_td.planner")
local dispatcher = require("epod_td.dispatcher")
local hub_registry = require("epod_td.hub_registry")
local managed_registry = require("epod_td.managed_registry")
local line_adopter = require("epod_td.line_adopter")
local fleet_naming = require("epod_td.fleet_naming")
local terminal_allocator = require("epod_td.terminal_allocator")

function M.createWindow()
    -- CLAUDE:
    -- Create the native TF2 Window + TabWidget here.
end

function M.refresh(selectedHubId)
    -- CLAUDE:
    -- Gather one current snapshot from existing modules.
    -- Refresh visible tab without rebuilding management logic.
end

return M
```

Then the tabs:

```lua
local function buildOverviewTab(hubId)
    -- HUB SUMMARY
    -- Source:
    --   hub_registry.lua
    --   stations.lua
    --   vehicles.lua
    --   demand.lua
    --
    -- DISPLAY:
    --   Hub name
    --   Managed services
    --   Total trucks
    --   Total waiting
    --   Terminal count
    --   Auto Redistribute state

    -- FLEET PLAN SUMMARY
    -- Source:
    --   planner.calculateTargetAllocation()
    --
    -- DISPLAY:
    --   Current trucks
    --   Target trucks
    --   +/- delta

    -- BUTTON:
    --   Redistribute Now
    -- Calls:
    --   dispatcher.applyPlan()
end
```

For **HUBS**:

```lua
local function buildHubsTab()
    -- LEFT SIDE:
    -- List every managed DD hub.
    --
    -- Source:
    --   hub_registry.getEnabledHubs()

    -- Clicking hub:
    --   selectedHubId = clickedHub
    --   refresh all relevant tabs

    -- RIGHT SIDE:
    -- Selected Hub Summary
    --
    -- Source:
    --   stations.getEntityName()
    --   vehicles.getManagedLinesForStation()
    --   stations.getTerminalCount()
end
```

Visually:

```text
HUBS
────────────────────────────────────

● Hendon East
  106 trucks
  8 services

● Hugh Town
   36 trucks
   2 services

● Central Freight
   74 trucks
   6 services


SELECTED HUB
────────────────────────────────────
Hendon East

Services       8
Vehicles     106
Waiting      131
Terminals      6

Auto Redistribute     ● ON
```

For **SERVICES**:

```lua
local function buildServicesTab(hubId)
    -- Source:
    --   vehicles.getManagedLinesForStation()
    --   vehicles.getVehiclesForLine()
    --   demand.scan()
    --   planner.calculateTargetAllocation()

    -- DISPLAY TABLE:
    --
    -- Managed | Service | Current | Target | Waiting | Delta
    --
    -- ●       Main Street     26       18       2      -8
    -- ●       Queens Road     18       16       8      -2
    -- ●       School Lane     11       14      34      +3

    -- FUTURE:
    -- ● / ○ clickable management toggle.
    --
    -- IMPORTANT:
    -- toggling must call registry/state code,
    -- not rely on the line name.
end
```

For **FLEET**:

```lua
local function buildFleetTab(hubId)
    -- Source:
    --   vehicles.getVehiclesForLine()
    --   vehicles.getAllCapacities()
    --   vehicles.getCompatibleCargoTypes()
    --   vehicles.getCargoLoad()
    --   vehicles.isVehicleEmpty()

    -- DISPLAY:
    --
    -- Total Fleet: 106
    --
    -- Capability Profile        Vehicles
    -- Universal                     90
    -- Bulk/material                 10
    -- Logs/planks/steel              6
    --
    -- Optional second table:
    --
    -- Service       Vehicles    Empty    Loaded
    -- Main Street      26         8        18
```

Later the cycle-time research can simply add:

```text
Service       Vehicles   Round Trip   Throughput
Main Street      26        08:12        ...
Queens Road      18        03:44        ...
```

For **TERMINALS**:

```lua
local function buildTerminalsTab(hubId)
    -- Source:
    --   stations.getTerminalCount()
    --   current line stop data
    --   terminal_allocator.lua
    --
    -- DISPLAY:
    --
    -- T1    Grain
    -- T2    Queens Road
    -- T3    School Lane
    -- T4    Main Street
    -- T5    Alexander Road
    -- T6    Grove / Highfield
    --
    -- BUTTON:
    --   Reorganize Terminals
    --
    -- Calls:
    --   terminal_allocator.spreadLinesAcrossTerminals()
end
```

For **CARGO**:

```lua
local function buildCargoTab(hubId)
    -- Source:
    --   demand.scan()
    --   demand.getCargoTypeDisplayName()
    --   demand.getCargoTypeIconPath()
    --
    -- DISPLAY:
    --
    -- Cargo Type      Waiting
    -- Fuel              93
    -- Food              28
    -- Goods             17
    -- Grain             44
    --
    -- Could also group by service.
end
```

For **ACTIVITY**, I would initially leave a placeholder because your log infrastructure doesn't yet expose a neat bounded activity feed:

```lua
local function buildActivityTab()
    -- CLAUDE:
    -- DO NOT parse stdout.
    --
    -- Future:
    -- add a small in-memory/persisted DD activity queue.
    --
    -- Example events:
    --   New service adopted
    --   Fleet plan calculated
    --   Vehicle reassigned
    --   Terminal changed
    --   Compatibility warning
end
```

And **SETTINGS**:

```lua
local function buildSettingsTab(hubId)
    -- Source:
    --   settings.lua
    --   hub_registry.lua

    -- OPTIONS:
    --
    -- Auto Redistribute       ● / ○
    -- Rename fleet            ● / ○
    -- Future colour ownership
    -- Future reassessment sensitivity
    -- Future cooldown setting

    -- WARNING:
    -- settings should be persisted through existing settings/state
    -- mechanisms rather than held only in GUI state.
end
```

The most important instruction I'd put at the very top for Claude is:

> **Do not migrate existing backend logic into `gui_manager.lua`. This is a presentation/controller refactor only. Existing modules remain authoritative. If the GUI needs information not currently exposed cleanly, add a small read-only public getter to the responsible module rather than duplicating the calculation inside the GUI.**

That one rule will stop the GUI rewrite turning into a 3-day regression nightmare. 😂

Then the current giant `epod_truck_distribution.lua` can gradually shrink. Right now it contains `ensureDistributionWindow()` around line ~1612 and `updateDistributionWindow()` around ~2186, plus all the individual button construction. Those are the pieces Claude can progressively move into `gui_manager.lua` while leaving event handling/bootstrap in the main game-script file.

So the eventual architecture becomes:

```text
epod_truck_distribution.lua
        │
        │ game events / lifecycle
        ▼
   gui_manager.lua
        │
        ├──── demand.lua
        ├──── planner.lua
        ├──── dispatcher.lua
        ├──── vehicles.lua
        ├──── stations.lua
        ├──── hub_registry.lua
        ├──── managed_registry.lua
        ├──── line_adopter.lua
        └──── terminal_allocator.lua
```

**Main file = glue.**
**GUI manager = presentation.**
**Existing modules = Brain.**

That’s how I’d tackle it without rewriting the working mod.
