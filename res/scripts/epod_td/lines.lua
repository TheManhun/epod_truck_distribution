local M = {}

-- ============================================================
-- SAFE NATIVE USERDATA ACCESS
-- ============================================================

function M.safeField(object, fieldName)
    if object == nil then
        return nil
    end

    local ok, value = pcall(
        function()
            return object[fieldName]
        end
    )

    if ok then
        return value
    end

    return nil
end


function M.safeLength(object)
    if object == nil then
        return 0
    end

    local ok, length = pcall(
        function()
            return #object
        end
    )

    if ok and length ~= nil then
        return length
    end

    return 0
end


-- ============================================================
-- LINE ACCESS
-- ============================================================

function M.get(lineId)
    if lineId == nil or lineId < 0 then
        return nil
    end

    local ok, line = pcall(
        api.engine.getComponent,
        lineId,
        api.type.ComponentType.LINE
    )

    if not ok or line == nil then
        return nil
    end

    return line
end


function M.getStops(lineId)
    local line = M.get(lineId)

    if not line then
        return nil
    end

    return M.safeField(line, "stops")
end


function M.getStopCount(lineId)
    local stops = M.getStops(lineId)

    return M.safeLength(stops)
end


function M.getName(lineId)
    if lineId == nil or lineId < 0 then
        return "NO LINE"
    end

    local ok, name = pcall(
        game.interface.getName,
        lineId
    )

    if ok and name ~= nil and name ~= "" then
        return name
    end

    return "Line " .. tostring(lineId)
end


function M.findByName(name)
    local allLines = game.interface.getLines()

    if allLines == nil then
        return nil
    end

    for _, lineId in ipairs(allLines) do
        if M.getName(lineId) == name then
            return lineId
        end
    end

    return nil
end


-- ============================================================
-- NATIVE VECTOR COPYING
-- ============================================================

function M.copyNativeSequence(source, destination)
    if source == nil or destination == nil then
        return
    end

    local count = M.safeLength(source)

    for index = 1, count do
        local value = source[index]

        if value ~= nil then
            local ok = pcall(
                function()
                    destination[#destination + 1] = value
                end
            )

            if not ok then
                -- Some TF2 native vector bindings may not
                -- support append this way.
                --
                -- Do not crash the complete line rewrite.
                return
            end
        end
    end
end


-- ============================================================
-- COPY NATIVE STOP
-- ============================================================

function M.makeNativeStopCopy(sourceStop)
    local stop = api.type.Line.Stop.new()

    stop.stationGroup =
        M.safeField(sourceStop, "stationGroup")

    stop.station =
        M.safeField(sourceStop, "station")

    stop.terminal =
        M.safeField(sourceStop, "terminal")


    local loadMode =
        M.safeField(sourceStop, "loadMode")

    if loadMode ~= nil then
        stop.loadMode = loadMode
    end


    local minWaitingTime =
        M.safeField(sourceStop, "minWaitingTime")

    if minWaitingTime ~= nil then
        stop.minWaitingTime = minWaitingTime
    end


    local maxWaitingTime =
        M.safeField(sourceStop, "maxWaitingTime")

    if maxWaitingTime ~= nil then
        stop.maxWaitingTime = maxWaitingTime
    end


    local sourceWaypoints =
        M.safeField(sourceStop, "waypoints")

    local destinationWaypoints =
        M.safeField(stop, "waypoints")

    M.copyNativeSequence(
        sourceWaypoints,
        destinationWaypoints
    )


    local sourceAlternatives =
        M.safeField(
            sourceStop,
            "alternativeTerminals"
        )

    local destinationAlternatives =
        M.safeField(
            stop,
            "alternativeTerminals"
        )

    M.copyNativeSequence(
        sourceAlternatives,
        destinationAlternatives
    )


    local how =
        M.safeField(sourceStop, "how")

    if how ~= nil then
        pcall(
            function()
                stop.how = how
            end
        )
    end

    return stop
end


-- ============================================================
-- APPEND NATIVE STOP
-- ============================================================

function M.appendNativeStop(nativeStops, nativeStop)
    local before = M.safeLength(nativeStops)

    local ok, err = pcall(
        function()
            nativeStops[before + 1] =
                nativeStop
        end
    )

    if not ok then
        return false, tostring(err)
    end

    local after = M.safeLength(nativeStops)

    if after ~= before + 1 then
        return false,
            "Native stop vector length did not increase."
    end

    return true, nil
end


return M