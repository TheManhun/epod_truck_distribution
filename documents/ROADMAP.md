# TF2 Distribution Manager — Roadmap

**For current build status, see `PROGRESS.md`.** This file describes the long-term staged plan and V1 constraints, largely still valid — but actual development has proceeded evidence-first (per `DECISIONS.md` Decision 13) rather than strictly stage-by-stage, and the "standby pool" model described below has been superseded by Decisions 17/18's persistent-line-per-destination model. Treat the stage structure here as the intended shape, not a literal log of what's been built or in what order.

## Overview

This roadmap is structured around technical proof-of-concepts. Progression between stages depends on proving that Transport Fever 2's Lua API can provide the required information and support the required runtime behavior before full design commitment.

The immediate development order remains:

1. Complete Stage 0 API research.
2. Build the minimal technical test harness.
3. Prove one existing road freight vehicle can transition:
   STANDBY → DELIVERY SERVICE → STANDBY
4. Test two destinations.
5. Test multiple trucks.
6. Only then proceed toward Truck Distribution V1.

The physical Distribution Centre, historical models, truck parks, reverse parking, town-level sharing, inter-DC assistance and other advanced features must not delay this proof-of-concept.

## Stage 0 — Discovery and API Baseline

### Goal

Establish what the mod can and cannot do inside Transport Fever 2's Lua/modding API before design is locked in.

### Deliverables

- inventory of suspected relevant API surfaces,
- notes on cargo, vehicle, and line introspection,
- a map of unknowns and assumptions,
- a working minimal test harness for prototype inspection,
- and verification of town association, multiple Distribution Centres, and standby-cost questions against official documentation and runtime testing.

### Key questions

- Can the mod inspect vehicle cargo compatibility?
- Can it inspect vehicle capacity?
- Can it inspect line state and cargo flow?
- Can it read stop or destination demand?
- Can it dynamically reassign an existing vehicle between lines or service states?
- Can multiple Distribution Centres be associated with the same town without redesigning the core architecture?
- Does Transport Fever 2 provide reduced operating cost for genuinely waiting vehicles in station/terminal states?
- Do historical physical Distribution Centre concepts need separate API support or are they purely later content work?

### STANDBY COST TEST

Compare identical vehicles over the same controlled period:

A. vehicle operating normally,
B. vehicle genuinely waiting inside a station/terminal,
C. vehicle stopped/queued outside a terminal,
D. vehicle in whatever standby mechanism the Distribution Manager prototype uses.

Measure actual charged running costs.

Goal: determine whether the base game already provides an economic discount for genuinely waiting vehicles. If confirmed, prefer using Transport Fever 2's native waiting-cost mechanics rather than implementing a custom maintenance rebate.

### SENTINEL CAPACITY TEST (added — see DECISIONS.md Decision 18)

Compare an identical destination stop under three conditions over the same controlled period:

A. destination with no assigned vehicle at all — baseline for whether demand appears/grows with zero service,
B. destination served only by a capacity-1, single-cargo-type vehicle — the sentinel/service-vehicle candidate,
C. destination served by a normal-capacity truck — current known-good baseline.

Then, holding B in place, add a second simultaneously-demanded cargo type at the same destination and observe whether the capacity-1 vehicle (carrying only one of the two types) registers demand for the type it isn't carrying.

Goal: confirm whether a capacity-1 vehicle sustains a cargo connection the same way a normal truck does (general TF2 knowledge says capacity does not gate demand registration — presence and correct cargo-type/catchment coverage do — but this is unconfirmed in this save), and specifically whether one sentinel per line is enough or whether multi-cargo-type destinations would need one sentinel per cargo type. Only commit the era-progression service-vehicle concept to V1 if both hold up.

### Feature Freeze

A temporary FEATURE FREEZE is in effect during Stage 0.

No additional feature concepts should be added during Stage 0 unless they are required to solve a proven technical blocker. New ideas discovered during development should normally be placed in a deferred ideas/backlog section and must not expand the current implementation scope.

### Exit criteria

- enough confirmed API behavior to design the dispatch model,
- unresolved questions explicitly listed as RESEARCH REQUIRED,
- and no commitment to production architecture before proof is gathered.

## Stage 1 — Technical Proof of Concept

### Goal

Prove that the mod can inspect the needed state and manipulate vehicle assignment in a controlled prototype.

### Scope

- build a minimal test environment for a Distribution Centre,
- prototype a managed stop list,
- prototype a standby pool concept,
- prototype a single-destination dispatch scenario,
- confirm vehicle reassignment can work without creating unstable network behavior,
- and evaluate whether a stable persistent managed line and standby line model are necessary for cargo routing.

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

### Must prove

- the mod can detect relevant vehicle and cargo state,
- the mod can observe active route/service state,
- the mod can reassign existing trucks to a new managed service,
- whether a truck can be safely reassigned across lines while still carrying loaded cargo, not just when empty (see DECISIONS.md Decision 18 — currently unverified),
- whether the mod can persist player-selected state (e.g. which stops are managed) across a save/reload, since nothing in the codebase implements TF2 mod save/load hooks yet (see DECISIONS.md Decision 18),
- the town-associated Distribution Centre model can be represented without architectural redesign,
- and any required line persistence model can be tested in the base game environment.

