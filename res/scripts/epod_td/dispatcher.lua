local config = require("epod_td.config")
local demand = require("epod_td.demand")
local vehicles = require("epod_td.vehicles")
local lines = require("epod_td.lines")
local stations = require("epod_td.stations")
local log = require("epod_td.log")

local M = {}
local liveDispatchAttempted = false


local function restoreVehicleToOriginalState(
    vehicleId,
    managedLineId,
    originalStopIndex,
    parkResetLineId
)

    if vehicleId == nil
        or managedLineId == nil
    then

        log.info(
            "LIVE DISPATCH TEST ENDED"
        )

        log.info(
            "No vehicle or managed line available for restore."
        )

        return
    end

    local currentVehicle =
        vehicles.get(
            vehicleId
        )

    local currentLine =
        lines.safeField(
            currentVehicle,
            "line"
        )

    local currentStopIndex =
        lines.safeField(
            currentVehicle,
            "stopIndex"
        )

    log.info(
        "RESTORE TO ORIGINAL STATE"
    )

    log.info(
        "RESTORE CURRENT LINE: "
            .. tostring(
                currentLine
            )
    )

    log.info(
        "RESTORE EXPECTED STOP INDEX: "
            .. tostring(
                originalStopIndex
            )
    )

    log.info(
        "RESTORE ACTUAL STOP INDEX: "
            .. tostring(
                currentStopIndex
            )
    )

    local function releaseManualDeparture()
        vehicles.setManualDeparture(
            vehicleId,
            false,
            function(releaseSuccess)

                log.info(
                    "LIVE DISPATCH TEST ENDED"
                )

                log.info(
                    "Manual departure released: "
                        .. tostring(
                            releaseSuccess
                        )
                )

                log.info(
                    "Vehicle restore completed."
                )

            end
        )
    end

    local function restoreManagedLine(finalStopIndex)
        vehicles.setLine(
            vehicleId,
            managedLineId,
            finalStopIndex,
            function(restoreSuccess)

                local restoredVehicle =
                    vehicles.get(
                        vehicleId
                    )

                local restoredLine =
                    lines.safeField(
                        restoredVehicle,
                        "line"
                    )

                local restoredStopIndex =
                    lines.safeField(
                        restoredVehicle,
                        "stopIndex"
                    )

                log.info(
                    "RESTORE MANAGED LINE RESULT: "
                        .. tostring(
                            restoreSuccess
                        )
                )

                log.info(
                    "RESTORE EXPECTED STOP INDEX: "
                        .. tostring(
                            finalStopIndex
                        )
                )

                log.info(
                    "RESTORE ACTUAL STOP INDEX: "
                        .. tostring(
                            restoredStopIndex
                        )
                )

                if restoreSuccess then
                    releaseManualDeparture()
                    return
                end

                releaseManualDeparture()

            end
        )
    end

    if currentLine ~= managedLineId then

        log.info(
            "Vehicle currently off managed line; restoring directly."
        )

        restoreManagedLine(
            originalStopIndex
        )

        return
    end

    if parkResetLineId == nil then

        log.info(
            "RESTORE TEMP RESET RESULT: "
                .. tostring(false)
        )

        log.info(
            "No temporary reset line supplied for safe restore."
        )

        releaseManualDeparture()

        return
    end

    vehicles.setLine(
        vehicleId,
        parkResetLineId,
        0,
        function(resetSuccess)

            log.info(
                "RESTORE TEMP RESET RESULT: "
                    .. tostring(
                        resetSuccess
                    )
            )

            if not resetSuccess then

                releaseManualDeparture()

                return
            end

            restoreManagedLine(
                originalStopIndex
            )

        end
    )

end


-- ============================================================
-- RANK DESTINATIONS
-- ============================================================

function M.rank(currentDemand)

    local ranked = {}

    if currentDemand == nil
        or currentDemand.destinations == nil
    then
        return ranked
    end


    for _, destination
        in pairs(currentDemand.destinations)
    do

        ranked[#ranked + 1] = {

            name =
                destination.name,

            demand =
                destination.total or 0,

            stopIndex =
                destination.stopIndex,

            stationGroup =
                destination.stationGroup,

            cargoTypes =
                destination.cargoTypes or {}

        }

    end


    table.sort(
        ranked,

        function(a, b)

            if a.demand == b.demand then

                return
                    (a.stopIndex or 999999)
                    <
                    (b.stopIndex or 999999)

            end

            return a.demand > b.demand

        end
    )


    return ranked

end


-- ============================================================
-- NEXT DESTINATION
-- ============================================================

