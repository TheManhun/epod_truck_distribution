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

Advanced ideas such as physical Distribution Centres, reverse-in bays, multi-centre sharing, and historical asset pipelines remain recorded as future work, but they do not expand the current implementation scope. `IDEAS.md` is that deferred ideas/backlog section — new ideas discovered during development land there, unverified and unbuilt, until they're checked against real behavior and graduate into a proper Decision.

### Clarification — the Truck Park model is not the "physical truck parking" non-goal

MASTERPLAN.md lists "physical truck parking or staging area" as an explicit V1 non-goal, meaning the *gameplay feature* of visible trucks occupying a yard. The Truck Park model referenced by `config.PARK_NAME` in `res/scripts/epod_td/config.lua` is not that feature. It is a technical mechanism: routing a vehicle through a real stop forces a genuine stop-arrival event, which is used to work around a cargo-pickup bug that occurs when a vehicle is reassigned to a new destination purely via `setLine` without an intervening real arrival. It exists to make dispatch behave correctly, not to deliver the staging-yard gameplay feature, so its presence does not expand Stage 0's implementation scope or violate the feature freeze.

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

## Decision 17 — V1 dispatch model: mod-created persistent lines, recommend before reassign, no standby yard

### Decision

**Superseded in part by Decision 18** — two claims below are corrected there: persistent services are not limited to existing player-created lines (the mod creates one dedicated line per managed stop, once, during setup), and managed-stop status is not automatic/structural (the player opts a stop in explicitly through a setup step). See Decision 18 for the current setup/allocation model. The rest of this decision (no standby yard, recommend-before-reassign, Hub == Distribution Centre, `reverseVehicle` is not the dispatch mechanism) still stands.

For V1, a "persistent destination service" is a line serving that destination that, once created, is not repeatedly torn down or rebuilt — whether it originates from a line the player already built, or one the mod creates during setup (see Decision 18). Trucks normally stay assigned to their current line. The Distribution brain reads waiting cargo and demand across those lines and, only when a real demand imbalance justifies it, reassigns trucks between the persistent lines. The brain ships with a recommend-only phase first (surface what it would do) before any phase that actually moves trucks live.

There is no standby/holding yard in this model. Trucks with no or light demand on their current line keep running that line, potentially lightly loaded or empty, rather than parking. The Truck Park mechanism referenced by `config.PARK_NAME` (see the Decision 12 clarification) is a technical stop-arrival workaround only — it is explicitly NOT the standby pool, and any resemblance in `vehicles.lua`'s current "PARK-servicing" vehicle classification to a standby pool is incidental, not the intended V1 standby mechanism.

"Hub" (`config.HUB_NAME`) and "Distribution Centre" are the same logical concept for V1: an existing TF2 cargo station the player selects, not a custom placeable construction object. The current selection-driven GUI (whichever station the player has selected in the base game's own UI) is how the Distribution Centre is inspected/configured; a persistent "stays enabled without needing to remain selected" configuration may be added later, but a custom physical building is not required for the dispatch brain to function.

A destination stop becomes "managed" automatically and structurally for V1: any road-cargo line touching the selected hub station has its other stops treated as managed destinations, with no explicit per-stop player registration required. An explicit include/exclude toggle is a possible later UI/polish addition, not a V1 requirement.

The `reverseVehicle` / stop-index "reverse destination test" in `dispatcher.lua` is an investigative proof about vehicle-state introspection, not the intended dispatch mechanism. The intended mechanism (once the brain moves past recommend-only) is controlled line reassignment between existing persistent lines.

### Reason

Constant creation/deletion of lines risks destabilising TF2's cargo routing (see Decision 7). Creating a line once per managed stop and then leaving it alone, reassigning only trucks (not lines) between persistent destinations, keeps the mod inside "dispatch existing vehicles through the player's network" rather than drifting into "the mod builds and rebuilds its own logistics network on every decision." Starting with recommend-only output before live reassignment lets the demand/ranking logic be validated against real save data before it is trusted to move trucks unsupervised.

### Consequence

`Truck - CD - Hendon`'s single-line, repeated Park/Hub/Destination topology is Stage 1 scaffolding used to prove demand-scanning and vehicle introspection — it is not the intended V1 line topology (see Decision 18 for the one-line-per-stop model that replaces it). Standby-pool and physical-parking design questions (Outstanding Unknowns, below) remain open and deferred, not solved by the Park stop. Any future dispatch implementation should target persistent per-stop lines and a recommend-first rollout, not the `reverseVehicle` experiment.

## Decision 18 — Setup-driven managed stop selection with demand-weighted fleet allocation

### Decision

This is the current concrete design path for the V1 dispatch brain, replacing the "reuse existing lines only" and "automatic/structural managed-stop detection" framing in Decision 17 with a more specific model:

1. **Setup is explicit and player-driven.** The GUI panel gains a setup mode: the player selects a candidate stop, and that action is what makes it "managed" — not passive structural detection. This restores MASTERPLAN's original language ("the player... selects which delivery stops each Distribution Centre manages") more precisely than the automatic detection Decision 17 described.
2. **Selecting a stop creates one dedicated persistent line** from the hub/Distribution Centre to that stop. This line is created once, at setup time, and is not recreated or deleted afterward — it becomes one of the persistent destination services described in Decision 17.
3. **The player's fixed fleet is initially spread evenly** across all managed lines when they are first set up.
4. **The dispatch brain then reallocates the surplus toward higher-demand lines** — moving the majority of trucks toward whichever managed destinations show the most backlog, while guaranteeing every managed line keeps at least one truck present at all times. The floor exists because a line with zero vehicles risks never generating a demand signal to recover from — TF2's demand appears to be driven by line/connection presence rather than vehicle capacity (see the capacity note below), so the floor is about presence, not capacity.
5. **Whether that floor truck should be one of the real fleet, or a separate non-counted "sentinel/service" vehicle (capacity 1, thematically an era-appropriate courier — horse rider in 1850, van in the modern era), is explicitly UNVERIFIED and deferred.** It is a promising refinement — if valid, it removes the floor's draw on the countable fleet entirely, which also sidesteps the edge case where floor-per-line could exceed total fleet size as the number of managed stops grows. It is not committed V1 architecture until tested. See Outstanding Unknowns.

### Reason

An opt-in setup step gives the player explicit, auditable control over what's managed, rather than sweeping in "whatever happens to be adjacent to the hub." Creating the line once at setup time (not on every dispatch decision) keeps this compatible with Decision 7's preference for persistent lines over churn. The even-split-then-reweight allocation model is simple, transparent, and explainable in the GUI, consistent with Decision 14. The floor-per-line rule is a direct response to a real TF2 mechanic risk (a completely unserved line may never register demand), not an arbitrary safety margin.

### Consequence

Decision 17's "existing lines only" and "automatic detection" framing is superseded by this decision for the parts that conflict; its recommend-before-reassign, no-standby-yard, and Hub == Distribution Centre points still stand unchanged. Two new technical unknowns are introduced by this decision and must be proven before it can be trusted in play: whether a truck can be safely reassigned across lines while still carrying loaded cargo, and whether the mod can persist the player's managed-stop selections across a save/reload (nothing in the codebase currently saves any mod state). Both are recorded in Outstanding Unknowns.

## Decision 19 — "Split Into Lines" is live-proven for retrofitting an existing setup

### Decision

`line_splitter.lua`'s `splitLineIntoDestinations`, triggered by a "Split Into Lines" button in the panel, takes an existing multi-destination line (e.g. one combined `Hub -> A -> Hub -> B -> Hub -> C` line, exactly the kind of setup a player retrofitting this mod onto an existing save would already have) and creates one dedicated two-stop line per real destination via `api.cmd.make.createLine`. This is Stage 1 of Decision 18's "one dedicated persistent line per managed stop" model, and it is now live-proven, not just designed: run against the actual test save's real `Truck - CD - Hendon` line (5 real destinations plus the hub's own return entry, correctly excluded), it created all 5 destination lines successfully, processed sequentially with each `createLine` callback awaited before the next was sent, fully logged, zero failures.

Stage 1 is deliberately additive-only: the source line and every vehicle on it are left completely untouched. This was verified in the log itself (`Source line untouched. No vehicles were moved.`) and is a hard boundary, not an incidental detail — moving the source line's real, currently-working fleet onto the new lines is Stage 2, a separate and more consequential action gated on verifying loaded-vehicle cross-line reassignment safety (still an Outstanding Unknown below), not attempted here.

### Reason

Bundling a freshly-proven, low-risk capability (`createLine`) with an unrelated, unverified, higher-risk one (reassigning a live, likely-loaded fleet) in the same action would have repeated exactly the mistake Decision 13 exists to prevent — trusting an assumption because an adjacent fact happened to check out. Splitting the retrofit into two stages lets the player get real, immediately-useful infrastructure (the destination lines exist, ready for Stage 2 once it's built) without staking the player's actual working fleet on an unproven action.

### Consequence

A player adding this mod to an existing save with a combined multi-stop line (the exact scenario this was designed for) can now retrofit it into per-destination lines safely today. Decision 18's allocation model (even split, then demand-weighted reallocation) cannot yet run for real, since Stage 2 (moving vehicles onto the new lines) does not exist yet — that remains the next concrete step once loaded-vehicle reassignment safety is checked.

`line_splitter.lua` copies each new line's terminal assignment directly from the source line's own stop (unchanged behavior, never actively chosen). Across two live test sessions this produced different visible terminal groupings in the game's Terminals tab (first session: all lines on Terminal 1; second session, same code: the 5 new lines on Terminal 2) despite nothing in the terminal-copying code changing between them — most plausibly TF2's own dynamic terminal balancing, not a fixed binding from what's written. This was **deliberately not investigated further**: the new lines currently carry zero vehicles (Stage 2 doesn't exist yet), so there is no real traffic to observe real terminal behavior against. Testing terminal assignment meaningfully requires real vehicles actually running the new lines — i.e. it depends on Stage 2, not the other way around. Revisit once Stage 2 exists and real trucks are moving.

## Decision 20 — Stage 2: assign one vehicle per split line, retire its stop only after that assignment is confirmed

### Decision

`line_splitter.M.assignVehiclesAndRetireStops(sourceLineId, hubStationGroup, onComplete)`, wired to an "Assign Trucks + Retire Stops" button (config.DEBUG only, manually-triggered), is the first real Stage 2 implementation. For each currently-empty mod-created ("● ") split line at the hub, sequentially: pull one vehicle off the real source line, hold it, `setLine` it onto the split line, release the hold, and — **only if that `setLine` reported success** — rewrite the source line via `updateLine` to remove every occurrence of that destination's stop. If a destination has no vehicle available, or `setLine` is rejected, its stop is deliberately left on the source line so the destination keeps being served the old way rather than being dropped with nothing covering it. This was the literal ordering requested: never retire a stop before its replacement is confirmed live.

It is decoupled from `splitLineIntoDestinations` (Stage 1) on purpose — it re-discovers empty split lines by reading their own two real stops (entity IDs), not by name parsing or by depending on having just run Stage 1 in the same session, so it works the same way regardless of when the split lines were created.

### Reason

