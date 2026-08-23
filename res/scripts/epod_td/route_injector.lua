local config = require("epod_td.config")
local log = require("epod_td.log")
local lines = require("epod_td.lines")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local managed_registry = require("epod_td.managed_registry")

local M = {}


-- ============================================================
-- TWO-PARK SETLINE PROOF OF CONCEPT
-- ============================================================

local function buildTwoParkTestRoute()
    local parkAName = "EPOD-TD Truck Park"
    local parkBName = "EPOD-TD Truck Park B"
    local hendonName = "Hendon East"
    local queensName = "Queens Road"
    local alexanderName = "Alexander Road"

    -- findStopByNameAnywhere returns (line, stop, lineId); only
    -- the stop (2nd value) is wanted here. Same latent bug found
    -- and fixed in buildCreateLineTestRoute below -- this function
    -- isn't currently called from anywhere live, so it hadn't
    -- surfaced yet.
    local _, parkAStop = stations.findStopByNameAnywhere(parkAName)
    local _, parkBStop = stations.findStopByNameAnywhere(parkBName)
    local _, hendonStop = stations.findStopByNameAnywhere(hendonName)
    local _, queensStop = stations.findStopByNameAnywhere(queensName)
    local _, alexanderStop = stations.findStopByNameAnywhere(alexanderName)

    if parkAStop == nil or parkBStop == nil or hendonStop == nil or queensStop == nil or alexanderStop == nil then
        return nil, "Missing one or more required route stops for the two-park proof test."
    end

    local newLine = api.type.Line.new()
    if newLine == nil then
        return nil, "api.type.Line.new() returned nil for the two-park test route."
    end

    local newStops = lines.safeField(newLine, "stops")
    if newStops == nil then
        return nil, "New native Line has no stops container for the two-park test route."
    end

    local stopCopies = {
        parkAStop,
        hendonStop,
        queensStop,
        parkBStop,
        hendonStop,
        alexanderStop
    }

    for _, sourceStop in ipairs(stopCopies) do
        local nativeStop = lines.makeNativeStopCopy(sourceStop)
        local ok, err = lines.appendNativeStop(newStops, nativeStop)

        if not ok then
            return nil, "Failed appending temporary stop: " .. tostring(err)
        end
    end

    return newLine, nil
end


function M.runTwoParkSetLineTest(vehicleId)
    local distinct, discovered = stations.logTwoParkDiscovery()

    if not distinct then
        log.info("TWO PARK SETLINE TEST ABORTED")
        log.info("PARKS PHYSICALLY DISTINCT: false")
        log.info("No test route or setLine command was executed.")
        return false
    end

    local testLineName = "EPOD-TD TEST - TWO PARKS"
    local testLineId = lines.findByName(testLineName)

    if testLineId == nil then
        log.info("Temporary route not found: " .. testLineName)
        log.info("The test route must exist before this setLine proof can run.")
        return false
    end

    local tempRoute, routeError = buildTwoParkTestRoute()
    if tempRoute == nil then
        log.info("TEMP TEST ROUTE BUILD FAILED")
        log.info(tostring(routeError))
        return false
    end

    local tempStops = lines.safeField(tempRoute, "stops")
    local tempCount = lines.safeLength(tempStops)

    log.info("--------------------------------------------------")
    log.info("TEST ROUTE")
    log.info("--------------------------------------------------")
    log.info("Name: " .. testLineName)
    log.info("Temp test route stop count: " .. tostring(tempCount))

    for index = 0, tempCount - 1 do
        local stop = tempStops[index + 1]
        local stationGroup = lines.safeField(stop, "stationGroup")
        local entityName = stations.getEntityName(stationGroup)
        log.info("stopIndex " .. tostring(index) .. " = " .. tostring(entityName))
    end

    local stop0Group = lines.safeField(tempStops[1], "stationGroup")
    local stop3Group = lines.safeField(tempStops[4], "stationGroup")
    log.info("stopIndex 0 stationGroup: " .. tostring(stop0Group))
    log.info("stopIndex 3 stationGroup: " .. tostring(stop3Group))
    log.info("STOP 0 / STOP 3 DISTINCT: " .. tostring(stop0Group ~= stop3Group))

    local vehicle = vehicles.get(vehicleId)
    if vehicle == nil then
        log.info("Vehicle not found for test: " .. tostring(vehicleId))
        return false
    end

    local currentLine = lines.safeField(vehicle, "line")
    local currentStopIndex = lines.safeField(vehicle, "stopIndex")
    local currentStation = stations.getEntityName(lines.safeField(vehicle, "station"))

    log.info("BEFORE SETLINE TEST")
    log.info("vehicle: " .. tostring(vehicleId))
    log.info("line: " .. tostring(currentLine))
    log.info("stopIndex: " .. tostring(currentStopIndex))
    log.info("current physical station: " .. tostring(currentStation))
    log.info("target stop name: EPOD-TD Truck Park B")

    vehicles.setManualDeparture(vehicleId, true, function(holdSuccess)
        log.info("HOLD RESULT: " .. tostring(holdSuccess))

        if not holdSuccess then
            log.info("Two-park test aborted because manual departure hold failed.")
            return
        end

        vehicles.setLine(vehicleId, testLineId, 3, function(result)
            local updatedVehicle = vehicles.get(vehicleId)
            local actualLine = updatedVehicle and lines.safeField(updatedVehicle, "line") or nil
            local actualStopIndex = updatedVehicle and lines.safeField(updatedVehicle, "stopIndex") or nil

            log.info("SAME-LINE DISTINCT-PARK SETLINE TEST")
            log.info("Command result: " .. tostring(result))
            log.info("Expected line: " .. tostring(testLineId))
            log.info("Actual line: " .. tostring(actualLine))
            log.info("Requested stopIndex: 3")
            log.info("Actual stopIndex: " .. tostring(actualStopIndex))
            log.info("Requested target: EPOD-TD Truck Park B")
            log.info("SETLINE STOP INDEX MATCH: " .. tostring(actualStopIndex == 3))

            vehicles.setManualDeparture(vehicleId, false, function(releaseSuccess)
                log.info("RELEASE RESULT: " .. tostring(releaseSuccess))
                log.info("Truck released after same-line distinct-park test; no reverseVehicle or restore command was issued.")
            end)
        end)
    end)

    return true
end


-- ============================================================
-- PRINT COMPLETE ROUTE
-- ============================================================

local function printRoute(title, line)
    log.info("----------------------------------------")
    log.info(title)

    if line == nil then
        log.info("LINE IS NIL")
        log.info("----------------------------------------")
        return
    end

    local stops =
        lines.safeField(line, "stops")

    if stops == nil then
        log.info("NO STOP CONTAINER")
        log.info("----------------------------------------")
        return
    end

    local count =
        lines.safeLength(stops)

    log.info(
        "Stops found: "
            .. tostring(count)
    )

    for index = 1, count do
        local stop = stops[index]

        if stop ~= nil then
            local stationGroup =
                lines.safeField(
                    stop,
                    "stationGroup"
                )

            local station =
                lines.safeField(
                    stop,
                    "station"
                )

            local terminal =
                lines.safeField(
                    stop,
                    "terminal"
                )

            log.info(
                string.format(
                    "%02d | %-30s | group=%s | station=%s | terminal=%s",
                    index - 1,
                    stations.getEntityName(
                        stationGroup
                    ),
                    tostring(
                        stationGroup
                    ),
                    tostring(
                        station
                    ),
                    tostring(
                        terminal
                    )
                )
            )
        end
    end

    log.info("----------------------------------------")
end


-- ============================================================
-- FIND PARK REFERENCE STOP
-- ============================================================

local function findParkReferenceStop()
    local referenceLineId =
        lines.findByName(
            config.PARK_REFERENCE_LINE_NAME
        )

    if referenceLineId == nil then
        return nil,
            nil,
            "Reference line not found: "
                .. config.PARK_REFERENCE_LINE_NAME
    end

    local line =
        lines.get(referenceLineId)

    if line == nil then
        return nil,
            nil,
            "Could not read Park reference line."
    end

    local parkStop =
        stations.findStopByName(
            line,
            config.PARK_NAME
        )

    if parkStop == nil then
        return nil,
            referenceLineId,
            "Could not find "
                .. config.PARK_NAME
                .. " on reference line."
    end

    return parkStop,
        referenceLineId,
        nil
end


-- ============================================================
-- CHECK WHETHER ROUTE IS ALREADY INJECTED
-- ============================================================

local function routeAlreadyInjected(
    line,
    hubStationGroup,
    parkStationGroup
)
    local stops =
        lines.safeField(line, "stops")

    if stops == nil then
        return false
    end

    local count =
        lines.safeLength(stops)

    if count == 0 then
        return false
    end

    local hubCount = 0
    local injectedHubCount = 0

    for index = 1, count do
        local stop = stops[index]

        local stationGroup =
            lines.safeField(
                stop,
                "stationGroup"
            )

        if stationGroup
            == hubStationGroup
        then
            hubCount =
                hubCount + 1

            local previousIndex =
                index - 1

            -- TF2 lines are circular.
            if previousIndex < 1 then
                previousIndex = count
            end

            local previousStop =
                stops[previousIndex]

            local previousGroup =
                lines.safeField(
                    previousStop,
                    "stationGroup"
                )

            if previousGroup
                == parkStationGroup
            then
                injectedHubCount =
                    injectedHubCount + 1
            end
        end
    end

    return hubCount > 0
        and hubCount == injectedHubCount
