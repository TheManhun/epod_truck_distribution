local log = require("epod_td.log")
local lines = require("epod_td.lines")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local managed_registry = require("epod_td.managed_registry")

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

    if lines.findByName(newLineName) ~= nil then

        log.info(
            "SPLIT SKIPPED (line already exists): "
                .. tostring(newLineName)
        )

        processNext(context)
        return

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


    processNext({
        sourceLine = sourceLine,
        sourceLineName = lineInfo.name,
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
                .. " empty split line(s)."
        )

        log.info("----------------------------------------")

        if context.onComplete ~= nil then
            context.onComplete(#context.candidates)
        end

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

        return {
            success = false,
            reason = "line-list-unavailable"
        }

    end

    local candidates = {}

    for _, lineId in ipairs(allLineIds) do

        local name = lines.getName(lineId)

        if managed_registry.isManaged(lineId) then

            local vehicleCount = #vehicles.getVehiclesForLine(lineId)

            if vehicleCount == 0 then

                local destinationStationGroup =
                    findDestinationStationGroupOnSplitLine(lineId, hubStationGroup)

                if destinationStationGroup ~= nil then

                    candidates[#candidates + 1] = {
                        id = lineId,
                        name = name,
                        destinationStationGroup = destinationStationGroup
                    }

                end

            end

        end

    end

    if #candidates == 0 then

        log.info(
            "Nothing to do: no empty mod-created (\"● \") split lines found."
        )

        return {
            success = true,
            processedCount = 0
        }

    end

    log.info(
        "Empty split lines found: "
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


return M
