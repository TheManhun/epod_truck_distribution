local log = require("epod_td.log")
local lines = require("epod_td.lines")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local managed_registry = require("epod_td.managed_registry")

local M = {}


-- ============================================================
-- REDISTRIBUTE SPARE VEHICLES ACROSS MANAGED SPLIT LINES,
-- WEIGHTED BY CURRENT DEMAND
--
-- Stage 3: line_splitter.lua's Stage 2 seeds every split line with
-- exactly one vehicle, pulled one at a time off the source line.
-- Whatever is left on the source line afterward (its remaining
-- fleet -- Stage 2 already retired every real stop it had, so it
-- is now serving nothing) sits idle. This distributes that
-- remainder across the real destination lines proportionally to
-- each one's current demand.scan() waiting total, per the design
-- agreed live: a destination currently showing 0 waiting demand
-- gets none of the spare pool and stays at its single seed truck --
-- not starved further, but not given capacity it has shown no need
-- for either.
--
-- CAVEAT (player-reported game mechanic, not yet independently
-- verified through the API): a terminal's waiting-cargo storage is
-- finite -- reportedly on the order of 100-200 per terminal
-- depending on its length, extendable by lengthening the terminal
-- or attaching warehouses. Cargo generated beyond that cap
-- despawns rather than continuing to accumulate. That means a
-- destination's "waiting" total is a FLOOR on its true demand, not
-- necessarily an accurate relative measure between two
-- destinations with different terminal capacities -- one could be
-- silently losing cargo to despawn while reading a similar or
-- lower waiting count than another that is not capped yet. This
-- allocator uses the visible waiting total as its best available
-- proxy anyway (no API for terminal capacity itself has been found
-- -- see TECHNICAL_RESEARCH.md), but that limitation should be kept
-- in mind when judging whether the resulting split actually matches
-- real need.
-- ============================================================

local function findDestinationStationGroupOnSplitLine(splitLineId, hubStationGroup)

    local splitLine = lines.get(splitLineId)

    if splitLine == nil then
        return nil
    end

    local splitStops = lines.safeField(splitLine, "stops")
    local splitCount = lines.safeLength(splitStops)

    for index = 1, splitCount do

        local stop = splitStops[index]

        if stop ~= nil then

            local stationGroup = lines.safeField(stop, "stationGroup")

            if stationGroup ~= nil and stationGroup ~= hubStationGroup then
                return stationGroup
            end

        end

    end

    return nil

end


local function findManagedSplitLines(hubStationGroup)

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    local candidates = {}

    if not ok or allLineIds == nil then
        return candidates
    end

    for _, lineId in ipairs(allLineIds) do

        local name = lines.getName(lineId)

        if managed_registry.isManaged(lineId) then

            local destinationStationGroup =
                findDestinationStationGroupOnSplitLine(lineId, hubStationGroup)

            if destinationStationGroup ~= nil then

                local scanResult =
                    demand.scan(lineId, hubStationGroup)

                local waiting =
                    (scanResult ~= nil and scanResult.totalWaiting) or 0

                candidates[#candidates + 1] = {
                    id = lineId,
                    name = name,
                    destinationStationGroup = destinationStationGroup,
                    waiting = waiting,
                    vehicleCount = #vehicles.getVehiclesForLine(lineId)
                }

            end

        end

    end

    return candidates

end


