local log = require("epod_td.log")
local lines = require("epod_td.lines")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local managed_registry = require("epod_td.managed_registry")

local M = {}


-- ============================================================
-- STAGE 4: SPREAD MANAGED LINES ACROSS TERMINALS, BY DEMAND
--
-- Builds on two things now LIVE-CONFIRMED (see DECISIONS.md):
-- `Line.Stop.terminal` is writable and the change actually shows up
-- in the game's own TERMINALS tab, and the tab displays
-- (raw terminal value) + 1 -- this writes raw 0-based values
-- directly (0 lands on the tab's "Terminal 1").
--
-- Ranks every mod-created ("● ") managed line at the hub by current
-- demand.scan() waiting total, gives the highest-demand lines their
-- own dedicated terminal first (one each, up to the station's real
-- terminal count read via stations.getTerminalCount), then -- once
-- terminals run out -- assigns each remaining lower-demand line to
-- whichever terminal currently carries the least combined demand,
-- so sharing is concentrated where it costs the least. See
-- IDEAS.md's "Demand-Weighted Terminal Sharing" for the reasoning
-- behind this specific allocation rule.
--
-- Only ever touches mod-created ("● ") lines, never a pre-existing
-- line like "Grain" -- same scoping discipline as line_splitter.lua
-- and fleet_allocator.lua's stages.
-- ============================================================

local function findManagedLinesWithDemand(hubStationGroup)

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

                local scanResult =
                    demand.scan(lineId, hubStationGroup)

                local waiting =
                    (scanResult ~= nil and scanResult.totalWaiting) or 0

                candidates[#candidates + 1] = {
                    id = lineId,
                    name = name,
                    hubStopIndex = hubStopIndex,
                    waiting = waiting
                }

            end

        end

    end

    return candidates

end


local function setLineHubTerminal(lineId, hubStopIndex, newTerminal, label, callback)

    local targetLine = lines.get(lineId)

    if targetLine == nil then

        log.info(
            "STAGE 4 FAILED (could not re-read line): "
                .. tostring(label)
        )

        callback()
        return

    end

    local stops = lines.safeField(targetLine, "stops")
    local stopCount = lines.safeLength(stops)

    local newLine = api.type.Line.new()

    if newLine == nil then

        log.info(
            "STAGE 4 FAILED (api.type.Line.new() returned nil): "
                .. tostring(label)
        )

        callback()
        return

    end

    local newStops = lines.safeField(newLine, "stops")

    if newStops == nil then

        log.info(
            "STAGE 4 FAILED (new native Line has no stops container): "
                .. tostring(label)
        )

        callback()
        return

    end

    local waitingTime = lines.safeField(targetLine, "waitingTime")

    if waitingTime ~= nil then
        pcall(function()
            newLine.waitingTime = waitingTime
        end)
    end

    vehicles.copyLineVehicleInfo(targetLine, newLine)

    for index = 1, stopCount do

        local sourceStop = stops[index]

        if sourceStop ~= nil then

            local nativeStop = lines.makeNativeStopCopy(sourceStop)

            if index == hubStopIndex then

                local okSet, setErr =
                    pcall(function()
                        nativeStop.terminal = newTerminal
                    end)

                if not okSet then

                    log.info(
                        "STAGE 4 FAILED setting terminal ("
                            .. tostring(label)
                            .. "): "
                            .. tostring(setErr)
                    )

                    callback()
                    return

                end

            end

            local okAppend, appendErr =
                lines.appendNativeStop(newStops, nativeStop)

            if not okAppend then

                log.info(
                    "STAGE 4 FAILED appending stop ("
                        .. tostring(label)
                        .. "): "
                        .. tostring(appendErr)
                )

                callback()
                return

            end

        end

    end


    local okCommand, commandOrError =
        pcall(api.cmd.make.updateLine, lineId, newLine)

    if not okCommand then

        log.info(
            "STAGE 4 COMMAND ERROR ("
                .. tostring(label)
                .. "): "
                .. tostring(commandOrError)
        )

        callback()
        return

    end


    local okSend, sendErr =
        pcall(function()

            api.cmd.sendCommand(commandOrError, function(cmd, success)

                log.info(
                    "STAGE 4 RESULT ("
                        .. tostring(label)
                        .. "): "
                        .. tostring(success)
                        .. " -> terminal "
                        .. tostring(newTerminal)
                        .. " (UI \"Terminal "
                        .. tostring(newTerminal + 1)
                        .. "\")"
                )

                callback()

            end)

        end)

    if not okSend then

        log.info(
            "STAGE 4 SEND ERROR ("
                .. tostring(label)
                .. "): "
                .. tostring(sendErr)
        )

        callback()

    end

end


-- ============================================================
-- STOCK TAKE: EXISTING TERMINAL OCCUPANCY
--
-- Confirmed live this was a real gap in the first version of this
-- allocator: it assigned terminal indices 0..N-1 to managed lines
-- purely by demand rank, with no awareness of what was already
-- sitting on those terminals. The very first run put the
-- highest-demand managed line on the same terminal "Grain" (a real,
-- unmanaged, 20-vehicle line) was already using, exactly the
-- congestion the whole feature exists to avoid.
--
-- Reads every line at the hub EXCEPT mod-managed ("● ") ones (those
-- are about to get a fresh terminal assignment below, so their
-- current position is about to be overwritten and would only
-- double-count if included here) and sums each one's current
-- demand.scan() waiting total into whichever terminal its Hendon
-- stop already uses. The managed-line assignment loop then starts
-- from this real baseline instead of an all-zero one.
-- ============================================================

-- LIVE-CONFIRMED BUG: the assignment loop below used to compare
-- terminals by terminalLoad alone. When every candidate is a
-- freshly-split line with 0 waiting demand (the normal state right
-- after Stage 1, before Stage 2/3 or real gameplay have generated
-- any activity), assigning a candidate to a terminal never changes
-- that terminal's tracked load (+= 0) -- so the "lowest load"
-- terminal never changes either, and every single candidate piles
-- onto the SAME terminal instead of spreading. Player hit this live:
-- all 5 freshly-split lines landed on terminal 0, twice in a row
-- (retrying didn't help, since nothing about the bug depended on
-- how many times it ran). Fixed by tracking a per-terminal LINE
-- COUNT alongside load, seeded here from real pre-existing
-- occupancy, and using it as a tiebreaker -- see the assignment loop
-- in M.spreadLinesAcrossTerminals for the actual comparison logic.
local function stockTakeExistingLoad(hubStationGroup, terminalCount, excludeLineIdSet)

    excludeLineIdSet =
        excludeLineIdSet or {}

    local terminalLoad = {}
    local terminalLineCount = {}

    for terminalIndex = 0, terminalCount - 1 do
        terminalLoad[terminalIndex] = 0
        terminalLineCount[terminalIndex] = 0
    end

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then
        return terminalLoad, terminalLineCount
    end

    for _, lineId in ipairs(allLineIds) do

        local name = lines.getName(lineId)

        if not managed_registry.isManaged(lineId)
            and not excludeLineIdSet[lineId]
        then

            local line = lines.get(lineId)
            local stops = line ~= nil and lines.safeField(line, "stops") or nil
            local stopCount = lines.safeLength(stops)

            for index = 1, stopCount do

                local stop = stops[index]

                if stop ~= nil then

                    local stationGroup = lines.safeField(stop, "stationGroup")

                    if stationGroup == hubStationGroup then

                        local terminal = lines.safeField(stop, "terminal")

                        if type(terminal) == "number"
                            and terminal >= 0
                            and terminal < terminalCount
                        then

                            local scanResult =
                                demand.scan(lineId, hubStationGroup)

                            local waiting =
                                (scanResult ~= nil and scanResult.totalWaiting) or 0

                            terminalLoad[terminal] =
                                terminalLoad[terminal] + waiting

                            terminalLineCount[terminal] =
                                terminalLineCount[terminal] + 1

                            log.info(
                                "STOCK TAKE: "
                                    .. tostring(name)
                                    .. " already on terminal "
                                    .. tostring(terminal)
                                    .. " (UI \"Terminal "
                                    .. tostring(terminal + 1)
                                    .. "\"), contributing "
                                    .. tostring(waiting)
                                    .. " waiting"
                            )

                        end

                    end

                end

            end

        end

    end

    return terminalLoad, terminalLineCount

end


local function processAssignmentsNext(assignments, index, onComplete)

    local assignment = assignments[index]

    if assignment == nil then

        log.info("----------------------------------------")

        log.info(
            "STAGE 4 COMPLETE: "
                .. tostring(#assignments)
                .. " line(s) processed."
        )

        log.info("----------------------------------------")

        if onComplete ~= nil then
            onComplete(#assignments)
        end

        return

    end

    setLineHubTerminal(
        assignment.lineId,
        assignment.hubStopIndex,
        assignment.terminal,
        assignment.lineName,

        function()
            processAssignmentsNext(assignments, index + 1, onComplete)
        end
    )

end


-- excludeLineIds: line entity IDs to treat as non-permanent
-- occupancy in the stock-take, alongside already-managed lines --
-- specifically, the ORIGINAL combined line(s) this same button-click
-- chain just split apart, still alive right now but about to be
-- deleted by a later "Assign & Balance Fleet" click. See the big
-- comment on the caller side (epod_truck_distribution.lua's
-- splitAllManagedLines) for the live bug this fixes. Optional --
-- pass nil/{} when calling this outside that chain (e.g. re-running
-- terminal spread on an already-settled hub with no source line in
-- flight).
function M.spreadLinesAcrossTerminals(hubStationGroup, excludeLineIds, onComplete)

    excludeLineIds =
        excludeLineIds or {}

    local excludeLineIdSet = {}

    for _, lineId in ipairs(excludeLineIds) do
        excludeLineIdSet[lineId] = true
    end

    log.info("----------------------------------------")
    log.info("STAGE 4: SPREAD LINES ACROSS TERMINALS")
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


    local candidates = findManagedLinesWithDemand(hubStationGroup)

    if #candidates == 0 then

        log.info("Nothing to do: no managed (\"● \") lines found.")

        return {
            success = true,
            processedCount = 0
        }

    end


    table.sort(candidates, function(a, b)
        return a.waiting > b.waiting
    end)


    -- Seeded with real pre-existing occupancy (see stockTakeExistingLoad
    -- above), not an all-zero start. Candidates are already sorted
    -- highest-demand first, so always picking the currently
    -- lowest-load terminal naturally gives the busiest managed line
    -- first claim on the genuinely emptiest terminal (accounting for
    -- lines like "Grain" this feature doesn't manage), and each
    -- subsequent line picks the next-best option given everything
    -- already placed -- no separate "dedicated vs. shared" branch
    -- needed, sharing just emerges once every terminal has real load
    -- on it.
    local terminalLoad, terminalLineCount =
        stockTakeExistingLoad(hubStationGroup, terminalCount, excludeLineIdSet)

    local assignments = {}

    for _, candidate in ipairs(candidates) do

        -- Compare (lineCount, load) as a pair, LINE COUNT FIRST.
        -- LIVE-CONFIRMED this ordering matters, not just the
        -- presence of a tiebreaker: comparing load first (tried
        -- first, then reverted) still failed on the real case that
        -- surfaced this bug, because the source line's leftover
        -- stops made terminals 1-5 PERMANENTLY more "loaded" than
        -- terminal 0 (535 vs 230, never tied) -- a zero-demand
        -- candidate never closes that gap no matter how many land on
        -- terminal 0, so a load-first comparison never rolls over to
        -- another terminal at all, tie or no tie. Comparing line
        -- count first fixes this directly and actually matches the
        -- feature's own stated design better: give every candidate
        -- its own terminal while capacity allows (lineCount
        -- naturally differentiates every terminal immediately,
        -- regardless of demand), and only fall back to load -- i.e.
        -- share where it costs least -- once every terminal already
        -- has at least one line and lineCount ties.
        local bestTerminal = 0
        local bestLineCount = terminalLineCount[0]
        local bestLoad = terminalLoad[0]

        for terminalIndex = 0, terminalCount - 1 do

            local lineCount = terminalLineCount[terminalIndex]
            local load = terminalLoad[terminalIndex]

            if lineCount < bestLineCount
                or (lineCount == bestLineCount and load < bestLoad)
            then
                bestLineCount = lineCount
                bestLoad = load
                bestTerminal = terminalIndex
            end

        end

        terminalLoad[bestTerminal] =
            terminalLoad[bestTerminal] + candidate.waiting

        terminalLineCount[bestTerminal] =
            terminalLineCount[bestTerminal] + 1

        assignments[#assignments + 1] = {
            lineId = candidate.id,
            lineName = candidate.name,
            hubStopIndex = candidate.hubStopIndex,
            waiting = candidate.waiting,
            terminal = bestTerminal
        }

    end


    for _, assignment in ipairs(assignments) do

        log.info(
            "PLAN: "
                .. tostring(assignment.lineName)
                .. " (waiting=" .. tostring(assignment.waiting) .. ")"
                .. " -> terminal " .. tostring(assignment.terminal)
                .. " (UI \"Terminal " .. tostring(assignment.terminal + 1) .. "\")"
        )

    end


    processAssignmentsNext(assignments, 1, onComplete)

    return {
        success = true,
        pending = true,
        totalCount = #assignments
    }

end


return M
