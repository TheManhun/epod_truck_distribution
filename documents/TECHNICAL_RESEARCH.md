# TF2 Distribution Manager — Technical Research Checklist

## Purpose

This document lists the technical questions that must be verified against the Transport Fever 2 Lua/modding API before the project commits to implementation.

Anything not proven by research is explicitly flagged as RESEARCH REQUIRED.

## Research Status Table

| Capability | Status | Notes |
| --- | --- | --- |
| Game scripts can access the Transport Fever 2 API | VERIFIED BY OFFICIAL API DOCUMENTATION | The modding framework exposes Lua scripting access to the game environment. |
| Line state can be inspected | VERIFIED BY OFFICIAL API DOCUMENTATION | Official docs describe line-related state and management surfaces. |
| Vehicles belonging to lines can be inspected | VERIFIED BY OFFICIAL API DOCUMENTATION | Vehicle and line objects are exposed through scripting APIs. |
| Existing vehicles can be assigned or reassigned to lines through API commands | VERIFIED BY OFFICIAL API DOCUMENTATION | The API exposes line assignment and vehicle management commands in principle. |
| Which Unicode symbols render in TF2's line-name font | **LIVE-VERIFIED (partial)** | `route_injector.runLineNamingGlyphTest()` created a real line named with five candidate symbols. Confirmed by direct visual inspection: **● and ↔ render correctly; ◆, ■, and ► render as unrendered boxes (tofu)**. `line_splitter.lua` now uses `● <hub> ↔ <destination>` as the naming convention for mod-created lines specifically because of this result, not by assumption. Only these five glyphs were tested — this is not a full survey of TF2's font, just enough to name lines safely. Plain ASCII (e.g. `[TD]`) was not tested but is expected to be safe. |
| Line creation, update, and deletion commands exist and work | **LIVE-VERIFIED** | `api.cmd.make.createLine(name, color, playerEntity, line)`, `api.cmd.make.updateLine(lineEntity, line)`, and `api.cmd.make.deleteLine(lineEntity)` are all confirmed present in `api.cmd.make` via a live `pairs()` dump (33 total commands; see `dumpAvailableCommands` in `epod_truck_distribution.lua`). `createLine` and `deleteLine` were then live-tested end to end by `route_injector.runCreateLineTest()`: created a real 2-stop line (Hendon East + Queens Road) via `createLine`, re-read it by name and confirmed both stops matched exactly (stationGroup 126300 and 134295, matching every other capture this session), then deleted it via `deleteLine` and confirmed by name that it no longer existed. `playerEntity` comes from `api.engine.util.getPlayer()`, also confirmed live (returned a real entity, 80304). `updateLine` was already separately proven live via `route_injector.lua`'s Park-injection test. Source of the original documentation lead: `tf2-api/docs/modules/api.cmd.md`, bundled with the "Auto Line Namer" workshop mod (id 3360333659). This is no longer a documentation claim — it is now the same tier of evidence as `setLine`/`updateLine`/`reverseVehicle`, and unblocks the one-line-per-managed-stop model in Decision 18. |
| Vehicle state exposes useful line/depot/terminal information | VERIFIED BY OFFICIAL API DOCUMENTATION | The object model includes runtime vehicle state information relevant to route and depot context. |
| A line's physical terminal assignment can be changed by writing `Line.Stop.terminal` and resubmitting via `updateLine` | **LIVE-VERIFIED** | `route_injector.runTerminalAssignmentTest()` changed `● Hendon East ↔ Queens Road`'s Hendon-stop terminal from `1` to `2`; a re-read of the line confirmed the field stuck, and the player independently confirmed in the game's own TERMINALS tab that the line moved to a different physical terminal bucket. Also confirmed: `api.engine.getLineStopsForTerminal` and `api.engine.getTerminal2lineStops` (claimed by an external, non-project source) do NOT exist in this game version. Indexing note: the TERMINALS tab displays `(raw terminal value) + 1` — raw `1` showed as the tab's "Terminal 2", raw `2` as "Terminal 3" — confirmed by this same before/after pair. See DECISIONS.md. |
| Cargo systems expose cargo-related simulation state | VERIFIED BY OFFICIAL API DOCUMENTATION | Cargo and freight simulation data are part of the documented modding surface. |
| Custom GUI components are supported | VERIFIED BY OFFICIAL API DOCUMENTATION | The UI/modding docs describe custom GUI capabilities. |
| Whether reassignment is safe at arbitrary points during a delivery | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Safe reassignment timing must be verified in runtime scenarios. |
| Safest moment/state for truck reassignment | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | The safest transition point must be tested, not assumed. |
| Exact cargo destination information available for cargo waiting at a Distribution Centre | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Need runtime confirmation of what cargo/destination data is actually exposed. |
| Exact vehicle cargo compatibility extraction | **LIVE-VERIFIED (partial)** | `game.interface.getEntity(vehicleId)` exposes real `capacities` (cargo types currently in active use, e.g. `{ FOOD = 5 }`) and `allCapacities` (every cargo type's theoretical capacity, most at 0) for a specific vehicle, confirmed live via `route_injector.M.runLoadedVehicleJourneyTestStep`. The same call also exposes `cargoLoad`, the vehicle's real current onboard cargo by type (e.g. `{ FOOD = 4 }`, empty `{}` when carrying nothing) — resolves the separate, previously-open "can onboard load be read at all" question too. Not yet tested across multiple vehicle types/eras, hence partial. |
| Exact vehicle carrying-capacity extraction across vehicle types | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Capacity values must be validated by test rather than inferred from general game logic. |
| Whether persistent managed lines behave correctly with cargo routing | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Stable lines may help or hinder routing, and this requires runtime proof. |
| Whether a zero-vehicle persistent line continues to influence cargo routing correctly | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | This is a critical edge case for persistent service design. |
| Whether a standby line can physically hold trucks without unwanted circulation | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Standby semantics must be confirmed in a controlled in-game test. |
| Whether station waiting reduces operating cost and by how much | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Official docs confirm waiting/full-load behaviour but not a specific discount percentage. |
| Whether multiple Distribution Centres can safely share trucks | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Home-centre ownership and cross-centre assistance must be tested. |
| Whether inter-DC cargo transfer can work using the base game's cargo routing | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | This is a major system-level design question and remains unproven. |
| Whether a capacity-1 vehicle registers and sustains cargo demand the same way a normal-capacity vehicle does | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | General TF2 knowledge says demand is gated by line/connection presence and cargo-type match, not capacity, but this is unconfirmed in this save. See SENTINEL CAPACITY TEST, ROADMAP.md Stage 0. |
| Whether one vehicle can register demand for multiple simultaneous cargo types at one destination, or only the type it is currently carrying | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Directly affects whether one sentinel per line is enough or one per cargo type is needed. |
| Whether a vehicle carrying loaded cargo can be safely reassigned across lines mid-journey | IN-GAME TEST REQUIRED / RESEARCH REQUIRED | Only cross-line reassignment of an empty/test vehicle has been proven so far (the two-park setLine test). |
| Whether the mod can persist player-selected state (e.g. managed-stop selections) across a save/reload | **LIVE-VERIFIED — but not via `data()`'s `save`/`load` hooks; via direct file I/O instead** | `save`/`load` fields on `data()`'s returned table are real (confirmed in shipped base-game code — `guidesystem.lua`, `mission/arrivaltracker.lua`), but proved unusable for this mod after eight live-tested fix attempts across two hard crashes (a real engine determinism constraint, `CGame::StartGameSim`/`Game.cpp:330`, plus an unresolved multi-instantiation problem where the engine runs multiple disconnected copies of this script's top-level code and the GUI-bound instance isn't reliably the one wired to real serialization — not even a shared Lua global bridges that gap). Full saga in DECISIONS.md Decision 24. **Pivoted to `io.open` instead**, confirmed live: `io` is available in this mod sandbox (undocumented — no shipped `res/config/game_script/` script was found using it) and a counter written/read directly via `io.open` survived two full quit/relaunch cycles cleanly, no guard or workaround needed. Currently writes to the TF2 install directory root via a plain relative filename — not yet suitable for real state (needs a per-savegame-scoped path, and shouldn't live in the Steam install folder long-term). |
| Whether TF2 exposes real-time simulation events (not just polling) for cargo/vehicle state changes | **LIVE-DOCUMENTED (partial)** | A `handleEvent(src, id, name, param)` field on the same `data()`-returned table (separate from `guiHandleEvent`) is confirmed real and used in shipped code: `res/scripts/mission/arrivaltracker.lua` listens for `id == "SimCargoSystem", name == "OnToArriveAtDestination"` (fires per cargo entity on delivery, `param` = the cargo entity id, readable via `game.interface.getEntity`) and `id == "SimPersonSystem", name == "OnCompletedLineUsage"`. This directly answers part of `IDEAS.md`'s "Change-driven demand reassessment" open question — a real event-driven trigger for cargo *arrival* does exist, not just a cached-snapshot comparison. No complementary "cargo newly waiting" event has been found yet (searched; not present anywhere in the shipped script set), so this covers the delivery side of demand change, not necessarily the generation side. Not yet used by this mod. `guidesystem.lua` also confirms a separate `update = function()` field, paced by simulation time (`dt`) rather than GUI-frame frequency like `guiUpdate` — a better candidate for a background planner/heartbeat than piggybacking on `guiUpdate`. |
| Whether a terminal's waiting-cargo storage capacity, and whether cargo despawns past it, are exposed through the API | RESEARCH REQUIRED (player-reported, not API-confirmed) | Player-reported game mechanic: each terminal has finite waiting-cargo storage, reportedly ~100-200 depending on terminal length (extendable by lengthening the terminal or attaching warehouses); cargo generated beyond that cap despawns rather than accumulating. No API field for terminal capacity has been found so far (the `STATION` component's `terminals` dump — see `stations.dumpStationGroupTerminals` — exposes `tag`, `personNodes`, `personEdges`, `vehicleNodeId`, no capacity/stock field). This means `demand.scan()`'s "waiting" totals are a FLOOR on true demand, not necessarily an accurate relative measure between two destinations with different terminal capacities. `fleet_allocator.lua`'s demand-weighted vehicle allocation uses the visible waiting total as its best available proxy anyway and documents this limitation inline. |
| Whether historical physical Distribution Centre buildings can be modelled with era-based progression and production constraints | RESEARCH REQUIRED | This is a future content pipeline question, not a V1 implementation concern. |
| Whether loading positions and standby positions can be represented as distinct physical bottlenecks | RESEARCH REQUIRED | Exact support depends on vehicle pathing and yard simulation. |
| Whether reverse-in truck bays are feasible with custom paths and vehicle behaviour | RESEARCH REQUIRED | This is experimental and should not block the logical V1 model. |
| Whether Blender-created TF2 asset pipelines are compatible with actual export requirements | RESEARCH REQUIRED | Exact format and workflow must be verified with the tooling and game requirements. |

## Source Notes

Researchers should consult the official Transport Fever 2 documentation before assuming behavior beyond the documented API surface:

- Modding documentation
- API Reference
- Game Scripts documentation
- User Interface documentation
- line/vehicle/cargo API modules

Do not invent function names or API behavior unless they have been explicitly checked against the official API reference.

## Core Research Questions

### Town Association and Multiple Distribution Centres

- Can a logical Distribution Centre controller be associated with a Transport Fever 2 town?
- Can a town eventually support multiple Distribution Centres without redesigning the core architecture?
- Can the player define and manage several centres in the same town while keeping their fleets independent?
- Is there any base-game constraint that makes this concept unrealistic? RESEARCH REQUIRED.

### Vehicle State

- Can the mod identify which vehicles belong to the player's fleet?
- Can it identify whether a vehicle is idle, active, assigned, or otherwise in service?
- Can it identify the vehicle type and its cargo compatibility?
- Can it read carrying capacity or equivalent load data?
- Can it distinguish road freight vehicles from other vehicle classes?
- Can it inspect vehicles at a Distribution Centre and/or across the network?

### Cargo and Demand

- Can the mod inspect cargo demand for a stop or destination?
- Can it inspect cargo backlog or waiting counts?
- Can it determine whether a stop is currently under-served or overloaded?
- Can it detect cargo type requirements for a destination?
- Can it read cargo status without duplicating or interfering with Transport Fever 2's own routing logic?
- Can the mod inspect cargo waiting at a Distribution Centre itself, and if so, what exact information is available? RESEARCH REQUIRED.

### Line and Route State

- Can the mod inspect line assignments and line state for vehicles?
- Can it determine whether a vehicle is on a route, a depot line, or a custom managed service?
- Can it create, edit, or maintain a persistent system-managed line between a Distribution Centre and a managed destination?
- Can it safely keep a persistent line alive without causing cargo routing disruption?
- Is line churn required or harmful for cargo routing? RESEARCH REQUIRED.
- Does Transport Fever 2 require stable lines for certain cargo behaviors? RESEARCH REQUIRED.
- Does a zero-vehicle persistent line continue to influence cargo routing correctly? RESEARCH REQUIRED.

### Reassignment and Dispatch

- Can the mod dynamically reassign an existing vehicle from one service or line to another?
- Can it move a vehicle from standby to a managed service without destroying line state?
- Can it return a vehicle from managed service back to standby or a depot pool?
- Can it do this for multiple vehicles on the same destination?
- Are there constraints or limitations on vehicle reassignment or route change timing? RESEARCH REQUIRED.
- What is the safest moment or state for truck reassignment? RESEARCH REQUIRED.
- Can a vehicle carrying loaded cargo be safely reassigned to a different line mid-journey, or must reassignment happen only when empty/at a terminal? RESEARCH REQUIRED — only an empty/test vehicle's cross-line `setLine` has been proven so far.

### Sentinel / Service Vehicle Concept (see DECISIONS.md Decision 18)

- Does a capacity-1 vehicle register and sustain cargo demand the same way a normal-capacity vehicle does? General TF2 knowledge suggests yes (presence and cargo-type match gate demand, not capacity), but this is unconfirmed locally. RESEARCH REQUIRED.
- Can one such vehicle register demand for multiple simultaneous cargo types at a destination, or only the type it happens to be carrying? RESEARCH REQUIRED — determines whether one sentinel per line is sufficient or one per cargo type is needed.
- See the SENTINEL CAPACITY TEST in `ROADMAP.md` Stage 0 for the proposed test design.

### Save/Load Persistence

- Can the mod persist custom state (e.g. which stops the player has selected as managed) across a save/reload using TF2's game_script save/load hooks? RESEARCH REQUIRED — not yet implemented or tested anywhere in the codebase.

### Standby / Parking Concept

The standby pool concept is a key design element, but it depends on how the game models idle vehicles and depot-like state.

Questions:

- Can idle trucks be grouped into a standby pool or mover line at the Distribution Centre?
- Is a vehicle's standby state represented by line assignment, depot assignment, or another state?
- Is it better to model standby as a dedicated line, a depot pool, or an internal dispatch state? RESEARCH REQUIRED.
- Can a standby line physically hold trucks without causing unwanted circulation? RESEARCH REQUIRED.

### Persistent Managed Lines

The design prefers persistent system-managed lines instead of repeatedly creating and deleting lines.

Questions:

- Does the API allow stable line management across long periods?
- Are persistent lines compatible with cargo routing for road freight?
- Is there a technical penalty for line persistence or dynamic reallocation? RESEARCH REQUIRED.

### Compatibility and Capacity

The design assumes compatibility and capacity can be read and respected.

Questions:

- Does the API expose cargo type compatibility and load capacity cleanly?
- Are there differences across vehicle ages, vehicle types, and cargo classes?
- Can the mod safely infer whether a given truck can carry a specific cargo type? RESEARCH REQUIRED.
- Can carrying capacity be extracted reliably for early horse carts, mid-century trucks, and modern high-capacity vehicles? RESEARCH REQUIRED.

### Inter-Distribution-Centre Fleet Assistance

- Can a vehicle be safely temporarily reassigned between Distribution Centre controllers?
- How should home-centre ownership be persisted?
- Does cross-centre reassignment affect cargo routing?
- How do borrowed trucks safely return home?
- Can a player-defined local reserve be enforced before trucks can be lent? RESEARCH REQUIRED.

### Inter-Distribution-Centre Cargo Transfer

- Can bulk cargo be transferred between Distribution Centres using the base game's cargo routing system?
- Can persistent lines between centres support this naturally?
- Does this create artificial cargo demand or conflict with base-game destination/routing logic? RESEARCH REQUIRED.

### Standby Economics Research

- Does the base game provide reduced operating cost for vehicles genuinely waiting in a station or terminal?
- What exact reduction, if any, occurs when waiting or idling in a controlled terminal state?
- Does this differ from vehicles queued or stopped outside a terminal?
- Should the mod prefer native TF2 waiting-cost mechanics over a custom maintenance rebate? RESEARCH REQUIRED until tested.

### Historical Physical Distribution Centres

- Can era-based Distribution Centre physical buildings be introduced in a way that fits Transport Fever 2's historical progression?
- Will separate loading positions and standby positions be required to represent bottlenecks and infrastructure differences?
- Can reverse-in loading bays be supported by pathing or vehicle behaviour, or do they require a forward-only fallback?
- Is Blender the appropriate future workflow for asset creation, and what exact export requirements apply? RESEARCH REQUIRED.

## Verification Strategy

The project must use a staged validation process:

1. inspect the official API references and examples,
2. run a minimal Lua test harness,
3. confirm the behavior against a controlled in-game scenario,
4. record the results in a design decision log,
5. and only then proceed to implementation planning.

## Explicit Rule

No feature may be considered implemented unless the underlying API behavior has been proven in a test environment. If nothing in the API can support the feature, the feature is rejected or postponed as RESEARCH REQUIRED.
