# TF2 Distribution Manager — Test Plan

## Purpose

This test plan defines the minimum validation required before progressing between development stages. The project is intentionally structured around technical proof-of-concepts, so each stage has explicit evidence requirements.

Any test that cannot be executed or verified against Transport Fever 2 behavior is treated as RESEARCH REQUIRED.

## Stage 0 — Discovery and API Baseline

### Goal

Determine whether the required data and actions are possible within the base game's Lua/modding API.

### Tests

- verify that the mod can enumerate relevant vehicle states,
- verify that the mod can inspect cargo types and capacities,
- verify whether a stop or destination exposes cargo demand and backlog data,
- verify whether line state is inspectable,
- verify whether vehicle reassignment is possible,
- verify whether a town can host a logical Distribution Centre association,
- verify whether a town may support multiple Distribution Centres without redesigning the core architecture,
- verify whether a persistent managed line can be treated as stable instead of disposable,
- and run the STANDBY COST TEST.

### STANDBY COST TEST

Compare identical vehicles over the same controlled period:

A. vehicle operating normally,
B. vehicle genuinely waiting inside a station/terminal,
C. vehicle stopped/queued outside a terminal,
D. vehicle in whatever standby mechanism the Distribution Manager prototype uses.

Measure actual charged running costs.

Goal: determine whether the base game already provides an economic discount for genuinely waiting vehicles. If confirmed, prefer using Transport Fever 2's native waiting-cost mechanics rather than implementing a custom maintenance rebate.

### SENTINEL CAPACITY TEST (see DECISIONS.md Decision 18)

Compare an identical destination stop under three conditions over the same controlled period:

A. no assigned vehicle at all,
B. served only by a capacity-1, single-cargo-type vehicle,
C. served by a normal-capacity truck.

Then, with B in place, add a second simultaneously-demanded cargo type at the same destination and check whether the capacity-1 vehicle registers demand for the type it isn't carrying.

Goal: confirm whether a capacity-1 vehicle sustains a cargo connection like a normal truck does, and whether one sentinel vehicle per line is enough or one per cargo type would be needed. Only proceed with the era-progression service-vehicle concept in FEATURES.md/MASTERPLAN.md if both hold up.

### Feature Freeze

A temporary FEATURE FREEZE is in effect during Stage 0.

No additional feature concepts should be added during Stage 0 unless they are required to solve a proven technical blocker. New ideas discovered during development should normally be placed in a deferred ideas/backlog section and must not expand the current implementation scope.

### Pass criteria

- each required capability is either confirmed or explicitly classified as RESEARCH REQUIRED,
- no assumptions are treated as true without evidence,
- the town-based structure is evaluated without assuming it is already supported,
- and the design decisions are updated using the verified facts.

## Stage 1 — Technical Proof of Concept

### Goal

Prove the central concept works in a minimal in-game scenario.

### Critical runtime experiment

- ONE existing road freight vehicle,
- ONE standby state/line,
- ONE delivery service.

Prove:

- standby → delivery service → standby.

Then expand the test to:

- ONE standby pool,
- TWO destinations,
- MULTIPLE trucks.

### Functional tests

#### Distribution Centre model

- create a minimal local Distribution Centre controller associated with a town,
- attach a test managed stop list,
- and confirm the centre can track the managed set without requiring a custom building prototype.

#### Standby pool concept

- assign an idle truck to standby,
- confirm it is recognisable as standby rather than active service,
- and verify it can be reassigned when needed.

#### Single-destination dispatch

- create one managed destination,
- mark it as requiring service,
- dispatch one truck from standby,
- and confirm the system can reassign or route the truck as intended.

#### Reassignment test

- assign a truck from standby to a managed destination,
- then return it to standby once the destination no longer requires it,
- and confirm the tracking state remains coherent.

#### Persistent line evaluation

- prototype a stable line between centre and destination,
- compare it with repeated create/delete behavior,
- and confirm whether the game requires continuity for reliable cargo routing.

#### Loaded cross-line reassignment (new — see DECISIONS.md Decision 18)

- load a truck with real cargo destined for its current line's stop,
- reassign it via `setLine` to a different persistent line mid-journey,
- and confirm whether the cargo is delivered, dropped, or lost, rather than assuming empty-vehicle behavior generalizes.

