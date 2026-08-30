local log = require("epod_td.log")
local lines = require("epod_td.lines")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local truck_station_finder = require("epod_td.truck_station_finder")
local managed_registry = require("epod_td.managed_registry")

local M = {}


-- ============================================================
-- ALTERNATIVE ROUTE SUGGESTION (Decision 188)
--
-- Player's own idea, building on the Truck Pool (Decision 187): "this
-- idea might free up more trucks... a line might be deleted as the
-- return truck can do it." A player-confirmed SUGGESTION only, never
-- automatic -- same rule as every mutating action in this mod.
--
-- Deliberately a DIFFERENT detection signal from chain_builder.lua's
-- own "Build Supply Chains": that one merges two of a hub's lines by a
-- real INDUSTRY RECIPE relationship (producer's output matches a
-- consumer's most-needed input), regardless of physical distance. This
-- module merges by PROXIMITY instead -- two stations that happen to be
-- geographically close, regardless of any recipe relationship. Shares
-- no code with chain_builder.lua, only the same proven execution
-- primitives from lines.lua/vehicles.lua it also relies on.
--
-- Real, already-proven mechanics reused, not guessed:
--   * Position: game.interface.getEntity(stationGroupId).position, a
--     plain {x, y, z}-shaped table indexed [1]/[2]/[3] -- same field
--     industry_naming.lua and gui_tab_overview.lua's own camera-jump
--     handler already read fresh at point-of-use (truck_station_finder.
--     scan()'s own cached results do NOT carry position).
--   * distanceSquared -- same 2D squared-distance formula industry_
--     naming.lua's own (private) helper already uses for "is this
--     station near that thing," duplicated here as a small local
--     helper rather than reaching into that file for something this
--     trivial.
--   * Cargo compatibility -- stations.getUnloadedCargoTypes +
--     vehicles.isCompatibleWithCargoType, the exact same pair
--     dispatcher.lua's own vehicleCompatibleWithAny already uses.
--   * Modifying a real, already-existing line's stops -- api.type.
--     Line.new() + lines.makeNativeStopCopy + lines.appendNativeStop +
--     api.cmd.make.updateLine -- this exact sequence is already live in
--     terminal_allocator.lua's setLineHubTerminal and line_splitter.
--     lua's buildSingleDestinationLine. REAL LIMITATION carried over
--     honestly: makeNativeStopCopy always copies from a stop object on
--     a line that ALREADY exists somewhere -- there is no proven
--     pattern anywhere in this codebase for building a Line.Stop truly
--     from scratch for a station that has never been on any line. A
--     candidate station with zero current lines is simply skipped, not
--     attempted.
--   * Migrate vehicles off the now-redundant line, delete it if it
--     ends up empty -- the exact same migrateEmptyVehiclesNext/
--     deleteIfEmpty pattern chain_builder.lua's own
--     M.migrateVehiclesAndCleanup already proves safe (same hold ->
--     setLine -> release sequence, same vehicles.isVehicleEmpty guard,
--     never deletes a line still carrying real traffic).
--
-- NOT modeled: adding a stop increases the ORIGINAL destination's own
-- round-trip time -- not calculated or shown anywhere. An honest gap,
-- same spirit as the Fleet Needs Report's own terminal-storage-cap
-- caveat.
-- ============================================================

-- Starting guess, not pixel/distance-tuned against a real map yet --
-- same "starting guess, live-tune later" category as every other new
-- threshold this session.
local SEARCH_RADIUS = 400
local SEARCH_RADIUS_SQUARED = SEARCH_RADIUS * SEARCH_RADIUS


local function distanceSquared(a, b)
    local dx = (a[1] or 0) - (b[1] or 0)
    local dy = (a[2] or 0) - (b[2] or 0)
    return dx * dx + dy * dy
end


local function getPosition(stationGroupId)

    local ok, entity = pcall(game.interface.getEntity, stationGroupId)

    if ok and entity ~= nil then
        return entity.position
    end

    return nil

end


local function findStopByStationGroup(line, stationGroupId)

    local stops = lines.safeField(line, "stops")
    local count = lines.safeLength(stops)

    for index = 1, count do

        local stop = stops[index]

        if stop ~= nil and lines.safeField(stop, "stationGroup") == stationGroupId then
            return stop
        end

    end

    return nil

end


local function vehicleCompatibleWithAny(vehicleId, cargoTypes)

    if #cargoTypes == 0 then
        return true
    end

    for _, cargoType in ipairs(cargoTypes) do

        if vehicles.isCompatibleWithCargoType(vehicleId, cargoType) == true then
            return true
        end

    end

    return false

end


-- Finds the nearest OTHER real truck station within SEARCH_RADIUS of
-- lineInfo's own single real destination, not already served by this
-- hub, not itself a hub, cargo-compatible with a vehicle already on
-- this line. Returns the matching truck_station_finder.scan() entry,
-- or nil.
function M.findNearbyStopCandidate(hubStationGroupId, lineInfo)

    local realDestination = nil

    for _, destination in ipairs(lineInfo.destinations or {}) do

        if destination.stationGroup ~= hubStationGroupId then
            realDestination = destination
            break
        end

    end

    if realDestination == nil then
        return nil
    end

    local originPosition = getPosition(realDestination.stationGroup)

    if originPosition == nil then
        return nil
    end

    local vehicleIds = vehicles.getVehiclesForLine(lineInfo.id)

    if #vehicleIds == 0 then
        return nil
    end

    local sampleVehicleId = vehicleIds[1]

    local okScan, scanResult = pcall(truck_station_finder.scan)

    if not okScan or scanResult == nil then
        return nil
    end

    -- Stations already served by this hub -- never suggest one already
    -- part of the picture.
    local alreadyServed = {}

    local okManaged, managedLines = pcall(vehicles.getManagedLinesForStation, hubStationGroupId)

    if okManaged and managedLines ~= nil then

        for _, otherLineInfo in ipairs(managedLines) do

            for _, destination in ipairs(otherLineInfo.destinations or {}) do
                alreadyServed[destination.stationGroup] = true
            end

        end

    end

    local best = nil
    local bestDistanceSquared = nil

    for _, entry in ipairs(scanResult) do

        if entry.stationGroupId ~= hubStationGroupId
            and entry.stationGroupId ~= realDestination.stationGroup
            and not alreadyServed[entry.stationGroupId]
            and not entry.isHub
        then

            local candidatePosition = getPosition(entry.stationGroupId)

            if candidatePosition ~= nil then

                local candidateDistanceSquared = distanceSquared(originPosition, candidatePosition)

                if candidateDistanceSquared <= SEARCH_RADIUS_SQUARED
                    and (bestDistanceSquared == nil or candidateDistanceSquared < bestDistanceSquared)
                then

                    local unloadedCargoTypes = stations.getUnloadedCargoTypes(entry.stationGroupId)

                    if vehicleCompatibleWithAny(sampleVehicleId, unloadedCargoTypes) then
                        best = entry
                        bestDistanceSquared = candidateDistanceSquared
                    end

                end

            end

        end

    end

    return best

end


-- Pure read -- mirrors M.applyAlternativeRoute's real decision logic
-- exactly (same "preview never promises something the real pass
-- wouldn't do" rule hub_setup.previewConversion already established).
-- Returns nil if this line has no real alternative-route candidate.
function M.previewAlternativeRoute(hubStationGroupId, lineId)

    local okManaged, managedLines = pcall(vehicles.getManagedLinesForStation, hubStationGroupId)

    if not okManaged or managedLines == nil then
        return nil
    end

    local lineInfo = nil

    for _, candidate in ipairs(managedLines) do

        if candidate.id == lineId then
            lineInfo = candidate
            break
        end

    end

    if lineInfo == nil then
        return nil
    end

    local candidate = M.findNearbyStopCandidate(hubStationGroupId, lineInfo)

    if candidate == nil then
        return nil
    end

    -- How many vehicles currently serve the candidate on its OWN
    -- separate line -- these are the ones that COULD be freed up if
    -- that line goes empty after migration. A real count, not a guess.
    local okCandidateLines, candidateLines =
        pcall(vehicles.getManagedLinesForStation, candidate.stationGroupId)

    local candidateLineId = nil
    local candidateVehicleCount = 0

    if okCandidateLines and candidateLines ~= nil and #candidateLines > 0 then
        candidateLineId = candidateLines[1].id
        candidateVehicleCount = candidateLines[1].vehicleCount or 0
    end

    return {
        lineId = lineId,
        lineName = lineInfo.name,
        candidateStationGroupId = candidate.stationGroupId,
        candidateName = candidate.name,
        candidateLineId = candidateLineId,
        candidateVehicleCount = candidateVehicleCount
    }

end


-- Same migrateEmptyVehiclesNext/deleteIfEmpty pattern chain_builder.lua
-- already proves safe -- duplicated here rather than exported from
-- that file, since both are private (local) there and this module's
-- own detection logic is deliberately unrelated to chain_builder's.
local function migrateEmptyVehiclesNext(vehicleIds, index, newLineId, movedCount, onComplete)

    local vehicleId = vehicleIds[index]

    if vehicleId == nil then
        onComplete(movedCount)
        return
    end

    if vehicles.isVehicleEmpty(vehicleId) ~= true then
        migrateEmptyVehiclesNext(vehicleIds, index + 1, newLineId, movedCount, onComplete)
        return
    end

    vehicles.setManualDeparture(vehicleId, true, function(holdSuccess)

        if not holdSuccess then
            migrateEmptyVehiclesNext(vehicleIds, index + 1, newLineId, movedCount, onComplete)
            return
        end

        vehicles.setLine(vehicleId, newLineId, 0, function(setLineSuccess)

            vehicles.setManualDeparture(vehicleId, false, function()

                log.info(
                    "ROUTE OPTIMIZER: moved vehicle " .. tostring(vehicleId)
                        .. " onto line " .. tostring(newLineId)
                        .. ": " .. tostring(setLineSuccess)
                )

                migrateEmptyVehiclesNext(
                    vehicleIds,
                    index + 1,
                    newLineId,
                    setLineSuccess and (movedCount + 1) or movedCount,
                    onComplete
                )

            end)

        end)

    end)

end


local function deleteIfEmpty(oldLineId, onComplete)

    if lines.get(oldLineId) == nil then
        onComplete()
        return
    end

    if #vehicles.getVehiclesForLine(oldLineId) > 0 then

        log.info(
            "ROUTE OPTIMIZER: old line " .. tostring(oldLineId)
                .. " still has vehicle(s) carrying cargo -- left in place, retry later."
        )

        onComplete()
        return

    end

    local okCommand, commandOrError = pcall(api.cmd.make.deleteLine, oldLineId)

    if not okCommand then

        log.info("ROUTE OPTIMIZER: delete command error for line " .. tostring(oldLineId) .. ": " .. tostring(commandOrError))
        onComplete()
        return

    end

    local okSend, sendErr =
        pcall(function()

            api.cmd.sendCommand(commandOrError, function(cmd, success)

                log.info("ROUTE OPTIMIZER: deleted old line " .. tostring(oldLineId) .. ": " .. tostring(success))

                if success then
                    managed_registry.unregister(oldLineId)
                end

                onComplete()

            end)

        end)

    if not okSend then
        log.info("ROUTE OPTIMIZER: delete send error for line " .. tostring(oldLineId) .. ": " .. tostring(sendErr))
        onComplete()
    end

end


-- The real mutating sequence. `preview` must be a fresh result from
-- M.previewAlternativeRoute -- never trusted stale (a hub's real state
-- can change between opening the popup and clicking Confirm).
function M.applyAlternativeRoute(hubStationGroupId, lineId, preview, onStatusUpdate, onComplete)

    onStatusUpdate = onStatusUpdate or function() end
    onComplete = onComplete or function() end

    local currentLine = lines.get(lineId)

    if currentLine == nil then

        log.info("ROUTE OPTIMIZER: line " .. tostring(lineId) .. " no longer exists.")
        onComplete(false)
        return

    end

    if preview.candidateLineId == nil then

        log.info("ROUTE OPTIMIZER: candidate station has no existing line to copy a stop from -- skipping.")
        onComplete(false)
        return

    end

    local candidateLine = lines.get(preview.candidateLineId)

    if candidateLine == nil then
        onComplete(false)
        return
    end

    local candidateStop = findStopByStationGroup(candidateLine, preview.candidateStationGroupId)

    if candidateStop == nil then

        log.info("ROUTE OPTIMIZER: could not find candidate's own real stop object -- skipping.")
        onComplete(false)
        return

    end

    onStatusUpdate("Adding stop to line...")

    local newLine = api.type.Line.new()

    if newLine == nil then
        onComplete(false)
        return
    end

    local newStops = lines.safeField(newLine, "stops")

    if newStops == nil then
        onComplete(false)
        return
    end

    local waitingTime = lines.safeField(currentLine, "waitingTime")

    if waitingTime ~= nil then
        pcall(function() newLine.waitingTime = waitingTime end)
    end

    vehicles.copyLineVehicleInfo(currentLine, newLine)

    local existingStops = lines.safeField(currentLine, "stops")
    local existingCount = lines.safeLength(existingStops)

    for index = 1, existingCount do

        local sourceStop = existingStops[index]

        if sourceStop ~= nil then
            lines.appendNativeStop(newStops, lines.makeNativeStopCopy(sourceStop))
        end

    end

    lines.appendNativeStop(newStops, lines.makeNativeStopCopy(candidateStop))

    local okCommand, commandOrError = pcall(api.cmd.make.updateLine, lineId, newLine)

    if not okCommand then

        log.info("ROUTE OPTIMIZER: updateLine command error: " .. tostring(commandOrError))
        onComplete(false)
        return

    end

    local okSend, sendErr =
        pcall(function()

            api.cmd.sendCommand(commandOrError, function(cmd, success)

                log.info("ROUTE OPTIMIZER: added stop to line " .. tostring(lineId) .. ": " .. tostring(success))

                if not success then
                    onComplete(false)
                    return
                end

                onStatusUpdate("Retiring redundant line if now empty...")

                local candidateLineId = preview.candidateLineId
                local candidateVehicleIds = vehicles.getVehiclesForLine(candidateLineId)

                if #candidateVehicleIds == 0 then

                    deleteIfEmpty(candidateLineId, function()
                        onComplete(true)
                    end)

                else

                    migrateEmptyVehiclesNext(
                        candidateVehicleIds,
                        1,
                        lineId,
                        0,

                        function(movedCount)

                            log.info(
                                "ROUTE OPTIMIZER: migrated " .. tostring(movedCount)
                                    .. " vehicle(s) from old line " .. tostring(candidateLineId)
                            )

                            deleteIfEmpty(candidateLineId, function()
                                onComplete(true)
                            end)

                        end
                    )

                end

            end)

        end)

    if not okSend then

        log.info("ROUTE OPTIMIZER: updateLine send error: " .. tostring(sendErr))
        onComplete(false)

    end

end


return M
