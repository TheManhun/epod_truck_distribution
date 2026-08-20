# TF2 Distribution Manager — Architectural Decisions

## Decision 1 — V1 Distribution Centre is a logical controller, not a custom building

### Decision

The player defines the logistics network, and the V1 Distribution Centre acts as a logical dispatch controller rather than a purpose-built custom physical building.

### Reason

This keeps the V1 design focused on dispatch logic and fleet management without conflating it with future building construction and visual infrastructure features.

### Consequence

The project can include a Distribution Centre in V1 as a logical control object while clearly reserving purpose-built custom construction for a later stage.

## Decision 2 — Player-defined network, not auto-optimisation

### Decision

The player defines the logistics network, and the Distribution Centre dispatches vehicles through it.

### Reason

The project should not automate network design, route selection, or fleet sizing. Transport Fever 2 already has its own simulation model for demand and routing. The mod should augment that model rather than replace its decisions.

### Consequence

The design remains transparent, predictable, and aligned with player strategy.

## Decision 3 — V1 is road freight only

### Decision

The first production version focuses exclusively on road freight and trucks.

### Reason

This narrows the problem to the most straightforward implementation target and aligns with the need to prove the underlying API assumptions before expanding to more complex transport systems.

### Consequence

The architecture can be started with a simpler vehicle dispatch model, while keeping the codebase open to future modal expansion.

## Decision 4 — Dispatch existing player-owned vehicles only

### Decision

The Distribution Manager dynamically reassigns the player's available trucks to managed destinations; it does not automatically buy/sell vehicles.

### Reason

This preserves player control over fleet size, spend, and network design. It also avoids the risk of the mod becoming an autonomous economic simulator.

### Consequence

The mod behaves as a dispatcher, not a logistics AI.

## Decision 5 — Town-based Distribution architecture

### Decision

A Distribution Centre is associated with a Transport Fever 2 town, and the architecture is designed so a town may eventually support multiple Distribution Centres.

### Reason

This allows distribution infrastructure to scale naturally as a town grows without forcing a redesign of the core dispatch architecture. It also remains compatible with a single-centre V1 priority.

### Consequence

The architecture supports both a single-controller V1 and a future multi-centre town model.

## Decision 6 — Standby pool / standby line concept

### Decision

Idle trucks belong to a standby pool or standby line at the Distribution Centre, and they can be reassigned when needed.

### Reason

This is a clean way to model available but unassigned trucks. It also matches the operational concept of a central logistics hub managing a fleet that is not always actively allocated.

### Consequence

The design supports dispatch from a central control point while preserving the player's chosen fleet size.

## Decision 7 — Persistent system-managed lines are preferred over churn

### Decision

The mod should prefer persistent lines between the Distribution Centre and each managed destination rather than repeatedly creating and deleting lines.

### Reason

Stable lines may be required by Transport Fever 2 cargo routing and vehicle simulation. The project should not assume line churn is safe without testing.

### Consequence

The architecture is likely to include a persistent service state model, and the design remains adaptable to the game's actual line requirements.

## Decision 8 — Vehicle compatibility and carrying capacity affect dispatch, not player fleet decisions

### Decision

The system should detect cargo compatibility and carrying capacity so dispatch works naturally across a broad range of vehicle types, but it should not automatically buy or sell trucks based on those values.

### Reason

The player may use everything from early horse carts to modern high-capacity trucks. A dispatcher that ignores cargo fit and capacity would be unusable across the game's historical progression. At the same time, the player remains responsible for fleet decisions.

### Consequence

The design must be compatible with the game's vehicle metadata and require API verification before implementation, while preserving player choice over vehicle purchases and fleet size.

## Decision 9 — Native TF2 waiting-cost mechanics are preferred when verified

### Decision

If Transport Fever 2's native waiting-cost behavior is confirmed to reduce operating costs for genuinely waiting vehicles, the mod should prefer that system over a custom maintenance rebate or custom standby economic mechanic.

### Reason

