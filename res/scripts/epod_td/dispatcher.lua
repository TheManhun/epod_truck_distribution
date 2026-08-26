-- ============================================================
-- TF2 Truck Distribution
-- dispatcher.lua
--
-- OPPORTUNISTIC DISPATCHER
--
-- Applies planner.lua's target fleet allocation for a hub by moving
-- real vehicles between managed lines -- the "Act" half of "Think
-- periodically, Act opportunistically" (IDEAS.md's "Runtime Fleet
-- Rebalancing -- Planner + Opportunistic Dispatcher").
--
-- RETIRED (Decision 31): this file previously held a single-line
-- "REVERSE DESTINATION TEST" (M.rank/getNextDestination/
-- buildDispatchPlan/executeDispatchPlan), built before Stage 1
-- (Decisions 19-23) split every multi-destination line into one
-- managed line per real destination. Ranking destinations WITHIN
-- one line no longer applies to the current architecture, and the
-- old code was never required anywhere in the mod (confirmed via a
-- full-repo search before removal) -- genuinely dead, not merely
-- unused. Replaced outright rather than layered underneath.
--
-- SAFETY RULES (all reused from elsewhere, nothing invented fresh
-- for this file):
--   * Only ever moves a vehicle confirmed EMPTY
--     (vehicles.isVehicleEmpty(id) == true) -- same Bug A avoidance
--     Stage 2/3 (line_splitter.lua/fleet_allocator.lua) already use.
--   * Only ever moves a vehicle compatible with at least one cargo
--     type the destination has real unloaded history for
--     (stations.getUnloadedCargoTypes + vehicles.isCompatibleWith-
--     CargoType, Decision 27) -- a hard prerequisite PROGRESS.md
--     already flagged before any Dispatcher could be built. See
--     stations.lua's getUnloadedCargoTypes for why this checks
--     against itemsUnloaded history rather than demand.scan()'s
--     cargoTypes -- a confirmed key-format match, not an assumed one.
--   * Uses the exact hold (setManualDeparture) -> setLine -> release
--     pattern already proven safe throughout fleet_allocator.lua,
--     line_splitter.lua, route_injector.lua -- nothing new here.
--   * Capped per run (MAX_MOVES_PER_RUN) -- a first live test should
--     move a handful of vehicles, not rebalance an entire fleet in
--     one blind click.
--   * MANUALLY TRIGGERED ONLY. Does not read the Auto Redistribute
--     toggle, does not run on a timer or on the delivery event --
--     same staged approach as every earlier stage (prove it live via
--     a manual button first). Wiring this to run automatically is a
--     deliberate later step, not this one.
--   * PER-VEHICLE COOLDOWN (Decision 32): a vehicle just moved by
--     this Dispatcher cannot be moved again for COOLDOWN_RUNS more
--     M.applyPlan calls. Added after live testing caught real
--     flapping -- 6 of the first ~20 moves across 5 runs were a
--     vehicle getting reassigned again shortly after its last
--     reassignment, 3 of them a full round trip back to their
--     original line for zero net benefit. Demand is volatile enough
--     (already observed: a destination's waiting cargo swinging from
--     0 to 10+ between two reads minutes apart) that recomputing the
--     plan "from scratch" every run can genuinely reverse its own
--     recent decision. This is a simple, self-contained fix: no new
--     time source needed (deliberately NOT os.time()/os.clock(),
--     neither ever tested in this sandbox) -- "runs" are just calls
--     to M.applyPlan, counted in-memory, resetting on reload (an
--     acceptable cost for a short-term hysteresis guard, not durable
--     state).
--   * PER-LINE DIRECTION COOLDOWN (Decision 33): the per-vehicle
--     cooldown above stops the SAME truck bouncing back and forth,
--     but live testing with it already active found a related,
--     un-caught problem: a whole LINE's correction reversing itself
--     one run later using DIFFERENT trucks (run 1 sent Queens Road
--     -> Alexander Road; runs 2-3 immediately sent Alexander Road ->
--     Queens Road, undoing it). No individual vehicle repeated, so
--     the vehicle cooldown never saw it, but it's the same underlying
--     waste -- real travel spent undoing a correction just made. A
--     line that was SURPLUS (gave vehicles away) cannot be treated as
--     DEFICIT (receive vehicles) again -- or vice versa -- for
--     LINE_DIRECTION_COOLDOWN_RUNS more runs. Recorded from the
--     Planner's classification every run a line has a nonzero delta,
--     regardless of whether MAX_MOVES_PER_RUN actually let a move
--     happen for it, so a blocked-by-cap line still "counts" as
--     having been read that way. A blocked line is simply excluded
--     from this run's queue, not forced into either direction.
-- ============================================================