end


-- ============================================================
-- BUILD NEW NATIVE TF2 LINE
-- ============================================================

local function buildInjectedNativeLine(
    sourceLine,
    hubStationGroup,
    parkReferenceStop
)
    local newLine =
        api.type.Line.new()

    if newLine == nil then
        return nil,
            0,
            "api.type.Line.new() returned nil."
    end

    local destinationStops =
        lines.safeField(
            newLine,
            "stops"
        )

    if destinationStops == nil then
        return nil,
            0,
            "New native Line has no stops container."
    end

    local sourceStops =
        lines.safeField(
            sourceLine,
            "stops"
        )

    if sourceStops == nil then
        return nil,
            0,
            "Source line has no stops."
    end


    -- Preserve deprecated waitingTime where supported.
    local waitingTime =
        lines.safeField(
            sourceLine,
            "waitingTime"
        )

    if waitingTime ~= nil then
        pcall(
            function()
                newLine.waitingTime =
                    waitingTime
            end
        )
    end


    vehicles.copyLineVehicleInfo(
        sourceLine,
        newLine
    )


    local sourceCount =
        lines.safeLength(sourceStops)

    local insertedParks = 0


    for index = 1, sourceCount do
        local sourceStop =
            sourceStops[index]

        if sourceStop == nil then
            return nil,
                insertedParks,
                "Source stop "
                    .. tostring(index)
                    .. " is nil."
        end


        local stationGroup =
            lines.safeField(
                sourceStop,
                "stationGroup"
            )


        -- Insert Truck Park immediately before
        -- every hub occurrence.
        if stationGroup
            == hubStationGroup
        then
            local nativeParkStop =
                lines.makeNativeStopCopy(
                    parkReferenceStop
                )

            local ok, err =
                lines.appendNativeStop(
                    destinationStops,
                    nativeParkStop
                )

            if not ok then
                return nil,
                    insertedParks,
                    "Failed appending Park stop: "
                        .. tostring(err)
            end

            insertedParks =
                insertedParks + 1
        end


        -- Preserve original stop.
        local nativeOriginalStop =
            lines.makeNativeStopCopy(
                sourceStop
            )

        local ok, err =
            lines.appendNativeStop(
                destinationStops,
                nativeOriginalStop
            )

        if not ok then
            return nil,
                insertedParks,
                "Failed appending original stop "
                    .. tostring(index)
                    .. ": "
                    .. tostring(err)
        end
    end


    return newLine,
        insertedParks,
        nil
end


-- ============================================================
-- VERIFY UPDATED ROUTE
-- ============================================================

local function verifyUpdatedRoute(
    lineId,
    hubStationGroup,
    parkStationGroup,
    expectedStopCount
)
    local updatedLine =
        lines.get(lineId)

    if updatedLine == nil then
        log.info(
            "VERIFY ERROR: Unable to reread line."
        )

        return false
    end


    printRoute(
        "ACTUAL ROUTE AFTER UPDATE",
        updatedLine
    )


    local actualStops =
        lines.safeField(
            updatedLine,
            "stops"
        )

    local actualCount =
        lines.safeLength(actualStops)


    log.info(
        "Expected stop count: "
            .. tostring(expectedStopCount)
    )

    log.info(
        "Actual stop count:   "
            .. tostring(actualCount)
    )


    local injectionCorrect =
        routeAlreadyInjected(
            updatedLine,
            hubStationGroup,
            parkStationGroup
        )


    if actualCount == expectedStopCount
        and injectionCorrect
    then
        log.info(
            "========================================"
        )

        log.info(
            "PARK INJECTION SUCCESS"
        )

        log.info(
            "Existing line entity preserved."
        )

        log.info(
            "Every "
                .. config.HUB_NAME
                .. " now has Truck Park immediately before it."
        )

        log.info(
            "NO TRUCK CONTROL WAS PERFORMED."
        )

        log.info(
            "========================================"
        )

        return true
    end


    log.info(
        "========================================"
    )

    log.info(
        "VERIFICATION FAILED"
    )

    log.info(
        "The command reported success but the resulting route was not as expected."
    )

    log.info(
        "========================================"
    )

    return false
end


-- ============================================================
-- PUBLIC ROUTE INJECTION ENTRY
-- ============================================================

function M.run()
    log.info(
        "----------------------------------------"
    )

    log.info(
        "ROUTE INJECTOR START"
    )


    -- ========================================================
    -- FIND SOURCE LINE
    -- ========================================================

    local sourceLineId =
        lines.findByName(
            config.SOURCE_LINE_NAME
        )


    if sourceLineId == nil then
        log.info(
            "FAILED: Could not find line: "
                .. config.SOURCE_LINE_NAME
        )

        return {
            success = false,
            reason = "source-line-not-found"
        }
    end


    log.info(
        "Source line: "
            .. config.SOURCE_LINE_NAME
    )

    log.info(
        "Source line entity: "
            .. tostring(sourceLineId)
    )


    -- ========================================================
    -- READ SOURCE LINE
    -- ========================================================

    local sourceLine =
        lines.get(sourceLineId)


    if sourceLine == nil then
        log.info(
            "FAILED: Unable to read native LINE."
        )

        return {
            success = false,
            reason = "source-line-unreadable"
        }
    end


    log.info(
        "Native line type: "
            .. type(sourceLine)
    )


    printRoute(
        "ORIGINAL COMPLETE ROUTE",
        sourceLine
    )


    local sourceStops =
        lines.safeField(
            sourceLine,
            "stops"
        )

    local originalStopCount =
        lines.safeLength(sourceStops)


    if originalStopCount == 0 then
        log.info(
            "FAILED: Source route has no stops."
        )

        return {
            success = false,
            reason = "source-line-empty"
        }
    end


    -- ========================================================
    -- FIND HUB
    -- ========================================================

    local hubStationGroup,
        hubOccurrences =
            stations.findStationGroupOnLine(
                sourceLine,
                config.HUB_NAME
            )


    if hubStationGroup == nil
        or hubOccurrences == 0
    then
        log.info(
            "FAILED: "
                .. config.HUB_NAME
                .. " was not found on source line."
        )

        return {
            success = false,
            reason = "hub-not-found"
        }
    end


    log.info(
        "Hub: "
            .. config.HUB_NAME
    )

    log.info(
        "Hub stationGroup: "
            .. tostring(hubStationGroup)
    )

    log.info(
        "Hub occurrences: "
            .. tostring(hubOccurrences)
    )


    -- ========================================================
    -- FIND PARK REFERENCE
    -- ========================================================

    local parkReferenceStop,
        parkReferenceLineId,
        parkError =
            findParkReferenceStop()


    if parkReferenceStop == nil then
        log.info(
            "FAILED: "
                .. tostring(parkError)
        )

        return {
            success = false,
            reason = "park-not-found"
        }
    end


    local parkStationGroup =
        lines.safeField(
            parkReferenceStop,
            "stationGroup"
        )


    log.info(
        "Park: "
            .. config.PARK_NAME
    )

    log.info(
        "Park stationGroup: "
            .. tostring(parkStationGroup)
    )

    log.info(
        "Park reference line: "
            .. tostring(parkReferenceLineId)
    )


    -- ========================================================
    -- DOUBLE-INJECTION PROTECTION
    -- ========================================================

    if routeAlreadyInjected(
        sourceLine,
        hubStationGroup,
        parkStationGroup
    )
    then
        log.info(
            "----------------------------------------"
        )

        log.info(
            "ROUTE ALREADY INJECTED."
        )

        log.info(
            "Every "
                .. config.HUB_NAME
                .. " already has Truck Park before it."
        )

        log.info(
            "NO UPDATE SENT."
        )

        log.info(
            "----------------------------------------"
        )

        return {
            success = true,
            alreadyInjected = true,
            lineId = sourceLineId
        }
    end


    -- ========================================================
    -- BUILD NATIVE LINE
    -- ========================================================

    log.info(
        "----------------------------------------"
    )

    log.info(
        "BUILDING NATIVE TF2 LINE"
    )

    log.info(
        "api.type.Line.new = "
            .. tostring(
                api.type.Line.new
            )
    )

    log.info(
        "api.type.Line.Stop.new = "
            .. tostring(
                api.type.Line.Stop.new
            )
    )


    local newLine,
        parksInserted,
        buildError =
            buildInjectedNativeLine(
                sourceLine,
                hubStationGroup,
                parkReferenceStop
            )


    if newLine == nil then
        log.info(
            "FAILED BUILDING NATIVE LINE: "
                .. tostring(buildError)
        )

        return {
            success = false,
            reason = "native-line-build-failed"
        }
    end


    log.info(
        "Native line created."
    )

    log.info(
        "type(newLine) = "
            .. type(newLine)
    )


    local newStops =
        lines.safeField(
            newLine,
            "stops"
        )

    local newStopCount =
        lines.safeLength(newStops)


    log.info(
        "Park stops inserted: "
            .. tostring(parksInserted)
    )

    log.info(
        "Original stop count: "
            .. tostring(originalStopCount)
    )

    log.info(
        "New stop count: "
            .. tostring(newStopCount)
    )


    -- ========================================================
    -- SANITY CHECK
    -- ========================================================

    local expectedStopCount =
        originalStopCount
            + hubOccurrences


    if parksInserted
        ~= hubOccurrences
    then
        log.info(
            "FAILED SANITY CHECK: Expected "
                .. tostring(hubOccurrences)
                .. " Park insertions but created "
                .. tostring(parksInserted)
        )

        return {
            success = false,
            reason = "park-count-mismatch"
        }
    end


    if newStopCount
        ~= expectedStopCount
    then
        log.info(
            "FAILED SANITY CHECK: Expected "
                .. tostring(expectedStopCount)
                .. " total stops but native Line contains "
                .. tostring(newStopCount)
        )

        return {
            success = false,
            reason = "stop-count-mismatch"
        }
    end


    printRoute(
        "NEW NATIVE ROUTE TO BE WRITTEN",
        newLine
    )


    -- ========================================================
    -- CREATE updateLine COMMAND
    -- ========================================================

    log.info(
        "----------------------------------------"
    )

    log.info(
        "READY TO WRITE"
    )

    log.info(
        "Existing line entity: "
            .. tostring(sourceLineId)
    )

    log.info(
        "This line entity will NOT be deleted."
    )

    log.info(
        "Old stops: "
            .. tostring(originalStopCount)
    )

    log.info(
        "New stops: "
            .. tostring(newStopCount)
    )

    log.info(
        "Creating updateLine command..."
    )


    local commandOk,
        commandOrError =
            pcall(
                api.cmd.make.updateLine,
                sourceLineId,
                newLine
            )


    if not commandOk then
        log.info(
            "UPDATE LINE COMMAND CREATION ERROR: "
                .. tostring(commandOrError)
        )

        return {
            success = false,
            reason = "update-command-create-failed"
        }
    end


    local command =
        commandOrError


    log.info(
        "updateLine command created."
    )

    log.info(
        "Sending updateLine command..."
    )


    -- ========================================================
    -- SEND WRITE COMMAND
    -- ========================================================

    local sendOk,
        sendError =
            pcall(
                function()
                    api.cmd.sendCommand(
                        command,

                        function(cmd, success)
                            log.info(
                                "----------------------------------------"
                            )

                            log.info(
                                "UPDATE LINE CALLBACK"
                            )

                            log.info(
                                "Success: "
                                    .. tostring(success)
                            )


                            if not success then
                                log.info(
                                    "TF2 REJECTED THE ROUTE UPDATE."
                                )

                                log.info(
                                    "No truck-control commands were sent."
                                )

                                return
                            end


                            log.info(
                                "TF2 accepted the line update."
                            )

                            log.info(
                                "Rereading existing line entity..."
                            )


                            verifyUpdatedRoute(
                                sourceLineId,
                                hubStationGroup,
                                parkStationGroup,
                                expectedStopCount
                            )
                        end
                    )
                end
            )


    if not sendOk then
        log.info(
            "SEND COMMAND ERROR: "
                .. tostring(sendError)
        )

        return {
            success = false,
            reason = "send-command-failed"
        }
    end


    log.info(
        "Command sent."
    )

    log.info(
        "Waiting for TF2 callback..."
    )


    return {
        success = true,
        pending = true,
        lineId = sourceLineId
    }
