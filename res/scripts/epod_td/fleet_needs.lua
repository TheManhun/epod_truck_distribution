local planner = require("epod_td.planner")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local vehicle_pool = require("epod_td.vehicle_pool")

local M = {}


-- ============================================================
-- FLEET NEEDS ESTIMATE (READ-ONLY)
--
-- Player's request: a report answering "this hub needs X more trucks
-- to fully service this area" -- prompted by reviewing the AI Builder
-- mod (Workshop 2820656841)'s pattern of scoring/evaluating candidates
-- against each other rather than fixed thresholds; adapted here to
-- this mod's own real signals, not borrowed code.
--
-- Deliberately a DIFFERENT question from planner.lua's
-- calculateTargetAllocation: that one REDISTRIBUTES the hub's existing
-- fleet (every delta sums to zero by construction -- its own
-- `pool = totalVehicles - floorSum`). This asks whether the hub's
-- TOTAL fleet is big enough in the first place. Reuses planner.lua's
-- own collectManagedLineCandidates (same real waiting/floor/activity-
-- tier signals, already live-tuned through Decisions 29/45/48) rather
-- than recomputing a fourth copy of the same apportionment logic.
--
-- Three real signals now feed the estimate:
--   1. Any candidate below its own floor (planner.lua's
--      MINIMUM_VEHICLES_PER_LINE + activity-tier bonus) with genuine
--      current waiting cargo is unambiguously short -- it needs at
--      least enough vehicles to reach that floor.
--   2. Beyond the floor, a line whose waiting-per-vehicle ratio is
--      markedly worse than this HUB'S OWN average (not a universal
--      constant) is under-trucked relative to its peers at the same
--      hub -- suggested additional trucks bring it back to the hub's
--      own average ratio, nothing more.
--   3. Player noticed the vanilla Line Statistics panel's "Cargo"
--      column (load/capacity, e.g. "64/64") and asked whether it could
--      sharpen this report. It catches a real blind spot signals 1/2
--      both share: a line running consistently FULL can show near-zero
--      WAITING at the origin (every unit gets carried off as fast as
--      it appears), which signals 1/2 alone would read as "no
--      shortage" despite the fleet being maxed out. `vehicles.lua`'s
--      new getLineLoadFactor sums real cargoLoad against real
--      allCapacities across a line's own vehicles -- when a line is
--      running at/above NEAR_CAPACITY_LOAD_FACTOR and signals 1/2 found
--      no shortage, this alone adds a +1 suggestion with its own
--      distinct reason text, rather than being silently folded into
--      the waiting-based number.
--
-- Same terminal-storage-cap caveat fleet_allocator.lua's own header
-- already documents: "waiting" is a floor on true demand, not exact --
-- so this is a suggestion, not a guarantee. NEAR_CAPACITY_LOAD_FACTOR
-- is a threshold, same category as demand.lua's own underServed cutoff
-- (waiting <= maxWaiting * 0.25) -- a starting point, not a proven
-- constant, subject to live tuning like that one was.
-- ============================================================

local NEAR_CAPACITY_LOAD_FACTOR = 0.9

