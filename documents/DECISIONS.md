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