### Exit criteria

- successful prototype behavior with explicit logs and observable state changes,
- clear evidence for what is supported by API vs what remains unverified,
- and approval to continue to layered design for V1.

## Stage 2 — Truck Distribution V1

### Goal

Deliver a road freight-only Distribution Manager for the player's managed fleet.

### In scope

- Distribution Centre placement/configuration,
- town association for the logical Distribution Centre controller,
- managed stop selection,
- fleet assignment and fleet count control,
- dispatch from standby to managed destinations,
- return to standby when demand falls,
- cargo/backlog awareness for managed stops,
- active and standby vehicle status in the GUI,
- warnings when available trucks cannot service demand,
- and stable service handling for multiple trucks on the same destination when needed.

### V1 operating model

Distribution Centre
    |
    +-- persistent managed service → Stop A
    +-- persistent managed service → Stop B
    +-- persistent managed service → Stop C
    |
    +-- standby pool

The player assigns a fixed fleet to the Distribution Centre. The dispatcher dynamically changes allocation within that player-defined fleet, while the total fleet remains fixed unless the player changes it.

### Current design path — see DECISIONS.md Decisions 17 and 18

The diagram above is the long-term shape; this is the concrete path being built toward it right now:

1. The GUI gains a setup mode. The player selects a candidate stop, and that selection is what makes it "managed" — an explicit action, not passive detection.
2. Selecting a stop makes the mod create one dedicated line from the hub to that stop, once. That line then persists — it is not recreated or deleted afterward, consistent with Decision 7's preference for stable lines over churn.
3. The player's fixed fleet starts evenly spread across all managed lines.
4. The brain reallocates the surplus toward the highest-demand lines, while guaranteeing at least one vehicle stays present on every managed line at all times (a completely unserved line risks never generating a demand signal to recover from).
5. That floor-per-line vehicle may eventually be a dedicated, non-counted "sentinel/service" vehicle (era-appropriate courier, capacity 1) rather than one of the real fleet — see the SENTINEL CAPACITY TEST in Stage 0. Until that's confirmed, the floor is provisionally one real truck.
6. The dispatcher itself rolls out in two phases: a recommend-only phase (surfaces what it would reassign, moves nothing) before any phase that actually reassigns trucks live between the managed lines.

There is no separate standby pool of idle, unassigned trucks in this model — every truck stays assigned to some managed line at all times, just possibly a low-priority one running light or empty. A real standby/holding yard (trucks parked, not assigned to any line) remains deferred, not solved.

### V1 constraints

- road freight/trucks only,
- no auto-optimisation,
- no auto-buy/sell logic,
- no auto fleet sizing,
- no stop selection automation,
- no route generation outside player-defined network logic,
- no inter-Distribution-Centre fleet assistance unless explicitly player-enabled and verified later,
- no inter-Distribution-Centre cargo transfer,
- no era-based physical Distribution Centre construction in V1,
- and no attempt to replace Transport Fever 2 demand and cargo routing.

### Exit criteria

- V1 can dispatch the player's fleet to managed destinations based on actual requirements,
- town association and logical DC control are stable enough for routine dispatch,
- the standby concept is stable enough for routine dispatch,
- the GUI clearly shows relevant state and warnings,
- and the system works without destabilising cargo routing or vehicle assignment.

## Stage 3 — Polish and Operational Reliability

### Goal

Improve player usability, clarity, and operational safety before broader expansion.

### Focus

- stronger GUI status and warnings,
- better assignment diagnostics,
- improved service state reporting,
- robustness against edge cases such as missing vehicles, unserviced destinations, or temporary shortages,
- and better player feedback on standby/assigned counts.

### Exit criteria

- the feature set is stable,
- the player can understand why trucks are assigned where they are,
- and the mod remains a dispatch manager rather than a hidden optimizer.

## Stage 4 — Future Transport Modes

### Goal

Evaluate whether the same Distribution Centre philosophy can be extended to additional transport types.

### Candidate expansions

- train distribution yards,
- ship distribution ports,
- bus/tram dynamic dispatch,
- and aircraft dispatch.

### Constraints

These are future possibilities and not V1 requirements. Each expansion must be evaluated independently against the API and against gameplay fit.

## Stage 5 — Future / Optional Enhancements

### Goal

Add optional gameplay conveniences only if they are technically feasible and compatible with the design philosophy.

### Examples

- era-based physical Distribution Centre construction,
- loading-position vs standby-position capacity separation,
- physical truck parking/staging area,
- same-town Inter-Distribution-Centre Fleet Assistance,
- inter-Distribution-Centre cargo transfer experiments,
- physical vehicle staging in the yard,
- reverse-in truck bay experimentation,
- Blender-created historical assets,
- and optional advanced dispatch analytics.

### Important rule

These enhancements are not required for V1 and should not block early technical proof-of-concept work.

## Milestone Summary

- Stage 0: Research and API baseline.
- Stage 1: Technical proof-of-concept.
- Stage 2: Truck Distribution V1.
- Stage 3: Reliability and usability polish.
- Stage 4: Future transport modes.
- Stage 5: Optional future enhancements.

## Development Rule

No stage beyond Stage 0 should proceed without evidence from the prior stage. The project is intentionally structured to prevent overbuilding on unverified assumptions.
