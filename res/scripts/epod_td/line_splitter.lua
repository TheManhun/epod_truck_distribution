local log = require("epod_td.log")
local lines = require("epod_td.lines")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local managed_registry = require("epod_td.managed_registry")
local line_ownership = require("epod_td.line_ownership")
local source_line_registry = require("epod_td.source_line_registry")

local M = {}


-- ============================================================
-- SPLIT ONE EXISTING MULTI-DESTINATION LINE INTO ONE DEDICATED
-- LINE PER REAL DESTINATION
--
-- Stage 1 only: purely additive. Builds api.cmd.make.createLine,
-- proven live (see TECHNICAL_RESEARCH.md and
-- route_injector.runCreateLineTest). Does NOT touch the source
-- line, does NOT move any vehicle, does NOT delete anything.
--
-- Deliberately scoped this way: whether a vehicle can be safely
-- reassigned across lines while still carrying loaded cargo is
-- still an unverified Outstanding Unknown (DECISIONS.md). Moving
-- the source line's real, currently-working fleet is Stage 2, a
-- separate and more consequential action, once that is proven.
-- Until then the source line and its vehicles keep operating
-- exactly as before; the new lines simply start out empty.
--
-- Entity-ID driven throughout: destinations are matched against
-- the source line's real stops by stationGroup equality, not by
-- name. Names are only ever used for constructing the new line's
-- display name and for the pre-creation duplicate-name check
-- (TF2 line identity is by entity, but createLine takes a name
-- argument and a repeat run should not silently create doubles).
-- ============================================================


local function findStopByStationGroup(sourceLine, stationGroup)
    local stops = lines.safeField(sourceLine, "stops")
    local count = lines.safeLength(stops)

    for index = 1, count do
        local stop = stops[index]

        if stop ~= nil then
            local sg = lines.safeField(stop, "stationGroup")

            if sg == stationGroup then
                return stop
            end
        end
    end

    return nil
end


local function buildSingleDestinationLine(hubStop, destinationStop)
    local newLine = api.type.Line.new()

    if newLine == nil then
        return nil, "api.type.Line.new() returned nil."
    end

    local newStops = lines.safeField(newLine, "stops")

    if newStops == nil then
        return nil, "New native Line has no stops container."
    end

    for _, sourceStop in ipairs({ hubStop, destinationStop }) do
        local nativeStop = lines.makeNativeStopCopy(sourceStop)
        local ok, err = lines.appendNativeStop(newStops, nativeStop)

        if not ok then
            return nil, "Failed appending stop: " .. tostring(err)
        end
    end

    return newLine, nil
end


