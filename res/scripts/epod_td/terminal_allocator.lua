local log = require("epod_td.log")
local lines = require("epod_td.lines")
local stations = require("epod_td.stations")
local managed_registry = require("epod_td.managed_registry")

local M = {}


-- ============================================================
-- STAGE 4: SHARED TERMINAL POOL VIA alternativeTerminals
--
-- REPLACES the earlier demand-ranked single-terminal-lock design
-- (rebuilding the whole native Line via api.type.Line.new() +
-- api.cmd.make.updateLine just to write one Line.Stop.terminal value
-- per managed line -- see git history for that version's hard-won
-- fixes, e.g. the line-count-before-load tiebreak bug and the
-- stock-take exclusion bug, both no longer relevant to this design).
--
-- New approach, player-directed: instead of the mod calculating and
-- hard-assigning one dedicated terminal per line, give every managed
-- ("● ") line's hub stop the SAME pool of every real terminal at the
-- hub via Line.Stop.alternativeTerminals, and let TF2's own vehicle
-- terminal-selection logic balance load across them per trip. One
-- direct api.cmd.make.setLineStopAlternativeTerminals command per
-- line, no full-line reconstruction needed.
--
-- alternativeTerminals itself is not new -- lines.makeNativeStopCopy
-- already reads and copies it when duplicating a stop onto a freshly
-- split line -- but nothing in this codebase has ever WRITTEN it
-- directly, and api.cmd.make.setLineStopAlternativeTerminals has
-- never been called here before. NOT YET LIVE-CONFIRMED: whether it
-- exists at all, whether it takes a plain Lua array of terminal
-- indices (as tried below) or a native vector type, and whether
-- Line.Stop.terminal (left untouched here) still needs to be a valid
-- in-range value for the alternatives to actually be considered.
-- Every call is pcall-wrapped and logs its own result either way.
-- ============================================================

local function findManagedLinesTouchingHub(hubStationGroup)

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

            local name = lines.getName(lineId)
            local line = lines.get(lineId)
            local stops = line ~= nil and lines.safeField(line, "stops") or nil
            local stopCount = lines.safeLength(stops)

            local hubStopIndex = nil

            for index = 1, stopCount do

                local stop = stops[index]

                if stop ~= nil then

                    local stationGroup = lines.safeField(stop, "stationGroup")

                    if stationGroup == hubStationGroup then
                        hubStopIndex = index
                        break
                    end

                end

            end

            if hubStopIndex ~= nil then

                candidates[#candidates + 1] = {
                    id = lineId,
                    name = name,
                    hubStopIndex = hubStopIndex
                }

            end

        end

    end

    return candidates

end


local function processCandidateNext(candidates, allTerminalIds, index, appliedCount, onComplete)

    local candidate = candidates[index]

    if candidate == nil then

        log.info("----------------------------------------")

        log.info(
            "STAGE 4 COMPLETE: "
                .. tostring(appliedCount)
                .. " of "
                .. tostring(#candidates)
                .. " line(s) given the shared terminal pool."
        )

        log.info("----------------------------------------")

        if onComplete ~= nil then
            onComplete(appliedCount)
        end

        return

    end

    -- Native stopIndex is 0-based (same convention as vehicles.setLine's
    -- stopIndex / buildRouteMap's routeIndex); candidate.hubStopIndex is
    -- a 1-based Lua array position into `stops`, so it needs the -1
    -- here despite reading directly off that array being fine
    -- unconverted elsewhere in this codebase.
    local nativeStopIndex = candidate.hubStopIndex - 1

    local function advance(success)
        processCandidateNext(
            candidates,
            allTerminalIds,
            index + 1,
            success and (appliedCount + 1) or appliedCount,
            onComplete
        )
    end

    local okCommand, commandOrError =
        pcall(
            api.cmd.make.setLineStopAlternativeTerminals,
            candidate.id,
            nativeStopIndex,
            allTerminalIds
        )

    if not okCommand then

        log.info(
            "STAGE 4 COMMAND ERROR ("
                .. tostring(candidate.name)
                .. "): "
                .. tostring(commandOrError)
        )

        advance(false)
        return

    end

    local okSend, sendErr =
        pcall(function()

            api.cmd.sendCommand(commandOrError, function(cmd, success)

                log.info(
                    "STAGE 4 RESULT ("
                        .. tostring(candidate.name)
                        .. "): "
                        .. tostring(success)
                        .. " -> alternativeTerminals = { "
                        .. table.concat(allTerminalIds, ", ")
                        .. " } (stopIndex "
                        .. tostring(nativeStopIndex)
                        .. ")"
                )

                advance(success)

            end)

        end)

    if not okSend then

        log.info(
            "STAGE 4 SEND ERROR ("
                .. tostring(candidate.name)
                .. "): "
                .. tostring(sendErr)
        )

        advance(false)

    end

end


-- excludeLineIds: kept only for call-site signature compatibility
-- with epod_truck_distribution.lua's splitAllManagedLines (which
-- passes the just-split source line IDs) -- unused by this shared-pool
-- design, since there is no stock-take of other lines' terminal
-- occupancy to protect anymore. Every managed line just gets the
-- same full pool regardless of what else is on the hub.
function M.spreadLinesAcrossTerminals(hubStationGroup, excludeLineIds, onComplete)

    log.info("----------------------------------------")
    log.info("STAGE 4: SHARED TERMINAL POOL")
    log.info("----------------------------------------")

    local terminalCount = stations.getTerminalCount(hubStationGroup)

    if terminalCount == 0 then

        log.info(
            "FAILED: could not determine a real terminal count for this station."
        )

        return {
            success = false,
            reason = "terminal-count-unavailable"
        }

    end

    log.info("Terminal count at hub: " .. tostring(terminalCount))

    local allTerminalIds = {}

    for terminalIndex = 0, terminalCount - 1 do
        allTerminalIds[#allTerminalIds + 1] = terminalIndex
    end


    local candidates = findManagedLinesTouchingHub(hubStationGroup)

    if #candidates == 0 then

        log.info("Nothing to do: no managed (\"● \") lines found.")

        return {
            success = true,
            processedCount = 0
        }

    end

    log.info(
        "Applying shared pool { "
            .. table.concat(allTerminalIds, ", ")
            .. " } to "
            .. tostring(#candidates)
            .. " managed line(s)..."
    )

    processCandidateNext(candidates, allTerminalIds, 1, 0, onComplete)

    return {
        success = true,
        pending = true,
        totalCount = #candidates
    }

end


return M