function M.estimateFleetNeeds(hubStationGroupId)

    local hubName = stations.getEntityName(hubStationGroupId)

    local candidates = planner.collectManagedLineCandidates(hubStationGroupId)

    if #candidates == 0 then

        return {
            hubName = hubName,
            hasData = false,
            lines = {},
            totalSuggestedAdditional = 0,
            baselineRatio = nil
        }

    end

    -- Baseline ratio is drawn only from lines already AT or ABOVE
    -- their own floor -- an under-floor line's ratio is abnormally bad
    -- by definition and would drag the baseline down if included.
    local totalWaiting = 0
    local totalVehiclesAtFloorOrAbove = 0

    for _, candidate in ipairs(candidates) do

        if candidate.currentVehicleCount >= candidate.floor then
            totalWaiting = totalWaiting + candidate.waiting
            totalVehiclesAtFloorOrAbove = totalVehiclesAtFloorOrAbove + candidate.currentVehicleCount
        end

    end

    local baselineRatio = nil

    if totalVehiclesAtFloorOrAbove > 0 then
        baselineRatio = totalWaiting / totalVehiclesAtFloorOrAbove
    end

    local resultLines = {}
    local totalSuggestedAdditional = 0

    for _, candidate in ipairs(candidates) do

        local suggested = 0
        local reason = nil

        if candidate.currentVehicleCount < candidate.floor and candidate.waiting > 0 then

            suggested = candidate.floor - candidate.currentVehicleCount

        elseif baselineRatio ~= nil and baselineRatio > 0 and candidate.waiting > 0 then

            local idealVehicles = candidate.waiting / baselineRatio
            suggested = math.max(0, math.ceil(idealVehicles) - candidate.currentVehicleCount)

        end

        local loadFactor = nil

        if candidate.totalCargoCapacity ~= nil and candidate.totalCargoCapacity > 0 then
            loadFactor = candidate.totalCargoLoad / candidate.totalCargoCapacity
        end

        local nearCapacity = loadFactor ~= nil and loadFactor >= NEAR_CAPACITY_LOAD_FACTOR

        if suggested == 0 and nearCapacity then

            -- Signal 3 only steps in when waiting-based signals 1/2
            -- found nothing -- this is the blind-spot case, not an
            -- addition on top of an already-flagged line.
            suggested = 1
            reason = "trucks running near-full capacity"

        end

        totalSuggestedAdditional = totalSuggestedAdditional + suggested

        -- Decision 187: player's own idea -- before this line's
        -- shortfall implies buying anything, check the truck pool
        -- (vehicle_pool.lua) for a compatible idle vehicle from
        -- another hub's surplus. Cargo type is read from any real
        -- vehicle already on this line (`vehicles.getCompatibleCargoTypes`,
        -- already proven for cross-line reassignment safety elsewhere)
        -- -- a line with 0 current vehicles has nothing to sample from
        -- and simply gets no pool match, same as "no data" elsewhere in
        -- this module.
        local poolMatch = nil

        if suggested > 0 then

            local okSampleVehicles, sampleVehicleIds = pcall(vehicles.getVehiclesForLine, candidate.id)

            if okSampleVehicles and sampleVehicleIds ~= nil and #sampleVehicleIds > 0 then

                local okCargoTypes, cargoTypes = pcall(vehicles.getCompatibleCargoTypes, sampleVehicleIds[1])

                if okCargoTypes and cargoTypes ~= nil then

                    for _, cargoType in ipairs(cargoTypes) do

                        local okMatch, matchEntry = pcall(vehicle_pool.findPoolVehicleForCargoType, cargoType)

                        if okMatch and matchEntry ~= nil then
                            poolMatch = matchEntry
                            break
                        end

                    end

                end

            end

        end

        resultLines[#resultLines + 1] = {
            lineId = candidate.id,
            name = candidate.name,
            waiting = candidate.waiting,
            currentVehicleCount = candidate.currentVehicleCount,
            activityTier = candidate.activityTier,
            loadFactor = loadFactor,
            suggestedAdditional = suggested,
            reason = reason,
            poolMatchVehicleId = poolMatch ~= nil and poolMatch.vehicleId or nil
        }

    end

    table.sort(resultLines, function(a, b)

        if a.suggestedAdditional ~= b.suggestedAdditional then
            return a.suggestedAdditional > b.suggestedAdditional
        end

        return a.waiting > b.waiting

    end)

    return {
        hubName = hubName,
        hasData = true,
        lines = resultLines,
        totalSuggestedAdditional = totalSuggestedAdditional,
        baselineRatio = baselineRatio
    }

end


-- Decision 182: the report's headline shows red once the total passes
-- this many trucks -- player's own number ("over 10"), not derived
-- from anything.
M.HIGH_NEED_THRESHOLD = 10


-- Decision 185: shared by every consumer of estimateFleetNeeds's result
-- that wants the same one-line headline (the LINES tab's Fleet Needs
-- Report popup, and now OVERVIEW's own summary row) -- kept in one
-- place so the phrasing/threshold can't drift between the two.
-- `isWarning` is true once the total passes HIGH_NEED_THRESHOLD; the
-- caller decides what to actually do with that (a popup row style, a
-- summary row style, anything else).
function M.buildHeadline(report)

    if report == nil or not report.hasData then
        return { text = "No managed lines at this hub yet -- nothing to estimate.", isWarning = false }
    end

    if report.totalSuggestedAdditional > 0 then

        return {
            text = "Needs " .. tostring(report.totalSuggestedAdditional) .. " more truck(s) for this hub.",
            isWarning = report.totalSuggestedAdditional > M.HIGH_NEED_THRESHOLD
        }

    end

    return { text = "No truck shortage detected -- fleet currently keeps up with demand.", isWarning = false }

end


-- Decision 187: the single best pool claim to offer via the report's
-- one Confirm button -- `resultLines` is already sorted worst-need-
-- first (M.estimateFleetNeeds' own table.sort), so the first entry
-- carrying a poolMatchVehicleId is the most useful one to offer. Only
-- ever surfaces ONE match per report -- claiming it and reopening the
-- report picks the next one, rather than trying to claim several at
-- once through a single-button popup.
function M.findBestPoolClaim(report)

    if report == nil or not report.hasData then
        return nil
    end

    for _, lineInfo in ipairs(report.lines) do

        if lineInfo.poolMatchVehicleId ~= nil then

            return {
                lineId = lineInfo.lineId,
                lineName = lineInfo.name,
                vehicleId = lineInfo.poolMatchVehicleId
            }

        end

    end

    return nil

end


return M
