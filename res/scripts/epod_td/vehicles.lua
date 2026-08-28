local config = require("epod_td.config")
local lines = require("epod_td.lines")
local stations = require("epod_td.stations")
local log = require("epod_td.log")

local M = {}


-- ============================================================
-- BASIC VEHICLE ACCESS
-- ============================================================

function M.get(vehicleId)

    if vehicleId == nil
        or vehicleId < 0
    then
        return nil
    end


    local ok, vehicle =
        pcall(
            api.engine.getComponent,
            vehicleId,
            api.type.ComponentType.TRANSPORT_VEHICLE
        )


    if not ok then
        return nil
    end


    return vehicle

end


-- ============================================================
-- VEHICLES ASSIGNED TO LINE
-- ============================================================

function M.getVehiclesForLine(lineId)

    if lineId == nil then
        return {}
    end


    local ok, result =
        pcall(
            api.engine.system.transportVehicleSystem.getLineVehicles,
            lineId
        )


    if not ok
        or result == nil
    then
        return {}
    end


    local vehicleIds = {}


    for _, vehicleId
        in ipairs(result)
    do

        vehicleIds[#vehicleIds + 1] =
            vehicleId

    end


    return vehicleIds

end


-- ============================================================
-- STATE NAME
-- ============================================================

function M.getStateName(state)

    if state == 0 then
        return "IN_DEPOT"
    end

    if state == 1 then
        return "EN_ROUTE"
    end

    if state == 2 then
        return "AT_TERMINAL"
    end

    if state == 3 then
        return "GOING_TO_DEPOT"
    end


    return "UNKNOWN_"
        .. tostring(state)

end


-- ============================================================
-- ROUTE MAP
--
-- Build a Lua table describing every stop on the current line.
--
-- IMPORTANT:
-- TransportVehicle.stopIndex appears to use ZERO-BASED route
-- indexing, while the native Lua stops container is ONE-BASED.
-- ============================================================

function M.buildRouteMap(lineId)

    local routeMap = {}

    local line =
        lines.get(lineId)


    if line == nil then
        return routeMap
    end


    local stops =
        lines.safeField(
            line,
            "stops"
        )


    if stops == nil then
        return routeMap
    end


    local count =
        lines.safeLength(stops)


    for luaIndex = 1, count do

        local stop =
            stops[luaIndex]


        if stop ~= nil then

            local stationGroup =
                lines.safeField(
                    stop,
                    "stationGroup"
                )


            local name =
                stations.getEntityName(
                    stationGroup
                )


            local routeIndex =
                luaIndex - 1


            local role =
                "DESTINATION"


            if name
                == config.PARK_NAME
            then

                role =
                    "PARK"

            elseif name
                == config.HUB_NAME
            then

                role =
                    "HUB"

            end


            routeMap[routeIndex] = {

                stopIndex =
                    routeIndex,

                stationGroup =
                    stationGroup,

                name =
                    name,

                role =
                    role

            }

        end

    end


    return routeMap

end


-- ============================================================
-- READ ONE VEHICLE
-- ============================================================

function M.inspect(
    vehicleId,
    routeMap
)

    local vehicle =
        M.get(vehicleId)


    if vehicle == nil then

        return {
            id = vehicleId,
            valid = false
        }

    end


    local state =
        lines.safeField(
            vehicle,
            "state"
        )

    local lineId =
        lines.safeField(
            vehicle,
            "line"
        )

    local stopIndex =
        lines.safeField(
            vehicle,
            "stopIndex"
        )

    local arrivalStationTerminal =
        lines.safeField(
            vehicle,
            "arrivalStationTerminal"
        )

    local arrivalStationTerminalLocked =
        lines.safeField(
            vehicle,
            "arrivalStationTerminalLocked"
        )

    local timeUntilLoad =
        lines.safeField(
            vehicle,
            "timeUntilLoad"
        )

    local timeUntilCloseDoors =
        lines.safeField(
            vehicle,
            "timeUntilCloseDoors"
        )

    local timeUntilDeparture =
        lines.safeField(
            vehicle,
            "timeUntilDeparture"
        )

    local daysAtTerminal =
        lines.safeField(
            vehicle,
            "daysAtTerminal"
        )

    local doorsOpen =
        lines.safeField(
            vehicle,
            "doorsOpen"
        )

    local autoDeparture =
        lines.safeField(
            vehicle,
            "autoDeparture"
        )

    local userStopped =
        lines.safeField(
            vehicle,
            "userStopped"
        )

    local noPath =
        lines.safeField(
            vehicle,
            "noPath"
        )

    local depot =
        lines.safeField(
            vehicle,
            "depot"
        )


    local routeStop = nil


    if routeMap ~= nil
        and stopIndex ~= nil
    then

        routeStop =
            routeMap[stopIndex]

    end


    local routeStopName =
        "UNKNOWN"

    local routeRole =
        "UNKNOWN"

    local stationGroup =
        nil


    if routeStop ~= nil then

        routeStopName =
            routeStop.name

        routeRole =
            routeStop.role

        stationGroup =
            routeStop.stationGroup

    end


    local parkServicing =
        routeRole == "PARK"
        and doorsOpen == true
        and timeUntilDeparture ~= nil
        and timeUntilDeparture > 0

    local parkBound =
        routeRole == "PARK"
        and not parkServicing


    return {

        id =
            vehicleId,

        valid =
            true,

        name =
            stations.getEntityName(
                vehicleId
            ),

        line =
            lineId,

        state =
            state,

        stateName =
            M.getStateName(
                state
            ),

        stopIndex =
            stopIndex,

        routeStopName =
            routeStopName,

        routeRole =
            routeRole,

        routeStationGroup =
            stationGroup,

        parkAssociated =
            routeRole == "PARK",

        parkServicing =
            parkServicing,

        parkBound =
            parkBound,

        arrivalStationTerminal =
            arrivalStationTerminal,

        arrivalStationTerminalLocked =
            arrivalStationTerminalLocked,

        timeUntilLoad =
            timeUntilLoad,

        timeUntilCloseDoors =
            timeUntilCloseDoors,

        timeUntilDeparture =
            timeUntilDeparture,

        daysAtTerminal =
            daysAtTerminal,

        doorsOpen =
            doorsOpen,

        autoDeparture =
            autoDeparture,

        userStopped =
            userStopped,

        noPath =
            noPath,

        depot =
            depot

    }

end


-- ============================================================
-- COPY LINE VEHICLE INFO
--
-- Required by route_injector.lua.
-- This does NOT control trucks.
-- ============================================================

function M.copyLineVehicleInfo(
    sourceLine,
    destinationLine
)

    local sourceVehicleInfo =
        lines.safeField(
            sourceLine,
            "vehicleInfo"
        )

    local destinationVehicleInfo =
        lines.safeField(
            destinationLine,
            "vehicleInfo"
        )


    if sourceVehicleInfo == nil
        or destinationVehicleInfo == nil
    then
        return
    end


    local defaultPrice =
        lines.safeField(
            sourceVehicleInfo,
            "defaultPrice"
        )


    if defaultPrice ~= nil then

        pcall(
            function()

                destinationVehicleInfo.defaultPrice =
                    defaultPrice

            end
        )

    end


    local sourceModes =
        lines.safeField(
            sourceVehicleInfo,
            "transportModes"
        )

    local destinationModes =
        lines.safeField(
            destinationVehicleInfo,
            "transportModes"
        )


    lines.copyNativeSequence(
        sourceModes,
        destinationModes
    )

end


-- ============================================================
-- ROAD/TRUCK LINE CLASSIFICATION
--
-- Classifies a line by the carrier of its currently-assigned
-- vehicles rather than by line/station NAME. game.interface.
-- getVehicles({ carrier = "ROAD" }) is a base-game filter proven
-- in shipped TF2 campaign mission scripts (e.g.
-- mods/urbangames_campaign_mission_01_1/res/scripts/part2.lua,
-- which calls game.interface.getVehicles({ carrier = "ROAD" })
-- and cross-references the returned entity IDs against
-- getEntity(id).line) but NOT YET independently confirmed against
-- a live test line in this mod the way demand.lua's
-- SIM_ENTITY_AT_TERMINAL scan was proven. Logged verbosely below
-- so the next EPOD-TD session capture can confirm real output.
--
-- Replaces the previous line.transportMode / line NAME
-- string-matching heuristic, which silently failed to classify
-- any truck line whose name did not contain "truck" or "cargo"
-- (transportMode, transportType, lineType and type all read nil
-- on real lines -- see EPOD-LOG.txt).
--
-- KNOWN LIMITATION: a line with zero currently-assigned vehicles
-- has no vehicle to check the carrier of, so it is reported
-- UNCLASSIFIED rather than guessed true or false. Whether an
-- empty line needs classifying at all is an open follow-up, not
-- solved here -- see DECISIONS.md Outstanding Unknowns.
-- ============================================================

local function buildRoadVehicleIdSet()

    local ok, roadVehicleIds = pcall(
        function()
            return game.interface.getVehicles({ carrier = "ROAD" })
        end
    )

    if not ok or roadVehicleIds == nil then
        log.info(
            "ROAD VEHICLE LOOKUP FAILED: "
                .. tostring(roadVehicleIds)
        )
        return {}
    end

    local roadSet = {}

    for _, vehicleId in ipairs(roadVehicleIds) do
        roadSet[vehicleId] = true
    end

    log.debug(
        "ROAD VEHICLE LOOKUP: "
            .. tostring(#roadVehicleIds)
            .. " road-carrier vehicles found game-wide."
    )

    return roadSet
end


-- classification.status is one of "ROAD", "NOT_ROAD", "UNCLASSIFIED".
function M.classifyLineCarrier(lineId, roadVehicleSet)
    local vehicleIds = M.getVehiclesForLine(lineId)

    if #vehicleIds == 0 then
        return {
            status = "UNCLASSIFIED",
            reason = "no-vehicles-assigned"
        }
    end

    for _, vehicleId in ipairs(vehicleIds) do
        if roadVehicleSet[vehicleId] then
            return {
                status = "ROAD",
                matchedVehicleId = vehicleId
            }
        end
    end

    return { status = "NOT_ROAD" }
end


-- ============================================================
-- MANAGED LINES FOR STATION
--
-- Read-only. Returns all road/truck lines whose stop list
-- includes the given stationGroup, along with their assigned
-- vehicle counts.
-- ============================================================

function M.getManagedLinesForStation(stationGroupId)
    local result = {}

    if stationGroupId == nil or stationGroupId < 0 then
        return result
    end

    local ok, allLineIds = pcall(
        function()
            return game.interface.getLines()
        end
    )

    if not ok or allLineIds == nil then
        return result
    end

    local roadVehicleSet = buildRoadVehicleIdSet()

    for _, lineId in ipairs(allLineIds) do
        local classification = M.classifyLineCarrier(lineId, roadVehicleSet)

        if classification.status == "UNCLASSIFIED" then
            log.debug(
                "Line " .. tostring(lineId)
                    .. " (" .. lines.getName(lineId) .. ")"
                    .. " has no assigned vehicles; carrier UNCLASSIFIED, not guessed."
            )
        end

        if classification.status == "ROAD" then
            local line = lines.get(lineId)
            local lineStops = line and lines.safeField(line, "stops") or nil
            local stopCount = lines.safeLength(lineStops)
            local includesStation = false

            for stopIndex = 1, stopCount do
                local stop = lineStops[stopIndex]
                if stop ~= nil then
                    local stopGroup = lines.safeField(stop, "stationGroup")
                    if stopGroup == stationGroupId then
                        includesStation = true
                        break
                    end
                end
            end

            if includesStation then
                local vehicleIds = M.getVehiclesForLine(lineId)
                local destinations = {}
                local seenDestinations = {}

                -- Previously excluded stopGroup == stationGroupId
                -- (the focused hub's own stop), on the assumption
                -- that a line only carries demand outward from the
                -- hub. Confirmed live that's wrong: demand.scan()
                -- already reports real waiting cargo destined back
                -- toward the hub (see demand.lua's buildDestinationMap
                -- generalization), but it never got a row here, so
                -- the hub's own return-direction demand was
                -- invisible unless the player switched focus to the
                -- other station. Included now.
                --
                -- The "(return)" text suffix that used to mark this
                -- case was dropped: the GUI now shows direction with
                -- a "->"/"<-" arrow prefix instead (comparing
                -- destination.stationGroup against the focused hub
                -- itself), so baking the same distinction into the
                -- name here would just be redundant with what the
                -- panel already renders.
                for stopIndex = 1, stopCount do
                    local stop = lineStops[stopIndex]
                    if stop ~= nil then
                        local stopGroup = lines.safeField(stop, "stationGroup")
                        local stopName = stations.getEntityName(stopGroup)
                        if stopGroup ~= nil
                            and stopName ~= config.PARK_NAME
                            and not seenDestinations[stopGroup]
                        then
                            seenDestinations[stopGroup] = true

                            destinations[#destinations + 1] = {
                                stationGroup = stopGroup,
                                name = stopName,
                            }
                        end
                    end
                end

                result[#result + 1] = {
                    id = lineId,
                    name = lines.getName(lineId),
                    vehicleCount = #vehicleIds,
                    vehicles = vehicleIds,
                    destinations = destinations,
                }
            end
        end
    end

    return result
end


-- ============================================================
-- ENTITY INFO DUMP (game.interface.getEntity)
--
-- Read-only, one level deep. game.interface.getEntity() already
-- returned useful plain Lua tables (not native userdata, so pairs()
-- works cleanly, unlike api.engine.getComponent's structures) for
-- LINE, STATION_GROUP, and STATION in the "Auto Line Namer"
-- workshop mod's bundled reference dump -- LINE's included
-- itemsTransported, a real per-cargo-type running total. Whether it
-- exposes anything about a VEHICLE's current onboard load has never
-- been checked in this codebase; TRANSPORT_VEHICLE's own component
-- fields (see general.lua's dump and vehicles.inspect() above) do
-- NOT include one. This exists to answer that directly instead of
-- assuming either way, ahead of building any "skip vehicles that
-- are currently loaded" reassignment logic.
-- ============================================================

function M.dumpEntityInfo(entityId, label)

    if entityId == nil then
        log.info(tostring(label) .. ": entityId is nil.")
        return nil
    end

    local ok, entity =
        pcall(game.interface.getEntity, entityId)

    if not ok or entity == nil then

        log.info(
            tostring(label)
                .. ": game.interface.getEntity("
                .. tostring(entityId)
                .. ") failed: "
                .. tostring(entity)
        )

        return nil

    end

    log.info("----------------------------------------")
    log.info(tostring(label) .. " (entity=" .. tostring(entityId) .. ")")
    log.info("----------------------------------------")

    local okIter, iterErr =
        pcall(function()

            for key, value in pairs(entity) do

                local valueType = type(value)

                if valueType == "table" then

                    local nested = {}

                    for nestedKey, nestedValue in pairs(value) do
                        nested[#nested + 1] =
                            tostring(nestedKey) .. "=" .. tostring(nestedValue)
                    end

                    log.info(
                        "  " .. tostring(key)
                            .. " = { " .. table.concat(nested, ", ") .. " }"
                    )

                else

                    log.info(
                        "  " .. tostring(key) .. " = " .. tostring(value)
                    )

                end

            end

        end)

    if not okIter then
        log.info("  <not enumerable: " .. tostring(iterErr) .. ">")
    end

    log.info("----------------------------------------")

    return entity

end


-- ============================================================
-- SIM CARGO SNAPSHOT FOR A LINE
--
-- api.engine.system.simCargoSystem.getSimCargosForLine(lineId) and
-- the SIM_CARGO component's `vehicleUsed` field: SIM_CARGO =
-- { cargoType, targetEntity, sourceEntity, speed, vehicleUsed,
-- startTime }. Both confirmed live -- the now-removed loaded-vehicle
-- reassignment test called this and logged real cargoType/
-- vehicleUsed values back. vehicleUsed = true is the closest
-- available signal for "this cargo entity is currently loaded onto
-- a vehicle" as opposed to sitting idle/waiting; there is no
-- per-vehicle cargo list exposed on TRANSPORT_VEHICLE itself, so
-- this is line-scoped, not vehicle-scoped -- only unambiguous when
-- exactly one vehicle is on the line being snapshotted (true for
-- most managed split lines in their steady state).
--
-- Kept even though nothing currently calls it: this is the best
-- available proxy for the still-pending "don't reassign a vehicle
-- that's currently carrying a load" check (requested live, not yet
-- built -- see the game.interface.getEntity(vehicleId) diagnostic
-- in epod_truck_distribution.lua's startup diagnostics, checking
-- whether TF2 exposes something more direct first).
-- ============================================================

function M.snapshotLineCargo(lineId)

    local result = {
        lineId = lineId,
        totalCargo = 0,
        onVehicleCargo = 0,
        entities = {}
    }

    if lineId == nil or lineId < 0 then
        return result
    end

    local ok, cargoIds =
        pcall(
            api.engine.system.simCargoSystem.getSimCargosForLine,
            lineId
        )

    if not ok or cargoIds == nil then

        log.info(
            "SNAPSHOT LINE CARGO FAILED for line "
                .. tostring(lineId)
                .. ": "
                .. tostring(cargoIds)
        )

        return result
    end

    for _, cargoId in ipairs(cargoIds) do

        local okComp, cargo =
            pcall(
                api.engine.getComponent,
                cargoId,
                api.type.ComponentType.SIM_CARGO
            )

        if okComp and cargo ~= nil then

            local cargoType =
                lines.safeField(cargo, "cargoType")

            local vehicleUsed =
                lines.safeField(cargo, "vehicleUsed")

            result.totalCargo =
                result.totalCargo + 1

            if vehicleUsed == true then
                result.onVehicleCargo =
                    result.onVehicleCargo + 1
            end

            result.entities[#result.entities + 1] = {
                id = cargoId,
                cargoType = cargoType,
                vehicleUsed = vehicleUsed
            }

        end

    end

    return result

end


function M.logCargoSnapshot(label, snapshot)

    log.info(
        label
            .. " | line=" .. tostring(snapshot.lineId)
            .. " | totalCargo=" .. tostring(snapshot.totalCargo)
            .. " | onVehicleCargo=" .. tostring(snapshot.onVehicleCargo)
    )

    for _, entry in ipairs(snapshot.entities) do

        log.info(
            "  cargo entity=" .. tostring(entry.id)
                .. " | cargoType=" .. tostring(entry.cargoType)
                .. " | vehicleUsed=" .. tostring(entry.vehicleUsed)
        )

    end

end


-- ============================================================
-- ONBOARD CARGO LOAD (per-vehicle, live-confirmed)
--
-- game.interface.getEntity(vehicleId) exposes a real `cargoLoad`
-- table -- e.g. { FOOD = 4 }, empty {} when carrying nothing --
-- confirmed live via route_injector.M.runLoadedVehicleJourneyTestStep
-- (see PROGRESS.md, DECISIONS.md). This was the missing mechanism
-- for the "don't reassign a vehicle that's currently carrying a
-- load" check requested live: previously there was no proven way to
-- read a specific vehicle's onboard cargo at all, only the
-- line-scoped SIM_CARGO/vehicleUsed proxy (snapshotLineCargo above),
-- which is ambiguous whenever more than one vehicle shares a line.
-- ============================================================

function M.getCargoLoad(vehicleId)

    if vehicleId == nil then
        return nil
    end

    local ok, entity =
        pcall(game.interface.getEntity, vehicleId)

    if not ok or entity == nil then
        return nil
    end

    return lines.safeField(entity, "cargoLoad")

end


-- Returns true (confirmed empty), false (confirmed carrying
-- something), or nil (could not be determined -- entity lookup
-- failed). Callers should treat nil the same as "loaded": if it
-- can't be confirmed empty, don't reassign it.
function M.isVehicleEmpty(vehicleId)

    local cargoLoad = M.getCargoLoad(vehicleId)

    if cargoLoad == nil then
        return nil
    end

    -- Decision 61 fix: this used to check next(cargoLoad) == nil --
    -- an empty TABLE -- but cargoLoad is a cargo-type -> amount map
    -- that can retain a key for a compatible cargo type at value 0
    -- even when nothing is actually loaded (same shape already
    -- accounted for by the Fleet Balance Report's sumLineCargo
    -- helper). That made a genuinely empty vehicle (confirmed 0/12
    -- in its own in-game panel) read as "still carrying" forever,
    -- permanently hiding it from Stage 3's spare-vehicle
    -- redistribution. Sum the actual amounts instead of counting
    -- keys.
    local ok, totalCarrying =
        pcall(function()

            local total = 0

            for _, amount in pairs(cargoLoad) do
                total = total + (amount or 0)
            end

            return total

        end)

    if not ok then
        return nil
    end

    return totalCarrying == 0

end


-- ============================================================
-- VEHICLE CARGO COMPATIBILITY (PROGRESS.md Not Started #4)
--
-- Distinct from cargoLoad/isVehicleEmpty above: those read what a
-- vehicle is CURRENTLY carrying (changes trip to trip). This reads
-- what a vehicle's model is FIXED to be able to carry at all --
-- allCapacities, confirmed real via game.interface.getEntity (see
-- PROGRESS.md/Done/Foundation) but not yet wrapped in a proper API
-- or tested across multiple vehicle types/eras until now. A hard
-- prerequisite for any future cross-line fleet reassignment: once a
-- hub's connected lines carry different cargo types, nothing can
-- safely decide "move this truck to that line" without first
-- knowing the truck can actually carry what that line needs.
-- ============================================================

function M.getAllCapacities(vehicleId)

    if vehicleId == nil then
        return nil
    end

    local ok, entity =
        pcall(game.interface.getEntity, vehicleId)

    if not ok or entity == nil then
        return nil
    end

    return lines.safeField(entity, "allCapacities")

end


-- Returns true/false/nil -- same nil-means-unconfirmed convention as
-- isVehicleEmpty above, so callers can treat nil the same as "not
-- confirmed compatible" rather than assuming safe.
function M.isCompatibleWithCargoType(vehicleId, cargoType)

    local allCapacities = M.getAllCapacities(vehicleId)

    if allCapacities == nil or cargoType == nil then
        return nil
    end

    local ok, capacity =
        pcall(function()
            return allCapacities[cargoType]
        end)

    if not ok then
        return nil
    end

    return capacity ~= nil and capacity > 0

end


-- Returns a simple list of cargo type names this vehicle's model can
-- carry (the keys of allCapacities), or nil if it could not be
-- determined. Convenience for logging/diagnostics -- most real
-- compatibility checks should use isCompatibleWithCargoType directly
-- against one known target type rather than building this list.
function M.getCompatibleCargoTypes(vehicleId)

    local allCapacities = M.getAllCapacities(vehicleId)

    if allCapacities == nil then
        return nil
    end

    local ok, result =
        pcall(function()

            local types = {}

            for cargoType, capacity in pairs(allCapacities) do

                if capacity ~= nil and capacity > 0 then
                    types[#types + 1] = cargoType
                end

            end

            return types

        end)

    if not ok then
        return nil
    end

    return result

end


-- ============================================================
-- LIVE SET-LINE COMMAND
--
-- Proven TF2 command path from earlier EPOD-TD testing.
-- ============================================================

function M.setLine(
    vehicleId,
    lineId,
    stopIndex,
    callback
)

    local okCommand,
        commandOrError =
            pcall(
                api.cmd.make.setLine,
                vehicleId,
                lineId,
                stopIndex
            )

    if not okCommand then

        log.info(
            "SET LINE COMMAND ERROR: "
                .. tostring(
                    commandOrError
                )
        )

        if callback ~= nil then
            callback(false)
        end

        return false
    end

    local command =
        commandOrError

    local okSend,
        sendError =
            pcall(
                function()

                    api.cmd.sendCommand(
                        command,

                        function(cmd, success)

                            log.info(
                                "SET LINE RESULT: "
                                    .. tostring(
                                        success
                                    )
                            )

                            if callback ~= nil then
                                callback(success)
                            end

                        end
                    )

                end
            )

    if not okSend then

        log.info(
            "SET LINE SEND ERROR: "
                .. tostring(
                    sendError
                )
        )

        if callback ~= nil then
            callback(false)
        end

        return false
    end

    return true

end


-- ============================================================
-- LIVE VEHICLE CONTROL HELPERS
--
-- Supported TF2 command wrappers for the live experiment.
-- ============================================================

function M.setManualDeparture(
    vehicleId,
    manual,
    callback
)

    local okCommand,
        commandOrError =
            pcall(
                api.cmd.make.setVehicleManualDeparture,
                vehicleId,
                manual
            )

    if not okCommand then

        log.info(
            "SET MANUAL DEPARTURE ERROR: "
                .. tostring(
                    commandOrError
                )
        )

        if callback ~= nil then
            callback(false)
        end

        return false
    end

    local command =
        commandOrError

    local okSend,
        sendError =
            pcall(
                function()

                    api.cmd.sendCommand(
                        command,

                        function(cmd, success)

                            log.info(
                                "SET MANUAL DEPARTURE RESULT: "
                                    .. tostring(
                                        success
                                    )
                            )

                            if callback ~= nil then
                                callback(success)
                            end

                        end
                    )

                end
            )

    if not okSend then

        log.info(
            "SET MANUAL DEPARTURE SEND ERROR: "
                .. tostring(
                    sendError
                )
        )

        if callback ~= nil then
            callback(false)
        end

        return false
    end

    return true

end


function M.reverseVehicle(
    vehicleId,
    callback
)

    local okCommand,
        commandOrError =
            pcall(
                api.cmd.make.reverseVehicle,
                vehicleId
            )

    if not okCommand then

        log.info(
            "REVERSE VEHICLE COMMAND ERROR: "
                .. tostring(
                    commandOrError
                )
        )

        if callback ~= nil then
            callback(false)
        end

        return false
    end

    local command =
        commandOrError

    local okSend,
        sendError =
            pcall(
                function()

                    api.cmd.sendCommand(
                        command,

                        function(cmd, success)

                            log.info(
                                "REVERSE VEHICLE RESULT: "
                                    .. tostring(
                                        success
                                    )
                            )

                            if callback ~= nil then
                                callback(success)
                            end

                        end
                    )

                end
            )

    if not okSend then

        log.info(
            "REVERSE VEHICLE SEND ERROR: "
                .. tostring(
                    sendError
                )
        )

        if callback ~= nil then
            callback(false)
        end

        return false
    end

    return true

end


return M