local log = require("epod_td.log")
local vehicles = require("epod_td.vehicles")
local stations = require("epod_td.stations")
local planner = require("epod_td.planner")

local M = {}

local MAX_MOVES_PER_RUN = 5

-- HARD SAFETY CAP (Decision 37, added after a real, severe live
-- incident): caps TOTAL attempts (success or failure) per run,
-- independent of MAX_MOVES_PER_RUN, which only ever counted
-- successes. A vehicle whose hold/setLine command kept failing was
-- retried with no exclusion and no bound -- synchronous recursion
-- with nothing to stop it, which pinned the CPU and, per the
-- player's report, apparently crashed the game repeatedly badly
-- enough to fill crash_dump with hundreds of .dmp files in under a
-- minute. This cap is the backstop; excludedVehicleIds (see
-- findMovableVehicle) is the actual fix that stops a failed vehicle
-- from being retried at all. Lowered from 20 (Decision 38): a
-- follow-up live test showed EVERY attempted vehicle failing across
-- two separate runs (~40 attempts, 0 successes, both Alexander Road
-- and Queens Road) -- not one rare per-vehicle timing collision but
-- something systemic at this hub, so grinding through the full 20
-- every time was still causing real, if bounded, hitches ("moments"
-- of freezing) every time the threshold fired.
local MAX_ATTEMPTS_PER_RUN = 8

-- NEW (Decision 38): bail out of the WHOLE run after this many
-- CONSECUTIVE failures with no intervening success, rather than
-- always grinding to MAX_ATTEMPTS_PER_RUN. If failures are systemic
-- (the whole hub is in a bad state right now, not one unlucky
-- vehicle), continuing to try more vehicles is very likely to keep
-- failing too -- exiting fast keeps each burst small. A run with
-- occasional, scattered failures among real successes is unaffected,
-- since this only counts a streak, not a total.
local MAX_CONSECUTIVE_FAILURES = 3

-- First-guess number, not yet tuned against live data -- needs to be
-- large enough that a vehicle actually reaches and settles at its
-- new line before being reconsidered, small enough that a genuinely
-- persistent, real demand shift doesn't stay artificially blocked.
local COOLDOWN_RUNS = 3

-- Same first-guess reasoning as COOLDOWN_RUNS above, applied to a
-- whole line's surplus/deficit direction instead of one vehicle.
local LINE_DIRECTION_COOLDOWN_RUNS = 3

local runCounter = 0
local lastMovedRun = {}
local lastLineDirection = {}
local lastLineDirectionRun = {}

