local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")

local M = {}


-- ============================================================
-- FLEET TAB (gui_manager.lua)
--
-- GUI ONLY -- reads vehicles.getManagedLinesForStation + demand.scan,
-- calculates nothing of its own. Same worst-backlog-first, idle-
-- capacity-flagged shape as the DEBUG "Fleet Balance Report" button,
-- for the single currently-focused hub rather than every enabled hub
-- at once, and without that report's per-vehicle carrying/capacity
-- breakdown (sumLineCargo) -- deliberately not duplicated here; that
-- stays the DEBUG report's own thing unless it's ever promoted into a
-- shared module.
-- ============================================================

function M.getLabel()
    return "FLEET"
end


function M.refresh(rows, hubStationGroupId)

    if hubStationGroupId == nil then

        rows[1].label:setText(
            "No hub selected -- select a station on the map first.",
            560
        )

        return

    end

    local ok, managedLines = pcall(vehicles.getManagedLinesForStation, hubStationGroupId)

    if not ok or managedLines == nil or #managedLines == 0 then

        rows[1].label:setText(
            "No managed services at this hub yet.",
            560
        )

        return

    end

    local entries = {}
    local totalVehicles = 0

    for _, lineInfo in ipairs(managedLines) do

        local scanResult = demand.scan(lineInfo.id, hubStationGroupId)
        local waiting = (scanResult ~= nil and scanResult.totalWaiting) or 0

        entries[#entries + 1] = {
            name = lineInfo.name,
            vehicleCount = lineInfo.vehicleCount,
            waiting = waiting
        }

        totalVehicles = totalVehicles + lineInfo.vehicleCount

    end

    table.sort(entries, function(a, b)
        return a.waiting > b.waiting
    end)

    local rowIndex = 1

    rows[rowIndex].label:setText(
        "Total fleet at this hub: " .. tostring(totalVehicles),
        560
    )
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Service                              Vehicles  Waiting",
        560
    )
    rowIndex = rowIndex + 1

    for _, entry in ipairs(entries) do

        if rowIndex > #rows then
            break
        end

        local idleFlag = entry.waiting == 0 and "  <-- idle" or ""

        rows[rowIndex].label:setText(
            string.format(
                "%-36s %9d %8d%s",
                tostring(entry.name):sub(1, 36),
                entry.vehicleCount,
                entry.waiting,
                idleFlag
            ),
            560
        )

        rowIndex = rowIndex + 1

    end

end


return M
