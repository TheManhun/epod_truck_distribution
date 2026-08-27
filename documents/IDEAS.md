## IDEAS.md Maintenance Rule

This file contains **OPEN ideas only**.

When an idea reaches a definite outcome, it must be removed from `IDEAS.md`.

- **Implemented and successfully tested** → record the result in `DECISIONS.md` and update `PROGRESS.md`, then REMOVE it from `IDEAS.md`.
- **Tested and failed** → record the useful evidence/reason in `DECISIONS.md` if appropriate, then REMOVE it from `IDEAS.md`.
- **Rejected / deliberately abandoned** → record the decision in `DECISIONS.md` if it is important enough to prevent the idea being reconsidered later, then REMOVE it from `IDEAS.md`.
- **Partially implemented or still has unresolved questions** → KEEP it in `IDEAS.md`, but trim completed portions and leave only the unresolved work.

### Core Rule

**If there is nothing left to decide, prove, test or build, it does not belong in IDEAS.md.**

`IDEAS.md` = open possibilities and unresolved work.  
`DECISIONS.md` = conclusions and evidence.  
`PROGRESS.md` = what currently exists and works.
_______________________________________________________________________________________________________________________________

## Distance/Cycle-Time-Aware Truck Allocation

### Origin

Raised live: the Planner currently sizes a line's target truck count purely off waiting cargo, with no idea how long a truck actually takes to do the round trip. Two lines showing equal waiting cargo could have very different real needs if one route is much longer — a long round trip clears less waiting cargo per truck per hour than a short one.

### The idea

Measure a line's real round-trip cycle time (departure from the hub to next departure, including load/unload — the natural loop every vehicle already does) and factor it into the target allocation: a longer cycle time means each truck contributes less throughput, so the line needs more trucks to clear the same waiting cargo. Two measurement paths worth checking, cheaper one first:
1. Check whether a `LINE` entity already exposes a round-trip/frequency statistic directly (TF2's own LINE STATISTICS panel shows frequency-like numbers, so plausible) — a one-off research dump is already queued for this.
2. If not, measure it empirically: timestamp a vehicle's natural "departed the hub stop" moment, then the next time it departs again — the gap is a real, observed cycle time, no distance data needed at all.

### The trap already caught — a real design constraint, not just a caveat

**Live-caught before any code was written**: naively reacting to *current* round-trip time creates a feedback loop. A traffic jam slows the round trip → the Planner reads that as "needs more trucks" → adding trucks to an already-congested route makes the jam worse → the round trip gets even slower → the Planner adds still more trucks. This is a real, self-reinforcing failure mode, not a hypothetical — the same class of problem (an automated system reacting to a signal it can itself worsen) as `IDEAS.md`'s own "Terminal Assignment Stability" flapping concern, one level more dangerous since it compounds rather than just oscillates.

**Refined design, worked through further in the same conversation** — cleaner than an initial "measure once early and freeze" idea, because it doesn't depend on guessing when a "safe" measurement window is:

- **Separate route requirement from route health.** Learn a per-line *baseline* cycle time from real completed trips — a rolling median biased toward the fastest/healthiest recent trips, not a plain average, so one bad traffic-jam trip can't drag the baseline down (and a temporary jam can't get relearned as "normal" if it persists — deliberately resistant to exactly the kind of slow creep a naive rolling average would fall for). Compare *recent* cycle time against that baseline to classify a line as healthy / congested / severely congested.
- **Hard policy rule, not just a timing trick**: a line's fleet size may only ever grow because of *demand* (real waiting cargo). A slower round-trip time is never itself a reason to add trucks — it can only ever justify *holding* the current fleet steady (a congested line that demand-math alone says needs +6 trucks should hold, not grow, until the congestion clears) or flagging the line as network-bottlenecked rather than fleet-starved.
- **Cross-check with actual throughput** (deliveries completed per period), not just cycle time — if a line's trucks are running mostly full but completing fewer trips over time, that's a real vehicle-count-independent bottleneck (the road/station itself), not a sign the line needs more capacity. This distinguishes "genuinely needs more trucks" (demand rising, trip time near baseline, throughput scaling normally) from "already has enough capacity, something else is the ceiling."
- Any real fleet-size change this system does eventually make should stay small and incremental, the same `MAX_MOVES_PER_RUN`-style philosophy already proven in `dispatcher.lua` — observe the result of a small change before making another, never a large jump off one calculation.

### What's actually confirmed vs. still a story

**Confirmed**: nothing yet — this is pre-research. The one-off `LINE` entity dump (path 1 above) has been queued but not yet run.

**Not yet confirmed**: whether TF2 exposes a usable cycle-time/frequency field on `LINE` at all; if not, whether the empirical departure-timestamp approach (path 2) is practical to build without adding meaningful per-tick tracking overhead. Also open: what "recent" window and what threshold above baseline should count as "congested" — needs live data, not a guessed number, matching this project's own established discipline for every other threshold in `dispatcher.lua`.

### If it does pan out

A genuine refinement to `planner.lua`'s target-allocation math, on top of the already-proven demand-weighted apportionment (Decisions 29/30) — not a replacement for it. Must be built with the "trip time can only hold or flag, never grow" policy rule from the start, not bolted on as an afterthought once a live-reactive version has already been tried and found to misbehave. Could also surface a genuinely useful player-facing signal on its own — "this line has enough trucks, the road is the real bottleneck" is a diagnosis DD can make that the player currently can't get anywhere else.

## Cargo-Type-Aware Allocation for Shared Multi-Cargo Lines

### Origin

Raised live: a hub feeding a two-input factory (steel needs coal + iron) showed one shared line sitting at 261 waiting cargo -- 226 of one type, only 35 of the other -- with just 1 truck servicing it. The bigger stockpile dominates a truck's limited capacity every time it loads, so the scarcer input keeps getting proportionally squeezed out trip after trip, independent of whether the factory actually needs them in anything like equal amounts. Player's own framing: "the line fills with iron, the coal can't fit, so it's unbalanced."

### The idea

Today's allocation math (`planner.calculateTargetAllocation`/`fleet_allocator`) only ever works from one combined `waiting` total per LINE -- it has no concept that a single stop can produce multiple cargo types competing for the same truck capacity. The player's proposal: investigate the real per-destination timing for each cargo type specifically -- how long it actually takes to gather/deliver a given amount of coal versus iron at this stop -- and use that to work out the right number of trucks to throw at each, rather than treating the line as one undifferentiated demand number.

Worth noting this isn't a data-visibility gap -- `demand.scan`'s per-destination `cargoTypes` breakdown (already used by tonight's new CARGO tab, and by the old panel's own waiting-cargo readout) already reports the exact per-type split live. The gap is that nothing downstream of that data point currently uses the breakdown for an actual allocation DECISION -- it's display-only today.

### Open questions -- nothing here confirmed yet

- ~~Does TF2 expose a factory's *required* input ratio anywhere queryable~~ -- **promising real lead found**, not yet confirmed in this project. The installed "AI Builder" mod (Steam Workshop 2820656841, a mature, 16-version, 25,000+ line mod) has real, working code for exactly this in its own `mod.lua`: an `addModifier("loadConstruction", ...)` hook that, for any construction with `data.type == "INDUSTRY"`, calls `data.updateFn(params)` and reads back `result.rule.input`/`result.rule.output`/`result.rule.capacity`/`result.stocks` -- a genuine production recipe, not inferred. The same mod's own `usefulcommands.txt` (hand-collected API notes) also confirms `api.res.constructionRep.getAll()`/`.get(i)` is a real, directly-queryable resource registry -- same family as `api.res.cargoTypeRep`, which this project's own `demand.lua` already uses successfully -- suggesting industry construction data might be reachable at ordinary runtime, not only through a `mod.lua` load-time hook. Two things remain genuinely unconfirmed before this is buildable: whether `constructionRep.get(i)` exposes the same `.updateFn`/recipe shape the load-time hook uses, and whether a LIVE industry entity carries a readable reference back to which construction it was built from (needed to go from "steel mill entity 88231" to "look up its recipe"). Worth a real, dedicated research pass (a `dumpEntityInfo`-style probe against a real industry entity and against `constructionRep`) before building anything on it -- but this is the strongest lead this question has had all session.
- How would a truck's per-cargo-type load actually get attributed on a shared multi-cargo line -- `vehicles.getCargoLoad` gives a per-vehicle breakdown already, so the raw mechanism likely exists; what's unproven is turning that into a real allocation signal without adding meaningful per-tick overhead.
- Same trap this project has already been burned by once (see "Distance/Cycle-Time-Aware Truck Allocation" above): a naive reactive version that keeps chasing whichever cargo type currently looks most starved risks overcorrecting and just flipping the imbalance the other way. Needs the same "baseline vs. recent, hold don't oscillate" discipline, not a first-instinct implementation.
- Whether splitting the two cargo types onto physically separate dedicated lines (if the real station topology even allows it) solves this more simply than any new allocation math would -- worth ruling out live before building anything.
- **New real example, 250-year save (for later, not yet investigated)**: player's own TF2 Vehicle Manager screenshot of a mixed-cargo line ("Barking to Langport Goods Tra[nsit]", 7 vehicles) showed visually distinct truck models -- some clearly flatbeds carrying only stone/aggregate-type cargo, others standard box trailers for general goods -- sharing the SAME line. If some of this line's own trucks are individually restricted to a subset of what the line actually carries (the same `allCapacities`-restricts-some-vehicles fact Decision 27 already confirmed fleet-wide, just not yet checked per-line), that's a real, vehicle-level cause of the exact imbalance this idea already investigates -- distinct from the destination-side "bigger stockpile dominates capacity" explanation above, and worth checking before assuming the fix is allocation math rather than restricted vehicles sitting on a line they can't fully service.

### Update -- real evidence gathered, two mechanisms explored and superseded

The read-only Cargo Balance Inspector (Decisions 77/78) confirmed this is real, not speculative: Goole Steel Plant showed Iron ore waiting=171 against Coal waiting=44 (~4:1), with Coal's all-time delivered total sitting at 0 despite Iron's 132 -- coal effectively never arrives there in practice.

Two mechanisms for actually separating the cargo were considered and both rejected, for concrete reasons rather than just caution:
- **Two lines with the same stops, cargo-filtered per stop** -- rejected. TF2 routes cargo by stops + vehicle capacity, not by line name/identity, so two identically-stopped lines wouldn't separate anything without an actual per-stop cargo filter. That filter lives in the same undocumented `Line.Stop` territory (`alternativeTerminals`) that already crashed this game twice (Decisions 56/57).
- **Two lines, separated by using cargo-restricted vehicles instead of a filter** -- rejected for THIS player's fleet specifically: confirmed live that the real trucks in play can carry both coal and iron (no naturally-restricted vehicles owned), so this mechanism has nothing to restrict with. Would need the player to specifically buy specialized (era-appropriate) single-cargo vehicles, which the mod deliberately never does on its own (Decision 4/8).

See "Point-to-Point Source Runners" below for the mechanism now considered the leading candidate instead of either of these.

### Update -- comparative signal promoted from DEBUG report into the live CARGO tab (Decision 79)

The same waiting-vs-all-time-unloaded comparison the Cargo Balance Inspector proved correct now also renders directly in the DD Central Manager's CARGO tab (no DEBUG mode needed) -- one section per multi-cargo destination, worst-served type flagged, via a new shared `demand.buildDestinationCargoRows` helper used by both the tab and the original report. Still read-only/display-only -- nothing here feeds an allocation decision yet, that's still the open question above.

## Point-to-Point Source Runners ("Steel Runners") -- Mine-to-Mill-to-Hub Loops

### Origin

Direct follow-on from the cargo-balance problem above, once both "two lines + filter" and "two lines + restricted vehicles" were ruled out. Player's proposal: instead of trying to separate cargo at a shared hub-fed line, send trucks on a direct loop from the actual SOURCE (e.g. a coal mine) straight to the destination (the steel mill), dropping the raw material there, picking up the mill's own output (steel) in return, and carrying that on to the distribution hub. A separate loop does the same for iron ore from the iron mine.