function M.getNextDestination(currentDemand)

    local ranked =
        M.rank(
            currentDemand
        )


    for _, destination
        in ipairs(ranked)
    do

        if destination.demand > 0 then
            return destination
        end

    end


    return nil

end


-- ============================================================
-- BUILD DRY-RUN DISPATCH PLAN
-- ============================================================

function M.buildDispatchPlan(
    currentDemand
)

    if currentDemand == nil then

        return {
            ready = false,
            reason = "no-demand-data"
        }

    end


    local lineId =
        currentDemand.lineId


    if lineId == nil then

        return {
            ready = false,
            reason = "no-line-id"
        }

    end


    local destination =
        M.getNextDestination(
            currentDemand
        )


    if destination == nil then

        return {
            ready = false,
            reason = "no-destination-demand",
            lineId = lineId
        }

    end


    local availableVehicles =
        vehicles.findAvailableAtPark(
            lineId
        )


    if #availableVehicles == 0 then

        return {
            ready = false,
            reason = "no-truck-available",
            lineId = lineId,
            destination = destination
        }

    end


    -- First available Park-servicing truck.
    --
    -- We can improve truck selection later when we inspect
    -- capacity/cargo and possibly waiting duration.

    local selectedVehicle =
        availableVehicles[1]


    return {

        ready =
            true,

        dryRun =
            true,

        lineId =
            lineId,

        destination =
            destination,

        vehicle =
            selectedVehicle,

        availableVehicleCount =
            #availableVehicles

    }

end


-- ============================================================
-- DESTINATION PRIORITY REPORT
-- ============================================================

function M.printReport(
    currentDemand
)

    if currentDemand == nil then

        currentDemand =
            demand.scan()

    end


    log.info(
        "----------------------------------------"
    )

    log.info(
        "DISPATCHER READ-ONLY TEST"
    )

    log.info(
        "NO VEHICLE CONTROL"
    )

    log.info(
        "----------------------------------------"
    )


    if currentDemand == nil then

        log.info(
            "No demand data returned."
        )

        return nil

    end


    if currentDemand.error ~= nil then

        log.info(
            "Cannot rank destinations: "
                .. tostring(
                    currentDemand.error
                )
        )

        return nil

    end


    local ranked =
        M.rank(
            currentDemand
        )


    local priority = 0


    for _, destination
        in ipairs(ranked)
    do

        if destination.demand > 0 then

            priority =
                priority + 1


            log.info(
                destination.name
                    .. " | demand="
                    .. tostring(
                        destination.demand
                    )
                    .. " | PRIORITY "
                    .. tostring(
                        priority
                    )
            )

        else

            log.info(
                destination.name
                    .. " | demand=0 | NO DISPATCH"
            )

        end

    end


    log.info(
        "----------------------------------------"
    )


    local nextDestination =
        M.getNextDestination(
            currentDemand
        )


    if nextDestination ~= nil then

        log.info(
            "NEXT DISPATCH:"
        )

        log.info(
            nextDestination.name
        )

        log.info(
            "Demand: "
                .. tostring(
                    nextDestination.demand
                )
        )

        log.info(
            "Route stop index: "
                .. tostring(
                    nextDestination.stopIndex
                )
        )

        log.info(
            "Station group: "
                .. tostring(
                    nextDestination.stationGroup
                )
        )

    else

        log.info(
            "NEXT DISPATCH: NONE"
        )

    end


    log.info(
        "----------------------------------------"
    )


    return nextDestination

end


-- ============================================================
-- DRY-RUN PLAN REPORT
-- ============================================================

