local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local hub_registry = require("epod_td.hub_registry")

local M = {}


-- ============================================================
-- OVERVIEW TAB (gui_manager.lua)
--
-- GUI ONLY -- reads existing modules, calculates nothing of its own.
-- First real tab built against the new framework; the rest start as
-- placeholders (see gui_tab_hubs.lua etc.) and get filled in the same
-- way over time.
-- ============================================================

function M.getLabel()
    return "OVERVIEW"
end


function M.refresh(rows, hubStationGroupId)

    if hubStationGroupId == nil then

        rows[1].label:setText(
            "No hub selected -- select a station on the map first.",
            560
        )

        return

    end

    local hubName = stations.getEntityName(hubStationGroupId)
    local managedLines = vehicles.getManagedLinesForStation(hubStationGroupId)
    local terminalCount = stations.getTerminalCount(hubStationGroupId)
    local autoRedistributeOn = hub_registry.isEnabled(hubStationGroupId)

    local totalVehicles = 0
    local totalWaiting = 0

    for _, lineInfo in ipairs(managedLines) do

        totalVehicles = totalVehicles + (lineInfo.vehicleCount or 0)

        local scanResult = demand.scan(lineInfo.id, hubStationGroupId)

        totalWaiting =
            totalWaiting + ((scanResult ~= nil and scanResult.totalWaiting) or 0)

    end

    local rowIndex = 1

    rows[rowIndex].label:setText(tostring(hubName), 560)
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Managed lines: " .. tostring(#managedLines),
        560
    )
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Total vehicles: " .. tostring(totalVehicles),
        560
    )
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Total waiting: " .. tostring(totalWaiting),
        560
    )
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Terminals: " .. tostring(terminalCount),
        560
    )
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Auto Redistribute: " .. (autoRedistributeOn and "ON" or "OFF"),
        560
    )

end


return M
