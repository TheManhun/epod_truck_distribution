local config = require("epod_td.config")
local lines = require("epod_td.lines")
local log = require("epod_td.log")

local M = {}

local function safeField(object, fieldName)
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


local function dumpComponentStructure(label, component)
    if component == nil then
        log.info(label .. " = nil")
        return
    end

    log.info(label .. " type: " .. type(component))

    local ok, entries = pcall(
        function()
            local result = {}
            for key, value in pairs(component) do
                result[#result + 1] = {
                    key = key,
                    value = value
                }
            end
            return result
        end
    )

    if not ok or type(entries) ~= "table" then
        log.info("  <structure not enumerable>")
        return
    end

    for _, entry in ipairs(entries) do
        local key = entry.key
        local value = entry.value
        local valueType = type(value)
        local valueText = tostring(value)

        if valueType == "table" then
            valueText = "table[" .. tostring(#value) .. "]"
        end

        log.info(
            "  " .. tostring(key) .. " = " .. valueText
        )
    end
end


local function inspectStationEntity(entityId, indexInGroup)
    if entityId == nil or entityId < 0 then
        log.info(
            "Station entry "
                .. tostring(indexInGroup)
                .. " is nil or invalid."
        )
        return
    end

    local ok, stationComponent = pcall(
        api.engine.getComponent,
        entityId,
        api.type.ComponentType.STATION
    )

    log.info(
        "STATION ENTITY "
            .. tostring(entityId)
            .. " (index "
            .. tostring(indexInGroup)
            .. ")"
    )

    local okName, stationName = pcall(
        game.interface.getName,
        entityId
    )

    if okName and stationName ~= nil and stationName ~= "" then
        log.info("station name: " .. tostring(stationName))
    else
        log.info("station name: unavailable")
    end

    if ok and stationComponent ~= nil then
        dumpComponentStructure("station component", stationComponent)

        local stationGroup = safeField(stationComponent, "stationGroup")
        local stationIndex = safeField(stationComponent, "station")
        local terminal = safeField(stationComponent, "terminal")
        local terminalCount = safeField(stationComponent, "terminalCount")
        local platform = safeField(stationComponent, "platform")
        local roadTerminal = safeField(stationComponent, "roadTerminal")
        local cargo = safeField(stationComponent, "cargo")
        local passenger = safeField(stationComponent, "passenger")

        log.info("stationGroup: " .. tostring(stationGroup))
        log.info("station index: " .. tostring(stationIndex))
        log.info("terminal: " .. tostring(terminal))
        log.info("terminalCount: " .. tostring(terminalCount))
        log.info("platform: " .. tostring(platform))
        log.info("roadTerminal: " .. tostring(roadTerminal))
        log.info("cargo: " .. tostring(cargo))
        log.info("passenger: " .. tostring(passenger))

        local terminals = safeField(stationComponent, "terminals")
        if terminals ~= nil then
            log.info("station terminals container: " .. tostring(type(terminals)))
            local terminalCountValue = lines.safeLength(terminals)
            log.info("station terminal count: " .. tostring(terminalCountValue))

            for terminalIndex = 1, terminalCountValue do
                local terminalEntry = terminals[terminalIndex]
                if terminalEntry ~= nil then
                    log.info(
                        "station terminal[" .. tostring(terminalIndex - 1) .. "] = "
                            .. tostring(terminalEntry)
                    )
                    dumpComponentStructure(
                        "station terminal component",
                        terminalEntry
                    )
                end
            end
        end
    else
        log.info("station component: unavailable")
    end
end


function M.printParkTerminalDiagnostic(managedLineId)
    if managedLineId == nil then
        log.info("========================================")
        log.info("EPOD-TD PARK TERMINAL DIAGNOSTIC")
        log.info("Managed line is nil. Diagnostic skipped.")
        log.info("========================================")
        return
    end

    local managedLine = lines.get(managedLineId)
    if managedLine == nil then
        log.info("========================================")
        log.info("EPOD-TD PARK TERMINAL DIAGNOSTIC")
        log.info("Managed line could not be read.")
        log.info("========================================")
        return
    end

    local parkStationGroupId,
        parkOccurrenceCount =
            M.findStationGroupOnLine(
                managedLine,
                config.PARK_NAME
            )

    log.info("========================================")
    log.info("EPOD-TD PARK TERMINAL DIAGNOSTIC")
    log.info("========================================")
    log.info("Park stationGroup: " .. tostring(parkStationGroupId))
    log.info("Park stationGroup name: " .. M.getEntityName(parkStationGroupId))
    log.info("Park occurrences on managed line: " .. tostring(parkOccurrenceCount))

    if parkStationGroupId == nil then
        log.info("No Park stationGroup found on the managed line.")
        log.info("========================================")
        return
    end

    local parkGroup = M.getStationGroup(parkStationGroupId)
    if parkGroup ~= nil then
        dumpComponentStructure("Park station group component", parkGroup)
    else
        log.info("Park stationGroup component: unavailable")
    end

    local stationCandidates = {
        "stations",
        "stationIds",
        "stationEntities",
        "stationsInGroup",
        "entries"
    }

    local stationEntries = nil

    for _, candidate in ipairs(stationCandidates) do
        local value = safeField(parkGroup, candidate)
        if value ~= nil then
            stationEntries = value
            log.info("Park station group field used: " .. candidate)
            break
        end
    end

    if stationEntries == nil then
        log.info("No station container could be safely read from the Park station group.")
    else
        local count = lines.safeLength(stationEntries)
        log.info("Park station count: " .. tostring(count))

        for index = 1, count do
            local stationEntityId = stationEntries[index]
            inspectStationEntity(stationEntityId, index - 1)
        end
    end

    local stops = lines.safeField(managedLine, "stops")
    local comparison = {}

    local parkStopIndexes = {0, 3, 6, 9, 12}

    for _, stopIndex in ipairs(parkStopIndexes) do
        local stop = stops and stops[stopIndex + 1] or nil
        local stationGroup = stop and safeField(stop, "stationGroup") or nil
        local station = stop and safeField(stop, "station") or nil
        local terminal = stop and safeField(stop, "terminal") or nil

        local record = {
            index = stopIndex,
            stationGroup = stationGroup,
            station = station,
            terminal = terminal
        }

        comparison[#comparison + 1] = record

        log.info(
            "PARK LINE OCCURRENCE " .. tostring(stopIndex)
        )
        log.info("line stopIndex: " .. tostring(stopIndex))
        log.info("stationGroup: " .. tostring(stationGroup))
        log.info("station: " .. tostring(station))
        log.info("terminal: " .. tostring(terminal))
    end

    log.info("PARK OCCURRENCE COMPARISON")
    for index = 2, #comparison do
        local previous = comparison[1]
        local current = comparison[index]
        local identical =
            previous.stationGroup == current.stationGroup
            and previous.station == current.station
            and previous.terminal == current.terminal

        log.info(
            tostring(previous.index)
                .. " vs "
                .. tostring(current.index)
                .. " physically identical: "
                .. tostring(identical)
        )
    end

    local hendonIndexes = {1, 4, 7, 10, 13}
    log.info("HENDON EAST OCCURRENCE COMPARISON")
    for _, stopIndex in ipairs(hendonIndexes) do
        local stop = stops and stops[stopIndex + 1] or nil
        local stationGroup = stop and safeField(stop, "stationGroup") or nil
        local station = stop and safeField(stop, "station") or nil
        local terminal = stop and safeField(stop, "terminal") or nil

        log.info(
            "HENDON OCCURRENCE " .. tostring(stopIndex)
        )
        log.info("line stopIndex: " .. tostring(stopIndex))
        log.info("stationGroup: " .. tostring(stationGroup))
        log.info("station: " .. tostring(station))
        log.info("terminal: " .. tostring(terminal))
    end

    local distinctParkTargetKeys = {}
    for _, record in ipairs(comparison) do
        if record.stationGroup ~= nil or record.station ~= nil or record.terminal ~= nil then
            local key =
                tostring(record.stationGroup)
                .. ":"
                .. tostring(record.station)
                .. ":"
                .. tostring(record.terminal)

            distinctParkTargetKeys[key] = true
        end
    end

    local distinctParkTargetCount = 0
    for _ in pairs(distinctParkTargetKeys) do
        distinctParkTargetCount = distinctParkTargetCount + 1
    end

    local parkTerminalStatus = "UNKNOWN"
    if distinctParkTargetCount == 0 then
        parkTerminalStatus = "UNKNOWN"
    elseif distinctParkTargetCount == 1 then
        parkTerminalStatus = "NO"
    else
        parkTerminalStatus = "YES"
    end

    log.info("PARK TERMINAL SUMMARY")
    log.info("Available physical Park stations: " .. tostring(distinctParkTargetCount))
    log.info("Available distinct Park terminals: " .. tostring(distinctParkTargetCount))
    log.info("Park line occurrences: " .. tostring(#comparison))
    log.info("Distinct physical targets used by those occurrences:")
    for key in pairs(distinctParkTargetKeys) do
        log.info("  " .. tostring(key))
    end
    log.info("CAN FIVE PARK BLOCKS USE DISTINCT TERMINALS: " .. parkTerminalStatus)

    if parkTerminalStatus == "YES" then
        log.info("Usable Park terminal indices appear to be distinct from the inspected data.")
    elseif parkTerminalStatus == "NO" then
        log.info("The inspected Park stop data shows the repeated Park occurrences collapse to the same physical stationGroup/station/terminal identity.")
    else
        log.info("The TF2 component data was insufficient to determine whether distinct Park terminals are available.")
    end

    log.info("========================================")
end


-- ============================================================
-- STATION GROUP TERMINAL DUMP
--
-- General-purpose, read-only: reuses inspectStationEntity (already
-- written, but only previously wired into the Park-specific
-- diagnostic above, so never independently confirmed against a
-- real multi-terminal station). Takes any stationGroupId directly
-- -- no line, no Park, no name dependence beyond what
-- inspectStationEntity itself already does for display purposes.
--
-- Exists to answer a concrete question raised live: after
-- line_splitter.lua created 5 new lines at Hendon East, all 5 (plus
-- the original line, plus Grain) ended up on the same terminal
-- while a second terminal sat unused, confirmed visually via the
-- game's own TERMINALS tab. This dumps the real terminalCount /
-- terminals data so a terminal-spreading fix can be built on
-- confirmed numbers instead of assumptions.
-- ============================================================

function M.dumpStationGroupTerminals(stationGroupId)
    log.info("========================================")
    log.info("STATION GROUP TERMINAL DUMP")
    log.info("========================================")

    if stationGroupId == nil or stationGroupId < 0 then
        log.info("Invalid stationGroupId.")
        log.info("========================================")
        return
    end

    local group = M.getStationGroup(stationGroupId)

    if group == nil then
        log.info("stationGroup component unavailable for " .. tostring(stationGroupId) .. ".")
        log.info("========================================")
        return
    end

    log.info("stationGroup: " .. tostring(stationGroupId))
    log.info("stationGroup name: " .. M.getEntityName(stationGroupId))
    dumpComponentStructure("station group component", group)

    local stationCandidates = {
        "stations",
        "stationIds",
        "stationEntities",
        "stationsInGroup",
        "entries"
    }

    local stationEntries = nil

    for _, candidate in ipairs(stationCandidates) do
        local value = safeField(group, candidate)
        if value ~= nil then
            stationEntries = value
            log.info("Station group field used: " .. candidate)
            break
        end
    end

    if stationEntries == nil then
        log.info("No station container could be safely read from this station group.")
        log.info("========================================")
        return
    end

    local count = lines.safeLength(stationEntries)
    log.info("Physical stations in group: " .. tostring(count))

    for index = 1, count do
        local stationEntityId = stationEntries[index]
        inspectStationEntity(stationEntityId, index - 1)
    end

    log.info("========================================")
end


-- ============================================================
-- TERMINAL COUNT FOR A STATION GROUP
--
-- Sums terminal counts across every physical STATION in the group
-- (reuses the same station-container field-candidate probing as
-- dumpStationGroupTerminals/M.dumpStationGroupTerminals above,
-- which already confirmed live that Hendon East's single physical
-- station carries a real, non-empty `terminals` container). Read-
-- only; needed by terminal_allocator.lua to know how many distinct
-- terminals are actually available to spread managed lines across,
-- rather than guessing a fixed number.
-- ============================================================

function M.getTerminalCount(stationGroupId)
    local group = M.getStationGroup(stationGroupId)

    if group == nil then
        return 0
    end

    local stationCandidates = {
        "stations",
        "stationIds",
        "stationEntities",
        "stationsInGroup",
        "entries"
    }

    local stationEntries = nil

    for _, candidate in ipairs(stationCandidates) do
        local value = safeField(group, candidate)
        if value ~= nil then
            stationEntries = value
            break
        end
    end

    if stationEntries == nil then
        return 0
    end

    local total = 0
    local count = lines.safeLength(stationEntries)

    for index = 1, count do
        local stationEntityId = stationEntries[index]

        if stationEntityId ~= nil and stationEntityId >= 0 then

            local ok, stationComponent =
                pcall(
                    api.engine.getComponent,
                    stationEntityId,
                    api.type.ComponentType.STATION
                )

            if ok and stationComponent ~= nil then
                local terminals = safeField(stationComponent, "terminals")
                total = total + lines.safeLength(terminals)
            end

        end

    end

    return total
end


-- ============================================================
-- HISTORICAL ITEMS LOADED / UNLOADED FOR A STATION GROUP
--
-- LIVE-CONFIRMED (see the destination station_group entity dumps
-- captured via vehicles.dumpEntityInfo): game.interface.getEntity()
-- on a STATION_GROUP returns itemsLoaded/itemsUnloaded tables with
-- a real running `_sum` field. A station whose itemsLoaded._sum has
-- been exactly 0 across its whole history has never once had
-- cargo picked up from it -- confirmed against 5 real town
-- destinations (Queens Road, Alexander Road, The Grove, Park
-- Avenue, Highfield Road: all itemsLoaded._sum == 0, all with real
-- nonzero itemsUnloaded) versus a real producer on the same hub
-- (Barrow-in-Furness Transfer: itemsLoaded._sum == 13661 GRAIN,
-- itemsUnloaded._sum == 0). This is the basis for hiding a
-- panel row only when it is structurally guaranteed to always read
-- 0, not just currently reading 0 -- see epod_truck_distribution.lua.
-- ============================================================

function M.getItemTotals(stationGroupId)
    if stationGroupId == nil or stationGroupId < 0 then
        return { loaded = 0, unloaded = 0 }
    end

    local ok, entity = pcall(game.interface.getEntity, stationGroupId)

    if not ok or entity == nil then
        return { loaded = 0, unloaded = 0 }
    end

    local loadedTable = safeField(entity, "itemsLoaded")
    local unloadedTable = safeField(entity, "itemsUnloaded")

    local loadedSum = loadedTable ~= nil and safeField(loadedTable, "_sum") or nil
    local unloadedSum = unloadedTable ~= nil and safeField(unloadedTable, "_sum") or nil

    return {
        loaded = loadedSum or 0,
        unloaded = unloadedSum or 0
    }
end


-- ============================================================
-- RECENT UNLOADED ACTIVITY (LAST MONTH)
--
-- getItemTotals above only ever reads the all-time _sum. This reads
-- itemsUnloaded._lastMonth._sum instead -- confirmed to exist and
-- be a real per-window total (Decision 28's deep dump). Used by
-- planner.lua to tell "this destination has never really received
-- anything" apart from "this destination is real and active but
-- just happens to show 0 waiting cargo at this exact instant" --
-- the second case should not be planned down to the bare floor just
-- because of a momentary reading (Decision 29).
-- ============================================================

function M.getRecentUnloadedTotal(stationGroupId)
    if stationGroupId == nil or stationGroupId < 0 then
        return 0
    end

    local ok, entity = pcall(game.interface.getEntity, stationGroupId)

    if not ok or entity == nil then
        return 0
    end

    local unloadedTable = safeField(entity, "itemsUnloaded")
    local lastMonthTable = unloadedTable ~= nil and safeField(unloadedTable, "_lastMonth") or nil
    local lastMonthSum = lastMonthTable ~= nil and safeField(lastMonthTable, "_sum") or nil

    return lastMonthSum or 0
end


-- ============================================================
-- UNLOADED CARGO TYPES (ALL-TIME)
--
-- Real cargo type names (e.g. "FOOD", "FUEL") this destination has
-- ever received, read from itemsUnloaded's top-level keys -- the
-- same set already proven to exist in the live dumps (Decision 28),
-- excluding the reserved _sum/_lastMonth/_lastYear keys.
--
-- Deliberately used for dispatcher.lua's vehicle-compatibility gate
-- INSTEAD OF demand.scan()'s per-destination cargoTypes: this comes
-- from game.interface.getEntity, the same API vehicles.lua's
-- getAllCapacities/isCompatibleWithCargoType already use (Decision
-- 27) -- confirmed matching string keys (FOOD, FUEL, CONSTRUCTION_
-- MATERIALS, etc., seen identically in both). demand.scan()'s
-- cargoTypes instead comes from api.engine.getComponent's raw
-- SIM_CARGO.cargoType field -- a different, lower-level API never
-- cross-checked against vehicle capacity keys. Mixing the two inside
-- a safety gate risked a silent format mismatch (every compatibility
-- check quietly returning false, and the Dispatcher refusing to
-- move anything without ever explaining why) -- not worth the risk
-- when a confirmed-matching alternative already exists.
-- ============================================================

local RESERVED_ITEM_HISTORY_KEYS = {
    _sum = true,
    _lastMonth = true,
    _lastYear = true
}

function M.getUnloadedCargoTypes(stationGroupId)

    local cargoTypes = {}

    if stationGroupId == nil or stationGroupId < 0 then
        return cargoTypes
    end

    local ok, entity = pcall(game.interface.getEntity, stationGroupId)

    if not ok or entity == nil then
        return cargoTypes
    end

    local unloadedTable = safeField(entity, "itemsUnloaded")

    if unloadedTable == nil then
        return cargoTypes
    end

    local okIter = pcall(function()

        for key, _ in pairs(unloadedTable) do

            if not RESERVED_ITEM_HISTORY_KEYS[key] then
                cargoTypes[#cargoTypes + 1] = key
            end

        end

    end)

    if not okIter then
        return {}
    end

    return cargoTypes

end


-- ============================================================
-- ITEM HISTORY DEEP DUMP -- one-off research
--
-- getItemTotals above only ever reads _sum. The raw entity dump
-- (EPOD-LOG.txt) already showed itemsLoaded/itemsUnloaded break
-- down by CARGO TYPE at the top level (e.g. FOOD=2482, FUEL=2853
-- alongside _sum), confirmed live -- that part needs no further
-- test. What's never been seen is what's actually inside the
-- _lastMonth/_lastYear sub-tables also present on that same
-- object -- the one-level-deep dumpEntityInfo only ever printed
-- their table address, not their contents. This answers IDEAS.md's
-- "Runtime Fleet Rebalancing" cargo-profile refinement: if
-- _lastMonth/_lastYear also break down by cargo type, the Planner
-- gets a ready-made recent-history signal for free instead of
-- needing new tracking.
-- ============================================================

local function dumpNestedTable(label, tableValue)

    if tableValue == nil then
        log.info("  " .. label .. " = <nil>")
        return
    end

    local okIter, iterErr =
        pcall(function()

            local parts = {}

            for key, value in pairs(tableValue) do
                parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
            end

            log.info("  " .. label .. " = { " .. table.concat(parts, ", ") .. " }")

        end)

    if not okIter then
        log.info("  " .. label .. " = <not enumerable: " .. tostring(iterErr) .. ">")
    end

end

function M.dumpItemHistory(stationGroupId, label)

    if stationGroupId == nil or stationGroupId < 0 then
        return
    end

    local ok, entity = pcall(game.interface.getEntity, stationGroupId)

    if not ok or entity == nil then
        log.info(tostring(label) .. ": could not read entity " .. tostring(stationGroupId))
        return
    end

    local loadedTable = safeField(entity, "itemsLoaded")
    local unloadedTable = safeField(entity, "itemsUnloaded")

    log.info("----------------------------------------")
    log.info("ITEM HISTORY DEEP DUMP: " .. tostring(label) .. " (id=" .. tostring(stationGroupId) .. ")")
    log.info("----------------------------------------")

    dumpNestedTable(
        "itemsLoaded._lastMonth",
        loadedTable ~= nil and safeField(loadedTable, "_lastMonth") or nil
    )

    dumpNestedTable(
        "itemsLoaded._lastYear",
        loadedTable ~= nil and safeField(loadedTable, "_lastYear") or nil
    )

    dumpNestedTable(
        "itemsUnloaded._lastMonth",
        unloadedTable ~= nil and safeField(unloadedTable, "_lastMonth") or nil
    )

    dumpNestedTable(
        "itemsUnloaded._lastYear",
        unloadedTable ~= nil and safeField(unloadedTable, "_lastYear") or nil
    )

    log.info("----------------------------------------")

end


function M.getStationGroup(stationGroupId)
    if stationGroupId == nil
        or stationGroupId < 0
    then
        return nil
    end

    local ok, group = pcall(
        api.engine.getComponent,
        stationGroupId,
        api.type.ComponentType.STATION_GROUP
    )

    if not ok then
        return nil
    end

    return group
end


function M.getEntityName(entityId)
    if entityId == nil
        or entityId < 0
    then
        return "UNKNOWN"
    end

    local ok, name = pcall(
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


-- ============================================================
-- FIND A NAMED STOP ON A LINE
-- ============================================================

function M.findStopByName(line, stationName)
    if line == nil then
        return nil
    end

    local stops =
        lines.safeField(line, "stops")

    if stops == nil then
        return nil
    end

    local count =
        lines.safeLength(stops)

    for index = 1, count do
        local stop = stops[index]

        if stop ~= nil then
            local stationGroup =
                lines.safeField(
                    stop,
                    "stationGroup"
                )

            if M.getEntityName(stationGroup)
                == stationName
            then
                return stop
            end
        end
    end

    return nil
end


function M.findStopByNameAnywhere(stationName)
    local allLines = game.interface.getLines()

    if allLines == nil then
        return nil, nil, nil
    end

    for _, lineId in ipairs(allLines) do
        local line = lines.get(lineId)

        if line ~= nil then
            local stop = M.findStopByName(line, stationName)

            if stop ~= nil then
                return line, stop, lineId
            end
        end
    end

    return nil, nil, nil
end


function M.describeStop(stop)
    if stop == nil then
        return {
            name = "UNKNOWN",
            stationGroup = nil,
            station = nil,
            terminal = nil
        }
    end

    return {
        name = M.getEntityName(
            lines.safeField(stop, "stationGroup")
        ),
        stationGroup = lines.safeField(stop, "stationGroup"),
        station = lines.safeField(stop, "station"),
        terminal = lines.safeField(stop, "terminal")
    }
end


function M.logTwoParkDiscovery()
    log.info("========================================")
    log.info("TWO PARK SETLINE TEST")
    log.info("========================================")

    local discovered = {}

    for _, parkName in ipairs({
        "EPOD-TD Truck Park",
        "EPOD-TD Truck Park B"
    }) do
        local line, stop, lineId = M.findStopByNameAnywhere(parkName)
        local summary = M.describeStop(stop)

        discovered[#discovered + 1] = {
            name = parkName,
            lineId = lineId,
            summary = summary
        }

        log.info("PARK " .. tostring(#discovered))
        log.info("name: " .. tostring(parkName))
        log.info("stationGroup: " .. tostring(summary.stationGroup))
        log.info("station: " .. tostring(summary.station))
        log.info("terminal: " .. tostring(summary.terminal))
    end

    local aStationGroup = discovered[1] and discovered[1].summary.stationGroup or nil
    local bStationGroup = discovered[2] and discovered[2].summary.stationGroup or nil
    local distinct =
        aStationGroup ~= nil
        and bStationGroup ~= nil
        and aStationGroup ~= bStationGroup

    log.info("PARKS PHYSICALLY DISTINCT: " .. tostring(distinct))

    if not distinct then
        log.info("ABORT: Park A and Park B are not physically distinct; leaving all game state unchanged.")
    end

    log.info("========================================")

    return distinct, discovered
end


-- ============================================================
-- FIND STATION GROUP + NUMBER OF OCCURRENCES
-- ============================================================

function M.findStationGroupOnLine(
    line,
    stationName
)
    if line == nil then
        return nil, 0
    end

    local stops =
        lines.safeField(line, "stops")

    if stops == nil then
        return nil, 0
    end

    local count =
        lines.safeLength(stops)

    local stationGroupId = nil
    local occurrences = 0

    for index = 1, count do
        local stop = stops[index]

        if stop ~= nil then
            local group =
                lines.safeField(
                    stop,
                    "stationGroup"
                )

            if M.getEntityName(group)
                == stationName
            then
                stationGroupId = group
                occurrences =
                    occurrences + 1
            end
        end
    end

    return stationGroupId,
        occurrences
end


return M