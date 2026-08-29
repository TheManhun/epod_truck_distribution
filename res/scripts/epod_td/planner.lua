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
-- CARGO-PROFILE FLOOR (Decision 29): a real, live-observed run found
-- two active lines (Queens Road, Alexander Road) planned down to the
-- bare 1-vehicle floor purely because they showed 0 waiting at that
-- exact instant, despite carrying real live fleets. Per IDEAS.md's
-- "Runtime Fleet Rebalancing" cargo-profile refinement: a
-- destination's recent/historical unloaded cargo (stations.lua,
-- Decision 28's confirmed per-window breakdown) now boosts its FLOOR
-- when current waiting is 0, so a momentarily-quiet real destination
-- isn't treated the same as one that has genuinely never carried
-- anything. This is deliberately a FLOOR protection only, not a
-- share of the demand-weighted pool below -- the pool share still
-- comes entirely from genuine current waiting cargo, the one signal
-- with an actual, trustworthy magnitude. Mixing raw historical
-- totals (which can run into the thousands) into that weighting
-- would risk swamping real live demand with a made-up scaling
-- factor this project has no evidence for yet (IDEAS.md's own
-- caution: exact thresholds need live tuning, not blind numbers).
--
-- NOT YET INCLUDED (deliberately): per-vehicle cargo-compatibility
-- sub-pooling (Decision 27) -- this version still assumes any
-- managed vehicle can serve any managed line. That's a separate,
-- later layer (per-cargo-type vehicle mix), not this one (how many
-- vehicles total a line should have).
-- ============================================================

local log = require("epod_td.log")
local lines = require("epod_td.lines")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local managed_registry = require("epod_td.managed_registry")
local stations = require("epod_td.stations")
local line_ownership = require("epod_td.line_ownership")

local M = {}


-- Every managed line reserves at least this many vehicles -- the
-- Planner reports a SHORTAGE or SURPLUS against a floor, it never
-- proposes emptying a line down to zero. Retiring a line entirely is
-- a deliberate, separate action ("Safe Close Managed Line",
-- IDEAS.md), not something the Planner should imply just because
-- it's quiet right now.
local MINIMUM_VEHICLES_PER_LINE = 1

-- Extra floor reserved for a destination that shows 0 waiting RIGHT
-- NOW but genuinely received real cargo last month -- protects it
-- from being read as "doesn't need anything" off a single snapshot.
local RECENT_ACTIVITY_FLOOR_BONUS = 2

-- Smaller extra floor for a destination with no recent (last-month)
-- activity but real all-time history -- a weaker signal than RECENT
-- (could be a seasonal/rare cargo type, or could be genuinely gone
-- quiet), so a smaller protection than RECENT gets.
local HISTORICAL_ACTIVITY_FLOOR_BONUS = 1

-- Floor-assignment priority when the fleet is too small to give
-- every candidate its full floor (see the edge-case guard below) --
-- genuine current demand gets first claim, then recent, then
-- historical, then candidates with no observed activity at all.
local ACTIVITY_TIER_PRIORITY = {
    ACTIVE = 3,
    RECENT = 2,
    HISTORICAL = 1,
    IRRELEVANT = 0
}


-- LIVE-CONFIRMED CRITICAL BUG (Decision 45, multi-hub testing): this
-- used to return the FIRST stop whose stationGroup wasn't
-- hubStationGroup, without ever checking that the line actually has a
-- stop AT hubStationGroup in the first place. Under a single hub this
-- was harmless -- every managed line touched that one hub by
-- construction, so "the first non-matching stop" always happened to
-- be the real destination. The instant a second hub existed, this
-- became a real bug: checking a pure-Hendon line like "Hendon East
-- <-> The Grove" against Yarm East's ID found "Hendon East" wasn't
-- Yarm East and returned it as if that line belonged to Yarm --
-- meaning Yarm's planner treated EVERY managed line in the entire
-- game as one of its own candidates, not just lines actually touching
-- Yarm. Live-confirmed via the log: Yarm's very first automatic
-- dispatch run moved a vehicle from a real Yarm line straight onto
-- "Hendon East <-> The Grove", a line with zero connection to Yarm.
-- Fixed by requiring an actual stop AT hubStationGroup to exist
-- before returning any destination at all.
local function findDestinationStationGroup(lineId, hubStationGroup)

    local line = lines.get(lineId)

    if line == nil then
        return nil
    end

    local stops = lines.safeField(line, "stops")
    local stopCount = lines.safeLength(stops)

    local touchesHub = false
    local destinationStationGroup = nil

    for index = 1, stopCount do

        local stop = stops[index]

        if stop ~= nil then

            local stationGroup = lines.safeField(stop, "stationGroup")

            if stationGroup == hubStationGroup then

                touchesHub = true

            elseif stationGroup ~= nil and destinationStationGroup == nil then

                destinationStationGroup = stationGroup

            end

        end

    end

    if not touchesHub then
        return nil
    end

    return destinationStationGroup

end


