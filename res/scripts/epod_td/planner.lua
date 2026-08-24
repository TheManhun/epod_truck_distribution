-- ============================================================
-- TF2 Truck Distribution
-- planner.lua
--
-- PERIODIC PLANNER (READ-ONLY)
--
-- "Think periodically. Act opportunistically." -- IDEAS.md's
-- "Runtime Fleet Rebalancing -- Planner + Opportunistic Dispatcher".
--
-- Calculates the TARGET fleet allocation for a hub's managed lines,
-- weighted by current demand.scan() waiting cargo -- the same
-- proven apportionment technique fleet_allocator.lua already uses
-- for the one-time spare-pool split (Stage 3), applied here to the
-- hub's WHOLE fleet instead of just a spare remainder.
--
-- DOES NOT:
--   * move any vehicle
--   * call setLine / setManualDeparture / any api.cmd.make.* command
--   * depend on the Auto Redistribute toggle (settings.lua) -- the
--     Planner always calculates, regardless of whether a future
--     Dispatcher is allowed to act on it. That gating happens one
--     layer up, never in here (agreed design principle, IDEAS.md).
--
-- NOT YET INCLUDED (deliberately -- see IDEAS.md's cargo-profile
-- refinement, Decision 28): this first pass weighs CURRENT waiting
-- cargo only, the same signal fleet_allocator.lua already uses. The
-- historical itemsLoaded/itemsUnloaded._lastMonth/_lastYear
-- per-cargo-type breakdown is now confirmed readable (Decision 28)
-- but not yet folded into this weighting, and no per-vehicle cargo-
-- compatibility sub-pooling (Decision 27) is applied yet either --
-- this version assumes any managed vehicle can serve any managed
-- line. Both are real, planned refinements, not built blind ahead of
-- a working baseline.
-- ============================================================

local log = require("epod_td.log")
local lines = require("epod_td.lines")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local managed_registry = require("epod_td.managed_registry")

local M = {}