function M.printDispatchPlan(
    currentDemand
)

    local plan =
        M.buildDispatchPlan(
            currentDemand
        )


    log.info(
        "----------------------------------------"
    )

    log.info(
        "EPOD-TD DISPATCH PLAN"
    )

    log.info(
        "DRY RUN - NO COMMAND WILL BE SENT"
    )

    log.info(
        "----------------------------------------"
    )


    if not plan.ready then

        log.info(
            "DISPATCH NOT READY"
        )

        log.info(
            "Reason: "
                .. tostring(
                    plan.reason
                )
        )


        if plan.destination ~= nil then

            log.info(
                "Wanted destination: "
                    .. tostring(
                        plan.destination.name
                    )
            )

            log.info(
                "Demand: "
                    .. tostring(
                        plan.destination.demand
                    )
            )

        end


        log.info(
            "----------------------------------------"
        )


        return plan

    end


    log.info(
        "DISPATCH READY"
    )

    log.info(
        "Available Park trucks: "
            .. tostring(
                plan.availableVehicleCount
            )
    )

    log.info(
        "----------------------------------------"
    )

    log.info(
        "TRUCK"
    )

    log.info(
        "Name: "
            .. tostring(
                plan.vehicle.name
            )
    )

    log.info(
        "Entity: "
            .. tostring(
                plan.vehicle.id
            )
    )

    log.info(
        "Park stopIndex: "
            .. tostring(
                plan.vehicle.stopIndex
            )
    )

    log.info(
        "Doors open: "
            .. tostring(
                plan.vehicle.doorsOpen
            )
    )

    log.info(
        "Departure timer: "
            .. tostring(
                plan.vehicle.timeUntilDeparture
            )
    )


    log.info(
        "----------------------------------------"
    )

    log.info(
        "DESTINATION"
    )

    log.info(
        "Name: "
            .. tostring(
                plan.destination.name
            )
    )

    log.info(
        "Demand: "
            .. tostring(
                plan.destination.demand
            )
    )

    log.info(
        "Destination stopIndex: "
            .. tostring(
                plan.destination.stopIndex
            )
    )

    log.info(
        "Station group: "
            .. tostring(
                plan.destination.stationGroup
            )
    )


    log.info(
        "----------------------------------------"
    )

    log.info(
        "PLANNED ACTION:"
    )

    log.info(
        tostring(
            plan.vehicle.name
        )
            .. " -> "
            .. tostring(
                plan.destination.name
            )
    )

    log.info(
        "*** DRY RUN - NO TF2 COMMAND SENT ***"
    )

    log.info(
        "----------------------------------------"
    )


    return plan

end


-- ============================================================
-- LIVE DISPATCH
--
-- Keep the truck on the managed line and only reset its stopIndex
-- to the correct Park entry for the selected destination.
-- ============================================================

