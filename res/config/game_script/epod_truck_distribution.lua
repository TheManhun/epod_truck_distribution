local hasRunInspection = false
local updateCount = 0

local PREFIX = "[EPOD-TD]"
local TARGET_LINE_NAME = "Truck - CD - Hendon"

-- Change to true when we need the old noisy diagnostic information.
local DEBUG_VERBOSE = false


-- =========================================================
-- LOGGING
-- =========================================================

local function log(message)
    print(PREFIX .. " " .. tostring(message))
end


-- =========================================================
-- BASIC HELPERS
-- =========================================================

local function getEntityName(entityId)
    if entityId == nil or entityId < 0 then
        return "UNKNOWN"
    end

    local ok, name = pcall(
        game.interface.getName,
        entityId
    )

    if ok and name ~= nil and name ~= "" then
        return name
    end

    return "Entity " .. tostring(entityId)
end


local function getLineName(lineId)
    if lineId == nil or lineId < 0 then
        return "NO LINE"
    end

    return getEntityName(lineId)
end


local function findLineByName(lines, wantedName)
    for _, lineId in ipairs(lines) do
        if getLineName(lineId) == wantedName then
            return lineId
        end
    end

    return nil
end


local function stateName(state)
    local names = {
        [0] = "IN_DEPOT",
        [1] = "EN_ROUTE",
        [2] = "AT_TERMINAL",
        [3] = "GOING_TO_DEPOT"
    }

    return names[state] or tostring(state)
end


local function cargoTypeName(cargoType)
    if cargoType == nil then
        return "UNKNOWN"
    end

    local okId, cargoId = pcall(
        api.res.cargoTypeRep.getName,
        cargoType
    )

    if okId and cargoId ~= nil and cargoId ~= "" then
        local okCargo, cargoData = pcall(
            api.res.cargoTypeRep.get,
            cargoType
        )

        if okCargo
            and cargoData ~= nil
            and cargoData.name ~= nil
            and cargoData.name ~= ""
        then
            return tostring(cargoData.name)
        end

        return tostring(cargoId)
    end

    return "CargoType " .. tostring(cargoType)
end


-- =========================================================
-- ROUTE INSPECTION
-- =========================================================

local function getRouteInfo(lineId)
    local ok, lineComponent = pcall(
        api.engine.getComponent,
        lineId,
        api.type.ComponentType.LINE
    )

    if not ok or lineComponent == nil then
        return nil, "LINE component unavailable"
    end

    local stops = lineComponent.stops

    if stops == nil then
        return nil, "Line stops unavailable"
    end

    local route = {
        stops = {},
        stationCounts = {},
        hubStationGroup = nil,
        hubName = nil,
        destinations = {}
    }

    -- Read stops from TF2's userdata-backed vector.
    for index = 1, 100 do
        local okStop, stop = pcall(function()
            return stops[index]
        end)

        if not okStop or stop == nil then
            break
        end

        local stationGroupId = stop.stationGroup

        local entry = {
            lineStopIndex = index - 1,
            stationGroup = stationGroupId,
            stationName = getEntityName(stationGroupId),
            terminal = stop.terminal
        }

        table.insert(route.stops, entry)

        if stationGroupId ~= nil then
            route.stationCounts[stationGroupId] =
                (route.stationCounts[stationGroupId] or 0) + 1
        end
    end

    -- The hub should normally be the station group appearing most often.
    local highestCount = 0

    for stationGroupId, count in pairs(route.stationCounts) do
        if count > highestCount then
            highestCount = count
            route.hubStationGroup = stationGroupId
        end
    end

    if route.hubStationGroup ~= nil then
        route.hubName =
            getEntityName(route.hubStationGroup)
    else
        route.hubName = "UNKNOWN HUB"
    end

    -- Everything other than the repeated hub becomes a managed destination.
    for _, stop in ipairs(route.stops) do
        if stop.stationGroup ~= route.hubStationGroup then
            table.insert(route.destinations, {
                lineStopIndex = stop.lineStopIndex,
                stationGroup = stop.stationGroup,
                name = stop.stationName,
                terminal = stop.terminal
            })
        end
    end

    return route, nil
end