-- A managed line always keeps at least this many vehicles in its
-- target -- the Planner reports a SHORTAGE or SURPLUS against a
-- floor, it never proposes emptying a line down to zero. Retiring a
-- line entirely is a deliberate, separate action ("Safe Close
-- Managed Line", IDEAS.md), not something the Planner should imply
-- just because it's quiet right now.
local MINIMUM_VEHICLES_PER_LINE = 1


local function findDestinationStationGroup(lineId, hubStationGroup)

    local line = lines.get(lineId)

    if line == nil then
        return nil
    end

    local stops = lines.safeField(line, "stops")
    local stopCount = lines.safeLength(stops)

    for index = 1, stopCount do

        local stop = stops[index]

        if stop ~= nil then

            local stationGroup = lines.safeField(stop, "stationGroup")

            if stationGroup ~= nil and stationGroup ~= hubStationGroup then
                return stationGroup
            end

        end

    end

    return nil

end


-- Every managed line touching this hub, with its current waiting
-- demand and current vehicle count. Deliberately hub-scoped the same
-- way fleet_naming.lua's lineTouchesHub is -- a managed line
-- belonging to a DIFFERENT hub must never leak into this hub's plan.
local function collectManagedLineCandidates(hubStationGroup)

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    local candidates = {}

    if not ok or allLineIds == nil then
        return candidates
    end

    for _, lineId in ipairs(allLineIds) do

        if managed_registry.isManaged(lineId) then

            local destinationStationGroup =
                findDestinationStationGroup(lineId, hubStationGroup)

            if destinationStationGroup ~= nil then

                local scanResult =
                    demand.scan(lineId, hubStationGroup)

                local waiting =
                    (scanResult ~= nil and scanResult.totalWaiting) or 0

                candidates[#candidates + 1] = {
                    id = lineId,
                    name = lines.getName(lineId),
                    destinationStationGroup = destinationStationGroup,
                    waiting = waiting,
                    currentVehicleCount = #vehicles.getVehiclesForLine(lineId)
                }

            end

        end

    end

    return candidates

end


-- Largest-remainder apportionment of `pool` whole vehicles across
-- `candidates`, weighted by each candidate's .waiting. Candidates
-- with .waiting == 0 get none of the pool -- same rule
-- fleet_allocator.lua's apportionByDemand already uses: a
-- destination showing no demand right now isn't given capacity it
-- hasn't shown a need for, beyond its floor.
local function apportionPoolByDemand(candidates, pool)

    local weighted = {}
    local totalWeight = 0

    for _, candidate in ipairs(candidates) do

        if candidate.waiting > 0 then
            weighted[#weighted + 1] = candidate
            totalWeight = totalWeight + candidate.waiting
        end

    end

    local shares = {}

    for _, candidate in ipairs(candidates) do
        shares[candidate.id] = 0
    end

    if totalWeight == 0 or pool <= 0 then
        return shares
    end

    local entries = {}
    local assigned = 0

    for _, candidate in ipairs(weighted) do

        local raw = pool * candidate.waiting / totalWeight
        local base = math.floor(raw)

        entries[#entries + 1] = {
            candidate = candidate,
            base = base,
            remainder = raw - base
        }

        assigned = assigned + base

    end

    local leftover = pool - assigned

    if leftover > 0 then

        table.sort(entries, function(a, b)
            return a.remainder > b.remainder
        end)

        for index = 1, leftover do

            local entry = entries[index]

            if entry ~= nil then
                entry.base = entry.base + 1
            end

        end

    end

    for _, entry in ipairs(entries) do
        shares[entry.candidate.id] = entry.base
    end

    return shares

end


-- Returns:
-- {
--   hubStationGroup = ...,
--   totalVehicles = ...,
--   totalWaiting = ...,
--   lines = {
--     { id, name, waiting, currentVehicleCount, targetVehicleCount, delta },
--     ...
--   }
-- }
function M.calculateTargetAllocation(hubStationGroup)

    local candidates = collectManagedLineCandidates(hubStationGroup)

    if #candidates == 0 then
        return {
            hubStationGroup = hubStationGroup,
            totalVehicles = 0,
            totalWaiting = 0,
            lines = {}
        }
    end

    local totalVehicles = 0
    local totalWaiting = 0

    for _, candidate in ipairs(candidates) do
        totalVehicles = totalVehicles + candidate.currentVehicleCount
        totalWaiting = totalWaiting + candidate.waiting
    end

    -- Every candidate reserves its floor first; only the remainder
    -- gets apportioned by demand. If there are more managed lines
    -- than total vehicles (fleet smaller than the floor requires --
    -- an edge case, not the normal shape of this problem), floors
    -- are handed out one at a time until vehicles run out rather
    -- than going negative.
    local floors = {}
    local floorPoolRemaining = totalVehicles

    for _, candidate in ipairs(candidates) do

        if floorPoolRemaining >= MINIMUM_VEHICLES_PER_LINE then
            floors[candidate.id] = MINIMUM_VEHICLES_PER_LINE
            floorPoolRemaining = floorPoolRemaining - MINIMUM_VEHICLES_PER_LINE
        else
            floors[candidate.id] = 0
        end

    end

    local floorSum = totalVehicles - floorPoolRemaining
    local pool = totalVehicles - floorSum

    local shares = apportionPoolByDemand(candidates, pool)

    local resultLines = {}

    for _, candidate in ipairs(candidates) do

        local target =
            (floors[candidate.id] or 0) + (shares[candidate.id] or 0)

        resultLines[#resultLines + 1] = {
            id = candidate.id,
            name = candidate.name,
            waiting = candidate.waiting,
            currentVehicleCount = candidate.currentVehicleCount,
            targetVehicleCount = target,
            delta = target - candidate.currentVehicleCount
        }

    end

    return {
        hubStationGroup = hubStationGroup,
        totalVehicles = totalVehicles,
        totalWaiting = totalWaiting,
        lines = resultLines
    }

end


function M.logTargetAllocation(hubStationGroup, hubName)

    local plan = M.calculateTargetAllocation(hubStationGroup)

    log.info("----------------------------------------")
    log.info(
        "FLEET PLAN: " .. tostring(hubName)
            .. " -- " .. tostring(plan.totalVehicles) .. " managed vehicle(s), "
            .. tostring(plan.totalWaiting) .. " total waiting"
    )
    log.info("----------------------------------------")

    if plan.totalWaiting == 0 and #plan.lines > 0 then

        log.info(
            "NOTE: no managed line at this hub currently shows any "
                .. "waiting demand -- target below reflects only the "
                .. "per-line floor ("
                .. tostring(MINIMUM_VEHICLES_PER_LINE)
                .. "), not a confident read of real need. Treat as "
                .. "low-confidence until demand shows up again."
        )

    end

    for _, line in ipairs(plan.lines) do

        local sign = ""

        if line.delta > 0 then
            sign = "+"
        end

        log.info(
            "  "
                .. tostring(line.name)
                .. " | waiting=" .. tostring(line.waiting)
                .. " | current=" .. tostring(line.currentVehicleCount)
                .. " | target=" .. tostring(line.targetVehicleCount)
                .. " | delta=" .. sign .. tostring(line.delta)
        )

    end

    log.info("----------------------------------------")

    return plan

end


return M