end


-- Alias retained because this was the original modular name.
function M.injectParkStops()
    return M.run()
end


-- ============================================================
-- CREATE LINE PROOF OF CONCEPT
--
-- Tests api.cmd.make.createLine(name, color, playerEntity, line).
-- Documented (found in the "Auto Line Namer" workshop mod's
-- bundled TF2 API reference, tf2-api/docs/modules/api.cmd.md) but
-- NOT yet live-proven in this game version -- this is the single
-- highest-stakes capability this mod has ever attempted (rewriting
-- the player's actual line network), so this test is deliberately
-- boxed in:
--
--   - builds a throwaway 2-stop line reusing two stops that
--     already exist (the hub and Queens Road) rather than
--     inventing anything new,
--   - never assigns any vehicle to it,
--   - never touches "Truck - CD - Hendon" or "Grain" at all,
--   - refuses to even start if api.cmd.make.deleteLine is not
--     also available, since creating something we could not
--     clean up would be worse than not testing at all,
--   - verifies the new line actually exists (found by name) and
--     has the expected stop count before declaring success,
--   - then deletes it and verifies it is actually gone by name
--     afterward.
-- ============================================================

local CREATE_LINE_TEST_NAME =
    "EPOD-TD TEST - Create Line"


local function buildCreateLineTestRoute()

    -- findStopByNameAnywhere returns (line, stop, lineId) --
    -- confirmed live that grabbing only the first value silently
    -- captures the LINE, not the stop, which crashes deeper inside
    -- makeNativeStopCopy the moment it tries to read
    -- stationGroup/station/terminal off something that isn't
    -- actually a stop.
    local _, hubStop =
        stations.findStopByNameAnywhere(
            config.HUB_NAME
        )

    local _, queensStop =
        stations.findStopByNameAnywhere(
            "Queens Road"
        )

    if hubStop == nil
        or queensStop == nil
    then
        return nil,
            "Missing required stops for the create-line test route."
    end

    local newLine =
        api.type.Line.new()

    if newLine == nil then
        return nil,
            "api.type.Line.new() returned nil for the create-line test."
    end

    local newStops =
        lines.safeField(
            newLine,
            "stops"
        )

    if newStops == nil then
        return nil,
            "New native Line has no stops container."
    end

    for _, sourceStop
        in ipairs({ hubStop, queensStop })
    do

        local nativeStop =
            lines.makeNativeStopCopy(
                sourceStop
            )

        local ok, err =
            lines.appendNativeStop(
                newStops,
                nativeStop
            )

        if not ok then
            return nil,
                "Failed appending test stop: "
                    .. tostring(err)
        end

    end

    return newLine, nil
end


function M.runCreateLineTest()
    log.info(
        "----------------------------------------"
    )

    log.info(
        "CREATE LINE PROOF OF CONCEPT"
    )

    log.info(
        "----------------------------------------"
    )


    if lines.findByName(CREATE_LINE_TEST_NAME) ~= nil then

        log.info(
            "FAILED: A line named '"
                .. CREATE_LINE_TEST_NAME
                .. "' already exists. Delete or rename it "
                .. "before running this test again."
        )

        return {
            success = false,
            reason = "test-line-name-collision"
        }

    end


    if api.cmd.make.createLine == nil then

        log.info(
            "FAILED: api.cmd.make.createLine is not available "
                .. "in this game version."
        )

        return {
            success = false,
            reason = "create-line-unavailable"
        }

    end


    if api.cmd.make.deleteLine == nil then

        log.info(
            "FAILED: api.cmd.make.deleteLine is not available -- "
                .. "refusing to create a test line we could not "
                .. "clean up afterward."
        )

        return {
            success = false,
            reason = "delete-line-unavailable"
        }

    end


    local testRoute, routeError =
        buildCreateLineTestRoute()

    if testRoute == nil then

        log.info(
            "FAILED BUILDING TEST ROUTE: "
                .. tostring(routeError)
        )

        return {
            success = false,
            reason = "test-route-build-failed"
        }

    end


    local okPlayer, playerEntity =
        pcall(
            api.engine.util.getPlayer
        )

    if not okPlayer or playerEntity == nil then

        log.info(
            "FAILED: api.engine.util.getPlayer() did not return "
                .. "a usable player entity: "
                .. tostring(playerEntity)
        )

        return {
            success = false,
            reason = "player-entity-unavailable"
        }

    end


    log.info(
        "Player entity: "
            .. tostring(playerEntity)
    )

    log.info(
        "Test line name: "
            .. CREATE_LINE_TEST_NAME
    )


    local okColor, color =
        pcall(
            api.type.Vec3f.new,
            1.0, 0.5, 0.0
        )

    if not okColor or color == nil then

        log.info(
            "FAILED: api.type.Vec3f.new() failed: "
                .. tostring(color)
        )

        return {
            success = false,
            reason = "color-build-failed"
        }

    end


    local okCommand, commandOrError =
        pcall(
            api.cmd.make.createLine,
            CREATE_LINE_TEST_NAME,
            color,
            playerEntity,
            testRoute
        )

    if not okCommand then

        log.info(
            "CREATE LINE COMMAND CREATION ERROR: "
                .. tostring(commandOrError)
        )

        return {
            success = false,
            reason = "create-command-create-failed"
        }

    end


    log.info(
        "createLine command created. Sending..."
    )


    local sendOk, sendErr =
        pcall(
            function()

                api.cmd.sendCommand(
                    commandOrError,

                    function(cmd, success)

                        log.info(
                            "----------------------------------------"
                        )

                        log.info(
                            "CREATE LINE CALLBACK"
                        )

                        log.info(
                            "Success: "
                                .. tostring(success)
                        )


                        if not success then

                            log.info(
                                "TF2 REJECTED THE CREATE LINE COMMAND."
                            )

                            return

                        end


                        local newLineId =
                            lines.findByName(
                                CREATE_LINE_TEST_NAME
                            )

                        log.info(
                            "Line found by name after creation: "
                                .. tostring(newLineId)
                        )


                        if newLineId == nil then

                            log.info(
                                "VERIFICATION FAILED: createLine "
                                    .. "reported success but no line "
                                    .. "with that name was found."
                            )

                            return

                        end


                        local createdLine =
                            lines.get(newLineId)

                        printRoute(
                            "CREATED TEST LINE",
                            createdLine
                        )

                        local createdStops =
                            lines.safeField(
                                createdLine,
                                "stops"
                            )

                        local createdCount =
                            lines.safeLength(
                                createdStops
                            )

                        log.info(
                            "Expected stop count: 2"
                        )

                        log.info(
                            "Actual stop count: "
                                .. tostring(createdCount)
                        )

                        log.info(
                            "CREATE LINE VERIFIED: "
                                .. tostring(createdCount == 2)
                        )


                        log.info(
                            "----------------------------------------"
                        )

                        log.info(
                            "CLEANING UP: deleting test line "
                                .. tostring(newLineId)
                        )


                        local okDeleteCmd, deleteCommandOrError =
                            pcall(
                                api.cmd.make.deleteLine,
                                newLineId
                            )

                        if not okDeleteCmd then

                            log.info(
                                "DELETE LINE COMMAND CREATION ERROR: "
                                    .. tostring(deleteCommandOrError)
                            )

                            return

                        end


                        local okDeleteSend, deleteSendErr =
                            pcall(
                                function()

                                    api.cmd.sendCommand(
                                        deleteCommandOrError,

                                        function(deleteCmd, deleteSuccess)

                                            log.info(
                                                "DELETE LINE RESULT: "
                                                    .. tostring(deleteSuccess)
                                            )

                                            local stillExists =
                                                lines.findByName(
                                                    CREATE_LINE_TEST_NAME
                                                )

                                            log.info(
                                                "Test line still findable "
                                                    .. "by name after delete: "
                                                    .. tostring(stillExists)
                                            )

                                            log.info(
                                                "CLEANUP VERIFIED: "
                                                    .. tostring(
                                                        stillExists == nil
                                                    )
                                            )

                                            log.info(
                                                "----------------------------------------"
                                            )

                                        end
                                    )

                                end
                            )

                        if not okDeleteSend then

                            log.info(
                                "DELETE LINE SEND ERROR: "
                                    .. tostring(deleteSendErr)
                            )

                        end

                    end
                )

            end
        )


    if not sendOk then

        log.info(
            "CREATE LINE SEND ERROR: "
                .. tostring(sendErr)
        )

        return {
            success = false,
            reason = "send-command-failed"
        }

    end


    log.info(
        "Command sent. Waiting for TF2 callback..."
    )


    return {
        success = true,
        pending = true
    }
end


-- ============================================================
-- LINE NAMING GLYPH TEST -- FINDING SETTLED, TEST REMOVED
--
-- This used to be a live createLine test comparing five candidate
-- symbols in a real line name. The finding is settled and baked
-- into line_splitter.lua's naming convention: ● and ↔ render
-- correctly in TF2's font; ◆, ■, and ► come back as tofu boxes (see
-- TECHNICAL_RESEARCH.md). With nothing left to compare, the test
-- function itself was removed rather than kept as dead code -- only
-- the cleanup below remains, to delete whatever the test left
-- behind in older sessions.
--
-- Literal UTF-8 characters in the source, not \xHH escapes: \xHH
-- hex escapes are not supported in vanilla Lua 5.1 (only \ddd
-- decimal escapes are), and there is no need to guess which Lua
-- version TF2 embeds when the literal bytes work identically
-- either way -- the source file is just bytes, and Lua treats a
-- string literal as an opaque byte sequence regardless of version.
-- ============================================================

