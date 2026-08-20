# TF2 Distribution Manager — Master Plan

## Mission

TF2 Distribution Manager is a Transport Fever 2 mod that lets players define a logistics network and then direct the movement of their existing road freight fleet through that network. The player is responsible for network design, stop selection, and fleet planning. The mod is responsible for dispatching available trucks to managed destinations according to actual cargo demand and service requirements.

This project deliberately begins with a technical proof-of-concept model. The most important question is not whether the concept is attractive, but whether Transport Fever 2's Lua/modding API exposes enough information to inspect cargo demand, vehicle state, line state, and reassignment behavior before committing to full implementation.

## Core Design Principle

The player defines the logistics network; the Distribution Centre dispatches vehicles through it.

The mod must not:

- automatically redesign the network,
- choose stop locations,
- buy or sell vehicles,
- determine ideal fleet size,
- or replace Transport Fever 2's cargo routing logic.

Transport Fever 2 remains responsible for:

- cargo demand,
- destination selection,
- cargo routing,
- and the core simulation of vehicle movement and schedule logic wherever possible.

The Distribution Manager is responsible for:

- detecting which stops are managed,
- tracking cargo/backlog at those stops,
- assigning available trucks to active services,
- dispatching and reassigning existing vehicles,
- and warning when the player's available fleet cannot keep up with demand.

## Town-Based Distribution Concept

Distribution Centres can be associated with a Transport Fever 2 town.

The player still:

- decides where Distribution Centres are located,
- selects which delivery stops each Distribution Centre manages,
- buys the vehicles,
- determines fleet size,
- and designs the road/logistics network.

A town may eventually have multiple Distribution Centres, for example:

- Hendon North Distribution Centre,
- Hendon South Distribution Centre,
- Hendon Industrial Distribution Centre.

Each Distribution Centre continues to own/manage its own:

- managed stops,
- assigned fleet,
- standby vehicles,
- active services.

This allows distribution infrastructure to scale naturally as a town grows while preserving a modular architecture. For V1, one Distribution Centre working correctly remains the priority. Town association and multiple Distribution Centres should be designed so they can be added without redesigning the core architecture.

## V1 Scope

V1 focuses exclusively on road freight/trucks.

Within V1, the player must be able to:

- place and configure a logical Distribution Centre controller (the V1 dispatch hub),
- select which cargo delivery stops it manages,
- purchase and assign a truck fleet,
- determine how many trucks the centre has,
- and operate the centre without the mod automatically rescaling the fleet.

A V1 Distribution Centre is a logical control object used to manage dispatch and fleet assignment. It is not a purpose-built custom physical building. That custom building concept belongs to a later stage and remains explicitly outside V1.

The mod must work naturally with a broad range of truck types and capacities from early horse carts through modern high-capacity vehicles. Cargo compatibility and carrying capacity should be inspectable so dispatch logic can respect the actual vehicle model design, but fleet sizing remains the player's decision. Vehicle carrying capacity affects dispatch decisions but does not decide player fleet decisions.

## Future — Era-Based Physical Distribution Centres

Physical Distribution Centre buildings are FUTURE functionality. The logical V1 Distribution Centre remains unchanged.

Potential era progression:

- 1850 — Goods & Cart Yard
  - simple timber goods shed,
  - dirt/mud yard,
  - horse/cart staging,
  - crates, barrels and hay bales,
  - small and inexpensive facility.

- 1900 — Freight Depot
  - brick/industrial warehouse,
  - improved yard surface,
  - suitable for early motor trucks,
  - more organised loading/staging.

- 1950 — Distribution Centre
  - larger freight warehouse,
  - dedicated loading docks,
  - paved truck staging,
  - improved internal traffic flow.

- 1990 / modern — Logistics Centre
  - modern warehouse,
  - multiple loading bays,
  - substantial truck staging area,
  - potentially separate entry/exit roads.

Exact years, costs and capacities are not decided and must be balanced later.

These future physical structures should not be treated as a V1 requirement.

## Historical Availability and Player Upgrades

New Distribution Centre generations should become available according to game year.

Availability does not automatically replace an existing centre. The player chooses whether and when to pay for an upgrade or replacement. An old facility may remain useful for a small town even after newer facilities become available.

The design should avoid arbitrary RPG-style efficiency bonuses where possible and prefer physical/infrastructure advantages such as:

- additional loading positions,
- additional genuine standby/staging positions,
- improved internal traffic flow,
- better entry/exit arrangements,
- and the ability to accommodate larger later-era vehicles.