-- Processes one destination at a time, waiting for each
-- createLine callback before starting the next, rather than
-- firing several simultaneous commands into an unproven situation.
local function processNext(context)

    context.index = context.index + 1

    local destination = context.destinations[context.index]

    if destination == nil then

        log.info(
            "----------------------------------------"
        )

        log.info(
            "SPLIT COMPLETE: "
                .. tostring(context.createdCount)
                .. " of "
                .. tostring(#context.destinations)
                .. " new lines created."
        )

        log.info(
            "Source line untouched. No vehicles were moved."
        )

        log.info(
            "----------------------------------------"
        )

        if context.onComplete ~= nil then
            context.onComplete(context.createdCount, #context.destinations)
        end

        return

    end


    local destStop =
        findStopByStationGroup(
            context.sourceLine,
            destination.stationGroup
        )

    if destStop == nil then

        log.info(
            "SPLIT SKIPPED (stop not found on source line): "
                .. tostring(destination.name)
        )

        processNext(context)
        return

    end


    -- ● marks a line this mod created/manages; ↔ signals the
    -- direction-agnostic, connected-network model (Decision 18/19,
    -- IDEAS.md) rather than an inbound/outbound label. Both
    -- confirmed live to actually render in TF2's font (see the
    -- glyph test in route_injector.lua) -- ◆, ■, and ► were tried
    -- and came back as unrendered boxes, so they're deliberately
    -- not used here. Literal characters in the source, not \xHH
    -- escapes (\xHH is not supported in vanilla Lua 5.1).
    local newLineName =
        "● "
            .. context.hubName
            .. " ↔ "
            .. destination.name

    local existingLineId = lines.findByName(newLineName)

    if existingLineId ~= nil then

        -- LIVE-CONFIRMED real case (Decision 51): a name match here
        -- does NOT necessarily mean this exact destination was
        -- already split -- two different physical stations can share
        -- a display name (a real map had two separate "Park Lane"
        -- stationGroups). Blindly skipping on a name match silently
        -- dropped the second one forever, since it never got its own
        -- line and so could never be served. Check whether the
        -- EXISTING same-named line actually goes to THIS destination
        -- before treating it as a real duplicate.
        local existingLine = lines.get(existingLineId)

        local existingStops =
            existingLine ~= nil
                and lines.safeField(existingLine, "stops")
                or nil

        local existingStopCount =
            lines.safeLength(existingStops)

        local sameDestination = false

        for index = 1, existingStopCount do

            local stop = existingStops[index]

            if stop ~= nil then

                local stationGroup =
                    lines.safeField(stop, "stationGroup")

                if stationGroup == destination.stationGroup then
                    sameDestination = true
                    break
                end

            end

        end

        if sameDestination then

            log.info(
                "SPLIT SKIPPED (line already exists): "
                    .. tostring(newLineName)
            )

            processNext(context)
            return

        end

        -- Different physical station, same display name --
        -- disambiguate with the destination's own entity ID rather
        -- than silently losing a real destination.
        newLineName =
            newLineName .. " (" .. tostring(destination.stationGroup) .. ")"

        log.info(
            "SPLIT: name collision with a DIFFERENT station -- "
                .. "disambiguating as \"" .. newLineName .. "\""
        )

    end


    local newLine, buildErr =
        buildSingleDestinationLine(
            context.hubStop,
            destStop
        )

    if newLine == nil then

        log.info(
            "SPLIT FAILED building route ("
                .. tostring(destination.name)
                .. "): "
                .. tostring(buildErr)
        )

        processNext(context)
        return

    end


    local okColor, color =
        pcall(
            api.type.Vec3f.new,
            0.2,
            0.6,
            0.9
        )

    if not okColor or color == nil then

        log.info(
            "SPLIT FAILED building color ("
                .. tostring(destination.name)
                .. "): "
                .. tostring(color)
        )

        processNext(context)
        return

    end


    local okCommand, commandOrError =
        pcall(
            api.cmd.make.createLine,
            newLineName,
            color,
            context.playerEntity,
            newLine
        )

    if not okCommand then

        log.info(
            "SPLIT FAILED creating command ("
                .. tostring(destination.name)
                .. "): "
                .. tostring(commandOrError)
        )

        processNext(context)
        return

    end


    log.info(
        "Creating: "
            .. newLineName
    )


    local okSend, sendErr =
        pcall(
            function()

                api.cmd.sendCommand(
                    commandOrError,

                    function(cmd, success)

                        log.info(
                            "  result: "
                                .. tostring(success)
                        )

                        if success then

                            context.createdCount =
                                context.createdCount + 1

                            -- The command callback only confirms
                            -- success, not the new line's entity ID
                            -- -- resolve it by the name we just gave
                            -- it (guaranteed unique per the
                            -- pre-creation duplicate-name check
                            -- above) and register it as managed. See
                            -- managed_registry.lua / IDEAS.md
                            -- PRIORITY -- this, not the "● " prefix,
                            -- is what actually makes the line
                            -- managed from now on.
                            local newLineId =
                                lines.findByName(newLineName)

                            if newLineId ~= nil then
                                managed_registry.register(newLineId)
                                line_ownership.claim(newLineId, context.hubStationGroup)
                            end

                        end

                        processNext(context)

                    end
                )

            end
        )

    if not okSend then

        log.info(
            "SPLIT FAILED sending command ("
                .. tostring(destination.name)
                .. "): "
                .. tostring(sendErr)
        )

        processNext(context)

    end

end


-- lineInfo: one entry from vehicles.getManagedLinesForStation()'s
-- result -- must have .id, .name, .destinations (each with
-- .stationGroup and .name).
--
-- hubStationGroup: the currently-focused station's stationGroup,
-- used only to skip the "(return)" destination entry (a real
-- destination has a different stationGroup than the hub itself).
function M.splitLineIntoDestinations(
    hubStationGroup,
    lineInfo,
    onComplete
)

    log.info(
        "----------------------------------------"
    )

    log.info(
        "SPLIT LINE INTO DESTINATIONS"
    )

    log.info(
        "Source line: "
            .. tostring(lineInfo.name)
            .. " (id="
            .. tostring(lineInfo.id)
            .. ")"
    )

    log.info(
        "----------------------------------------"
    )


    local sourceLine =
        lines.get(lineInfo.id)

    if sourceLine == nil then

        log.info(
            "FAILED: could not re-read source line."
        )

        return {
            success = false,
            reason = "source-line-unreadable"
        }

    end


    -- Decision 59: a line that genuinely touches two enabled hubs at
    -- once (e.g. hub B is itself one of hub A's stops) would
    -- otherwise get split independently from BOTH hubs' perspectives
    -- -- each treating the other as "just a destination" -- producing
    -- duplicate lines for the same station pair and leaving the
    -- source line claimed by nobody in particular, never fully
    -- retired by either side. line_ownership already tracks exactly
    -- this ("which hub owns this line") for split children and
    -- adopted lines (Decision 45/48); this is the same check applied
    -- to the SOURCE line itself, at the one point that's about to
    -- treat it as "mine to split." isOwnedByOther lazily claims an
    -- unowned line for hubStationGroup as a side effect, matching
    -- planner.lua's existing usage.
    if line_ownership.isOwnedByOther(lineInfo.id, hubStationGroup) then

        log.info(
            "SKIPPED: line already claimed by a different hub as its "
                .. "own combined source (owner="
                .. tostring(line_ownership.getOwner(lineInfo.id))
                .. "): "
                .. tostring(lineInfo.name)
        )

        -- Must still call onComplete: splitAllManagedLines's caller
        -- chains through this callback to move on to the NEXT
        -- candidate line -- skipping it here would silently stall
        -- the whole Split All sequence right at this line, since
        -- this path (unlike "nothing to split", which the caller
        -- already pre-filters via its own realCount < 2 check) is
        -- genuinely reachable in normal use.
        if onComplete ~= nil then
            onComplete(0, 0)
        end

        return {
            success = true,
            createdCount = 0,
            totalCount = 0,
            reason = "already-owned-by-other-hub"
        }

    end


    local hubStop =
        findStopByStationGroup(
            sourceLine,
            hubStationGroup
        )

    if hubStop == nil then

        log.info(
            "FAILED: hub stop not found on source line."
        )

        return {
            success = false,
            reason = "hub-stop-not-found"
        }

    end


    local realDestinations = {}

    for _, destination in ipairs(lineInfo.destinations or {}) do

        -- Skip the hub's own "(return)" entry -- that is demand
        -- data about the source line itself, not a separate stop
        -- to give its own dedicated line.
        if destination.stationGroup ~= hubStationGroup then

            realDestinations[#realDestinations + 1] =
                destination

        end

    end


    if #realDestinations == 0 then

        log.info(
            "Nothing to split: no real destinations found "
                .. "(besides the hub itself)."
        )

        return {
            success = true,
            createdCount = 0,
            totalCount = 0
        }

    end


    local okPlayer, playerEntity =
        pcall(
            api.engine.util.getPlayer
        )

    if not okPlayer or playerEntity == nil then

        log.info(
            "FAILED: api.engine.util.getPlayer() unavailable: "
                .. tostring(playerEntity)
        )

        return {
            success = false,
            reason = "player-entity-unavailable"
        }

    end


    log.info(
        "Real destinations to split off: "
            .. tostring(#realDestinations)
    )


    -- Decision 46 fix: record which line this actually is FOR this
    -- hub, the one moment it's genuinely known -- "Assign & Balance
    -- Fleet" reads this back instead of guessing by a hardcoded name.
    -- Only when there's genuinely more than one real destination left
    -- on it: splitAllManagedLines (the button's caller) runs this
    -- function once per line already touching the hub, including
    -- lines that are already clean, single-destination children from
    -- an earlier split -- those would reach this point too (their one
    -- real destination just gets skipped a few lines down as
    -- "already exists"), and must never overwrite the real combined
    -- source's record with themselves.
    if #realDestinations > 1 then
        source_line_registry.addSourceLine(hubStationGroup, lineInfo.id)
    end

    processNext({
        sourceLine = sourceLine,
        sourceLineName = lineInfo.name,
        hubStationGroup = hubStationGroup,
        hubName = stations.getEntityName(hubStationGroup),
        hubStop = hubStop,
        destinations = realDestinations,
        index = 0,
        createdCount = 0,
        playerEntity = playerEntity,
        onComplete = onComplete
    })


    return {
        success = true,
        pending = true,
        totalCount = #realDestinations
    }

end


-- ============================================================
-- STAGE 2: ASSIGN A VEHICLE TO EACH EMPTY SPLIT LINE, THEN
-- RETIRE THAT DESTINATION FROM THE SOURCE LINE
--
-- Deliberately a SEPARATE entry point from splitLineIntoDestinations
-- above, not a mode of it: Stage 1 stays exactly what its own
-- header comment promises (additive only, never touches the source
-- line or moves a vehicle), so a player retrofitting this mod who
-- only wants the destination lines to exist yet still has that
-- option. This function is the deliberately riskier follow-up,
-- combining two mechanisms that are each independently proven --
-- setLine cross-line reassignment (route_injector's two-park test
-- and reassignment test) and updateLine route rewriting (the
-- original Truck Park stop injection, route_injector.M.run(), which
-- already rewrote this exact production line's stops live) -- for
-- the first time together.
--
-- Decoupled from line creation on purpose: it re-discovers empty
-- "● " lines by reading their own two real stops directly (entity
-- IDs, not name parsing) rather than depending on being called
-- right after splitLineIntoDestinations, so it works the same way
-- whether the split lines were created a moment ago or in an
-- earlier session.
--
-- Per destination, strictly sequential and strictly ordered:
--   1. hold the vehicle (setManualDeparture)
--   2. setLine it onto the empty split line
--   3. release the hold
--   4. ONLY if that setLine actually succeeded, retire the
--      destination's stop from the source line via updateLine
--
-- If a destination has no vehicle available to give it (the source
-- line ran out), or setLine is rejected, its stop is deliberately
-- left on the source line -- the destination keeps being served by
-- the original combined line rather than being dropped with nothing
-- covering it. This is the literal ordering the feature was asked
-- for: never retire a stop before its replacement is confirmed
-- live.
--
-- The one thing this does NOT verify is whether cargo the picked
-- vehicle was already carrying survives the reassignment intact --
-- still an open, only-partially-tested question (see DECISIONS.md
-- Outstanding Unknowns; the dedicated single-vehicle test that used
-- to check this was removed once real Stage 2/3 runs across many
-- vehicles became the stronger evidence). Running this on anything
-- but the disposable test save before that is confirmed would be
-- premature.
-- ============================================================

local function buildSourceLineWithoutStop(sourceLineId, stationGroupToRemove)

    local liveSourceLine = lines.get(sourceLineId)

    if liveSourceLine == nil then
        return nil, 0, "Could not re-read source line."
    end

    local sourceStops = lines.safeField(liveSourceLine, "stops")
    local sourceCount = lines.safeLength(sourceStops)

    local newLine = api.type.Line.new()

    if newLine == nil then
        return nil, 0, "api.type.Line.new() returned nil."
    end

    local newStops = lines.safeField(newLine, "stops")

    if newStops == nil then
        return nil, 0, "New native Line has no stops container."
    end

    -- Preserve waitingTime and vehicleInfo the same way
    -- route_injector.lua's buildInjectedNativeLine does when
    -- rewriting this same kind of line.
    local waitingTime = lines.safeField(liveSourceLine, "waitingTime")

    if waitingTime ~= nil then
        pcall(function()
            newLine.waitingTime = waitingTime
        end)
    end

    vehicles.copyLineVehicleInfo(liveSourceLine, newLine)

    local removedCount = 0

    for index = 1, sourceCount do

        local stop = sourceStops[index]

        if stop ~= nil then

            local stationGroup = lines.safeField(stop, "stationGroup")

            if stationGroup == stationGroupToRemove then

                removedCount = removedCount + 1

            else

                local nativeStop = lines.makeNativeStopCopy(stop)
                local ok, err = lines.appendNativeStop(newStops, nativeStop)

                if not ok then
                    return nil, removedCount, "Failed appending preserved stop: " .. tostring(err)
                end

            end

        end

    end

    return newLine, removedCount, nil

end


local function removeStopFromSourceLine(sourceLineId, stationGroupToRemove, destinationLabel, callback)

    local newLine, removedCount, buildErr =
        buildSourceLineWithoutStop(sourceLineId, stationGroupToRemove)

    if newLine == nil then

        log.info(
            "STAGE 2 STOP REMOVAL FAILED building route ("
                .. tostring(destinationLabel)
                .. "): "
                .. tostring(buildErr)
        )

        callback()
        return

    end

    if removedCount == 0 then

        log.info(
            "STAGE 2 STOP REMOVAL: "
                .. tostring(destinationLabel)
                .. " was not found on the source line -- nothing removed."
        )

        callback()
        return

    end

    local okCommand, commandOrError =
        pcall(api.cmd.make.updateLine, sourceLineId, newLine)

    if not okCommand then

        log.info(
            "STAGE 2 STOP REMOVAL COMMAND ERROR ("
                .. tostring(destinationLabel)
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
                    "STAGE 2 STOP REMOVAL RESULT ("
                        .. tostring(destinationLabel)
                        .. "): "
                        .. tostring(success)
                        .. " ("
                        .. tostring(removedCount)
                        .. " occurrence(s) removed)"
                )

                callback()

            end)

        end)

    if not okSend then

        log.info(
            "STAGE 2 STOP REMOVAL SEND ERROR ("
                .. tostring(destinationLabel)
                .. "): "
                .. tostring(sendErr)
        )

        callback()

    end

end


-- Prefers an empty vehicle -- confirmed loaded (or unreadable)
-- vehicles are skipped entirely, sidestepping Bug A (PROGRESS.md:
-- losing cargo a vehicle is already carrying) rather than testing
-- whether it happens to be safe. Uses vehicles.isVehicleEmpty
-- (game.interface.getEntity's real per-vehicle cargoLoad field,
-- live-confirmed via the loaded-vehicle journey test) -- nil
-- (unconfirmed) is treated the same as loaded, never assumed safe.
local function findEmptyVehicle(vehicleIds)

    for _, vehicleId in ipairs(vehicleIds) do

        if vehicles.isVehicleEmpty(vehicleId) == true then
            return vehicleId
        end

    end

    return nil

end


local function assignOneVehicleThenRetireStop(sourceLineId, splitLineId, destinationStationGroup, destinationLabel, callback)

    local availableVehicleIds = vehicles.getVehiclesForLine(sourceLineId)

    if #availableVehicleIds == 0 then

        log.info(
            "STAGE 2 SKIPPED ("
                .. tostring(destinationLabel)
                .. "): source line has no vehicles left to give it. "
                .. "Its stop is left on the source line -- this "
                .. "destination keeps being served the old way."
        )

        callback()
        return

    end

    local vehicleId = findEmptyVehicle(availableVehicleIds)

    if vehicleId == nil then

        log.info(
            "STAGE 2 SKIPPED ("
                .. tostring(destinationLabel)
                .. "): every vehicle on the source line is currently "
                .. "carrying cargo (or its load couldn't be confirmed) "
                .. "-- none were reassigned, to avoid Bug A "
                .. "(PROGRESS.md). Its stop is left on the source line "
                .. "-- try again once an empty vehicle is available."
        )

        callback()
        return

    end

    log.info(
        "STAGE 2: assigning vehicle "
            .. tostring(vehicleId)
            .. " to "
            .. tostring(destinationLabel)
            .. "'s line (id="
            .. tostring(splitLineId)
            .. ")"
    )

    vehicles.setManualDeparture(vehicleId, true, function(holdSuccess)

        if not holdSuccess then

            log.info(
                "STAGE 2 FAILED (could not hold vehicle "
                    .. tostring(vehicleId)
                    .. "): "
                    .. tostring(destinationLabel)
            )

            callback()
            return

        end

        vehicles.setLine(vehicleId, splitLineId, 0, function(setLineSuccess)

            vehicles.setManualDeparture(vehicleId, false, function(releaseSuccess)

                log.info(
                    "STAGE 2 setLine result for vehicle "
                        .. tostring(vehicleId)
                        .. ": "
                        .. tostring(setLineSuccess)
                        .. " (release: "
                        .. tostring(releaseSuccess)
                        .. ")"
                )

                if not setLineSuccess then

                    log.info(
                        "STAGE 2 FAILED (setLine rejected): "
                            .. tostring(destinationLabel)
                            .. " -- its stop is left on the source line."
                    )

                    callback()
                    return

                end

                removeStopFromSourceLine(
                    sourceLineId,
                    destinationStationGroup,
                    destinationLabel,
                    callback
                )

            end)

        end)

    end)

end


-- Reads a candidate split line's own two real stops to find its
-- destination stationGroup -- entity-ID driven, not name parsing,
-- even though the "● " prefix is what found the candidate in the
-- first place (that prefix is only used to identify WHICH lines are
-- mod-managed, same as everywhere else in this file).
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


local function processStage2Next(context)

    context.index = context.index + 1

    local candidate = context.candidates[context.index]

    if candidate == nil then

        log.info("----------------------------------------")

        log.info(
            "STAGE 2 COMPLETE: processed "
                .. tostring(#context.candidates)
                .. " split line(s)."
        )

        log.info("----------------------------------------")

        if context.onComplete ~= nil then
            context.onComplete(#context.candidates)
        end

        return

    end

    -- Decision 52: a split line that's already staffed (by ongoing
    -- Auto Redistribute, most likely, or a previous run) doesn't need
    -- a vehicle FROM the source line -- it just needs its stop
    -- retired off the source, same end state either way.
    if candidate.vehicleCount > 0 then

        log.info(
            "STAGE 2: "
                .. tostring(candidate.name)
                .. " already has "
                .. tostring(candidate.vehicleCount)
                .. " vehicle(s) -- retiring its stop without assigning "
                .. "another."
        )

        removeStopFromSourceLine(
            context.sourceLineId,
            candidate.destinationStationGroup,
            candidate.name,

            function()
                processStage2Next(context)
            end
        )

        return

    end

    assignOneVehicleThenRetireStop(
        context.sourceLineId,
        candidate.id,
        candidate.destinationStationGroup,
        candidate.name,

        function()
            processStage2Next(context)
        end
    )

end


-- sourceLineId: the real, currently-working combined line to pull
-- vehicles from and retire stops off of (e.g. found via
-- lines.findByName(config.SOURCE_LINE_NAME)).
--
-- hubStationGroup: the focused hub, used only to tell a split line's
-- hub-side stop apart from its destination-side stop.
function M.assignVehiclesAndRetireStops(sourceLineId, hubStationGroup, onComplete)

    log.info("----------------------------------------")
    log.info("STAGE 2: ASSIGN VEHICLES + RETIRE STOPS")
    log.info("----------------------------------------")

    if sourceLineId == nil then

        log.info("FAILED: source line not found.")

        -- Decision 61: every early-return path here must call
        -- onComplete -- processSourceLineNext chains through it to
        -- run Stage 3 + the delete step and move on to the NEXT
        -- recorded source line for this hub. Missing this on any
        -- branch silently kills the whole Assign & Balance run the
        -- moment it hits a stale/unreadable source line ID.
        if onComplete ~= nil then
            onComplete(0)
        end

        return {
            success = false,
            reason = "source-line-not-found"
        }

    end

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then

        log.info("FAILED: could not read line list.")

        if onComplete ~= nil then
            onComplete(0)
        end

        return {
            success = false,
            reason = "line-list-unavailable"
        }

    end

    -- LIVE-CONFIRMED BUG (Decision 52): this used to only consider a
    -- split line a candidate if it was STILL EMPTY (vehicleCount ==
    -- 0) -- written back when Stage 2 was the only thing that could
    -- ever put a vehicle on a freshly-split line. Now that ongoing
    -- Auto Redistribute runs concurrently and correctly treats every
    -- registered split line as a normal deficit candidate, it
    -- routinely staffs a split line with its own floor vehicle
    -- before the player ever clicks "Assign & Balance Fleet" --
    -- meaning that split line no longer counted as a "candidate"
    -- here, so its stop was NEVER retired from the source line. The
    -- source line's remaining un-retired stops kept showing real
    -- waiting demand indefinitely, which both the ongoing dispatcher
    -- AND this same Stage 3 redistribution kept correctly (from their
    -- own local view) feeding MORE vehicles into -- the source line
    -- could never reach zero and be deleted, exactly the "it keeps
    -- getting reassigned a 2nd truck" behavior observed live. Fixed:
    -- every managed split line touching this hub is now a candidate
    -- regardless of current vehicle count; a line that's ALREADY
    -- staffed (by Auto Redistribute or a previous run, doesn't
    -- matter which) just has its stop retired directly, skipping the
    -- assign-a-vehicle step it no longer needs.
    local candidates = {}

    for _, lineId in ipairs(allLineIds) do

        local name = lines.getName(lineId)

        -- Harmless but confusing without this: the source line is
        -- itself "managed" and can itself resolve a
        -- destinationStationGroup (whatever real stop happens to be
        -- first in whatever it has left), so without excluding it
        -- explicitly it shows up as its own candidate and retires one
        -- more of its own stops via a slightly misleading code path.
        -- Observed live (harmless -- it just did one more legitimate
        -- stop removal against itself) but worth excluding cleanly.
        if lineId ~= sourceLineId
            and managed_registry.isManaged(lineId)
        then

            local destinationStationGroup =
                findDestinationStationGroupOnSplitLine(lineId, hubStationGroup)

            if destinationStationGroup ~= nil then

                candidates[#candidates + 1] = {
                    id = lineId,
                    name = name,
                    destinationStationGroup = destinationStationGroup,
                    vehicleCount = #vehicles.getVehiclesForLine(lineId)
                }

            end

        end

    end

    if #candidates == 0 then

        log.info(
            "Nothing to do: no mod-created (\"● \") split lines found."
        )

        if onComplete ~= nil then
            onComplete(0)
        end

        return {
            success = true,
            processedCount = 0
        }

    end

    log.info(
        "Split lines found: "
            .. tostring(#candidates)
    )

    processStage2Next({
        sourceLineId = sourceLineId,
        candidates = candidates,
        index = 0,
        onComplete = onComplete
    })

    return {
        success = true,
        pending = true,
        totalCount = #candidates
    }

end


-- ============================================================
-- DELETE EMPTY SOURCE LINE
--
-- Once assignVehiclesAndRetireStops (above) has handed every real
-- destination and every vehicle off to its own split line, the
-- source line can be left with 0 vehicles and 0 real destinations
-- -- just a degenerate loop of the hub stop repeated with nothing
-- left to serve. Confirmed live this actually happens (Decision 20's
-- live run: "Truck - CD - Hendon" reduced to 0 real destinations;
-- a later Stage 3 run then moved every one of its vehicles
-- elsewhere too, accounting for the full fleet total across the
-- other managed lines with none left over).
--
-- Refuses to delete anything that still has a vehicle OR still
-- serves a real (non-hub) destination -- this is a safety check,
-- not a formality: deleteLine is proven (route_injector's original
-- create/delete test), but it should only ever run against a line
-- confirmed to have nothing left to lose.
-- ============================================================

function M.deleteEmptySourceLine(sourceLineId, hubStationGroup, onComplete)

    log.info("----------------------------------------")
    log.info("DELETE EMPTY SOURCE LINE")
    log.info("----------------------------------------")

    if sourceLineId == nil then

        log.info("FAILED: source line not found.")

        if onComplete ~= nil then
            onComplete(false, "source-line-not-found")
        end

        return {
            success = false,
            reason = "source-line-not-found"
        }

    end


    local vehicleCount = #vehicles.getVehiclesForLine(sourceLineId)

    if vehicleCount > 0 then

        log.info(
            "REFUSED: source line still has "
                .. tostring(vehicleCount)
                .. " vehicle(s) -- not deleting a line that's still doing work."
        )

        if onComplete ~= nil then
            onComplete(false, "still-has-vehicles")
        end

        return {
            success = false,
            reason = "still-has-vehicles"
        }

    end


    local sourceLine = lines.get(sourceLineId)

    if sourceLine == nil then

        log.info("FAILED: could not read source line.")

        if onComplete ~= nil then
            onComplete(false, "source-line-unreadable")
        end

        return {
            success = false,
            reason = "source-line-unreadable"
        }

    end

    local stops = lines.safeField(sourceLine, "stops")
    local stopCount = lines.safeLength(stops)

    local realDestinationCount = 0

    for index = 1, stopCount do

        local stop = stops[index]

        if stop ~= nil then

            local stationGroup = lines.safeField(stop, "stationGroup")

            if stationGroup ~= hubStationGroup then
                realDestinationCount = realDestinationCount + 1
            end

        end

    end

    if realDestinationCount > 0 then

        log.info(
            "REFUSED: source line still serves "
                .. tostring(realDestinationCount)
                .. " real destination stop(s) -- not deleting a line "
                .. "that's still doing work."
        )

        if onComplete ~= nil then
            onComplete(false, "still-has-destinations")
        end

        return {
            success = false,
            reason = "still-has-destinations"
        }

    end


    log.info(
        "Source line confirmed empty: 0 vehicles, 0 real destinations. Deleting..."
    )

    local okCommand, commandOrError =
        pcall(api.cmd.make.deleteLine, sourceLineId)

    if not okCommand then

        log.info(
            "DELETE LINE COMMAND ERROR: "
                .. tostring(commandOrError)
        )

        if onComplete ~= nil then
            onComplete(false, "delete-command-failed")
        end

        return {
            success = false,
            reason = "delete-command-failed"
        }

    end


    local okSend, sendErr =
        pcall(function()

            api.cmd.sendCommand(commandOrError, function(cmd, success)

                log.info("DELETE LINE RESULT: " .. tostring(success))

                if onComplete ~= nil then
                    onComplete(success, success and "deleted" or "rejected")
                end

            end)

        end)

    if not okSend then

        log.info("DELETE LINE SEND ERROR: " .. tostring(sendErr))

        if onComplete ~= nil then
            onComplete(false, "send-failed")
        end

        return {
            success = false,
            reason = "send-failed"
        }

    end


    return {
        success = true,
        pending = true
    }

end


-- ============================================================
-- DEDUPE: TWO MANAGED LINES SERVING THE SAME STATION PAIR
--
-- Decision 59: before the line_ownership check above existed (and
-- for any data already sitting in a save from before this fix), a
-- source line touching two enabled hubs at once could get split
-- independently from BOTH hubs' perspectives, producing two separate
-- 2-stop lines connecting the exact same two stations -- e.g.
-- "Thatcham Sidings <-> Goole North" and "Goole North <-> Thatcham
-- Sidings" as two different line entities. This mod treats lines as
-- direction-agnostic (Decision 18/19), so two lines sharing a
-- station pair are genuine duplicates, not two different routes.
--
-- Only ever deletes a duplicate with 0 vehicles -- same safety
-- discipline as deleteEmptySourceLine above (deleteLine is proven,
-- but only ever run against a line confirmed to have nothing left to
-- lose). If more than one copy in a pair already has vehicles, none
-- are touched -- resolving that would mean moving real vehicles/
-- cargo, out of scope here, so it's only logged for a person to
-- look at. Only ever considers plain 2-stop managed lines -- a
-- combined source line (more than 2 stops) is a different shape and
-- never a candidate here.
-- ============================================================

local function findManagedTwoStopLines()

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

            local line = lines.get(lineId)
            local stops = line ~= nil and lines.safeField(line, "stops") or nil
            local stopCount = lines.safeLength(stops)

            if stopCount == 2 then

                local stationGroupA = lines.safeField(stops[1], "stationGroup")
                local stationGroupB = lines.safeField(stops[2], "stationGroup")

                if stationGroupA ~= nil and stationGroupB ~= nil then

                    local key =
                        stationGroupA < stationGroupB
                            and (tostring(stationGroupA) .. ":" .. tostring(stationGroupB))
                            or (tostring(stationGroupB) .. ":" .. tostring(stationGroupA))

                    candidates[#candidates + 1] = {
                        id = lineId,
                        name = lines.getName(lineId),
                        key = key,
                        vehicleCount = #vehicles.getVehiclesForLine(lineId)
                    }

                end

            end

        end

    end

    return candidates

end


-- Shared by dedupeSharedRouteLines and deleteEmptyOwnedLines below --
-- both only ever call this once they've already confirmed 0 vehicles,
-- so no extra safety check is repeated here. logTag identifies which
-- feature triggered the delete in the log, since both features can
-- fire independently.
local function deleteEmptyManagedLine(entry, logTag, callback)

    -- LIVE-CONFIRMED CRASH (Decision 63): api.cmd.make.deleteLine on
    -- an ID that doesn't correspond to a real, currently-readable
    -- line is a native engine crash ("Internal error"), not a Lua
    -- error -- pcall around the command below does NOT catch it,
    -- same lesson as Decision 56/57's alternativeTerminals crashes.
    -- deleteEmptySourceLine has always re-read the line right before
    -- deleting it for exactly this reason; this shared helper never
    -- did. Bit live: source_line_registry/line_ownership/hub_registry
    -- all write to the game install folder rather than per-save
    -- (a long-documented gap, PROGRESS.md), so loading a DIFFERENT
    -- save that happens to share entity IDs with a previous session
    -- (as save-1 and save-2 do here, since save-2 is a later save of
    -- the same lineage) can hand this function a line ID that's
    -- stale/nonexistent in the save actually loaded right now. Only
    -- ever attempt the delete once the line is confirmed to still
    -- exist and be readable.
    if lines.get(entry.id) == nil then

        log.info(
            logTag .. ": REFUSED (line no longer exists/unreadable, not "
                .. "attempting delete -- likely a stale cross-save "
                .. "registry entry): "
                .. tostring(entry.name)
                .. " (id=" .. tostring(entry.id) .. ")"
        )

        callback()
        return

    end

    log.info(
        logTag .. ": deleting empty line (0 vehicles): "
            .. tostring(entry.name)
            .. " (id=" .. tostring(entry.id) .. ")"
    )

    local okCommand, commandOrError =
        pcall(api.cmd.make.deleteLine, entry.id)

    if not okCommand then

        log.info(
            logTag .. ": DELETE LINE COMMAND ERROR ("
                .. tostring(entry.name)
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
                    logTag .. ": DELETE RESULT ("
                        .. tostring(entry.name)
                        .. "): "
                        .. tostring(success)
                )

                callback()

            end)

        end)

    if not okSend then

        log.info(
            logTag .. ": DELETE SEND ERROR ("
                .. tostring(entry.name)
                .. "): "
                .. tostring(sendErr)
        )

        callback()

    end

end


local function processDedupeGroupsNext(groupKeys, groups, index, deletedCount, onComplete)

    local key = groupKeys[index]

    if key == nil then

        log.info("----------------------------------------")

        log.info(
            "DEDUPE COMPLETE: "
                .. tostring(deletedCount)
                .. " duplicate line(s) deleted."
        )

        log.info("----------------------------------------")

        if onComplete ~= nil then
            onComplete(deletedCount)
        end

        return

    end

    local group = groups[key]

    if group == nil or #group < 2 then
        processDedupeGroupsNext(groupKeys, groups, index + 1, deletedCount, onComplete)
        return
    end

    local withVehicles = {}
    local empty = {}

    for _, entry in ipairs(group) do

        if entry.vehicleCount > 0 then
            withVehicles[#withVehicles + 1] = entry
        else
            empty[#empty + 1] = entry
        end

    end

    if #withVehicles > 1 then

        log.info(
            "DEDUPE: skipping duplicate pair -- more than one copy already "
                .. "has vehicles, not safe to auto-resolve: "
                .. tostring(group[1].name)
        )

        processDedupeGroupsNext(groupKeys, groups, index + 1, deletedCount, onComplete)
        return

    end

    -- Keep exactly one: whichever copy has vehicles, if any, else the
    -- first empty one found. Delete every other empty copy.
    local keepId = nil

    if #withVehicles == 1 then
        keepId = withVehicles[1].id
    elseif #empty > 0 then
        keepId = empty[1].id
    end

    local toDelete = {}

    for _, entry in ipairs(empty) do
        if entry.id ~= keepId then
            toDelete[#toDelete + 1] = entry
        end
    end

    local function deleteNext(deleteIndex, runningDeletedCount)

        local entry = toDelete[deleteIndex]

        if entry == nil then
            processDedupeGroupsNext(groupKeys, groups, index + 1, runningDeletedCount, onComplete)
            return
        end

        deleteEmptyManagedLine(entry, "DEDUPE", function()
            deleteNext(deleteIndex + 1, runningDeletedCount + 1)
        end)

    end

    deleteNext(1, deletedCount)

end


-- Network-wide, not scoped to a single hub -- a duplicate pair can
-- span two different hubs (that's exactly how Decision 59's case
-- happened), so there is no single "current hub" to scope this to.
function M.dedupeSharedRouteLines(onComplete)

    log.info("----------------------------------------")
    log.info("DEDUPE: SHARED ROUTE LINES")
    log.info("----------------------------------------")

    local candidates = findManagedTwoStopLines()

    local groups = {}
    local groupKeys = {}

    for _, entry in ipairs(candidates) do

        if groups[entry.key] == nil then
            groups[entry.key] = {}
            groupKeys[#groupKeys + 1] = entry.key
        end

        local group = groups[entry.key]
        group[#group + 1] = entry

    end

    processDedupeGroupsNext(groupKeys, groups, 1, 0, onComplete)

end


-- ============================================================
-- DELETE EMPTY LINES LEFT BEHIND WHEN A HUB IS DISABLED
--
-- Decision 60: raised live straight after the Thatcham Sidings
-- episode (Decision 59) -- turning Auto Redistribute OFF for a hub
-- stops it claiming NEW lines, but does nothing about ones it already
-- claimed while it was briefly enabled. Those were left sitting there
-- as permanent 0-vehicle clutter until someone noticed and deleted
-- them by hand. Player's framing: the mod should be a step ahead of
-- whatever a player accidentally sets up, not just report on it.
--
-- Wired into handleAutoRedistributeToggleButtonClick's disable branch
-- (epod_truck_distribution.lua) -- runs the moment a hub is turned
-- off, reacting to that specific player action rather than sweeping
-- the whole network in the background on its own schedule.
--
-- Only ever deletes a line with 0 vehicles, same safety discipline as
-- dedupeSharedRouteLines and deleteEmptySourceLine. A line the
-- now-disabled hub owns that still has real vehicles is left
-- completely alone and just logged -- it's still doing real work
-- moving real cargo, whatever hub_registry's enabled/disabled flag
-- says now.
-- ============================================================

local function processDeleteEmptyOwnedNext(candidates, index, deletedCount, onComplete)

    local entry = candidates[index]

    if entry == nil then

        log.info("----------------------------------------")

        log.info(
            "HUB DISABLE CLEANUP COMPLETE: "
                .. tostring(deletedCount)
                .. " empty owned line(s) deleted."
        )

        log.info("----------------------------------------")

        if onComplete ~= nil then
            onComplete(deletedCount)
        end

        return

    end

    if entry.vehicleCount > 0 then

        log.info(
            "HUB DISABLE CLEANUP: leaving "
                .. tostring(entry.name)
                .. " alone -- still has "
                .. tostring(entry.vehicleCount)
                .. " vehicle(s)."
        )

        processDeleteEmptyOwnedNext(candidates, index + 1, deletedCount, onComplete)
        return

    end

    deleteEmptyManagedLine(entry, "HUB DISABLE CLEANUP", function()
        processDeleteEmptyOwnedNext(candidates, index + 1, deletedCount + 1, onComplete)
    end)

end


function M.deleteEmptyOwnedLines(hubStationGroupId, onComplete)

    log.info("----------------------------------------")
    log.info("HUB DISABLE CLEANUP: deleting empty lines owned by hub " .. tostring(hubStationGroupId))
    log.info("----------------------------------------")

    local ownedLineIds = line_ownership.getLinesOwnedBy(hubStationGroupId)

    local candidates = {}

    for _, lineId in ipairs(ownedLineIds) do

        candidates[#candidates + 1] = {
            id = lineId,
            name = lines.getName(lineId),
            vehicleCount = #vehicles.getVehiclesForLine(lineId)
        }

    end

    processDeleteEmptyOwnedNext(candidates, 1, 0, onComplete)

end


return M