local GLYPH_TEST_NAME =
    "EPOD-TD GLYPH TEST -- ◆ ■ ● ► ↔ [TD] Hendon East - Queens Road"


-- ============================================================
-- CLEAN UP THE GLYPH TEST LINE
--
-- Deletes ONLY the exact GLYPH_TEST_NAME line via the already-proven
-- deleteLine command (route_injector's original create/delete test),
-- same as line_splitter.deleteEmptySourceLine's safety posture: does
-- nothing if a line with that exact name isn't found, never touches
-- anything else.
-- ============================================================

function M.cleanupLineNamingGlyphTest()

    local existingLineId =
        lines.findByName(GLYPH_TEST_NAME)

    if existingLineId == nil then
        return { success = true, alreadyClean = true }
    end

    log.info("----------------------------------------")
    log.info("CLEANING UP GLYPH TEST LINE")
    log.info("----------------------------------------")

    local okCommand, commandOrError =
        pcall(api.cmd.make.deleteLine, existingLineId)

    if not okCommand then

        log.info(
            "DELETE LINE COMMAND ERROR: "
                .. tostring(commandOrError)
        )

        return {
            success = false,
            reason = "delete-command-failed"
        }

    end

    local okSend, sendErr =
        pcall(function()

            api.cmd.sendCommand(commandOrError, function(cmd, success)

                log.info(
                    "GLYPH TEST LINE DELETE RESULT: "
                        .. tostring(success)
                )

            end)

        end)

    if not okSend then

        log.info(
            "DELETE LINE SEND ERROR: "
                .. tostring(sendErr)
        )

        return {
            success = false,
            reason = "send-failed"
        }

    end

    return { success = true, pending = true }

end


-- ============================================================
-- LOADED VEHICLE JOURNEY TEST (two clicks: start, then check)
--
-- Answers the still-open safety question properly this time: does
-- cargo a vehicle is already carrying survive api.cmd.make.setLine
-- reassignment through to actual delivery -- not just "does the
-- immediate stop-field value change" (already proven elsewhere) or
-- "does a line-level cargo count stay roughly the same" (the first,
-- flawed attempt at this test, run against a 50-vehicle line and
-- rightly called out as inconclusive). Follows the exact chain
-- requested live:
--
--   cargo before -> setLine -> first hub arrival -> cargo loaded? ->
--   departure -> eventual delivery
--
-- Also incidentally answers the OTHER open Partial item for free:
-- Decision 12's Truck Park workaround is not wired into Stage 2's
-- assignVehiclesAndRetireStops (a bare setLine, no intervening real
-- stop arrival) -- watching this same vehicle's first pickup at its
-- new destination directly shows whether that known bug is actually
-- triggered by this exact scenario.
--
-- Split into two clicks because there is no sleep/wait primitive in
-- this codebase: the first click picks a real, currently-loaded
-- vehicle and reassigns it exactly the way Stage 2 does; the second
-- (run again after playing for a few real minutes) reports on that
-- same vehicle's current state so the player's own observed time
-- gap stands in for a wait.
--
-- Only ever picks a single-vehicle managed ("● ") line as the
-- source, so vehicles.snapshotLineCargo's line-scoped count is an
-- unambiguous per-vehicle read, not the ambiguous multi-vehicle case
-- that undermined the first attempt at this test.
-- ============================================================

local journeyWatch = nil


-- Prefers a single-vehicle line for the cleanest possible cargo
-- attribution (vehicles.snapshotLineCargo is line-scoped, so with
-- exactly one vehicle on the line it is also unambiguously
-- per-vehicle). Confirmed live this preference cannot always be met
-- any more: once Stage 3 (fleet_allocator.redistributeSpareVehiclesByDemand)
-- has run, every managed line ends up with more than one vehicle,
-- proportional to its demand, so a strict "exactly 1" requirement
-- found nothing across four separate attempts on the test save.
-- Falls back to the line with the FEWEST vehicles that still shows
-- onboard cargo, and reports that count honestly (isAmbiguous) so
-- the caller can flag the same ambiguity warning the original
-- (now-removed) loaded-vehicle test used, rather than silently
-- treating a multi-vehicle read as if it were clean.
local function findLoadedSingleVehicleLine()

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then
        return nil
    end

    local best = nil

    for _, lineId in ipairs(allLineIds) do

        local name = lines.getName(lineId)

        if managed_registry.isManaged(lineId) then

            local vehicleIds = vehicles.getVehiclesForLine(lineId)

            if #vehicleIds > 0 then

                local cargoSnapshot = vehicles.snapshotLineCargo(lineId)

                if cargoSnapshot.onVehicleCargo > 0 then

                    if best == nil or #vehicleIds < best.vehicleCount then

                        best = {
                            lineId = lineId,
                            lineName = name,
                            vehicleId = vehicleIds[1],
                            vehicleCount = #vehicleIds
                        }

                    end

                    if #vehicleIds == 1 then
                        break
                    end

                end

            end

        end

    end

    if best == nil then
        return nil
    end

    return {
        lineId = best.lineId,
        lineName = best.lineName,
        vehicleId = best.vehicleId,
        isAmbiguous = best.vehicleCount > 1,
        vehicleCount = best.vehicleCount
    }

end


-- Prefers a genuinely empty line, same reasoning as
-- findLoadedSingleVehicleLine above: an empty destination makes the
-- AFTER cargo snapshot unambiguously attributable to the watched
-- vehicle alone. Confirmed live this preference cannot always be
-- met either, for the identical reason as the source side: once
-- Stage 3 has redistributed the fleet, every real managed line ends
-- up with at least one vehicle, so a strict "== 0" requirement found
-- nothing. Falls back to the OTHER line with the fewest vehicles,
-- reporting that count honestly (isAmbiguous) rather than pretending
-- the fallback is as clean as a genuinely empty line would have been.
local function findEmptyDestinationLine(excludeLineId)

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then
        return nil
    end

    local best = nil

    for _, lineId in ipairs(allLineIds) do

        if lineId ~= excludeLineId then

            local name = lines.getName(lineId)

            if managed_registry.isManaged(lineId) then

                local vehicleIds = vehicles.getVehiclesForLine(lineId)
                local vehicleCount = #vehicleIds

                if best == nil or vehicleCount < best.vehicleCount then

                    best = {
                        lineId = lineId,
                        lineName = name,
                        vehicleCount = vehicleCount
                    }

                end

                if vehicleCount == 0 then
                    break
                end

            end

        end

    end

    if best == nil then
        return nil
    end

    return {
        lineId = best.lineId,
        lineName = best.lineName,
        isAmbiguous = best.vehicleCount > 0,
        vehicleCount = best.vehicleCount
    }

end


function M.startLoadedVehicleJourneyTest(onComplete)

    log.info("----------------------------------------")
    log.info("LOADED VEHICLE JOURNEY TEST -- START")
    log.info("----------------------------------------")

    if journeyWatch ~= nil then

        log.info(
            "A journey test is already in progress for vehicle "
                .. tostring(journeyWatch.vehicleId)
                .. ". Run the check step instead, or reload the "
                .. "save to abandon it."
        )

        if onComplete ~= nil then
            onComplete(false, "already-watching")
        end

        return { success = false, reason = "already-watching" }

    end


    local source = findLoadedSingleVehicleLine()

    if source == nil then

        log.info(
            "FAILED: no managed (\"● \") line with confirmed onboard "
                .. "cargo was found right now. Try again in a moment "
                .. "-- this needs a real vehicle that's actually "
                .. "carrying something."
        )

        if onComplete ~= nil then
            onComplete(false, "no-loaded-vehicle-found")
        end

        return { success = false, reason = "no-loaded-vehicle-found" }

    end


    local destination = findEmptyDestinationLine(source.lineId)

    if destination == nil then

        log.info(
            "FAILED: no other managed (\"● \") line found to use as "
                .. "the destination."
        )

        if onComplete ~= nil then
            onComplete(false, "no-destination-found")
        end

        return { success = false, reason = "no-destination-found" }

    end


    log.info(
        "Source: " .. tostring(source.lineName)
            .. " (id=" .. tostring(source.lineId) .. ")"
            .. " | vehicles on this line=" .. tostring(source.vehicleCount)
    )

    log.info(
        "Vehicle: " .. tostring(source.vehicleId)
    )

    if source.isAmbiguous then

        log.info(
            "WARNING: "
                .. tostring(source.vehicleCount)
                .. " vehicles share this source line, not just the "
                .. "one being watched. The BEFORE/AFTER cargo counts "
                .. "below are still line-scoped, so they can shift "
                .. "because of what the OTHER vehicles on this line "
                .. "are doing, not just the watched vehicle. Treat "
                .. "the line-level numbers as a weaker signal here "
                .. "and lean on vehicles.dumpEntityInfo's per-vehicle "
                .. "read and the in-game LINE STATISTICS panel "
                .. "instead."
        )

    end

    log.info(
        "Destination: " .. tostring(destination.lineName)
            .. " (id=" .. tostring(destination.lineId) .. ")"
            .. " | vehicles on this line before="
            .. tostring(destination.vehicleCount)
    )

    if destination.isAmbiguous then

        log.info(
            "WARNING: the destination line already has "
                .. tostring(destination.vehicleCount)
                .. " other vehicle(s) on it. The AFTER cargo count "
                .. "on this line will include their cargo too, not "
                .. "just the watched vehicle's -- lean on "
                .. "vehicles.dumpEntityInfo's per-vehicle read and "
                .. "the in-game LINE STATISTICS panel for the real "
                .. "signal here, same as the source-side warning."
        )

    end


    local beforeInspect = vehicles.inspect(source.vehicleId)

    log.info("BEFORE")

    log.info(
        "state=" .. tostring(beforeInspect.stateName)
            .. " | line=" .. tostring(beforeInspect.line)
            .. " | stopIndex=" .. tostring(beforeInspect.stopIndex)
            .. " | doorsOpen=" .. tostring(beforeInspect.doorsOpen)
    )

    vehicles.dumpEntityInfo(
        source.vehicleId,
        "VEHICLE ENTITY BEFORE REASSIGNMENT"
    )

    local sourceCargoBefore = vehicles.snapshotLineCargo(source.lineId)

    vehicles.logCargoSnapshot("SOURCE LINE BEFORE", sourceCargoBefore)

    local destinationCargoBefore = vehicles.snapshotLineCargo(destination.lineId)

    vehicles.logCargoSnapshot("DESTINATION LINE BEFORE", destinationCargoBefore)


    journeyWatch = {
        vehicleId = source.vehicleId,
        sourceLineId = source.lineId,
        sourceLineName = source.lineName,
        sourceIsAmbiguous = source.isAmbiguous,
        sourceVehicleCount = source.vehicleCount,
        destinationLineId = destination.lineId,
        destinationLineName = destination.lineName,
        destinationIsAmbiguous = destination.isAmbiguous,
        destinationVehicleCountBefore = destination.vehicleCount,
        beforeOnVehicleCargo = sourceCargoBefore.onVehicleCargo,
        destinationOnVehicleCargoBefore = destinationCargoBefore.onVehicleCargo
    }


    vehicles.setManualDeparture(source.vehicleId, true, function(holdSuccess)

        log.info("HOLD RESULT: " .. tostring(holdSuccess))

        if not holdSuccess then

            log.info(
                "TEST ABORTED: could not hold vehicle before reassignment."
            )

            journeyWatch = nil

            if onComplete ~= nil then
                onComplete(false, "hold-failed")
            end

            return

        end


        vehicles.setLine(source.vehicleId, destination.lineId, 0, function(setLineSuccess)

            log.info("SETLINE RESULT: " .. tostring(setLineSuccess))

            vehicles.setManualDeparture(source.vehicleId, false, function(releaseSuccess)

                log.info("RELEASE RESULT: " .. tostring(releaseSuccess))

                if not setLineSuccess then

                    log.info("TEST ABORTED: setLine was rejected.")

                    journeyWatch = nil

                    if onComplete ~= nil then
                        onComplete(false, "setline-rejected")
                    end

                    return

                end


                local afterInspect = vehicles.inspect(source.vehicleId)

                log.info("IMMEDIATELY AFTER")

                log.info(
                    "state=" .. tostring(afterInspect.stateName)
                        .. " | line=" .. tostring(afterInspect.line)
                        .. " | stopIndex=" .. tostring(afterInspect.stopIndex)
                        .. " | doorsOpen=" .. tostring(afterInspect.doorsOpen)
                )

                log.info(
                    "LINE ACTUALLY CHANGED: "
                        .. tostring(afterInspect.line == destination.lineId)
                )

                log.info("----------------------------------------")

                log.info(
                    "Vehicle "
                        .. tostring(source.vehicleId)
                        .. " is now being watched. Let the game run "
                        .. "for a few real minutes -- long enough for "
                        .. "it to reach "
                        .. tostring(destination.lineName)
                        .. ", unload, and depart again -- then click "
                        .. "this button a second time to check on it."
                )

                log.info("----------------------------------------")

                if onComplete ~= nil then
                    onComplete(true, "watching")
                end

            end)

        end)

    end)

    return { success = true, pending = true }

end


function M.checkLoadedVehicleJourneyTest(onComplete)

    log.info("----------------------------------------")
    log.info("LOADED VEHICLE JOURNEY TEST -- CHECK")
    log.info("----------------------------------------")

    if journeyWatch == nil then

        log.info(
            "No journey test is currently in progress. Run the "
                .. "start step first."
        )

        if onComplete ~= nil then
            onComplete(false, "not-watching")
        end

        return { success = false, reason = "not-watching" }

    end


    local watch = journeyWatch

    log.info(
        "Vehicle: " .. tostring(watch.vehicleId)
    )

    log.info(
        "Source line: " .. tostring(watch.sourceLineName)
            .. " (id=" .. tostring(watch.sourceLineId) .. ")"
    )

    log.info(
        "Destination line: " .. tostring(watch.destinationLineName)
            .. " (id=" .. tostring(watch.destinationLineId) .. ")"
    )


    local nowInspect = vehicles.inspect(watch.vehicleId)

    if not nowInspect.valid then

        log.info(
            "FAILED: vehicle "
                .. tostring(watch.vehicleId)
                .. " could no longer be read (sold? despawned?)."
        )

        journeyWatch = nil

        if onComplete ~= nil then
            onComplete(false, "vehicle-unreadable")
        end

        return { success = false, reason = "vehicle-unreadable" }

    end

    log.info("NOW")

    log.info(
        "state=" .. tostring(nowInspect.stateName)
            .. " | line=" .. tostring(nowInspect.line)
            .. " | stopIndex=" .. tostring(nowInspect.stopIndex)
            .. " | doorsOpen=" .. tostring(nowInspect.doorsOpen)
    )

    log.info(
        "STILL ON DESTINATION LINE: "
            .. tostring(nowInspect.line == watch.destinationLineId)
    )

    vehicles.dumpEntityInfo(
        watch.vehicleId,
        "VEHICLE ENTITY NOW"
    )

    local destinationCargoNow =
        vehicles.snapshotLineCargo(watch.destinationLineId)

    vehicles.logCargoSnapshot("DESTINATION LINE NOW", destinationCargoNow)

    log.info("========================================")
    log.info("VERDICT")
    log.info("========================================")

    log.info(
        "Onboard cargo on source line before: "
            .. tostring(watch.beforeOnVehicleCargo)
            .. (
                watch.sourceIsAmbiguous
                    and (
                        " (AMBIGUOUS -- "
                            .. tostring(watch.sourceVehicleCount)
                            .. " vehicles shared that line, this is "
                            .. "not attributable to the watched "
                            .. "vehicle alone)"
                    )
                    or " (clean: this was the only vehicle on that line)"
            )
    )

    log.info(
        "Onboard cargo on destination line before: "
            .. tostring(watch.destinationOnVehicleCargoBefore)
            .. " (" .. tostring(watch.destinationVehicleCountBefore)
            .. " other vehicle(s) already there)"
    )

    log.info(
        "Onboard cargo on destination line now: "
            .. tostring(destinationCargoNow.onVehicleCargo)
            .. (
                watch.destinationIsAmbiguous
                    and (
                        " (AMBIGUOUS -- shared with "
                            .. tostring(watch.destinationVehicleCountBefore)
                            .. " other vehicle(s), not attributable to "
                            .. "the watched vehicle alone; compare "
                            .. "against the BEFORE value above rather "
                            .. "than treating this as a clean absolute "
                            .. "number)"
                    )
                    or " (clean: the destination line started empty, "
                        .. "so this is attributable to the watched "
                        .. "vehicle alone)"
            )
    )

    log.info(
        "NOTE: this is still just an entity-count snapshot, not "
            .. "proof of delivery. The real confirmation is visual: "
            .. "check the game's own LINE STATISTICS panel for "
            .. tostring(watch.destinationLineName)
            .. " -- a real cargo rate/balance there (not just "
            .. "0/0 or --) means this vehicle actually delivered "
            .. "something after reassignment, not just carried it "
            .. "for a moment. Also worth checking directly: has the "
            .. "vehicle's state cycled through AT_TERMINAL and back "
            .. "to EN_ROUTE at least once since the reassignment "
            .. "(a completed stop, not just travel)?"
    )

    log.info("========================================")

    journeyWatch = nil

    if onComplete ~= nil then
        onComplete(true, "checked")
    end

    return { success = true }

end


-- Single entry point for a button that doesn't know (and shouldn't
-- need to know) which step comes next -- journeyWatch is private to
-- this module.
function M.runLoadedVehicleJourneyTestStep(onComplete)

    if journeyWatch == nil then
        return M.startLoadedVehicleJourneyTest(onComplete)
    end

    return M.checkLoadedVehicleJourneyTest(onComplete)