The base game already contains waiting/full-load rules and behaviour. Reusing them is more robust than inventing a custom economic model unless the native system is insufficient.

### Consequence

The physical truck park or staging concept may become mechanically meaningful only if verified waiting-cost behavior is confirmed.

## Decision 10 — Same-town fleet assistance is future-only and player-enabled

### Decision

If two or more Distribution Centres are associated with the same town, they may optionally share spare fleet capacity in a future player-enabled assistance model.

### Reason

This can improve logistics flexibility without making the system autonomous. It should remain highly controlled and identifiable as a future extension rather than a V1 requirement.

### Consequence

Shared vehicles must remain identifiable as belonging to their home centre, and they must return when assistance is no longer required.

## Decision 11 — Historical progression should emerge through infrastructure and vehicle technology

### Decision

Physical Distribution Centre evolution should arise primarily through infrastructure and vehicle technology rather than arbitrary stat bonuses.

### Reason

This matches Transport Fever 2's historical progression and preserves player agency. Upgrades should be meaningful because of access to more loading positions, staging, internal traffic flow, and larger vehicle compatibility rather than hidden RPG-style boosts.

### Consequence

Future physical centre designs should emphasise genuine operational advantages and era-appropriate visuals rather than abstract numerical bonuses.

## Decision 12 — Feature Freeze is required during Stage 0

### Decision

The project must maintain a temporary FEATURE FREEZE during Stage 0 unless a new idea is required to solve a proven technical blocker.

### Reason

The immediate priority is to finish API research and a minimal technical proof-of-concept. Expanding the concept list before Stage 0 is complete would delay the critical validation work.

### Consequence

Advanced ideas such as physical Distribution Centres, reverse-in bays, multi-centre sharing, and historical asset pipelines remain recorded as future work, but they do not expand the current implementation scope.

## Decision 13 — Unknown API behavior is treated as a blocker, not assumed

### Decision

Any capability that is not verified is explicitly marked RESEARCH REQUIRED.

### Reason

The project is intentionally built around technical proof-of-concepts. We must not invent API capabilities or rely on assumptions about line state, cargo data, or vehicle reassignment.

### Consequence

The design is conservative and robust. It can evolve only based on evidence.

## Decision 14 — GUI must communicate operational state, not optimise away player decisions

### Decision

The GUI should show Distribution Centre state, associated town context, managed stops, fleet size, active trucks, standby trucks, destination status, cargo/backlog information, waiting times, and warnings.

### Reason

The player needs operational clarity without being handed an autonomous optimiser. This balances usability and control.

### Consequence

The interface will prioritise explainability and transparency.

## Decision 15 — Expand only after proof

### Decision

Future transport modes and advanced features will be considered only after the V1 road-freight research and build cycle is validated.

### Reason

The architecture should stay compact and evidence-driven. Overbuilding on speculative multi-modal design would increase technical risk without solving the immediate problem.

### Consequence

The roadmap remains modular and stage-gated.

## Decision 16 — Preserve game simulation authority

### Decision

Transport Fever 2 remains responsible for cargo demand, destination logic, and cargo routing wherever possible.

### Reason

The mod should support the game rather than override it. This reduces conflict with the base game's simulation and makes the mod less likely to break established transport logic.

### Consequence

A good implementation is one that integrates with existing game systems rather than replacing them.

## Outstanding Unknowns

The following items are design decisions that require runtime verification before they can be confirmed:

- whether vehicle reassignment can be done safely,
- whether persistent managed lines are required for stable cargo flow,
- whether the game exposes compatible cargo types and capacities reliably,
- whether a standby pool can be modelled cleanly through depot or line state,
- whether multiple Distribution Centres can safely share trucks,
- whether inter-DC cargo transfer can work with the base game's cargo routing,
- whether waiting-cost discounts occur for genuine terminal waits,
- whether physical yard and reverse-in concepts are viable with custom paths and visual behaviour,
- and how much live state the API exposes without adverse side effects.

These are not omissions; they are deliberate research gates.
