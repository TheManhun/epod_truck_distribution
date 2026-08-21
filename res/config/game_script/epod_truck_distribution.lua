-- ============================================================
-- EPOD-TD
-- TF2 Truck Distribution
--
-- v0.0.25
-- NATIVE PARK INJECTION WRITE TEST
--
-- PURPOSE
-- -------
-- Modify the EXISTING:
--
--     Truck - CD - Hendon
--
-- line.
--
-- BEFORE:
--
--     Hendon East
--     Destination A
--     Hendon East
--     Destination B
--     Hendon East
--     Destination C
--     ...
--
-- AFTER:
--
--     EPOD-TD Truck Park
--     Hendon East
--     Destination A
--
--     EPOD-TD Truck Park
--     Hendon East
--     Destination B
--
--     EPOD-TD Truck Park
--     Hendon East
--     Destination C
--     ...
--
-- IMPORTANT
-- ---------
-- * Reads the COMPLETE existing route.
-- * Does NOT assume how many destinations exist.
-- * Preserves the SAME line entity.
-- * Does NOT create a replacement line.
-- * Does NOT allocate trucks.
-- * Does NOT modify cargo.
-- * Does NOT reverse trucks.
-- * Does NOT hold trucks.
-- * Does NOT dispatch trucks.
--
-- This version ONLY rewrites the stop list.
-- ============================================================


-- ============================================================
-- CONFIG
-- ============================================================

local PREFIX = "[EPOD-TD]"

local VERSION = "0.0.25"

local SOURCE_LINE_NAME =
    "Truck - CD - Hendon"

-- We currently use the already-existing test line merely
-- to discover the native Truck Park stop.
--
-- Later the real mod will know its nominated Truck Park
-- directly from the Distribution Centre configuration.
local PARK_REFERENCE_LINE_NAME =
    "EPOD-TD TEST - Alexander"

local HUB_NAME =
    "Hendon East"

local PARK_NAME =
    "EPOD-TD Truck Park"

-- Give TF2 a little time after loading the save before
-- inspecting and changing the line.
local START_DELAY_UPDATES = 120


-- ============================================================
-- RUNTIME STATE
-- ============================================================

local updateCount = 0

local started = false
local finished = false
local commandPending = false


-- ============================================================
-- LOGGING
-- ============================================================

local function log(message)

    print(
        PREFIX
            .. " "
            .. tostring(message)
    )

end


local function separator()

    log(
        "----------------------------------------"
    )

end


local function header()

    log(
        "========================================"
    )

    log(
        "TF2 Truck Distribution v"
            .. VERSION
    )

    log(
        "NATIVE PARK INJECTION WRITE TEST"
    )

    log(
        "ROUTE CHANGE ONLY - NO TRUCK CONTROL"
    )

    log(
        "========================================"
    )

end


-- ============================================================
-- ENTITY / LINE NAMES
-- ============================================================

local function getEntityName(entityId)

    if entityId == nil
        or entityId < 0
    then

        return "UNKNOWN"

    end


    local ok, name =
        pcall(
            game.interface.getName,
            entityId
        )


    if ok
        and name ~= nil
        and name ~= ""
    then

        return name

    end


    return "Entity "
        .. tostring(entityId)

end


local function getLineName(lineId)

    if lineId == nil
        or lineId < 0
    then

        return "NO LINE"

    end


    local ok, name =
        pcall(
            game.interface.getName,
            lineId
        )


    if ok
        and name ~= nil
        and name ~= ""
    then

        return name

    end


    return "Line "
        .. tostring(lineId)

end


local function findLineByName(name)

    local lines =
        game.interface.getLines()


    if lines == nil then
        return nil
    end


    for _, lineId
        in ipairs(lines)
    do

        if getLineName(lineId)
            == name
        then

            return lineId

        end

    end


    return nil

end


-- ============================================================
-- SAFE NATIVE USERDATA ACCESS
-- ============================================================

local function safeField(
    object,
    fieldName
)

    if object == nil then
        return nil
    end


    local ok, value =
        pcall(
            function()

                return object[fieldName]

            end
        )


    if ok then
        return value
    end


    return nil