This preserves player decision-making and fits Transport Fever 2's historical progression.

## Future — Loading vs Standby Capacity

A physical Distribution Centre may have separate:

- cargo loading positions,
- standby/staging positions.

Example:

A Distribution Centre might have:

- 4 loading bays,
- 12 standby positions,
- but a player-defined fleet larger than either number.

This could create genuine infrastructure bottlenecks. A large fleet does not automatically mean high throughput if the Distribution Centre has inadequate loading/staging infrastructure.

Exact implementation is RESEARCH REQUIRED.

## Experimental — Physical Vehicle Staging

Visible trucks/carts should physically use the Distribution Centre yard where technically feasible.

Possible behaviour:

- idle vehicles visibly occupy staging positions,
- dispatched vehicles leave staging and travel to loading/service,
- returning vehicles re-enter standby/staging,
- early horse carts wait naturally in an open goods yard,
- later trucks use organised parking/staging bays.

This feature is cosmetic/immersive unless supported naturally by Transport Fever 2 vehicle/path mechanics. It must not fake vehicle behaviour in ways that destabilise simulation.

## Experimental — Reverse-In Truck Bays

Reverse-in loading/parking bays are EXPERIMENTAL and RESEARCH REQUIRED.

Desired modern-era behaviour:

- a truck enters the Distribution Centre yard,
- manoeuvres through an internal vehicle path,
- reverses into a loading or standby bay,
- waits there,
- and later exits when dispatched.

Do not assume Transport Fever 2 supports road vehicles reversing along custom paths. The project must investigate later:

- whether custom construction vehicle paths can support reverse movement,
- whether road vehicles can visually reverse,
- whether animation/path tricks would be required,
- whether articulated vehicles behave correctly,
- and whether this can be achieved without interfering with simulation/pathfinding.

Failure to support reversing must not block the physical Distribution Centre feature. A fallback design using forward-only drive-through bays is acceptable.

## Graphics / Asset Pipeline — Future

Future physical Distribution Centre assets may be created in Blender.

Target:

- visually compatible with Transport Fever 2's art direction,
- efficient rather than unnecessarily high-detail,
- historically appropriate materials/architecture,
- appropriate LOD/performance considerations,
- multiple era-specific models rather than one modern model across the entire timeline.

The modelling workflow may use AI-assisted Blender tooling, but generated assets must still be inspected, optimised and exported in whatever formats Transport Fever 2 actually requires. Exact TF2 model/export requirements remain subject to technical research.

## Architecture Overview

### 1. Distribution Centre (logical controller in V1)

The Distribution Centre is the logical control point for a managed logistics region in V1.

In other words, the V1 concept is a dispatch and management layer rather than a custom physical structure. The custom construction of a purpose-built Distribution Centre building is a separate future feature and not part of this phase.

Responsibilities:

- define the set of managed stops,
- hold the fleet assignment state,
- expose a GUI for centre status and dispatch overview,
- maintain the standby pool for idle vehicles,
- and coordinate service assignment for each destination.

### 2. Managed Stops

Each managed stop is a transport stop or destination that the player links to the centre.

Responsibilities:

- hold managed status,
- report cargo demand and backlog,
- indicate whether service is active,
- provide waiting time and shortage information,
- and maintain a relationship with the Distribution Centre.

### 3. Fleet Layer

The fleet layer is not a simulated AI optimizer. It is a deterministic dispatcher.

Responsibilities:

- know which vehicles belong to the player's fleet,
- know which are standby,
- know which are assigned to managed destinations,
- and reassign vehicles between standby and service when the player or the system requests changes.

### 4. Dispatch Logic

Dispatch logic decides which trucks are sent to which managed destinations. It does not invent new network routes or reconfigure the map. It operates on the existing network and the current state of the managed services.

Responsibilities:

- evaluate destination demand and backlog,
- check vehicle compatibility and capacity,
- maintain active truck allocation counts,
- dispatch from standby to service when needed,
- return vehicles to standby when service is no longer required,
- and warn when demand exceeds available fleet coverage.

### 5. Service Model

The service model tracks each destination as a managed operation rather than a raw line object.

The likely V1 model to investigate is:

- Distribution Centre
  - persistent managed service → Stop A
  - persistent managed service → Stop B
  - persistent managed service → Stop C
  - standby pool

