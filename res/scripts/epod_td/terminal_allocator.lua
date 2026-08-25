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
-- REVERTED (Decision 50): Decision 42 replaced this with a
-- shared-pool design built on api.cmd.make.setLineStopAlternative-
-- Terminals -- flagged at the time as NOT YET LIVE-CONFIRMED to
-- exist. Live multi-hub testing confirmed it doesn't: every single
-- call failed with "attempt to call a nil value" (Lua's error for
-- calling a function that isn't real). Reverted to this version,
-- exactly as it stood before Decision 42, which IS proven working.
--
-- Builds on two things LIVE-CONFIRMED (see DECISIONS.md):
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
-- ONE-OFF, DISPOSABLE: ALTERNATIVE TERMINALS RESEARCH
--
-- Raised live: a single heavily-loaded line (e.g. 20 trucks all
-- funneling through one dedicated terminal) causes real road/queue
-- congestion at that one terminal even when the hub has plenty of
-- other terminals sitting idle -- the player found TF2's own native
-- UI for this (the line-stop editor's second, fork-icon terminal
-- picker, which lets a stop use several terminals interchangeably).
-- lines.lua's makeNativeStopCopy already round-trips a stop's
-- alternativeTerminals field through the exact same proven
-- updateLine command this mod uses everywhere else -- it's just
-- always been empty until now, since nothing has ever written into
-- it. Decision 42's mistake was calling a SEPARATE, nonexistent
-- command (setLineStopAlternativeTerminals) instead of just setting
-- this field on the stop object like .terminal already is.
--
-- Unknown going in: what shape each entry needs -- a bare terminal
-- index integer (matching how .terminal itself is written) or a
-- structured table. Tries the bare-integer shape first, since it's
-- the closest match to what's already proven working. Logs whether
-- each append succeeded, sends through updateLine, then re-reads the
-- line back to see what actually persisted. Remove once answered.
-- ============================================================
function M.testAlternativeTerminals(hubStationGroup, lineId, onComplete)

    log.info("----------------------------------------")
    log.info("ALT TERMINAL RESEARCH: starting for line " .. tostring(lineId))
    log.info("----------------------------------------")

    local targetLine = lines.get(lineId)

    if targetLine == nil then

        log.info("ALT TERMINAL RESEARCH FAILED: could not read line " .. tostring(lineId))

        onComplete()
        return

    end

    local stops = lines.safeField(targetLine, "stops")
    local stopCount = lines.safeLength(stops)

    local terminalCount = stations.getTerminalCount(hubStationGroup)

    if terminalCount == 0 then

        log.info("ALT TERMINAL RESEARCH FAILED: no terminal count for hub " .. tostring(hubStationGroup))

        onComplete()
        return

    end

    log.info("ALT TERMINAL RESEARCH: terminal count at hub = " .. tostring(terminalCount))


    local newLine = api.type.Line.new()
    local newStops = lines.safeField(newLine, "stops")

    local waitingTime = lines.safeField(targetLine, "waitingTime")

    if waitingTime ~= nil then
        pcall(function()
            newLine.waitingTime = waitingTime
        end)
    end

    vehicles.copyLineVehicleInfo(targetLine, newLine)

    local hubStopIndex = nil

    for index = 1, stopCount do

        local sourceStop = stops[index]

        if sourceStop ~= nil then

            local nativeStop = lines.makeNativeStopCopy(sourceStop)

            local stationGroup = lines.safeField(sourceStop, "stationGroup")

            if stationGroup == hubStationGroup and hubStopIndex == nil then

                hubStopIndex = index

                local primaryTerminal = lines.safeField(sourceStop, "terminal") or 0

                local alternatives = lines.safeField(nativeStop, "alternativeTerminals")

                if alternatives == nil then

                    log.info("ALT TERMINAL RESEARCH: alternativeTerminals field is nil on native stop.")

                else

                    -- Attempt 1 (bare integer, matching how .terminal
                    -- itself is written) and Attempt 2 (a plain
                    -- {station=, terminal=} Lua table) are both
                    -- LIVE-CONFIRMED to fail -- every append returned
                    -- false either way. The official API docs
                    -- (wiki.transportfever2.com/api/modules/api.type.
                    -- html#StationTerminal) confirm why: this field
                    -- takes a list of type.StationTerminal, a genuine
                    -- native type ("identifies a Terminal inside a
                    -- StationGroup"), not a bare integer or a plain
                    -- table. Attempt 3: construct it properly via
                    -- api.type.StationTerminal.new(), same pattern
                    -- already proven for api.type.Line.new() and
                    -- api.type.Line.Stop.new() elsewhere in this
                    -- codebase. Exact field names aren't documented,
                    -- so this tries the two most likely candidates
                    -- (stationGroup/terminal, matching this codebase's
                    -- own existing stop terminology) individually via
                    -- pcall to discover empirically which one sticks.
                    local okConstructorType, StationTerminalType =
                        pcall(function()
                            return api.type.StationTerminal
                        end)

                    if not okConstructorType or StationTerminalType == nil then

                        log.info(
                            "ALT TERMINAL RESEARCH: api.type.StationTerminal is not accessible."
                        )

                    else

                        for terminalIndex = 0, terminalCount - 1 do

                            if terminalIndex ~= primaryTerminal then

                                local okNew, stationTerminal =
                                    pcall(function()
                                        return StationTerminalType.new()
                                    end)

                                if not okNew then

                                    log.info(
                                        "ALT TERMINAL RESEARCH: StationTerminal.new() FAILED: "
                                            .. tostring(stationTerminal)
                                    )

                                else

                                    -- LIVE-CONFIRMED DANGEROUS: an
                                    -- earlier version of this test set
                                    -- .terminal only (stationGroup=
                                    -- write failed, silently) and
                                    -- still appended the incomplete
                                    -- object anyway -- updateLine
                                    -- accepted it with no validation,
                                    -- and the game later crashed with
                                    -- a native engine assertion
                                    -- (`stIdx0 >= 0` failed) trying to
                                    -- pathfind using it. NEVER append
                                    -- a StationTerminal unless BOTH
                                    -- the terminal index AND some
                                    -- station-identifying field were
                                    -- confirmed to actually write.
                                    local okSetTerminal =
                                        pcall(function()
                                            stationTerminal.terminal = terminalIndex
                                        end)

                                    local okSetGroup =
                                        pcall(function()
                                            stationTerminal.stationGroup = hubStationGroup
                                        end)

                                    local identityField = nil

                                    if okSetGroup then
                                        identityField = "stationGroup"
                                    else

                                        local okSetStation =
                                            pcall(function()
                                                stationTerminal.station = hubStationGroup
                                            end)

                                        if okSetStation then
                                            identityField = "station"
                                        end

                                    end

                                    if okSetTerminal and identityField ~= nil then

                                        local okAppend =
                                            pcall(function()
                                                alternatives[#alternatives + 1] = stationTerminal
                                            end)

                                        log.info(
                                            "ALT TERMINAL RESEARCH: terminal "
                                                .. tostring(terminalIndex)
                                                .. " -> identity field="
                                                .. tostring(identityField)
                                                .. ", append="
                                                .. tostring(okAppend)
                                        )

                                    else

                                        log.info(
                                            "ALT TERMINAL RESEARCH: terminal "
                                                .. tostring(terminalIndex)
                                                .. " -> SKIPPED (set terminal="
                                                .. tostring(okSetTerminal)
                                                .. ", no working identity field found) -- "
                                                .. "refusing to append an incomplete object."
                                        )

                                    end

                                end

                            end

                        end

                    end

                end

            end

            local okAppendStop, appendErr =
                lines.appendNativeStop(newStops, nativeStop)

            if not okAppendStop then

                log.info(
                    "ALT TERMINAL RESEARCH FAILED appending stop: "
                        .. tostring(appendErr)
                )

                onComplete()
                return

            end

        end

    end

    local okCommand, commandOrError =
        pcall(api.cmd.make.updateLine, lineId, newLine)

    if not okCommand then

        log.info("ALT TERMINAL RESEARCH COMMAND ERROR: " .. tostring(commandOrError))

        onComplete()
        return

    end

    local okSend, sendErr =
        pcall(function()

            api.cmd.sendCommand(commandOrError, function(cmd, success)

                log.info("ALT TERMINAL RESEARCH: updateLine command success = " .. tostring(success))

                local reread = lines.get(lineId)
                local rereadStops = reread ~= nil and lines.safeField(reread, "stops") or nil
                local rereadStop =
                    (rereadStops ~= nil and hubStopIndex ~= nil)
                        and rereadStops[hubStopIndex]
                        or nil
                local rereadAlts =
                    rereadStop ~= nil
                        and lines.safeField(rereadStop, "alternativeTerminals")
                        or nil
                local rereadCount = lines.safeLength(rereadAlts)

                log.info(
                    "ALT TERMINAL RESEARCH: re-read alternativeTerminals count = "
                        .. tostring(rereadCount)
                )

                if rereadCount > 0 then

                    for i = 1, rereadCount do

                        local entry = rereadAlts[i]

                        log.info(
                            "ALT TERMINAL RESEARCH: re-read entry ["
                                .. tostring(i)
                                .. "] = "
                                .. tostring(entry)
                                .. " (stationGroup="
                                .. tostring(lines.safeField(entry, "stationGroup"))
                                .. ", terminal="
                                .. tostring(lines.safeField(entry, "terminal"))
                                .. ")"
                        )

                    end

                end

                log.info("----------------------------------------")

                onComplete()

            end)

        end)

    if not okSend then

        log.info("ALT TERMINAL RESEARCH SEND ERROR: " .. tostring(sendErr))

        onComplete()

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