function M.executeDispatchPlan(
    plan
)

    log.info(
        "----------------------------------------"
    )

    log.info(
        "REVERSE DESTINATION TEST"
    )

    log.info(
        "----------------------------------------"
    )

    if liveDispatchAttempted then

        log.info(
            "LIVE DISPATCH ABORTED"
        )

        log.info(
            "Single-test guard already triggered."
        )

        return false
    end

    if not config.LIVE_DISPATCH_ENABLED then

        log.info(
            "LIVE DISPATCH DISABLED"
        )

        return false
    end

    if plan == nil
        or not plan.ready
    then

        log.info(
            "NO READY DISPATCH PLAN"
        )

        return false
    end

    if plan.lineId == nil then

        log.info(
            "LIVE DISPATCH FAILED"
        )

        log.info(
            "Plan has no managed line ID."
        )

        return false
    end

    if plan.vehicle == nil
        or plan.vehicle.id == nil
    then

        log.info(
            "LIVE DISPATCH FAILED"
        )

        log.info(
            "No selected vehicle available."
        )

        return false
    end

    if plan.destination == nil then

        log.info(
            "LIVE DISPATCH FAILED"
        )

        log.info(
            "Dispatch plan has no destination."
        )

        return false
    end

    local vehicleId =
        plan.vehicle.id

    local vehicleBefore =
        vehicles.get(
            vehicleId
        )

    if vehicleBefore == nil then

        log.info(
            "LIVE DISPATCH FAILED"
        )

        log.info(
            "Selected vehicle could not be re-read."
        )

        return false
    end

    local routeMap =
        vehicles.buildRouteMap(
            plan.lineId
        )

    local beforeInspect =
        vehicles.inspect(
            vehicleId,
            routeMap
        )

    local selectedDestination =
        plan.destination

    local desiredStopIndex =
        selectedDestination.stopIndex

    local desiredDestinationName =
        selectedDestination.name

    local desiredStationGroup =
        selectedDestination.stationGroup

    liveDispatchAttempted = true

    log.info(
        "EXPECTED DISPATCH DESTINATION"
    )

    log.info(
        "destination name: "
            .. tostring(
                desiredDestinationName
            )
    )

    log.info(
        "destination stopIndex: "
            .. tostring(
                desiredStopIndex
            )
    )

    log.info(
        "destination stationGroup: "
            .. tostring(
                desiredStationGroup
            )
    )

    log.info(
        "BEFORE REVERSE"
    )

    log.info(
        "vehicle ID: "
            .. tostring(
                vehicleId
            )
    )

    log.info(
        "line: "
            .. tostring(
                lines.safeField(
                    vehicleBefore,
                    "line"
                )
            )
    )

    log.info(
        "stopIndex: "
            .. tostring(
                lines.safeField(
                    vehicleBefore,
                    "stopIndex"
                )
            )
    )

    log.info(
        "route stop name: "
            .. tostring(
                beforeInspect.routeStopName
            )
    )

    log.info(
        "arrivalStationTerminal: "
            .. tostring(
                lines.safeField(
                    vehicleBefore,
                    "arrivalStationTerminal"
                )
            )
    )

    log.info(
        "arrivalStationTerminalLocked: "
            .. tostring(
                lines.safeField(
                    vehicleBefore,
                    "arrivalStationTerminalLocked"
                )
            )
    )

    log.info(
        "doorsOpen: "
            .. tostring(
                lines.safeField(
                    vehicleBefore,
                    "doorsOpen"
                )
            )
    )

    log.info(
        "timeUntilDeparture: "
            .. tostring(
                lines.safeField(
                    vehicleBefore,
                    "timeUntilDeparture"
                )
            )
    )

    vehicles.setManualDeparture(
        vehicleId,
        true,
        function(holdSuccess)

            log.info(
                "STEP 1 - HOLD RESULT: "
                    .. tostring(
                        holdSuccess
                    )
            )

            if not holdSuccess then

                log.info(
                    "REVERSE DESTINATION TEST ABORTED"
                )

                log.info(
                    "Hold command failed."
                )

                return
            end

            vehicles.reverseVehicle(
                vehicleId,
                function(reverseSuccess)

                    log.info(
                        "REVERSE VEHICLE RESULT: "
                            .. tostring(
                                reverseSuccess
                            )
                    )

                    if not reverseSuccess then

                        log.info(
                            "REVERSE DESTINATION TEST FAILED"
                        )

                        log.info(
                            "Single reverse did not succeed."
                        )

                        vehicles.setManualDeparture(
                            vehicleId,
                            false,
                            function(releaseSuccess)
                                log.info(
                                    "STEP RELEASE RESULT: "
                                        .. tostring(
                                            releaseSuccess
                                        )
                                )
                            end
                        )

                        return
                    end

                    local afterVehicle =
                        vehicles.get(
                            vehicleId
                        )

                    local afterInspect =
                        vehicles.inspect(
                            vehicleId,
                            routeMap
                        )

                    local afterLine =
                        lines.safeField(
                            afterVehicle,
                            "line"
                        )

                    local afterStopIndex =
                        lines.safeField(
                            afterVehicle,
                            "stopIndex"
                        )

                    local afterRouteStopName =
                        afterInspect and afterInspect.routeStopName or "UNKNOWN"

                    local afterArrivalTerminal =
                        lines.safeField(
                            afterVehicle,
                            "arrivalStationTerminal"
                        )

                    local afterArrivalLocked =
                        lines.safeField(
                            afterVehicle,
                            "arrivalStationTerminalLocked"
                        )

                    log.info(
                        "AFTER ONE REVERSE"
                    )

                    log.info(
                        "line: "
                            .. tostring(
                                afterLine
                            )
                    )

                    log.info(
                        "stopIndex: "
                            .. tostring(
                                afterStopIndex
                            )
                    )

                    log.info(
                        "route stop name: "
                            .. tostring(
                                afterRouteStopName
                            )
                    )

                    log.info(
                        "arrivalStationTerminal: "
                            .. tostring(
                                afterArrivalTerminal
                            )
                    )

                    log.info(
                        "arrivalStationTerminalLocked: "
                            .. tostring(
                                afterArrivalLocked
                            )
                    )

                    local reverseMatchesDemand =
                        afterStopIndex ~= nil
                        and desiredStopIndex ~= nil
                        and afterStopIndex == desiredStopIndex

                    log.info(
                        "REVERSE DESTINATION TEST"
                    )

                    log.info(
                        "Desired destination: "
                            .. tostring(
                                desiredDestinationName
                            )
                    )

                    log.info(
                        "Desired stopIndex: "
                            .. tostring(
                                desiredStopIndex
                            )
                    )

                    log.info(
                        "Reverse produced stopIndex: "
                            .. tostring(
                                afterStopIndex
                            )
                    )

                    log.info(
                        "REVERSE MATCHES DEMAND DESTINATION: "
                            .. tostring(
                                reverseMatchesDemand
                            )
                    )

                    vehicles.setManualDeparture(
                        vehicleId,
                        false,
                        function(releaseSuccess)
                            log.info(
                                "STEP RELEASE RESULT: "
                                    .. tostring(
                                        releaseSuccess
                                    )
                            )

                            log.info(
                                "REVERSE DESTINATION TEST COMPLETE"
                            )

                            log.info(
                                "Truck released to continue toward TF2-selected stop."
                            )
                        end
                    )

                end
            )

        end
    )

    return true

end


-- ============================================================
-- FUTURE LIVE UPDATE
-- ============================================================

function M.update()

    local currentDemand =
        demand.scan()


    return M.buildDispatchPlan(
        currentDemand
    )

end


return M