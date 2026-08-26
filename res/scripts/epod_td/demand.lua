-- ============================================================
-- TF2 Truck Distribution
-- demand.lua
--
-- DESTINATION DEMAND READER
--
-- READ ONLY
--
-- Reads cargo currently waiting on a supplied distribution line
-- and groups it by destination.
--
-- IMPORTANT:
-- Behaviour is entity-ID driven.
--
-- It does NOT depend on:
--   * line names
--   * station names
--   * hub names
--   * park names
--
-- Names are fetched only for display/logging.
--
-- DOES NOT:
--   * modify cargo
--   * modify routes
--   * assign vehicles
--   * dispatch vehicles
-- ============================================================

local log = require("epod_td.log")
local stations = require("epod_td.stations")

local M = {}


-- ============================================================
-- SAFE ACCESS HELPERS
-- ============================================================

local function safeField(object, fieldName)

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


local function safeLength(sequence)

    if sequence == nil then
        return 0
    end

    local ok, length =
        pcall(
            function()
                return #sequence
            end
        )

    if ok and type(length) == "number" then
        return length
    end

    return 0

end


local function safeIndex(sequence, index)

    if sequence == nil then
        return nil
    end

    local ok, value =
        pcall(
            function()
                return sequence[index]
            end
        )

    if ok then
        return value
    end

    return nil

end


-- ============================================================
-- ENTITY / LINE HELPERS
-- ============================================================

-- LIVE-CONFIRMED real bug (screenshot, Decision 105 follow-up): this
-- used to be its own raw game.interface.getName call with no
-- stripping at all -- a second, independent implementation of what
-- stations.getEntityName already does, drifted apart from it. Any
-- destination fed through this into line_splitter.lua's
-- "hubName .. ↔ .. destination.name" (line 151-155) skipped both the
-- "● " hub-prefix strip AND the newer "* Industry <-> Hub - NN"
-- strip, so a hub-linked or industry-linked destination's own
-- decorated name got embedded wholesale, re-showing the hub a second
-- time. Delegates to the shared, now-fixed stations.getEntityName
-- instead of maintaining a second copy of the same logic.
local function getEntityName(entityId)

    if type(entityId) ~= "number" then
        return "UNKNOWN"
    end

    return stations.getEntityName(entityId)

end


local function getLineName(lineId)

    if type(lineId) ~= "number"
        or lineId < 0
    then
        return "UNKNOWN LINE"
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

    return "Line " .. tostring(lineId)

end


local function getLine(lineId)

    if type(lineId) ~= "number"
        or lineId < 0
    then
        return nil
    end

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
-- CARGO TYPE ACCESS
--
-- We deliberately do not hard-code cargo names here.
--
-- The scanner returns TF2's real cargo type ID.
-- Once we prove the demand data is correct, the UI layer can
-- resolve proper native cargo icons/names using a proven TF2 API.
-- ============================================================

local function getCargoType(entityId)

    local ok, cargo =
        pcall(
            api.engine.getComponent,
            entityId,
            api.type.ComponentType.SIM_CARGO
        )

    if not ok
        or cargo == nil
    then
        return nil
    end

    local cargoType =
        safeField(
            cargo,
            "cargoType"
        )

    if cargoType ~= nil then
        return cargoType
    end

    return safeField(
        cargo,
        "type"
    )

end


function M.getCargoTypeLabel(cargoType)

    if cargoType == nil then
        return "Unknown cargo"
    end

    return "CargoType "
        .. tostring(cargoType)

end


-- ============================================================
-- CARGO TYPE NAME / ICON RESOLUTION
--
-- api.res.cargoTypeRep.get(cargoType) resolves the numeric cargo
-- type index (as read off SIM_CARGO above) to its base-game
-- definition table. This mirrors the proven api.res.bridgeTypeRep
-- / tunnelTypeRep pattern used by the base game's own
-- selectortooltip.lua, which reads a .name field off the returned
-- table the same way.
--
-- NOT YET independently confirmed live in this mod. The literal
-- string "cargoTypeRep" is present in the compiled game binary
-- (TransportFever2.exe) and the sibling *TypeRep.get() pattern is
-- proven, but the exact shape of the returned table (.id, .name)
-- has not been dumped from a live session. Wrapped in pcall and
-- logged once per cargo type so the next EPOD-TD session capture
-- can confirm it, same evidence-gathering approach as the ROAD
-- carrier fix in vehicles.lua.
--
-- Icon path convention ("ui/" + path inside res/textures/ui/ui.zip)
-- is confirmed from the base game's own construction Lua
-- (station/street/modular_terminal.con builds icon paths the same
-- way, e.g. "ui/construction/station/street/cargo_era_c.tga").
-- Icon files themselves (hud/cargo_<lowercase id>_small.tga) are
-- confirmed present in res/textures/ui/ui.zip for every core cargo
-- type.
-- ============================================================