-- ACTIVITY LOG (player's own idea, "so the user can see wow it does
-- stuff"): one real game-time timestamp per successful vehicle move,
-- regardless of whether it came from a manual "Apply Fleet Plan"
-- click or the automatic timer -- both go through moveOneVehicle
-- below, so both count. Uses game.interface.getGameTime().time (real
-- confirmed field, milliseconds of simulated game time -- scales with
-- game speed, freezes when paused), NOT os.time(), so "moved in the
-- last 5 minutes" means 5 in-game minutes, not 5 real-world minutes
-- that might not match if the player is fast-forwarding or paused.
local recentMoveTimestamps = {}

local function getGameTimeMs()

    local ok, gameTime =
        pcall(function()
            return game.interface.getGameTime().time
        end)

    if ok and gameTime ~= nil then
        return gameTime
    end

    return nil

end

local function recordSuccessfulMove()

    local gameTimeMs = getGameTimeMs()

    if gameTimeMs ~= nil then
        recentMoveTimestamps[#recentMoveTimestamps + 1] = gameTimeMs
    end

end

-- Prunes anything older than windowMs while counting, so the list
-- stays bounded to only what's still within someone's query window
-- rather than growing forever over a long session.
function M.getRecentMoveCount(windowMs)

    local gameTimeMs = getGameTimeMs()

    if gameTimeMs == nil then
        return 0
    end

    local cutoff = gameTimeMs - windowMs

    local count = 0
    local kept = {}

    for _, timestamp in ipairs(recentMoveTimestamps) do

        if timestamp >= cutoff then
            count = count + 1
            kept[#kept + 1] = timestamp
        end

    end

    recentMoveTimestamps = kept

    return count

end


local function vehicleCompatibleWithAny(vehicleId, cargoTypes)

    if #cargoTypes == 0 then

        -- No known unloaded-cargo history at all for this
        -- destination (a brand-new or truly never-served stop) --
        -- fall back to today's documented baseline assumption (any
        -- managed vehicle can serve any managed line, PROGRESS.md)
        -- rather than refusing to move anything just because history
        -- doesn't exist yet.
        return true

    end

    for _, cargoType in ipairs(cargoTypes) do

        if vehicles.isCompatibleWithCargoType(vehicleId, cargoType) == true then
            return true
        end

    end

    return false

end


local function isInCooldown(vehicleId)

    local movedOnRun = lastMovedRun[vehicleId]

    if movedOnRun == nil then
        return false
    end

    return (runCounter - movedOnRun) < COOLDOWN_RUNS

end


-- Finds an empty, compatible, not-in-cooldown, not-already-failed-
-- this-run vehicle currently on `surplusLineId` to give to a
-- destination needing `neededCargoTypes`. Returns a vehicleId, or
-- nil if none qualify. `excludedVehicleIds` (see Decision 37) is
-- required, not optional -- a vehicle whose hold/setLine command
-- failed this run must never be handed back out as a candidate
-- again, or the exact infinite-retry bug that caused Decision 37
-- returns.
local function findMovableVehicle(surplusLineId, neededCargoTypes, excludedVehicleIds)

    local candidateIds = vehicles.getVehiclesForLine(surplusLineId)

    for _, vehicleId in ipairs(candidateIds) do

        if not excludedVehicleIds[vehicleId]
            and vehicles.isVehicleEmpty(vehicleId) == true
            and not isInCooldown(vehicleId)
            and vehicleCompatibleWithAny(vehicleId, neededCargoTypes)
        then
            return vehicleId
        end

    end

    return nil

end


local function moveOneVehicle(vehicleId, destinationLineId, destinationLabel, onComplete)

    vehicles.setManualDeparture(vehicleId, true, function(holdSuccess)

        if not holdSuccess then

            log.info(
                "DISPATCH: could not hold vehicle "
                    .. tostring(vehicleId)
                    .. " -- skipped."
            )

            onComplete(false)
            return

        end

        vehicles.setLine(vehicleId, destinationLineId, 0, function(setLineSuccess)

            vehicles.setManualDeparture(vehicleId, false, function(releaseSuccess)

                log.info(
                    "DISPATCH: vehicle "
                        .. tostring(vehicleId)
                        .. " -> "
                        .. tostring(destinationLabel)
                        .. ": "
                        .. tostring(setLineSuccess)
                        .. " (release: "
                        .. tostring(releaseSuccess)
                        .. ")"
                )

                if setLineSuccess then
                    recordSuccessfulMove()
                end

                onComplete(setLineSuccess)

            end)

        end)

    end)

end


-- Returns true if `line` just flipped direction (surplus<->deficit)
-- from its last recorded direction within LINE_DIRECTION_COOLDOWN_RUNS,
-- and should therefore be excluded from this run's queue rather than
-- allowed to reverse itself.
local function isDirectionBlocked(line, newDirection)

    local previousDirection = lastLineDirection[line.id]

    if previousDirection == nil or previousDirection == newDirection then
        return false
    end

    local previousRun = lastLineDirectionRun[line.id]

    return previousRun ~= nil
        and (runCounter - previousRun) < LINE_DIRECTION_COOLDOWN_RUNS

end


local function recordLineDirection(line, direction)

    lastLineDirection[line.id] = direction
    lastLineDirectionRun[line.id] = runCounter

end


-- Splits a planner.lua plan into deficits (delta > 0, need vehicles)
-- and surpluses (delta < 0, have spare vehicles), each tagged with
-- `.remaining` (how many more vehicles it still needs/can still
-- give), sorted largest-first so the biggest gaps get first claim.
-- A line whose direction would reverse too soon after its last
-- recorded direction (see isDirectionBlocked) is excluded entirely
-- rather than allowed to flip-flop.
local function buildMoveQueue(plan)

    local deficits = {}
    local surpluses = {}

    for _, line in ipairs(plan.lines) do

        if line.delta > 0 then

            if isDirectionBlocked(line, "deficit") then

                log.info(
                    "DISPATCH: "
                        .. tostring(line.name)
                        .. " reads as needing vehicles, but was surplus "
                        .. "too recently -- skipping this run to avoid "
                        .. "reversing itself."
                )

            else

                line.remaining = line.delta
                deficits[#deficits + 1] = line
                recordLineDirection(line, "deficit")

            end

        elseif line.delta < 0 then

            if isDirectionBlocked(line, "surplus") then

                log.info(
                    "DISPATCH: "
                        .. tostring(line.name)
                        .. " reads as having surplus, but was in deficit "
                        .. "too recently -- skipping this run to avoid "
                        .. "reversing itself."
                )

            else

                line.remaining = -line.delta
                surpluses[#surpluses + 1] = line
                recordLineDirection(line, "surplus")

            end

        end

    end

    table.sort(deficits, function(a, b) return a.delta > b.delta end)
    table.sort(surpluses, function(a, b) return a.delta < b.delta end)

    return deficits, surpluses

end


local function processMoveNext(context)

    context.attempts = context.attempts + 1

    if context.attempts > MAX_ATTEMPTS_PER_RUN then

        log.info(
            "DISPATCH: reached MAX_ATTEMPTS_PER_RUN ("
                .. tostring(MAX_ATTEMPTS_PER_RUN)
                .. ") -- stopping for this run (repeated failures)."
        )

        context.onComplete(context.movesMade)
        return

    end

    if context.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES then

        log.info(
            "DISPATCH: "
                .. tostring(context.consecutiveFailures)
                .. " consecutive failures -- stopping this run early "
                .. "(likely systemic, not one bad vehicle)."
        )

        context.onComplete(context.movesMade)
        return

    end

    if context.movesMade >= MAX_MOVES_PER_RUN then

        log.info(
            "DISPATCH: reached MAX_MOVES_PER_RUN ("
                .. tostring(MAX_MOVES_PER_RUN)
                .. ") -- stopping for this run."
        )

        context.onComplete(context.movesMade)
        return

    end

    local deficit = context.deficits[context.deficitIndex]

    if deficit == nil then

        log.info(
            "DISPATCH COMPLETE: "
                .. tostring(context.movesMade)
                .. " vehicle(s) moved."
        )

        context.onComplete(context.movesMade)
        return

    end

    if deficit.remaining <= 0 then

        context.deficitIndex = context.deficitIndex + 1
        processMoveNext(context)
        return

    end

    local surplus = context.surpluses[context.surplusIndex]

    if surplus == nil then

        log.info(
            "DISPATCH: no more surplus lines -- "
                .. tostring(deficit.name)
                .. " still short "
                .. tostring(deficit.remaining)
                .. "."
        )

        context.deficitIndex = context.deficitIndex + 1
        processMoveNext(context)
        return

    end

    if surplus.remaining <= 0 then

        context.surplusIndex = context.surplusIndex + 1
        processMoveNext(context)
        return

    end

    local neededCargoTypes =
        stations.getUnloadedCargoTypes(deficit.destinationStationGroup)

    local vehicleId =
        findMovableVehicle(surplus.id, neededCargoTypes, context.excludedVehicleIds)

    if vehicleId == nil then

        log.info(
            "DISPATCH: no eligible vehicle (empty + compatible + not "
                .. "in cooldown) on "
                .. tostring(surplus.name)
                .. " for "
                .. tostring(deficit.name)
                .. " -- trying next surplus line."
        )

        context.surplusIndex = context.surplusIndex + 1
        processMoveNext(context)
        return

    end

    log.info(
        "DISPATCH: moving vehicle "
            .. tostring(vehicleId)
            .. " from "
            .. tostring(surplus.name)
            .. " -> "
            .. tostring(deficit.name)
    )

    moveOneVehicle(vehicleId, deficit.id, deficit.name, function(success)

        if success then

            deficit.remaining = deficit.remaining - 1
            surplus.remaining = surplus.remaining - 1
            context.movesMade = context.movesMade + 1
            lastMovedRun[vehicleId] = runCounter
            context.consecutiveFailures = 0

        else

            -- Never retry a vehicle that just failed -- this is the
            -- actual fix for Decision 37's incident. Without this,
            -- findMovableVehicle would hand the exact same vehicle
            -- straight back out again next call.
            context.excludedVehicleIds[vehicleId] = true
            context.consecutiveFailures = context.consecutiveFailures + 1

        end

        processMoveNext(context)

    end)

end


-- REENTRANCY GUARD (added after a real live incident, Decision 36):
-- each move is 3 async API calls (hold -> setLine -> release); if
-- something calls M.applyPlan again before a previous call's async
-- chain has finished, the two runs' commands could interleave and
-- pile up rather than the second one waiting its turn. Combined with
-- AUTO_DISPATCH_DELIVERY_THRESHOLD being set far too low relative to
-- real observed delivery rates (attemptAutoDispatch could trigger
-- multiple times per second during a delivery burst), this produced
-- a genuine, serious hang -- the game became unresponsive with audio
-- stutter and had to be force-closed. This guard is the structural
-- fix: no matter how often something tries to call M.applyPlan, only
-- one run is ever actually in flight at a time; a call arriving
-- while one is already running is refused outright rather than
-- queued or interleaved.
--
-- KEYED BY HUB (Decision 44, multi-hub): a bare boolean would refuse
-- hub B's run just because hub A's is still in flight, even though
-- they touch completely disjoint lines and vehicles and have no
-- reason to block each other -- e.g. the automatic poll working
-- through hub A while the player manually clicks "Apply Fleet Plan"
-- for hub B. Only the SAME hub being re-entered (the actual Decision
-- 36 scenario) is still refused.
local applyPlanRunningByHub = {}


-- Applies planner.lua's current target allocation for `hubStationGroup`
-- by moving real, empty, compatible vehicles between managed lines,
-- up to MAX_MOVES_PER_RUN. Manually triggered or called from
-- attemptAutoDispatch -- see file header. onComplete(movesMade)
-- fires once no more moves are possible, the cap is reached, or this
-- call was refused because another run for this same hub is already
-- in flight.
function M.applyPlan(hubStationGroup, onComplete)

    if applyPlanRunningByHub[hubStationGroup] then

        log.info(
            "APPLY FLEET PLAN: a previous run for hub "
                .. tostring(hubStationGroup)
                .. " is still in flight -- refusing this call rather "
                .. "than overlapping it."
        )

        if onComplete ~= nil then
            onComplete(0)
        end

        return

    end

    applyPlanRunningByHub[hubStationGroup] = true

    local function finish(movesMade)

        applyPlanRunningByHub[hubStationGroup] = nil

        if onComplete ~= nil then
            onComplete(movesMade)
        end

    end

    runCounter = runCounter + 1

    log.info("----------------------------------------")
    log.info("APPLY FLEET PLAN (run " .. tostring(runCounter) .. ")")
    log.info("----------------------------------------")

    local plan = planner.calculateTargetAllocation(hubStationGroup)

    if #plan.lines == 0 then

        log.info("Nothing to do: no managed lines at this hub.")
        finish(0)
        return

    end

    local deficits, surpluses = buildMoveQueue(plan)

    if #deficits == 0 then

        log.info("Nothing to do: no line currently needs more vehicles.")
        finish(0)
        return

    end

    processMoveNext({
        deficits = deficits,
        surpluses = surpluses,
        deficitIndex = 1,
        surplusIndex = 1,
        movesMade = 0,
        attempts = 0,
        consecutiveFailures = 0,
        excludedVehicleIds = {},
        onComplete = finish
    })

end


return M
