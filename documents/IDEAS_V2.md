# IDEAS_V2.md — Future / Post-V1 Concepts

This file is deliberately separate from `IDEAS.md`. `IDEAS.md` holds ideas that
could plausibly land inside the current build once tested. Everything in this
file is scoped to a hypothetical V2 — a custom-built visual/gameplay layer on
top of the brain, not something to start work on now.

Nothing here is authorized against the current feature freeze. Entries here
should still follow the same discipline as `IDEAS.md` (Origin / The idea /
Confirmed vs. story / If it pans out) so they're ready to evaluate seriously
once V1 is actually done, not just vague aspirations.

---

## Custom Distribution Hub with visible parking/standby trucks

### Origin

Grew out of tonight's `setVehicleManualDeparture` research item. Originally
the "physical Distribution Centre" idea (Decision 12, MASTERPLAN Stage 5)
looked like it required authoring real terminal/queue logic from scratch —
the same complexity that sank the archived single-bay attempt. Finding a
plausible way to hold a *real* vehicle at an ordinary terminal via manual
departure reframes the problem: the hub might not need custom terminal logic
at all, just a nice building and a proven way to hold/release real trucks at
it.

### The idea

A custom-built, era-appropriate Distribution Hub construction (using the
Ground/Fence/GatePosts groundwork already built in Blender) where surplus
trucks visibly park and wait until the planner needs them, then pull away on
cue — the "wow factor" being genuinely idle, parked vehicles a player can
see, not just a UI number.

Two build strategies, not yet chosen between:
- Clone the simple vanilla depot's entrance/snapNodes edge pattern (proven,
  low-risk, already read directly from `depot/road_depot_era_a.con`).
- Follow MadHatter's `mdhtr_distribution` mod's approach — a real, published,
  working example of a custom building with a road-connected entrance, using
  the same simple depot-entrance script rather than the full modular terminal
  system.

Either way, the "parking" itself would be `setVehicleManualDeparture` holding
a real fleet vehicle at the hub's terminal — not a custom queue/bay system,
and not the sentinel-vehicle idea (that's a separate, independent concept in
`IDEAS.md` for keeping a line's demand connection alive, not for visual
parking).

### What's actually confirmed vs. still a story

**Confirmed:**
- The simple depot entrance/edge pattern is real and readable directly from
  TF2's own vanilla files (`depot/road_depot_era_a.con`).
- A real, published community mod (MadHatter's `mdhtr_distribution`) combines
  a custom building with this exact simple road-connection pattern
  successfully.
- The Ground/Fence/GatePosts visual base and era-upgrade/size-choice concept
  already exist from tonight's Blender work.

**Not yet confirmed — inherits these directly, does not re-litigate them:**
- `setVehicleManualDeparture` itself: whether a vehicle can arrive, be held
  indefinitely, be safely reassigned while empty, and released cleanly —
  this is an open research item, not proven.
- Whether a held vehicle blocks terminal/path access for others, and whether
  its line/cargo connection remains valid while held.
- How many vehicles can be held at once before hitting the "Hendon East
  traffic apocalypse" limit already flagged when this idea first came up.

### Explicit dependency gate — do not start before these

This idea is gated behind, in order:
1. `PROGRESS.md` Not Started #1 (the two Partial safety gaps — loaded-vehicle
   reassignment safety, and the Park-stop pickup bug) — everything downstream
   assumes reassignment is actually safe.
2. `PROGRESS.md` Not Started #2 (persistence) — a hub full of parked trucks
   that resets on every reload isn't a real feature.
3. `PROGRESS.md` Not Started #3 (change-driven demand reassessment) — parking
   only makes sense once there's a real trigger deciding when a truck should
   idle vs. serve, not just manual button presses.
4. The `setVehicleManualDeparture` research item itself (already logged in
   `IDEAS.md`) resolving to a confirmed yes.

### If it pans out

Becomes the actual Stage 5 payoff referenced in `MASTERPLAN.md` — turns the
already-built Blender groundwork (ground, fence, gate posts, era-scaling
concept) from a technical Park-stop workaround into the real, visible feature
players see and want. Should not be started, even as a prototype, before the
gate above is cleared — the same lesson as "eliminate empty runs" on the
concept poster: don't ship the exciting visual ahead of the mechanism it
depends on actually being proven.
