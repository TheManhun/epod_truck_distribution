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
-- ============================================================

local log = require("epod_td.log")
local vehicles = require("epod_td.vehicles")
local stations = require("epod_td.stations")
local planner = require("epod_td.planner")

local M = {}

local MAX_MOVES_PER_RUN = 5

-- First-guess number, not yet tuned against live data -- needs to be
-- large enough that a vehicle actually reaches and settles at its
-- new line before being reconsidered, small enough that a genuinely
-- persistent, real demand shift doesn't stay artificially blocked.
local COOLDOWN_RUNS = 3

local runCounter = 0
local lastMovedRun = {}


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


-- Finds an empty, compatible, not-in-cooldown vehicle currently on
-- `surplusLineId` to give to a destination needing
-- `neededCargoTypes`. Returns a vehicleId, or nil if none qualify.
local function findMovableVehicle(surplusLineId, neededCargoTypes)

    local candidateIds = vehicles.getVehiclesForLine(surplusLineId)

    for _, vehicleId in ipairs(candidateIds) do

        if vehicles.isVehicleEmpty(vehicleId) == true
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

                onComplete(setLineSuccess)

            end)

        end)

    end)

end


-- Splits a planner.lua plan into deficits (delta > 0, need vehicles)
-- and surpluses (delta < 0, have spare vehicles), each tagged with
-- `.remaining` (how many more vehicles it still needs/can still
-- give), sorted largest-first so the biggest gaps get first claim.
local function buildMoveQueue(plan)

    local deficits = {}
    local surpluses = {}

    for _, line in ipairs(plan.lines) do

        if line.delta > 0 then

            line.remaining = line.delta
            deficits[#deficits + 1] = line

        elseif line.delta < 0 then

            line.remaining = -line.delta
            surpluses[#surpluses + 1] = line

        end

    end

    table.sort(deficits, function(a, b) return a.delta > b.delta end)
    table.sort(surpluses, function(a, b) return a.delta < b.delta end)

    return deficits, surpluses

end


local function processMoveNext(context)

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
        findMovableVehicle(surplus.id, neededCargoTypes)

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

        end

        processMoveNext(context)

    end)

end


-- Applies planner.lua's current target allocation for `hubStationGroup`
-- by moving real, empty, compatible vehicles between managed lines,
-- up to MAX_MOVES_PER_RUN. Manually triggered only -- see file
-- header. onComplete(movesMade) fires once no more moves are
-- possible or the cap is reached.
function M.applyPlan(hubStationGroup, onComplete)

    runCounter = runCounter + 1

    log.info("----------------------------------------")
    log.info("APPLY FLEET PLAN (run " .. tostring(runCounter) .. ")")
    log.info("----------------------------------------")

    local plan = planner.calculateTargetAllocation(hubStationGroup)

    if #plan.lines == 0 then

        log.info("Nothing to do: no managed lines at this hub.")

        if onComplete ~= nil then
            onComplete(0)
        end

        return

    end

    local deficits, surpluses = buildMoveQueue(plan)

    if #deficits == 0 then

        log.info("Nothing to do: no line currently needs more vehicles.")

        if onComplete ~= nil then
            onComplete(0)
        end

        return

    end

    processMoveNext({
        deficits = deficits,
        surpluses = surpluses,
        deficitIndex = 1,
        surplusIndex = 1,
        movesMade = 0,
        onComplete = onComplete or function() end
    })

end


return M
