https://wiki.transportfever2.com/api/modules/api.cmd.html

# `api.cmd.make.*` Command Reference

The full command surface, confirmed real via a live `pairs()` dump of `api.cmd.make` in this exact game version (`dumpAvailableCommands`, `epod_truck_distribution.lua`) — 33 commands, first captured and logged in `EPOD-LOG.txt`.

**Being present in this list only means the command exists.** It says nothing about what arguments it takes, what entity types it accepts, or whether it actually works the way its name implies — that has to be checked separately, the same evidence-first discipline as everything else in this project (`DECISIONS.md` Decision 13). This file exists so that check only has to happen once per command, not get re-litigated from a blank slate every time it comes up.

## Confirmed used, live, by this mod

| Command | Where | What for |
|---|---|---|
| `createLine` | `line_splitter.lua`, `route_injector.lua` | Creates a new line with a name/color/stops baked in at creation time (see Decision 19) — **not** a rename mechanism for an existing line. |
| `deleteLine` | `line_splitter.lua` | Deletes a line once confirmed empty (Decision 23). |
| `updateLine` | `terminal_allocator.lua` | Rewrites an existing line's stop data — this is how terminal assignment actually gets written (Decision 21/22). |
| `setLine` | `vehicles.lua` | Reassigns a vehicle to a different line (Decision 20). |
| `setVehicleManualDeparture` | `vehicles.lua` | Holds/releases a vehicle at its current stop — used as a safe "pause" before/after `setLine`. |
| `reverseVehicle` | `dispatcher.lua`, `route_injector.lua` | Reverses a vehicle's direction — proven only on a vehicle already stopped at a terminal (see `IDEAS.md`'s "Detect-empty-and-reverse"). |
| `setName` | `route_injector.lua` (`testVehicleRenameAndColor`), `fleet_naming.lua` | **Confirmed to work on a VEHICLE entity**, not just lines — renamed vehicle 141339, verified by re-reading the entity (not just the command's success flag), then restored. Now used for real by `fleet_naming.M.renameFleetToHubIdentity`, live-run against a real ~90+ vehicle fleet with no restore step (see `IDEAS.md`). See the `setName`/`setColor` section below for the full trace. |
| `setColor` | `route_injector.lua` (`testVehicleRenameAndColor`) | **Confirmed to work on a VEHICLE entity, visually.** No color field exists to re-read programmatically (see below), so this was confirmed by accident: the test vehicle (141339) was left magenta/purple (never restored, by design) and the player spotted it running around the map afterward, unmistakably the test's `Vec3f(1.0, 0.0, 1.0)` colour. Real, visible, in-game confirmation — stronger than the command's own `RESULT: true` flag alone. |

## Confirmed used, live, by a reference mod (not by us)

Found in **LineManager** (workshop mod `2581894757`, `res/scripts/cartok/api_helper.lua`) — real, working calls in shipped, published mod code, just never exercised by this project:

| Command | Usage in LineManager |
|---|---|
| `buyVehicle` | `api_helper.buyVehicle(depot_id, transportVehicleConfig, callback)` — full purchase flow. |
| `sellVehicle` | `api_helper.sellVehicle(vehicle_id)`. |
| `sendToDepot` | `api_helper.sendVehicleToDepot(vehicle_id, sell_on_arrival)`. |

## Present in the command surface, unconfirmed by anyone checked so far

Real commands (confirmed present in the live dump), but **not found actually invoked** in this mod's own code *or* in LineManager's:

`setAnimalState`, `spawnAnimal`, `removeTown`, `developTown`, `sendScriptEvent`, `replaceVehicle`, `bookJournalEntry`, `removeField`, `connectTownsAndIndustries`, `createTowns`, `setUserStopped`, `instantlyUpdateTownCargoNeeds`, `buildProposal`, `setSimBuildingClosureTimeStamp`, `setTownInfo`, `setVehicleTargetMaintenanceState`, `setCalendarSpeed`, `setDate`, `setSimBuildingManualDevelopment`, `setGameSpeed`, `replaceTerrain`, `setVehicleShouldDepart`

(`setName` and `setColor` both moved to the confirmed table above.)

**`setName` specifically** is worth flagging: it's the one this project most recently wanted (per-vehicle renaming, `IDEAS.md`'s hub-identity naming idea). Checked directly against LineManager — despite that mod's whole purpose being line renaming, `setName` appears **only** in a static reference-list file it bundles (`general.lua`, the same kind of command dump this file itself is built from), never in a real function call anywhere in its actual logic. LineManager's rename *suggestions* appear to be display-only, for the player to type in manually via TF2's own UI — not applied programmatically. This means `setName` working on a vehicle (or even on an existing line, post-creation) is **completely unconfirmed by any code we've checked** — a live test is needed before any feature assumes it works, exactly the kind of gap the original `●` line-name situation (Decision 26) already showed is worth checking rather than assuming.

**Official docs checked** (https://wiki.transportfever2.com/api/modules/api.cmd.html, linked at the top of this file): both `setName(entity, name)` and `setColor(entity, color)` are documented with fully generic, entity-agnostic signatures — "the entity Id of the entity that should be renamed/coloured," no restriction to lines. `color` is `type.Vec3f`, matching the format already used for `createLine`'s color argument.

**Now live-verified, matching the docs.** `route_injector.M.testVehicleRenameAndColor` ran against vehicle 141339: `BEFORE: name=Road vehicle 74` → `setName RESULT: true` → `AFTER RENAME: name=● RENAME TEST 141339` (confirmed by re-reading the entity, not just trusting the command's success flag) → restored → `AFTER RESTORE: name=Road vehicle 74`. **`setName` is confirmed to work on a vehicle entity.** The player initially thought nothing had happened because the test renames and restores within the same click, milliseconds apart, specifically so it never leaves a real vehicle renamed — there's no real-world window to visually catch the change mid-test, only the log's before/after reads prove it happened.

**`setColor` confirmed too, by accident.** No colour field exists on a vehicle to re-read programmatically, so the test's `RESULT: true` alone wasn't full proof — but the test deliberately never restores colour (nothing to restore to), so vehicle 141339 was left magenta/purple (`Vec3f(1.0, 0.0, 1.0)`). Several real-time minutes later the player spotted a lone purple horse-and-cart running around the map, unprompted, and correctly connected it back to the earlier test. That's genuine, unambiguous visual confirmation. `fleet_naming.lua`'s real rename feature was then built and live-run against a real fleet (~90+ vehicles), confirming `setName` holds up at scale too, not just on one test vehicle.

## Maintenance

Update this file directly whenever a command moves tiers (unconfirmed → confirmed, or a new reference mod turns up more real usage) rather than re-deriving it from scratch. Cross-reference from `TECHNICAL_RESEARCH.md`/`DECISIONS.md` rather than duplicating this table elsewhere.