This model supports a player-defined fleet where total fleet size remains fixed unless the player changes it. The dispatcher dynamically changes allocation within that fleet, while the GUI warns the player if demand exceeds available vehicles.

The system should investigate:

- a standby/parking concept where idle trucks belong to a standby pool or line at the Distribution Centre,
- persistent system-managed lines between the Distribution Centre and each managed destination,
- and future same-town fleet assistance between multiple Distribution Centres if player-enabled and API-verified.

This avoids repeatedly creating and deleting lines in situations where stable lines may be required by Transport Fever 2 for cargo routing and simulation consistency.

## Design Principles

### 1. Player-driven logistics

The mod should never override the player's strategic choices on network topology, fleet ownership, or capacity planning.

### 2. Respect the base game simulation

Transport Fever 2 should remain the authoritative source for route, cargo, and destination simulation wherever possible. The mod should adapt to the game's simulation rather than trying to replace it.

### 3. Reassign existing vehicles, not create artificial demand

V1 should operate by dynamically dispatching the player's available trucks. It should not create or destroy network structures in ways that interfere with Transport Fever 2's cargo system.

### 4. Prefer stable lines over churn

System-managed persistent lines are preferred because stable line ownership may be required for consistent cargo routing. Tests must verify whether repeated line churn is necessary or harmful.

### 5. Do not guess unverified API behavior

Any API capability that has not been proven by research and testing is explicitly marked as RESEARCH REQUIRED.

### 6. Function before optimisation

The project should prioritise proving that vehicle state, cargo state, and line state can be inspected and changed reliably before adding advanced heuristics or automation.

### 7. Native TF2 waiting economics are preferred when proven

If Transport Fever 2's native waiting-cost behaviour is verified to reduce operating costs for genuinely waiting vehicles, the mod should prefer that system over a custom maintenance rebate or custom standby economic mechanic.

### 8. Historical progression should emerge from infrastructure and vehicle technology

Historical progression should primarily come from physical infrastructure and vehicle technology rather than arbitrary stat bonuses.

Examples:

- 1850: small dirt goods yard and horse carts,
- 1900: organised freight depot and early trucks,
- 1950: larger paved distribution facility,
- modern era: large logistics centre with substantial loading/staging infrastructure.

The player decides whether upgrading is worth the cost.

## UI/UX Principles

The GUI should show:

- Distribution Centre state,
- associated town context,
- managed stops,
- fleet size,
- active trucks,
- standby trucks,
- destination status,
- cargo/backlog information,
- waiting times,
- and warnings when available fleet cannot adequately service demand.

The UI should help the player understand operational capacity without turning into an optimiser or autopilot.

## Non-goals for V1

The following are explicitly out of scope for V1 and should not be included in the initial build:

- purpose-built Distribution Centre construction or custom physical Distribution Centre buildings,
- physical truck parking or staging area,
- automated vehicle purchase or sale,
- route optimisation,
- ideal fleet sizing calculation,
- Inter-Distribution-Centre Fleet Assistance,
- inter-Distribution-Centre cargo transfer,
- train distribution yards,
- ship distribution ports,
- bus/tram dynamic dispatch,
- aircraft dispatch,
- and reduced standby operating costs unless technically feasible and verified.

## Feature Freeze

A temporary FEATURE FREEZE is in effect.

No additional feature concepts should be added during Stage 0 unless they are required to solve a proven technical blocker. New ideas discovered during development should normally be placed in a deferred ideas/backlog section and must not expand the current implementation scope.

Immediate project priority remains:

1. Complete Stage 0 API research.
2. Build the minimal technical test harness.
3. Prove one existing road freight vehicle can transition:
   STANDBY → DELIVERY SERVICE → STANDBY
4. Test two destinations.
5. Test multiple trucks.
6. Only then proceed toward Truck Distribution V1.

The physical Distribution Centre, historical models, truck parks, reverse parking, town-level sharing, inter-DC assistance and other advanced features must not delay this proof-of-concept.

## Philosophy

This is a logistics control mod, not a transport planner. Its job is to make the player's fleet usable as a managed distribution system without bypassing the game's own route simulation and demand model. That makes it a strong fit for Transport Fever 2's design, while keeping the mod modular and proof-driven.

## Decision Gate

A project is only allowed to continue into a full implementation phase once the technical proof-of-concept verifies that Transport Fever 2 exposes the required vehicle, cargo, and line information needed to safely implement dynamic dispatch and reassignment.

If the API cannot support the required operations, the design must be revised rather than forced through speculation.