end


-- ============================================================
-- BUG B TEST -- DOES A BARE setLine PICK UP CARGO AT THE NEW
-- DESTINATION? (Decision 12's Park-stop problem, PROGRESS.md)
--
-- Different question from the journey test above (that one is Bug A
-- -- does an ALREADY-LOADED vehicle keep/lose its existing cargo).
-- This one starts from a CONFIRMED-EMPTY vehicle (mirroring exactly
-- what line_splitter.assignOneVehicleThenRetireStop actually does in
-- real play -- see line_splitter.lua:665-769) and asks: after a bare
-- setLine with no injectParkStops workaround, does it ever pick up
-- ANY cargo at its new destination's first stop?
--
-- This test is cleaner than the journey test above in one respect:
-- since vehicles.getCargoLoad/isVehicleEmpty reads the WATCHED
-- VEHICLE's own onboard cargo directly, other vehicles sharing the
-- destination line don't create ambiguity here the way they did for
-- the line-scoped snapshotLineCargo reads above -- "is THIS vehicle
-- now carrying anything" is a clean, per-vehicle answer regardless
-- of what else is on that line.
-- ============================================================

local bugBWatch = nil


local function findEmptyVehicleOnManagedLine()

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then
        return nil
    end

    for _, lineId in ipairs(allLineIds) do

        local name = lines.getName(lineId)

        if managed_registry.isManaged(lineId) then

            local vehicleIds = vehicles.getVehiclesForLine(lineId)

            for _, vehicleId in ipairs(vehicleIds) do

                if vehicles.isVehicleEmpty(vehicleId) == true then

                    return {
                        lineId = lineId,
                        lineName = name,
                        vehicleId = vehicleId
                    }

                end

            end

        end

    end

    return nil

end


-- LIVE-CONFIRMED BUG IN THE FIRST VERSION: originally used
-- vehicles.snapshotLineCargo (api.engine.system.simCargoSystem.
-- getSimCargosForLine) to measure "waiting" as totalCargo minus
-- onVehicleCargo. Live testing showed every managed line's snapshot
-- always had totalCargo == onVehicleCargo EXACTLY -- 7/7, 220/220,
-- 35/35, 19/19 across four very differently-sized lines, always a
-- zero difference. That's not "demand happens to be low" (a
-- coincidence that specific four times would be absurd) -- it means
-- getSimCargosForLine only returns cargo already associated with a
-- vehicle serving that line, never cargo genuinely waiting at a
-- stop for pickup. This matches an existing note elsewhere in this
-- project's own history: the old pre-redesign loaded-vehicle test
-- found this same metric barely moved and flagged it as an
-- unreliable per-vehicle signal for exactly this reason.
--
-- The correct mechanism, already proven and used elsewhere in this
-- codebase (fleet_allocator.lua's findManagedSplitLines): demand.scan
-- (lineId, hubStationGroupId), which walks cargo entities game-wide
-- via SIM_ENTITY_AT_TERMINAL and matches on stationGroup -- the same
-- source that powers the panel's own demand numbers. It needs to be
-- told which of the line's two stops is the hub; findSharedStationGroup
-- below finds that by intersecting the candidate line's stops against
-- the SOURCE line's stops (every managed line in this mod shares
-- exactly one stop -- the hub).
local function getLineStationGroups(lineId)

    local line = lines.get(lineId)

    if line == nil then
        return {}
    end

    local stops = lines.safeField(line, "stops")
    local count = lines.safeLength(stops)
    local result = {}

    for index = 1, count do

        local stop = stops[index]

        if stop ~= nil then

            local stationGroup = lines.safeField(stop, "stationGroup")

            if stationGroup ~= nil then
                result[#result + 1] = stationGroup
            end

        end

    end

    return result

end


local function findSharedStationGroup(lineIdA, lineIdB)

    local groupsA = getLineStationGroups(lineIdA)
    local groupsB = getLineStationGroups(lineIdB)

    for _, groupA in ipairs(groupsA) do
        for _, groupB in ipairs(groupsB) do
            if groupA == groupB then
                return groupA
            end
        end
    end

    return nil

end


-- Picks the destination with the MOST waiting (not-yet-picked-up)
-- cargo, to give the test the best real chance of showing a pickup
-- within a reasonable real-time window. Unlike findEmptyDestinationLine
-- above, deliberately does NOT prefer an empty destination line --
-- since the per-vehicle cargoLoad read makes other vehicles on that
-- line a non-issue, an empty destination would actually be the WRONG
-- choice here (an empty line likely also has no waiting demand yet).
local function findDestinationLineWithWaitingDemand(sourceLineId)

    local hubStationGroup = nil

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then
        return nil
    end

    local best = nil
    local candidateCount = 0

    for _, lineId in ipairs(allLineIds) do

        if lineId ~= sourceLineId then

            local name = lines.getName(lineId)

            if managed_registry.isManaged(lineId) then

                if hubStationGroup == nil then
                    hubStationGroup = findSharedStationGroup(sourceLineId, lineId)
                end

                candidateCount = candidateCount + 1

                local waiting = 0

                if hubStationGroup ~= nil then

                    local scanResult = demand.scan(lineId, hubStationGroup)
                    waiting = (scanResult ~= nil and scanResult.totalWaiting) or 0

                end

                -- Diagnostic, not spammy: this only runs once per
                -- button click (not per guiUpdate tick), and the
                -- candidate list is small (one line per managed
                -- destination). Kept because "no destination found"
                -- was otherwise a dead end -- the pipeline is
                -- designed to keep trucks matched to demand, so
                -- waiting cargo across managed lines can genuinely
                -- sit near zero much of the time; this shows the
                -- real numbers instead of just pass/fail.
                log.info(
                    "  candidate: "
                        .. tostring(name)
                        .. " | waiting="
                        .. tostring(waiting)
                        .. " | hubStationGroup="
                        .. tostring(hubStationGroup)
                )

                if waiting > 0
                    and (best == nil or waiting > best.waiting)
                then

                    best = {
                        lineId = lineId,
                        lineName = name,
                        waiting = waiting
                    }

                end

            end

        end

    end

    if best == nil then

        log.info(
            "  ("
                .. tostring(candidateCount)
                .. " other managed line(s) checked, none showed any "
                .. "waiting cargo right now)"
        )

    end

    return best

end


function M.startBugBTest(onComplete)

    log.info("----------------------------------------")
    log.info("BUG B TEST (PARK-STOP PICKUP) -- START")
    log.info("----------------------------------------")

    if bugBWatch ~= nil then

        log.info(
            "A Bug B test is already in progress for vehicle "
                .. tostring(bugBWatch.vehicleId)
                .. ". Run the check step instead, or reload the "
                .. "save to abandon it."
        )

        if onComplete ~= nil then
            onComplete(false, "already-watching")
        end

        return { success = false, reason = "already-watching" }

    end


    local source = findEmptyVehicleOnManagedLine()

    if source == nil then

        log.info(
            "FAILED: no managed (\"● \") line with a confirmed-empty "
                .. "vehicle was found right now. Try again in a "
                .. "moment."
        )

        if onComplete ~= nil then
            onComplete(false, "no-empty-vehicle-found")
        end

        return { success = false, reason = "no-empty-vehicle-found" }

    end


    local destination = findDestinationLineWithWaitingDemand(source.lineId)

    if destination == nil then

        log.info(
            "FAILED: no other managed (\"● \") line currently shows "
                .. "any waiting (not-yet-picked-up) cargo. Try again "
                .. "once demand has built up somewhere."
        )

        if onComplete ~= nil then
            onComplete(false, "no-demand-destination-found")
        end

        return { success = false, reason = "no-demand-destination-found" }

    end


    log.info(
        "Source: " .. tostring(source.lineName)
            .. " (id=" .. tostring(source.lineId) .. ")"
    )

    log.info(
        "Vehicle: " .. tostring(source.vehicleId)
            .. " (confirmed empty)"
    )

    log.info(
        "Destination: " .. tostring(destination.lineName)
            .. " (id=" .. tostring(destination.lineId) .. ")"
            .. " | waiting cargo=" .. tostring(destination.waiting)
    )


    local beforeInspect = vehicles.inspect(source.vehicleId)

    log.info("BEFORE")

    log.info(
        "state=" .. tostring(beforeInspect.stateName)
            .. " | line=" .. tostring(beforeInspect.line)
            .. " | stopIndex=" .. tostring(beforeInspect.stopIndex)
            .. " | doorsOpen=" .. tostring(beforeInspect.doorsOpen)
    )

    vehicles.dumpEntityInfo(
        source.vehicleId,
        "VEHICLE ENTITY BEFORE REASSIGNMENT"
    )


    bugBWatch = {
        vehicleId = source.vehicleId,
        sourceLineId = source.lineId,
        sourceLineName = source.lineName,
        destinationLineId = destination.lineId,
        destinationLineName = destination.lineName,
        destinationWaitingBefore = destination.waiting
    }


    -- Deliberately the exact same bare setLine pattern
    -- assignOneVehicleThenRetireStop uses in real play (line_splitter.lua)
    -- -- no injectParkStops workaround -- since the whole point is to
    -- observe what Stage 2 actually does today, not the fixed version.
    vehicles.setManualDeparture(source.vehicleId, true, function(holdSuccess)

        log.info("HOLD RESULT: " .. tostring(holdSuccess))

        if not holdSuccess then

            log.info(
                "TEST ABORTED: could not hold vehicle before reassignment."
            )

            bugBWatch = nil

            if onComplete ~= nil then
                onComplete(false, "hold-failed")
            end

            return

        end


        vehicles.setLine(source.vehicleId, destination.lineId, 0, function(setLineSuccess)

            log.info("SETLINE RESULT: " .. tostring(setLineSuccess))

            vehicles.setManualDeparture(source.vehicleId, false, function(releaseSuccess)

                log.info("RELEASE RESULT: " .. tostring(releaseSuccess))

                if not setLineSuccess then

                    log.info("TEST ABORTED: setLine was rejected.")

                    bugBWatch = nil

                    if onComplete ~= nil then
                        onComplete(false, "setline-rejected")
                    end

                    return

                end


                local afterInspect = vehicles.inspect(source.vehicleId)

                log.info("IMMEDIATELY AFTER")

                log.info(
                    "state=" .. tostring(afterInspect.stateName)
                        .. " | line=" .. tostring(afterInspect.line)
                        .. " | stopIndex=" .. tostring(afterInspect.stopIndex)
                )

                log.info(
                    "LINE ACTUALLY CHANGED: "
                        .. tostring(afterInspect.line == destination.lineId)
                )

                log.info("----------------------------------------")

                log.info(
                    "Vehicle "
                        .. tostring(source.vehicleId)
                        .. " is now being watched (bare setLine, no "
                        .. "Park-stop workaround). Let the game run "
                        .. "for a few real minutes -- long enough for "
                        .. "it to reach "
                        .. tostring(destination.lineName)
                        .. "'s first stop at least once -- then click "
                        .. "this button a second time to check whether "
                        .. "it actually picked up any cargo."
                )

                log.info("----------------------------------------")

                if onComplete ~= nil then
                    onComplete(true, "watching")
                end

            end)

        end)

    end)

    return { success = true, pending = true }

end


function M.checkBugBTest(onComplete)

    log.info("----------------------------------------")
    log.info("BUG B TEST (PARK-STOP PICKUP) -- CHECK")
    log.info("----------------------------------------")

    if bugBWatch == nil then

        log.info(
            "No Bug B test is currently in progress. Run the start "
                .. "step first."
        )

        if onComplete ~= nil then
            onComplete(false, "not-watching")
        end

        return { success = false, reason = "not-watching" }

    end


    local watch = bugBWatch

    log.info(
        "Vehicle: " .. tostring(watch.vehicleId)
    )

    log.info(
        "Destination line: " .. tostring(watch.destinationLineName)
            .. " (id=" .. tostring(watch.destinationLineId) .. ")"
    )


    local nowInspect = vehicles.inspect(watch.vehicleId)

    if not nowInspect.valid then

        log.info(
            "FAILED: vehicle "
                .. tostring(watch.vehicleId)
                .. " could no longer be read (sold? despawned?)."
        )

        bugBWatch = nil

        if onComplete ~= nil then
            onComplete(false, "vehicle-unreadable")
        end

        return { success = false, reason = "vehicle-unreadable" }

    end

    log.info("NOW")

    log.info(
        "state=" .. tostring(nowInspect.stateName)
            .. " | line=" .. tostring(nowInspect.line)
            .. " | stopIndex=" .. tostring(nowInspect.stopIndex)
    )

    log.info(
        "STILL ON DESTINATION LINE: "
            .. tostring(nowInspect.line == watch.destinationLineId)
    )

    vehicles.dumpEntityInfo(
        watch.vehicleId,
        "VEHICLE ENTITY NOW"
    )

    local cargoLoadNow = vehicles.getCargoLoad(watch.vehicleId)
    local isEmptyNow = vehicles.isVehicleEmpty(watch.vehicleId)

    local destinationSnapshotNow =
        vehicles.snapshotLineCargo(watch.destinationLineId)

    local destinationWaitingNow =
        destinationSnapshotNow.totalCargo - destinationSnapshotNow.onVehicleCargo

    log.info("========================================")
    log.info("VERDICT")
    log.info("========================================")

    log.info(
        "Vehicle's own cargoLoad now: "
            .. tostring(cargoLoadNow)
            .. " | isEmpty=" .. tostring(isEmptyNow)
    )

    log.info(
        "Destination line waiting cargo: before="
            .. tostring(watch.destinationWaitingBefore)
            .. ", now=" .. tostring(destinationWaitingNow)
    )

    if isEmptyNow == false then

        log.info(
            "RESULT: the vehicle IS carrying cargo now -- it picked "
                .. "something up via the bare setLine, no "
                .. "injectParkStops workaround needed. This is a "
                .. "direct, per-vehicle read (cargoLoad), not a "
                .. "line-scoped proxy -- Bug B did NOT trigger for "
                .. "this vehicle, in this run."
        )

    elseif isEmptyNow == true then

        log.info(
            "RESULT: the vehicle is STILL empty. If it has visited "
                .. "the destination's stop at least once by now "
                .. "(check stopIndex/state history, or watch it "
                .. "in-game) and demand was genuinely present the "
                .. "whole time, this is direct evidence Bug B is "
                .. "real -- the bare setLine reassignment did not "
                .. "trigger pickup logic at the new destination. If "
                .. "it hasn't reached the stop yet, this run is "
                .. "inconclusive -- let it run longer and check again."
        )

    else

        log.info(
            "RESULT: INCONCLUSIVE -- cargoLoad could not be read "
                .. "this time (isEmptyNow=nil). Try the check again."
        )

        return { success = true, pending = true }

    end

    log.info("========================================")

    bugBWatch = nil

    if onComplete ~= nil then
        onComplete(true, "checked")
    end

    return { success = true }

end


function M.runBugBTestStep(onComplete)

    if bugBWatch == nil then
        return M.startBugBTest(onComplete)
    end

    return M.checkBugBTest(onComplete)

end


-- ============================================================
-- CARGO COMPATIBILITY LIVE VERIFICATION (PROGRESS.md Not Started #4)
--
-- Single click, immediate -- unlike the two-click journey/Bug B
-- tests above, this is a pure read with nothing to wait on.
--
-- FINDING, LIVE-CONFIRMED (first version of this test): sampling
-- just one vehicle per managed line showed every single one with
-- the IDENTICAL full 16-cargo-type list -- meaning the mechanism
-- worked (no read failures) but never actually proved the
-- classification DISCRIMINATES between vehicle types, since every
-- vehicle sampled happened to be a generic "universal" model. This
-- version scans every ROAD vehicle game-wide (not just managed
-- lines, so a restricted truck sitting unassigned or on any line
-- still gets caught) and groups them by their exact distinct
-- capability profile, so real variation (or its absence) is visible
-- directly rather than inferred from a handful of samples.
-- ============================================================

function M.testCargoCompatibility()

    log.info("----------------------------------------")
    log.info("CARGO COMPATIBILITY TEST")
    log.info("----------------------------------------")

    local ok, roadVehicleIds =
        pcall(function()
            return game.interface.getVehicles({ carrier = "ROAD" })
        end)

    if not ok or roadVehicleIds == nil then

        log.info("FAILED: could not read road vehicle list.")

        return { success = false, reason = "vehicle-list-unavailable" }

    end

    local profiles = {}
    local profileOrder = {}
    local uncheckable = 0

    for _, vehicleId in ipairs(roadVehicleIds) do

        local compatibleTypes = vehicles.getCompatibleCargoTypes(vehicleId)

        if compatibleTypes == nil then

            uncheckable = uncheckable + 1

        else

            local sorted = {}

            for _, cargoType in ipairs(compatibleTypes) do
                sorted[#sorted + 1] = cargoType
            end

            table.sort(sorted)

            local profileKey = table.concat(sorted, ",")

            if profiles[profileKey] == nil then

                profiles[profileKey] = {
                    count = 0,
                    types = sorted,
                    exampleVehicleId = vehicleId
                }

                profileOrder[#profileOrder + 1] = profileKey

            end

            profiles[profileKey].count = profiles[profileKey].count + 1

        end

    end

    log.info(
        "Total road vehicles: "
            .. tostring(#roadVehicleIds)
            .. " | distinct capability profiles: "
            .. tostring(#profileOrder)
            .. " | unreadable: "
            .. tostring(uncheckable)
    )

    for _, profileKey in ipairs(profileOrder) do

        local profile = profiles[profileKey]

        log.info(
            "  "
                .. tostring(profile.count)
                .. " vehicle(s) (e.g. "
                .. tostring(profile.exampleVehicleId)
                .. ") | compatible="
                .. table.concat(profile.types, ",")
        )

    end

    if #profileOrder <= 1 then

        log.info(
            "NOTE: every road vehicle in this save shares the same "
                .. "capability profile -- the classification mechanism "
                .. "is reading real data, but discrimination between "
                .. "restricted and universal vehicles has not yet "
                .. "been observed. Not a bug -- just means nothing "
                .. "cargo-restricted exists in the fleet yet."
        )

    end

    log.info("----------------------------------------")

    return {
        success = true,
        totalVehicles = #roadVehicleIds,
        distinctProfiles = #profileOrder
    }

end


-- ============================================================
-- VEHICLE RENAME / COLOUR LIVE TEST (config.DEBUG only)
--
-- IDEAS.md's "Vehicle Identity Naming and Fleet Colour-Coding" idea
-- needs to know whether setName/setColor actually work on a VEHICLE
-- entity at all -- confirmed present in api.cmd.make (COMMANDS.md),
-- but zero live evidence either way from this mod or the one
-- reference mod checked (LineManager only ever displays rename
-- suggestions, never calls setName itself). This settles it directly
-- rather than inferring from "it sits alongside other generic
-- commands."
--
-- Single click, immediate, picks one confirmed-empty vehicle off any
-- currently-managed line (same finder the Bug B test uses, so this
-- never touches a vehicle mid-delivery):
--   1. Read its current name.
--   2. setName it to a test string, re-read, log whether it stuck.
--   3. Restore the original name (re-read once more to confirm the
--      restore itself worked -- don't just assume it did).
--   4. setColor it to a test colour. NOT auto-restored: unlike name,
--      no colour field was ever found on a vehicle in the full
--      entity dump (SAMPLE MANAGED-LINE VEHICLE, PROGRESS.md/Done),
--      so there is nothing to read back and no honest way to
--      restore the exact original colour programmatically. Logged
--      clearly so this is a deliberate, known trade-off, not a
--      silent side effect -- one test vehicle's colour is trivially
--      fixable by hand in-game afterward if desired.
-- ============================================================

function M.testVehicleRenameAndColor()

    log.info("----------------------------------------")
    log.info("VEHICLE RENAME / COLOUR TEST")
    log.info("----------------------------------------")

    local source = findEmptyVehicleOnManagedLine()

    if source == nil then

        log.info(
            "FAILED: no managed (\"● \") line with a confirmed-empty "
                .. "vehicle was found right now. Try again in a "
                .. "moment."
        )

        return { success = false, reason = "no-empty-vehicle-found" }

    end

    local vehicleId = source.vehicleId

    log.info(
        "Vehicle: "
            .. tostring(vehicleId)
            .. " (on "
            .. tostring(source.lineName)
            .. ")"
    )

    local okEntity, entityBefore =
        pcall(game.interface.getEntity, vehicleId)

    if not okEntity or entityBefore == nil then

        log.info(
            "FAILED: could not read the vehicle entity before testing."
        )

        return { success = false, reason = "entity-read-failed" }

    end

    local originalName =
        lines.safeField(entityBefore, "name")

    log.info(
        "BEFORE: name=" .. tostring(originalName)
    )

    local testName =
        "● RENAME TEST " .. tostring(vehicleId)

    local okNameCommand, nameCommandOrError =
        pcall(
            api.cmd.make.setName,
            vehicleId,
            testName
        )

    if not okNameCommand then

        log.info(
            "setName COMMAND ERROR: " .. tostring(nameCommandOrError)
        )

        return { success = false, reason = "setname-command-failed" }

    end

    api.cmd.sendCommand(
        nameCommandOrError,

        function(cmd, renameSuccess)

            log.info(
                "setName RESULT: " .. tostring(renameSuccess)
            )

            local okAfter, entityAfter =
                pcall(game.interface.getEntity, vehicleId)

            local nameAfter =
                okAfter and entityAfter ~= nil
                    and lines.safeField(entityAfter, "name")
                    or nil

            log.info(
                "AFTER RENAME: name=" .. tostring(nameAfter)
            )

            log.info(
                "VERDICT (name): "
                    .. (
                        nameAfter == testName
                            and "setName WORKS on a vehicle entity -- LIVE CONFIRMED"
                            or "setName did NOT change the vehicle's name -- unconfirmed/failed"
                    )
            )

            -- Restore original name regardless of verdict above --
            -- never leave the player's real vehicle renamed just
            -- because the test was run.
            local okRestoreCommand, restoreCommandOrError =
                pcall(
                    api.cmd.make.setName,
                    vehicleId,
                    originalName
                )

            if not okRestoreCommand then

                log.info(
                    "RESTORE setName COMMAND ERROR: "
                        .. tostring(restoreCommandOrError)
                        .. " -- vehicle "
                        .. tostring(vehicleId)
                        .. " may still show the test name, rename it "
                        .. "back by hand if so."
                )

            else

                api.cmd.sendCommand(
                    restoreCommandOrError,

                    function(cmd2, restoreSuccess)

                        log.info(
                            "RESTORE setName RESULT: "
                                .. tostring(restoreSuccess)
                        )

                        local okRestored, entityRestored =
                            pcall(game.interface.getEntity, vehicleId)

                        local nameRestored =
                            okRestored and entityRestored ~= nil
                                and lines.safeField(entityRestored, "name")
                                or nil

                        log.info(
                            "AFTER RESTORE: name="
                                .. tostring(nameRestored)
                                .. " (original was "
                                .. tostring(originalName)
                                .. ")"
                        )

                    end
                )

            end


            -- Colour test, run after the name restore is at least
            -- issued -- NOT auto-restored, see the big comment above.
            local okColor, testColor =
                pcall(
                    api.type.Vec3f.new,
                    1.0,
                    0.0,
                    1.0
                )

            if not okColor or testColor == nil then

                log.info(
                    "COLOUR TEST SKIPPED: could not build a test "
                        .. "colour value: "
                        .. tostring(testColor)
                )

                return

            end

            local okColorCommand, colorCommandOrError =
                pcall(
                    api.cmd.make.setColor,
                    vehicleId,
                    testColor
                )

            if not okColorCommand then

                log.info(
                    "setColor COMMAND ERROR: "
                        .. tostring(colorCommandOrError)
                )

                return

            end

            api.cmd.sendCommand(
                colorCommandOrError,

                function(cmd3, colorSuccess)

                    log.info(
                        "setColor RESULT: " .. tostring(colorSuccess)
                    )

                    log.info(
                        "VERDICT (colour): "
                            .. (
                                colorSuccess
                                    and "setColor command SUCCEEDED on a "
                                        .. "vehicle entity -- check the "
                                        .. "vehicle visually in-game to "
                                        .. "confirm it actually changed "
                                        .. "(no colour field was found "
                                        .. "to re-read and verify "
                                        .. "programmatically)"
                                    or "setColor command FAILED/rejected "
                                        .. "-- unconfirmed"
                            )
                    )

                    log.info(
                        "NOTE: vehicle "
                            .. tostring(vehicleId)
                            .. "'s colour was NOT restored -- no "
                            .. "readable original value to restore to. "
                            .. "Recolour it by hand in-game if wanted."
                    )

                end
            )

        end
    )

    return { success = true, pending = true, vehicleId = vehicleId }

end


return M