-- Largest-remainder apportionment: splits `totalSpare` whole
-- vehicles across `candidates` (each with a .waiting weight)
-- proportionally, guaranteed to sum to exactly totalSpare unless
-- totalSpare is 0 or every candidate's weight is 0. Candidates with
-- .waiting == 0 are excluded entirely -- they get no share, per the
-- agreed rule.
local function apportionByDemand(candidates, totalSpare)

    local weighted = {}
    local totalWeight = 0

    for _, candidate in ipairs(candidates) do

        if candidate.waiting > 0 then
            weighted[#weighted + 1] = candidate
            totalWeight = totalWeight + candidate.waiting
        end

    end

    if totalWeight == 0 or totalSpare <= 0 then
        return {}
    end

    local shares = {}
    local assigned = 0

    for _, candidate in ipairs(weighted) do

        local raw = totalSpare * candidate.waiting / totalWeight
        local base = math.floor(raw)

        shares[#shares + 1] = {
            candidate = candidate,
            base = base,
            remainder = raw - base
        }

        assigned = assigned + base

    end

    local leftover = totalSpare - assigned

    if leftover > 0 then

        local ordered = {}

        for _, entry in ipairs(shares) do
            ordered[#ordered + 1] = entry
        end

        table.sort(ordered, function(a, b)
            return a.remainder > b.remainder
        end)

        for index = 1, leftover do

            local entry = ordered[index]

            if entry ~= nil then
                entry.base = entry.base + 1
            end

        end

    end

    local result = {}

    for _, entry in ipairs(shares) do

        if entry.base > 0 then

            result[#result + 1] = {
                candidate = entry.candidate,
                count = entry.base
            }

        end

    end

    return result

end


local function assignVehiclesToLine(vehicleIds, cursor, destinationLineId, destinationLabel, count, callback)

    if count <= 0 then
        callback(cursor)
        return
    end

    local vehicleId = vehicleIds[cursor]

    if vehicleId == nil then

        log.info(
            "REDISTRIBUTE: ran out of spare vehicles while still "
                .. "owing "
                .. tostring(count)
                .. " to "
                .. tostring(destinationLabel)
        )

        callback(cursor)
        return

    end

    -- Skip a vehicle currently carrying cargo (or whose load
    -- couldn't be confirmed) rather than reassigning it -- sidesteps
    -- Bug A (PROGRESS.md) instead of testing whether it happens to
    -- be safe. This candidate does not count against `count`: it was
    -- never actually used, just passed over, so the next real
    -- candidate still owes the full remaining count.
    if vehicles.isVehicleEmpty(vehicleId) ~= true then

        log.info(
            "REDISTRIBUTE: skipping vehicle "
                .. tostring(vehicleId)
                .. " (currently carrying cargo or load unknown) -- "
                .. "avoiding Bug A (PROGRESS.md)"
        )

        assignVehiclesToLine(vehicleIds, cursor + 1, destinationLineId, destinationLabel, count, callback)
        return

    end

    vehicles.setManualDeparture(vehicleId, true, function(holdSuccess)

        if not holdSuccess then

            log.info(
                "REDISTRIBUTE FAILED (could not hold vehicle "
                    .. tostring(vehicleId)
                    .. "): "
                    .. tostring(destinationLabel)
            )

            assignVehiclesToLine(vehicleIds, cursor + 1, destinationLineId, destinationLabel, count - 1, callback)
            return

        end

        vehicles.setLine(vehicleId, destinationLineId, 0, function(setLineSuccess)

            vehicles.setManualDeparture(vehicleId, false, function(releaseSuccess)

                log.info(
                    "REDISTRIBUTE: vehicle "
                        .. tostring(vehicleId)
                        .. " -> "
                        .. tostring(destinationLabel)
                        .. ": "
                        .. tostring(setLineSuccess)
                        .. " (release: "
                        .. tostring(releaseSuccess)
                        .. ")"
                )

                assignVehiclesToLine(vehicleIds, cursor + 1, destinationLineId, destinationLabel, count - 1, callback)

            end)

        end)

    end)

end


local function processAllocationNext(context)

    context.index = context.index + 1

    local allocation = context.allocations[context.index]

    if allocation == nil then

        log.info("----------------------------------------")
        log.info("REDISTRIBUTE COMPLETE")
        log.info("----------------------------------------")

        if context.onComplete ~= nil then
            context.onComplete(context.index - 1)
        end

        return

    end

    log.info(
        "REDISTRIBUTE: giving "
            .. tostring(allocation.count)
            .. " vehicle(s) to "
            .. tostring(allocation.candidate.name)
            .. " (currently "
            .. tostring(allocation.candidate.waiting)
            .. " waiting)"
    )

    assignVehiclesToLine(
        context.spareVehicleIds,
        context.cursor,
        allocation.candidate.id,
        allocation.candidate.name,
        allocation.count,

        function(newCursor)
            context.cursor = newCursor
            processAllocationNext(context)
        end
    )

end


-- sourceLineId: the line to pull the spare pool from (e.g. the
-- original combined line, now retired down to just the hub after
-- Stage 2).
--
-- hubStationGroup: the focused hub, used to find each split line's
-- one real destination and to run demand.scan() against it.
function M.redistributeSpareVehiclesByDemand(sourceLineId, hubStationGroup, onComplete)

    log.info("----------------------------------------")
    log.info("REDISTRIBUTE SPARE VEHICLES BY DEMAND")
    log.info("----------------------------------------")

    if sourceLineId == nil then

        log.info("FAILED: source line not found.")

        return {
            success = false,
            reason = "source-line-not-found"
        }

    end

    local candidates = findManagedSplitLines(hubStationGroup)

    if #candidates == 0 then

        log.info("Nothing to do: no managed (\"● \") split lines found.")

        return {
            success = true,
            processedCount = 0
        }

    end

    local spareVehicleIds = vehicles.getVehiclesForLine(sourceLineId)

    if #spareVehicleIds == 0 then

        log.info("Nothing to do: source line has no spare vehicles.")

        return {
            success = true,
            processedCount = 0
        }

    end

    log.info(
        "Spare vehicles available: "
            .. tostring(#spareVehicleIds)
    )

    for _, candidate in ipairs(candidates) do

        log.info(
            "  candidate: "
                .. tostring(candidate.name)
                .. " | waiting="
                .. tostring(candidate.waiting)
                .. " | currentVehicles="
                .. tostring(candidate.vehicleCount)
        )

    end

    local allocations = apportionByDemand(candidates, #spareVehicleIds)

    if #allocations == 0 then

        log.info(
            "Nothing to do: no candidate currently shows any waiting "
                .. "demand, so the spare pool is left on the source "
                .. "line rather than assigned anywhere blind."
        )

        return {
            success = true,
            processedCount = 0
        }

    end

    for _, allocation in ipairs(allocations) do

        log.info(
            "PLAN: "
                .. tostring(allocation.candidate.name)
                .. " -> +"
                .. tostring(allocation.count)
                .. " vehicle(s)"
        )

    end

    processAllocationNext({
        spareVehicleIds = spareVehicleIds,
        cursor = 1,
        allocations = allocations,
        index = 0,
        onComplete = onComplete
    })

    return {
        success = true,
        pending = true
    }

end


return M