-- =========================================================
-- FLEET INSPECTION
-- =========================================================

local function getFleetSummary(lineId, allVehicles)
    local fleet = {
        total = 0,
        enRoute = 0,
        atTerminal = 0,
        inDepot = 0,
        goingToDepot = 0,
        vehicles = {}
    }

    for _, vehicleId in ipairs(allVehicles) do
        local ok, vehicle = pcall(
            api.engine.getComponent,
            vehicleId,
            api.type.ComponentType.TRANSPORT_VEHICLE
        )

        if ok
            and vehicle ~= nil
            and vehicle.carrier == 0
            and vehicle.line == lineId
        then
            fleet.total = fleet.total + 1

            if vehicle.state == 0 then
                fleet.inDepot = fleet.inDepot + 1
            elseif vehicle.state == 1 then
                fleet.enRoute = fleet.enRoute + 1
            elseif vehicle.state == 2 then
                fleet.atTerminal = fleet.atTerminal + 1
            elseif vehicle.state == 3 then
                fleet.goingToDepot = fleet.goingToDepot + 1
            end

            if DEBUG_VERBOSE then
                table.insert(fleet.vehicles, {
                    id = vehicleId,
                    state = vehicle.state,
                    stopIndex = vehicle.stopIndex,
                    daysAtTerminal = vehicle.daysAtTerminal
                })
            end
        end
    end

    return fleet
end


-- =========================================================
-- CARGO INSPECTION
-- =========================================================

local function getWaitingCargo(lineId, route)
    local result = {
        total = 0,
        byStop = {}
    }

    local cargoSystem =
        api.engine.system.simCargoSystem

    if cargoSystem == nil then
        return result, "simCargoSystem unavailable"
    end

    local okCargo, cargoEntities = pcall(
        cargoSystem.getSimCargosForLine,
        lineId
    )

    if not okCargo or cargoEntities == nil then
        return result, "Unable to read line cargo"
    end

    local lineComponent = api.engine.getComponent(
        lineId,
        api.type.ComponentType.LINE
    )

    if lineComponent == nil then
        return result, "LINE component unavailable"
    end

    local stops = lineComponent.stops

    -- Create destination records first so zero-demand stops appear too.
    for _, destination in ipairs(route.destinations) do
        result.byStop[destination.lineStopIndex] = {
            name = destination.name,
            total = 0,
            cargo = {}
        }
    end

    for _, cargoEntity in ipairs(cargoEntities) do
        local cargo = api.engine.getComponent(
            cargoEntity,
            api.type.ComponentType.SIM_CARGO
        )

        local terminalState = api.engine.getComponent(
            cargoEntity,
            api.type.ComponentType.SIM_ENTITY_AT_TERMINAL
        )

        if cargo ~= nil
            and terminalState ~= nil
            and terminalState.line == lineId
        then
            result.total = result.total + 1

            local destinationStop =
                terminalState.lineStop1

            local destination =
                result.byStop[destinationStop]

            -- Defensive fallback if TF2 reports an unexpected stop.
            if destination == nil then
                local okStop, stop = pcall(function()
                    return stops[destinationStop + 1]
                end)

                local destinationName =
                    "Stop " .. tostring(destinationStop)

                if okStop
                    and stop ~= nil
                    and stop.stationGroup ~= nil
                then
                    destinationName =
                        getEntityName(stop.stationGroup)
                end

                destination = {
                    name = destinationName,
                    total = 0,
                    cargo = {}
                }

                result.byStop[destinationStop] =
                    destination
            end

            destination.total =
                destination.total + 1

            local name =
                cargoTypeName(cargo.cargoType)

            destination.cargo[name] =
                (destination.cargo[name] or 0) + 1
        end
    end

    return result, nil
end


-- =========================================================
-- SUMMARY OUTPUT
-- =========================================================