### Why this is a genuinely better mechanism, not just a different one

A direct `Coal Mine <-> Steel Mill` line naturally has only coal available to pick up at the mine end -- there's nothing else physically produced there for a truck to load instead. Separation happens as a mechanical consequence of what each end actually produces, not because anything was configured to enforce it. No cargo filter, no vehicle restriction, no undocumented native field, no risk of repeating Decisions 56/57. This is a materially safer mechanism than either of the two rejected above.

It also incidentally solves a second problem raised in the same conversation: mines not being physically near the hub that's supposed to serve the mill they feed. A direct mine-to-mill loop doesn't route through a hub's own local catchment at all, so it doesn't matter which hub's "territory" the mine sits in.

### What this actually requires -- a real, separate piece of work, not a quick addition

- **A new line topology.** Everything this mod currently manages (Split, Assign & Balance, terminal spreading, the Planner's target allocation) assumes a 2-stop `Hub <-> Destination` line. A mine-mill-hub loop is a 3+-stop chain shaped completely differently -- none of the existing pipeline logic applies to it directly.
- **Knowing which mine feeds which mill.** Nothing in this mod (or, per live research, in TF2's own scripting API as currently understood) confirms a queryable mine-to-mill relationship. The catchment-detection idea (`SIM_BUILDING`, `SIM_CARGO.targetEntity`/`sourceEntity` -- the latter already confirmed real, Decision 27-adjacent) could eventually discover this automatically, but that's unconfirmed, separate research. The realistic first version has the PLAYER designate "this mine feeds this mill" explicitly -- consistent with this mod's own founding principle (Decision 2: player defines the network, the mod dispatches within it), not a regression from wanting full automation.
- **A new balancing question**: once real mine-to-mill loops exist, deciding how many trucks each loop gets (coal loop vs. iron loop) is the SAME demand-weighted allocation problem the Planner already solves for ordinary hub lines -- just needs applying to this new line shape once it exists.

### Status

Not started. A real, well-reasoned direction with a genuinely lower risk profile than the alternatives already tried tonight, but it's new scope (a second line topology, a new player-facing "designate a source" step) rather than an extension of the existing hub model. Worth a deliberate design/build session on its own, not squeezed in alongside other work.

## Scope Split: "City Distribution Centre" (v1) vs. a Future "Production Distribution Centre"

### Origin

Raised live, half-joking but genuinely sound, right after the cargo-balance/Steel Runners discussion above: rather than solving multi-input production-recipe balancing (coal+iron for steel, etc.) inside this mod, market and scope v1 as a **City Distribution Centre** -- managing only finished-goods delivery to towns. The much harder recipe-balance problem, and any Steel-Runners-style mine-to-mill mechanism, becomes a separate, later **Production Distribution Centre** concept instead of something v1 needs to solve to be useful.

### Why this is a real option, not just a name change

Towns don't have the "must receive the right ratio of N inputs before anything happens" production-chain dynamic that industries do -- a town just wants deliveries; there's no equivalent of "coal starves the steel mill" between the cargo types a town consumes. Scoping to town-only destinations means the entire cargo-balance problem line of work from tonight (Cargo Balance Inspector, the two rejected separation mechanisms, Steel Runners) stops being a v1 blocker at all -- it's deferred to a genuinely separate future effort with its own name and its own scope, not something jammed into the existing hub model. It also directly answers this session's own "this is becoming Line Manager" scope-creep concern (see the Steel Runners idea above) with a clean, narrow identity instead of an ever-expanding one.

### What "reject raw materials" would actually take

Not just branding -- a real, buildable filter: the mod would need to tell a town-serving destination apart from an industry-serving one, so a Split/Distribution-Hub setup could deliberately skip (or warn about) an industrial destination rather than silently mismanaging it the way it does today. This is the same detection question as the catchment/`SIM_BUILDING` research idea already recorded elsewhere in this file -- there, it was for INCLUDING nearby industries; here, the same capability would be used for EXCLUDING them. Nothing about this distinction is confirmed yet (no live check has been done for "is this destination a town or an industry").

### Status

Not decided, not started -- raised as a genuine strategic option, not yet committed to. Worth weighing deliberately (possibly a fresh conversation, not squeezed into a late-night wind-down) rather than defaulted into.

### If it does pan out

A real, structural refinement to the Planner specifically for hubs with multi-input industries -- distinct from the existing distance/cycle-time idea (which is about a single line's overall throughput) but likely shares infrastructure with it once cycle-time-per-cargo-type measurement exists.

## Fleet Utilization Display (%)

### Origin

Raised live while stress-testing the newly-wired automatic Dispatcher (Decision 34) — the player found it hard to keep the hub's demand full enough to give the Dispatcher something real to do, and had to deliberately add more deliveries to make the test interesting.

### The idea

A simple utilization percentage per hub (or per line): how full the current fleet is relative to what it actually needs. 100% (or over) signals "add more trucks"; well under 100% signals "you could sell some." Cheap to compute — `planner.lua`'s `calculateTargetAllocation` already produces `currentVehicleCount` and `targetVehicleCount` per line; utilization is just `current / target` (or its inverse, framed as surplus).

### What's actually confirmed vs. still a story

**Confirmed**: the underlying numbers already exist and are live-verified correct (Decisions 29/30) — no new data collection needed, just a display/formatting layer.

**Not yet decided**: what "target" should mean for this specific display once the cargo-profile floor (Decision 30) and any future per-vehicle-type sub-pooling are in the mix — a floor-boosted target isn't quite the same thing as "true need," so a naive `current/target` could read as under-utilized even when a line is genuinely fine. Where this lives (hub-level single number vs. per-line breakdown) and whether it belongs in the existing panel or a future overview window (`IDEAS.md`'s "Distribution Network Overview") is also undecided.

### If it does pan out

A small, self-contained addition on top of already-proven data — no dependency on anything not already built. Good candidate for the eventual GUI polish pass (`IDEAS.md`'s "Final GUI Research and Cleanup Phase") rather than urgent now.

## Vehicle Identity Naming and Fleet Colour-Coding

### Origin

Raised alongside the auto-redistribute toggle discussion, as a natural extension once trucks start dynamically moving between services under one hub's pooled fleet: a truck could go from Queens Road → Grain → The Grove, and visually it would help to see it's still part of the same Hendon East fleet the whole time.

### The idea

Rename DD-managed vehicles to reflect their home hub rather than their current service — e.g. `● Hendon East` rather than naming after whichever line they happen to be on right now, since that would go stale the moment the vehicle gets reassigned (the exact lesson already learned the hard way from the `●` line-name situation, Decision 26 — name the OWNER, not the current assignment). A per-hub fleet colour was also proposed, purely optional and defaulting to "player controlled" (DD never touches colour unless explicitly told to), since players often colour-code their own networks deliberately and DD silently recolouring them would be unwelcome.

Both would need to be genuinely optional toggles, off by default for colour, and the identity itself must remain entity-ID-based (already true via `managed_registry.lua`) regardless of what any player does to the name or colour afterward.

### Naming — built

**Live-confirmed and built.** `setName` works on a vehicle entity (`route_injector.testVehicleRenameAndColor`, verified by re-reading the entity, not just the command's success flag — see `COMMANDS.md`). `fleet_naming.lua`'s `M.renameFleetToHubIdentity`, wired to the "Rename Fleet to Hub Identity (DEBUG)" button, renames every managed vehicle at the selected hub to `● <Hub Name> - Fleet (N)` — a plain ASCII hyphen, not the em-dash originally proposed in chat, since that glyph has never been tested in TF2's fonts and this renames real, persistent vehicles rather than a disposable test (the same discipline that picked `●`/`↔` for line names over the untested `◆ ■ ►`). Player-triggered only, never automatic, per Decision 4.

**Live-confirmed at real scale too**: run against a real ~90+ vehicle fleet, visible correctly in TF2's own vehicle list. One cosmetic quirk was noticed and fixed same-session: the vehicle list sorts by name as a plain string, so `Fleet (10)`-`(19)` were landing before `Fleet (2)`. Fixed by dropping the parentheses and zero-padding the number to match the fleet's own size (`Fleet 001`, `Fleet 118`, etc. — width computed from the actual vehicle count, so small fleets don't carry pointless leading zeros).

**Open**: numbering is sequential by current discovery order each time it runs, not a stable per-vehicle ID — re-running after the fleet changes size will renumber everyone. No evidence yet that this matters in practice; a persisted stable number (same `io.open` pattern as `managed_registry.lua`) is possible later if it turns out to.

### Colour — confirmed working, still no real feature built

**Live-confirmed, by accident.** No colour field exists on a vehicle to re-read programmatically, so the command's own `RESULT: true` wasn't full proof by itself — but the test deliberately never restores colour (nothing to restore to), so the one test vehicle was left magenta/purple. The player spotted it running around the map, unprompted, real minutes later, and correctly traced it back to the test. Genuine visual confirmation: `setColor` works on a vehicle entity. No real "per-hub fleet colour" feature has been built yet — only the disposable single-vehicle test exists. If picked back up: a genuinely optional toggle, defaulting to "player controlled" (DD never touches colour unless explicitly told to), matching the reasoning already agreed on.

### If it does pan out

Cosmetic/UX polish, not core plumbing — belongs in the same later bucket as `IDEAS.md`'s "Final GUI Research and Cleanup Phase," after the Planner/Dispatcher work is functional, not alongside it. First concrete step if picked back up: a single throwaway live test of `setName` against one vehicle entity, mirroring how every other command in `COMMANDS.md` earned its "confirmed" tier.


# TF2 Distribution Manager — Ideas / Backlog

Speculative or partially-explored ideas that are **not** part of the current design path (see `DECISIONS.md` Decisions 17–18 and `ROADMAP.md`) and are **not** committed to any stage. Nothing in this file is settled architecture — it exists so an idea worth remembering doesn't either get lost or get built on faith. Per Decision 12's feature freeze, new ideas discovered during development land here rather than silently expanding current implementation scope.

An idea graduates out of this file into `DECISIONS.md` only once it's been checked against real behavior, not just reasoned about.

## Connected Distribution Network (multi-line hub, pressure-based, direction-agnostic)

**Revision note**: this idea originally framed lines as INBOUND or OUTBOUND (see "Superseded framing" below). That framing has been dropped — not simplified, corrected. A TF2 truck line is a loop that serves every stop on each pass; a line isn't structurally inbound or outbound, individual stops just carry varying cargo pressure in whatever direction the game's own demand happens to be routing at a given moment. A line that mostly carries grain toward a hub today could carry something else the other way later if the network changes. Labeling a whole line by direction would have imposed a static category on something genuinely dynamic — and would have meant shipping a UI claim (`INBOUND`/`OUTBOUND` badges) that was never actually verified. The corrected model:

```text
CONNECTED LINE
```

...and the brain (once it exists) reasons about cargo pressure per stop and per cargo type along that line, not a direction label on the line as a whole. This also means the eventual dispatch brain should be framed as "this line has X units of unmet transport pressure across its connected stops and cargo types," not "this is an inbound line, allocate for inbound demand" — which scales better toward the multi-hub idea below too, since any line in a Factory ↔ DC ↔ DC ↔ Town chain may carry useful cargo in either direction.

**Consequence for `loadMode`**: dropping direction as a line-level label means `loadMode` is no longer a gate for the *display* layer specifically — `demand.scan()` already reports "cargo currently waiting somewhere on this line, destined for stop X," which is a valid pressure signal per stop regardless of physical direction, and its correctness doesn't depend on `loadMode`. It may still matter later once an actual dispatch brain has to decide whether a truck can load/unload at a given stop — that's a Decision 18 concern for when reassignment logic exists, not a blocker for building the display panel now.

### Origin

Discovered by accident: `getManagedLinesForStation` matches *any* road-truck line with a stop sharing the selected station's `stationGroup`. This correctly picked up a second, unrelated-looking line ("Grain," 20 trucks, destined for "Barrow-in-Furness Transfer") alongside the intended distribution line ("Truck - CD - Hendon," 50 trucks) at Hendon East. Verified directly against the code (not inherited from an external claim) — this is a genuine stationGroup-equality match, not a name or proximity heuristic bug.

### The idea

A managed hub isn't necessarily just its main delivery line — any line physically touching the hub's station is part of a connected network. If demand pressure can be read across every connected line and stop, the dispatch brain could eventually reason about the whole network rather than just one line's demand:

```text
Hendon East
Connected Lines: 2
Connected Vehicles: 70
Total Waiting: 502

LINE / STOP                  VEHICLES   WAITING

Grain                           20          0
  Barrow-in-Furness Transfer                0

Truck - CD - Hendon             50        502
  Queens Road                             104
  Alexander Road                          302
  The Grove                                96
  Park Avenue                               0
  Highfield Road                            0
```

...and eventually reason about scarcity/surplus across the whole thing, expressed as "this line has X units of unmet transport pressure across its connected stops and cargo types," not a direction label on the line. A further extension of the same idea: multiple nearby Distribution Centres sharing a regional truck pool, with the brain recommending transfers between hubs when one is under pressure and another is idle — this scales better under the pressure model too, since any line in a Factory ↔ DC ↔ DC ↔ Town chain may carry useful cargo in either direction depending on what the network needs at the time.

### What's actually confirmed vs. still a story

**Confirmed** (checked directly against the code):
- The match is structural (`stationGroup` equality across every stop on every road-truck line), not a bug.
- `getManagedLinesForStation`/`managedTruckCount` currently pool every matched line's trucks into one number — a real correctness gap if this number ever feeds dispatch logic (`config.LIVE_DISPATCH_ENABLED = true` already exists, even though nothing currently uses managed-line data to dispatch).
- `demand.scan()` is already being called against the Grain line today (using Hendon East as hub) and already reports its destination-side waiting cargo in the GUI. Its "waiting cargo destined for stop X" semantics are a valid per-stop pressure signal regardless of physical direction, so this is usable as-is for a pressure-based dashboard — no direction classification needed for the display layer.

**Not yet confirmed** (would need real verification before any of this becomes a decision):
- Cargo-type compatibility across connected lines. Grain's line almost certainly carries only `GRAIN`; the other lines carry different cargo types. Two lines sharing a hub are not automatically one fungible truck pool — a truck can only be usefully reassigned between them if it's actually compatible with both. This has not been checked, and matters once actual reassignment (not just display) is being considered.
- Both observed demand numbers (Grain's line and its Barrow-in-Furness stop) have shown `Waiting: 0` in every capture so far — there's no live evidence yet of a scenario where cross-line rebalancing would actually be useful.

### If it does pan out

Worth formalizing as its own roadmap stage (after V1's single-hub dispatch, not instead of it) — treat "touches the station" as "part of the connected network to display," but confirm cargo-type compatibility before treating it as "part of one interchangeable fleet" for actual reassignment. Multi-hub rebalancing is a further, later extension on top of that, not a V1 concern.

## Detect-empty-and-reverse: a Park-stop-free fix for the first-run cargo bug

### Origin

Raised verbally, late in a session, as a possible alternative to the Truck Park mechanism documented in `DECISIONS.md`'s Decision 12 clarification. The underlying problem the Park stop currently works around: reassigning a vehicle to a new line purely via `setLine`, with no intervening real stop arrival, makes the vehicle run its first leg without picking up cargo. The Park stop fixes this by forcing a genuine stop-arrival event before the vehicle continues to its real destination.

### The idea

Instead of routing every reassigned vehicle through a dedicated physical Park stop, let the vehicle depart normally on its first leg after reassignment. Monitor it; the moment it's detected as having left the origin stop while still empty, call `reverseVehicle` on it (already proven, via `vehicles.reverseVehicle` / `api.cmd.make.reverseVehicle`, used in `dispatcher.lua`'s reverse-destination test) to turn it around before it completes a wasted run. If reversing produces the same effect as a genuine arrival, this would remove the need for the Park stop, the injected extra stop in every managed line's topology, and the whole `route_injector.lua` line-rewriting mechanism that exists to insert it.

### What's actually confirmed vs. still a story

**Confirmed** (already proven elsewhere in this codebase):
- `reverseVehicle` is a real, working command — but only proven on a vehicle already **stopped at a terminal** (the Park stop, in the existing test), not on one mid-transit between stops.
- `vehicles.inspect()` can read a vehicle's `state` (`IN_DEPOT` / `EN_ROUTE` / `AT_TERMINAL` / `GOING_TO_DEPOT`), `stopIndex`, `doorsOpen`, and timing fields.
- The underlying bug this targets is real and already documented (Decision 12 clarification).

**Not yet confirmed** (the actual open questions):
- Whether a vehicle's current cargo load (how much it's carrying right now, or that it's carrying nothing) can be read at all — no test in this codebase has read vehicle cargo load live; only stop/line/timing fields have been inspected so far.
- Whether calling `reverseVehicle` on a vehicle that is `EN_ROUTE` (moving, between stops, not at any terminal) has the same effect as calling it on a vehicle already stopped at a terminal. This is the load-bearing assumption and it is genuinely different from what's been tested — the existing proof only covers the stopped case.
- Whether reversing a moving vehicle actually triggers a genuine arrival-equivalent event that fixes the loading bug, or just redirects its travel without the needed side effect, in which case the vehicle would still run its next leg empty too.
- Detection timing: `guiUpdate` polls periodically, not on every simulation tick — needs to reliably catch "just departed, still empty" before the vehicle has covered enough distance that reversing doesn't actually save anything over just letting the run complete.

### If it does pan out

Removes a real piece of structural complexity — no injected Park stop, no dedicated topology hack, one fewer moving part in every managed line. Worth a small, scoped test before touching the real network: reassign one test vehicle, watch its cargo state (once that's readable) immediately after departure, reverse it, and check whether the *next* leg actually loads correctly — the same evidence-first treatment every other idea in this file has gotten, not a replacement for the Park mechanism until it's actually proven to work.


### Empty-Run Recovery / Second-Chance Loading

When a managed truck is travelling **empty**, the Distribution Brain can decide whether completing the empty journey is worthwhile.

* If the **next stop has compatible cargo waiting** for the truck to collect, allow it to continue — the empty trip has a purpose.
* If the next stop has **nothing useful to collect**, but the **previous stop now has compatible cargo waiting**, reverse the truck so it can return and load.
* If neither stop has useful cargo, allow the truck to continue normally.
* Add a short delay after departure (e.g. ~5 seconds) before checking, to avoid interfering with the normal station/loading cycle.
* Limit/restrict repeated reversals so a truck cannot become stuck reversing indefinitely.

This could also solve the **first empty trip after line reassignment** problem without requiring a separate parking stop: if a reassigned truck leaves the Distribution Centre empty but cargo is available behind it, the brain simply reverses it for a second loading opportunity.

**Core rule:** *Empty vehicle + useful work ahead = continue. Empty vehicle + no work ahead + useful work behind = reverse.*

## Terminal Assignment Stability (hysteresis / minimal reassignment)

### Origin

Raised alongside a pasted external proposal, after Decision 22's first live run exposed the pre-existing-occupancy bug (see DECISIONS.md). The proposal's core allocation rule was already what got built; this piece is the part that wasn't: guarding against reassigning terminals too eagerly if this ever runs on a recurring schedule instead of only ever being manually triggered.

### The idea

If terminal assignment is ever re-run automatically (on a timer, or in response to demand changing) rather than only when the player clicks a button, blindly recomputing the full allocation every time could cause lines to bounce between terminals for small, insignificant demand fluctuations — visually disruptive (cargo/vehicles "jumping platforms") for no real benefit. The proposed guard: only reassign when the current layout is "materially" inefficient (some threshold), and even then, make the smallest change that fixes it rather than recomputing everything from scratch; prefer keeping a line where it already is when two placements would be roughly equivalent.

### What's actually confirmed vs. still a story

**Confirmed**: the underlying allocation rule this would sit on top of (demand-ranked, stock-take-aware) is built and real (Decision 22).

**Not yet confirmed — the whole premise of this idea**: whether re-running the allocator repeatedly actually produces visible "flapping" in practice. It has only ever been run twice, both manually triggered by the player clicking a button — there is no recurring/automatic trigger for it yet, so there is no evidence this is a real problem rather than a hypothetical one. Building stability/threshold logic against an unobserved problem would be exactly the kind of unverified assumption Decision 13 exists to prevent.

### If it does pan out

Only relevant once (if) terminal spreading is ever triggered automatically/repeatedly rather than manually. At that point: define what "materially inefficient" means in concrete terms (a load-imbalance threshold between terminals, most likely), and change the allocator to diff against the current assignment and only move lines that are actually out of place, rather than recomputing every line's terminal from scratch each run.

## Demand-Weighted Terminal Sharing (once managed lines outnumber physical terminals)

**Graduated to `DECISIONS.md` Decision 22** (`terminal_allocator.lua`) — built and live-run once, with a real pre-existing-occupancy bug found and fixed (see DECISIONS.md). Left here because the "not yet confirmed" questions below are still genuinely open even though the feature itself now exists.

**ACTIVE AGAIN (Decision 50).** Decision 42 briefly replaced this with a shared-pool model built on `api.cmd.make.setLineStopAlternativeTerminals` — live multi-hub testing confirmed that command doesn't actually exist (every call failed with "attempt to call a nil value"), so `terminal_allocator.lua` was reverted back to exactly this demand-ranked, single-dedicated-terminal-per-line design, now re-confirmed working live on a second hub (Yarm East) alongside everything else fixed that session. This is the real, current implementation again, not a fallback.

### Origin

Raised live immediately after `route_injector.runTerminalAssignmentTest()` confirmed `Line.Stop.terminal` is genuinely writable and the game's own TERMINALS tab agrees (see DECISIONS.md's terminal-assignment entry). Once it's possible to deliberately choose which terminal a line uses, the next question is what to do once there are more managed lines than physical terminals at the hub.

### The idea

Spread as many managed lines onto their own dedicated terminal as there are terminals available (ranked by demand — busiest lines get first claim on a dedicated terminal). Once terminals run out, don't leave the remaining lines to whatever TF2's own default balancing happens to pick — Decision 19 already observed that default behavior isn't reliably demand-aware (two live sessions with unchanged code produced different terminal groupings). Instead, deliberately pair the *lowest*-demand lines together to share a terminal, and keep pairing the next-lowest-demand line onto whichever terminal currently has the least combined demand, so sharing is concentrated where it costs the least (a low-traffic line losing exclusive terminal access matters less than a high-traffic one would).

This is a greedy/bin-packing allocation, not exotic: sort managed lines by current `demand.scan()` waiting total descending, hand out dedicated terminals in that order until the terminal count (read via `stations.dumpStationGroupTerminals`, already proven to return a real per-station terminal container) is exhausted, then assign every remaining line to the currently-lowest-combined-demand terminal.

### What's actually confirmed vs. still a story

**Confirmed**:
- `Line.Stop.terminal` is writable and the change actually sticks, both in the data and visually in-game (DECISIONS.md).
- The UI terminal-number offset (raw value + 1) is known.
- A station's terminal count is readable (`stations.dumpStationGroupTerminals`, already returns a real terminal container — 6 entries for Hendon East in an earlier capture).
- Terminal storage capacity is finite (player-reported, visually confirmed as "100/100" in the TERMINALS tab) — so sharing a terminal is a real tradeoff (both lines' trucks now converge on the same loading bay and the same stock ceiling), not a free way to add capacity.

**Not yet confirmed**:
- What happens with 3+ lines sharing one terminal — does congestion become visually/functionally a real problem, or does TF2 handle it gracefully the way it already handles today's default (unmanaged) sharing?
- Whether writing a terminal index at or beyond the station's actual terminal count errors, clamps, or is silently accepted — matters for making sure the allocation logic never targets a terminal that doesn't exist.
- Whether TF2's own default (no explicit terminal set) balancing is genuinely non-demand-aware or just looked that way from two data points — worth a slightly larger sample before concluding this feature adds real value over doing nothing.

### If it does pan out

A natural extension of the "spread all N managed lines across terminals" work `route_injector.runTerminalAssignmentTest`'s own comments already flag as the next step — this is the fallback for when N exceeds the terminal count, rather than leaving overflow lines to arbitrary default behavior.

## Refresh Cost at Late-Game Scale (hundreds of trucks, multiple Distribution Centres)

### Origin

Raised live as a forward-looking concern, not tied to any specific bug seen so far: "how often are checks being run, when late game you might have hundreds of trucks, even many different dist centres, will it start to lag the entire game."

### The idea

Not a feature — a flag that the current refresh architecture has a real, traceable scaling cost that hasn't been measured against a late-game-sized save, and should be profiled (or redesigned) before this mod is used on one.

Traced through the actual code as it stands today:

- `guiUpdate()` runs at native TF2 GUI-frame frequency (called by the engine itself, not something this mod controls the cadence of). The expensive work inside it is throttled by `AUTO_REFRESH_GUI_UPDATES` (currently 120) — a full refresh only runs once every 120 `guiUpdate` calls, or immediately whenever the player selects a station (`dirty = true`). The real wall-clock interval that 120 calls corresponds to has never actually been measured.
- Each full refresh calls `vehicles.getManagedLinesForStation(stationGroupId)`, which: (a) calls `game.interface.getVehicles({carrier="ROAD"})` once — every road vehicle in the entire game, not just this hub's; (b) iterates `game.interface.getLines()` — every line in the entire game — calling `getVehiclesForLine` on each one to classify it.
- For every managed line found at the focused hub, `demand.scan()` calls `api.engine.forEachEntityWithComponent(callback, SIM_ENTITY_AT_TERMINAL)` — this walks every entity in the *entire game* carrying that component; the filter down to just this line happens inside the callback, not before the walk starts, so the walk itself is unavoidably game-wide. This runs once per managed line, per refresh — cost scales as (managed lines at this hub) × (total in-transit cargo entities game-wide).
- `config.DEBUG` is currently `true`, and while it is, `demand.printReport()` re-runs `M.scan()` a second time for every managed line, every refresh, purely to produce log output — doubling the single most expensive part of the refresh unconditionally.

**Already-in-place mitigation**: the 120-tick throttle, and the fact that only one hub (whichever station is currently GUI-selected) is ever computed at a time — there is no background loop today that evaluates every Distribution Centre regardless of what the player has selected.

**Not yet confirmed / not yet measured**:
- The real wall-clock refresh interval `AUTO_REFRESH_GUI_UPDATES` corresponds to.
- Actual frame-time cost of `demand.scan()`'s entity walk against a save with hundreds of trucks and a realistic amount of in-transit cargo — everything above is architectural reasoning about *what* runs, not a measured cost.
- Whether TF2's Lua API exposes anything more targeted than a full `forEachEntityWithComponent` walk (an event/callback on cargo arrival, for instance) that would avoid the polling-plus-full-walk pattern entirely — no evidence either way has been looked for yet.

### If it does pan out (i.e. profiling confirms this is a real problem)

Concrete directions already visible from the trace above, roughly in order of effort:
1. Turn off `demand.printReport()`'s redundant re-scan outside of active debugging — it currently doubles the cost unconditionally.
2. Cache `buildRoadVehicleIdSet()` and each line's carrier classification between refreshes instead of recomputing game-wide every time, invalidating only when something that could actually change it happens (a line/vehicle change), not on a fixed timer.
3. Investigate whether a more targeted API than a full entity walk exists for cargo-at-terminal state.

This matters most for any future work that goes beyond today's single-hub, GUI-selection-driven model — a background system that autonomously evaluates *every* Distribution Centre on a timer, not just the one currently selected in the panel, would multiply this cost by the number of hubs and needs its own deliberately-scoped, likely incremental/cached design from the start, not an assumption that today's approach naturally extends.

## Player-Set Vehicle Budget (not auto-buy/sell)

### Origin

Raised after `buyVehicle`/`sellVehicle` turned up as real, confirmed commands in the live `api.cmd.make` command dump (`dumpAvailableCommands`, `TECHNICAL_RESEARCH.md`). Their existence being confirmed is not the same as deciding to use them — flagged explicitly by the person raising the idea: "don't want it to Auto."

### The idea

Decision 4 currently reads as an absolute: the mod does not automatically buy or sell vehicles, specifically to avoid becoming "an autonomous economic simulator." This idea is narrower than reopening that — instead of the mod deciding to spend money on its own, the player could set an explicit spending ceiling ("Vehicle Budget") that authorizes the mod to buy/sell *within* that limit, if and when buy/sell logic is ever built. The mod would still never decide *whether* to spend, only ever operate inside a boundary the player deliberately set — closer to a logistics manager working within an approved budget than an AI given a blank check.

### What's actually confirmed vs. still a story

**Confirmed**: `api.cmd.make.buyVehicle(playerEntity, depotEntity, config)` and `api.cmd.make.sellVehicle(vehicleId)` are real, present commands (confirmed in the same live dump that proved `createLine`/`deleteLine`). `buyVehicle`'s exact signature is documented in the same bundled `tf2-api/docs/modules/api.cmd.md` reference, and `LineManager` (workshop mod 2581894757) uses both live in its own `api_helper.lua`.

**Not yet confirmed / not yet decided**: everything about whether and how this fits V1 at all. This is a genuine expansion beyond Decision 4 as currently written, not a loophole in it — Decision 4 is an absolute "does not," and this idea proposes a conditional "may, within player-set limits." It should not be treated as approved scope until that's discussed and, if accepted, written into `DECISIONS.md` as an amendment or a new decision, not assumed from this entry alone.

### If it does pan out

Would only make sense after there's an actual dispatch brain capable of recognizing "this line is chronically under-resourced" in the first place — a budget without a reason to spend it is premature. Worth revisiting once Decision 18's allocation logic exists and is showing real, sustained fleet shortfalls, not before.

## New load suggestion 

When a Truck Station is selected a small popup screen will show with a Single button [click to convert to Distribution Hub]
Then all the create lines, termial allocation and trucks split up happens with one click
Conversion done 
Still has the X close option top right

## X exit
If the Truck Station X is pressed can it also close the popup screen for distribution hub?

## Remove not needed runs display
All the city stops that show <- Henderson East | Waiting : 0  not needed remove them from the list, they will never show more than zero as they are drop off lines. 

## Distribution Network Overview (DD Toolbar Button)

Add a **DD / Dynamic Distribution** button to the main TF2 toolbar.

Clicking it opens a network-wide Distribution Management window showing all compatible truck cargo stations detected in the player's network.

Possible information/actions:

- List all detected truck cargo stations.
- Clearly identify stations currently managed as Distribution Hubs.
- Show basic status for managed hubs, such as:
  - connected services
  - managed vehicles
  - total waiting cargo
- Allow an unmanaged station to be converted into a Distribution Hub with one click.
- Allow the player to open an existing Distribution Hub dashboard.
- Provide an option to remove a station from Distribution Management.
- Removing management should stop automatic control but leave the player's existing lines, vehicles and terminal assignments intact.
- The network window could eventually show warnings such as excessive waiting cargo, insufficient fleet capacity or terminal congestion.

This would provide one central management screen instead of requiring the player to locate and click individual stations on the map.

### Minimal version worth building first

Raised live: rather than the full network-overview window above, the simplest useful version is just a toolbar icon that opens/toggles the *existing* Truck Distribution panel (or the new tabbed GUI once it's ready) -- no new window content, just a way to reach the panel without needing a station selected first. Natural stepping stone toward the fuller network-overview idea above, not a competing design.

### Related but distinct mechanism -- construction-parameter COMBOBOX (real, proven, does NOT apply to this hub picker)

Player noted a real `uiType = "COMBOBOX"` example from wiki documentation (a construction's `params` list entry, e.g. `{key=..., name=_("Post Assets"), uiType="COMBOBOX", values={...}}`) as a possible way to select a Distribution Hub from a list. Worth recording precisely why it doesn't fit this particular need, so the idea isn't lost but also isn't reached for in the wrong place: construction params are STATIC choices fixed at author-time in a `.con` file, resolved once when a NEW construction is placed -- they can't reflect the live, currently-enabled set of Distribution Hubs, which changes at runtime as the player enables/disables them during play. This is the same real mechanism the installed "Warehouse" mod (`dsd_road_station1.con`) uses for its platform-count/street-type dropdowns during this session's parking-lot construction research -- genuinely safe and proven, just for a different kind of choice (build-time construction options, e.g. a future option on the truck park construction itself) than a live in-panel hub picker. The live hub-picker need is already solved a different way: a real `api.gui.comp.ToggleButtonGroup` populated from `hub_registry.getEnabledHubs()` at refresh time, in `gui_experiment.lua` (Decision 76) -- built specifically because the earlier `api.gui.comp.ComboBox` attempt crashed the game (Decision 73).

### Implementation note -- UNVERIFIED, needs research before trusting

A pasted external guide claims the mechanism is: a `guiInit`/`guiUpdate`-driven `createToolbarButton()` that calls `api.gui.util.getById("mainToolbar")` to find the toolbar container, builds a button via `api.gui.comp.Button.new(api.gui.comp.ImageView.new("ui/icon.tga"))`, sets an id/tooltip, wires `button:onClick(...)`, and appends it with `toolbar:add(button)`; the icon itself would need to be a 24x24 `.tga` with alpha, under `res/textures/ui/`. None of this -- the `"mainToolbar"` id, the `Button`/`ImageView` component API, whether `toolbar:add` exists -- has been independently confirmed against this game version the way this project's other API claims have been (see `dumpAvailableCommands`'s own precedent for settling exactly this kind of question directly instead of trusting a plausible-sounding guide). Before building on it: confirm `api.gui.util.getById("mainToolbar")` actually resolves to something real and enumerate its real methods, the same evidence-first way `COMMANDS.md`/`TECHNICAL_RESEARCH.md` were built for everything else in this mod.


## Final GUI Research and Cleanup Phase

Before finalising the release UI, study mature/open-source TF2 mods such as **LineManager** and **Auto Line Namer** to identify proven methods for building native-looking TF2 interfaces.

Research should focus on how existing mods implement:

- Native buttons rather than temporary `[ Button ]` text controls.
- Toolbar/menu buttons and custom icons.
- Windows and layouts.
- Tables and aligned columns.
- Scrollable lists.
- Tabs.
- Dropdowns.
- Checkboxes/toggles.
- Tooltips.
- Style classes and native TF2 visual styling.
- Window open/close behaviour.
- GUI event handling.
- Communication between GUI scripts and game-script logic.
- Persistent UI/settings state where appropriate.

Do not redesign the current working GUI during core gameplay development.

Treat this as an **end-of-development GUI cleanup/polish phase** once the Distribution Brain's gameplay mechanics are stable.

Goal: replace temporary development controls and diagnostic presentation with a clean, intuitive interface that looks and behaves like a native Transport Fever 2 feature.

## Runtime Fleet Rebalancing — Planner + Opportunistic Dispatcher

### Issue

Dynamic fleet reallocation is working, but continuously moving large numbers of trucks whenever demand changes could create several problems.

#### 1. Loaded Vehicle Reassignment

A truck may already contain cargo reserved for its current service.

Changing its line while loaded could cause cargo loss, incorrect delivery behaviour or other unwanted TF2 behaviour.

**Possible solution:**
- Do not normally reassign loaded vehicles.
- Prefer trucks that are confirmed empty.
- Treat empty trucks at or near the Distribution Hub as candidates for reassignment.

---

#### 2. Large Batch Reallocation / Pathfinding Load

Moving many vehicles to new lines simultaneously may cause TF2 to recalculate paths for many trucks at once, potentially creating performance spikes on large networks.

Example:

Queens needs +8 trucks while Grain has 6 surplus and Park has 2 surplus.

Avoid immediately moving all 8 trucks at the same moment.

**Possible solution: separate planning from execution.**

The Distribution Brain periodically calculates the desired fleet allocation but does not immediately perform every required reassignment.

Example:

    Target Fleet:
    Queens      +8 required
    Grain       -6 surplus
    Park        -2 surplus

These become pending requirements.

As suitable empty vehicles become available, the dispatcher gradually performs the required moves.

This creates two separate systems:

**Periodic Planner**
- Scan waiting cargo/demand.
- Inspect current fleet allocation.
- Calculate desired trucks per service.
- Record which services are over/under target.

**Opportunistic Dispatcher**
- Monitor vehicles.
- When an eligible empty vehicle reaches a sensible decision point:
  - Check whether its current service has surplus capacity.
  - Find an under-served compatible service.
  - Reassign the vehicle.
- Continue until actual allocation approaches the Planner's target.

This should produce smoother and more natural fleet movement than periodically shuffling large numbers of trucks at once.

---

#### 3. Cargo Compatibility

Not every vehicle in a Distribution Hub's fleet should necessarily be considered interchangeable.

Example:

    Distribution Hub
    70 total trucks

does not necessarily mean:

    70 trucks capable of serving every line

Some vehicles may only support particular cargo types.

**Possible solution:**

Treat the hub as one logical fleet while retaining each vehicle's cargo capabilities.

Before reassignment:

    Cargo required by target service
              ∩
    Cargo supported by vehicle
              ↓
         Compatible?

Only compatible vehicles may be reassigned to that service.

The Brain therefore manages a shared fleet containing compatibility sub-pools rather than assuming every truck is identical.

**Refinement — cargo profile, not just instantaneous cargo.** Current waiting cargo alone can mislead the planner: a service that normally handles Fuel, Food, and Construction Materials might show only Fuel waiting at the exact moment of reassessment (the other two just delivered and cleared, or not yet arrived), and a naive allocator would conclude it only needs Fuel-compatible trucks — then a train drops 150 Food thirty seconds later and the service is stuck with specialist tankers that can't touch it.

**Design principle for V1**: compatibility should be based on the service's observed cargo profile (current + recent history), not solely the cargo visible at the instant of reassessment.

Proposed weighting, strongest to weakest:
1. **Current waiting cargo** — strongest signal, what needs moving right now.
2. **Recently observed cargo** (station's own recent load/unload history) — keeps a cargo type's compatibility "alive" even when its current count is temporarily zero.
3. **Longer-window history** — a fallback so a seasonal/intermittent cargo type doesn't get silently forgotten between deliveries.

**Research question — answered, live-confirmed (Decision 28).** `stations.getItemTotals` only ever read `_sum`; a deeper one-off dump of the same station's `itemsLoaded`/`itemsUnloaded._lastMonth`/`_lastYear` sub-tables showed real per-cargo-type keys (`{ _sum=0, CONSTRUCTION_MATERIALS=0, FUEL=0, FOOD=0 }`, etc.), not just an opaque total. The planner can read cargo-profile history straight from data TF2 already tracks — no new history-tracking system needed.

**Partially built — the AGGREGATE half, not the per-cargo-type half (Decision 30).** `planner.lua` now uses recent/historical *presence* (any activity at all, not broken down by type) to boost a quiet line's floor instead of collapsing it to the bare minimum — live-confirmed fixing the exact snapshot problem this section describes. What's still open: this is a scalar "is this destination real and active" signal, not yet the per-CARGO-TYPE profile this section's vehicle-mix idea actually needs (`stations.getRecentUnloadedTotal` currently reads `_lastMonth._sum`, not per-type). The vehicle-compatibility-mix idea below (4 universal + 3 fuel-capable + 2 food-capable, etc.) still needs that per-type breakdown, plus Decision 27's per-vehicle compatibility data, neither wired together yet.

**Also proposed**: don't over-optimize allocation so tightly that the fleet becomes brittle the instant the cargo mix shifts. Favour universal (broadly-compatible) vehicles when a service's cargo mix is uncertain or historically variable, reserve specialists for services with a clearly dominant, stable cargo type, and deliberately hold back a small slice of a service's target allocation as "flexibility reserve" — broadly-compatible trucks kept on hand rather than assigned purely to match the current instantaneous mix.

This is a refinement to make before the Planner actually starts choosing which vehicles to reassign (Not Started #4 in PROGRESS.md) — the underlying per-vehicle compatibility data it depends on is already proven (Decision 27), what's missing is the profile/history layer on top of it.

---

#### 4. Terminal Physical Congestion

Demand-based terminal allocation could theoretically place several high-frequency services onto terminals whose physical approach/exit geometry causes congestion.

**Possible solution:**

Do not add complexity until live testing demonstrates this is a real problem.

If required later, terminal allocation could consider:
- terminal utilisation,
- line frequency,
- shared terminals,
- terminal/road adjacency,
- station entrance/exit congestion.

For V1, retain the simpler proven demand/load-based terminal allocator unless testing shows a need for physical-layout awareness.

---

## Relationship to Empty-Run Recovery

The opportunistic dispatcher could integrate naturally with the planned Empty-Run Recovery system.

An empty vehicle becomes a natural decision opportunity:

    Vehicle empty
         ↓
    Current line needs it?
         ↓
    YES → continue normally

    NO
         ↓
    Compatible service needs another truck?
         ↓
    YES → reassign

If the vehicle has already departed empty:

    Useful compatible cargo ahead?
         ↓
    YES → continue

    NO
         ↓
    Useful compatible cargo behind?
         ↓
    YES → reverse for second loading opportunity

This means fleet balancing and empty-run recovery could eventually share the same vehicle decision system.

### Core Design Principle

**Think periodically. Act opportunistically.**

The Brain can continuously understand what the Distribution Hub *should* look like without constantly forcing the physical fleet to change.

Demand determines the target allocation.

Safe empty-vehicle opportunities determine when that target is actually implemented.

## Standby/Holding Pool via `setVehicleManualDeparture`

### Origin

Raised while re-reading `COMMANDS.md`'s confirmed-command table: `setVehicleManualDeparture` is already live and working in this mod (`vehicles.setManualDeparture`, used by `line_splitter.lua`, `route_injector.lua`, `fleet_allocator.lua`, `dispatcher.lua`), but only ever as a **brief hold-reassign-release within one operation** — hold the vehicle, confirm it's stopped, call `setLine`, then release it again, all inside a few seconds. That pattern is proven safe. This idea is a different, larger use of the same command: holding a vehicle indefinitely as a genuine parked/standby spare, not releasing it again until the Planner/Dispatcher decides it's actually needed somewhere.

### The idea

When a truck returns to its hub and nothing currently needs it, instead of leaving it running its existing (possibly redundant) line, hold it there (`manual = true`) as a standby spare. When the Opportunistic Dispatcher (see "Runtime Fleet Rebalancing" above) later identifies an under-served service, pull a held vehicle from the standby pool, reassign its line, and release the hold. This is also a candidate for the "safe reassignment" moment itself, separate from standby: hold on arrival → confirm cargo is empty → change line → release, potentially cleaner than trying to catch a moving empty vehicle mid-route.

`setUserStopped` (present in the command surface, unconfirmed by anyone checked) is a different, adjacent command worth distinguishing before using either one for standby: it's presumed to be the equivalent of the player manually pressing Stop, a more general/blunt tool, versus `setVehicleManualDeparture`'s narrower "won't depart from its current stop" behaviour. Which one is actually right for an indefinite hold (rather than the momentary hold already proven) hasn't been tested.

### Economic motivation

Not just a traffic/dispatch smoothing idea — player reports TF2 gives a stopped vehicle roughly a **40% reduction in depreciation** while it isn't running. If real, that changes this from a "nicer to look at" idea into one with a direct in-game money benefit: surplus fleet sitting idle in a standby pool would depreciate slower than the same trucks left running an under-used line just to look busy. This number is player-recalled, not yet checked against the game's own vehicle-value display — worth confirming (park one vehicle, compare its value/depreciation rate stopped vs. running over the same time window) before it's used to justify the feature, same as any other unverified claim in this file.

### What's actually confirmed vs. still a story

**Confirmed**: `setVehicleManualDeparture` is real, works, and is already load-bearing in shipped logic — but only ever held for a few seconds at a time, always followed by a release in the same operation.

**Not yet confirmed**:
- Whether holding a vehicle for a long, indefinite period (minutes/hours of game time, not seconds) has the same safe behaviour as the brief holds already proven, or surfaces some different edge case (e.g. does TF2 route other traffic around it fine, does its line/cargo association stay valid while held).
- Whether a vehicle held this way blocks the physical terminal/parking bay it's sitting in for other traffic — this hub only has a handful of physical terminals, and parking even a modest number of surplus trucks there risks congestion (several standby vehicles occupying terminals that lines actively needed would want to use).
- `setUserStopped` vs `setVehicleManualDeparture` for this specific purpose — not compared or tested against each other.

### If it does pan out

Conservative to start: at most a small number of standby vehicles at the existing station, or none at all until the congestion question is actually tested — this mod's hub has limited physical terminal space, unlike the separate "custom Distribution Centre with dedicated parking bays" concept discussed elsewhere, which could absorb far more standby vehicles without conflict. Worth a small, scoped live test (hold one already-idle vehicle for several real minutes, watch for any traffic/terminal side effects, then release it) before this becomes part of the real Dispatcher — the same evidence-first treatment as everything else in this file, not an assumption that "it worked for a few seconds" implies "it's fine indefinitely."

## Event-Driven Demand Reassessment

**Research update — now live-confirmed, not just documented (Decision 28)**: `handleEvent(src, id, name, param)` is wired for real in `epod_truck_distribution.lua` and was run live: 500+ genuine `OnToArriveAtDestination` fires in one short test session, `param` reliably giving a real, readable cargo entity id each time. This settles "does it actually fire" — it does, reliably — but also confirms it's genuinely **high-frequency and game-wide**, not scoped to managed hubs: the "material change threshold" idea below isn't just a caution anymore, it's a proven-necessary requirement before this event can drive anything. No complementary "cargo newly waiting" event has turned up yet (searched the full shipped script set), so this covers the delivery/arrival side of demand change, not necessarily the generation side. The event handler itself doesn't yet do anything beyond counting fires — no threshold/batching logic exists yet.

### Idea

Avoid continuously recalculating Distribution Hub fleet allocation on a short fixed timer.

Instead, allow the Distribution Brain to remain mostly idle until the hub's actual waiting-cargo state changes materially.

This could significantly reduce unnecessary calculations while also allowing the Brain to react quickly when a large new delivery arrives.

### Example — Incoming Delivery

A train, ship, aircraft or another freight service delivers a large amount of cargo to the Distribution Hub:

    Previous waiting stock: 220
    New waiting stock:      480
    Change:                +260

                ↓

    Material stock change detected

                ↓

    Immediately reassess demand

                ↓

    Calculate new target fleet allocation

The Brain does not need to specifically know that "a train arrived."

The important event is that the hub's real waiting cargo has changed significantly.

---

### Also Detect Falling Demand

Reassessment should not trigger only when cargo arrives.

A busy destination may be cleared by its trucks:

    Alexander Road

    Previous: 300 waiting
    Current:   40 waiting

                ↓

    Demand has materially fallen

                ↓

    Reassess allocation

This prevents trucks remaining heavily allocated to a service after its backlog has disappeared.

---

### Monitor Per-Service Demand, Not Only Hub Total

Total cargo at the hub may remain unchanged while demand moves between destinations.

Example:

    Queens Road       250 → 50
    Alexander Road    100 → 300

    Total waiting:    350 → 350

The hub total has not changed, but the required truck allocation has changed dramatically.

Therefore the trigger should monitor waiting cargo by managed service/destination and, where useful, cargo type.

---

### Material Change Threshold

Do not trigger a full reassessment for every single unit of cargo added or removed.

Possible rule:

    Has waiting cargo for a managed service
    changed by more than X units or Y percent?

        NO  → do nothing
        YES → reassess demand

Exact thresholds should be determined through live testing rather than hard-coded prematurely.

---

### Slow Safety Heartbeat

Even with event-driven reassessment, retain a very slow safety check.

Purpose:

- Detect any state change the normal monitoring missed.
- Verify cached demand data is still correct.
- Recover safely after unusual TF2 behaviour.
- Provide protection against edge cases discovered later.

The safety heartbeat should not automatically cause fleet movement.

It should simply verify whether the current Distribution Brain state still matches the real network.

---

### Proposed Runtime Model

    WAITING CARGO STATE
            ↓
    Material change detected?
       ↓              ↓
      NO             YES
       ↓              ↓
    Do nothing    Scan demand
                       ↓
                 Calculate target
                 fleet allocation
                       ↓
                 Store required
                 fleet changes
                       ↓
             Opportunistically move
              suitable empty trucks

                         +

               SLOW SAFETY HEARTBEAT
                         ↓
                  Verify cached state

### Core Principle

**React to meaningful changes instead of constantly polling and recalculating.**

The Distribution Brain should spend most of its time observing the network and only perform expensive planning work when the logistics situation has actually changed.

## Automatic Network Change Detection & Safe Line Shutdown

### Goal

A managed Distribution Hub should adapt naturally when the player changes the surrounding freight network.

The player should continue building and editing normal TF2 lines using the normal game interface. Dynamic Distribution should detect those changes and integrate them into the managed hub without requiring the player to manually reconfigure the Distribution Manager.

This preserves the core design philosophy:

**The player designs the network.  
Dynamic Distribution operates the hub.**

---

## Network Change Detection

### New Destination / Delivery Line

If the player creates a new line that connects to a managed Distribution Hub, the Brain should detect that the hub's network topology has changed.

Example:

    Existing Hub:
        Hendon East
            ├── Alexander Road
            ├── Queens Road
            └── The Grove

    Player creates:
        Hendon East → Smith Street → Victoria Road

The Brain detects the new service and reassesses the hub.

Possible process:

    Network change detected
            ↓
    Inspect new/changed line
            ↓
    Identify new stops/destinations
            ↓
    Determine how they relate to the hub
            ↓
    Integrate them into Distribution Management
            ↓
    Create/adopt required persistent services
            ↓
    Discover eligible vehicles
            ↓
    Recalculate fleet requirements
            ↓
    Recalculate terminal allocation

This means the player can continue creating ordinary TF2 lines, including temporary multi-stop routes, and the Distribution Manager can convert that intent into the structure it requires.

---

## New Feeder Service

The same detection should apply when the player adds a new service bringing resources INTO the Distribution Hub.

Example:

    New Factory
        ↓
    New Truck Station
        ↓
    Hendon East Distribution Hub

The Brain should recognise that a new cargo service is now connected to the hub.

It can then:

- Include the service in the hub network.
- Detect its vehicles.
- Inspect their cargo compatibility.
- Include eligible vehicles in the logical hub fleet where appropriate.
- Include its terminal usage when balancing terminals.
- React to the additional cargo entering the hub.

The player should not need to manually register every new feeder or destination with Dynamic Distribution.

---

## Possible Fast Trigger — Closing/Editing Lines

Investigate whether TF2 exposes a reliable GUI or game event when:

- a line is created,
- a stop is added,
- a stop is removed,
- a line is edited,
- or the line management/editing window is closed.

Closing the TF2 line editor could be used as a cheap indication that:

    "The player may have changed the network."

This should NOT immediately rebuild anything.

Instead:

    Possible network change
            ↓
    Compare current hub network
    against stored snapshot
            ↓
       No difference
            ↓
         Do nothing

    Difference detected
            ↓
      Reassess hub

The event therefore wakes the Brain rather than automatically assuming something changed.

---

## Network Fingerprint / Snapshot

Maintain a lightweight representation of each managed hub's known network.

Possible information:

- connected line entity IDs,
- stop/station entity IDs,
- stop order,
- terminal assignments,
- known feeder/destination relationships,
- known managed vehicles.

When the network-change trigger fires, compare the current structure with the previous snapshot.

Only run the more expensive integration logic when the structure has genuinely changed.

If TF2 does not expose reliable network-edit events, a very slow lightweight topology check could provide a fallback.

---

## New-Line Detection/Adoption — V1 BUILT (Decision 41), opt-out still open

The "new destination/delivery line" and "new feeder service" cases above are now handled by `line_adopter.lua` + `pollNewLineAdoption()`: a slow topology poll (no separate fingerprint/snapshot needed — `managed_registry.isManaged()` already IS the "known network" state) finds any road/truck line touching the hub that isn't registered yet, renames it to match the hub's convention, and registers it. Player-confirmed scope for V1: anything touching the hub is swept in, no opt-out.

Still open, deliberately deferred, not built:

- **Per-line opt-out.** Either a reserved name prefix meaning "leave this one alone" (mirrors "●" meaning "managed"), or a live confirmation popup when a new line is first detected — *"New line detected at Hendon, want this to be Auto managed?"* (the player's own suggested phrasing). A popup needs a proven TF2 GUI confirmation-dialog mechanism, not yet researched in this codebase.
- **Safe line shutdown** — the other half of "Automatic Network Change Detection & Safe Line Shutdown": detecting a managed line's removal/edit and recovering its vehicles before anything is lost, with a waiting-cargo warning first. Not started.

---

## Player Manually Deletes a Line

The player always retains authority over their network.

If the player manually deletes a managed line using TF2's normal interface, Dynamic Distribution should NOT fight the player's decision or attempt to recreate it automatically.

Instead:

    Managed line disappears
            ↓
    Detect topology change
            ↓
    Remove obsolete DD state
            ↓
    Reassess remaining services
            ↓
    Recalculate fleet/terminal state

Dynamic Distribution manages the network on behalf of the player; it does not override deliberate player actions.

---

## Safe "Close Managed Line" Option

Dynamic Distribution could provide its own safer way to deliberately retire a managed service.

Example:

    ● Hendon East ↔ Park Avenue

    [ CLOSE MANAGED LINE ]

Unlike directly deleting the line through TF2, this gives the Distribution Manager an opportunity to recover the vehicles first.

Possible shutdown process:

    Player selects Close Managed Line
            ↓
    Mark service as CLOSING
            ↓
    Stop allocating additional vehicles
            ↓
    Identify vehicles currently assigned
            ↓
    Recover/reassign suitable empty vehicles
    into the remaining hub fleet
            ↓
    Vehicle count reaches 0
            ↓
    Safely delete the obsolete line
            ↓
    Remove it from Distribution Management
            ↓
    Recalculate fleet allocation
            ↓
    Recalculate terminal allocation

This prevents useful vehicles being unnecessarily lost or mishandled during line removal.

---

## Waiting Cargo Warning

Before closing a managed service, inspect its waiting cargo.

Example:

    CLOSE: Hendon East ↔ Park Avenue

    Vehicles:       3
    Waiting cargo: 42

    ⚠ Cargo is still waiting for this service.

    [ CANCEL ]
    [ CLOSE ANYWAY ]

The Brain should warn rather than decide for the player.

Zero current demand should NEVER automatically cause a line to be deleted.

A quiet service can remain alive with minimum service until the player explicitly chooses to close it.

---

## Relationship to Other Runtime Triggers

Dynamic Distribution could eventually have three primary reasons to wake the Brain:

### 1. Cargo Change

    Large delivery arrives
    Backlog cleared
    Demand shifts between destinations
            ↓
    Recalculate fleet requirements

### 2. Network Change

    New line
    New destination
    New feeder
    Stop added/removed
    Line deleted
            ↓
    Reassess hub structure

### 3. Safety Heartbeat

    Slow periodic verification
            ↓
    Confirm cached state still
    matches the real TF2 network

These triggers perform different jobs.

    CARGO CHANGE
         ↓
    "Do I need to move trucks?"

    NETWORK CHANGE
         ↓
    "Has the operation itself changed?"

    SAFETY HEARTBEAT
         ↓
    "Is what I believe still true?"

---

## Core Design Principle

Dynamic Distribution should not require the player to learn a special way of building freight networks.

The player continues playing Transport Fever 2 normally:

    Build station
    Build roads
    Create line
    Add/remove stops
    Connect new industry
    Delete unwanted service

Dynamic Distribution observes those decisions and manages the operational consequences inside hubs that the player has explicitly placed under Distribution Management.

**Player chooses what the network should do.  
Dynamic Distribution works out how to operate it efficiently.**

## Per-Line Management Toggle — `● / ○`

### Idea

Every eligible cargo line connected to a managed Distribution Hub should be discovered automatically and included in Dynamic Distribution management by default.

However, the player may occasionally have a particular line they want to manage manually.

Provide a simple per-line toggle directly in the Distribution Hub panel.

Use the management-status symbol itself as the control:

    ● = Managed by Dynamic Distribution
    ○ = Observed, but Player Managed

The symbol is clickable:

    ● → click → ○
    ○ → click → ●

This avoids adding separate ON/OFF buttons and makes the management state of the entire hub visible at a glance.

---

### Example

    HENDON EAST — DISTRIBUTION HUB

    SERVICES

    ● Queens Road          18 trucks    240 waiting
    ● Alexander Road       20 trucks    310 waiting
    ● The Grove             8 trucks     75 waiting
    ● Grain                20 trucks    180 waiting
    ○ Special Contract      4 trucks     30 waiting

The player can immediately see that:

- Queens Road is DD managed.
- Alexander Road is DD managed.
- The Grove is DD managed.
- Grain is DD managed.
- Special Contract exists at the hub but has been deliberately excluded from DD management.

No separate settings screen should be required for normal use.

---

## Default Behaviour

When DD discovers a new eligible cargo line connected to a managed Distribution Hub:

    New eligible line detected
            ↓
    Default state = ● MANAGED
            ↓
    Include in Distribution Hub pool

The player therefore does not need to manually enable every new service.

This is important for automatic network-change detection.

Example:

    Player creates new Grain line
            ↓
    DD detects it
            ↓
    ● Grain
            ↓
    Automatically becomes part
    of the managed hub

The player only needs to intervene if they specifically do NOT want DD managing that service.

---

## Turning Management OFF

When the player clicks:

    ● → ○

DD should immediately stop performing future management actions on that line.

Turning management OFF should be safe and non-destructive.

DD should NOT:

- delete the line,
- remove vehicles,
- reassign its vehicles,
- change its terminal,
- change its stops,
- rename the line,
- or otherwise attempt to "undo" previous management.

The existing service should simply remain exactly as it currently exists.

From that point onward, the player manages it manually.

---

## Observed vs Managed

An OFF line should NOT become invisible to the Distribution Brain.

There is an important distinction:

    ● MANAGED
        DD knows the line exists
        AND may modify it.

    ○ OBSERVED / PLAYER MANAGED
        DD knows the line exists
        BUT must not modify it.

This allows DD to remain aware of the physical network.

For example, an excluded line may still occupy Terminal 3.

DD's terminal allocator needs to know:

    Terminal 3 already has traffic/load

even though DD is forbidden from changing that line.

Therefore excluded lines should still contribute relevant information such as:

- terminal occupancy,
- station/network topology,
- cargo activity where useful,
- vehicle presence where needed for context.

They are visible to the Brain but outside its authority.

---

## Turning Management ON

When the player clicks:

    ○ → ●

the line becomes eligible for DD management again.

Possible process:

    ○ Player Managed
            ↓
        Player clicks
            ↓
    ● DD Managed
            ↓
    Inspect current line
            ↓
    Inspect vehicles
            ↓
    Inspect cargo compatibility
            ↓
    Inspect waiting demand
            ↓
    Include in managed fleet/service pool
            ↓
    Include in next Planner calculation

DD should adopt the line's CURRENT state rather than assuming it still looks the way it did when management was previously disabled.

---

## Persistence

Management state must be persistent.

Example:

    Hub Entity: 12345

    Lines:
        5001 = managed
        5002 = managed
        5003 = player_managed
        5004 = managed

After save/reload:

    ● 5001
    ● 5002
    ○ 5003
    ● 5004

The player's opt-out choice must survive save/load.

---

## Relationship to the `●` Line-Name Fix

This feature should be implemented alongside or after:

**Decouple Managed-Line Identity From the `●` Name Prefix**

The `● / ○` displayed in the DD panel represents internal management state.

It must NOT depend on the actual TF2 line name.

Example:

Actual TF2 line name:

    Grain

DD panel:

    ● Grain

The player could rename the TF2 line:

    Bulk Grain Delivery

DD then displays:

    ● Bulk Grain Delivery

The management state has not changed.

The symbol belongs to the DD interface, not to the line's identity.

---

## Optional Line Naming Behaviour

DD may continue adding `●` to newly created managed line names because the symbol:

- visually identifies DD-created lines in TF2's normal line list,
- conveniently groups those lines together,
- is difficult to accidentally reproduce,
- and provides a useful visual hint outside the DD panel.

However, this must remain cosmetic.

Removing or changing the `●` in the actual line name must NOT change management state.

The authoritative state is the DD persistent record.

---

## Future Network Overview

The same control could eventually appear in the planned DD Network Overview.

Example:

    HENDON EAST DISTRIBUTION HUB

    ● Queens Road
    ● Alexander Road
    ● Grain
    ○ Special Contract

    PORTLAND DISTRIBUTION HUB

    ● Fuel
    ● Food
    ○ Local Goods

This would allow the player to quickly see which services across the entire network are under DD control.

---

## Core Design Principle

**Automatic by default, player-controlled when desired.**

A Distribution Hub should manage every eligible connected service automatically unless the player explicitly tells it not to.

The player should always be able to say:

    "I want to manage THIS particular line myself."

with one click.

`●` = DD has the wheel.

---

## Convert to Distribution Hub — Fast vs. Safe

### Origin

Raised live once "Split → Assign & Balance → Organize Terminals" was finally proven working end to end on a second hub (Decisions 45/46/48/50/51/52). PROGRESS.md #7 already lists folding those three stages into one "Convert to Distribution Hub" button; this refines that with a real choice the player should get, not just a single combined click.

### The idea

Assign & Balance already only ever takes an *empty* vehicle from the source line (`findEmptyVehicle`, the existing Bug A avoidance) — a genuinely gradual, "safe" conversion: the source line keeps earning off whatever's still loaded, and trucks migrate over naturally as they empty out, possibly across more than one click. The idea is to offer a second, faster option that skips that caution on purpose: grab every vehicle immediately regardless of what it's carrying, accept whatever's currently in transit as lost, and finish the conversion in one pass instead of several.

Two plain buttons, not a popup — a TF2 GUI confirmation dialog with multiple choices has never been attempted in this codebase, and buttons are already proven dozens of times over, so there's no reason to take on that unproven API risk for something two buttons already solve cleanly:

- **Convert (Safe)** — today's existing behavior, unchanged.
- **Convert (Fast)** — same chain, but the vehicle-selection step takes any vehicle, loaded or not.

### What's actually confirmed vs. still a story

**Confirmed**: the "Safe" path end to end (Decisions 45/46/48/50/51/52) — split, retire stops, redistribute spares, delete the source line, all live-tested working on a real second hub.

**Not yet built or tested**: the "Fast" variant itself, and whether reassigning a genuinely loaded vehicle via `setLine` actually loses its cargo outright or TF2 handles it some other way — this mod has always avoided testing that specific case on purpose (Bug A), so there's no live evidence either way yet.

### If it does pan out

Natural fit alongside PROGRESS.md #7's one-click conversion button once that gets built — two labeled variants of the same combined chain, differing only in which vehicles Stage 2 is allowed to take.

---

## Central Fleet Depot — buy trucks with no line, let DD deploy them network-wide

### Origin

Raised live during the 6-hub stress test, watching town cargo demand badly outstrip delivery (`documents/DECISIONS.md`'s Decision 56 session) and joking about just buying a couple hundred more trucks to catch up. The real idea underneath the joke: right now there's no way to buy trucks that AREN'T tied to a specific line from the moment of purchase — every truck goes straight onto whatever line the player buys it into, or (via Stage 3) gets redistributed among one hub's OWN split lines. There's no way to buy a batch of trucks into a neutral pool and have the mod figure out where they're actually needed most.

### The idea

A designated "central" station/depot where the player buys vehicles with no line assignment at all. DD detects these unassigned vehicles, ranks demand across **every enabled hub** (not just one, unlike Stage 3 today), and assigns each vehicle to whichever real destination line currently needs it most — a genuine network-wide version of the demand-ranked logic `fleet_allocator.redistributeSpareVehiclesByDemand` already proves works, just scoped up from "one hub's own split lines" to "the whole managed network."

### What's actually confirmed vs. still a story

**Confirmed**: the underlying demand-ranking mechanism (largest-remainder method, `fleet_allocator.lua`) already works, live-tested, within a single hub.

**Not yet built or tested, and genuinely new territory**: detecting a vehicle that has been bought with no line at all (not yet confirmed this mod can identify "a vehicle sitting unassigned at a station" the same reliable way it identifies vehicles already on a managed line); ranking demand ACROSS multiple hubs simultaneously rather than one at a time; and assigning a brand-new vehicle onto a real line from scratch (previous work always started from a vehicle already on some existing line being reassigned, never a genuinely fresh, lineless purchase).

### If it does pan out

Would turn "buy 200 trucks" from a manual chore (picking which line each one goes to, then hoping it was the right call) into a single purchase decision, with DD handling deployment — a natural escalation of the same "player decides how much, DD decides where" pattern Auto Redistribute already established.

### Refinement: make it a real, visible place, not just an abstract pool

Raised live in the same session: instead of unassigned vehicles being an invisible mod-tracked state, give this a real physical home — one large truck bay/depot the player builds, where any bought-but-unassigned truck physically sits and visibly accumulates until DD deploys it. Two direct benefits over a purely invisible pool:

- **A visual "do I need more trucks" signal.** An empty bay means DD has already deployed everything you bought; a bay full of parked trucks means either demand is genuinely being met everywhere, or deployment is stuck/slow — either way, the player can just look at the bay instead of needing a report to know whether to buy more.
- **Natural fit with the Fleet Balance Report idea below** — the bay's own vehicle count becomes one more row in that report ("N trucks waiting at the central depot"), rather than a separate thing to track.

### Further refinement: a custom-built model, linked per-hub, actually holding vehicles at rest

Raised live once the physical-bay idea above was on the table: rather than a generic parking lot, a purpose-built depot model (designed via Claude + Blender, a separate asset pipeline from anything touched in this Lua-scripting project so far) that's explicitly linked to a specific distribution hub — so a busy hub can have its own overflow bay rather than one single global depot serving the whole map.

The mechanism this would actually run on: `setVehicleShouldDepart` and `setVehicleManualDeparture`, both real, confirmed-existing entries in `api.cmd.make.*` (seen in the mod's own COMMAND SURFACE DIAGNOSTIC startup log every session, never yet used for anything). These are what would let a truck be genuinely held parked at the bay — not just idle on an empty line — until DD's demand ranking picks it and releases it onto a real destination line. That's a concrete, plausible mechanism, not just a visual idea: hold on arrival, release on assignment.

**Genuinely new territory, not yet touched by this project at all**: building/importing a custom 3D model is a completely separate pipeline from every Lua change made so far — nothing about tonight's work (or any prior session) touches asset creation. This is realistically its own project phase: model first, then the departure-hold mechanism, then wiring it to the network-wide demand ranking from the Central Fleet Depot idea above. Not something to start same-session as a long stress-test night with one real crash already behind it — a fresh-start project when ready.

### Further refinement: wire it up the same way a magic station name already works elsewhere

Raised live: how does the depot actually get linked to a specific hub, in a way that feels natural to the player rather than requiring some separate UI? Proposed mechanism: the player builds an ordinary truck LINE connecting the depot ("Truck Central") to whichever real distribution hub they want it feeding, using nothing but the vanilla line-drawing tool they already know. The mod detects this new line (same detection this mod already does via `line_adopter.lua`'s new-line polling), records the depot↔hub relationship into a new dedicated registry (same proven `io.open` pattern as `hub_registry.lua`/`line_ownership.lua`/`source_line_registry.lua`), and then immediately deletes the actual line via `api.cmd.make.deleteLine` — already proven working, already used for real in `line_splitter.deleteEmptySourceLine`. The line was never meant to carry cargo; it was just the player's way of saying "link this depot to that hub," and gets converted into a persistent mod-level fact instead.

This isn't a new mechanism invented from nothing — it directly reuses a pattern already live in this exact codebase: `config.PARK_NAME = "EPOD-TD Truck Park"` is already a magic station name the mod recognizes and treats specially (filtered out of destination lists in `vehicles.lua`). "Truck Central" would be the same trick — a recognized name, not a new kind of entity — just used to trigger a link-then-delete instead of a filter.

**What's already proven vs. still to confirm**: `deleteLine` working — proven (Decision from the Stage 3.5 auto-delete feature). Detecting a new line touching a hub — proven (`line_adopter.lua`, running every session). **Not yet confirmed**: whether deleting the line immediately after creation, inside the same detection→respond cycle, causes any visible flicker or player confusion (the line existing on-screen for one frame before vanishing) — worth an isolated live test before relying on it, same evidence-first standard as everything else this project has done.

### The actual payoff: this is how cross-hub rebalancing gets solved

Raised live, and this is the piece that ties the whole night together: right now the Fleet Balance Report can *tell* the player Goole North is hoarding 134 trucks while a bridging line two hops away starves at 655 waiting (Decision 56 session, real numbers) — but the only fix is a person manually clicking Assign & Balance and hoping it reaches far enough. Depot↔hub links turn that from a report into an action: a starved hub (or the central depot) sends trucks across its own link, using data straight from the same demand-ranking already proven in `fleet_allocator.lua` and the Fleet Balance Report — real network-wide redistribution, not just the current within-one-hub version. This is the direct answer to the mod's biggest identified gap: "distribution *within* each hub" (proven, working) versus "distribution *across* the whole network" (the missing piece). Depot links plus the Fleet Balance Report's own data are the two halves of an actual solution to that gap, not two separate ideas.

---

## Network Reports as a Real GUI Feature (not just DEBUG file dumps)

### Origin

Raised live right after building the Fleet Balance Report and Dump All Managed Lines DEBUG buttons (Decision 56 session) — both proved genuinely useful for spotting real imbalances (the Corby North 39-truck/0-waiting line, the Goole North 134-truck hoarding line), but both are DEBUG-only, one-shot, and write to a file the player has to go find rather than a live in-game view.

### The idea

The new GUI framework's **Fleet tab** (`gui_tab_fleet.lua`, currently a placeholder) is the natural real home for this — live, always-visible, network-wide (every enabled hub at once, not just whichever one's selected) instead of a manual one-off DEBUG dump. Same underlying data and sort-by-worst-backlog logic already proven in `handleFleetBalanceReportButtonClick`, just rendered as a real panel that refreshes on its own like the Overview tab already does, instead of a button that writes a text file.

### What's actually confirmed vs. still a story

**Confirmed**: the exact data and ranking logic work — live-tested via the DEBUG button across 84 real lines and 486 real vehicles in one session, correctly surfacing every real imbalance found that session.

**Not yet built**: rendering it inside `gui_manager.lua`'s row-pool system instead of as log/file output, and doing it network-wide (today's version takes a single `hubStationGroupId`; the tab version would need to loop every enabled hub, matching how the other polling loops already do this one hub at a time).

### If it does pan out

Turns tonight's one-off diagnostic tools into a permanent, always-available feature — the player could just open the Fleet tab any time to see the whole network's balance at a glance, instead of remembering to click a DEBUG button and go find a text file.

---

---

## Detecting Merged-StationGroup Hubs

### Origin

Raised live (Decision 58): the Fleet Balance Report surfaced a line at Goole North with 14 fully idle vehicles and a suspicious "+"-joined name (`Goole Exchange + Goole Halt + Goole West + Goole East + Upper Goole + Upper Thatcham`). Turned out those six "destinations" are all the same `StationGroup` as the hub itself — TF2 auto-merges physically adjacent same-company stations regardless of individual building names — so the split pipeline's return-trip filter (correctly) treats every one of them as "the hub," and the line can never be split or rebalanced. Decided not to fix the underlying filter (see Decision 58's Reason — there's no reliable way to tell this apart from a genuine return-trip artifact), but the report could still make this visible instead of silent.

### The idea

Fleet Balance Report already flags `vehicleCount > 0 and waiting == 0` as "idle capacity." A cheap additional check: if a line's non-hub stop name contains " + " (TF2's own multi-stop auto-name joiner) alongside that same idle-capacity flag, add a second, more specific flag — something like `<-- possible merged-StationGroup hub (never split-eligible)` — so the player doesn't have to independently rediscover this via the Line Manager next time it happens on a different hub.

### What's already proven vs. still a story

**Confirmed**: the underlying cause (StationGroup merge → filtered out by the return-trip check → permanently unsplit) via live investigation this session. **Not yet built**: the name-pattern check itself — untested whether " + " reliably-only appears in this exact scenario or could false-positive on some other legitimately-named line.

### If it does pan out

Turns a "huh, that's weird, why is this idle" moment (which took a live Line Manager screenshot and a code read-through to explain, this time) into something the report just tells the player directly the first time it happens on any hub.

---

---

## Per-Feature On/Off Toggles for Automatic Naming/Colouring

### Origin

Raised live right after `industry_naming.lua` and `fleet_naming.lua` existed side by side, both firing automatically with no way to opt out: "we should give the end user the option to turn features off haha." Right now, turning any of these off means editing/removing code -- not something a player using this as a normal mod should have to do.

### The idea

Three independent settings, each a plain boolean stored via `settings.lua`'s existing generic `M.get(key)`/`M.set(key, value)` store (already the exact right shape for this -- no new persistence mechanism needed):

- **Name Change Trucks (on/off)** -- gates `fleet_naming.renameFleetToHubIdentity` (currently only ever player-triggered via a button, so this toggle would guard that button/action itself).
- **Name Change Truck Stations (on/off)** -- gates `industry_naming.detectAndNameStations`, called from `pollIndustryNaming()` in the main game_script. Since that poll runs automatically (Decision 105), this is the one toggle of the three that actually needs checking on a live/automatic path, not just at a manual button click.
- **Colour Change Trucks (on/off)** -- gates whichever vehicle-colour feature exists/lands from IDEAS.md's "Vehicle Identity Naming and Fleet Colour-Coding" idea (referenced in `fleet_naming.lua`'s own header comment) -- not yet built as of this note, but should carry the same toggle from day one rather than bolting it on after the fact.

Needs a real GUI home for the three checkboxes/toggle buttons -- most natural fit is a "Settings" section somewhere in `gui_manager.lua`'s tab framework (or a small dedicated SETTINGS tab), rather than DEBUG-only or config-file-only switches, since these are meant to be an ordinary player-facing preference.

### What's already proven vs. still a story

**Confirmed**: `settings.lua`'s get/set mechanism itself is proven and already live (Decision 35's fresh-read-every-call fix, used for `autoDispatchPending` today). **Not yet built**: any of the three keys, the gating checks inside `fleet_naming.lua`/`industry_naming.lua`/the not-yet-built colour feature, or the GUI controls to flip them.

### If it does pan out

A player who doesn't want their trucks/stations auto-renamed (or, once built, auto-coloured) gets a real off switch instead of needing to edit Lua -- turns three currently-unconditional automatic behaviours into genuine opt-in/opt-out player preferences, consistent with this project's own "stay in our lane, player-driven" stance on automation elsewhere.

---

## Persistent Game-Bar Indicator (instead of / alongside a window)

### Origin

Player shared the TF2 modding wiki's own FPS-counter example: `api.gui.util.getById("gameInfo"):getLayout():addItem(rawComponent)`, run once from a `guiInit` callback -- injecting a small element directly into the game's own always-visible bottom bar, not a new floating window at all.

### The idea

A small permanent indicator (e.g. active hub count, "N trucks moved recently," or a quick health glyph) living directly in the game's own `"gameInfo"` bar -- always visible with zero clicks, never hidden behind the map or needing a window opened at all. A genuinely different option from every GUI surface this mod has built so far (the old panel, the new "DD Central Manager" tabbed window, `gui_debug_tests.lua`), which all require the player to open something first.

### What's already proven vs. still a story

**Confirmed real and documented** (TECHNICAL_RESEARCH.md): the wiki's own official example does exactly this, using the raw `api.gui.comp.*` system and a real `guiInit` callback this mod does not currently define. **Not yet built or tried**: nothing has been added to the real `"gameInfo"` bar in this codebase; unproven whether TF2's actual `"gameInfo"` id/layout matches what the wiki shows in this game version, same "confirm before building on it" caution as every other API claim in this project.

### If it does pan out

Gives the player an always-on pulse of DD activity without opening any window -- complements rather than replaces the DD Central Manager, which stays the place for real detail/actions.

---

## Native `TabWidget`/`List` Components (real tabs/lists, not the manual workarounds this project built)

### Origin

Same wiki page: it documents a real `TabWidget` component (`onCurrentChanged` callback, `tabWidget.currentChanged` event) and a real `List` component (`onSelect`, `list.select`). `gui_manager.lua`'s "DD Central Manager" fakes tabs with plain buttons specifically because — per that file's own comment — "a native TF2 tab-widget API has never been used anywhere in this codebase" (Decision 50); every long-content view in this project (the old panel's rows, the new GUI's row pools) uses a pre-allocated flat pool with a hard truncation ceiling for the same reason.

### The idea

Two separate, independent experiments, both raw-system-only (same caution as the failed `gui.scrollArea_create` attempt — Decision 121 — never mix raw `api.gui.comp.*` into a `gui.lua`-built layout tree):

- Try a real `api.gui.comp.TabWidget` for "DD Central Manager"'s tab bar, replacing the manual "> " -prefix/style-class button-switching hack. Confirmed to have a real, direct `onCurrentChanged` callback per the wiki's own component-callback table (checkmark confirmed against the actual table image, not just pasted text) — the stronger of these two leads.
- Try a real `api.gui.comp.List` for the LINES tab (or any other long/growing content), replacing the truncate-at-a-fixed-row-count pattern used everywhere today — might solve Decision 123's "content pushed off-screen / other tabs pushed down" tradeoff more natively than juggling two competing row-pool sizes. Weaker lead than TabWidget: the real component-callback table has no `List` column at all, so there's no confirmed direct `:onSelect(fn)` method — any real selection handling would go through the generic `guiHandleEvent` dispatcher instead (see TECHNICAL_RESEARCH.md). Worth confirming `List` even exists as a constructible component before relying on it.

Either one would need its own from-scratch raw-system window (like `gui_experiment.lua`) to prove safe before ever touching the real "DD Central Manager" window, exactly the same staged approach every other GUI primitive in this project has gone through.

### What's already proven vs. still a story

**Confirmed real and documented**: both components exist per the wiki's own component-callback table (TECHNICAL_RESEARCH.md). **Not yet tried at all**: no code anywhere in this project has ever called `api.gui.comp.TabWidget` or `api.gui.comp.List`; genuinely unproven in this specific game version/mod sandbox until tested live.

### If it does pan out

Real native tabs and a real scrollable list would resolve two long-standing, self-imposed workarounds (manual tab-switching, hard row-count truncation) at once, and would be the natural foundation if the old panel is ever fully retired in favor of "DD Central Manager."

## Clickable Hub List on Overview — switch which hub the GUI shows without hunting the map

### Origin

Raised live, following the 8-tab-to-4-tab consolidation discussion (Decision 138-era): folding the HUBS tab's enabled-hub list into OVERVIEW was proposed as a static display only. Player's own follow-up: "add this to ideas, but Hubs listed on front page, if you click a hub it then shows that hubs data in the GUI? easy way to check all hubs not have to hunt the map for them."

### The idea

OVERVIEW shows the list of enabled hubs (already exactly what HUBS displays today via `hub_registry.getEnabledHubs()` + `stations.getEntityName`) as real clickable rows, not plain text. Clicking a hub in that list switches which hub's data the ENTIRE window shows — every tab (LINES, CARGO, SETTINGS, etc.) re-renders against the clicked hub, exactly as if the player had selected that hub's station on the map.

### Why this is a bigger change than it looks -- flagged during the tabs-consolidation critique

Every tab in `gui_central_raw.lua` today receives `hubStationGroupId` as a parameter threaded through from ONE source of truth: `distributionState.selectedStationGroupId`, set only by clicking a real station entity on the map (`handleStationSelection` in `epod_truck_distribution.lua`). There is currently no concept of "the GUI's own idea of which hub is active," independent of the map selection -- `gui_central_raw.lua`'s `ensureWindow`/`M.refresh`/`selectTab` all take `hubStationGroupId` as an incoming argument on every call, never store their own.

Building this means introducing exactly that: a GUI-owned "currently viewed hub" that can be SET by a click inside the window itself, decoupled from (though still initialized by) the map selection. Real design questions this raises, not yet answered:
- Does clicking a map station still override the GUI's in-window hub choice on the next tick, or does the GUI's own choice "win" until the player clicks another hub row or closes/reopens the window? (The two mechanisms could easily fight each other -- e.g. player clicks "Poole Sidings" in the list, then the game's own passive re-selection logic or a stray click elsewhere on the map silently snaps it back to "Upper St Albans.")
- `M.refresh(hubStationGroupId)` is called every `guiUpdate` tick with whatever the CURRENT map selection is -- if the GUI's own hub choice is meant to persist independently, every tab's refresh path needs to start preferring an internal `state.viewedHubStationGroupId` over the incoming parameter, which touches `gui_central_raw.lua`'s core refresh/selectTab plumbing, not just the OVERVIEW tab's own rendering.

### What's already available vs. still to design

**Already available, reusable as-is**: the hub list itself (`hub_registry.getEnabledHubs()`, `stations.getEntityName()`) -- `gui_tab_hubs.lua` already builds exactly this list today, just as plain text rows, not buttons.

**Not yet designed**: the map-selection-vs-GUI-selection precedence question above; whether "switching hub in the GUI" should also pan/center the map camera to that hub (nice-to-have, matches native TF2 entity-follow behavior, unconfirmed whether this raw window type exposes anything like `setLocateButtonVisible`/a real camera-jump call) or leave the map alone entirely (simpler, avoids surprising the player by moving their camera).

### If it does pan out

Removes the last practical reason a player would need to leave the GUI and hunt the map just to check on a different hub -- directly serves the "easy way to check all hubs" goal, and is the natural completion of folding HUBS into OVERVIEW (Decision 138-era tab consolidation) rather than leaving that merge as a read-only downgrade from what the dedicated HUBS tab could already do (nothing there was ever clickable either, so this is a genuine upgrade, not just a relocation).

---

`○` = Player has the wheel.