#### Managed-stop persistence (new — see DECISIONS.md Decision 18)

- select a stop as managed through the setup flow,
- save and reload the game,
- and confirm whether the managed-stop selection and its dedicated line survive, using TF2's game_script save/load hooks (not yet implemented anywhere in the codebase).

### Pass criteria

- the central dispatch concept works in a minimal controlled scenario,
- the standby model remains coherent,
- dynamic reassignment is possible or specifically blocked by API constraints,
- the town-based controller model remains compatible with a future multi-centre town design,
- loaded-cargo cross-line reassignment behavior is confirmed rather than assumed,
- managed-stop selection is confirmed to survive a save/reload or explicitly documented as not yet supported,
- and the persistent-line question is answered by evidence instead of assumption.

## Stage 2 — Truck Distribution V1 Validation

### Goal

Validate the road truck system before accepting it as a viable release feature.

### Functional tests

#### Fleet constraints

- verify the player-defined fleet is respected,
- verify the mod does not auto-buy or auto-sell vehicles,
- verify no automatic fleet sizing logic overrides the player's input,
- and verify no assignable vehicle is used outside the player's fleet.

#### Managed destination behavior

- verify the mod tracks which stops are managed,
- verify multiple trucks can be allocated to the same destination when required,
- verify active and standby statuses are reported correctly,
- and verify destination overload/waiting conditions are visible.

#### Capacity and compatibility

- verify cargo compatibility checks are possible for supported vehicle types,
- verify carrying capacity can be compared against destination need,
- and verify the mod behaves naturally across early and modern truck types.

#### Dispatch safety

- verify idle trucks are returned to standby appropriately,
- verify no vehicle disappears from the player's fleet during reassignment,
- verify no service assignment becomes inconsistent under switching demand,
- and verify the mod does not destabilise cargo routing when the vehicle changes service state.

#### GUI validation

- verify the Distribution Centre GUI displays fleet size, active trucks, standby trucks, destination status, and warnings,
- verify the player understands why trucks are assigned where they are,
- and verify that warnings appear when the available fleet cannot service demand.

### Pass criteria

- the player can define and operate a basic truck distribution network without the mod bypassing game logic,
- dispatch behavior is stable and understandable,
- fleet count is not auto-managed,
- and the system does not destabilise route or cargo behavior.

## Stage 3 — Reliability and UX Polish

### Goal

Ensure the system remains reliable and understandable in ordinary play.

### Tests

- test edge cases for unassigned vehicles,
- test empty or unavailable fleet states,
- test demand spikes and temporary shortages,
- test poor or missing connections to managed stops,
- test same-town multiple Distribution Centre scenarios without breaking the single-centre model,
- and confirm warning states trigger correctly.

### Pass criteria

- the GUI clearly explains shortages and standby conditions,
- the player can diagnose assignment state without hidden logic,
- and operational failure modes remain understandable and recoverable.

## Stage 4 — Future Research

### Goal

Assess whether future transport types or advanced logistics behaviours can fit within the same control philosophy.

### Tests

- evaluate API support for train route assignment,
- evaluate API support for ship or port logistics,
- evaluate API support for bus/tram dispatch,
- evaluate API support for aircraft dispatch,
- evaluate same-town Inter-Distribution-Centre Fleet Assistance with a minimum reserve rule,
- evaluate inter-Distribution-Centre cargo transfer through persistent lines and cargo routing tests,
- evaluate era-based physical Distribution Centres,
- evaluate loading-position vs standby-position capacity separation,
- evaluate reverse-in truck bay feasibility,
- and compare each mode against the V1 assumptions before adding any implementation work.

### Pass criteria

- each future mode is either backed by evidence or rejected as RESEARCH REQUIRED,
- and no expansion is added before proving the underlying API supports it.

## General Quality Gates

Before proceeding from any stage to the next, the project must confirm:

- the required API feature exists or is impossible to use,
- the prototype behaves as expected in a controlled scenario,
- the game remains stable and the mod does not replace base-game logistics logic,
- and all unresolved points are documented as RESEARCH REQUIRED.

## Completion Rule

A stage is considered complete only when its tests are run, evidence is recorded, and the next stage is justified by that evidence.