local function printMonitor(
    lineId,
    route,
    fleet,
    waitingCargo
)
    log("========================================")
    log("TF2 Truck Distribution v0.0.8")
    log("READ-ONLY DISTRIBUTION MONITOR")
    log("========================================")

    log("Hub: " .. tostring(route.hubName))
    log(
        "Managed line: "
            .. getLineName(lineId)
    )

    log("----------------------------------------")
    log("FLEET")
    log("Total:          " .. tostring(fleet.total))
    log("En route:       " .. tostring(fleet.enRoute))
    log("At terminal:    " .. tostring(fleet.atTerminal))
    log("In depot:       " .. tostring(fleet.inDepot))
    log(
        "Going to depot: "
            .. tostring(fleet.goingToDepot)
    )

    log("----------------------------------------")
    log("DESTINATION QUEUES")

    -- Sort destinations by queue size, highest first.
    local destinations = {}

    for stopIndex, destination in pairs(waitingCargo.byStop) do
        table.insert(destinations, {
            stopIndex = stopIndex,
            name = destination.name,
            total = destination.total,
            cargo = destination.cargo
        })
    end

    table.sort(destinations, function(a, b)
        if a.total == b.total then
            return a.name < b.name
        end

        return a.total > b.total
    end)

    for _, destination in ipairs(destinations) do
        log(
            string.format(
                "%-24s %4d waiting",
                destination.name,
                destination.total
            )
        )

        if destination.total > 0 then
            local cargoNames = {}

            for cargoName, _ in pairs(destination.cargo) do
                table.insert(cargoNames, cargoName)
            end

            table.sort(cargoNames)

            for _, cargoName in ipairs(cargoNames) do
                log(
                    string.format(
                        "  %-22s %4d",
                        cargoName,
                        destination.cargo[cargoName]
                    )
                )
            end
        end
    end

    log("----------------------------------------")
    log(
        "TOTAL WAITING: "
            .. tostring(waitingCargo.total)
    )

    -- Useful future dispatcher hint, but still observational only.
    if waitingCargo.total == 0 then
        log(
            "Status: No cargo currently waiting."
        )
    else
        log(
            "Status: Cargo demand detected."
        )
    end

    if DEBUG_VERBOSE then
        log("----------------------------------------")
        log("DEBUG VEHICLES")

        for _, vehicle in ipairs(fleet.vehicles) do
            log(
                "Vehicle "
                    .. tostring(vehicle.id)
                    .. " | "
                    .. stateName(vehicle.state)
                    .. " | stop="
                    .. tostring(vehicle.stopIndex)
                    .. " | terminalDays="
                    .. tostring(vehicle.daysAtTerminal)
            )
        end

        log("----------------------------------------")
        log("DEBUG ROUTE")

        for _, stop in ipairs(route.stops) do
            log(
                string.format(
                    "Stop %02d | %s | group=%s | terminal=%s",
                    stop.lineStopIndex,
                    stop.stationName,
                    tostring(stop.stationGroup),
                    tostring(stop.terminal)
                )
            )
        end
    end

    log("========================================")
end


-- =========================================================
-- MAIN INSPECTION
-- =========================================================

local function inspectGame()
    local vehicles =
        game.interface.getVehicles()

    local lines =
        game.interface.getLines()

    local targetLineId =
        findLineByName(
            lines,
            TARGET_LINE_NAME
        )

    if targetLineId == nil then
        log(
            "ERROR: Target line not found: "
                .. TARGET_LINE_NAME
        )

        return
    end

    local route, routeError =
        getRouteInfo(targetLineId)

    if route == nil then
        log(
            "ERROR: "
                .. tostring(routeError)
        )

        return
    end

    local fleet =
        getFleetSummary(
            targetLineId,
            vehicles
        )

    local waitingCargo, cargoError =
        getWaitingCargo(
            targetLineId,
            route
        )

    if cargoError ~= nil then
        log(
            "WARNING: "
                .. tostring(cargoError)
        )
    end

    printMonitor(
        targetLineId,
        route,
        fleet,
        waitingCargo
    )
end


-- =========================================================
-- GAME SCRIPT
-- =========================================================

local function update()
    if hasRunInspection then
        return
    end

    updateCount = updateCount + 1

    -- Give the simulation a few update cycles after loading.
    if updateCount < 10 then
        return
    end

    hasRunInspection = true

    local ok, err =
        pcall(inspectGame)

    if not ok then
        log(
            "MONITOR ERROR: "
                .. tostring(err)
        )
    end
end


function data()
    return {
        update = update,
    }
end