end


local function safeLength(object)

    if object == nil then
        return 0
    end


    local ok, length =
        pcall(
            function()

                return #object

            end
        )


    if ok
        and length ~= nil
    then

        return length

    end


    return 0

end


-- ============================================================
-- READ LINE
-- ============================================================

local function getNativeLine(lineId)

    local ok, line =
        pcall(
            api.engine.getComponent,
            lineId,
            api.type.ComponentType.LINE
        )


    if not ok
        or line == nil
    then

        return nil

    end


    return line

end


-- ============================================================
-- PRINT COMPLETE ROUTE
-- ============================================================

local function printRoute(
    title,
    line
)

    separator()

    log(title)


    if line == nil then

        log(
            "LINE IS NIL"
        )

        separator()

        return

    end


    local stops =
        safeField(
            line,
            "stops"
        )


    if stops == nil then

        log(
            "NO STOP CONTAINER"
        )

        separator()

        return

    end


    local count =
        safeLength(
            stops
        )


    log(
        "Stops found: "
            .. tostring(count)
    )


    for index = 1, count do

        local stop =
            stops[index]


        if stop ~= nil then

            local stationGroup =
                safeField(
                    stop,
                    "stationGroup"
                )


            local station =
                safeField(
                    stop,
                    "station"
                )


            local terminal =
                safeField(
                    stop,
                    "terminal"
                )


            log(
                string.format(
                    "%02d | %-30s | group=%s | station=%s | terminal=%s",
                    index - 1,
                    getEntityName(
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


    separator()

end


-- ============================================================
-- NATIVE VECTOR COPYING
--
-- Native TF2 vectors cannot be replaced with ordinary Lua
-- tables where userdata is expected.
--
-- For fields such as waypoints / alternative terminals we
-- preserve them by copying values into the newly-created
-- native containers when possible.
-- ============================================================

local function copyNativeSequence(
    source,
    destination
)

    if source == nil
        or destination == nil
    then

        return
    end


    local count =
        safeLength(
            source
        )


    for index = 1, count do

        local value =
            source[index]


        if value ~= nil then

            local ok =
                pcall(
                    function()

                        destination[#destination + 1] =
                            value

                    end
                )


            if not ok then

                -- Some TF2 native vector bindings may not
                -- support append this way.
                --
                -- Do not crash the whole line rewrite.
                return

            end

        end

    end

end


-- ============================================================
-- COPY STOP CONFIGURATION
--
-- Creates an actual native:
--
--     api.type.Line.Stop
--
-- rather than an ordinary Lua table.
--
-- The TF2 API describes Line.Stop as containing stationGroup,
-- station, terminal, alternativeTerminals, loadMode,
-- minWaitingTime, maxWaitingTime, waypoints and how.
-- ============================================================

local function makeNativeStopCopy(
    sourceStop
)

    local stop =
        api.type.Line.Stop.new()


    -- --------------------------------------------------------
    -- BASIC DESTINATION
    -- --------------------------------------------------------

    stop.stationGroup =
        safeField(
            sourceStop,
            "stationGroup"
        )


    stop.station =
        safeField(
            sourceStop,
            "station"
        )


    stop.terminal =
        safeField(
            sourceStop,
            "terminal"
        )


    -- --------------------------------------------------------
    -- LOAD MODE
    -- --------------------------------------------------------

    local loadMode =
        safeField(
            sourceStop,
            "loadMode"
        )


    if loadMode ~= nil then

        stop.loadMode =
            loadMode

    end


    -- --------------------------------------------------------
    -- WAITING TIMES
    -- --------------------------------------------------------

    local minWaitingTime =
        safeField(
            sourceStop,
            "minWaitingTime"
        )


    if minWaitingTime ~= nil then

        stop.minWaitingTime =
            minWaitingTime

    end


    local maxWaitingTime =
        safeField(
            sourceStop,
            "maxWaitingTime"
        )


    if maxWaitingTime ~= nil then

        stop.maxWaitingTime =
            maxWaitingTime

    end


    -- --------------------------------------------------------
    -- WAYPOINTS
    -- --------------------------------------------------------

    local sourceWaypoints =
        safeField(
            sourceStop,
            "waypoints"
        )


    local destinationWaypoints =
        safeField(
            stop,
            "waypoints"
        )


    copyNativeSequence(
        sourceWaypoints,
        destinationWaypoints
    )


    -- --------------------------------------------------------
    -- ALTERNATIVE TERMINALS
    -- --------------------------------------------------------

    local sourceAlternatives =
        safeField(
            sourceStop,
            "alternativeTerminals"
        )


    local destinationAlternatives =
        safeField(
            stop,
            "alternativeTerminals"
        )


    copyNativeSequence(
        sourceAlternatives,
        destinationAlternatives
    )


    -- --------------------------------------------------------
    -- "how"
    --
    -- Our probe showed:
    --
    --     how = nil
    --
    -- on the current Hendon stop.
    --
    -- We therefore do not manufacture cargo-specific stop
    -- configuration when none exists.
    --
    -- If an existing stop exposes native "how" data, attempt
    -- to preserve the native value directly.
    -- --------------------------------------------------------

    local how =
        safeField(
            sourceStop,
            "how"
        )


    if how ~= nil then

        pcall(
            function()

                stop.how =
                    how

            end
        )

    end


    return stop

end


-- ============================================================
-- APPEND NATIVE STOP
-- ============================================================

local function appendNativeStop(
    nativeStops,
    nativeStop
)

    local before =
        safeLength(
            nativeStops
        )


    local ok, err =
        pcall(
            function()

                nativeStops[
                    before + 1
                ] =
                    nativeStop

            end
        )


    if not ok then

        return false,
            tostring(err)

    end


    local after =
        safeLength(
            nativeStops
        )


    if after ~= before + 1 then

        return false,
            "Native stop vector length did not increase."

    end


    return true, nil

end


-- ============================================================
-- FIND PARK REFERENCE STOP
-- ============================================================

local function findParkReferenceStop()

    local referenceLineId =
        findLineByName(
            PARK_REFERENCE_LINE_NAME
        )


    if referenceLineId == nil then

        return nil,
            nil,
            "Reference line not found: "
                .. PARK_REFERENCE_LINE_NAME

    end


    local line =
        getNativeLine(
            referenceLineId
        )


    if line == nil then

        return nil,
            nil,
            "Could not read Park reference line."

    end


    local stops =
        safeField(
            line,
            "stops"
        )


    if stops == nil then

        return nil,
            nil,
            "Park reference line has no stops."

    end


    local count =
        safeLength(
            stops
        )


    for index = 1, count do

        local stop =
            stops[index]


        if stop ~= nil then

            local stationGroup =
                safeField(
                    stop,
                    "stationGroup"
                )


            if getEntityName(
                stationGroup
            ) == PARK_NAME
            then

                return stop,
                    referenceLineId,
                    nil

            end

        end

    end


    return nil,
        referenceLineId,
        "Could not find "
            .. PARK_NAME
            .. " on reference line."

end


-- ============================================================
-- FIND HENDON STATION GROUP
-- ============================================================

local function findHubStationGroup(
    sourceLine
)

    local stops =
        safeField(
            sourceLine,
            "stops"
        )


    if stops == nil then

        return nil, 0

    end


    local count =
        safeLength(
            stops
        )


    local hubStationGroup = nil
    local occurrences = 0


    for index = 1, count do

        local stop =
            stops[index]


        if stop ~= nil then

            local stationGroup =
                safeField(
                    stop,
                    "stationGroup"
                )


            if getEntityName(
                stationGroup
            ) == HUB_NAME
            then

                hubStationGroup =
                    stationGroup

                occurrences =
                    occurrences + 1

            end

        end

    end


    return hubStationGroup,
        occurrences

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
        safeField(
            line,
            "stops"
        )


    if stops == nil then
        return false
    end


    local count =
        safeLength(
            stops
        )


    if count == 0 then
        return false
    end


    local hubCount = 0
    local injectedHubCount = 0


    for index = 1, count do

        local stop =
            stops[index]


        local stationGroup =
            safeField(
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


            -- Line is circular.
            if previousIndex < 1 then

                previousIndex =
                    count

            end


            local previousStop =
                stops[
                    previousIndex
                ]


            local previousGroup =
                safeField(
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
        and hubCount
            == injectedHubCount

end


-- ============================================================
-- COPY LINE VEHICLE INFO
-- ============================================================

local function copyVehicleInfo(
    sourceLine,
    destinationLine
)

    local sourceVehicleInfo =
        safeField(
            sourceLine,
            "vehicleInfo"
        )


    local destinationVehicleInfo =
        safeField(
            destinationLine,
            "vehicleInfo"
        )


    if sourceVehicleInfo == nil
        or destinationVehicleInfo == nil
    then

        return

    end


    -- --------------------------------------------------------
    -- DEFAULT PRICE
    -- --------------------------------------------------------

    local defaultPrice =
        safeField(
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


    -- --------------------------------------------------------
    -- TRANSPORT MODES
    -- --------------------------------------------------------

    local sourceModes =
        safeField(
            sourceVehicleInfo,
            "transportModes"
        )


    local destinationModes =
        safeField(
            destinationVehicleInfo,
            "transportModes"
        )


    copyNativeSequence(
        sourceModes,
        destinationModes
    )

end


-- ============================================================
-- BUILD NEW NATIVE LINE
-- ============================================================

local function buildInjectedNativeLine(
    sourceLine,
    hubStationGroup,
    parkReferenceStop
)

    -- THIS is the important change from v0.0.22/v0.0.23.
    --
    -- We create a real TF2 Line userdata.

    local newLine =
        api.type.Line.new()


    if newLine == nil then

        return nil,
            0,
            "api.type.Line.new() returned nil."

    end


    local destinationStops =
        safeField(
            newLine,
            "stops"
        )


    if destinationStops == nil then

        return nil,
            0,
            "New native Line has no stops container."

    end


    local sourceStops =
        safeField(
            sourceLine,
            "stops"
        )


    if sourceStops == nil then

        return nil,
            0,
            "Source line has no stops."

    end


    -- Preserve deprecated waitingTime if the native type
    -- allows it.

    local waitingTime =
        safeField(
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


    copyVehicleInfo(
        sourceLine,
        newLine
    )


    local sourceCount =
        safeLength(
            sourceStops
        )


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
            safeField(
                sourceStop,
                "stationGroup"
            )


        -- ----------------------------------------------------
        -- BEFORE EVERY HENDON:
        --
        -- append a native copy of Truck Park.
        -- ----------------------------------------------------

        if stationGroup
            == hubStationGroup
        then

            local nativeParkStop =
                makeNativeStopCopy(
                    parkReferenceStop
                )


            local ok, err =
                appendNativeStop(
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


        -- ----------------------------------------------------
        -- PRESERVE ORIGINAL STOP
        -- ----------------------------------------------------

        local nativeOriginalStop =
            makeNativeStopCopy(
                sourceStop
            )


        local ok, err =
            appendNativeStop(
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
        getNativeLine(
            lineId
        )


    if updatedLine == nil then

        log(
            "VERIFY ERROR: Unable to reread line."
        )

        return false

    end


    printRoute(
        "ACTUAL ROUTE AFTER UPDATE",
        updatedLine
    )


    local actualStops =
        safeField(
            updatedLine,
            "stops"
        )


    local actualCount =
        safeLength(
            actualStops
        )


    log(
        "Expected stop count: "
            .. tostring(
                expectedStopCount
            )
    )


    log(
        "Actual stop count:   "
            .. tostring(
                actualCount
            )
    )


    local injectionCorrect =
        routeAlreadyInjected(
            updatedLine,
            hubStationGroup,
            parkStationGroup
        )


    if actualCount
        == expectedStopCount
        and injectionCorrect
    then

        log(
            "========================================"
        )

        log(
            "PARK INJECTION SUCCESS"
        )

        log(
            "Existing line entity preserved."
        )

        log(
            "Every Hendon East now has "
                .. "Truck Park immediately before it."
        )

        log(
            "NO TRUCK CONTROL WAS PERFORMED."
        )

        log(
            "========================================"
        )


        return true

    end


    log(
        "========================================"
    )

    log(
        "VERIFICATION FAILED"
    )

    log(
        "The command reported success but the "
            .. "resulting route was not as expected."
    )

    log(
        "========================================"
    )


    return false

end


-- ============================================================
-- MAIN WRITE TEST
-- ============================================================

local function runTest()

    if started then
        return
    end


    started = true


    header()


    -- ========================================================
    -- FIND EXISTING HENDON LINE
    -- ========================================================

    local sourceLineId =
        findLineByName(
            SOURCE_LINE_NAME
        )


    if sourceLineId == nil then

        log(
            "FAILED:"
        )

        log(
            "Could not find line: "
                .. SOURCE_LINE_NAME
        )

        finished = true

        return

    end


    log(
        "Source line: "
            .. SOURCE_LINE_NAME
    )


    log(
        "Source line entity: "
            .. tostring(
                sourceLineId
            )
    )


    -- ========================================================
    -- READ EXISTING LINE
    -- ========================================================

    local sourceLine =
        getNativeLine(
            sourceLineId
        )


    if sourceLine == nil then

        log(
            "FAILED: Unable to read native LINE."
        )

        finished = true

        return

    end


    log(
        "Native line type: "
            .. type(
                sourceLine
            )
    )


    printRoute(
        "ORIGINAL COMPLETE ROUTE",
        sourceLine
    )


    local sourceStops =
        safeField(
            sourceLine,
            "stops"
        )


    local originalStopCount =
        safeLength(
            sourceStops
        )


    if originalStopCount == 0 then

        log(
            "FAILED: Source route has no stops."
        )

        finished = true

        return

    end


    -- ========================================================
    -- FIND HENDON
    -- ========================================================

    local hubStationGroup,
        hubOccurrences =
            findHubStationGroup(
                sourceLine
            )


    if hubStationGroup == nil
        or hubOccurrences == 0
    then

        log(
            "FAILED:"
        )

        log(
            HUB_NAME
                .. " was not found on source line."
        )

        finished = true

        return

    end


    log(
        "Hub: "
            .. HUB_NAME
    )


    log(
        "Hub stationGroup: "
            .. tostring(
                hubStationGroup
            )
    )


    log(
        "Hub occurrences: "
            .. tostring(
                hubOccurrences
            )
    )


    -- ========================================================
    -- FIND PARK
    -- ========================================================

    local parkReferenceStop,
        parkReferenceLineId,
        parkError =
            findParkReferenceStop()


    if parkReferenceStop == nil then

        log(
            "FAILED:"
        )

        log(
            tostring(
                parkError
            )
        )

        finished = true

        return

    end


    local parkStationGroup =
        safeField(
            parkReferenceStop,
            "stationGroup"
        )


    log(
        "Park: "
            .. PARK_NAME
    )


    log(
        "Park stationGroup: "
            .. tostring(
                parkStationGroup
            )
    )


    log(
        "Park reference line: "
            .. tostring(
                parkReferenceLineId
            )
    )


    -- ========================================================
    -- PROTECT AGAINST DOUBLE INJECTION
    -- ========================================================

    if routeAlreadyInjected(
        sourceLine,
        hubStationGroup,
        parkStationGroup
    )
    then

        separator()

        log(
            "ROUTE ALREADY INJECTED."
        )

        log(
            "Every Hendon East already has "
                .. "Truck Park before it."
        )

        log(
            "NO UPDATE SENT."
        )

        separator()


        finished = true

        return

    end


    -- ========================================================
    -- BUILD REAL NATIVE TF2 LINE
    -- ========================================================

    separator()

    log(
        "BUILDING NATIVE TF2 LINE"
    )


    log(
        "api.type.Line.new = "
            .. tostring(
                api.type.Line.new
            )
    )


    log(
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

        log(
            "FAILED BUILDING NATIVE LINE:"
        )

        log(
            tostring(
                buildError
            )
        )

        finished = true

        return

    end


    log(
        "Native line created."
    )


    log(
        "type(newLine) = "
            .. type(
                newLine
            )
    )


    local newStops =
        safeField(
            newLine,
            "stops"
        )


    local newStopCount =
        safeLength(
            newStops
        )


    log(
        "Park stops inserted: "
            .. tostring(
                parksInserted
            )
    )


    log(
        "Original stop count: "
            .. tostring(
                originalStopCount
            )
    )


    log(
        "New stop count: "
            .. tostring(
                newStopCount
            )
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

        log(
            "FAILED SANITY CHECK:"
        )

        log(
            "Expected "
                .. tostring(
                    hubOccurrences
                )
                .. " Park insertions but created "
                .. tostring(
                    parksInserted
                )
        )

        finished = true

        return

    end


    if newStopCount
        ~= expectedStopCount
    then

        log(
            "FAILED SANITY CHECK:"
        )

        log(
            "Expected "
                .. tostring(
                    expectedStopCount
                )
                .. " total stops but native Line contains "
                .. tostring(
                    newStopCount
                )
        )

        finished = true

        return

    end


    printRoute(
        "NEW NATIVE ROUTE TO BE WRITTEN",
        newLine
    )


    -- ========================================================
    -- CREATE updateLine COMMAND
    -- ========================================================

    separator()

    log(
        "READY TO WRITE"
    )


    log(
        "Existing line entity: "
            .. tostring(
                sourceLineId
            )
    )


    log(
        "This line entity will NOT be deleted."
    )


    log(
        "Old stops: "
            .. tostring(
                originalStopCount
            )
    )


    log(
        "New stops: "
            .. tostring(
                newStopCount
            )
    )


    log(
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

        log(
            "UPDATE LINE COMMAND CREATION ERROR:"
        )

        log(
            tostring(
                commandOrError
            )
        )

        finished = true

        return

    end


    local command =
        commandOrError


    log(
        "updateLine command created."
    )


    -- ========================================================
    -- SEND WRITE COMMAND
    -- ========================================================

    commandPending = true


    log(
        "Sending updateLine command..."
    )


    local sendOk,
        sendError =
            pcall(
                function()

                    api.cmd.sendCommand(
                        command,

                        function(
                            cmd,
                            success
                        )

                            commandPending =
                                false


                            separator()

                            log(
                                "UPDATE LINE CALLBACK"
                            )


                            log(
                                "Success: "
                                    .. tostring(
                                        success
                                    )
                            )


                            if not success then

                                log(
                                    "TF2 REJECTED THE ROUTE UPDATE."
                                )

                                log(
                                    "No truck-control commands were sent."
                                )

                                finished =
                                    true

                                return

                            end


                            log(
                                "TF2 accepted the line update."
                            )


                            log(
                                "Rereading existing line entity..."
                            )


                            -- Give us the actual engine state
                            -- returned after command execution.

                            verifyUpdatedRoute(
                                sourceLineId,
                                hubStationGroup,
                                parkStationGroup,
                                expectedStopCount
                            )


                            finished =
                                true

                        end
                    )

                end
            )


    if not sendOk then

        commandPending =
            false

        log(
            "SEND COMMAND ERROR:"
        )

        log(
            tostring(
                sendError
            )
        )

        finished = true

        return

    end


    log(
        "Command sent."
    )


    log(
        "Waiting for TF2 callback..."
    )

end


-- ============================================================
-- UPDATE LOOP
-- ============================================================

local function update()

    updateCount =
        updateCount + 1


    if finished
        or commandPending
    then

        return

    end


    if updateCount == 1 then

        log(
            "========================================"
        )

        log(
            "EPOD-TD v"
                .. VERSION
                .. " loaded"
        )

        log(
            "Waiting before route injection..."
        )

        log(
            "========================================"
        )

    end


    if updateCount
        < START_DELAY_UPDATES
    then

        return

    end


    local ok, err =
        pcall(
            runTest
        )


    if not ok then

        log(
            "========================================"
        )

        log(
            "PARK INJECTION ERROR"
        )

        log(
            tostring(err)
        )

        log(
            "========================================"
        )


        finished = true

    end

end


-- ============================================================
-- TF2 GAME SCRIPT ENTRY
-- ============================================================

function data()

    return {

        update =
            update

    }

end