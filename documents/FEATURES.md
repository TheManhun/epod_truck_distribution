# TF2 Distribution Manager — Feature Breakdown

**For current build status, see `PROGRESS.md`.** This file is the original wishlist/scope breakdown from before development started; the constraints and future-feature descriptions below are largely still valid, but it does not reflect what's actually been built (see `PROGRESS.md`) or the Decision 17/18 model that superseded the "standby pool" framing described here.

## Must Have

These are the features required for the V1 road freight/truck distribution system.

### Distribution Centre Core

- place and configure a logical Distribution Centre controller for V1,
- associate the centre with a Transport Fever 2 town,
- assign it to a managed region or network area,
- track active managed stops,
- and present the centre state in a clear GUI.

Note: in V1, the Distribution Centre is a logical dispatch controller. A custom physical Distribution Centre building is a later feature, not part of V1.

### Managed Stop Selection

- player selects which cargo delivery stops are managed by the centre,
- stop list is manually controlled by the player,
- and the centre can track destination status over time.

Current design path (see `DECISIONS.md` Decision 18): this selection happens through an explicit setup mode in the GUI — the player picks a candidate stop, and that action is what makes it managed. Selecting a stop makes the mod create one dedicated persistent line to it, once, at setup time.

### Fleet Ownership and Assignment

- player purchases and assigns a truck fleet,
- player determines centre fleet size,
- existing available trucks can be assigned to standby or service,
- multiple trucks may be allocated to the same destination when required,
- and the total fleet remains fixed unless the player changes it.

### Dispatch and Standby Logic

- idle trucks belong to a standby pool or standby line at the Distribution Centre,
- trucks can be reassigned from standby to managed delivery services,
- trucks can return to standby when they are no longer required,
- and dispatch is based on actual transport requirements rather than automated optimization.

Current design path (see `DECISIONS.md` Decisions 17 and 18): there is no separate idle standby pool in the plan being built right now. Every truck stays assigned to some managed line at all times; the fleet starts evenly spread across managed lines and is then weighted toward whichever lines show the most demand, with a floor guaranteeing at least one vehicle stays on every managed line. Dispatch itself ships recommend-only first, before any phase that reassigns trucks live. The standby-pool-of-idle-trucks model above remains a longer-term idea, not discarded, just not what's currently being implemented.

### Operational Visibility

- show fleet size,
- show active trucks,
- show standby trucks,
- show destination status,
- show cargo backlog or waiting information,
- and show warnings when available fleet cannot adequately service demand.

### Cargo and Capacity Awareness

- vehicle cargo compatibility is detectable,
- vehicle carrying capacity is detectable,
- and the dispatcher respects these constraints as far as the API allows.

### V1 System Boundaries

- road freight/trucks only,
- no auto-buy/sell behaviors,
- no automatic ideal fleet sizing,
- no auto stop selection,
- no automatic route optimization,
- and no automatic redesign of the player's network.

## Nice to Have

These features are useful but not required for V1 and remain pending API verification.

- per-destination pending cargo summary,
- historical dispatch statistics,
- assignment reason logs,
- warnings for underutilised trucks,
- stop prioritisation labels,
- default standby grouping rules,
- simple GUI filters for active, standby, and overloaded destinations,
- and Inter-Distribution-Centre Fleet Assistance for same-town centres, if player-enabled and technically safe.

### Inter-Distribution-Centre Fleet Assistance

This is a future / nice-to-have feature rather than a V1 requirement.

Example model:

- two or more Distribution Centres may be associated with the same town,
- spare standby vehicles may be lent to a neighbouring centre when player-enabled,
- borrowed vehicles remain identifiable as belonging to their home centre,
- vehicles return to their home centre when assistance is no longer required,
- the player can specify a minimum local reserve before trucks can be lent,
- and the system does not auto-buy, auto-sell, or permanently rebalance fleets without player action.

This requires API verification before implementation.

## Experimental

These features may be explored after a stable V1 proof-of-concept, but they are not mandatory and may require additional API research.

- persistent system-managed line model between the centre and managed stops,
- standby line behavior as a formal dispatch state,
- a dedicated, non-fleet-counted "sentinel/service" vehicle (capacity 1, era-appropriate skin) to keep a managed line's cargo connection active without drawing from the countable truck fleet — unverified, see the SENTINEL CAPACITY TEST in `ROADMAP.md` Stage 0,
- dynamic reassignment under time-varying demand,
- advanced service balancing rules without automatic optimisation,
- inter-Distribution-Centre cargo transfer,
- physical Distribution Centre staging and vehicle parking,
- visible vehicle staging in the Distribution Centre yard,
- reverse-in truck bays,
- and other physical yard behaviours that depend on Transport Fever 2 pathing and simulation support.

### Inter-Distribution-Centre Cargo Transfer

This is a separate future concept from fleet assistance. It is not a V1 feature.

Possible future model:

- Producer / rail hub,
- central Distribution Centre,
- regional Distribution Centres,
- local final-mile delivery services.

This could enable regional distribution, hub-and-spoke freight networks, and multi-stage logistics, but only if Transport Fever 2 cargo routing and persistent lines can support it safely. This remains EXPERIMENTAL / FUTURE and RESEARCH REQUIRED.

## Future

These are explicit future expansions and not V1 requirements.

- era-based physical Distribution Centre constructions,
- historical progression from goods/cart yard to freight depot to distribution centre to logistics centre,
- loading-position and standby-position capacity separation,
- physical truck parking/staging area,
- reduced standby vehicle operating or maintenance costs if technically feasible,
- train distribution yards,
- ship distribution ports,
- bus/tram dynamic dispatch,
- aircraft dispatch,
- Blender-created era-appropriate style assets,
- and multi-modal distribution centre coordination.

## Feature Freeze

A temporary FEATURE FREEZE is in effect during Stage 0.

No additional feature concepts should be added during Stage 0 unless they are required to solve a proven technical blocker. New ideas discovered during development should normally be placed in a deferred ideas/backlog section and must not expand the current implementation scope.

Immediate project priority remains:

1. Complete Stage 0 API research.
2. Build the minimal technical test harness.
3. Prove one existing road freight vehicle can transition: STANDBY → DELIVERY SERVICE → STANDBY
4. Test two destinations.
5. Test multiple trucks.
6. Only then proceed toward Truck Distribution V1.

The physical Distribution Centre, historical models, truck parks, reverse parking, town-level sharing, inter-DC assistance and other advanced features must not delay this proof-of-concept.

## Product Rule

Features should only be considered part of the design once they are grounded in verified API behavior and stage-appropriate testing. Unverified automation, cargo transfer assumptions, physical-yard assumptions, or route manipulation remains blocked until proven.