-- ACTIVE: real waiting cargo right now -- the trustworthy signal.
-- RECENT: 0 waiting now, but real cargo unloaded here last month --
--   protect it, don't treat a snapshot as "doesn't need anything."
-- HISTORICAL: no recent activity, but real all-time history --
--   weaker signal (seasonal cargo, or genuinely gone quiet), smaller
--   protection.
-- IRRELEVANT: no waiting, no recent, no historical activity at all
--   -- this destination has never actually needed cargo capacity.
local function classifyActivityTier(waiting, recentUnloaded, historicalUnloaded)

    if waiting > 0 then
        return "ACTIVE"
    elseif recentUnloaded > 0 then
        return "RECENT"
    elseif historicalUnloaded > 0 then
        return "HISTORICAL"
    end

    return "IRRELEVANT"

end


local function floorBonusForTier(tier)

    if tier == "RECENT" then
        return RECENT_ACTIVITY_FLOOR_BONUS
    elseif tier == "HISTORICAL" then
        return HISTORICAL_ACTIVITY_FLOOR_BONUS
    end

    return 0

end


-- Every managed line touching this hub, with its current waiting
-- demand, current vehicle count, and cargo-profile activity tier.
-- Deliberately hub-scoped the same way fleet_naming.lua's
-- lineTouchesHub is -- a managed line belonging to a DIFFERENT hub
-- must never leak into this hub's plan (Decision 45 fixed
-- findDestinationStationGroup itself for lines that don't touch this
-- hub AT ALL; this ownership check below handles the separate case of
-- a line that genuinely touches MULTIPLE hubs -- Decision 48).
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

            if destinationStationGroup ~= nil
                and not line_ownership.isOwnedByOther(lineId, hubStationGroup)
            then

                local scanResult =
                    demand.scan(lineId, hubStationGroup)

                local waiting =
                    (scanResult ~= nil and scanResult.totalWaiting) or 0

                local recentUnloaded =
                    stations.getRecentUnloadedTotal(destinationStationGroup)

                local historicalUnloaded =
                    stations.getItemTotals(destinationStationGroup).unloaded

                local tier =
                    classifyActivityTier(waiting, recentUnloaded, historicalUnloaded)

                -- Not consumed by calculateTargetAllocation's own
                -- redistribution math below (that math is unchanged) --
                -- carried on the candidate purely so other read-only
                -- consumers (fleet_needs.lua) can reuse this same
                -- collection pass instead of re-scanning every line's
                -- vehicles a second time.
                local loadFactor = vehicles.getLineLoadFactor(lineId)

                candidates[#candidates + 1] = {
                    id = lineId,
                    name = lines.getName(lineId),
                    destinationStationGroup = destinationStationGroup,
                    waiting = waiting,
                    recentUnloaded = recentUnloaded,
                    historicalUnloaded = historicalUnloaded,
                    activityTier = tier,
                    floor = MINIMUM_VEHICLES_PER_LINE + floorBonusForTier(tier),
                    currentVehicleCount = loadFactor.vehicleCount,
                    totalCargoLoad = loadFactor.totalLoad,
                    totalCargoCapacity = loadFactor.totalCapacity
                }

            end

        end

    end

    return candidates

end

-- Exported so other read-only modules can reuse this exact real
-- waiting/floor/activity-tier signal set instead of recomputing a
-- fourth copy of it (fleet_allocator.lua and gui_tab_lines.lua's
-- earlier private candidate-collection each already duplicate pieces
-- of this same logic -- see documents/DECISIONS.md's own deferred
-- cleanup note about consolidating it). fleet_needs.lua's
-- M.estimateFleetNeeds is the first consumer.
M.collectManagedLineCandidates = collectManagedLineCandidates


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

    -- Every candidate reserves its (activity-tier-boosted) floor
    -- first; only the remainder gets apportioned by demand. If there
    -- are more floor-vehicles owed than total vehicles exist (an
    -- edge case, not the normal shape of this problem), floors are
    -- handed out in activity-tier priority order -- genuine current
    -- demand claims its floor before recent, recent before
    -- historical -- rather than an arbitrary line order, and each
    -- candidate's floor is capped by whatever's actually left.
    local floors = {}

    local priorityOrder = {}

    for _, candidate in ipairs(candidates) do
        priorityOrder[#priorityOrder + 1] = candidate
    end

    table.sort(priorityOrder, function(a, b)
        return ACTIVITY_TIER_PRIORITY[a.activityTier] > ACTIVITY_TIER_PRIORITY[b.activityTier]
    end)

    local floorPoolRemaining = totalVehicles

    for _, candidate in ipairs(priorityOrder) do

        local grant = math.min(candidate.floor, floorPoolRemaining)

        floors[candidate.id] = grant
        floorPoolRemaining = floorPoolRemaining - grant

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
            destinationStationGroup = candidate.destinationStationGroup,
            waiting = candidate.waiting,
            recentUnloaded = candidate.recentUnloaded,
            historicalUnloaded = candidate.historicalUnloaded,
            activityTier = candidate.activityTier,
            floor = candidate.floor,
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
                .. "waiting demand -- every target below comes from "
                .. "per-line floors (cargo-profile-boosted where recent/"
                .. "historical activity was found), not genuine current "
                .. "demand. Treat as low-confidence until demand shows "
                .. "up again."
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
                .. " | tier=" .. tostring(line.activityTier)
                .. " | floor=" .. tostring(line.floor)
                .. " | current=" .. tostring(line.currentVehicleCount)
                .. " | target=" .. tostring(line.targetVehicleCount)
                .. " | delta=" .. sign .. tostring(line.delta)
        )

    end

    log.info("----------------------------------------")

    return plan

end


return M