This combines two mechanisms that are each independently proven elsewhere in this codebase — `setLine` cross-line reassignment (the two-park test, and `runLoadedVehicleReassignmentTest`) and `updateLine` route rewriting (the original Truck Park stop injection, `route_injector.M.run()`, which already rewrote this exact production line's stops live) — for the first time together, on the real production line, unattended once triggered. Given Decision 13's evidence-first discipline, this is explicitly scoped to the disposable test save, not declared safe for a real save yet.

### Consequence

The one thing this does **not** verify is whether cargo a picked vehicle was already carrying survives the reassignment intact — `runLoadedVehicleReassignmentTest`'s first run was inconclusive (see the Outstanding Unknown below), not positive. Running `assignVehiclesAndRetireStops` is itself now also a real-world data point on that same question, across up to several vehicles at once, so its own log output (and in-game observation of whether each reassigned truck keeps working normally) should be read with that in mind before this is ever considered for a real save.

**Live run result**: all 5 real destinations at Hendon East processed successfully — every `setLine` and every subsequent `updateLine` stop retirement reported `true`, logged in strict order. Post-run demand numbers looked healthy (Queens Road 159 waiting, Alexander Road 163, The Grove 71, Park Avenue 9, Highfield Road 11), confirming the new lines are attracting real cargo now that each has a vehicle. One side effect worth noting: the source line (`Truck - CD - Hendon`) was not deleted, only retired stop-by-stop — since every one of its real destinations got handed off, its own `demand.scan()` now shows nothing but `Hendon East | 0 waiting`, and its remaining ~45 vehicles (fleet total held steady at 70 throughout — nothing was lost, only moved) are left looping a destination-less shell line. This is the direct, correct consequence of the retirement rule, not a bug, but it is an orphaned-line/idle-fleet gap that Decision 21 exists to close.

## Decision 21 — Stage 3: redistribute the spare fleet across split lines by demand, excluding zero-demand destinations

### Decision

`fleet_allocator.M.redistributeSpareVehiclesByDemand(sourceLineId, hubStationGroup, onComplete)`, wired to a "Redistribute Spare Vehicles by Demand" button (config.DEBUG only, manually-triggered), addresses the orphaned-fleet gap Decision 20 leaves behind. It reads every managed ("● ") split line's current `demand.scan()` waiting total, then apportions the source line's remaining spare vehicles across them by largest-remainder apportionment, proportional to each destination's waiting total. A destination currently showing 0 waiting demand is excluded entirely from the split and keeps only its single Stage 2 seed vehicle — not starved further, but not given capacity it has shown no need for either. This is the literal rule agreed live: "if its 0 leave it as one truck, split the remaining based on demand."

### Reason

Directly closes the gap Decision 20's live run exposed: a large idle fleet stranded on a line with nothing left to serve. Demand-weighted allocation was already the target model in Decision 18; this is its first real implementation, now that Stage 2 makes "spare vehicles sitting on a used-up source line" a real, observable situation rather than a hypothetical.

### Consequence

**Caveat, raised live by the player and not yet independently verified through the API**: a terminal's waiting-cargo storage is finite (reportedly ~100-200 depending on terminal length, extendable by lengthening the terminal or attaching warehouses), and cargo generated beyond that cap despawns rather than continuing to accumulate. That means a `waiting` total is a FLOOR on true demand, not necessarily an accurate relative measure between two destinations with different terminal capacities — one could be silently losing cargo to despawn while reading a similar or lower number than another that isn't capped yet. `fleet_allocator.lua` uses the visible waiting total as its best available proxy anyway (no API for terminal capacity itself has been found — see TECHNICAL_RESEARCH.md) and documents this limitation inline; allocation results should be read with that in mind, not treated as a precise measure of true relative need.

### Terminal assignment — LIVE-CONFIRMED, both halves of the external lead checked separately

A player-pasted external source (not this project's own prior verification) proposed that `Line.Stop.terminal` is directly writable and controls a line's physical terminal assignment, alongside two `api.engine.getLineStopsForTerminal` / `api.engine.getTerminal2lineStops` query functions. Per Decision 13, this was treated as a lead to test, not a fact to build on — and testing it split the claim into one part that held up and one that didn't:

- **Confirmed true**: a one-line test (`route_injector.M.runTerminalAssignmentTest()`, since removed — superseded by Decision 22 below) changed `● Hendon East ↔ Queens Road`'s Hendon-stop terminal from `1` to `2` via the proven copy/modify/`updateLine` pattern, and both a re-read of the line's own data AND the player's own visual check of the game's TERMINALS tab confirmed the line actually moved to a different physical terminal bucket — not just a stop-field value silently ignored.
- **Confirmed false**: neither `api.engine.getLineStopsForTerminal` nor `api.engine.getTerminal2lineStops` exists in this game version — both checked `false` before ever being called.
- **New finding, from the live before/after pair itself**: the game's TERMINALS tab displays terminal numbers as `(raw Line.Stop.terminal value) + 1`. The line's raw terminal was `1` before the change (shown in-game as "Terminal 2"), and became `2` after (shown in-game as "Terminal 3"). `terminal_allocator.lua` (Decision 22) writes 0-based values directly to account for this.

This is now a real capability, not just a tested one.

## Decision 22 — Stage 4: spread managed lines across terminals, ranked by demand

### Decision

`terminal_allocator.M.spreadLinesAcrossTerminals(hubStationGroup, onComplete)`, wired to a "Spread Lines Across Terminals" button (config.DEBUG only, manually-triggered), replaces the single-line terminal test with the real feature: it reads the hub's actual terminal count (`stations.getTerminalCount`, summed across every physical station in the group), ranks every mod-created ("● ") managed line by current `demand.scan()` waiting total, and assigns the highest-demand lines their own dedicated terminal first (one each, up to the terminal count). Once terminals run out, each remaining lower-demand line is assigned to whichever terminal currently carries the least combined demand, so any forced sharing lands on the terminal that can best absorb it. This is exactly the rule proposed live in `IDEAS.md`'s "Demand-Weighted Terminal Sharing" entry, now built rather than just recorded as an idea.

Only ever touches mod-created ("● ") lines — never "Grain" or another pre-existing line — matching every other stage's scoping discipline.

### Reason

Once Decision 21 confirmed the underlying write mechanism actually works (both in the data and visually, in-game), leaving it as a single-line proof rather than the real multi-line feature would have been leaving proven, working capability on the table. Replacing the test with the real feature (rather than keeping both) follows the same reasoning as retiring the loaded-vehicle test once Stage 2/3 existed — a superseded diagnostic left in place is just clutter.

### Consequence

**Live run #1 found a real bug, since fixed.** `stations.getTerminalCount` worked correctly (matched the TERMINALS tab). But the allocation itself ignored pre-existing occupancy: it assigned terminal indices 0..N-1 to managed lines purely by demand rank, with no awareness that "Grain" (a real, unmanaged, 20-vehicle line) was already sitting on terminal 0. The result — the highest-demand managed line (Queens Road) landed on the same terminal as Grain, exactly the congestion the feature exists to prevent. Caught live by the player: "terminal 1 had the grain line, so this should be left."

**Fix**: added a stock-take step (`stockTakeExistingLoad` in `terminal_allocator.lua`) that reads every line at the hub *except* the ones about to be reassigned, sums each one's current demand into whichever terminal it already occupies, and seeds the allocator's starting state with that real occupancy instead of an all-zero baseline. The assignment loop was also simplified: instead of a separate "first N ranked lines get dedicated slots by index" branch, it now always places the next line (in demand order) onto whichever terminal currently has the least total load — dedicated-vs-shared now emerges naturally from that one rule instead of being a special case, and it automatically respects pre-existing occupancy from lines like Grain. Re-run against a live save many times since (this stage is now a normal part of the "Split Into Lines & Organize Terminals" button, run on every real split).

**Live run #2 found a second, related bug, since fixed.** Freshly split lines (right after Stage 1, before Stage 2/3 or real gameplay generate any activity) all show `waiting = 0`. The "always place onto the currently-lowest-load terminal" rule from the first fix breaks down here: assigning a zero-demand candidate never changes its terminal's tracked load (`+= 0`), so the terminal that started lowest stays lowest forever, and every zero-demand candidate piles onto that SAME terminal instead of spreading. Player hit this live setting up a brand-new hub — all 5 freshly-split lines landed on the same terminal, and retrying the button didn't help (the bug doesn't depend on how many times it runs, only on the candidates all being tied at zero, which stayed true both times). Root cause confirmed by tracing the exact numbers from the log: terminal 0 (Grain) started at load 230, terminals 1-5 (the not-yet-deleted source line's other stops) started at 535 each — a permanent gap zero-weighted candidates could never close, not a coincidental tie.

**Fix**: `stockTakeExistingLoad` now also tracks a per-terminal *line count* (how many lines already sit there) alongside load. The assignment loop compares `(lineCount, load)` as a pair, **line count first**: pick whichever terminal currently has the fewest lines, and only fall back to comparing load when line counts tie. This naturally gives every candidate its own terminal while capacity allows (matching the feature's own "dedicated terminal first" design intent even better than before), and only merges onto a shared terminal — picked by lowest load, i.e. cheapest to share — once every terminal already has at least one line.

**Live run #3 found this fix was still incomplete — corrected, not overclaimed.** The line-count-first fix was traced by hand against the bug and looked right, but the player re-tested live and found a residual case: Grain and the single highest-ranked new line still shared terminal 1 (the other 4 spread correctly across terminals 2-5). Root cause: at the moment terminal-spread runs (chained directly onto Stage 1, *before* a separate "Assign & Balance Fleet" click later deletes the original combined line), that original line is still alive and still touches 5 terminals — stock-take counts it as real permanent occupancy exactly like Grain, tying every terminal it touches with Grain's terminal on line count (all at count=1). The load tiebreak then picks Grain's terminal for the first candidate, since Grain's baseline load happened to be lower than the soon-to-be-deleted source line's. The player's own retry of the whole button — coincidentally, not because retrying itself helped — "fixed" it, because by the second run the source line had since been deleted by an intervening Assign & Balance click, so stock-take no longer found anything tying with Grain.

**Real fix**: the line(s) actually split in this run are now collected (`sourceLineIds`, threaded through `splitAllManagedLines`'s recursion in `epod_truck_distribution.lua`) and passed to `spreadLinesAcrossTerminals`, which passes them to `stockTakeExistingLoad` to exclude — the same treatment already-managed lines get, since this line is equally not "real permanent occupancy": it's mid-transition, about to be superseded by this same overall operation. **Live-verified**: a fresh test showed Grain alone on terminal 1 and all 5 managed lines spread cleanly across terminals 2-6, no doubling up.

**Deferred, not built**: a player-pasted external proposal suggested adding hysteresis/stability thresholds ("never reshuffle for tiny demand changes," "make the smallest useful reassignment" instead of a full recompute each time) to stop terminals "flapping" between assignments. The underlying idea (avoid needless churn) is reasonable general practice, but there is no evidence yet that this allocator actually flaps in a way that matters — it has only been run twice, both manually triggered, not on any kind of timer. Building stability logic against a problem that hasn't been observed would be exactly what Decision 13 exists to prevent. Recorded in `IDEAS.md` as a future consideration if repeated runs actually show unstable/thrashing assignments.

**Also open, from Decision 22's first version**: what actually happens with 3+ lines sharing one terminal (does it visibly congest, or does TF2 handle it the way it already handles today's default unmanaged sharing), and whether writing a terminal index at or beyond the station's real terminal count errors, clamps, or is silently accepted.

## Decision 23 — Delete the source line once it is provably empty

### Decision

`line_splitter.M.deleteEmptySourceLine(sourceLineId, hubStationGroup, onComplete)` is chained as a third automatic step onto the "Assign & Balance Fleet" button, after Decision 20's assign step and Decision 21's balance step both complete. It refuses to act unless the source line has exactly 0 vehicles AND 0 real (non-hub) destination stops remaining — only then does it call `api.cmd.make.deleteLine` (proven live since `route_injector`'s original create/delete test). If either check fails, it leaves the line alone and reports why.

### Reason

Proposed live once the numbers made it obvious the source line was genuinely done: a live run's vehicle counts across the 6 real managed lines summed to exactly 70, matching the fleet total with nothing left on the source line, and its own `demand.scan()` showed nothing but the hub's own empty bucket. Chained onto the existing button rather than given its own — the same "combine what we know works" reasoning as Decision 21, and the safety check (not a confirmation click) is what actually gates the destructive action, matching how `deleteLine` was already trusted to run unattended in the original create/delete test.

### Consequence

Not yet run. Once it has been, `Truck - CD - Hendon` should disappear from both this mod's panel and the game's own line list/TERMINALS tab, cleaning up the stray Hendon-only stop entries that were cluttering the terminal breakdown alongside the real managed lines.

## Decision 24 — `data()`'s `save`/`load` hooks are not usable for real persistence in this mod; use direct file I/O (`io.open`) instead

### Decision

`epod_truck_distribution.lua`'s `data()` now includes `save`/`load` fields (a real, base-game-confirmed mechanism — see the "Persistence" entry below). This went through two crashes and seven fix attempts before landing on the real design:

- **v1**: `loadPersistedState` incremented `persistedState.loadCount` unconditionally, every call. **Crashed the game** (hard engine assertion, see Reason).
- **v2 ("fix" that didn't work)**: guarded the increment with a session-scoped local boolean, on the assumption the engine calls `load()` twice on one continuously-running script instance. Retested live — **identical crash, identical log pattern**. The guard never blocked the second call.
- **v3 (stopped the crash, but the test itself was still broken)**: made `load()`/`save()` fully passive (no mutation at all) and moved the counting into `runStartupDiagnosticsOnce`, the existing `guiUpdate`-driven one-shot-per-process guard. This did stop the crash — but retested live and the counter stayed at `1` across an in-game save-and-reload instead of climbing to `2`. Reading the raw stdout log directly showed why: `runStartupDiagnosticsOnce` only fires once per **process**, and the player's second "load" was done via TF2's in-game Load Game menu without quitting — so the process-scoped guard correctly never re-armed. It was simply never the right trigger for "count every genuine load."
- **v4 (stopped the crash, moved mutation to a button, but STILL didn't round-trip)**: `load()`/`save()` made fully passive and silent, with the one deliberate mutation (`bumpPersistenceTestCounter`) moved to a new DEBUG button, fully decoupled from `load()`/`save()`'s own call cadence. Retested live with the full protocol (click button, save, fully quit, relaunch, load, click button again) — counter still came back as `1`, not `2`.
- **v5 ("fix" that still didn't work)**: added back a guard boolean in `loadPersistedState`, gating the plain `persistedState = state` copy rather than any computed value. Retested live with the full protocol — **still** came back as `1`, not `2`.
- **v6 ("fix" that still didn't work)**: refined the guard to only latch inside the branch that actually adopted valid data (`state == nil`, empty table, or `reset == true` returns immediately without touching the flag) — matching `guidesystem.lua`'s own `if initialized then return end` idiom exactly. Retested live with the full protocol, three full quit/relaunch/load cycles — **still** came back as `1` every time.
- **v7 ("fix" that still didn't work)**: dropped the "adopt only once" framing entirely. `loadPersistedState` gated on whether the *player* had made a deliberate change this session (`hasMutatedPersistedStateThisSession`, set only inside `bumpPersistenceTestCounter`) — freely adopting every valid `load()` call before that, refusing everything after. Retested live with the full protocol — **still** came back `0` on disk, checked directly against the `.sav.lua` file.
- **v8 (current, working design)**: added per-call instance fingerprinting (a unique tag per chunk execution) to every `save()`/`load()`/button-click log line, and found the real root cause (Finding #7, see Reason) — the engine runs multiple, entirely disconnected instances of this script's top-level code within one session, and the button's mutation was landing on a different instance than the one whose `save()` was actually wired to real serialization. No guard logic inside `load()`/`save()` could ever fix this, since a Lua `local` cannot be shared across separate executions of the same chunk. Fixed by moving `persistedState` (and the mutation guard) into uniquely-namespaced Lua globals (`_G["__EPOD_TD_PERSISTED_STATE__"]`, `_G["__EPOD_TD_HAS_MUTATED_PERSISTED_STATE__"]`) instead — globals live in the one shared `_G` table for the whole Lua VM, so every instance of the chunk reads and writes the same underlying data regardless of how many separate instantiations exist.

### Reason

Live-confirmed root cause for the crash: **both** crash logs showed `loadPersistedState` firing twice in immediate succession at startup (`loadCount` printed as `1`, then `2`), followed immediately by:

```
urban_games/train_fever/src/Game/Game.cpp:330: void __cdecl CGame::StartGameSim(void):
Assertion `m_data->gameStates[1]->ScriptSave() == m_data->gameStates[0]->ScriptSave()' failed.
```

TF2's own engine calls a script's `load()` more than once per session as part of its own internal consistency check in `CGame::StartGameSim` — it takes two internal game-state snapshots and asserts their `ScriptSave()` (i.e. our `save()`) output is **identical**. v1 mutated `persistedState` on every call to `load()`, so the two snapshots disagreed and the engine hard-crashed on its own assertion — not a catchable Lua error, a fatal engine-level exception that force-quit the game. v2's session-scoped local boolean didn't survive between those two internal calls either — the identical crash with the identical `1`-then-`2` pattern is only explainable if each of the engine's two internal calls runs against its own fresh instantiation of the script (fresh top-level locals, guard included), not two calls into one instance.

Live-confirmed root cause for why v3's counting silently failed (diagnosed by reading the raw `stdout.txt` crash-dump log directly, since v3 also added temporary unconditional prints inside `load()`/`save()` to see exactly what the engine was doing): **`save()`/`load()` fire continuously throughout ordinary gameplay** — thousands of times over a single test session, each `load()` call handed a distinct, freshly-allocated state table. This meant no signal inside `load()`/`save()` themselves, and no `guiUpdate`-driven "once per process" guard, could distinguish "the player genuinely loaded a save" from the engine's own internal cadence of calls.

v4's button-driven mutation still didn't survive a real save/quit/relaunch/load cycle: `loadPersistedState` was unconditionally doing `persistedState = state` on every one of those thousands of ongoing calls, apparently clobbering the deliberately-bumped in-memory counter with stale data before it ever reached a real save.

v5, v6, and v7's guards all failed the same live retest (counter stuck at, or reverting to, a lower value than expected across a real save/quit/relaunch/load, checked directly against the `.sav.lua` file each time). Each was reasoned through carefully and each turned out to share the same unstated assumption: that there is exactly ONE `persistedState` in play per session, and the only question is *when* `load()`'s calls happen relative to it. That assumption was never actually tested until v8.

**FINDING #7, LIVE-CONFIRMED (this is the one that actually explains the whole saga)**: added a unique per-instance fingerprint (a fresh table's address, fixed for one chunk execution's lifetime) to every `save()`/`load()`/button-click log line, then ran the full protocol once more. The log showed **three separate module instances** initialized within one session. The button's click (`bumpPersistenceTestCounter`) landed on one instance; that instance's own `load()` calls also fired correctly. But the `save()` calls that were actually feeding the real `.sav.lua` serialization belonged to a **completely different instance** — one whose `persistedState` the button had never touched, permanently stuck at `loadCount=0` for the rest of the session. This directly explains every prior failure: v4-v7 were all correctly reasoning about ONE instance's `load()`/`save()` behavior while the actual data loss was happening at a structural level *between* instances that no amount of guard logic inside a single instance could ever reach. The engine appears to re-execute this script's top-level code more than once per session — consistent with the early boot log's repeated "Mods changed, recreating data..." messages — and, evidently, keeps GUI bindings (`guiUpdate`, button clicks) pointed at a later instantiation than the one whose `save`/`load` registration is actually used for real serialization.

**FINDING #8, LIVE-CONFIRMED: v8 ALSO failed.** Retested the shared-global design with the full protocol, checked directly against the `.sav.lua` file — still `loadCount=0`, unchanged from v4-v7. This means even `_G` is not reliably shared across whatever "multiple instances" mechanism Finding #7 uncovered — either TF2's mod sandbox gives each script instantiation a genuinely isolated Lua environment (where not even globals bridge across instances), or something else about the engine's save/load hook registration is broken in a way this project never fully diagnosed. **This was not chased further** — after eight live-tested attempts across two crashes, the decision was made to stop iterating on `save`/`load` entirely and test a structurally different, orthogonal mechanism instead: real file I/O via Lua's `io` library, writing the mod's own file directly rather than going through the engine's hooks at all. This was the user's suggestion.

**FINDING #9, LIVE-CONFIRMED: file I/O works, and reliably persists across a real process restart.** `io.open` is available in this mod sandbox (undocumented — no shipped base-game script under `res/config/game_script/` was found using it) and writes land at the TF2 install directory root when given a plain relative filename (e.g. `io.open("epod_td_file_io_test.txt", "w")` → `D:\Steam\steamapps\common\Transport Fever 2\epod_td_file_io_test.txt`). A counter test (read existing value, increment, write back) was run through two full quit/relaunch cycles: session 1 wrote `1`, session 2 read `1` and wrote `2`, session 3 read `2` — each confirmed both via the log and by reading the file directly. Unlike every `save`/`load` attempt, this has never needed a guard, a global, or any workaround — plain sequential read/write just works, because it never depends on which script instance the engine happens to be running.

### Consequence

**`save`/`load` are not being used for real persistence in this mod.** Eight live-tested attempts (v1-v8) across two hard crashes and at least two distinct root causes (a real engine-level determinism constraint, and an unresolved multi-instantiation problem that even Lua globals couldn't bridge) is enough evidence that this mechanism is not safely usable here, even though it is real, shipped, and used successfully by base-game scripts. Whether those base-game scripts avoid the multi-instantiation problem some other way (a different registration path, a different lifecycle) was not investigated — not worth the time once a working alternative existed.

**Real persistence in this mod now means: files written directly via `io.open`, not `data()`'s `save`/`load` fields.** Any future real persisted state (network fingerprints, managed-hub selections, etc. — see PROGRESS.md/Not Started) should use this mechanism. Two open design questions before building on it for real: (1) the install-directory location is not appropriate long-term — Steam can touch that folder on verify/update, and a single shared file isn't scoped to a specific savegame, so different saves would silently clobber each other's data; a per-savegame-identified path (or a path under the user's `userdata` folder) needs to be found and tested. (2) it's unconfirmed whether `io` is reliably available in all contexts this mod might run in (different TF2 versions, other players' installs, Steam Deck/Proton) since it isn't used by any shipped script — this should be treated as a soft assumption, not a guarantee, and the mod should degrade gracefully (log and skip, not crash) if `io.open` ever returns nil.

The broader lesson for this whole saga: eight consecutive fix attempts against `save`/`load` were each internally consistent and each wrong in a way only caught by checking ground truth (the actual `.sav.lua` file, then a per-instance log fingerprint) rather than by re-reading the code more carefully. After several reasoned fixes in a row all fail the same live check against the same mechanism, the more efficient move is to question whether that mechanism is fixable at all, not to refine the same guard a fifth or sixth time — file I/O ended up working on the first real attempt once the underlying approach changed.

Worth flagging separately: `save()`/`load()` firing thousands of times per session is itself a real cost consideration for anything that ever tries to use them again — kept as a documented reason to avoid the mechanism, not something to design around.

## Decision 25 — Removed the abandoned custom 3D model / construction experiment (`_archive_epod_single_bay/`, `model_source/`, `res/models/`)

### Decision

Deleted three directories entirely: `_archive_epod_single_bay/` (a custom `STREET_STATION` construction definition, `epod_single_bay_terminal.con`/`.module`, plus two `.mdl` files), `model_source/` (two `.fbx` source files, `epod_truck_park.fbx`), and `res/models/` (compiled mesh/material/model output — `Cube.001`, `Cube.046`, `Cube.050`, `Ground_mesh`, `MAT_Gravel`, `MAT_Wood` — clearly raw, unedited exporter names from a 3D modeling tool, not anything hand-authored for this mod).

### Reason

Player hit an unexpected in-game prompt while modifying an existing station: "Costs: $18,272 / 10 modules will be removed." That doesn't come from anything this mod's actual Lua logic does (`epod_truck_distribution.lua` and `res/scripts/epod_td/*` are pure gameplay/dispatch logic — no construction, no models, no modules). Investigation found `_archive_epod_single_bay/epod_single_bay_terminal.con` sitting in the mod folder: a genuine, functional-looking `STREET_STATION` construction type with real module slots (`street_terminal_cargo`, etc.) — exactly the shape of thing that produces a "modules will be removed" prompt when an existing placement of it gets touched. None of this was ever wired into or referenced by the mod's actual distribution-management code; it was leftover from an earlier, separate experiment (evidenced by the folder's own name and by `model_source/`'s and `res/models/`'s generic, unedited exporter-default names).

### Consequence

All three directories are gone. Since none of this was ever committed (only staged), nothing was lost from git history. If custom 3D construction pieces are ever wanted again for this mod, they should be built and tested as a deliberate, separate effort — not left half-wired-in from an abandoned attempt, where a leftover `.con` file can silently affect real player stations without any of this mod's own code being involved at all.

## Decision 26 — Managed-line identity moved to a persistent registry (entity IDs), decoupled from the `●` name prefix

### Decision

Built `res/scripts/epod_td/managed_registry.lua`: a small module that is now the sole authority on "is this line managed by Dynamic Distribution," replacing every runtime `name:sub(1, 4) == "● "` check across the codebase (9 sites, in `epod_truck_distribution.lua`, `terminal_allocator.lua`, `line_splitter.lua`, `fleet_allocator.lua`, and `route_injector.lua`'s test tooling) with `managed_registry.isManaged(lineId)`. `line_splitter.lua`'s Stage 1 now calls `managed_registry.register(newLineId)` immediately after a new split line is confirmed created (resolved by name via `lines.findByName`, since the `createLine` command callback only confirms success, not the new entity ID). The `●` prefix itself is untouched and still gets added to every managed line's display name (`epod_truck_distribution.lua`'s `displayLineName` logic) — it is now purely cosmetic, exactly as `IDEAS.md`'s original PRIORITY entry specified: "Names belong to the player. Identity belongs to the Brain."

State is persisted via `io.open` (the mechanism proven in Decision 24 — not `data()`'s `save`/`load` hooks), written to `epod_td_managed_lines.txt` as one line-entity-ID per line. No dependency on knowing which specific save is currently active: every session's first registry query triggers a one-time `migrateAndValidate()` pass that (a) drops any stored line ID that no longer resolves to a real line in the current game (stale — a different save, or since deleted) and (b) registers any currently-existing `●`-named line not already in the record. This is exactly the migration/validation approach `IDEAS.md`'s own "Persistence Integration" and "Migration / Safety" sections specified, not an improvised substitute.

### Reason

The player's own `IDEAS.md` PRIORITY entry identified a real fragility: every managed-line check across the codebase was name-based (`name:sub(1, 4) == "● "`), meaning a player rename would silently break fleet allocation, terminal allocation, and split-line discovery for that line — the `●` had become part of DD's internal state instead of a purely cosmetic hint. The fix requires two things the mod didn't reliably have until recently: (1) persistent, non-Lua-`local` storage that survives a session boundary, and (2) a validation step so stale/foreign data doesn't get trusted blindly — both are now available (Decision 24's file I/O work, and the validation pattern that decision's own saga made obvious was necessary).

### Consequence

Renaming a managed line (removing or changing the `●`) no longer affects whether DD manages it — membership is entity-ID-based, checked against `managed_registry.lua`, not the display name. Newly split lines register themselves automatically at creation time; no separate registration step is needed elsewhere.

**Live-verified since the design above was written**: migration was checked directly against the log — all 5 pre-existing `●` lines in the test save (Queens Road, Park Avenue, The Grove, Alexander Road, Highfield Road) migrated into the registry correctly on first load, matching the file written to disk exactly. Rename-survival was then checked directly: `● Hendon East ↔ Park Avenue` (entity 142769) was renamed in-game to `Hendon East - Park Avenue` (no `●` at all), and the very next demand-report/panel refresh still logged `Managed line: Hendon East - Park Avenue | entity=142769` — same entity ID, fully still tracked, proving the rename did not break management. The remaining open item is smaller than originally scoped: (1) a fresh Stage 1 split's immediate self-registration has not been separately live-tested (though it uses the same `lines.findByName` + `managed_registry.register` pattern already proven safe elsewhere), and (2) the persisted file still lives at the same TF2-install-directory location as Decision 24's proof-of-concept file — the "shouldn't live in Steam's own folder long-term" caveat applies equally here, an open polish item, not blocking correctness. `managed_registry.unregister(lineId)` exists and is ready for when a "Close Managed Line" feature (`IDEAS.md`) is eventually built, but nothing currently calls it — no code path deletes an actual managed line yet.

## Decision 27 — Vehicle cargo compatibility classification is live-verified to genuinely discriminate between vehicle types

### Decision

Built `vehicles.getAllCapacities`/`isCompatibleWithCargoType`/`getCompatibleCargoTypes` (reading each vehicle's real, fixed `allCapacities` field — what it can EVER carry, distinct from `cargoLoad`'s "what it's carrying right now") and a live verification test, `route_injector.testCargoCompatibility`, wired to a DEBUG button. The test scans every road vehicle game-wide (not just managed lines, so a restricted vehicle sitting anywhere still gets caught) and groups them by distinct capability profile.

### Reason

The first version of this test sampled only one vehicle per managed line and found all 5 samples shared the identical full 16-cargo-type list — the mechanism read real data with no errors, but never actually proved it could tell a restricted vehicle apart from a universal one, since every sampled vehicle happened to be generic. Rather than assume the mechanism worked from a single, possibly-unrepresentative sample, the player added deliberately semi-restricted trucks to the fleet and the test was rerun, scanning the full 99-vehicle fleet game-wide this time.

**Live-confirmed result**: 3 distinct capability profiles across 99 road vehicles — 95 universal vehicles (all 16 cargo types), 2 vehicles with 11 types (missing FOOD, GOODS, MACHINES, PLASTIC, TOOLS), and 2 vehicles with only 3 types (LOGS, PLANKS, STEEL). This proves `allCapacities` is a genuine per-vehicle-model restriction, not a carrier-wide default that happens to always return everything.

### Consequence

This closes the "is the raw compatibility data reliable" question that PROGRESS.md's cargo-compatibility item was blocked on. It does NOT yet mean compatibility is used anywhere in real dispatch decisions — no code path today checks a vehicle's compatibility before reassigning it (Stage 2/3's only current safety check is `isVehicleEmpty`, unrelated to cargo type). This is a hard prerequisite for the Planner/Opportunistic Dispatcher (`IDEAS.md`, PROGRESS.md Not Started #4), not the dispatcher itself — that logic still needs to be built on top of this now-proven-reliable mechanism.

## Decision 28 — Planner prerequisites live-confirmed: the `OnToArriveAtDestination` event fires reliably (very frequently, game-wide), and station cargo history genuinely breaks down by cargo type

### Decision

Wired `handleEvent` for real for the first time (`epod_truck_distribution.lua`'s `handleDeliveryEvent`, on `data()`'s `handleEvent` field, separate from `guiHandleEvent`) and ran it live, alongside a one-off deeper dump of a station's `itemsLoaded`/`itemsUnloaded._lastMonth`/`_lastYear` sub-tables (`stations.dumpItemHistory`, since removed — see below).

### Reason

Both were genuine open questions blocking the Planner + Opportunistic Dispatcher work (PROGRESS.md Not Started #3/#4): whether `OnToArriveAtDestination` (only ever confirmed present in shipped reference code, never actually fired in this mod) is real and reliable, and whether the cargo-profile idea from `IDEAS.md`'s "Runtime Fleet Rebalancing" (compatibility based on observed history, not just instantaneous waiting cargo) has real data to draw on.

**Event trigger — confirmed live and firing reliably.** A single, fairly short test session produced over 500 real fires (`DELIVERY EVENT: 500 total fires so far this session` was the last milestone logged). `param` reliably carried a real, readable cargo entity id each time; `src` was consistently empty across all 5 detail-logged fires — not yet understood, but `param` is the field that matters for identifying what arrived. **This is a genuinely high-frequency, game-wide event** — every cargo delivery in the whole save, not scoped to managed hubs — confirming `IDEAS.md`'s own "Material Change Threshold" caution was the right instinct: a Planner reacting to every single fire would reassess far too often to be useful; some batching/threshold is a real requirement, not a hypothetical one.

**Cargo history — confirmed to genuinely break down by cargo type.** The one-level-deep `dumpEntityInfo` had only ever shown `_lastMonth`/`_lastYear` as opaque table addresses; a dedicated one-level-deeper dump showed real per-type keys: `itemsLoaded._lastMonth = { _sum=0, CONSTRUCTION_MATERIALS=0, FUEL=0, FOOD=0 }`, `itemsUnloaded._lastMonth = { GRAIN=0, _sum=0 }` (station 126300 — Hendon East itself, all values 0 in this short test, but the STRUCTURE is what was in question, not the specific numbers). This confirms the Planner can read a service's recent cargo-type history straight from data TF2 already tracks, without building new history-tracking from scratch.

### Consequence

Both findings are prerequisites now closed, not the Planner itself — nothing yet consumes either. The `stations.dumpItemHistory` one-shot dump served its purpose and was removed (matching this session's own log-volume discipline) but stays available to call manually. The event handler stays wired permanently (it's cheap — increments a counter, only logs detail for the first 5 fires and a periodic count after that) since the Planner will eventually need it live. Next real design step: decide the actual "material change" threshold/batching rule now that real fire-frequency data exists to inform it, rather than picking a number blind.

## Decision 29 — Planner core (`planner.lua`) live-confirmed correct; real evidence that instantaneous-only demand is unsafe to act on

### Decision

Built `planner.lua`'s `M.calculateTargetAllocation` (a per-line target vehicle count, largest-remainder apportionment by current `demand.scan()` waiting cargo, floor of 1 vehicle per managed line) and a DEBUG "Show Fleet Plan" button (`handleShowFleetPlanButtonClick`) to log it against a real hub. Purely read-only — does not move a vehicle, does not depend on the Auto Redistribute toggle.

### Reason

**Math independently verified against the live log, not just eyeballed.** Hendon East, 54 managed vehicles, 214 total waiting across 5 managed lines (Grain correctly excluded — not `managed_registry`-managed): hand-computing the same floor-then-largest-remainder apportionment by hand reproduces the logged output exactly (Grove: waiting=194 → target=45, delta=+32; Highfield: waiting=18 → target=5, delta=+3; Park Avenue: waiting=2 → target=2, delta=0; Queens Road: waiting=0 → target=1, delta=-13; Alexander Road: waiting=0 → target=1, delta=-22). The algorithm is doing exactly what it was designed to do.

**That exact result is also the clearest evidence yet for why `IDEAS.md`'s cargo-profile refinement is load-bearing, not optional polish.** Queens Road and Alexander Road both happened to show 0 waiting cargo at the instant this ran, despite carrying 14 and 23 vehicles respectively (both real, active managed lines, not quiet by nature) — a naive Dispatcher acting on this literal output would strip 13 and 22 trucks off two working lines because of a momentary snapshot, exactly the "Fuel shows 120 right now but Food/Construction will be back in 30 seconds" failure mode raised the night before this was built. This is real, observed proof of the risk, not a hypothetical caution anymore.

**Bonus finding, not the main goal**: fixing the earlier one-level-deep entity dump limitation (see Decision 28) also revealed a real cargo-delivery entity's actual structure for the first time: `{ speed, vehicleUsed, id, type=SIM_CARGO, targetEntity, startTime, sourceEntity, cargoType }`. `cargoType` is handed over free on every delivery event — no separate read needed to know what arrived. `targetEntity` looks like the delivery's destination entity id, which — not yet confirmed — could let a future threshold filter `OnToArriveAtDestination` down to only deliveries at our own managed hubs instead of the whole game, a much better foundation than blind game-wide counting. `src` remains consistently empty across every fire observed so far; not yet understood, not needed for anything built so far.

### Consequence

The Planner's core arithmetic is now trusted — the open work is entirely the profile/weighting layer on top, not the apportionment mechanism underneath it. **This output must not be wired to any Dispatcher/execution path until the cargo-profile refinement (current + recent + historical weighting, `IDEAS.md`) is built** — today's version would make real, harmful reassignment decisions on momentary zero-readings, live-demonstrated above, not just theorized. Next real steps: (1) confirm whether `targetEntity` reliably identifies a managed hub's own destinations, since that would make the event trigger genuinely scoped instead of global; (2) fold the now-confirmed `_lastMonth`/`_lastYear` per-cargo-type history (Decision 28) into the Planner's weighting before this is trusted for anything beyond a read-only report.

## Decision 30 — Cargo-profile floor (RECENT/HISTORICAL tiers) live-confirmed fixing Decision 29's exact problem

### Decision

Added activity-tier classification to `planner.lua`: a candidate line is `ACTIVE` (real waiting > 0), `RECENT` (0 waiting, but real `itemsUnloaded._lastMonth` activity at its destination — `stations.getRecentUnloadedTotal`, new), `HISTORICAL` (0 waiting, no recent activity, but real all-time `itemsUnloaded` — already-existing `stations.getItemTotals`), or `IRRELEVANT` (none of the above). RECENT gets a +2 floor bonus, HISTORICAL +1, on top of the base 1-vehicle floor — deliberately a floor-only protection, not a share of the demand-weighted pool, to avoid mixing raw historical totals (which can run into the thousands) into a weighting scheme with no evidence-based scaling factor yet.

### Reason

Live-tested twice in one session (via the newly-self-service `EPOD_Get_Log.bat`, run directly rather than waiting on a manual paste). Both runs conserved exactly (targets summed to the real fleet size, 54, both times) and correctly classified: Alexander Road at 0 waiting was tagged `HISTORICAL` and protected at floor 2 (target 2, delta -21) instead of collapsing to the bare 1 Decision 29 observed (delta -22) — the exact problem this was built to fix, now demonstrated fixed. Park Avenue at 0 waiting similarly landed at `HISTORICAL`, floor 2, exactly matching its real current count (delta 0). Separately, Queens Road's `ACTIVE`-tier weighted share responded correctly to real change between the two runs (waiting 1→10, delta improved -13→-11), confirming the pool-sharing side still works correctly alongside the new floor logic.

**Known rough edge, not fixed yet**: a line showing `waiting=1` (technically real, but negligible next to a hub total in the hundreds) is classified `ACTIVE` and gets only the plain floor, no RECENT/HISTORICAL boost — slightly *less* protected than a same-history destination sitting at a clean 0. Not the bug this was built to fix (that was specifically the zero-waiting snapshot case, now fixed and demonstrated), but a real boundary quirk worth a note rather than silently ignoring.

### Consequence

The floor mechanism works as designed and is live-demonstrated fixing the exact failure mode Decision 29 found — but the protection is deliberately modest (1-2 extra vehicles), not a full restoration of a quiet line's prior fleet. That's intentional: this project has no evidence yet for a larger, more confident number, and Decision 29's own caution against fabricating weights applies here too. `EPOD_Get_Log.bat` can now be run directly rather than relying on the player to paste log output manually, speeding up this kind of live-test loop going forward.

## Decision 31 — Opportunistic Dispatcher built (`dispatcher.lua`), retiring the old dead single-line reverse-test code it replaced

### Decision

Rewrote `dispatcher.lua` entirely. **Removed**: `M.rank`/`M.getNextDestination`/`M.buildDispatchPlan`/`M.printReport`/`M.printDispatchPlan`/`M.executeDispatchPlan` — a "REVERSE DESTINATION TEST" that ranked destinations *within one line* and used `reverseVehicle` to redirect a Park-stopped vehicle toward the highest-demand one. Confirmed via a full-repo search that nothing required this file from anywhere — genuinely dead code, not merely unused, and architecturally obsolete besides: it predates Stage 1 (Decisions 19–23), which now splits every multi-destination line into one managed line per real destination, so "rank destinations within one line" no longer describes anything that exists. `config.LIVE_DISPATCH_ENABLED`, the flag that gated the old `executeDispatchPlan`, was removed alongside it for the same reason.

**Built**: `M.applyPlan(hubStationGroup, onComplete)` — the real Opportunistic Dispatcher, applying `planner.lua`'s target allocation by moving real vehicles between managed lines, capped at `MAX_MOVES_PER_RUN` (5) per call. Wired to a new DEBUG "Apply Fleet Plan" button — manually triggered only, same staged rollout as every earlier stage.

### Reason

This is the first code in the mod that moves a vehicle based on the Planner's dynamic demand read rather than a fixed, deterministic rule (Stage 1–4's split/balance logic always does the same well-tested thing; this decides differently depending on what demand looks like right now). Two safety rules were treated as non-negotiable before writing it, both already flagged as prerequisites in earlier decisions:

- **Only moves a confirmed-empty vehicle** (`vehicles.isVehicleEmpty(id) == true`) — same Bug A avoidance Stage 2/3 already use, reused rather than re-derived.
- **Only moves a vehicle compatible with the destination's real cargo history** (Decision 27's `isCompatibleWithCargoType`) — PROGRESS.md already stated the Planner's output "must not be wired to any Dispatcher" without this.

**A real risk was caught and avoided while building the compatibility check, not after**: the obvious source for "what cargo does this destination need" was `demand.scan()`'s per-destination `cargoTypes` table — but that field comes from `api.engine.getComponent(entity, SIM_CARGO).cargoType`, a low-level API never cross-checked against `vehicles.lua`'s `allCapacities` keys (which come from `game.interface.getEntity`, a different, higher-level API). Silently mixing the two into one compatibility check risked every single check quietly returning false — the Dispatcher would appear to run, log nothing wrong, and simply never move any vehicle, with no obvious cause. Instead, added `stations.getUnloadedCargoTypes` (the real cargo type names present in `itemsUnloaded`, e.g. `FOOD`, `FUEL` — same `game.interface.getEntity` source as vehicle capacities, confirmed matching representation) and gate against that instead. This is also arguably the better signal anyway — real historical cargo mix at the destination, not an instantaneous snapshot, consistent with Decisions 29/30's whole point.

### Consequence

**Live-tested, first run clean.** One click of "Apply Fleet Plan" against Hendon East moved exactly 5 vehicles, all `● Hendon East ↔ Alexander Road` → `● Hendon East ↔ The Grove` — every move logged `SET MANUAL DEPARTURE RESULT: true` → `SET LINE RESULT: true` → release `true`, zero failures, zero "no empty/compatible vehicle" skips. The largest-surplus-to-largest-deficit pairing picked exactly what the last Planner reading implied it should (Alexander Road was the biggest surplus, The Grove the biggest deficit), then stopped cleanly at `MAX_MOVES_PER_RUN` rather than continuing to drain Alexander Road in one click — the cap and the sort both behaved as designed. Only one pairing has been observed so far (one surplus, one deficit); the fallback path (surplus line has no empty/compatible candidate, move on to the next surplus) has not yet been exercised live. Still deliberately NOT wired to the Auto Redistribute toggle, a timer, or the delivery event — manual button only, matching every earlier stage's rollout discipline. `MAX_MOVES_PER_RUN = 5` remains a deliberately conservative cap, not yet tuned up now that one run is proven safe.

## Decision 32 — Real flapping caught live; added a per-vehicle cooldown to the Dispatcher

### Decision

Added `COOLDOWN_RUNS` (3) to `dispatcher.lua`: a vehicle just moved by `M.applyPlan` cannot be selected as a move candidate again for the next 3 calls, tracked with a simple in-memory `runCounter`/`lastMovedRun[vehicleId]` — not a new time source (`os.time`/`os.clock` are untested in this sandbox and deliberately not reached for), just a count of `M.applyPlan` invocations. Resets on save reload, an accepted cost for a short-term hysteresis guard rather than durable state.

### Reason

Requested three manual "Apply Fleet Plan" runs to gather more live data before wiring automation (the agreed next step). Cross-referencing the vehicle IDs moved across all 5 runs so far found real flapping: **6 of ~20 total moves were a vehicle being reassigned again shortly after its previous reassignment**, and **3 of those (116791, 135325, 117443) were a full round trip** — Alexander Road → The Grove in run 2, then The Grove → Alexander Road in run 5, right back where they started, two real journeys for zero net benefit. Root cause: the Planner recomputes entirely from current instantaneous demand every run, and demand is genuinely volatile — already observed swinging a destination's waiting cargo from 0 to 10+ between two reads minutes apart (Decision 30) — so a fresh computation can legitimately reverse its own recent decision.

This directly confirms `IDEAS.md`'s "Terminal Assignment Stability" entry, previously honest that it had "no evidence this is a real problem rather than a hypothetical one." It now has evidence, one layer up (fleet count between lines, not terminal choice within one).

### Consequence

**Fully live-tested, including expiry.** The first 3-run sample showed zero repeated vehicle IDs (consistent, but the cooldown's expiry specifically unobserved). A later 5-run sample confirmed expiry directly: vehicles 139237/139398, moved in run 1, became eligible again exactly in run 4 (gap 3, matching `COOLDOWN_RUNS`) and were picked for a new reassignment — the cooldown releasing exactly on schedule, not a bug. `COOLDOWN_RUNS = 3` remains a first guess in terms of whether it's the *right* number, not tuned against how long a vehicle actually takes to settle — but the mechanism itself now works exactly as coded. This was the right thing to catch and fix *before* Not Started #4's remaining step (wiring the Dispatcher to run automatically) — an automatic trigger firing more often than manual clicks would have made this worse, not better, shuffling vehicles continuously instead of letting them settle.

That first 3-run sample also surfaced a second, related problem — see Decision 33.

## Decision 33 — Whole-line direction flapping caught live (different trucks, same waste); added a per-line direction cooldown

### Decision

Added a second, independent hysteresis guard to `dispatcher.lua`: a managed line that was classified `surplus` (gave vehicles away) cannot be classified `deficit` (receive vehicles) again — or vice versa — for `LINE_DIRECTION_COOLDOWN_RUNS` (3) more `M.applyPlan` calls. Recorded every run a line has a nonzero delta, whether or not `MAX_MOVES_PER_RUN` actually let a move happen for it. A blocked line is excluded entirely from that run's deficit/surplus queue, not forced into either direction. Same in-memory, `runCounter`-based mechanism as Decision 32's per-vehicle cooldown — no new time source.

### Reason

The 3-run sample gathered to test Decision 32's per-vehicle cooldown (which showed zero repeated vehicle IDs, consistent with working) revealed a second, related problem the vehicle cooldown does not and cannot catch:

```
Run 1: Queens Road    -> Alexander Road  (5 vehicles)
Run 2: Alexander Road -> Queens Road     (5 different vehicles)
Run 3: Alexander Road -> Queens Road     (5 more different vehicles)
```

No single vehicle repeated — each run drew from a large enough pool of untouched vehicles that the per-vehicle cooldown never triggered — but the hub-level correction reversed itself one run later anyway, using different trucks each time. Same underlying waste as Decision 32's finding (real travel spent undoing a correction just made), just invisible to a vehicle-ID-based check. Root cause is the same as Decision 32's: demand read fresh every run is volatile enough to legitimately disagree with itself a few minutes later.

### Consequence

**Fully live-confirmed, including the boundary.** A reload plus 5 more runs produced repeated real blocks (`"...but was in deficit too recently -- skipping"` etc. on multiple lines across runs 2-5) AND two clean expiry examples landing exactly on the `< 3` boundary: The Grove, blocked from flipping to surplus in runs 2-3 (gap 1, gap 2), was correctly allowed to reverse in run 4 (gap exactly 3); Queens Road, blocked in run 3 (gap 1), was correctly allowed to reverse in run 5 (gap exactly 3). Decision 32's per-vehicle cooldown expired correctly in the same run too — vehicles 139237/139398 (moved Queens→Grove in run 1) became eligible again in run 4 (gap exactly 3) and were picked for Grove→Alexander, not a bug, the cooldown releasing exactly on schedule. Both guards now trusted: block when they should, release exactly when they should. Ready to move on to Not Started #4's remaining step — wiring the Dispatcher to the Auto Redistribute toggle + delivery event instead of the manual button.

## Decision 34 — Dispatcher wired to run automatically: Auto Redistribute toggle + delivery-event material-change threshold

### Decision

`attemptAutoDispatch()` (new, `epod_truck_distribution.lua`) is called from `handleDeliveryEvent` every `AUTO_DISPATCH_DELIVERY_THRESHOLD` (50) real `OnToArriveAtDestination` fires. It checks `settings.get("autoRedistribute")` (the toggle built and left deliberately unwired two nights ago) and `distributionState.selectedStationGroupId`, and if both are set, calls `dispatcher.applyPlan` against the currently selected hub — the same function the manual "Apply Fleet Plan" button already calls, both coexisting. The toggle's label dropped its "(DEBUG, not wired yet)" qualifier now that it's real.

### Reason

This is the last piece of PROGRESS.md's Not Started #4. The threshold is deliberately a simple **global** delivery count, not scoped to the selected hub's own deliveries specifically — Decision 29 already flagged that whether a delivery event's `targetEntity` reliably identifies a managed hub's own destinations is unconfirmed, and this shouldn't wait on that research being resolved first. Using the already-proven raw fire count (Decision 28: 500-1300+ per session) as a rough "enough activity has passed" clock is an honest, if crude, stand-in — a real per-hub material-change threshold is a future refinement once `targetEntity` scoping is proven, not a blocker for a first working version.

`AUTO_DISPATCH_DELIVERY_THRESHOLD = 50` is a first guess, not tuned — needs live observation of how often it actually fires relative to real demand changes.

### Consequence

**Not yet live-tested.** This is the first time anything in the mod moves a vehicle without a direct player click — everything before this (Split, Assign & Balance, the manual "Apply Fleet Plan") required a button press. It inherits every safety property already live-confirmed in the Dispatcher (empty-only, cargo-compatible, per-vehicle cooldown, per-line direction cooldown — Decisions 31/32/33), so this is the payoff of that testing work, not a leap past it. Still bounded the same way manual runs are (`MAX_MOVES_PER_RUN = 5` per trigger). Needs: a reload, turning the toggle ON, selecting a hub, and watching real gameplay to confirm it actually fires around the expected delivery count and behaves the same as the manual runs already proven safe.

## Decision 35 — Auto-dispatch never fired: two layers of the same multi-instance problem (Decision 24's class of bug), both fixed

### Decision

**Layer 1 — which hub to act on.** `attemptAutoDispatch` no longer reads `distributionState.selectedStationGroupId`. Instead, `handleAutoRedistributeToggleButtonClick` persists which hub is being auto-managed (`settings.get/set("autoDispatchHubStationGroupId")`, a new numeric setting) at the exact moment the toggle is switched ON, and `attemptAutoDispatch` reads that persisted value instead.

**Layer 2 — `settings.lua`/`managed_registry.lua` themselves.** Both modules previously loaded their persisted state once, lazily, and cached it in a module-level `state` table for the rest of the script instance's life (`ensureLoaded()`). Removed entirely: every `settings.get`/`settings.set` and every `managed_registry.isManaged`/`register`/`unregister` now calls `loadStateFromDisk()` fresh, every single call. `settings.lua`'s file format was also generalized to store numbers as well as booleans (`tonumber` fallback in `loadStateFromDisk`), needed for the numeric hub ID.

### Reason

Live testing (Decision 34's follow-up) found zero `AUTO DISPATCH` triggers across a 12,700+ delivery session — 250+ crossings of the 50-delivery threshold — despite the toggle confirmed ON and Hendon East confirmed selected in the panel for large stretches. A targeted diagnostic (logging `tostring(distributionState)`, the table's own memory identity, from both `attemptAutoDispatch` and `updateDistributionWindow`) proved Layer 1 directly: two different addresses (`000001A5DC593CF0` vs `000001A5DC6B1EF0`) — two separate script instances, the same class of bug that forced `data()`'s `save`/`load` hooks to be abandoned (Decision 24).

Layer 1's fix alone was then tested live and **still** produced zero triggers across another 7800+ deliveries (150+ threshold crossings) after the hub was confirmed captured via a logged `AUTO REDISTRIBUTE: now managing hub 126300` line. That forced a second look, and exposed Layer 2: `settings.lua`'s `ensureLoaded()` only loads once per instance. The `handleEvent` instance's very first `settings.get()` call happened at delivery #50 of the fresh session — *before* the toggle was ever clicked (which happened around delivery #200) — so it cached `{autoRedistribute = true}` with no `autoDispatchHubStationGroupId` key at all, and never looked at the file again for the rest of its life. The GUI instance's later write to disk was real and correct; the `handleEvent` instance's permanently-stale in-memory snapshot simply never saw it. `managed_registry.lua` had the exact same pattern — and its own header comment explicitly (and, it turns out, incorrectly) claimed a module-level cache was safe here "in a way it wasn't for the save/load proof-of-concept." That claim went untested until this session exposed the identical bug in its sibling module.

### Consequence

Both fixes are genuine improvements, not just patches. Layer 1: auto-dispatch now keeps running for its designated hub even while the player is elsewhere on the map, rather than requiring the panel to stay focused on it — closer to what "automatic" should mean. Trade-off: the target hub is fixed at toggle-ON time, not continuously re-synced to the current selection — changing it requires toggling off/on again with the new hub selected. Fine for today's single-hub scope (PROGRESS.md Not Started #6). Layer 2: closes a latent, previously-unproven risk in `managed_registry.lua` — a line registered by one instance (e.g. a fresh Stage 1 split) could have been invisible to `isManaged()` calls from a different instance for the rest of that instance's life. **Not yet live-tested** — needs a reload and a real `AUTO DISPATCH` line to finally confirm both layers together.

**Broader lesson, worth restating plainly**: no module-level Lua state should ever be assumed to persist meaningfully across a call boundary in this codebase unless it's read fresh from disk every time. "We already proved file I/O works" (Decision 24) is not the same claim as "we cached it correctly" — this session had to relearn that distinction the hard way, twice, in two different modules, before it stuck.

## Decision 36 — Real live incident: the game hung and had to be force-closed. Root cause was two compounding automation bugs, both fixed

### What happened

Shortly after Decision 35's fixes went live, the player reported the game "acting paused yet running full speed," with audio cutting in and out. They closed the game as a precaution; on shutdown it went unresponsive and had to be force-closed. No save corruption was reported, but this was a genuine, serious incident — not a cosmetic bug — and is recorded honestly rather than glossed over, consistent with this project's evidence-first discipline applying to failures as much as successes.

### Root cause (two compounding factors, not one)

1. **`AUTO_DISPATCH_DELIVERY_THRESHOLD = 50` was far too low.** The player had deliberately stacked up extra deliveries at the hub to stress-test the automatic Dispatcher (Decision 34). Real observed delivery rates during that kind of burst can exceed 50 within a fraction of a second — meaning `attemptAutoDispatch` (and the full `planner.calculateTargetAllocation` + `dispatcher.applyPlan` cycle inside it) could trigger many times per second instead of the intended "occasional automatic check-in."

2. **`dispatcher.lua` had no reentrancy guard.** Each vehicle move is 3 sequential async API calls (`setManualDeparture` → `setLine` → `setManualDeparture`). Nothing stopped a new `M.applyPlan` call from starting while a previous call's async chain was still resolving. Combined with factor 1, this meant multiple overlapping `applyPlan` runs could pile up real, synchronous, in-flight command sequences faster than the engine could resolve them — a genuine, unbounded (in the observed session) backlog of pending work, not just "running a bit more than intended."

Neither factor alone was catastrophic; together, under real stress-test conditions, they were.

### Decision (the fix)

1. **`AUTO_DISPATCH_DELIVERY_THRESHOLD` raised from 50 to 500** — still a first guess, not precisely tuned, but a far safer starting point given real observed burst rates.
2. **`dispatcher.lua` gained a hard reentrancy guard** (`isApplyPlanRunning`, module-level): if `M.applyPlan` is called while a previous call's async chain hasn't finished, the new call is refused outright (logged, `onComplete(0)`) rather than allowed to overlap. This is the structural fix — it makes the system safe *regardless* of how the threshold is tuned, or of any other future trigger (a timer, a different event) that might call `applyPlan` more often than expected. The threshold change alone would have reduced the *frequency* of the problem; the reentrancy guard is what actually makes overlap impossible.

### Consequence

This is the clearest evidence yet in this project that a value moving real vehicles automatically needs a hard structural safety net, not just a "seems reasonable" tuning constant — the same lesson `IDEAS.md`'s own "Material Change Threshold" and "Terminal Assignment Stability" entries already gestured at in the abstract, now backed by a real incident report rather than a hypothetical. **Not yet live-tested** — needs a reload and real play (ideally including another deliberate stress-test burst, now that the reentrancy guard should make that survivable) to confirm the fix holds. Given the severity, worth watching closely on the first few automatic triggers rather than walking away from the game.

## Decision 37 — Second, more severe live incident: unbounded synchronous retry loop, apparently crashing the game repeatedly

### What happened

After Decision 36's fixes (threshold raised, reentrancy guard added), the player reported the game "acting paused yet running full speed" with audio stutter again — this time starting almost instantly on load, independent of the Auto Redistribute toggle and independent of whether the Truck Distribution panel was open or selected at all. Pulling the live log while it was happening showed the real cause immediately: `dispatcher.lua` repeatedly logging `DISPATCH: could not hold vehicle 139417 -- skipped.` followed immediately by `DISPATCH: moving vehicle 139417 from ● Hendon East ↔ Alexander Road -> ● Hendon East ↔ The Grove` — the exact same vehicle, over and over, with no gap. Separately, the player found their `crash_dump` folder filling with hundreds of ~316KB `.dmp` files, all timestamped within the same minute — evidence the game was not merely stalling but apparently crashing and being regenerated repeatedly at high frequency. The player force-closed the game as a precaution; no save corruption was reported.

### Root cause

`dispatcher.lua`'s failure-handling path had a real bug: when a vehicle's `setManualDeparture(true, ...)` command failed, `moveOneVehicle`'s callback fired with `success = false`, and `processMoveNext` simply called itself again with **no change to which vehicle would be picked next**. `findMovableVehicle` re-scans `vehicles.getVehiclesForLine(surplusLineId)` in the same order every time and returns the first eligible candidate — since nothing marked the just-failed vehicle as ineligible, it was handed back out immediately, failed again, and so on. `MAX_MOVES_PER_RUN` never caught this because it only counts *successful* moves (`context.movesMade`), which never incremented. This was synchronous Lua recursion (the failure path fires its callback immediately, not via a delayed engine callback), so nothing ever yielded back to the renderer/audio between iterations — a genuine unbounded tight loop, not just "running a bit too often" like Decision 36's issue.

**Confirmed directly from TF2's own native engine log** (`stdout.txt`, not just the mod's own filtered `EPOD-LOG.txt` extract): every single failure was the same native C++ assertion, logged immediately before each `SET MANUAL DEPARTURE SEND ERROR`:

```
urban_games/train_fever/src/Lib/ecs/Engine.cpp:490: ecs::Engine::BeginModification(): Assertion `!m_betweenChanges' failed.
__CRASHDB_DUMP__ <uuid>
```

`grep -c "__CRASHDB_DUMP__"` on the raw log found **1,397 occurrences** in one unbroken burst, all from a single `AUTO DISPATCH` trigger (only one `material-change threshold reached` line exists in the entire captured session — the loop never returned control long enough for a second delivery-count milestone to even log). Notably, **the very first attempt on vehicle 139417 hit the assertion too**, before any retry logic ran — meaning the underlying trigger (the engine already being "between changes" for that entity at the exact moment `setVehicleManualDeparture` tried to begin its own modification) is a real, if rare, timing collision, not something caused by retrying. What turned one isolated collision into a catastrophic incident was purely the missing exclusion: nothing stopped the same vehicle being handed straight back out and retried instantly, so one rare timing collision became 1,397 real crash-dump writes to disk in well under a minute. The root cause of *why* that one collision happened in the first place remains unconfirmed and isn't chased further here — the fix doesn't need to know why a failure happens, only guarantee a failure is never retried blindly.

### Decision (the fix)

1. **`findMovableVehicle` now takes and respects `excludedVehicleIds`.** Any vehicle whose `moveOneVehicle` call fails (hold or `setLine`) is added to this set and will never be selected again for the rest of that `M.applyPlan` call. This is the actual fix — a failure now permanently removes that vehicle from consideration this run, rather than being retried.
2. **`MAX_ATTEMPTS_PER_RUN` (20) added as a hard backstop**, counting every attempt (success or failure), independent of `MAX_MOVES_PER_RUN`'s success-only count. Even in some future failure mode this fix doesn't anticipate, total attempts per run are now bounded.

### Consequence

This is the most serious incident logged in this project to date — worse than Decision 36's, because it appears to have caused actual repeated crashes, not just unresponsiveness. Two real defensive layers now exist in `dispatcher.lua` (exclusion-on-failure, hard attempt cap) on top of Decision 36's reentrancy guard and Decisions 32/33's cooldowns — the Dispatcher has accumulated meaningful real-world hardening through this testing, each layer added in direct response to an actual observed failure, not speculative "just in case" code. **Not yet live-tested.** Given the severity, testing this again warrants real caution: watch the log closely on the very first automatic or manual trigger after reload rather than leaving it running unattended.

## Decision 38 — Decision 37's fix confirmed working (no runaway), but revealed a systemic failure pattern; added a fast consecutive-failure bailout

### What happened

After Decision 37's fix, the player reloaded, turned Auto Redistribute on, and reported "having moments" of freezing — clearly less severe than the earlier incidents, but still real. The log confirmed the fix is working exactly as designed: two separate `AUTO DISPATCH` runs each correctly logged `DISPATCH: reached MAX_ATTEMPTS_PER_RUN (20) -- stopping for this run (repeated failures)` and completed with `0 vehicle(s) moved` — no runaway, no unbounded recursion, no repeat of Decision 37's 1,397-dump storm.

But the pattern underneath was new and worth taking seriously: **every single vehicle attempted failed** — roughly 19-20 attempts per run, 0 successes, across two runs and two different source lines (Alexander Road, then Queens Road). This is not one rare per-vehicle timing collision (Decision 37's confirmed cause) — it's the whole hub, consistently, both times. Each bounded-but-still-~20-attempt burst was apparently enough to cause a brief, real hitch every time the delivery threshold fired.

### Decision (the fix)

1. **`MAX_ATTEMPTS_PER_RUN` lowered from 20 to 8** — still a backstop, just a smaller one, given a full run of failures is evidently costly enough to notice even bounded.
2. **New: `MAX_CONSECUTIVE_FAILURES` (3).** If 3 attempts in a row fail with no intervening success, the whole run bails out immediately rather than continuing to grind toward the attempt cap. This targets the specific pattern just observed directly: if failures are systemic, trying more vehicles is very likely to keep failing too, so exiting fast keeps each burst small. A run with occasional, scattered failures among real successes is unaffected — this only counts a streak, not a running total.

### Consequence

**Not yet live-tested.** The underlying question — why is *every* vehicle at this hub currently failing to hold, not just an occasional one — remains open and is a bigger, more interesting question than this fix answers. Leading theory, not yet confirmed: this save has been deliberately stress-tested with very high vehicle counts and delivery volume (100+ vehicles, thousands of deliveries per session), and the underlying `ecs::Engine::BeginModification` "between changes" state (Decision 37) may simply be common, not rare, when the simulation is under this much concurrent load — meaning the collision rate scales with how hard the save is being pushed, not a fixed per-vehicle defect. If that's right, this may partly resolve itself under more normal (less deliberately extreme) play, and is worth re-testing under lighter load before concluding anything further needs fixing here.

## Decision 39 — Root cause of the systemic failures found: never call the Dispatcher from inside `handleEvent`. Deferred execution to `guiUpdate`

### Decision

`attemptAutoDispatch` (called from `handleDeliveryEvent`) no longer calls `dispatcher.applyPlan` at all — it only sets a persisted flag, `settings.set("autoDispatchPending", true)`. A new function, `pollAutoDispatchPending`, runs from `guiUpdate` (throttled independently of station selection, `AUTO_DISPATCH_POLL_INTERVAL = 120`) and performs the actual `dispatcher.applyPlan` call when the flag is set.

### Reason

Decision 38's tighter failure handling worked as designed, but the underlying question — why does *every* automatic attempt fail — needed answering. A direct, controlled comparison in the live log gave a conclusive answer: a manual "Apply Fleet Plan" click at one point in the session succeeded 5/5, another manual click later succeeded 5/5 again (10/10 total) — while roughly 15 consecutive automatic triggers in between failed 100% of the time (~45/45 failed attempts). This is not a rare, random collision (Decision 37's original framing) — it's deterministic based on *where the command is issued from*.

`handleEvent` fires from inside the game engine's own delivery-processing callback — the engine is actively mid-modification when `OnToArriveAtDestination` fires. Issuing a real `api.cmd.make.*` + `sendCommand` call synchronously from inside that same callback hits the engine while it's still "between changes" from the delivery that triggered the callback in the first place — exactly the `ecs::Engine::BeginModification` assertion confirmed in Decision 37. A manual button click happens from ordinary player input, never from inside that callback, so it was never affected — which is exactly why hours of earlier manual testing (Decisions 31-33) never once hit this.

**A second, previously-unnoticed problem surfaced from the same log evidence**: the manual click's own `APPLY FLEET PLAN` run counter read "(run 1)" then "(run 2)" — completely disconnected from the automatic triggers' counter, which was independently up to "(run 15)" at the same point in real time. `dispatcher.lua`'s module-level state (`runCounter`, `lastMovedRun`, `lastLineDirection`, `isApplyPlanRunning`) is subject to the exact same multi-instance problem as `settings.lua`/`managed_registry.lua` (Decision 35) — the GUI instance and the `handleEvent` instance each have their own separate copy of `dispatcher.lua`'s module state. This means Decisions 32/33's cooldowns and Decision 36's reentrancy guard were never actually being shared between manual and automatic triggers — each instance was independently tracking its own view of "what was recently moved."

### Consequence

Deferring all real `dispatcher.applyPlan` calls to run from `guiUpdate` fixes both problems in one change, not two separate fixes: (1) the engine-modification call context is now the same one manual clicks already proved safe, and (2) since manual clicks *also* run from `guiUpdate`'s script instance, every real dispatch call now shares the same `runCounter`/cooldown/reentrancy state regardless of trigger source — the cooldowns finally mean what they were always supposed to mean.

**Live-confirmed, completely clean.** 14 automatic dispatch runs observed after reload — zero failures across all of them, real successful moves throughout (`DISPATCH: vehicle X -> ...: true`, runs of 5, 3, 2, and 1 vehicle moved), several runs correctly completing with 0 moves via `DISPATCH COMPLETE` (no deficit needing filling, not a failure). Not one `could not hold vehicle` line anywhere. The pauses the player had been feeling on every automatic trigger were gone in the same session. This closes the automatic-dispatch incident saga (Decisions 36-39) — the actual triggering cause was avoided, not just bounded.

## Decision 40 — Threshold raised again (500→5000): real dispatch cycles were firing too often once they started succeeding

### What happened

After Decision 39's fix confirmed clean (14 successful automatic runs, zero failures), the player reported a small, regular pause roughly every second, with trucks not running smoothly. Checking the log's delivery-event milestones showed this save's delivery rate is extreme — 17,800+ real deliveries logged within one session — meaning the 500-delivery threshold was being crossed every few seconds, not every minute as originally intended.

### Reason

Decisions 37/38's failure-path was cheap (a handful of failed hold attempts, quickly excluded and bailed out). Decision 39 made dispatch actually *succeed* — which means real work: up to 5 vehicles per run, each a 3-step async command chain (hold → setLine → release). Doing that real work every few seconds, indefinitely, is a genuine small recurring cost — likely the actual source of the "every second" pause, distinct from every previous incident in this saga (which were all about failures, not the cost of success).

### Decision

`AUTO_DISPATCH_DELIVERY_THRESHOLD` raised from 500 to 5000 — an order of magnitude, still an untuned first guess given no reliable way yet to measure this save's exact deliveries-per-second rate. The right long-term fix remains what Decision 34 already flagged: a real per-hub delivery count (only counting deliveries that actually land at the managed hub, via the delivery event's `targetEntity`) rather than a global, game-wide count — that's gated on confirming `targetEntity` reliably identifies a hub's own destinations (still open, Decision 29). This is a stopgap, not the final answer.

### Consequence

**Not yet live-tested.** Worth deciding empirically rather than guessing further: if 5000 still feels too frequent, the number should keep climbing rather than assuming a fix is needed elsewhere. This is a tuning question, not a bug — unlike every other decision in the 36-39 range, nothing here was broken, the toggle is just working exactly as often as told to.

## Decision 41 — Automatic new-line detection and adoption (`line_adopter.lua`)

### What happened

Tonight's live testing proved the manual adoption workaround twice: renaming a pre-existing unmanaged line ("Grain") and a brand-new player-created line ("Hendon East - Main Street") to carry the "● " prefix by hand caused `managed_registry.migrateAndValidate()` to pick each one up on its next check, after which the Planner/Dispatcher immediately and correctly folded it into the shared fleet (5 vehicles pulled onto Main Street, drained proportionally from Grain's surplus). The player then proposed removing the manual rename step entirely: detect a new line touching the hub, adopt it automatically, and let it join the network as demand grows — explicitly matching their original stated vision for the mod ("the only thing the player does is add more trucks and add new stops").

### Reason

Scope decision, player-confirmed: for this first version, ANY road/truck line found touching the hub (via `vehicles.getManagedLinesForStation`, the same topological check the panel display already uses) that isn't yet in the persistent registry gets swept in automatically, with no opt-out yet. A per-line "leave this alone" escape hatch — a toggle, or a confirmation popup ("New line detected at Hendon, want this to be Auto managed?") — was explicitly deferred to a later pass, not built now.

### Decision

New module `line_adopter.lua`: `M.detectAndAdopt(hubStationGroup, onComplete)` scans lines touching the hub, filters to ones not already `managed_registry.isManaged()`, and for each one attempts `api.cmd.make.setName` to rename it to match the hub's existing convention (`line_splitter.lua`'s "● <hub> ↔ <destination>"), then calls `managed_registry.register()` regardless of whether the rename succeeded — the persistent registry, not the name, has been the real authority since Decision 22/26, so adoption does not depend on the cosmetic rename working.

Wired into `epod_truck_distribution.lua` as `pollNewLineAdoption()`, called from `guiUpdate()` right alongside `pollAutoDispatchPending()` — never from `handleEvent`, per Decision 39's deferred-execution rule, since this issues real `setName`/registration commands. Gated on the same `autoRedistribute` toggle and persisted hub designation as auto-dispatch, throttled independently (`AUTO_ADOPT_POLL_INTERVAL = 600`, looser than the dispatch poll since this is topological, not urgent), and reentrancy-guarded (`isLineAdoptionRunning`) the same way `dispatcher.applyPlan` is, since the adoption chain is itself asynchronous (setName → sendCommand → register, one candidate at a time).

### Consequence

**Not yet live-tested — two real unknowns flagged, not assumed:**

1. `api.cmd.make.setName` is live-confirmed on a VEHICLE entity (`fleet_naming.lua`) but has never been tried against a LINE entity — every line so far got its name baked in at `createLine` time, never renamed afterward. If it fails or no-ops on a LINE, the line still gets registered and managed correctly, just without the cosmetic "●" name matching the rest of the fleet.
2. `vehicles.getManagedLinesForStation` only returns lines it can classify as ROAD carrier, which requires at least one currently-assigned vehicle (see `classifyLineCarrier`) — a line created with zero vehicles won't be detected until the player assigns at least one. Matches the real workflow observed tonight (both Grain and Hendon East already had a vehicle before being noticed) and the panel display's existing constraint, not a new gap.

**Update — first real test, same session:** the player added a new line ("School Lane") with a truck, and it WAS auto-adopted (line count 7→8, confirmed live) — both open unknowns above are resolved: `setName` DOES work on a LINE entity, and a line with ≥1 vehicle is detected correctly. One real bug surfaced by this first live case: the adopted name came out as "● Hendon East ↔ Hendon East + School Lane" — `vehicles.getManagedLinesForStation`'s `destinations` list deliberately includes the hub's own stop (for return-direction demand display), which `buildAdoptedLineName` was joining in unfiltered. Fixed by filtering out any destination whose `stationGroup` matches the hub before building the name. Note this fix is not retroactive — the already-registered "School Lane" line keeps its buggy name until manually renamed in TF2's own line editor, since the auto-adopter only ever processes lines not yet in the registry.

## Decision 43 — Destination row wrap bug: waiting count split into its own fixed box

### What happened

Player screenshot, real bug: the Grain line's "-> Barrow-in-Furness Transfer | Waiting: 10" row wrapped ugly onto two lines, while the exact same destination showing "Waiting: 4" a few minutes later (same session, demand had just dropped) rendered fine on one line. Every other managed line's destination name is shorter and never showed this.

### Reason

`renderManagedLineRows` (`epod_truck_distribution.lua`) concatenated the destination name and the "| Waiting: N" suffix into one string rendered in a single fixed-width (`ROW_LABEL_WIDTH = 300`) text box. "Barrow-in-Furness Transfer" is the longest real destination name in the save; adding a 2-digit waiting count pushed the combined string just over the 300px wrap width, while a 1-digit count stayed just under it — a pure text-width bug, not a data bug (see Grain's math, confirmed correct, same conversation).

### Decision

Gave the waiting count its own small fixed-width text box (`WAITING_LABEL_WIDTH = 90`, new `waitingLabel` widget per row, same shared-row-pool pattern as `label`/`cargoIcons`/`cargoCounts`), the same treatment cargo counts already get next to their icons. `ROW_LABEL_WIDTH` reduced to 260 (destination name + arrow only, no longer carrying the suffix); `WINDOW_WIDTH` raised 560→610 to fit the new column. `destRow.label` now gets just `"    <arrow> <name>"`; `destRow.waitingLabel` gets `formatDestinationLabel`'s "Waiting: N" text separately. `clearRow` updated to blank the new widget too so it never leaks stale text onto a reused row.

### Consequence

**Not yet live-tested.** The exact pixel widths (260/90/610) are a first estimate extrapolated from the observed wrap point (~6.4px/char in this font: 300px held 47 characters without wrapping, 48 wrapped), not independently confirmed at these specific values — could still need tuning if a longer destination name than "Barrow-in-Furness Transfer" ever shows up, or if the font's real metrics differ from this estimate.

## Decision 42 — Stage 4 replaced: shared terminal pool via `alternativeTerminals` instead of a per-line dedicated-terminal lock

### What happened

The player shared a code snippet for `api.cmd.make.setLineStopAlternativeTerminals(lineId, stopIndex, allTerminalIds)` — a command never used anywhere in this codebase. `Line.Stop.alternativeTerminals` itself already existed (`lines.makeNativeStopCopy` copies it when duplicating a stop onto a freshly split line), but nothing had ever written it directly; it is a distinct field from `Line.Stop.terminal`, which is what the existing Stage 4 (Decision 22) writes to hard-lock one line to one terminal.

### Reason

Player-directed replacement, not an addition: rather than the mod computing which single terminal each managed line should get (demand-ranked, with a real stock-take of pre-existing occupancy — Decision 22's hard-won design, including the line-count-before-load tiebreak fix and the source-line-exclusion fix), give every managed line's hub stop the exact same pool of every real terminal at the hub and let TF2's own native vehicle terminal-selection logic balance load across them per trip. Simpler mechanism, and it removes an entire class of allocation bugs (the two Decision 22 fixes above no longer apply — there is nothing left to rank or stock-take once every line gets the same full pool).

### Decision

Rewrote `terminal_allocator.lua`'s `M.spreadLinesAcrossTerminals`: dropped `setLineHubTerminal` (the full `api.type.Line.new()` reconstruction + `api.cmd.make.updateLine` rewrite) and `stockTakeExistingLoad` entirely — no longer needed, since there's no per-line ranking or existing-occupancy accounting left to do. New body finds every managed ("● ") line touching the hub, builds `{0, 1, ..., terminalCount-1}` as a plain Lua array (matching the pasted snippet's own form, not a native vector type), and calls `api.cmd.make.setLineStopAlternativeTerminals(lineId, nativeStopIndex, allTerminalIds)` once per line — `nativeStopIndex` converted from the 1-based Lua `stops` array position the same way `vehicles.buildRouteMap`'s `routeIndex` already does (`hubStopIndex - 1`). `Line.Stop.terminal` itself is left untouched. Call site (`epod_truck_distribution.lua`'s "Split Into Lines & Organize Terminals" button) unchanged — same function signature, same manual-click call context, so Decision 39's rule about never issuing commands from `handleEvent` doesn't come into play here (this only ever runs from a player button click).

### Consequence

**Not yet live-tested — three real unknowns, not assumed:**

1. Whether `api.cmd.make.setLineStopAlternativeTerminals` exists at all in this TF2 version.
2. Whether it accepts a plain Lua array of terminal indices, or requires a native vector type instead (every call is `pcall`-wrapped and logs its own result either way, so a wrong type shows up as a clean logged error, not a crash).
3. Whether `Line.Stop.terminal` needs to already hold a valid in-range value for the alternatives to be considered at all, or whether the default (untouched) value is fine.

If this doesn't pan out, Decision 22's original demand-ranked single-terminal-lock design is the documented fallback (see `IDEAS.md`'s "Demand-Weighted Terminal Sharing" — kept there, marked superseded rather than deleted, specifically for this possibility) and is fully recoverable from git history.

## Decision 44 — Multi-hub support: per-hub enabled set replaces the single global toggle

### What happened

Player decided "playable by many" is the actual next goal for this mod (not just polish for one save), and picked multi-hub support as the first gap to close: every real player's network is likely to have more than one distribution centre, and the mod so far only ever auto-manages one hub game-wide (`settings.lua`'s single `autoRedistribute` boolean + single `autoDispatchHubStationGroupId` value, captured from whichever station happened to be selected the moment the toggle was clicked ON — turning it on while looking at a second hub would silently drop the first hub's automation with no warning).

### Reason

Auditing every hub-touching function first showed this was a narrower fix than it looked: `planner.calculateTargetAllocation`, `dispatcher.applyPlan`, `terminal_allocator.spreadLinesAcrossTerminals`, `line_adopter.detectAndAdopt`, and `fleet_naming.renameFleetToHubIdentity` were ALL already parameterized per hub from when they were first built — none of them assumed a single global hub. The only genuinely single-hub parts were the persistence layer (one stored ID) and dispatcher.lua's reentrancy guard (one shared boolean for every hub's run).

### Decision

New module `hub_registry.lua`, same proven io.open/fresh-read pattern as `managed_registry.lua`: a real SET of hub stationGroup IDs, each independently `enable`d/`disable`d, `isEnabled` checked per hub, `getEnabledHubs()` returning the full list. `settings.lua`'s `autoRedistribute` and `autoDispatchHubStationGroupId` keys are retired (not migrated — a stale leftover key from before this change just sits inert, same tolerance the project already extends to any unused settings data). The Auto Redistribute button now only ever toggles whichever hub is currently selected (`distributionState.selectedStationGroupId`), never rebinding a different hub's state; its label is refreshed both on click and on every `updateDistributionWindow()` panel refresh (keyed by whichever station is selected at the time), so switching between two hubs shows each one's own real ON/OFF state instead of a stale value.

`pollAutoDispatchPending` and `pollNewLineAdoption` (both `epod_truck_distribution.lua`) now walk `hub_registry.getEnabledHubs()` SEQUENTIALLY — one hub's `applyPlan`/`detectAndAdopt` call only starts after the previous hub's callback has actually fired, via the same one-at-a-time async-chain pattern already used everywhere else in this mod (`line_splitter.processNext`, `fleet_naming.processRenameNext`, `line_adopter.processAdoptNext`, `terminal_allocator.processCandidateNext`). Deliberately NOT firing every enabled hub's commands concurrently: dispatcher.lua's reentrancy guard (`applyPlanRunningByHub`, now a table keyed by hub instead of one shared boolean, since the Decision 36 scenario is about the SAME hub re-entering itself, not two disjoint hubs) makes concurrent-but-disjoint hubs LIKELY safe, but nothing has live-confirmed that overlapping command chains across different hubs are actually safe at the engine level — Decisions 37 and 38's incidents both came from exactly this kind of "should be fine" assumption, so this stays conservative for zero added cost (the whole poll already only runs once every `AUTO_ADOPT_POLL_INTERVAL`/`AUTO_DISPATCH_POLL_INTERVAL` frames).

The single-flag reentrancy guards for the two polls themselves (`isLineAdoptionRunning`) did NOT need to become per-hub, since hubs are only ever processed one after another within one poll cycle — the flag correctly means "a poll cycle is still working through its hub list," not anything tied to one specific hub.

### Consequence

**Not yet live-tested with a genuine second hub.** Everything here is designed from correctly reading the existing hub-parameterized functions, not from a live multi-hub run — needs a save with two real distribution hubs, both toggled ON, to confirm: the button correctly shows independent state per hub, both hubs' automation actually runs (sequentially, per poll cycle), and a manual click on one hub's "Apply Fleet Plan" while the other hub's automatic poll is mid-chain is not incorrectly refused (the actual scenario the per-hub reentrancy guard exists for).

## Decision 45 — Critical multi-hub scoping bug: `findDestinationStationGroup` never checked the line actually touches the hub

### What happened

Live multi-hub testing (Yarm East + Hendon East both enabled) showed Yarm's very first automatic dispatch run pull a vehicle off a genuine Yarm line and onto "Hendon East ↔ The Grove" — a line with zero physical connection to Yarm East. The log made it unambiguous: this wasn't the predicted "two hubs sharing one genuine bridging line" scenario, it was Yarm's planner treating a completely unrelated Hendon-only line as its own.

### Reason

`planner.lua`'s `findDestinationStationGroup(lineId, hubStationGroup)` returned the FIRST stop on a line whose stationGroup simply wasn't equal to `hubStationGroup` — it never checked that the line has a stop AT `hubStationGroup` in the first place. Checking "Hendon East ↔ The Grove" against Yarm's ID: the first stop, "Hendon East", already satisfies "not equal to Yarm's ID", so it got returned immediately as if it were a legitimate Yarm destination. Under a single hub this was invisible: every managed line touched that one hub by construction (either split from it or adopted because it touched it), so "the first non-matching stop" always happened to be the real destination — the function was never actually doing hub-scoping work, it just looked like it was. The instant a second hub existed, `collectManagedLineCandidates(yarmHub)` silently included every single managed line in the entire game, not just lines touching Yarm.

### Decision

Fixed: the function now walks every stop, requires finding one that actually EQUALS `hubStationGroup` (`touchesHub = true`) before returning any destination at all, and returns `nil` (correctly excluding the line as a candidate) if the hub is never found on the line's stop list.

### Consequence

**Live-confirmed as the fix, not yet re-tested end to end** — the player reloaded from a save just before this test to re-run it cleanly once the fix landed. This resets the earlier "hubs fighting over trucks" concern (Decision 44's open question) to genuinely unknown again: most of what looked like cross-hub conflict in the first test run was actually this bug, not real contention over an actual shared line. Worth re-observing with the fix in place before deciding whether the shared-bridging-line design question needs solving at all.

## Decision 46 — Second bug found same session: `SOURCE_LINE_NAME` hardcoded to Hendon East's original line name

### What happened

"Assign & Balance Fleet (DEBUG)" failed immediately on Yarm East with "FAILED: source line not found."

### Reason

`config.lua`'s `M.SOURCE_LINE_NAME = "Truck - CD - Hendon"` is a single hardcoded literal string — the name of Hendon East's own original combined line from early in this project. `fleet_allocator.redistributeSpareVehiclesByDemand`'s caller looks up the source line via `lines.findByName(config.SOURCE_LINE_NAME)`, which can only ever find that one specific name. Yarm East's original combined line was named "Line 6," so the lookup always returns nil for it (or for any hub that isn't Hendon East). This predates multi-hub entirely — a single-hub hardcoding assumption that simply never got exercised until a second hub existed to expose it.

### Decision

Fixed, same session. New module `source_line_registry.lua`, same file-I/O pattern as the others: `line_splitter.lua`'s `M.splitLineIntoDestinations` records `hubStationGroup -> lineInfo.id` at the moment it actually splits a genuine combined line (guarded by `#realDestinations > 1`, so an already-split single-destination child passing back through this same function on a re-run of the split button never overwrites the real record with itself). `handleAssignAndBalanceButtonClick` (`epod_truck_distribution.lua`) now reads this per-hub record instead of `lines.findByName(config.SOURCE_LINE_NAME)`. If no source line is recorded yet for a hub, it now fails with a clear message ("run Split Into Lines... first") instead of a silent "source line not found" that reads like the feature is just broken -- the player's own reasoning for prioritizing this fix ("the end user sees it do nothing, they would delete it at this stage").

Reasoning for automating this stage too, deliberately NOT done yet: this is the riskiest stage (real vehicle moves + deleting the original line), and per PROGRESS.md's "Bug A/B" it still carries an acknowledged open risk. Same staged discipline as everything else built successfully tonight -- prove it manually across more than one hub first, then consider folding it into the automatic chain adoption/terminal-pooling already use.

## Decision 47 — Auto-adoption now also re-applies the shared terminal pool

### What happened

Player asked directly: does Auto Redistribute organize terminals for a newly adopted line, or only reassign vehicles? Checked: `pollNewLineAdoption`/`pollAutoDispatchPending` never called `terminal_allocator.spreadLinesAcrossTerminals` — that only ever ran from the manual "Split Into Lines & Organize Terminals" button. A hands-off hub was still leaving newly-adopted lines on whatever terminal they already had.

### Decision

`processHubAdoptionNext` (`epod_truck_distribution.lua`) now calls `terminal_allocator.spreadLinesAcrossTerminals(hubStationGroupId, {}, ...)` immediately after a successful adoption, but ONLY when `adoptedCount > 0` for that hub this cycle — `spreadLinesAcrossTerminals` re-writes every managed line's `alternativeTerminals` unconditionally each time it's called, so gating it behind "something actually changed" avoids re-sending identical commands to every line, every poll cycle, for no reason. Same sequential one-hub-at-a-time chain as the rest of Decision 44's design (the terminal step completes before moving to the next hub).

### Consequence

**Not yet live-tested.**

## Decision 48 — Shared-line ownership: a line belongs to exactly one hub

### What happened

After Decision 45's fix, a re-test with three enabled hubs (Yarm East, Hendon East, Hendon Annex) showed the log clearly: a genuine bridging line touching all three of them ("Line 7", the real Yarm↔Hendon East↔Hendon Annex route) had its vehicle count pulled in different directions across nine consecutive automatic runs -- drained by Hendon East, drained further by Hendon Annex, blocked from being refilled by Yarm (the existing per-line direction cooldown correctly stopped an immediate reversal), drained again by Hendon Annex, partially given back, then refilled by Yarm. Three independent, locally-"correct" dispatchers competing for the same vehicles, never settling. This confirmed live exactly what had been flagged as an open design question a few exchanges earlier (Decision 44) -- not hypothetical anymore.

### Reason

Decision 45 fixed the bug where a hub's planner saw lines it had NO connection to at all. It deliberately did not address the separate, legitimate case: a line that genuinely touches more than one enabled hub is a real, valid candidate in EVERY one of those hubs' independent plans, and nothing coordinated between them. The direction-cooldown (Decision 33) only ever protects one line from reversing itself too fast -- it has no concept of "a DIFFERENT hub already decided something about this line moments ago."

### Decision

New module `line_ownership.lua`, same proven file-I/O pattern as `managed_registry.lua`/`hub_registry.lua`: every managed line belongs to exactly one hub. Ownership is set deterministically at the two moments it's actually known -- `line_splitter.lua` claims it for whichever hub a line was just split FOR, `line_adopter.lua` claims it for whichever hub's poll adopted it. For lines that predate this module entirely (Grain, School Lane, Line 6/7, anything managed before tonight) and so have no recorded owner: `line_ownership.isOwnedByOther` lazily claims it for whichever hub's planner run touches it first -- same self-healing-on-first-contact convention already used by `managed_registry.migrateAndValidate`.

`planner.lua`'s `collectManagedLineCandidates` now excludes a line if it's owned by a DIFFERENT hub, even though `findDestinationStationGroup` confirms it structurally touches this hub too. This is the actual fix for the tug-of-war: only the owning hub's plan will ever include the line as a dispatch candidate going forward.

### Consequence

**Not yet live-tested.** The lazy-claim fallback means which hub ends up owning a pre-existing shared line (like Line 7) is effectively whichever hub's automatic poll happens to run first after this fix lands -- not a deliberate choice, just first-come-first-served, same as every other "first touch wins" convention in this mod. A deliberate player-facing way to reassign a line's owner (or see which hub currently owns it) is a real follow-up, not built here -- this only stops the fighting, it doesn't yet expose the decision to the player.

## Decision 49 — "Dump All Managed Lines (DEBUG)" button

### What happened

Screenshots kept failing to upload during multi-hub testing (repeatedly too large). Player asked directly for a way to see the full network state straight from the log instead.

### Decision

New DEBUG button, same style as "Show Fleet Plan": logs every managed line game-wide (not scoped to the selected hub) with its current vehicle count, every real stop, which single hub owns it (Decision 48's `line_ownership.getOwner`), and which enabled hubs it structurally touches even if it isn't owned by them — the exact information needed to verify the ownership fix without a screenshot at all. Read-only, moves nothing.

### Consequence

**Not yet live-tested.**

## Decision 50 — Shared terminal pool reverted: `setLineStopAlternativeTerminals` confirmed not to exist

### What happened

Live multi-hub test: "Split Into Lines & Organize Terminals" on Yarm East ran Stage 4 against all 9 candidate lines and every single one failed identically: `STAGE 4 COMMAND ERROR (...): attempt to call a nil value`.

### Reason

"attempt to call a nil value" is Lua's error for calling something that isn't actually a function. `api.cmd.make.setLineStopAlternativeTerminals` -- the command Decision 42 was built around, sourced from a pasted snippet and explicitly flagged at the time as NOT YET LIVE-CONFIRMED -- does not exist in this TF2 version under this name. The flag turned out to matter: this is exactly the scenario Decision 42's own writeup called out as the fallback case ("If that command turns out not to exist/work as hoped, this section's original design... is the fallback to revert to").

### Decision

Reverted `terminal_allocator.lua` to the exact pre-Decision-42 version: the demand-ranked, `api.cmd.make.updateLine`-based single-terminal-lock design, including both of its own hard-won live fixes (the line-count-before-load tiebreak, the stock-take exclusion of the just-split source line). `IDEAS.md`'s "Demand-Weighted Terminal Sharing" section is once again the active design, not a superseded fallback.

### Consequence

Not yet re-tested on Yarm East specifically post-revert, but this exact code is the same code already proven working on Hendon East many times over, so confidence is high. The shared-pool idea itself isn't necessarily dead -- if a real alternative-terminals command surfaces under a different name later, it's worth trying again -- but it needs independent live confirmation before being trusted with anything, not a pasted snippet's word for it.

## Decision 51 — Split line naming: a name collision no longer silently drops a real destination

### What happened

Splitting Yarm East's combined line: `SPLIT SKIPPED (line already exists): ● Yarm East ↔ Park Lane`, and `SPLIT COMPLETE: 5 of 6 new lines created` -- one real destination never got split.

### Reason

The map has two genuinely different physical stations both named "Park Lane" (confirmed via the "Dump All Managed Lines" button, Decision 49: the combined line's stop list showed two different stationGroup IDs, both displaying as "Park Lane"). `line_splitter.lua` decided whether to skip a destination purely by whether a line with the intended name (`"● " .. hubName .. " ↔ " .. destination.name`) already existed -- it never checked whether that EXISTING line actually went to the SAME destination. The second "Park Lane" collided with the first's name and was silently skipped, meaning that whole real destination could never be served by the automated system at all, not a cosmetic issue.

### Decision

Before skipping on a name match, `line_splitter.lua` now reads the existing same-named line's own stops and checks whether `destination.stationGroup` is actually among them. Only skip if it genuinely is the same destination already split. If it's a different station that happens to share a display name, disambiguate by appending the destination's own stationGroup entity ID to the line name (e.g. "● Yarm East ↔ Park Lane (148559)") instead of dropping it.

### Consequence

**Not yet live-tested.** Also surfaced, not addressed here: splitting Line 7 (the real Yarm↔Hendon East↔Hendon Annex bridging line) from Yarm's own side created two brand-new lines ("● Yarm East ↔ Hendon East", "● Yarm East ↔ Hendon Annex") duplicating a connection Line 7 already provided. Not broken, just redundant capacity -- worth knowing about, not fixed tonight.

## Decision 52 — Assign & Balance Fleet fixed: it was racing against Auto Redistribute and losing

### What happened

Player observed Line 6 (Yarm's original combined line) get stuck: drained down toward empty by the ongoing dispatcher, then handed a vehicle right back, repeatedly, never reaching zero even after "Assign & Balance Fleet" ran. Log traced it exactly: Stage 2 logged `Empty split lines found: 1` and only ever retired ONE stop (Victoria Road) off Line 6, even though six other split lines existed. Stage 3 then logged `candidate: Line 6 | waiting=14 | currentVehicles=20` and `PLAN: Line 6 -> +1 vehicle(s)` -- followed by `REFUSED: source line still has 1 vehicle(s) -- not deleting a line that's still doing work.`

### Reason

`line_splitter.M.assignVehiclesAndRetireStops` (Stage 2) only ever considered a split line a candidate for stop-retirement if it was CURRENTLY EMPTY (`vehicleCount == 0`) -- written back when Stage 2 was the only mechanism that could ever put a vehicle on a freshly-split line, so "still empty" and "hasn't been handled yet" meant the same thing. That assumption broke the moment ongoing Auto Redistribute started running concurrently (the entire point of tonight's multi-hub work): it correctly treats every registered split line as a normal deficit candidate and routinely staffs it with its own floor vehicle before the player ever gets to click "Assign & Balance Fleet." By the time Stage 2 ran, six of Yarm's seven split lines already had 1-2 vehicles each (from ordinary automatic dispatch, not Stage 2) -- so Stage 2 saw them as "not empty" and never retired their stops from Line 6. Those un-retired stops kept generating real waiting demand, which BOTH the ongoing dispatcher and Stage 3's own redistribution correctly (from their own local view) kept feeding vehicles into. Line 6 could structurally never reach zero.

### Decision

Stage 2 now collects EVERY managed split line touching the hub as a candidate, regardless of current vehicle count. A line that already has vehicles (staffed by Auto Redistribute or a prior run, doesn't matter which) has its stop retired from the source line directly, skipping the now-unnecessary "assign a vehicle from the source" step; a genuinely empty line still gets the original assign-then-retire treatment. `removeStopFromSourceLine` was already idempotent (logs "nothing removed" and moves on if the stop is already gone), so calling it more broadly across repeated runs is safe.

### Consequence

**Not yet live-tested.** Re-running "Assign & Balance Fleet" on Yarm East now should retire ALL of Line 6's remaining real stops in one pass rather than just whichever happened to still be empty, letting its vehicle count actually drain toward zero and `deleteEmptySourceLine` finally succeed.

## Decision 53 — Assign & Balance Fleet now handles a hub with more than one source line

### What happened

Player noticed, correctly, that Line 7 never got retired the way Line 6 did, despite also being split at Yarm East and having a full fleet still sitting on it. Log confirmed: `Source line: Line 7 (id=171559)` split first, then `Source line: Line 6 (id=87762)` split second, both in the same "Split Into Lines" click.

### Reason

`source_line_registry.lua` (Decision 46) stored a single line ID per hub, overwritten on every split -- correct for the case it was built to fix (Hendon East's one hardcoded source line), but wrong the moment a hub genuinely has more than one original combined line touching it. Line 7 legitimately touches Yarm East (it's a real inter-hub route, not a mistake), so splitting Yarm East split it too -- but as the second split call's record overwrote the first, "Assign & Balance Fleet" only ever knew about whichever line was split last (Line 6). Line 7's split was real and correct; its retirement pass simply never had a chance to run.

### Decision

`source_line_registry.lua` now stores a SET of line IDs per hub (`M.addSourceLine` adds to the set, `M.getSourceLines` returns the whole array) instead of a single overwritten value. `handleAssignAndBalanceButtonClick` (`epod_truck_distribution.lua`) now runs the full assign → redistribute → delete chain against EVERY recorded source line for the hub, one at a time via a new `processSourceLineNext` recursive chain (same one-at-a-time discipline as every other multi-item async loop in this mod), accumulating combined totals for the final button label.

### Consequence

**Live-confirmed, Decision 53 update**: re-tested in the 6-hub stress test session below — Assign & Balance Fleet correctly processed multiple recorded source lines per hub, one at a time, exactly as designed.

## Decision 54 — `source_line_registry` now removes an entry once its source line is actually deleted

### What happened

During the 6-hub stress test (Corby North, Corby East, Hemel Hempstead East, Stow-on-the-Wold North, Stow-on-the-Wold Transfer, Goole North — 84 managed lines total), a "Dump All Managed Lines" check turned up 84 identical `STAGE 2 STOP REMOVAL FAILED building route (...): Could not re-read source line.` entries in one sweep — every single managed line across every hub, all in the same button click.

### Reason

`source_line_registry.lua` (Decisions 46/53) had `M.addSourceLine` but no removal counterpart. Once a hub's original combined line was fully drained and deleted by a prior successful "Assign & Balance Fleet" run, its ID stayed recorded in `epod_td_source_lines.txt` forever. Every later click on that hub re-ran `assignVehiclesAndRetireStops` against that now-dead ID too, alongside whatever real work remained — `lines.get(deadId)` correctly returned nil, so every candidate line at that hub logged this exact failure once per click. Confirmed harmless (the failure path still calls its callback, so the chain continued and real work was never blocked — `line_splitter.lua` line 664), but genuine, permanent, ever-growing log noise on any hub that had ever completed one successful retirement.

### Decision

Added `M.removeSourceLine(hubStationGroupId, lineId)` to `source_line_registry.lua`. Wired into `epod_truck_distribution.lua`'s `processSourceLineNext`, called the moment `line_splitter.deleteEmptySourceLine`'s callback confirms `deleted == true`.

### Consequence

**Live-confirmed after a save reload**: fresh session log showed zero "Could not re-read source line" entries and zero FAILED entries at all, across two separate "Dump All Managed Lines" checks (84 lines, steady). Note: Lua game scripts load once per session, so this fix could not take effect until the save was reloaded — the stale entries already written before the fix kept generating noise for the rest of that same session, as expected.

## Decision 55 — Added a dedicated "Re-Organize Terminals" button, independent of Split

### What happened

Player added more physical terminals to already-settled hubs mid-test (Goole North grew from 6 to 15 terminals; Stow-on-the-Wold Transfer grew further still, to 21) and asked whether DD could take advantage of them without re-running the whole Split flow.

### Reason

`terminal_allocator.spreadLinesAcrossTerminals` only ever ran from two places: the end of "Split Into Lines & Organize Terminals" (which also re-walks every managed line's split-candidacy logic, wasted work on an already-fully-split hub), or automatically after a genuinely new line is adopted (Decision 46/47). Neither path exists for "the player just built more terminals, nothing about the lines changed." This exact gap was raised live and logged in `IDEAS.md` ("Re-Spread Terminals When Terminal Count Changes") shortly before the player asked for it directly.

### Decision

Added a new always-visible button, "Re-Organize Terminals" (`handleReorganizeTerminalsButtonClick` in `epod_truck_distribution.lua`), sitting right under Split on every hub's panel. Calls `terminal_allocator.spreadLinesAcrossTerminals` directly for the selected hub with `excludeList = {}` — the same call shape already proven at the adoption call site. Not DEBUG-gated: same reasoning as folding the original "Spread Lines Across Terminals" step into Split originally — it never touches vehicle cargo, so it carries none of the Bug A/B risk the DEBUG-only buttons are gated for.

### Consequence

**Live-confirmed after the same save reload**: clicked on Stow-on-the-Wold Transfer with its newly-expanded 21 physical terminals. Log showed `Terminal count at hub: 21`, 28 managed lines planned and spread, all 28 STAGE 4 RESULTs reporting `true`. Removed from `IDEAS.md` as implemented and tested.

## Decision 56 — `alternativeTerminals` research: real engine crash found and fixed; investigation paused

### What happened

Player wanted a line with a huge fleet (e.g. 20 trucks on one dedicated terminal) to be able to use every terminal at a hub instead of one, to relieve real road congestion observed at Goole North. Player independently found TF2's own native UI for this — the line-stop editor's second (fork-icon) terminal picker — confirming the underlying feature is real and player-facing. A disposable research function (`terminal_allocator.testAlternativeTerminals`) was built to determine whether the same `api.cmd.make.updateLine` command already proven throughout this mod could write this field programmatically, avoiding Decision 42's mistake of calling a separate command that didn't exist.

Three shapes were tried in sequence, each informed by the previous result:
1. **Bare integer** (matching how `.terminal` itself is written) — every append attempt returned `false`. Confirmed via the official API docs (`wiki.transportfever2.com/api/modules/api.type.html#StationTerminal`): `alternativeTerminals` requires a list of `type.StationTerminal`, a genuine native type, not a bare integer.
2. **Plain `{station=, terminal=}` Lua table** — also failed outright for the same reason.
3. **Proper `api.type.StationTerminal.new()` construction**, then setting `.terminal` (succeeded) and `.stationGroup` (failed on all 20 attempts) before appending anyway. This is where it went wrong: the code appended the object regardless of whether the station-identifying field write had succeeded, so 20 incomplete `StationTerminal` objects (valid terminal index, no valid station identity) were appended to a real, live line with 20 real vehicles and sent through `updateLine`, which accepted the command with no deeper validation. The game **fatally crashed** shortly after: `Assertion Failure: Assertion 'stIdx0 >= 0' failed`, consistent with the engine later trying to pathfind using one of the incomplete entries and computing a garbage/negative stop index.

### Reason

`pcall` succeeding on a field write only proves the write didn't throw a Lua-level error — it says nothing about whether the resulting native object is semantically valid, and `updateLine`/`sendCommand` do not appear to validate a line's `alternativeTerminals` contents before accepting it. The failure was silent and deferred: the command reported success, and the crash only happened later when the engine actually tried to use the malformed data during real pathfinding, not at write time. The official API docs also turned out to be a dead end for exact field names — `StationTerminal`'s own definition is just "Identifies a Terminal inside a StationGroup," with no field list published anywhere on the wiki.

### Decision

Fixed `testAlternativeTerminals` to never append a `StationTerminal` object unless BOTH the terminal index write and some station-identifying field write are confirmed successful first (tries `stationGroup` then falls back to `station`); if neither identity field can be set, that terminal index is now skipped and logged, never appended. **Investigation paused** rather than continued guessing against the field name live: the wiki has no further detail to try, and guessing further risks repeating the same crash on real production lines. If this is revisited, it should be tested against a disposable throwaway line (this codebase already has a proven create/test/delete pattern from earlier research) rather than a real line carrying real vehicles and cargo.

### Consequence

**Live-confirmed the fix prevents recurrence in principle** (an incomplete object can no longer be appended), but the underlying question — what field(s) `StationTerminal` actually needs — remains unanswered. **The save itself was confirmed NOT corrupted**: reloading afterward (into "TD-Test-Set-Up-2") loaded and ran cleanly, dump still showing a healthy 84 managed lines with zero errors. The one crash was real but self-contained to that single moment; it did not persist or recur on reload.

## Decision 57 — Second real crash from the same research button; button removed entirely

### What happened

After reloading with Decision 56's fix in place, "Test Alt Terminals (DEBUG)" was clicked again (the player was aiming for a nearby report button — all the DEBUG buttons sit stacked together in the panel, an easy mis-click). This time the `.station` fallback field (the second candidate Decision 56's fix tries after `.stationGroup`) **succeeded** where `.stationGroup` had failed before, so the safety check passed and the object was appended. The game crashed again shortly after with a recoverable "Internal error: An error just occurred" dialog (softer than Decision 56's fatal engine assertion, but a real crash regardless) — same underlying cause: `pcall` succeeding on `stationTerminal.station = hubStationGroup` only proves the assignment didn't throw, not that a stationGroup ID is actually valid in a field meant for an individual station entity. The engine accepted the write, then failed later using the semantically-wrong value.

### Reason

Decision 56's fix addressed "never append an object where the write silently failed" but not the deeper problem: a *successful* write can still be semantically wrong, and there is no way to validate that from Lua before the engine actually uses the data. Guessing field names on an undocumented native type (`StationTerminal`) is inherently unsafe on a real production line — the second guess succeeding just meant the crash moved to a different candidate, not that it stopped happening. Compounding this: the button's placement, stacked directly among the report buttons the player actually uses, made an accidental click likely.

### Decision

Removed the "Test Alt Terminals" button and its handler entirely from `epod_truck_distribution.lua` — not fixed further, removed. Two real crashes from the same experimental feature is the threshold for "this doesn't stay clickable," regardless of further safety checks, until the actual field names are confirmed through a genuinely safe channel (e.g. official documentation with a full field list, or testing exclusively against a disposable throwaway line with no real cargo/vehicles at stake). The underlying research function (`terminal_allocator.testAlternativeTerminals`) remains in the codebase, callable manually if ever revisited — same pattern as other disposable research functions in this project — but nothing in the UI can trigger it anymore.

### Consequence

The `alternativeTerminals` investigation is now fully paused with no live path to accidentally re-trigger it. Confirmed (again) the crash is self-contained and recoverable — this one was a soft script-level "Internal error," the game kept running afterward and "Dump All Managed Lines" ran successfully moments later in the same session. If this feature is ever revisited, it needs a fundamentally different approach: either real documentation of `StationTerminal`'s fields, or exclusively testing against a disposable line, never a real one carrying real vehicles again.

## Decision 58 — Merged-StationGroup hubs are an invisible dead zone for the split pipeline (discovered, not fixed)

### What happened

The new Fleet Balance Report (Decision 56 session's feature) surfaced a line — `Goole North ↔ Goole Exchange + Goole Halt + Goole West + Goole East + Upper Goole + Upper Thatcham` — sitting at 14 vehicles, 0 waiting, 0% in-transit utilization: fully idle. The player pulled it up in TF2's own Line Manager and found something odd: all 6 stops on that line display as "Goole North," just on different terminals (14, 1, 4, 5, 6, 8), not as 6 separate stations.

Reading `line_splitter.lua` confirmed this line was never something the mod created — Stage 1 (`splitLineIntoDestinations`) only ever builds 2-stop (hub + one destination) lines, so a 6-stop line is structurally outside anything the split pipeline outputs. The actual cause: TF2 auto-merges physically adjacent/connected stations of the same company into one shared `StationGroup` entity regardless of individually-chosen building names. Goole Exchange, Goole Halt, Goole West, Goole East, Upper Goole, and Upper Thatcham are all, at the engine level, the *same* `StationGroup` as Goole North itself — just different terminals within one merged complex. TF2's own auto-naming for an unnamed multi-stop line joins the individual terminal labels with "+", which is exactly the name the report displayed.

`splitLineIntoDestinations` explicitly filters out any "destination" whose `stationGroup` equals the hub's own (`line_splitter.lua:441`, the "(return)" filter) — real, intentional logic for skipping demand-scan artifacts about the source line's own hub stop. But because all 6 of these named terminals resolve to the *same* `stationGroup` as the hub, every one of them gets caught by that same filter and silently dropped. The line is never split, never touched by Stage 2/3/4, and its vehicles can never be rebalanced by anything this mod does.

### Reason

The mod's entire hub/destination model assumes one `StationGroup` = one physical place. That assumption breaks when the player (knowingly or not) lets TF2 merge several differently-named stations into a single `StationGroup` — from the mod's perspective, "the hub" and "six real destinations" become indistinguishable, because they genuinely are the same entity at the API level. This isn't a bug in the split/filter logic; the filter is doing exactly what it's supposed to do (skip return-trip artifacts). It's a real gap in the mod's underlying model of what a "hub" can be.

### Decision

Not fixing this in code. There is no reliable way to tell "a real return-trip stop" apart from "a real destination that happens to share the hub's `StationGroup` because of an in-game merge" — both look identical (`stationGroup == hubStationGroup`) from the API's point of view, so any change here risks breaking the return-trip filter this same logic correctly relies on everywhere else. The practical fix, if the player wants those trucks freed up, is entirely on the TF2 side: physically separate those stations in-game so they register as distinct `StationGroup`s again. Documenting this as a known, understood edge case rather than chasing a code fix for it.

### Consequence

Any hub built from multiple TF2-merged stations will have some fraction of its lines/vehicles permanently invisible to Stage 1-4, sitting at whatever state they were in when the merge happened — not a crash, not corrupted data, just silently outside the mod's reach. Worth checking for on any hub whose Fleet Balance Report shows a suspiciously idle line with a "+"-joined name; see IDEAS.md's "Detecting Merged-StationGroup Hubs" for a possible future report-side flag (surfacing it, not fixing it).

## Decision 59 — A shared line touching two enabled hubs gets split twice; fixed with ownership + a dedupe sweep

### What happened

The player deliberately built a test line touching two enabled hubs at once (Goole North and Thatcham Sidings, since Thatcham Sidings is itself one of the line's stops), then split it and found the result confusing: `Goole North ↔ Goole Annex + Thatcham Sidings + Goole Sidings` (the original combined line) never shrank, and the raw log showed it had been split **twice**, independently, from each hub's own perspective. Goole North's split treated Thatcham Sidings as "just a destination" and vice versa, producing 5 overlapping child lines (`Thatcham Sidings ↔ Goole North`, `Thatcham Sidings ↔ Goole Annex`, `Thatcham Sidings ↔ Goole Sidings`, `Goole North ↔ Goole Annex`, `Goole North ↔ Thatcham Sidings`) for what was really 3 real destinations — and, since this mod treats lines as direction-agnostic (Decision 18/19), `Thatcham Sidings ↔ Goole North` and `Goole North ↔ Thatcham Sidings` are genuinely the same route created twice.

### Reason

`line_ownership.lua` (Decision 45/48) already exists specifically to give a shared line exactly one owning hub — but it was only ever consulted for split *children* and adopted lines (`planner.lua`'s dispatch candidate scan), never for the *source* combined line at the moment `line_splitter.splitLineIntoDestinations` decides to treat it as "mine to split." So nothing stopped a second hub from independently re-splitting a line the first hub had already claimed.

### Decision

Two changes, addressing prevention and cleanup separately (the player's own framing: "maybe if there's a double up the system just deletes it" covers cleanup, but not the underlying race that keeps producing new doubles):

1. **Prevention**: `splitLineIntoDestinations` now checks `line_ownership.isOwnedByOther(lineInfo.id, hubStationGroup)` immediately after re-reading the source line, before doing anything else. If another hub already owns it, the split is skipped entirely and logged. Reuses the exact registry already proven for this purpose elsewhere — no new state file. (Caught in review before this shipped: every early-return path in this function, including the new one, must still call `onComplete`, since `splitAllManagedLines`'s caller chains through it to move on to the next candidate line in the list — missing this would have silently stalled the whole Split All sequence the first time this path fired for real, unlike the pre-existing early-return paths which the caller's own `realCount < 2` pre-filter mostly keeps it from ever reaching.)

2. **Cleanup**: new `line_splitter.dedupeSharedRouteLines`, wired to a new "Dedupe Shared Route Lines (DEBUG)" button, network-wide (a duplicate pair can span two different hubs, so there's no single hub to scope it to). Groups every managed 2-stop line by its station pair (direction-agnostic, so A↔B and B↔A group together); for any pair with more than one line, keeps exactly one (preferring whichever copy already has vehicles) and deletes the rest, **only if they have 0 vehicles** — same safety discipline as `deleteEmptySourceLine`. If more than one copy in a pair already has vehicles, none are touched and it's only logged, since resolving that would mean moving real vehicles/cargo, out of scope here.

### Consequence

New duplicates of this kind can no longer form (fix #1). Existing ones, including the mess already sitting in the current save from before this fix, can be cleaned up on demand via the new DEBUG button (fix #2) rather than by hand in the Line Manager. Not yet live-tested — needs a reload to confirm both the ownership skip and the dedupe sweep behave as designed against the real 45120 mess.

## Decision 60 — Disabling a hub now cleans up the empty lines it leaves behind

### What happened

Straight after Decision 59's Thatcham Sidings episode, the player turned Auto Redistribute OFF for Thatcham Sidings (correctly stopping it from claiming any more lines as its own hub) but pointed out the 3 empty lines it had already created (`Thatcham Sidings ↔ Goole Annex`, `Thatcham Sidings ↔ Goole Sidings`, plus one already removed by the dedupe sweep) were just going to sit there forever with nothing to clean them up. Framing: "we need it to act smarter... the end user will make all sort of crazy links, we need to be one step ahead" -- the mod should react to the consequences of a player's own action, not just report on the mess afterward.

### Reason

`hub_registry.disable()` only ever flipped a flag -- nothing downstream of it looked at what that hub had actually claimed while it was enabled. `line_ownership.lua` already records exactly this (which lines a hub owns), but had no reverse lookup (all lines owned BY a given hub, rather than the owner OF a given line) and nothing ever asked it that question.

### Decision

Added `line_ownership.getLinesOwnedBy(hubStationGroupId)` (the reverse of the existing `getOwner`), and a new `line_splitter.deleteEmptyOwnedLines(hubStationGroupId, onComplete)` that finds everything a hub owns and deletes whichever of those lines have 0 vehicles -- same safety bar as `dedupeSharedRouteLines` and `deleteEmptySourceLine` (Decision 59/20), never touches a line still carrying real vehicles. Wired directly into `handleAutoRedistributeToggleButtonClick`'s disable branch, so it fires the moment a hub is turned off -- reacting to that specific player action, not a background sweep running on its own schedule across the whole network. The single-line delete-command logic used by both this and Decision 59's dedupe sweep was consolidated into one shared `deleteEmptyManagedLine(entry, logTag, callback)` helper rather than duplicated a third time.

### Consequence

Turning Auto Redistribute off for a hub now self-heals the lines it leaves behind, instead of requiring a manual Dedupe click or hand-deletion in the Line Manager. Not yet live-tested -- needs a reload, then toggling Auto Redistribute on then off for a hub with real owned-but-empty lines to confirm the cleanup actually fires and logs correctly.

## Decision 61 — Assign & Balance Fleet could hang forever on a stale source-line entry

### What happened

Player selected Goole North and clicked Assign & Balance Fleet to finally process the still-unsplit `Goole North ↔ Goole Annex + Thatcham Sidings + Goole Sidings` line (id=45120) discussed all session. The button sat on "Working... (see log)" indefinitely. The raw log showed Stage 2 ran, found all 90 managed lines game-wide as "candidates" (a separate, real scoping bug in `findDestinationStationGroupOnSplitLine` -- it returns the first stop that ISN'T the hub, without ever checking that the candidate line touches the hub at all, so it matches everything), and every single stop-removal attempt failed with "Could not re-read source line." Then Stage 3 logged "Nothing to do: source line has no spare vehicles" and the log went completely silent -- no delete step, no move to the next source line, no final label update, forever.

Reading `epod_td_source_lines.txt` directly showed the real cause: Goole North's hub had TWO recorded source lines, `28014:26897` and `28014:45120` -- 26897 is a long-dead line ID (a leftover from earlier in the session, predating Decision 54's fix, that was never cleaned from the registry). `processSourceLineNext` (epod_truck_distribution.lua) processes a hub's recorded source lines one at a time; it happened to reach the dead 26897 first.

### Reason

The real, fatal bug: both `line_splitter.assignVehiclesAndRetireStops` and `fleet_allocator.redistributeSpareVehiclesByDemand` have multiple early-return "nothing to do" branches (source line not found/unreadable, no candidates, no spare vehicles, no allocations) that returned a result table WITHOUT ever calling their `onComplete` callback. `processSourceLineNext` chains entirely through that callback to run the next stage and eventually move on to the hub's NEXT recorded source line. Hitting 26897 (0 vehicles, since the line doesn't exist) tripped exactly this kind of early return in `redistributeSpareVehiclesByDemand` -- the callback chain died right there, and 45120 -- the line actually genuinely alive and waiting to be processed -- was never reached at all this run. This is the same class of bug caught and fixed earlier this session in `line_splitter.splitLineIntoDestinations`'s new ownership-check branch (Decision 59) -- evidently not everywhere else that same pattern already existed had been checked.

### Decision

Added the missing `onComplete` call to every early-return branch in both `assignVehiclesAndRetireStops` (3 branches) and `redistributeSpareVehiclesByDemand` (4 branches). Also: `processSourceLineNext`'s delete-step callback now specifically recognizes `reason == "source-line-unreadable"` (as opposed to "still-has-vehicles"/"still-has-destinations", which mean a REAL line just isn't finished yet) and calls `source_line_registry.removeSourceLine` to forget it immediately, rather than leaving it to be uselessly re-attempted on every future Assign & Balance click. The separate `findDestinationStationGroupOnSplitLine` over-broad-candidate-matching bug (Stage 2/3 treating literally every managed game-wide line as a "candidate" for whichever hub is currently running, not just ones that actually touch it) was identified but NOT fixed here -- it's real, but it degrades harmlessly as long as the source line itself is readable (a non-matching candidate's stop-removal attempt just finds nothing to remove and no-ops), so it wasn't the cause of this hang and was left for a separate pass.

### Consequence

**Live-confirmed the core fix works**: after reloading, Assign & Balance Fleet on Goole North correctly skipped/forgot the dead 26897 entry and reached the real 45120 line, stripping all 3 real destinations off it and redistributing its spare vehicles. Also surfaced two further real findings in the same run, both fixed in this same decision:

1. **`fleet_allocator.findManagedSplitLines` is not actually hub-scoped**: the log showed 45120's freed-up spare vehicles being sent to completely unrelated hubs (Corby North, Stow-on-the-Wold, Hemel Hempstead) network-wide, not kept within Goole North's own destination family -- the opposite of what `line_ownership` (Decision 45/48) exists to enforce. Confirmed real but **not fixed yet** -- flagged for a separate, deliberate pass since it's a bigger behavioral change (every hub's Assign & Balance has been sharing spare capacity network-wide all session, and whether that's actually wanted needs discussing, not just reverting).

2. **`vehicles.isVehicleEmpty` was checking the wrong thing**: two of 45120's own vehicles, confirmed genuinely empty (0/12) via their own in-game vehicle panel, were permanently skipped by Stage 3's redistribution ("currently carrying cargo or load unknown"), leaving the source line's final 2 vehicles stranded and the line undeletable indefinitely. Root cause: the check tested `next(cargoLoad) == nil` (an empty TABLE), but `cargoLoad` is a cargo-type -> amount map that can retain a key for a compatible cargo type at value 0 even when nothing is loaded (the exact same map shape `sumLineCargo`, from the earlier in-transit-cargo feature, already had to sum values for rather than count keys). Fixed by summing the actual amounts and checking the total is 0, instead of checking whether the table itself is empty.

Also raised live (player's own framing): even once vehicles clear, the source line ends up as a degenerate "loop" -- several stops that are ALL the hub itself, repeated -- something a player could never build through TF2's own UI, existing only because `buildSourceLineWithoutStop` removes one destination's stop at a time without ever consolidating the redundant hub-only stops left behind. Confirmed as a real but purely cosmetic/transient artifact (it only exists in the brief window between a line's last real destination being stripped and its last vehicle being reassigned) -- not fixed in this decision, left as a candidate follow-up.

## Decision 62 — Turning a hub ON now runs full first-time setup, and the button is renamed "Distribution Hub"

### What happened

Player's idea: standing up a brand-new hub currently means clicking four separate things in the right order (Split, Rename Fleet, Re-Organize Terminals -- already folded into Split -- and Assign & Balance), with no guidance that this sequence exists at all. Proposed wrapping it into the existing Auto Redistribute toggle itself, renamed something clearer like "Distribution Hub: ON/OFF" -- default OFF, and turning it ON triggers the whole setup sequence.

A parallel idea (a live "We are setting up your new Distribution Hub... waiting for trucks to drop off load..." progress indicator) was raised and scaled back after the player's own follow-up concern about optimization: not every player runs this mod on a bare vanilla setup, and a live-updating progress display would need some form of background polling to know when trucks finish delivering -- exactly the kind of added always-on cost the player asked to avoid. Settled on a plain, one-shot final status logged at the end instead of a live progress display.

### Decision

`handleAutoRedistributeToggleButtonClick`'s ON branch now calls a new `runNewHubSetupSequence(hubStationGroupId, onAllDone)`, which chains the exact same module functions the three existing buttons already call -- `splitAllManagedLines` (now takes an optional `onAllDone` parameter, threaded through its recursive calls and the terminal-organizing step, backward-compatible since the existing Split button just passes nil), then `fleet_naming.renameFleetToHubIdentity`, then `processSourceLineNext` (the same Stage 2/3/delete orchestration Assign & Balance already uses) -- with a single plain `logUi` status at the end summarizing what happened, naming anything left mid-delivery for the player to catch on a later manual Assign & Balance click. No new logic was written for any of the three steps themselves; this is purely orchestration.

The button's user-facing label text was renamed from "Auto Redistribute" to "Distribution Hub" (`autoRedistributeLabelText` and all `logUi` messages in this handler) to better describe what it now does -- turning a station into a fully managed Distribution Hub, not just toggling ongoing rebalancing. The underlying function/variable names (`handleAutoRedistributeToggleButtonClick`, `hub_registry.enable/disable`, etc.) were deliberately left unchanged -- only the visible strings changed, keeping the diff to what the player actually asked for rather than a wider mechanical rename.

Turning a hub OFF is unchanged (still just disables plus Decision 60's empty-line cleanup) -- this feature is additive to the ON path only.

### Consequence

Not yet live-tested -- needs a reload. The real test: turn Distribution Hub ON for a fresh, never-split hub and confirm the log shows all three steps running in sequence and a sensible final summary, without needing to click Split/Rename Fleet/Assign & Balance separately.

## Decision 63 — Cross-save registry contamination caused both the wrong ON state and a real crash

### What happened

Player loaded save-1 specifically to test Decision 62's new hub-setup sequence on a genuinely fresh, never-managed hub -- but the Distribution Hub toggle showed ON for a hub that had never been touched in this save. Clicking it OFF (triggering Decision 60's cleanup) crashed the game with a native "Internal error" dialog. The raw log confirmed the sequence: `DISTRIBUTION HUB: turned OFF for hub 27920` -> `HUB DISABLE CLEANUP: deleting empty lines owned by hub 27920` -> crash, with the crash trace naming the `autoRedistributeButton` click as the triggering event.

### Reason

Two findings, one root cause. `hub_registry.lua`, `line_ownership.lua`, and `source_line_registry.lua` all write to the game install folder rather than a per-savegame location -- a gap flagged as far back as this project's early Persistence notes (PROGRESS.md Not Started #2), always described as theoretical ("a different save" as a hypothetical). It stopped being hypothetical tonight: save-2 is a later save of the *same* save-1 lineage (the player's own framing: "Save-2 50 years into mod control"), so both saves genuinely share the same entity IDs for the same physical stations -- hub 27920 really is "Corby North" in both. Loading save-1 after a long save-2 session meant `hub_registry` still had 27920 marked enabled from save-2's play, so the toggle showed ON in save-1 despite this specific save never having managed anything.

The crash was the sharper consequence: `line_ownership.getLinesOwnedBy(27920)` returned line IDs recorded during save-2's session, most of which don't exist (or don't exist as lines at all) in save-1's much earlier state. The new `deleteEmptyManagedLine` helper (Decision 59/60) never re-confirmed a line still existed before calling `api.cmd.make.deleteLine` on it -- unlike `deleteEmptySourceLine`, which has always re-read its target first. `api.cmd.make.deleteLine` on a stale ID is a native engine crash, not a Lua error -- the `pcall` already wrapping that command does not catch it, the same lesson already learned once from Decision 56/57's `alternativeTerminals` crashes.

### Decision

Player pushed back hard on treating this as a future research item: real players swap saves constantly, and a mod that can crash on save-swap is not shippable regardless of how rare the trigger felt tonight. Two fixes, not one:

1. **Immediate crash fix**: `deleteEmptyManagedLine` now calls `lines.get(entry.id)` and refuses to attempt the delete (just logs and moves on) if the line isn't confirmed to still exist -- closes the crash for both `dedupeSharedRouteLines` and `deleteEmptyOwnedLines`, and any future caller of this shared helper.

2. **Systemic fix, not just this one call site**: `managed_registry.lua` already had a proven answer to "no reliable API exists to identify which save is active" -- validate every stored ID against the CURRENT game on load, silently dropping anything that no longer resolves to something real, rather than trusting a global file blindly. `hub_registry.lua`, `line_ownership.lua`, and `source_line_registry.lua` never had this (`hub_registry.lua` used to explicitly claim it "doesn't actually bite" -- live-confirmed wrong tonight). All three now validate on load the same way: `hub_registry` checks each stored hub ID still resolves to a real `STATION_GROUP` component (`stations.getStationGroup`); `line_ownership` and `source_line_registry` check each stored line ID is still in `game.interface.getLines()` (the exact pattern `managed_registry.lua` already proved, including its per-instance throttle on the expensive walk). This closes the crash risk for the general case any real player will actually hit: swapping to a genuinely unrelated save, whose stale IDs from the previous save almost never coincidentally resolve to something valid in the new one.

**What this does NOT fix**: the specific case that caused tonight's crash -- an ID that's genuinely valid in BOTH saves, because save-2 is a later save of save-1's own lineage and true per-save isolation would need a save-identity fingerprint, which still doesn't exist (no reliable API was found, per `managed_registry.lua`'s own research). Existence-validation can't distinguish "valid in this save" from "coincidentally also valid in a related save" -- only a real fingerprint could. That remains open, but Decision 63's fix #1 (the actual crash-causing gap) is what's load-bearing here: even with hub 27920's wrongly-ON state passing validation, the delete command itself no longer fires blind, so it no longer crashes.

### Consequence

The specific crash is closed, and the same class of crash (a stale registry ID reaching a delete/mutate command) is now closed for any genuinely unrelated save-swap, not just this one incident. Cosmetic cross-save state confusion (a hub showing ON when this specific save never enabled it) can still happen for saves that share lineage/entity IDs, same as tonight -- worth knowing about, not crash-worthy anymore. True per-save isolation remains a real, still-open research question (PROGRESS.md Not Started #2) for whenever a save-identity fingerprint API is found.

## Decision 64 — Converted hub stations get a "● " name prefix too

### What happened

Player's idea: managed LINES already get a "● " prefix so they're recognizable at a glance, but the HUB station itself gives no visual signal it's been converted -- you have to open this panel to know. Requested the same convention applied to the station name: `Stow-on-the-Wold Transfer` -> `● Stow-on-the-Wold Transfer` once its Distribution Hub toggle is ON.

### Reason

`api.cmd.make.setName` is documented by the official API as fully entity-agnostic ("the entity Id of the entity that should be renamed," no restriction to lines -- COMMANDS.md) and already LIVE-CONFIRMED working on two different entity types in this codebase: vehicles (`fleet_naming.lua`, real live use against ~90+ vehicle fleets) and lines (via `createLine`'s name argument, used throughout `line_splitter.lua`). Renaming a `STATION_GROUP` entity specifically had never been attempted, but nothing about the documented signature or the proven pattern suggested it should behave differently -- a reasonable, low-risk extension rather than genuinely new API territory. Unlike the `alternativeTerminals` saga (Decision 56/57), `setName` has never been the cause of a crash anywhere in this project across two confirmed entity types.

### Decision

Added `stations.M.setEntityName(entityId, newName, onComplete)` -- a thin wrapper around `api.cmd.make.setName` + `api.cmd.sendCommand`, the exact same proven command shape `fleet_naming.lua` already uses per-vehicle. Wired into `handleAutoRedistributeToggleButtonClick`: turning a hub ON prefixes its station name with "● " (only if not already prefixed, so re-enabling an already-converted hub doesn't double up); turning it OFF strips the prefix back off (only if present). Symmetric with the ON behavior even though only the ON case was explicitly requested, since a station's visible name should reflect its current managed state either direction.

### Consequence

**Live-confirmed the rename itself works** -- station names correctly showed "● Corby North" etc. in a real dump. But the same dump caught a real regression: `line_splitter.lua` and `fleet_naming.lua` both build compound names by reading the hub's station name (`stations.getEntityName`) and prepending their OWN "● " -- once the station's real name already carried that prefix, every freshly-created line/fleet name doubled up ("● ● Corby North ↔ Corby Exchange", confirmed live across many lines created after a hub's rename). Fixed by splitting `stations.getEntityName` into two functions: `getRawEntityName` (the true stored name, unmodified -- used by the toggle handler itself, which needs ground truth to correctly add/strip the prefix idempotently) and `getEntityName` (now always strips a leading "● " before returning -- used by every other caller building a name FROM a hub's name, so a renamed hub's own decorative prefix never leaks into something built from it again). Centralized in `stations.lua` rather than patched at each of the several call sites (`line_splitter.lua`, `fleet_naming.lua`, `line_adopter.lua` all read a hub's name this same way), so the same class of bug can't resurface at a call site not yet written.

## Decision 65 — Fully-degenerate source lines self-heal their last stray empty trucks

### What happened

Two real hubs, screenshotted and confirmed in-game: "Line 9" (Stow-on-the-Wold North, 2 trucks, 0/8 cargo) and "Line 5" (Hemel Hempstead East, 1 truck, 0/4 cargo) both fully stripped of every real destination, but still looping the hub-only degenerate line forever with confirmed-empty trucks going nowhere. Player's framing, deciding whether it was worth fixing: "if we fix it now we have a strong initial setup phase" -- this isn't a rare edge case, it's a near-guaranteed outcome of the one-click hub setup (Decision 62) any time demand-weighted apportionment computes a fair share smaller than the actual spare pool.

### Reason

`redistributeSpareVehiclesByDemand` deliberately caps allocation at each candidate's computed fair share of CURRENT waiting demand -- correct behavior for normal ongoing rebalancing (never assign a spare truck somewhere with no real need for it, per the original agreed design). But once a source line has already been stripped to 0 real destinations, that same caution has no more upside: there is no destination left this line could ever legitimately serve again, so a leftover empty truck sitting on it is pure waste, not a considered decision to hold back capacity for later demand elsewhere.

### Decision

Added `fleet_allocator.forceDistributeRemainingSpares(sourceLineId, hubStationGroup, onComplete)`: only ever touches a vehicle confirmed empty (`vehicles.isVehicleEmpty == true`, the exact Decision 61 fix) -- anything not confirmed empty is skipped and left alone, same Bug A safety net as everywhere else in this codebase. Spreads round-robin onto whichever candidate line currently has the fewest vehicles -- no demand weighting needed, since the only goal here is clearing the dead line, not optimizing allocation.

Wired into `processSourceLineNext` (epod_truck_distribution.lua) as a mop-up: `deleteEmptySourceLine`'s refusal reason `"still-has-vehicles"` specifically means 0 real destinations are left (the *other* refusal reason, `"still-has-destinations"`, is a genuinely different situation -- a real line just not finished yet -- and is deliberately NOT retried this way). Only on that specific reason: run the force-distribute mop-up once, then retry the delete once more before finally recording the source line as done or still-kept.

### Consequence

Not yet live-tested -- needs a reload, then re-running Assign & Balance (or toggling Distribution Hub off/on) on Stow-on-the-Wold North and Hemel Hempstead East specifically, since both already have a real fully-degenerate line sitting in exactly the state this fix targets.

## Decision 66 — Concurrent hub setups can crash the game; refuse to overlap them

### What happened

Real fatal crash, game had to be restarted: `Assertion Failure: Assertion 'it != components.end()' failed`, naming entity 27845 -- exactly "Line 5", the fully-degenerate Hemel Hempstead East source line Decision 65's new force-distribute/retry-delete logic had been actively working on. Player was converting a 4th hub via Distribution Hub ON when it happened.

### Reason

Each hub's Distribution Hub setup (Decision 62) is a long chain of sequential async `sendCommand` round-trips (Split -> Rename -> Stage 2 -> Stage 3 -> delete). Nothing stopped a second hub's setup from starting while an earlier one was still mid-chain -- and their log output has been visibly interleaving all session with no prior incident. Decision 65 changed what's possible during that overlap: a "still-has-vehicles" source line that previously would just sit forever (never deleted) can now actually get deleted once its last vehicle clears. If that deletion lands in the same moment a DIFFERENT hub's setup is iterating `game.interface.getLines()` and reading components off every managed line (`findManagedSplitLines`, `findDestinationStationGroupOnSplitLine`, `demand.scan`, etc.), the engine can be asked to read a component off an entity that's being torn down mid-frame -- a native assertion, not a Lua error. No pcall or "safer" read can catch this; the same lesson already learned from the `deleteLine`/`alternativeTerminals` crashes applies here too. Decision 65 didn't create the overlapping-setups risk, but it did create a new place a deletion could land inside that existing, previously-silent race window.

### Decision

Added `distributionState.hubSetupInProgress`, a simple reentrancy guard (same pattern as `dispatcher.lua`'s `isApplyPlanRunning`, Decision 36): `handleAutoRedistributeToggleButtonClick`'s ON branch now refuses to start a second hub's setup while one is already running, logging a plain "wait for it to finish" message instead. Set true right before `runNewHubSetupSequence` starts, cleared in its completion callback -- which required also fixing a pre-existing gap in `processSourceLineNext`'s three outer `pcall` failure branches (`assignVehiclesAndRetireStops`/`redistributeSpareVehiclesByDemand`/`deleteEmptySourceLine` throwing synchronously): they used to only log and update the button label, never actually calling `onAllDone`. Harmless before tonight, but combined with the new guard it would have left `hubSetupInProgress` stuck `true` forever the first time any of those three ever threw -- permanently disabling hub setup for the rest of the session. All three now call `onAllDone()` too.

**Known remaining gap, not covered by this fix**: the older manual DEBUG buttons (Split, Assign & Balance Fleet, Re-Organize Terminals) do not share this same guard -- a player running one of those by hand while a Distribution Hub setup is mid-flight could still hit the same class of race. Lower probability (those buttons are hidden behind Show Debug Tools, off by default) but not eliminated; a shared, codebase-wide mutex across every line-mutating operation would be the fuller fix, not built tonight.

### Consequence

Not yet live-tested -- needs a reload. The direct trigger (clicking a second hub's Distribution Hub toggle while an earlier one is still running) should now be refused outright rather than racing. Converting hubs one at a time, waiting for each "DISTRIBUTION HUB SETUP COMPLETE" before starting the next, remains the safe pattern regardless -- this guard just makes that the enforced behavior instead of only the recommended one.

## Decision 67 — Line ownership was decided by "who asks first," not "who's the real hub"

### What happened

Player, rightly frustrated ("if me part developer gets it wrong 100% so will the end user"): Line 7 kept refusing to convert no matter what, attributed to Corby East -- but Corby East turned out to be a small, single-platform stub with no Distribution Hub UI worth mentioning, clearly not "a real hub" a player would ever think to click. Checked Line 7's own stop list directly: `Corby North` appears **7 times** (the genuine repeated hub-destination-hub-destination pattern this whole split pipeline is built around), `Corby East` appears **once**, as an ordinary destination -- identical in kind to Corby Annex or Corby Sidings on the same line. Corby North is unmistakably the real hub here. Yet `line_ownership.txt` had it recorded the other way around.

### Reason

`line_ownership.isOwnedByOther`'s lazy first-touch claim (the mechanism that lets a pre-existing, never-explicitly-split line become owned by whichever hub's planner notices it) credited whichever ENABLED hub's scan happened to call this function first -- with zero regard for whether that hub actually appears as the line's structural anchor or merely touches it once as a destination. Both Corby North and Corby East are enabled hubs; Corby East's scan just happened to run first, so it won by pure timing, permanently locking Corby North (the line's real owner in every meaningful sense) out of ever touching it.

### Decision

Added `lines.findDominantStationGroup(lineId)`: counts how many times each stationGroup appears among a line's stops and returns whichever one repeats most (must appear more than once, distinguishing a real hub-anchor from an ordinary single-visit destination) -- nil if there's no such repeated stop. `isOwnedByOther`'s lazy claim now uses this to decide who ownership actually goes to, falling back to crediting the caller only when no repeated anchor exists at all (e.g. an already-split plain 2-stop line, where "who asked" is the only signal there is). Also directly corrected the one already-wrong entry this exposed (`epod_td_line_ownership.txt`: line 24333 reassigned from 28905 to 27920) so Line 7 doesn't have to wait for a future re-claim that will never happen naturally (ownership, once recorded, is never re-evaluated once set).

### Consequence

New wrong-owner assignments of this shape should no longer happen going forward. Not yet live-tested — needs a reload, then re-running Split/Distribution Hub on Corby North specifically to confirm Line 7 is finally picked up as its own. Worth keeping in mind: this was found because ONE case got surfaced by player frustration -- the same first-touch flaw could theoretically have mis-attributed other lines elsewhere on the map before this fix existed, and there's no bulk re-audit of already-recorded ownership built here, only a fix to how NEW claims get decided plus the one confirmed bad entry corrected by hand.

## Decision 68 — Closed Decision 67's two acknowledged gaps: reentrancy guard now covers manual buttons too, and ownership mis-attribution now self-heals every session instead of needing a one-off manual fix

### What happened

Decision 66's reentrancy guard (`distributionState.hubSetupInProgress`) only ever wrapped the new one-click "Distribution Hub" setup sequence. The three older manual DEBUG-era buttons -- Split, Re-Organize Terminals, Assign & Balance Fleet -- call the exact same underlying line-mutating machinery (`splitAllManagedLines`, `terminal_allocator.spreadLinesAcrossTerminals`, `line_splitter`/`fleet_allocator`) but were never gated, so the identical overlap crash Decision 66 fixed for the ON/OFF toggle was still reachable by clicking one of these buttons at a second hub while a hub setup (or another manual button) was still running elsewhere. Separately, Decision 67 fixed how NEW ownership claims get decided (`lines.findDominantStationGroup`) and hand-corrected the one bad entry a player happened to find, but explicitly flagged that ownership, once recorded, was never re-evaluated -- any other pre-existing mis-attribution from the old first-touch bug would sit wrong forever with no way to notice it short of another player hitting the same "stubborn Line 7" symptom by chance.

### Decision

Both gaps closed:

1. **Reentrancy guard extended.** `handleSplitButtonClick`, `handleReorganizeTerminalsButtonClick`, and `handleAssignAndBalanceButtonClick` now all check and set the same `distributionState.hubSetupInProgress` flag the ON/OFF toggle uses, clearing it in every completion and failure path (verified each function's callback chain reaches exactly one clearing point, same audit already done for Decision 66's original chain). One shared flag now makes any two of these four entry points -- toggle, Split, Re-Organize Terminals, Assign & Balance, at the same hub or different hubs -- mutually exclusive.
2. **Ownership reconciliation made automatic.** `line_ownership.lua`'s `loadAndValidate()` (already a once-per-session pass, same throttle as its stale-entry cleanup) now also re-derives every recorded line's real dominant stop and corrects the record if it disagrees -- the exact check that manually caught the Corby North/Corby East case, now run automatically against every entry, every session, instead of only when a player happens to notice a stubborn line. Deliberately conservative: only overwrites when `findDominantStationGroup` finds a real repeated anchor (non-nil) that disagrees with the stored owner -- an already-split plain 2-stop line has no such anchor and is left untouched, same fallback rule `isOwnedByOther` itself already uses.

### Reason

Both were explicitly named as known, accepted gaps at the time (Decision 66's "not extended to the manual DEBUG buttons, lower probability since hidden behind Show Debug Tools" and Decision 67's "no bulk re-audit built here, only a fix to how NEW claims get decided"), not oversights discovered later. Closing them now: the manual buttons are still real, reachable code paths regardless of default visibility, and a silent per-session self-heal is strictly better than relying on a player to notice the same symptom Decision 67 needed a screenshot and pointed frustration to diagnose.

### Consequence

Cost is bounded and one-time per session: the reconciliation walk touches each already-recorded line once (same station-group counting `findDominantStationGroup` already does, no new game-wide scan), directly in line with the project's standing "minimal, not a new background poll" constraint. Not yet live-tested -- next play session should confirm no false-corrections fire against legitimately-settled ownership, and that clicking two manual buttons at different hubs back-to-back now correctly queues rather than overlaps.

## Decision 69 — Cross-save contamination confirmed live for real (not just hypothetical): hub_registry now checks the "● " name as ground truth; four shared registry files reset after new-game data was found bleeding into Save 1

### What happened

Loading Save 1 and selecting Corby North -- a hub the player confirmed had never been touched in this save -- showed the "Distribution Hub" toggle already reading ON. Checked `epod_td_enabled_hubs.txt` directly: its 6 entries (`28014, 28029, 28905, 27920, 27437, 15903`) are the exact same stationGroup IDs as the 6 hub owners in last night's completely different "new game" fleet balance report. `epod_td_source_lines.txt` made it concrete: its one entry, `28905:24333`, is literally the exact hub/line pair from Decision 67's Corby East incident -- data that only ever existed because of that separate new-game session. Since none of these files are scoped per savegame (documented since Decision 24, partially addressed by Decision 63's existence-check), and since Save 1 and the new game apparently share the same underlying map/entity-ID layout, the new game's session -- played more recently -- had already overwritten whatever Save 1 itself recorded earlier tonight, before the two crashes.

### Reason

Decision 63's validate-on-load closes the case where a stored ID no longer resolves to anything real (a genuinely unrelated map). It does nothing for this case: the ID resolves fine, in both saves, to a real entity -- just the wrong save's history. This is a materially different, and more dangerous, failure mode than a wrong ON/OFF label: `source_line_registry` feeds its stored line ID directly into `assignVehiclesAndRetireStops`/`redistributeSpareVehiclesByDemand`/`deleteEmptySourceLine` -- exactly Decision 63's original crash mechanism (a resolvable-but-wrong-context ID reaching a mutating command), just not yet triggered because the player checked the label first instead of clicking Assign & Balance blind.

### Decision

Two changes:

1. **`hub_registry.lua`'s `loadAndValidate()` gained a second, independent validity check** alongside the existing "does this ID still resolve" test: does the station's real, current name actually carry the "● " prefix Decision 64 always applies at the exact moment a hub is turned ON? A hub genuinely enabled in the currently-loaded save always has that prefix by the time anyone reads the flag again (the rename happens in the same synchronous click, before any later read). If the flag says enabled but the live name disagrees, the flag is dropped as cross-save noise rather than trusted. This directly generalizes the player's own diagnostic instinct ("check the name has a dot") into the same self-healing validate-on-load shape already proven for stale entries.
2. **The four shared registry files were reset to empty** (`epod_td_enabled_hubs.txt`, `epod_td_source_lines.txt`, `epod_td_line_ownership.txt`, `epod_td_managed_lines.txt`) rather than hand-picking which entries belonged to which save -- tracing the evidence showed essentially all of it was new-game data already, and `managed_registry.lua`'s existing self-healing re-adopt-by-name pass (Decision 26) means nothing is permanently lost: any real `●`-named line in either save silently re-registers itself the next time it's touched. Real save data (lines, names, vehicles, in either save) was not touched -- only this mod's own external bookkeeping.

A source-line-specific version of the same name-based ground-truth check was considered and deliberately NOT built tonight: unlike a hub, a legitimate in-progress source line is deliberately NOT "●"-renamed (it's the original combined line, mid-retirement), so the same heuristic doesn't transfer cleanly, and a rushed, unproven check risked introducing a new false-drop bug into a registry that feeds real delete commands -- worse than leaving the known gap named. Recorded here as still open, not solved.

### Consequence

Save 1 should now start genuinely clean for tonight's testing (items 2/3 from this session, plus this fix). Re-opening the new game later will show every hub toggle back to OFF -- expected and safe to re-click: Split's own line-detection is always a live scan, not registry-dependent, and already-split lines (realCount < 2) are a guaranteed no-op, confirmed by existing code, not yet re-tested live post-reset. This is the second real, live-observed consequence of the long-deferred "no per-save-scoped path" gap (Decision 24, Decision 63) -- no longer a theoretical caveat, now directly responsible for one wrong-label incident and one live-confirmed near-miss on the exact mechanism that already crashed the game once. Worth prioritizing the real fix (a genuine per-save-scoped persistence path) rather than continuing to patch individual symptoms as they're found.

## Decision 70 — Panel was opening for any selected entity, not just stations

### What happened

Requested live: selecting a vehicle in-game (not a station) was popping the Truck Distribution panel open too.

### Reason

`resolveStationGroup(entityId)` already correctly returned `nil` for a vehicle -- a TRANSPORT_VEHICLE has neither a STATION nor STATION_GROUP component -- but `handleStationSelection` never actually checked that result before unconditionally opening/refreshing the window. `guiUpdate`'s own gate (`selectedEntityId == nil`) didn't help either, since `selectedEntityId` gets set for any resolvable entity, station or not.

### Decision

Factored the existing deselect logic (clear selection state, close the window if open) into a shared `closeDistributionWindowAndClearSelection()`, and call it from `handleStationSelection` whenever `resolveStationGroup` comes back nil -- treating "selected something that isn't a station" exactly like "selected nothing" for this panel's purposes, instead of opening for irrelevant content.

### Consequence

Not yet live-tested. Should confirm: selecting a vehicle no longer opens/refreshes the panel; selecting a real station still works exactly as before; switching directly from a station to a vehicle correctly closes the panel rather than leaving stale content.

## Decision 71 — New GUI gained real action buttons; the reentrancy guard moved into a shared module so both windows can't race each other

### What happened

Before adding any clickable action to the new "DD Central Manager" window, checked how the existing overlap-crash guard (Decision 66, extended in Decision 68) actually worked -- it was a private field (`hubSetupInProgress`) on `epod_truck_distribution.lua`'s own `distributionState` table. The new GUI window is deliberately a second, independent window that can be open and clicked at the same time as the old panel (its own header comment already says so). Adding a mutating action button to it without sharing that guard would have reintroduced the exact same overlap-crash class Decision 66/68 just spent tonight closing -- just via a second door instead of the first.

### Decision

1. **Extracted the guard into `operation_lock.lua`** -- a tiny standalone module (`isRunning()`/`begin()`/`finish()`, in-memory only, same as the field it replaces). Every one of `epod_truck_distribution.lua`'s existing guard checks (Split, Re-Organize Terminals, Assign & Balance, Distribution Hub ON) now goes through this shared module instead of its own private field.
2. **Gave `gui_manager.lua` a real action-button capability**: a pool of 8 pre-allocated button slots (same "pre-allocate once, refill per tab" reasoning already used for the text-row pool -- native TF2 UI components can't be created on demand). Each slot's `onClick` is wired exactly once, at window-creation time, to call whatever `.handler` function is currently assigned to that slot -- deliberately avoids ever needing to re-call `:onClick` on the same button object, since whether that stacks or replaces handlers has never been tested in this codebase.
3. **Wired "Re-Organize Terminals" into the OVERVIEW tab** as the first real action, guarded by `operation_lock` exactly like the old panel's copy. Deliberately the ONLY action wired in tonight: it's already a clean, public, single-call module function (`terminal_allocator.spreadLinesAcrossTerminals`) with no orchestration to extract. Split/Assign & Balance/Distribution Hub ON-OFF are still private composed sequences inside `epod_truck_distribution.lua` -- adding those to the new GUI needs them extracted into a shared module first, so two files aren't each maintaining their own copy of the same multi-step chain.

### Reason

Matches this session's dominant theme: two real crashes tonight both came from state that looked locally correct but wasn't actually shared/scoped correctly (the hub-setup race itself, and the cross-save registry contamination). Adding a third window-vs-window race of the same shape, right after fixing the first two, would have been a real regression hiding in plain sight rather than a hypothetical risk.

### Consequence

Not yet live-tested. Should confirm: Re-Organize Terminals from the new GUI actually runs and rebalances terminals; clicking it on the old panel and the new GUI at the same time correctly blocks the second click instead of racing; the old panel's own Split/Assign & Balance/Re-Organize Terminals/Distribution Hub buttons still behave exactly as before now that they read `operation_lock` instead of their own field. Porting Split/Assign & Balance/Distribution Hub ON-OFF into the new GUI is the natural next step, gated on extracting their composed sequences out of `epod_truck_distribution.lua` first.

## Decision 72 — GUI element experiment: does api.gui's wiki-documented Slider/ComboBox/ToggleButton/ImageView actually work in this game version?

### What happened

Player supplied the official wiki page for `api.gui` (https://wiki.transportfever2.com/api/modules/api.gui.html), which documents a `comp.*` class-based surface including `Slider`, `ComboBox`, `ToggleButton`, `ImageView`, `TabWidget`, `Table`, and `List` -- none ever used anywhere in this codebase, which so far only uses `gui.window_create`/`textView_create`/`button_create`/`boxLayout_create` (a separate, undocumented-on-that-wiki, snake_case base-game convenience module).

### Decision

Repurposed the still-placeholder SETTINGS tab as a disposable, low-risk sandbox to test four of these live: Slider, ComboBox (populated with real enabled-hub names), ToggleButton, and ImageView (fed a real, live cargo-type icon path via `demand.getCargoTypeIconPath`, opportunistically grabbed from whatever any enabled hub currently has waiting, rather than a guessed cargo type). Also dumps `require("gui")`'s actual contents once, settling directly whether that convenience module already wraps any of these (same `dumpAvailableCommands`-style evidence-gathering already proven elsewhere in this codebase) instead of guessing a snake_case name.

Every element is built independently, each wrapped in its own `pcall` with clear pass/fail logging, so one failing can't stop the others from being tried or break the rest of the window -- and the whole `gui_tab_settings.M.build()` call is wrapped in a second, outer `pcall` from `gui_manager.lua` as a further safety net. This caution is not reflexive: Decisions 56/57's `alternativeTerminals` saga is the exact lesson this project already paid for once -- a "documented" API call, trusted without an isolated test first, caused two real crashes.

### Reason

The wiki genuinely offers real upgrades over the current button-hack tab system and manual `string.format` tables -- most notably `TabWidget` (a real native tab widget, deliberately avoided so far per this exact codebase's own risk-aversion) and `List` (a much better fit for the still-unbuilt HUBS tab than reusing the generic action-button pool). None of that gets built into the real GUI on the strength of a wiki page alone.

### Consequence

Not yet live-tested -- this is the experiment itself, not its result. Next play session should report: which of Slider/ComboBox/ToggleButton/ImageView actually constructed and rendered, what `require("gui")`'s real dumped contents showed, and whether anything crashed (native crash risk from a bad GUI call has not been ruled out, even though it's a different class of API than `alternativeTerminals`). `TabWidget`/`Table`/`List` deliberately NOT tested yet -- narrower first batch, wider test only once these four show the experimental harness itself is safe. Remove this whole experiment (and build the real Settings tab per `GUI_Plan.md`) once results are in.

## Decision 73 — Decision 72's experiment found a real crash: raw ComboBox construction leaked a native component, asserting at game close. Table/ScrollArea confirmed safe; Slider/ComboBox/ToggleButton confirmed unsafe

### What happened

Ran Decision 72's experiment live. The game itself kept running fine afterward -- Overview, Fleet, other tabs all still worked -- but a **fatal crash fired the moment the player closed the game**: `Assertion 'CComponent::NumInstances() == 0' failed`. The real log (`crash_dump/stdout.txt`, not the stale repo copy of `EPOD-LOG.txt`) had the exact cause: `layout:addItem(comboBox)` threw a genuine engine-level exception (`gui.lua:54: internal error` / "value is not a string") from inside the native `boxLayout_addItem` call, with its own separate minidump. The `ComboBox` object itself had already been constructed and populated with real hub names by that point -- the failure was specifically in attaching it to the layout, leaving a broken, unparented native component alive in memory with nothing owning it. The shutdown-time instance-count assertion is exactly the kind of check that would catch precisely that: a component the engine created but that was never properly torn down because it was never properly parented into a window's ownership tree in the first place.

### Reason

Confirmed directly from the same log capture: dumping `require("gui")`'s real contents live showed this game version's convenience wrapper module (already proven throughout this codebase via `window_create`/`button_create`/`textView_create`/`boxLayout_create`) covers exactly 19 functions -- `window`, `button`, `textView`, `boxLayout`, `absoluteLayout` (get only), `component`, `imageView`, `table`, `scrollArea` -- and nothing else. `Slider`, `ComboBox`, `ToggleButton`, `CheckBox`, `TabWidget`, and `List` (all wiki-documented on `api.gui.comp.*`) have **no wrapped equivalent** in this game version's `gui` module. Reaching for them meant constructing raw `api.gui.comp.*` objects directly and mixing them into a `gui.lua`-managed layout tree -- exactly the combination that broke. `ToggleButton.new(label)` failed the same way for a related reason (passed a `gui.textView_create` return value, which is apparently NOT the raw userdata a native constructor expects -- a wrapped Lua-side object, incompatible with an API expecting genuine native structures). `Slider.new()` failed on argument count alone. Both of those failed cleanly, caught by `pcall`, no leak -- ComboBox is the one that got far enough to actually break something before failing.

### Decision

Stripped Slider/ComboBox/ToggleButton out of `gui_tab_settings.lua` entirely rather than leaving them gated behind any runtime guard -- the experiment's own `experiment.built` flag was session-scoped and would have re-run (and re-crashed) on the very next game launch otherwise. Kept the one confirmed-safe result: `ImageView`, built through the real `gui.imageView_create` wrapper (not the raw fallback that never got exercised for this element, since the wrapped path was tried first and succeeded outright) -- this also incidentally confirms `demand.getCargoTypeIconPath`'s guessed icon-path convention (`ui/hud/cargo_<id>_small.tga`) is correct, live cargo type `COAL` resolved to a real, loadable `ui/hud/cargo_coal_small.tga`.

**Going forward**: `Table` and `ScrollArea` are now confirmed real and safe to build on, through the same proven wrapper pattern as everything else in this codebase -- genuine, low-risk upgrades over the current manual `string.format`-padded text tables and the fixed `MAX_ROWS = 24` ceiling. `Slider`/`ComboBox`/`ToggleButton`/`CheckBox`/`TabWidget`/`List` are not merely "not yet tried" -- they are confirmed to have no safe path in this game version via straightforward construction, and must not be attempted again without a fundamentally different approach (if one even exists) and a far more isolated, disposable test than a live production window.

### Consequence

The current button-based fake-tab system and the generic label-only action-button pool stay exactly as they are -- there is no safe native replacement for them available right now. Real next steps for the GUI: convert SERVICES/FLEET/CARGO's manual string-formatted tables to `gui.table_create`, and wrap the row pool (or at least its content area) in `gui.scrollArea_create` to stop it from silently truncating at 24 rows on larger hubs. HUBS still has no safe way to be a clickable list or dropdown -- it'll need to reuse the existing action-button-pool pattern (one button per hub, same shape as OVERVIEW's action buttons) rather than `List`/`ComboBox`.

## Decision 74 — Read `res/scripts/gui.lua` directly from the TF2 install; found the real mechanism behind Decision 73's crash, and added a zero-risk `game.gui` enumeration

### What happened

Player asked whether the game's own native windows (e.g. the Headquarters/Finance panel) use a different system, and whether that's worth investigating. `res/scripts/gui.lua` turned out to be a real, plain, readable file at the TF2 install directory (not packed) -- read it directly rather than guessing.

### Reason

This is the actual mechanism behind Decision 73's crash, more precisely than "unsafe, not just untested": every `gui.xxx_create` function in that file is a thin wrapper returning a plain Lua table `{ id = "someString" }`, and every method on it (`addItem`, `setText`, etc.) works by passing `self.id`/`child.id` (a STRING) into a lower-level native function (`game.gui.xxx_yyy(id, ...)`). The wiki-documented `api.gui.comp.*` classes are genuine native OOP userdata objects with no `.id` string field at all -- a completely different, incompatible object model that happens to also be reachable from Lua. `layout:addItem(comboBox)` crashed specifically because it tried to read `comboBox.id` off a real native `ComboBox` userdata object, got nil/garbage instead of a real ID string, and the native call failed on it. This isn't "two similar systems, one riskier" -- it's two fundamentally different systems, and mixing an object from one into a call expecting the other is what broke.

This also answers the player's actual question: `gui.lua` only wraps 9 component kinds (window, box/absolute layout, component, textView, imageView, button, table, scrollArea) -- nothing tab-like. The richer `comp.*` classes (TabWidget included) most likely belong to the engine's internal UI system that native windows like Headquarters are built from, not something exposed through the same ID-based path mods get access to.

### Decision

Added a second, purely read-only enumeration (`dumpGameGuiModule`, zero construction/mutation calls, same safety profile as `dumpAvailableCommands` elsewhere in this codebase) to check directly whether `game.gui` -- the real native table underneath `gui.lua`'s wrapper -- exposes more component kinds than the 9 `gui.lua` chose to wrap. If a native `tabWidget_create` or similar exists at that layer, it would use the SAME id-string convention as everything already proven safe, unlike the incompatible `comp.*` mixing that crashed.

### Consequence

Not yet live-tested -- next session's log should show `game.gui`'s real full contents.

## Decision 75 — Corrects Decision 73: Slider/List/CheckBox/ToggleButton are NOT unsafe. Mixing them into a gui.lua-managed layout is. A real, working mod (Move It Enhanced) proves the full raw system safely, including custom styling and a real toolbar icon

### What happened

Player pointed at an installed workshop mod ("Move It Enhanced", Steam Workshop ID `3730920085`) as a real example of a polished TF2 mod GUI. Its `res/scripts/move_it_enhanced/gui.lua` and `gui_util.lua` were read directly. It builds its entire interface -- window, sliders, toggle buttons, toggle button groups, checkboxes, a scrollable list, a real toolbar icon on the base game's own button bar -- using nothing but the raw `api.gui.comp.*`/`api.gui.layout.*` classes Decision 73 had just concluded were "confirmed unsafe." It works. It's shipped, presumably to real players, with no reported instability.

### Reason

Re-reading Decision 73's actual crash evidence in light of this: the crash was never caused by `ComboBox` itself. It was caused by calling `layout:addItem(comboBox)` where `layout` was a `gui.boxLayout_create(...)` object -- one of `gui.lua`'s thin ID-string wrapper tables (Decision 74 already found this: every `gui.lua` method just forwards `self.id`/`child.id`, a plain Lua field, into a `game.gui.*` native call). A raw `api.gui.comp.ComboBox` object has no `.id` field at all, so that call was doomed regardless of which raw component was involved -- `ComboBox` just happened to be the one tried against a real layout attach point; `Slider`/`ToggleButton` failed at construction/type-checking before ever reaching that point.

Move It Enhanced never makes this mistake because it **never touches `gui.lua` at all** -- every layout, window, and component in it is built with the matching raw constructor (`api.gui.layout.BoxLayout.new(...)`, `api.gui.comp.Window.new(...)`, etc.), so every `addItem`/`add` call is passing a real native object to a native method expecting exactly that, consistently, top to bottom. The two systems (`gui.lua`'s ID-registry wrapper vs. the raw OOP class tree) are not "one safer than the other" -- they're two complete, independently self-consistent object models. Decision 73's actual, correct lesson was narrower than it concluded: never pass an object from one system into a method belonging to the other. Used consistently within its own system, the raw API is evidently robust enough to ship in a real, popular mod.

Also confirmed live from the same source, resolving two previously-open questions in `IDEAS.md`:
- **Native toolbar icon (the pasted external guide from earlier tonight) is real and does exactly what it claimed**: `api.gui.util.getById("mainButtonsLayout"):getItem(2)`, then `layout:addItem(button)` -- a working mod hooks into the base game's own toolbar this exact way.
- **Custom native-looking styling is real and documented in a shippable form**: `res/config/style_sheet/moveit_stylesheet.lua` defines real selectors (`!MoveITButton`, with `:hover`/`:active`/`:disabled` pseudo-states) using `stylesheetutil.lua`'s `makeAdder`/`makeColor`, setting `backgroundColor`/`borderColor`/`padding`/`margin`/`fontSize`/`color` -- applied via `component:addStyleClass(name)`. This is the actual mechanism behind every "looks like Urban Games shipped it" mod GUI, not a guess.

### Decision

Correcting Decision 73's framing: `Slider`/`ComboBox`/`ToggleButton`/`CheckBox`/`List`/`ToggleButtonGroup` are not confirmed unsafe -- only mixing a raw-constructed object into a `gui.lua`-managed tree (or vice versa) is confirmed unsafe. A real, richer GUI is achievable, but it means building a subtree (or a whole window) entirely on the raw `api.gui.comp.*`/`api.gui.layout.*` system, matching Move It Enhanced's pattern exactly, not patching individual widgets into the existing `gui_manager.lua` tree.

Not done tonight: this is a bigger, separate undertaking than a quick fix, and per this project's own established discipline (`GUI_Plan.md`'s "one tab at a time," never a rewrite), it should be scoped deliberately -- most likely as a genuinely separate, small, isolated raw-system test window first (mirroring how `gui_tab_settings.lua`'s experiment was kept disposable and separate from the proven panel), before either building new tabs on the raw system or migrating existing ones.

### Consequence

Real path now exists for the richer controls raised earlier tonight (a real Slider for "favor this line," a real hub-picker List/ToggleButtonGroup for HUBS, real native styling instead of default TextView look) -- but it requires committing to the raw system for whatever component tree uses them, consistently, not incrementally bolting one raw widget onto the existing `gui.lua` tree. Worth a deliberate design decision on scope (new raw-built tab/window vs. eventual full migration) before more code gets written, not an immediate build.

## Decision 76 — Built a real raw-system experiment window (`gui_experiment.lua`) and a matching style sheet, following Move It Enhanced's proven pattern exactly

### Decision

New `res/scripts/epod_td/gui_experiment.lua`, triggered by a new always-visible "Open Raw UI Experiment (TEST)" button on the existing panel (same treatment as "Open New GUI"). Built entirely on `api.gui.comp.*`/`api.gui.layout.*` -- deliberately requires nothing from `require("gui")`, so there is no way to accidentally repeat Decision 73's mixing mistake. Contains: a styled header with a real, live cargo icon; a real segmented hub-picker built from `ToggleButtonGroup` + real enabled-hub names (the working replacement for the ComboBox that crashed the game); a live hub summary readout; a real `Slider` (the player's "truck bias" idea, demo-only, logs its value); a real `CheckBox` (demo-only); and a styled `Button`. New `res/config/style_sheet/epod_td_stylesheet.lua`, same mechanism as Move It's own style sheet (`stylesheetutil`'s `makeAdder`/`makeColor`, `!ClassName` selectors, `:hover`/`:active`/`:disabled`/`:selected` pseudo-states), applied via `component:addStyleClass(...)`.

### Consequence

**Live-confirmed clean.** The window opened via its own button, showed the real enabled hub ("Goole North") as a working segmented toggle, live hub summary text, a real functioning slider, a checkbox rendering with a genuine native checkmark, and the custom stylesheet actually rendered (dark header background, colored button) -- the first genuinely native-looking element in this entire mod's GUI history. Most importantly: **the game closed cleanly and reloaded with no issue** -- the exact failure mode from Decision 73 (fatal `CComponent::NumInstances() == 0` assertion on close) did not recur. This confirms the root-cause fix: building entirely on the raw `api.gui.comp.*` system, never crossing it with `gui.lua`, is genuinely safe -- not just theoretically, live-proven.

Slider/checkbox/action button are still deliberately demo-only (log-only handlers) -- wiring any of them to a real dispatch decision is a separate, later step now that the rendering/interaction/shutdown safety are all confirmed.

## Decision 77 — Cargo Balance Inspector (read-only): the mod is destination-aware but not production-recipe-aware, and this is Stage 1 of finding out how badly that matters

### What happened

Player identified a real gap: a destination needing two inputs (e.g. a steel mill needing both IRON_ORE and COAL) shows up as one combined `waiting` total to the Planner today -- 90 waiting could be 81 iron + 9 coal, and the current allocation math has no way to know the coal side is being starved. Proposed a two-stage plan: a read-only inspector first (real evidence before any control mechanism), then a cargo-aware dispatch mechanism chosen from what that evidence shows.

### Decision

Built Stage 1 only. New DEBUG button "Cargo Balance Inspector," alongside Fleet Balance Report. For every managed destination touching 2+ distinct real cargo types (current waiting, from `demand.scan`'s already-proven per-destination `cargoTypes` breakdown, OR all-time unloaded history, from a new small getter `stations.getUnloadedAmountsByType` -- same confirmed `itemsUnloaded` field Decision 28 already proved breaks down by real cargo type, just keeping amounts instead of only the type list), reports both numbers side by side and flags whichever type sits at or below 25% of the busiest type at THAT destination as "comparatively under-served."

Deliberately does NOT claim to know a destination's actual required input ratio -- no API for that has been confirmed, and this project already learned once (Decision 22's terminal stock-take bug) that an aggregate observation can look meaningful and be wrong. The flag is explicitly relative-within-destination, not a claim about the true recipe.

Deliberately stays read-only and does not go near `alternativeTerminals`/cargo-filter territory -- a related, much bigger proposal (splitting a destination into per-cargo-type dedicated lines with load/unload filters) was raised in the same conversation, but that's the same class of undocumented `Line.Stop` sub-field area that crashed the game twice already (Decisions 56/57), both times because a write that succeeded was still semantically wrong and only failed later when the engine actually used it on a real line with real vehicles. Not ruled out for later, but explicitly not attempted until real evidence from this inspector justifies it, and even then only against a disposable throwaway line per Decision 57's own rule.

### Consequence

Not yet live-tested. Next step per the player's own plan: run it against a real multi-input destination (the steel mill that prompted this) for a few minutes and read `epod_td_cargo_balance_report.txt` -- that real evidence, not more speculation, should decide whether Stage 2 (some cargo-aware control mechanism) is even worth the risk, and if so which one.

## Decision 78 — Cargo Balance Inspector's first live run found a real bug in itself: two different cargo-type key spaces, never reconciled

### What happened

First live run produced a broken-looking report: "Iron ore" (waiting=197) and "CargoType IRON_ORE" (unloaded=162) appeared as two separate rows for the exact same real cargo type, and every single all-time-unloaded row got flagged "comparatively under-served" regardless of whether that was true.

### Reason

`demand.scan`'s `cargoTypes` map is keyed by the raw numeric `SIM_CARGO.cargoType` id; `stations.getUnloadedAmountsByType` (built the same session, Decision 77) is keyed by the uppercase string constant (`"IRON_ORE"`) `itemsLoaded`/`itemsUnloaded` actually use. Two different key spaces for the same real cargo type, merged directly without reconciling them -- `stations.lua`'s own pre-existing comment on `getUnloadedCargoTypes` had already flagged exactly this risk ("a different, lower-level API never cross-checked against vehicle capacity keys... risked a silent format mismatch"), and this is precisely that mismatch, self-inflicted in the same session that wrote the warning. Since the two key sets never matched, every unloaded-only row's "waiting" always read as 0 -- always at or below the 25% threshold -- making the under-served flag fire on every single row regardless of any real imbalance.

### Decision

Added `demand.getCargoTypeId(cargoType)` -- returns the same raw string constant `getCargoTypeIconPath` already builds icon paths from, resolved through the already-proven `cargoTypeRep.get()` path. The inspector now normalizes every waiting-side cargo type onto this string-constant key before merging with the unloaded side, so both columns line up under one real row per cargo type. A cargo type seen only in all-time history (never currently waiting) has no resolvable display name via `cargoTypeRep` from a bare string constant -- falls back to a plain prettified version of the constant itself ("IRON_ORE" -> "Iron Ore") rather than the confusing "CargoType IRON_ORE" label.

### Consequence

Not yet re-tested live. The one genuinely useful, unaffected signal from the first run stands on its own regardless of this bug: Goole Steel Plant showed Iron ore waiting=184 against Coal waiting=36 -- both numbers came from the SAME key space (both matched on the waiting side, no merge involved), a real ~5:1 imbalance, exactly the problem this whole feature exists to surface. Worth a second run now to see the fully corrected report before deciding anything about Stage 2.

## Decision 79 — Cargo Balance Inspector's comparison logic promoted from a DEBUG-only report file into the live CARGO tab, via a new shared `demand.buildDestinationCargoRows` helper

### What happened

The player asked to focus on presenting the mod's existing data and functionality better. The CARGO tab (`gui_tab_cargo.lua`) already existed but only showed one combined waiting total per cargo type across the whole hub -- exactly the shape of number that hides a multi-input imbalance (Decision 77/78's whole point). Meanwhile the real, live-confirmed comparative signal (Goole Steel Plant's genuine 4:1 iron/coal imbalance) only ever reached the player through a DEBUG-gated report file dump.

### Reason

Duplicating the Decision 78 key-normalization + comparison logic into the CARGO tab as a second copy would violate this project's own stated architecture for these tabs ("reads existing modules, calculates nothing of its own") and would leave two copies of a subtle, already-once-buggy merge to keep in sync.

### Decision

Extracted the per-destination merge/flag logic out of `handleCargoBalanceInspectorButtonClick` into `demand.buildDestinationCargoRows(destination)` -- takes one `demand.scan` destination entry, returns sorted, flagged rows (`displayName`, `waiting`, `unloaded`, `underServed`) or `nil` if the destination has fewer than 2 real cargo types. Both the original DEBUG report handler and the new `gui_tab_cargo.lua` call this same function; the report keeps its own network-wide, all-hubs traversal and file-writing, the tab keeps its own single-hub traversal and GUI row-writing. `gui_tab_cargo.lua` was rewritten from "one combined total per cargo type" to "one section per destination, worst-served type flagged," matching the report's shape exactly. No DEBUG gate on this tab -- it was already always-visible.

### Consequence

Not yet live-tested. If it renders as intended, the CARGO tab becomes the mod's first live, always-on surface for the multi-input imbalance question that's been under discussion all session (Steel Runners, City vs Production Distribution Centre) -- seeing it passively during normal play rather than only via a manually-triggered DEBUG report.

## Decision 80 — GUI Central Manager style pass: applied the Decision 76 style sheet to the OTHER (gui.lua-wrapped) object system, not yet live-verified from that side

### What happened

Same "present the data better" request. `res/scripts/gui.lua` (already read in full for Decision 74) shows every wrapped object's `componentMetatable` forwards a real `setStyleClassList(list)` call straight to `game.gui.component_setStyleClassList(id, list)` -- the identical native style-class mechanism the Decision 76 style sheet already hooks into from the OTHER (raw `api.gui.comp.*`) object system, just never called from the gui.lua side before now.

### Reason

The DD Central Manager window (`gui_manager.lua` + `gui_tab_*.lua`) is built entirely on gui.lua's wrapper, not the raw system -- Decision 75's rule (never mix the two systems' objects) says nothing about reusing the same style sheet's class NAMES from gui.lua's own, separate `setStyleClassList` method. That's calling a method that already belongs to gui.lua's own object, not passing a foreign object into it -- not the crash pattern from Decision 73.

### Decision

Added new classes to `res/config/style_sheet/epod_td_stylesheet.lua` (`!EpodTdTabActive`/`!EpodTdTabInactive`, `!EpodTdTableHeader`, `!EpodTdWarningText`, `!EpodTdMutedText`) alongside the existing raw-system classes -- one file, both systems. Applied via `pcall(label.setStyleClassList, label, {...})` at every call site (header label, tab buttons, action buttons, and per-row in OVERVIEW/SERVICES/FLEET/TERMINALS/CARGO for header rows and warning conditions -- idle services, services short on fleet, hubs with Auto Redistribute off, under-served cargo types, unassigned terminal lines). Every call is individually pcall-wrapped and the existing text-based fallback markers (e.g. the tab row's leading "> ") were kept, not removed -- if `setStyleClassList` turns out not to apply from this side, the window degrades to unstyled text exactly as it already did, nothing breaks.

### Consequence

Not yet live-tested -- this is the one genuinely unverified assumption in this pass (does a gui.lua-wrapped component actually pick up style classes from a style sheet the same way a raw-system component does). Needs a real in-game check before this is trusted for anything beyond cosmetic tolerance of failure.

## Decision 81 — Decision 80's style pass, live-tested: `setStyleClassList` DOES work from gui.lua's wrapper side, but style classes leaked across the shared row/button pool

### What happened

Player tested Decision 80 live and shared a screenshot of the OVERVIEW tab. Good news first: the header bar, active/inactive tab backgrounds, and the "Re-Organize Terminals" action button all rendered exactly as styled -- confirming, for the first time, that `setStyleClassList` genuinely works from gui.lua-wrapped components, not just the raw `api.gui.comp.*` side (Decision 76). Bad news: "Total vehicles: 65", "Total waiting: 1366", "Terminals: 11", and "Auto Redistribute: **ON**" all rendered in the orange warning color -- despite `gui_tab_overview.lua` never calling `setStyleClassList` on any of those rows, and despite "ON" specifically being the one state that should never be flagged. The 7 unused action-button slots also rendered as bare, ugly green squares with no text.

### Reason

`state.rows` and `state.actionButtons` are a shared, reused pool of native components across every tab and every refresh (the whole reason this framework exists -- native component IDs can't be created on demand). `clearAllRows()`/`clearActionButtons()` only ever reset TEXT (`setText("", ...)`) between refreshes -- never style. A style class applied conditionally by one tab (e.g. FLEET flagging an idle row, or OVERVIEW's own Auto-Redistribute-OFF row on some earlier refresh/hub) stuck on that row object permanently, silently bleeding into whatever unrelated content later landed in the same row index. Decision 80's action buttons had the mirror-image bug: `EpodTdPrimaryButton` was applied once at creation time to all 8 slots, so any slot a tab didn't claim that refresh still kept its green background with blank text.

### Decision

`clearRow()` now also resets style via `pcall(row.label.setStyleClassList, row.label, {})`, and `clearActionButtons()` does the same for `slot.button` -- both run at the start of every `M.refresh()`, before the active tab repopulates content, so every row/button starts genuinely neutral each frame and only carries a style class if THIS refresh's content actually earned one. Removed the now-pointless blanket `EpodTdPrimaryButton` application at button-creation time in `ensureWindow` (it was always overwritten by the very next `clearActionButtons()` call anyway); `gui_tab_overview.lua`'s Re-Organize Terminals slot now (re-)applies `EpodTdPrimaryButton` itself only in its active (non-busy) branch, matching the same "style attaches only when there's real, actionable content" pattern already used for row-level warning colors.

### Consequence

**Live-confirmed fixed.** Player re-tested and shared a second screenshot: "Goole North" now renders in the new gold header color, "Total vehicles/waiting/Terminals" and "Auto Redistribute: ON" are back to plain default text (no more orange leak), and the 7 unused action-button slots no longer render at all. General lesson for this pool-based framework, not just this one bug: any per-refresh mutation beyond `setText` (style, tooltip, anything else `componentMetatable` exposes) must be reset centrally in the clear step, not left to individual tabs to remember to un-set on their own non-flagged rows.

## Decision 82 — Header/muted text colors bumped after live screenshot showed them nearly indistinguishable from default text

### What happened

Same screenshot: `!EpodTdTableHeader`'s `{0.85, 0.85, 0.95, 1}` and `!EpodTdMutedText`'s `{0.75, 0.75, 0.78, 1}` were both so close to the window's default near-white text color that "Goole North" (styled as a header) looked no different from "Managed lines: 10" (unstyled) in the actual screenshot.

### Decision

Bumped `!EpodTdTableHeader` to a warm gold `{0.95, 0.8, 0.5, 1}` and `!EpodTdMutedText` to a visibly dimmer `{0.5, 0.55, 0.55, 1}`, chosen to read as distinct from default text, from the orange warning color, and from each other.

### Consequence

**Live-confirmed working.** Second screenshot shows "Goole North" clearly gold and visually distinct from both default and warning text.

## Decision 83 — Full live pass across CARGO/SERVICES/FLEET/TERMINALS confirmed the polish pass clean; stripped the "● " managed-line marker from display in all three fleet-facing tabs

### What happened

Player screenshotted all four remaining tabs. Result: CARGO's under-served flagging and header styling were correct across four real destinations (Thatcham West, Stow-on-the-Wold Transfer, Springfield Road, The Drive) with no leak; SERVICES' delta>0 rows were consistently orange and delta<=0 rows consistently default; FLEET's two genuinely idle lines were the only two rows flagged; TERMINALS' header was gold with no leak. Decision 81's fix held up everywhere, not just OVERVIEW.

One new, non-bug observation: every line name in SERVICES/FLEET/TERMINALS carries a leading "● " -- confirmed this is managed_registry.lua's own convention (managed lines get renamed with this marker, the same mechanism its self-heal logic uses to recognize its own lines on load). Unlike the CARGO tab's hub marker (which only appeared on the occasional dual-role destination and carried real information there), this marker is on literally every row in these three tabs by definition -- zero information value in THIS context, just clutter eating into the already-tight 36-character truncated name budget (names were visibly cut off mid-word, e.g. "Hemel H").

### Decision

Added the same display-only `stripManagedLineMarker` helper (byte-identical logic to `gui_tab_cargo.lua`'s `stripHubMarker`, kept as separate small local functions per file rather than a shared module -- each gui_tab_*.lua is already a self-contained "GUI ONLY" file by convention, and this project already tolerates small duplicated helpers at this layer, e.g. `findAnyLiveCargoType` exists separately in both `gui_tab_settings.lua` and `gui_experiment.lua`) to `gui_tab_services.lua`, `gui_tab_fleet.lua`, and `gui_tab_terminals.lua`. Applied only to the displayed name string passed to `string.format`/`table.concat`; the real line name (and the self-heal mechanism reading it) is untouched.

### Consequence

Not yet re-tested live.

## Decision 84 — Real live data exposed a slow-converging fleet imbalance; "Apply Fleet Plan" promoted from a DEBUG-only button into a SERVICES tab action button

### What happened

The player's own live SERVICES tab screenshot showed two lines sitting 5-7 vehicles OVER their planner-computed target (9 vehicles against targets of 4 and 2) while five other lines sat 2-5 vehicles under theirs, with waiting cargo up to 273. "The spread is not going well."

### Reason

Not a bug in the plan itself -- `planner.calculateTargetAllocation` already correctly identifies the right numbers (that's exactly what the Delta column showed). The gap is convergence SPEED: `dispatcher.lua`'s automatic trigger only fires every `AUTO_DISPATCH_DELIVERY_THRESHOLD` (5000) deliveries network-wide, and even then caps itself at `MAX_MOVES_PER_RUN` (5) vehicle moves per run -- both deliberately conservative limits added after two real crash incidents (Decisions 36-38, an unresponsive-game hang and a repeated-crash pileup). A ~16-vehicle imbalance at one hub can take a long time to close through the automatic path alone. The fix for this already existed -- a manual "Apply Fleet Plan (DEBUG)" button on the old panel calls the exact same `dispatcher.applyPlan` instantly -- it just wasn't reachable from the new GUI, and required DEBUG mode.

### Decision

Wired `dispatcher.applyPlan` into the SERVICES tab's action-button slot 1, guarded by the shared `operation_lock` (same category of hub-mutating action as Re-Organize Terminals/Split/Assign & Balance, Decision 71's precedent) -- always visible, no DEBUG gate, right on the tab where the imbalance is visible. Deliberately still 100% player-triggered, not new automation -- matches [[feedback_automation_preference]]. Did NOT attempt to show a "done: N moved" confirmation on the button label itself -- `gui_manager.lua`'s `M.refresh` runs every `guiUpdate` frame and would overwrite any such text on the very next frame (immediately after `operation_lock.finish()` releases the busy state), making it effectively invisible. Logged instead, same restraint Re-Organize Terminals's own completion callback already uses -- the SERVICES table's own rows are the real, durable confirmation once they refresh with the new Current/Waiting/Delta numbers.

### Consequence

Not yet live-tested. If the player clicks it several times in a row, cooldowns (Decisions 32/33) mean each click can only move a few more vehicles before hitting the cap or running out of currently-empty, not-in-cooldown candidates on the surplus lines -- closing a ~16-vehicle gap may take several manual clicks spread over real time (each vehicle needs to actually reach and settle at its new line before `COOLDOWN_RUNS` lets it be reconsidered), not one click.

## Decision 85 — New research thread: a custom-modeled truck parking lot construction, built the same evidence-first way as everything else tonight

### What happened

Player is modeling a real 90x90m truck parking lot in Blender (with a second Claude instance in Blender) and asked whether roads, ~11 parking stops, and vehicle pathing could be added to it as a real TF2 construction. Rather than answer from general training knowledge, read real files at every step: the base game's own `depot/road_depot_era_a.con` and `station/street/modular_terminal.con` (from `construction.zip`), then two real, purpose-built mods the player already had installed -- "Warehouse" (Workshop 2152226924, `dsd_road_station1.con`) and its own road-segment/platform `.mdl` files -- cross-checked against the official wiki (`modding:constructionbasics`, `modding:constructiontypes`).

### What was found, in order

1. `.con` files are plain Lua returning `result.models` (placed `.mdl` instances) and `result.edgeLists` (`type = "STREET"`/`"TRACK"`, literal point-path `edges`, `snapNodes` marking which points connect to the public road network when the player builds manually) -- confirmed both by the real depot file and the wiki.
2. `.mdl` files are ALSO plain, human-editable Lua text (not compiled binaries) -- confirmed by opening a real one from the Warehouse mod, and by the player's own `epod_truck_distribution_1.mdl` (exported via ModelEditor's real FBX import, itself confirmed working live this session -- Decision 86 below).
3. The actual truck-pathing/parking mechanism lives inside a placed model's own `metadata.transportNetworkProvider`: a `laneLists` table (drivable curve nodes tagged by `transportModes`, e.g. `{"TRUCK"}`) and a `terminals` table (`vehicleNode = N`, an index into a laneList's nodes marking the stop point). Confirmed both by the real `dsd_road_station1_platform0.mdl` and the wiki's `constructiontypes` page (`result.terminalGroups` groups model-supplied terminals; `vehicleNodeOverride` optionally overrides a terminal's own embedded `vehicleNode`; `result.stations` groups terminalGroups/terminal indices into a tagged, capacity-pooled station).
4. Genuinely NOT resolved by either source: the exact multi-node curve-stitching format (one real example's 4-entry laneList reads as a junction/turnaround, not a simple chain, so its shape doesn't generalize cleanly), and whether `vehicleNode`/`snapNodes` indices are 0- or 1-based.
5. `.msh` mesh files are plain text too, but only as an offset/layout header -- real vertex data lives in an accompanying binary `.msh.blob`, not worth reverse-engineering when the player could just state the real gate coordinates directly (which they did: lot center at world origin, south fence at y=-45 as the public-road side, entrance gate centered at x=-30, exit at x=+30, each a 6m-wide gap).

### Decision

Given the multi-node curve format's genuine ambiguity, staged this exactly like every other unverified-API question tonight: smallest provable slice first. Added a `metadata.transportNetworkProvider` block directly to `epod_truck_distribution_1.mdl` with ONE simple 2-node straight TRUCK lane (real coordinates: entrance gate at (-30,-45,0) to a first terminal stop at (-30,-20,0)) rather than attempting the full 11-stop layout or any turns. Added a matching `result.edgeLists` stub to `epod_truck_park.con` (`type="STREET"`, real syntax copied from `road_depot_era_a.con`) connecting that same entrance point out to the public road. Deliberately did NOT add `terminalGroups`/`stations` yet -- construction `type` is still `ASSET_DEFAULT`, not `STREET_STATION`; this stage only tests whether a plain asset can contribute a driveable, connected TRUCK lane at all, not whether it can register as a cargo stop.

### Consequence

Not yet live-tested -- explicitly flagged to the player as a first real experiment, not confirmed working, with the single least-certain detail (`vehicleNode` 0- vs 1-based indexing) called out by name as the first thing to try changing if the truck doesn't behave as expected.

## Decision 86 — Confirmed live: the Blender -> FBX -> ModelEditor -> real, loadable `.mdl` pipeline works end-to-end in this project

### What happened

This was the single biggest unverified risk flagged when the parking-lot idea first came up (Decision-adjacent conversation, same session). Player used ModelEditor.exe's real FBX import (`model_editor/plugins/FbxImportPlugin.dll`, confirmed present in the game install) on `epod_truck_park.fbx`, producing real files on disk: `res/models/model/epod_truck_distribution_1.mdl`, per-object `.msh`/`.msh.blob` mesh data, and real `.mtl` materials (`MAT_Gravel`, `MAT_Wood`) matching the Blender build.

### Decision

Wrote a minimal `ASSET_DEFAULT` construction (`res/construction/asset/epod_truck_park.con`) referencing the exported model, modeled on the real base-game `asset/default_multi_bench_new.con`.

### Consequence

First live placement test showed a small white checkered placeholder cube, not the real lot -- NOT a pipeline failure. The real game log (`stdout.txt`) gave the exact cause: `[RESOURCE ERROR] Referenced model not found: 'models/model/epod_truck_distribution_1.mdl'`. Root cause: model `id` paths are relative to where `res/models/model.zip` mounts (`res/models/model/`), not to `res/` -- confirmed by finding the base game's own `bench_new.mdl` on disk at `res/models/model/asset/bench_new.mdl` but referenced in its `.con` as just `"asset/bench_new.mdl"`. Fixed by dropping the redundant `models/model/` prefix. Not yet re-tested live after the fix.

## Decision 87 — Real crash selecting the construction from the menu; isolated by reverting the more speculative of two new changes

### What happened

Player selected "EPOD Truck Park" from the construction menu's misc category and got a real "Internal error" dialog. The live log confirmed a genuine engine-level crash (a hang warning + `MinidumpCallback` with a real minidump ID), not a clean `[RESOURCE ERROR]`-style message like the earlier model-path bug. Selecting an item in the construction menu is exactly when the engine calls the `.con`'s `updateFn` to build a preview -- confirmed this is the trigger, not something unrelated, by asking the player exactly what they were doing (selecting from assets) before touching the log.

### Reason

Two genuinely new, previously-untested pieces were added together in the same edit: `epod_truck_park.con`'s `result.edgeLists` (syntax copied near-verbatim from a real, working base-game file, `depot/road_depot_era_a.con`) and `epod_truck_distribution_1.mdl`'s hand-authored `metadata.transportNetworkProvider` block (a 2-node laneList + terminal, with NO exact matching real precedent -- the one real reference read, `dsd_road_station1_platform0.mdl`, has an ambiguous 4-node junction/turnaround shape that never cleanly confirmed the simple 2-node case). With two unverified changes stacked, the crash can't be attributed to either one without isolating them.

### Decision

Reverted `epod_truck_distribution_1.mdl`'s `metadata` back to empty (`{}`), keeping `epod_truck_park.con`'s `edgeLists` addition in place -- the more speculative, less-grounded piece is the one pulled out first. One live retest now cleanly answers which change was fatal: if selecting the construction works with just the edgeLists change present, the hand-authored transport-network metadata was the crash cause; if it still crashes, the edgeLists addition itself is.

### Consequence

Not yet retested live. If the transport-network metadata is confirmed as the cause, the next step is narrowing down what specifically about the hand-authored format is invalid -- most likely candidates: the duplicate-final-node convention, the `vehicleNode` indexing guess, or `laneLists` requiring more structure than a bare 2-node line provides.

## Decision 88 — Isolation completed: the `.con`'s `edgeLists` addition was the real, fatal crash cause, not the `.mdl`'s transport-network metadata

### What happened

Retested after Decision 87's revert (transport-network metadata removed, `edgeLists` addition still in place). Still crashed -- this time with a full, detailed dialog instead of the earlier generic one: `Assertion Failure: Assertion `it->second.second == 1' failed`, with a real minidump and a UI hierarchy showing `styleClasses = {"action-constructionbuilder"}` -- confirming the crash is inside the construction-preview builder, consistent with selecting the item from the menu being the trigger.

### Reason

Isolation is now conclusive: removing the transport-network metadata did NOT fix the crash, so that was never the cause (Decision 87's suspicion was wrong). The `.con`'s `edgeLists` addition is the actual fault. Root cause not fully diagnosed, but the most likely candidate: the real reference file (`depot/road_depot_era_a.con`) uses TWO edges sharing a common inner point (offering two alternate snap distances), and this version simplified that to a single edge -- the assertion's shape (`it->second.second == 1`, reading like a reference-count check expecting exactly one thing and finding a different count) is consistent with some internal edge/node bookkeeping invariant that the two-edge shape satisfies and the single-edge simplification does not.

### Decision

Reverted `epod_truck_park.con`'s `edgeLists` addition entirely, restoring the last confirmed-clean state (Stage 1: plain model placement, no road connection). Not yet re-attempted -- next try should copy the real depot file's edge shape more exactly (two edges, matching point-sharing pattern) rather than simplifying it, and/or investigate whether `edgeLists` on an `ASSET_DEFAULT` construction is even the right mechanism versus needing a different construction `type`.

### Consequence

Confirms this project's own established discipline paid off directly: stacking two unverified changes in one edit would have left the actual cause ambiguous; isolating one at a time turned two plausible suspects into one conclusively-identified one, cheaply (two live tests, not a longer guessing loop). **Live-confirmed clean afterward**: player placed the reverted construction with no crash -- the real 90x90m fenced lot rendered correctly. Ground texture shows expected grass-bleed-through patchiness since `terrainAlignmentLists` is still empty (no ground reshaping yet) -- cosmetic, not a sign of a broken pipeline.

## Decision 89 — Second road-connection attempt: copied the real depot file's exact two-edge shape instead of simplifying to one

### What happened

Decision 88 conclusively isolated the crash to the `edgeLists` addition, most likely to simplifying the real reference file's two edges (sharing one inner point, differing outer points) down to a single edge. Second attempt copies that exact structural shape onto real coordinates: both edges share the lot's real gate point `(-30,-45,0)` as their inner/second element, differing only in how far south their outer/first element sits (`(-30,-56,0)` and `(-30,-66,0)`), with `snapNodes = {1}` unchanged from the real file.

### Decision

Construction `type` deliberately left as `ASSET_DEFAULT`, unchanged -- this test isolates edge SHAPE specifically. If it still crashes, construction type becomes the next thing to try changing, not before.

### Consequence

**Live-confirmed working.** No crash this time -- the two-edge shape was the real fix for Decision 88's fatal assertion. First placement attempts (near an existing road/small park, then in an open field) showed the ordinary "Too much curvature" build-validation message, ruling out "just needs an empty spot" -- it reproduced even on open grass. Root cause: the same completely normal TF2 rule any vanilla construction follows -- a road connection needs a reasonable angle to whatever it's snapping near. Confirmed by the player rotating/repositioning until the angle worked, at which point it placed cleanly next to a real road with real traffic passing by. This is the pipeline's first full end-to-end live success: a custom Blender model, exported through ModelEditor's real FBX import, placed in-game as a working construction with a real, functioning road connection.

## Decision 90 — Ground/terrain fitting: found the real, simple mechanism directly in the base game's own shared `constructionutil.lua`, not the complex triangulated mesh data the depot reference file used

### What happened

Player picked "ground/terrain fitting" as the next thing to work on -- the empty `terrainAlignmentLists` (Stage 1's placeholder, copied from the real bench asset which never needed real ground-fitting) was the known cause of the blotchy grass-bleed-through look. Rather than reverse-engineer the depot file's complex triangulated `meshes.equal/greater/less` data (which is tool-generated, not hand-writable), read the real, shared `res/scripts/constructionutil.lua` directly and found `addModelsAndGroups`'s own internals plus a second, much simpler real usage: `makeFaces()` (used by the base game's own `makeTrainStationNew`), which builds `result.terrainAlignmentLists = {{type="EQUAL", faces = { plainRectanglePolygon } }}` directly -- a bare 4-point polygon, not a triangulated mesh at all.

### Decision

Added a `lotFootprint` rectangle matching the construction's real, already-confirmed bounding box (±45 on X and Y, from `epod_truck_distribution_1.mdl`'s own `boundingInfo`) as the `EQUAL` terrain alignment face. Deliberately did NOT add matching `result.groundFaces` texture-painting -- the model already supplies its own gravel-textured ground mesh visually; adding a second, separate ground-texture paint on top would risk fighting or duplicating it. This stage only asks whether flattening the real terrain under the footprint fixes the visual mismatch, not repainting the ground.

### Consequence

**Live-confirmed working.** Player placed on real uneven terrain near an existing road -- the blotchy grass-bleed-through is completely gone, the gravel texture fills the whole real footprint cleanly. Ground/terrain fitting is done.

## Decision 91 — Road connection style swapped: the depot turnaround apron was visually oversized for a plain lot; not the edge geometry's fault

### What happened

Same test that confirmed Decision 90's ground fix also showed the road connection rendering as an oversized paved fan/apron shape, and not fully snapped to the existing dirt path.

### Reason

`"street_depot/entrance_old.lua"` (borrowed in Decision 89 purely because it was in the one real working reference available) is the base game's vehicle-PURCHASE-DEPOT turnaround apron style -- built for buses/trucks queuing to buy/sell vehicles, never actually vetted for a plain lot entrance. The oversized look is that style's own real geometry, not a defect in this construction's edge coordinates.

### Decision

Swapped to `"standard/town_small_old.lua"` -- confirmed real (not guessed) by finding it used directly in `res/scripts/constructionutil.lua`'s own `constructionutil.makeTrainStation`, a genuinely generic plain-street style already proven in real base-game code, for exactly the same kind of STREET edgeList connection. Edge geometry (the two-edge shape from Decision 89) left unchanged -- only the street style string changed.

### Consequence

**Live-confirmed the style swap alone did NOT fix the visible shape.** Player tested and found the paved connector still rendered as a curved, tapering wedge -- correctly pointed out that this was never going to be fixed by a texture/style change, since the shape comes from the edge coordinates (two edges of different length sharing one point), not the material. Decision 91's framing ("root cause: the street style itself") was incomplete -- the style swap was a real, separate improvement (plainer paving texture instead of a depot apron look), but the taper shape is a distinct issue this decision didn't actually address. Also newly observed: the paved connector shows as a separate "no name" entity when selected -- confirms `edgeLists` is successfully building a real, independent street object (genuine further progress past Decision 88's crash), but it isn't touching either the lot's own fence or the pre-existing road on either side.

## Decision 92 — Equalized the two edges' arm lengths; real counter-evidence found against "unequal arms = broken apron"

### What happened

The tapering wedge shape was correctly traced to the two edges sharing one point but extending to different lengths (11 units and 21 units, matching the real depot file's own ~11:21 ratio almost exactly). Before treating "unequal arms" as confirmed broken, checked `constructionutil.lua`'s real `makeTrainStation` function for its own STREET edgeList -- found the SAME shared-point/unequal-arm shape, at an even more extreme ratio (3 units vs 18 units), in genuine shipped vanilla code. This means the shape itself is very likely TF2's normal "entrance stub widens toward the street" idiom, not a defect -- so equalizing the arms doesn't correct a bug, it just chooses a plainer strip shape instead of a tapered one, which is what's visually wanted for a plain lot regardless.

### Decision

Made both edges the same length (11 units) from the shared gate point, collapsing the taper into a straight strip. Left the real, still-unresolved disconnection issue (the stub not touching either the fence or the existing road) for a separate fix -- current leading hypothesis, raised independently before this exchange and not yet contradicted: `result.models[].transf` explicitly applies `constructionutil.rotateTransf(params, ...)` so the model rotates correctly with however the player orients the construction at placement, but `result.edgeLists[].edges` are raw, un-rotated literal coordinates -- if the piece was rotated at all when placed, the model and the edges would end up in genuinely different real-world orientations, which would produce exactly this "correctly-shaped fence, disconnected floating road stub" symptom. Deliberately did not guess at the `transf` module's exact API for rotating a raw point without confirming this first -- asked the player directly whether the piece was rotated when placed, still awaiting an answer.

### Consequence

Superseded by Decision 93 before a live retest -- the rotation-mismatch theory was never actually confirmed or refuted, because a more fundamental error was found first.

## Decision 93 — The actual root cause, found by re-reading the Warehouse mod's real road-building call sites: `edges` entries are `{position, tangentVector}`, not `{point1, point2}`

### What happened

Player suggested looking at exactly how the Warehouse mod (already installed, already read once for its terminal mechanism -- Decision 85) builds its own road connection, rather than continuing to hand-tune coordinates copied from the vehicle-purchase depot. Found the real call sites (`dsd_road_station1.con` lines 618-619): `makeStreets({ { {xMax, yCentre, 0.0}, {streetStub, 0.0, 0.0} }, ... }, {1}, ...)`. The second element of each pair is a literal small vector pointing in the direction of travel (`{streetStub, 0.0, 0.0}` -- a fixed-length constant along the axis of motion), not a second coordinate.

### Reason

Every `edges` entry written since Decision 89 copied the depot file's literal numbers under the assumption they were two endpoints of a line segment. They were actually already-converted `{position, tangentVector}` Hermite-curve samples -- confirmed by cross-checking `constructionutil.lua`'s own `addEdges` function (read earlier for Decision 90's research but not connected to this until now): it explicitly computes `tangent = subtract(points[2], points[1])` from a caller-supplied two-point pair and stores `{points[1], tangent}` -- i.e. the LOW-level format really is point+tangent, and `addEdges` is the convenience wrapper that converts the intuitive two-point format into it. Every attempt so far skipped that conversion and fed a raw second coordinate in as if it were already a tangent -- a nonsensical, huge, wrongly-directed vector -- fully explaining both the tapering wedge shape (Decisions 91/92) and the disconnection from the fence and the existing road (never actually explained by the rotation-mismatch theory, which turned out not to be needed).

### Decision

Replaced the hand-built `result.edgeLists` assignment with a call to `constructionutil.addEdges({ {point1,point2}, {point1,point2} }, result, "STREET", {type=...}, true)` -- the real existing helper, doing the point-pair-to-tangent conversion correctly instead of by hand. Edges now span the real 6m gate width (x=-33 to x=-27) as two parallel, equal-length lines, giving a plain constant-width strip instead of any taper. `free = true` lets the helper auto-compute snap points via `streetutil.freeAllNodes` rather than a manually guessed `snapNodes` index.

### Consequence

**Live-confirmed the core fix worked.** Player placed and the road correctly touched the lot's fence at the gate -- no more taper, no more disconnection. Both issues really did share one root cause, exactly as predicted.

## Decision 94 — New, separate problem surfaced once the connection worked: `free = true`'s auto-generated turnaround loops collided with each other

### What happened

With the connection now correctly anchored, placement failed with "Collision, Construction not possible" -- two purple oval/racetrack shapes visible right at the connection point, overlapping each other.

### Reason

`free = true` passed to `constructionutil.addEdges` computes `res.freeNodes = streetutil.freeAllNodes(edges)`, which auto-generates turnaround-loop geometry at every free edge endpoint. With the two parallel lanes only 6m apart (matching the real gate width), the loops generated for each lane overlapped each other.

### Decision

Changed `free` to `false`, stopping the automatic loop generation entirely. Trade-off: `constructionutil.addEdges` hardcodes `snapNodes = {}` whenever `free` isn't true, so this construction currently has no interactive snap point at all -- acceptable for isolating whether removing the loops fixes the collision, not a final state. A real explicit `snapNodes` index (matching the depot file's `snapNodes = {1}` pattern, now correctly understood) is the next real follow-up once this is confirmed collision-free.

### Consequence

**Live-confirmed the loops are gone** -- a clean small rectangle, no more overlap. But the whole construction (not just the road) now shows red "Collision" -- with `snapNodes` hardcoded empty whenever `free` isn't true, the engine sees a genuinely unconnected road stub sitting close to a real pre-existing road and refuses the whole placement, since nothing marks that endpoint as intended to connect there.

## Decision 95 — Explicit `snapNodes` added back after the `addEdges` call, without reintroducing the loop-generation problem

### What happened

Decision 94 traded the loop-collision for a new "unconnected road too close to existing road" collision by removing `snapNodes` entirely along with `free`.

### Decision

Kept `free = false` (no auto-loop generation) but added `result.edgeLists[#result.edgeLists].snapNodes = {2, 4}` immediately after the `constructionutil.addEdges` call -- the function appends a plain Lua table to `result.edgeLists`, nothing stops mutating it afterward. Indices reasoned from `addEdges`'s own flattening order: two 2-point input groups become 4 edge entries (lane1 inner, lane1 outer, lane2 inner, lane2 outer); 2 and 4 are both lanes' OUTER (away-from-the-lot) points, matching the real depot file's own convention of marking the street-side point connectable rather than the building-side one.

### Consequence

**Crashed -- the exact same fatal assertion as Decision 88** ("`it->second.second == 1`"), on a structurally different-looking attempt (four edge entries from two separate lane groups, `snapNodes = {2,4}`, versus Decision 88's two edges sharing one point, `snapNodes = {1}`). The same failure recurring across two superficially different configurations is a stronger signal than either configuration's own specific numbers -- points at a shared structural mistake rather than a wrong index value.

## Decision 96 — Corrected the actual structural model: a "STREET" edgeList wants ONE connected centerline path, not two hand-specified lane-boundary curves

### What happened

Re-examined every real reference file with this specific question in mind (not "what numbers did it use" but "how many separate, disconnected edge chains does it define"): the depot, `constructionutil.makeTrainStation`, and both real Warehouse mod `makeStreets` call sites all define their road as ONE connected path -- even a 2-entry `edges` array is two sample points along one continuous run (sharing a point, per Decision 93's corrected understanding of the point+tangent format), never two independent, never-touching parallel lines.

### Reason

The previous attempt (Decision 95) built exactly that: two separate lane-boundary curves (x=-33 and x=-27) that never share a single point anywhere -- two genuinely disjoint edge chains inside one edgeList entry, attempting to hand-specify the road's WIDTH directly. That's very likely the real thing the `it->second.second == 1` assertion guards against in both crashes -- not a snapNodes indexing mistake at all. The "STREET" system doesn't take a manually-specified width; the referenced style (`"standard/town_small_old.lua"`) determines the paved width automatically from a single centerline path, exactly matching how every real example actually works.

### Decision

Replaced the two-lane-boundary approach with a single centerline path -- one 2-point group from the gate `(-30,-45,0)` outward to `(-30,-56,0)`, matching the shape (not the exact numbers) of every real reference file. `snapNodes = {2}` marks the single outer/street-side point as connectable, following the same convention.

### Consequence

Not yet live-tested. This is the first attempt built from "what structural pattern do ALL real examples share" rather than "what specific numbers did one example use" -- a more general, better-grounded basis than any single previous attempt.

## Decision 97 — Player found and read a second independent real mod ("Lollo"'s modular streetside lorry station); resolved the snapNodes 0-vs-1-based indexing question left open since Decision 84/89

### What happened

Player extracted and read a `.base5` backup file (an older, pre-refactor, self-contained version) from a real, mature, actively-engineered lorry-station mod. Two findings: (1) independent confirmation of Decision 93's `{position, tangentVector}` format -- a second, unrelated real mod uses the identical shape (`{ {point}, {-1,0,0} }`, a small direction vector, not a second point); (2) resolves the snapNodes indexing question that was never actually settled -- that mod's real, working code sets `snapNodes = {0, 5}` on a 6-edge chain. A "0" appearing at all is only possible under 0-based (native/engine-style) indexing; ordinary Lua table indexing never produces a valid index of 0. Also notably: that mod sets `freeNodes = {}` explicitly alongside populated `snapNodes`, rather than omitting the field.

### Reason

Every previous `snapNodes` value written tonight (`{1}` in Decisions 89/95, `{2,4}` in Decision 95, `{2}` in Decision 96) was chosen assuming ordinary 1-based Lua indexing. Under the corrected 0-based understanding, Decision 96's `{2}` was very likely out-of-bounds on a 2-entry `edges` array (only indices 0 and 1 exist) -- independently explaining that crash regardless of the two-vs-one-path structural question Decision 96 also addressed. Decision 95's `{1}` was pointing at the INNER (gate-side) point, not the outer/street-side point as intended.

### Decision

Corrected `snapNodes` to `{1}` under 0-based indexing (Lua-table index 2 = the outer/street-side point of the single centerline path, native index 1). Added an explicit `result.edgeLists[#result.edgeLists].freeNodes = {}`, matching the real mod's pattern exactly -- `constructionutil.addEdges` with `free = false` never sets this field at all (leaves it nil), which may not be equivalent to an explicit empty table on the native/engine side.

### Consequence

**Live-confirmed working, end to end.** Placed cleanly: a proper cobblestone driveway running from the lot's entrance gate straight to the real, pre-existing paved road with lane markings, no crash, no collision, no taper, fully connected on both ends. This closes out the road-connection thread that started with Decision 88's crash -- nine attempts total, each one narrowed by real evidence (game log errors, real reference mods, a second independent mod cross-check) rather than repeated guessing. Summary of what the finished, working shape actually is: a single centerline path (not hand-specified lane boundaries) from the gate outward, built via `constructionutil.addEdges` with `free = false`, an explicit `snapNodes = {1}` under 0-based native indexing marking the outer/street-side point, and an explicit `freeNodes = {}` -- referencing a plain, generic street style (`"standard/town_small_old.lua"`) rather than the vehicle-depot-specific style first borrowed in Decision 89.

## Decision 98 — Added the exit gate as a second, mirrored road connection using the now-proven entrance pattern

### What happened

With the entrance connection fully confirmed working, added the exit gate (x=30, gap x=27..33, same south fence) as a second, independent `constructionutil.addEdges` call using the exact same shape that just worked: one centerline path, the same generic street style, `snapNodes = {1}` (0-based, outer point) and explicit `freeNodes = {}`.

### Decision

Each `constructionutil.addEdges` call appends its own new entry to `result.edgeLists`, so indexing off `#result.edgeLists` again after the second call correctly targets the exit's own entry, independent of the entrance's.

### Consequence

**Live-confirmed working.** Both gates now have their own independent, cleanly-connected road stub reaching the public highway, no collision between the two despite being on the same construction. This closes out the road-connection thread that began with Decision 88's crash: entrance and exit both proven working, using the same understood, reusable pattern (single centerline path via `constructionutil.addEdges`, generic street style, `snapNodes = {1}` under 0-based indexing, explicit `freeNodes = {}`).

## Decision 99 — First real attempt at the internal driveable lane + terminals, scoped deliberately small after a live design discussion

### What happened

Player floated a full yard concept: drive down the middle, U-turn at the far end, park along one side near the exit, ~5 terminals per side. Given tonight's ModelEditor GUI crash (real, confirmed via Windows crash dumps) ruled out the visual metadata editor for now, and a true U-turn is a genuinely untested curve shape for this project (only straight 2-node lanes have been proven, in the `.con` road stubs), asked the player to choose scope before writing anything. Player chose the smaller, safer option: one straight lane, 2-3 terminal stops, no curve, deferring the full yard layout until this core mechanism is confirmed.

### Decision

Added a real `metadata.transportNetworkProvider` block to `epod_truck_distribution_1.mdl` -- one straight `laneLists` entry (`transportModes = {"TRUCK"}`) extending the already-proven entrance line (x=-30) further north into the lot, with 3 nodes at y=-25/-5/15 plus a closing sentinel duplicate, and a `terminals` table with 3 entries referencing `vehicleNode` 1/2/3 (0-based, per Decision 97's resolved indexing). Tangent convention follows the same `nextPoint - thisPoint` formula `constructionutil.addEdges` itself uses. Also changed `epod_truck_park.con`'s construction `type` from `ASSET_DEFAULT` to `STREET_STATION_CARGO` -- every real example with working terminals uses a station type, none use `ASSET_DEFAULT` -- and added `result.terminalGroups` (3 groups, each referencing `{modelIndex=0, terminalIndex}`) and `result.stations` (one station grouping all 3, matching the real Warehouse mod's own `{terminals={0,1,2,...}, tag=0, pool={...}}` shape).

### Consequence

**Crashed -- but with an unusually precise native error.** "Internal error (see console for details)" during placement preview; the real log gave the exact native assertion: `Assertion 'num % 2 == 0' failed` inside `street_util::CreateTransportNetwork` (`construction_util_connector.cpp:78`) -- the actual engine function that processes `LaneList` data directly. Not the construction-type change suspected in Decision 99's own consequence note -- a structural mistake in the lane's node count instead.

## Decision 100 — Fixed the actual cause: lane node counts must be even (segment pairs), not a continuous polyline of unique points

### What happened

The crashing lane had 5 node entries (gate + 3 stops + 1 duplicate "closing sentinel," following Decision 90's own -- now shown to be wrong -- reading of `straightline.mdl`'s 2-node example). 5 is odd; the native assertion requires an even count.

### Reason

Re-checked every real example specifically for node/edge COUNT (not shape) for the first time: `straightline.mdl` (2), `platform0.mdl`'s laneList (4), the depot's edges (2), every `constructionutil.addEdges` call (always exactly 2 entries per input segment) -- all even, always. The real structure is PAIRS of (segment-start, segment-end) per straight run, not N unique connected points forming one polyline with a closing duplicate at the end. Connected segments simply repeat the same coordinate at their shared point rather than deduplicating it into a single shared entry -- Decision 90's "closing sentinel" reading of a trivial 1-segment (2-node) example never actually tested against a multi-stop case, and turned out to describe the coincidence of a single segment, not a real convention.

### Decision

Rewrote the lane as 3 explicit 2-point segments (gate→stop1, stop1→stop2, stop2→stop3) = 6 node entries, always even. Restored the third "weight" element (3) on each node entry, matching every real reference exactly -- it was dropped by accident while fixing the count, not a deliberate change. Updated `terminals`' `vehicleNode` indices to 1, 3, 5 (0-based) -- the "arrival" entry of each stop's incoming segment.

### Consequence

**Live-confirmed the node-count fix worked** -- no more fatal crash. Placement now failed with a much gentler, non-fatal "Invalid terminals" validation message instead. Nothing about it appeared in the live game log, unlike every previous crash tonight.

## Decision 101 — Used ModelEditor's own VALIDATE feature to isolate the fault to the `.con` side, not the `.mdl`; removed an unnecessary `terminalGroups` layer

### What happened

With no log detail available for "Invalid terminals," used ModelEditor's own **VALIDATE** button on `epod_truck_distribution_1.mdl` directly -- returned "No errors!", and the lane/terminal data rendered visibly correct in the 3D viewport (a clean path through all 3 terminal markers, matching the intended layout exactly). This conclusively isolates the fault to `epod_truck_park.con`'s `terminalGroups`/`stations` wiring, not the model's own `transportNetworkProvider` data.

### Reason

Re-read the real Warehouse mod's ACTIVE code again, specifically checking whether it uses `terminalGroups` at all (not just how it's shaped, which is what Decision 99 checked) -- it doesn't. The real, working, currently-used code skips `result.terminalGroups` entirely and has `result.stations[].terminals` reference the placed models' own terminal indices directly (`{0,1,...,7}` for its 8 placed platform models, each contributing one terminal). A `terminalGroups` block DOES exist in that same file, but fully commented out -- an abandoned earlier approach, not what actually ships. Decision 99 built on the wiki's description of `terminalGroups` as if it were required, without checking whether the one real reference that has working terminals actually uses it.

### Decision

Removed `result.terminalGroups` from `epod_truck_park.con` entirely. `result.stations[1].terminals` now references the `.mdl`'s own 3 terminals directly by index (`{0, 1, 2}`), matching the real active Warehouse mod pattern exactly rather than the more indirect (and apparently unused) mechanism the wiki describes.

### Consequence

**Live-confirmed "Invalid terminals" persisted** even after removing `terminalGroups` -- the stations wiring wasn't the (whole) problem.

## Decision 102 — Added a second, CARGO-tagged laneList alongside the existing TRUCK lane

### What happened

"Invalid terminals" continued with no new log detail. Re-examined `dsd_road_station1_platform0.mdl` (the real, confirmed-working `STREET_STATION_CARGO`-type terminal model) specifically for how many laneLists it has, not just its terminal/node shape -- it has TWO: one tagged `{"TRUCK","TRAM","ELECTRIC_TRAM"}` (the driving lane) and a separate one tagged `{"CARGO"}` (offset from the driving lane, spanning the platform). Our `.mdl` only had the driving lane.

### Decision

Added a second `laneLists` entry tagged `transportModes = {"CARGO"}`, positioned a few meters east of the driving lane (x=-27, still within the real 6m gate width) and spanning the same 3 terminal stops. Doesn't need to reach the gate itself, only cover the stop range, matching how platform0.mdl's own CARGO lane is scoped to just the platform length, not the full approach.

### Consequence

**Live-confirmed "Invalid terminals" persisted** even with a real CARGO-tagged lane added -- that wasn't the (whole) cause either.

## Decision 103 — Corrected Decision 101's wrong turn: `stations[].terminals` really does reference `terminalGroups` ids, not raw model-terminal indices; restored `terminalGroups`

### What happened

Two fixes in a row (Decisions 101, 102) failed to clear "Invalid terminals." Rather than guess a third time, re-fetched the wiki with a narrower, more targeted question this time (the exact required shape of `result.stations`) instead of relying on the earlier general research pass. It is unambiguous: "`terminals` is a list of terminalGroup ids ... fetched in the order of the groups in `result.terminalGroups`."

### Reason

Decision 101 removed `terminalGroups` based on the real Warehouse mod's shorthand (`stations.terminals = {0,1,...,7}` with no `terminalGroups` defined at all), concluding that pattern meant `stations.terminals` could reference raw model-terminal indices directly. That was the wrong inference -- that mod almost certainly works because omitting `terminalGroups` with exactly ONE terminal per placed model (8 models, 8 terminals total) happens to auto-generate matching group ids 1:1, coincidentally producing the same numbers either way. With ONE model contributing THREE terminals, this project's case doesn't fit that same coincidence. Also worth noting for the record: Decision 99's original `terminalGroups` version was never actually tested against "Invalid terminals" at all -- every attempt with it hit the unrelated `.mdl` node-count crash (fixed in Decision 100) before this message could ever appear, so Decision 101 was reacting to an untested assumption, not a confirmed failure of `terminalGroups` itself.

### Decision

Restored `result.terminalGroups` (3 groups, each `{terminals={{0,i}}}`, matching Decision 99's original, wiki-correct shape exactly). Kept Decision 100's node-count fix and Decision 102's CARGO lane addition, both still independently reasoned and not implicated by this specific error.

### Consequence

Not yet live-tested. This reinstates the very first terminalGroups attempt now that the two things that were genuinely blocking it (the node-count crash, and never getting far enough to test this specific piece) are resolved.

## Decision 104 — Strategic pivot on the parking-lot/depot idea: use a real, working truck depot construction (not hand-authored terminal metadata) and build the behavior in Lua instead

### What happened

After Decisions 99-103's repeated "Invalid terminals" failures (crash fixed, node-count fixed, terminalGroups shape corrected against explicit wiki wording -- still invalid, with zero log detail to work from each time), player proposed a different approach: stop hand-authoring the native `transportNetworkProvider`/terminal system entirely. Instead, use a real, already-working truck depot/station construction as the physical building (the already-installed "Warehouse" mod, Workshop 2152226924, is literally a configurable large truck stop -- up to 8 platforms, up to 3600+ shared capacity -- directly answering the player's own "is there a mod with a massive truck stop" question), and build "Central Truck Depot" designation + inter-depot vehicle linking entirely in this project's own Lua game-script layer instead.

### Reason

This sidesteps the exact wall hit repeatedly tonight -- the native construction terminal-validation system is undocumented past a few wiki sentences, gives no log detail on failure, and has needed 9+ live-tested attempts just to get the ROAD connection working, before terminals were even reachable. The Lua game-script layer, by contrast, is this project's proven strength -- `hub_registry.lua`'s pattern (a simple per-entity enabled/disabled registry with a GUI toggle) and `dispatcher.lua`'s pattern (hold -> setLine -> release vehicle reassignment) already solve the two real mechanisms this idea needs: designating a depot, and moving vehicles to/from it. No custom terminal geometry is needed at all if the physical depot is a real, already-functional construction.

### Decision

Deferred as the plan for a future session, not started tonight given how long the construction-modding thread already ran. Shape agreed: (1) a new small registry (mirroring `hub_registry.lua`) letting a player select a real depot/station construction and mark it "Central Truck Depot"; (2) vehicle linking logic (mirroring `dispatcher.lua`'s proven safe move pattern) that assigns/reassigns vehicles between depots as needed; (3) the physical building is a real, existing construction (the Warehouse mod's, or any other real depot/station) -- not `epod_truck_park.con`, which stays as tonight's research artifact, not a production piece.

### Consequence

`epod_truck_park.con`/`epod_truck_distribution_1.mdl`'s outstanding "Invalid terminals" issue is left unresolved and de-prioritized, not abandoned as a dead end -- the real, hard-won pipeline knowledge from tonight (Blender->FBX->ModelEditor, ground fitting, the `{position,tangentVector}` edge format, 0-based indexing, `constructionutil.addEdges`) remains valid and reusable if custom construction work is picked up again later; only the terminal/station layer specifically hit a wall.

## Appendix — open runtime-verification items

The following items are design decisions that require runtime verification before they can be confirmed:

- whether vehicle reassignment can be done safely,
- whether a vehicle can be safely reassigned across lines while still carrying loaded cargo (new, from Decision 18) — **still not rigorously confirmed, but no longer via a dedicated test.** The single-vehicle diagnostic that used to check this (`route_injector.runLoadedVehicleReassignmentTest`) was removed once Decision 20/21's real Stage 2/3 runs became the stronger evidence: dozens of real vehicles reassigned across multiple live sessions, all reporting healthy in-game behavior afterward (real cargo flowing, real profit, no reported stranded/lost trucks). That is meaningfully better evidence than the old test's single-vehicle, line-scoped cargo count ever produced — its first run was genuinely inconclusive (587 cargo entities on a 50-vehicle line, unchanged before/after, which proves nothing about one vehicle's share) — but it is still not a clean, itemized before/after account of one vehicle's specific cargo, so this remains open rather than fully closed.
- whether persistent managed lines are required for stable cargo flow,
- whether refresh cost (`vehicles.getManagedLinesForStation` + `demand.scan`'s game-wide `SIM_ENTITY_AT_TERMINAL` walk, run once per managed line every ~120 `guiUpdate` ticks) stays acceptable at late-game entity counts — hundreds of trucks, many in-transit cargo entities, possibly multiple Distribution Centres. Raised live, not yet profiled against a real late-game save; see `IDEAS.md`'s "Refresh Cost at Late-Game Scale" for the full trace of what actually runs and where the likely cost is concentrated,
- whether demand-weighted terminal sharing (assigning the lowest-demand managed lines to double up on a terminal once dedicated terminals run out) is worth building on top of the now-confirmed terminal-write capability — see `IDEAS.md`'s "Demand-Weighted Terminal Sharing",
- ~~whether the game exposes compatible cargo types and capacities reliably~~ — **resolved, Decision 27**: `allCapacities` genuinely discriminates between vehicle types, live-confirmed across a 99-vehicle fleet,
- whether a standby pool can be modelled cleanly through depot or line state,
- whether a capacity-1 "sentinel/service" vehicle can register and sustain cargo demand the same way a normal-capacity vehicle does, and specifically whether it can register demand for multiple simultaneous cargo types at one destination or only the type it happens to carry (new, from Decision 18 — general TF2 knowledge suggests capacity does not gate demand registration, but this has not been confirmed in this save),
- whether the mod can persist player state (e.g. managed-stop selections) across a save/reload — **resolved as of Decision 24**: the mechanism (`io.open`-based file I/O) is confirmed working, but no real state has been built on it yet, and a proper per-savegame file path is still needed,
- whether multiple Distribution Centres can safely share trucks,
- whether inter-DC cargo transfer can work with the base game's cargo routing,
- whether waiting-cost discounts occur for genuine terminal waits,
- whether physical yard and reverse-in concepts are viable with custom paths and visual behaviour,
- and how much live state the API exposes without adverse side effects.

These are not omissions; they are deliberate research gates.
