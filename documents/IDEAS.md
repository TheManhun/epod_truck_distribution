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

**SUPERSEDED by Decision 42, not yet live-tested.** The demand-ranked single-dedicated-terminal-per-line model described below (rebuild the whole `Line`, write one `Line.Stop.terminal` value) has been replaced in `terminal_allocator.lua` with a much simpler shared-pool model: every managed line's hub stop gets the SAME full set of terminals via the (previously unused) `Line.Stop.alternativeTerminals` field and `api.cmd.make.setLineStopAlternativeTerminals`, letting TF2's own vehicle terminal-selection balance load per trip instead of the mod computing an assignment. If that command turns out not to exist/work as hoped, this section's original design (and its git history) is the fallback to revert to — kept below for that reason, not as active guidance.

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

`○` = Player has the wheel.