local reportedCargoTypeLookupFailure = {}

function M.getCargoTypeInfo(cargoType)

    if cargoType == nil then
        return nil
    end

    local ok, cargoTypeInfo =
        pcall(
            api.res.cargoTypeRep.get,
            cargoType
        )

    if not ok or cargoTypeInfo == nil then

        if not reportedCargoTypeLookupFailure[cargoType] then

            reportedCargoTypeLookupFailure[cargoType] = true

            log.info(
                "CARGO TYPE LOOKUP FAILED for cargoType "
                    .. tostring(cargoType)
                    .. ": "
                    .. tostring(cargoTypeInfo)
            )

        end

        return nil

    end

    return cargoTypeInfo

end


-- Falls back to M.getCargoTypeLabel when the real name is unavailable.
function M.getCargoTypeDisplayName(cargoType)

    local info = M.getCargoTypeInfo(cargoType)

    if info == nil then
        return M.getCargoTypeLabel(cargoType)
    end

    local name = safeField(info, "name")

    if name == nil or name == "" then
        return M.getCargoTypeLabel(cargoType)
    end

    return name

end


-- Decision 78: the raw uppercase constant name (e.g. "IRON_ORE"),
-- same value getCargoTypeIconPath already builds icon paths from.
-- Needed because demand.scan's cargoTypes map is keyed by the raw
-- numeric SIM_CARGO type id, while stations.lua's itemsLoaded/
-- itemsUnloaded fields are keyed by this string constant directly --
-- two different key spaces for the same real cargo type. Confirmed
-- live (Cargo Balance Inspector's first run) that mixing them without
-- this conversion produces duplicate rows for the same cargo type
-- under two different-looking names ("Iron ore" vs "CargoType
-- IRON_ORE") instead of one correctly merged row. Returns nil when
-- the cargo type can't be resolved, same convention as
-- getCargoTypeIconPath.
function M.getCargoTypeId(cargoType)

    local info = M.getCargoTypeInfo(cargoType)

    if info == nil then
        return nil
    end

    local id = safeField(info, "id")

    if id == nil or id == "" then
        return nil
    end

    return id

end


-- Returns nil (not a guessed path) when the cargo type or its id
-- field cannot be resolved; callers must fall back to text.
function M.getCargoTypeIconPath(cargoType)

    local info = M.getCargoTypeInfo(cargoType)

    if info == nil then
        return nil
    end

    local id = safeField(info, "id")

    if id == nil or id == "" then
        return nil
    end

    return "ui/hud/cargo_"
        .. tostring(id):lower()
        .. "_small.tga"

end


-- Decision 79: shared per-destination cargo-type breakdown, extracted
-- from the Cargo Balance Inspector (Decisions 77/78) so the live
-- CARGO tab (gui_tab_cargo.lua) can show the same comparatively-
-- under-served signal instead of it only existing in a DEBUG report
-- file. Merges scan()'s numeric-keyed waiting cargo with
-- stations.getUnloadedAmountsByType's string-keyed all-time history
-- (Decision 78's key-space fix), sorts worst-served-first, and flags
-- anything at or below 25% of the destination's busiest type -- same
-- threshold, same relative-only caveat as the original inspector.
-- Returns nil when the destination has fewer than 2 real cargo types
-- (nothing to compare).
function M.buildDestinationCargoRows(destination)

    local waitingByType = {}
    local displayNameByKey = {}

    for cargoType, amount in pairs(destination.cargoTypes or {}) do

        local normalizedKey =
            M.getCargoTypeId(cargoType) or ("unresolved:" .. tostring(cargoType))

        waitingByType[normalizedKey] = (waitingByType[normalizedKey] or 0) + amount
        displayNameByKey[normalizedKey] = M.getCargoTypeDisplayName(cargoType)

    end

    local okUnloaded, unloadedByType =
        pcall(stations.getUnloadedAmountsByType, destination.stationGroup)

    if not okUnloaded then
        unloadedByType = {}
    end

    local allTypes = {}

    for cargoType, _ in pairs(waitingByType) do
        allTypes[cargoType] = true
    end

    for cargoType, _ in pairs(unloadedByType) do
        allTypes[cargoType] = true
    end

    local typeCount = 0

    for _ in pairs(allTypes) do
        typeCount = typeCount + 1
    end

    if typeCount < 2 then
        return nil
    end

    local rows = {}

    for cargoType, _ in pairs(allTypes) do

        -- displayNameByKey only has an entry when this cargo type was
        -- seen on the waiting side (the only side that resolves a
        -- real name via cargoTypeRep -- Decision 78). A type seen
        -- only in all-time unloaded history has no resolvable name;
        -- fall back to a prettified version of the raw constant
        -- ("IRON_ORE" -> "Iron Ore").
        local displayName = displayNameByKey[cargoType]

        if displayName == nil then

            displayName =
                tostring(cargoType)
                    :gsub("_", " ")
                    :gsub("(%a)([%w']*)", function(first, rest)
                        return first:upper() .. rest:lower()
                    end)

        end

        rows[#rows + 1] = {
            cargoType = cargoType,
            displayName = displayName,
            waiting = waitingByType[cargoType] or 0,
            unloaded = unloadedByType[cargoType] or 0
        }

    end

    table.sort(rows, function(a, b)
        return a.waiting > b.waiting
    end)

    local maxWaiting = 0

    for _, row in ipairs(rows) do

        if row.waiting > maxWaiting then
            maxWaiting = row.waiting
        end

    end

    for _, row in ipairs(rows) do
        row.underServed = maxWaiting > 0 and row.waiting <= maxWaiting * 0.25
    end

    return rows

end


-- ============================================================
-- DESTINATION MAP
--
-- Bucket EVERY stop on the line, including the hub's own stop
-- occurrence(s) -- not just stops structurally adjacent to a hub
-- occurrence, as an earlier version of this function required.
--
-- That earlier hub-adjacency requirement created a real blind
-- spot: cargo waiting somewhere on the line with lineStop1 pointing
-- back at the hub itself was silently excluded, because the hub
-- was never registered as a valid destination bucket. That meant
-- "how much is waiting at the OTHER station on this line" (e.g.
-- cargo queued to travel FROM a destination BACK TO the hub) was
-- invisible to the scan, even though SIM_ENTITY_AT_TERMINAL already
-- has that data.
--
-- This matters because a connected TF2 line is a loop, not a fixed
-- one-way pipe -- see IDEAS.md's "Connected Distribution Network"
-- entry. A line's demand pressure can exist in either direction,
-- and the hub is itself just another stop on the loop that can
-- have cargo waiting to travel toward it.
--
-- hubStationGroupId is no longer used to decide which stops
-- qualify as buckets (every stop does); it is kept as a parameter
-- because callers still pass it, and it remains meaningful context
-- for whoever reads the result. Multiple stop occurrences of the
-- same physical stationGroup (e.g. the hub appearing more than once
-- on a route shaped like Hub/Dest/Hub/Dest/...) are already merged
-- downstream in buildStationGroupSummary, so registering every
-- occurrence individually here is safe.
-- ============================================================

local function buildDestinationMap(
    line,
    hubStationGroupId
)

    local destinations = {}

    if line == nil
        or type(hubStationGroupId) ~= "number"
        or hubStationGroupId < 0
    then
        return destinations
    end

    local stops =
        safeField(
            line,
            "stops"
        )

    local stopCount =
        safeLength(
            stops
        )

    if stopCount < 2 then
        return destinations
    end


    for luaIndex = 1, stopCount do

        local stop =
            safeIndex(
                stops,
                luaIndex
            )

        if stop ~= nil then

            local stationGroup =
                safeField(
                    stop,
                    "stationGroup"
                )

            if type(stationGroup) == "number"
                and stationGroup >= 0
            then

                -- TF2's lineStop references are zero-based.
                -- Lua access above is one-based.

                local lineStopIndex =
                    luaIndex - 1

                destinations[
                    lineStopIndex
                ] = {

                    stopIndex =
                        lineStopIndex,

                    stationGroup =
                        stationGroup,

                    name =
                        getEntityName(
                            stationGroup
                        ),

                    total =
                        0,

                    cargoTypes =
                        {}

                }

            end

        end

    end


    return destinations

end


-- ============================================================
-- AGGREGATE DESTINATIONS BY STATION GROUP
--
-- A route may theoretically contain the same destination more
-- than once. The UI normally wants one row per destination.
-- ============================================================

local function buildStationGroupSummary(destinations)

    local summary = {}

    for stopIndex, destination
        in pairs(
            destinations
        )
    do

        if destination ~= nil
            and type(destination.stationGroup)
                == "number"
        then

            local stationGroup =
                destination.stationGroup

            local record =
                summary[
                    stationGroup
                ]

            if record == nil then

                record = {

                    stationGroup =
                        stationGroup,

                    name =
                        destination.name,

                    total =
                        0,

                    cargoTypes =
                        {},

                    stopIndices =
                        {}

                }

                summary[
                    stationGroup
                ] =
                    record

            end

            record.stopIndices[
                #record.stopIndices + 1
            ] =
                stopIndex

        end

    end

    return summary

end


-- ============================================================
-- ADD ONE WAITING CARGO ENTITY
-- ============================================================

local function addCargoToDestination(
    result,
    destination,
    entityId
)

    destination.total =
        destination.total + 1

    result.totalWaiting =
        result.totalWaiting + 1

    result.matchedCargoEntities =
        result.matchedCargoEntities + 1


    local cargoType =
        getCargoType(
            entityId
        )

    if cargoType ~= nil then

        destination.cargoTypes[
            cargoType
        ] =
            (
                destination.cargoTypes[
                    cargoType
                ]
                or 0
            )
            + 1

    end

end


-- ============================================================
-- BUILD AGGREGATED DESTINATION TOTALS
-- ============================================================

local function populateStationGroupSummary(result)

    for _, destination
        in pairs(
            result.destinations
        )
    do

        if destination ~= nil then

            local summary =
                result.byStationGroup[
                    destination.stationGroup
                ]

            if summary ~= nil then

                summary.total =
                    summary.total
                    + (
                        destination.total
                        or 0
                    )


                if destination.cargoTypes ~= nil then

                    for cargoType, count
                        in pairs(
                            destination.cargoTypes
                        )
                    do

                        summary.cargoTypes[
                            cargoType
                        ] =
                            (
                                summary.cargoTypes[
                                    cargoType
                                ]
                                or 0
                            )
                            + count

                    end

                end

            end

        end

    end

end


-- ============================================================
-- SCAN WAITING CARGO
--
-- Parameters:
--
-- lineId
--     Numeric TF2 LINE entity.
--
-- hubStationGroupId
--     Numeric stationGroup representing the selected distribution
--     hub.
--
-- Cargo is matched using:
--
--     SIM_ENTITY_AT_TERMINAL.line
--     SIM_ENTITY_AT_TERMINAL.lineStop1
--
-- lineStop1 identifies the cargo's destination stop on the line.
-- ============================================================

function M.scan(
    lineId,
    hubStationGroupId
)

    local result = {

        lineId =
            lineId,

        lineName =
            getLineName(
                lineId
            ),

        hubStationGroup =
            hubStationGroupId,

        hubName =
            getEntityName(
                hubStationGroupId
            ),

        totalWaiting =
            0,

        matchedCargoEntities =
            0,

        destinations =
            {},

        byStationGroup =
            {},

        error =
            nil

    }


    if type(lineId) ~= "number"
        or lineId < 0
    then

        result.error =
            "Invalid managed line entity."

        return result

    end


    if type(hubStationGroupId) ~= "number"
        or hubStationGroupId < 0
    then

        result.error =
            "Invalid hub stationGroup entity."

        return result

    end


    local line =
        getLine(
            lineId
        )

    if line == nil then

        result.error =
            "Unable to read LINE component."

        return result

    end


    result.destinations =
        buildDestinationMap(
            line,
            hubStationGroupId
        )


    result.byStationGroup =
        buildStationGroupSummary(
            result.destinations
        )


    -- --------------------------------------------------------
    -- Walk every entity currently associated with a terminal.
    --
    -- This is READ ONLY.
    -- --------------------------------------------------------

    local ok, err =
        pcall(
            function()

                api.engine.forEachEntityWithComponent(

                    function(
                        entityId,
                        atTerminal
                    )

                        if atTerminal == nil then
                            return
                        end


                        local cargoLine =
                            safeField(
                                atTerminal,
                                "line"
                            )

                        if cargoLine ~= lineId then
                            return
                        end


                        local destinationStop =
                            safeField(
                                atTerminal,
                                "lineStop1"
                            )

                        if destinationStop == nil then
                            return
                        end


                        local destination =
                            result.destinations[
                                destinationStop
                            ]

                        if destination == nil then
                            return
                        end


                        addCargoToDestination(
                            result,
                            destination,
                            entityId
                        )

                    end,

                    api.type.ComponentType
                        .SIM_ENTITY_AT_TERMINAL

                )

            end
        )


    if not ok then

        result.error =
            "Cargo scan error: "
            .. tostring(err)

        return result

    end


    populateStationGroupSummary(
        result
    )


    return result

end


-- ============================================================
-- GET ONE DESTINATION FROM A SCAN RESULT
--
-- Convenience helper for the UI.
-- ============================================================

function M.getDestination(
    scanResult,
    stationGroupId
)

    if scanResult == nil
        or scanResult.byStationGroup == nil
        or type(stationGroupId) ~= "number"
    then
        return nil
    end

    return scanResult.byStationGroup[
        stationGroupId
    ]

end


-- ============================================================
-- READ-ONLY DIAGNOSTIC REPORT
--
-- This is deliberately parameterised too.
--
-- No configured line/station name is used.
-- ============================================================

function M.printReport(
    lineId,
    hubStationGroupId
)

    local demand =
        M.scan(
            lineId,
            hubStationGroupId
        )


    log.separator()

    log.info(
        "DESTINATION DEMAND REPORT"
    )

    log.info(
        "Managed line: "
        .. tostring(
            demand.lineName
        )
        .. " | entity="
        .. tostring(
            demand.lineId
        )
    )

    log.info(
        "Hub: "
        .. tostring(
            demand.hubName
        )
        .. " | stationGroup="
        .. tostring(
            demand.hubStationGroup
        )
    )


    if demand.error ~= nil then

        log.error(
            demand.error
        )

        log.separator()

        return demand

    end


    log.separator()


    local orderedDestinations = {}

    for _, destination
        in pairs(
            demand.byStationGroup
        )
    do

        orderedDestinations[
            #orderedDestinations + 1
        ] =
            destination

    end


    table.sort(
        orderedDestinations,
        function(a, b)

            local aIndex =
                a.stopIndices[1]
                or 999999

            local bIndex =
                b.stopIndices[1]
                or 999999

            return aIndex < bIndex

        end
    )


    for _, destination
        in ipairs(
            orderedDestinations
        )
    do

        log.info(
            tostring(
                destination.name
            )
            .. " | "
            .. tostring(
                destination.total
            )
            .. " waiting"
        )


        local cargoTypes = {}

        for cargoType, count
            in pairs(
                destination.cargoTypes
            )
        do

            cargoTypes[
                #cargoTypes + 1
            ] = {

                cargoType =
                    cargoType,

                count =
                    count

            }

        end


        table.sort(
            cargoTypes,
            function(a, b)

                return tostring(
                    a.cargoType
                )
                    <
                    tostring(
                        b.cargoType
                    )

            end
        )


        for _, cargo
            in ipairs(
                cargoTypes
            )
        do

            log.info(
                "  "
                .. M.getCargoTypeLabel(
                    cargo.cargoType
                )
                .. ": "
                .. tostring(
                    cargo.count
                )
            )

        end


        log.info(
            "  stationGroup: "
            .. tostring(
                destination.stationGroup
            )
        )

        log.separator()

    end


    log.info(
        "TOTAL WAITING: "
        .. tostring(
            demand.totalWaiting
        )
    )

    log.info(
        "Matched cargo entities: "
        .. tostring(
            demand.matchedCargoEntities
        )
    )

    log.separator()


    return demand

end


return M