local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")

local M = {}


-- ============================================================
-- CARGO TAB (gui_manager.lua)
--
-- GUI ONLY -- reads demand.scan's per-destination cargoTypes
-- breakdown (already computed for real dispatch decisions elsewhere),
-- totaled by cargo type across every managed line at the focused hub.
-- Calculates nothing of its own beyond summing what demand.scan
-- already reports.
-- ============================================================

function M.getLabel()
    return "CARGO"
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

    local totalsByCargoType = {}

    for _, lineInfo in ipairs(managedLines) do

        local scanResult = demand.scan(lineInfo.id, hubStationGroupId)

        if scanResult ~= nil and scanResult.destinations ~= nil then

            for _, destination in pairs(scanResult.destinations) do

                if destination.cargoTypes ~= nil then

                    for cargoType, amount in pairs(destination.cargoTypes) do

                        totalsByCargoType[cargoType] =
                            (totalsByCargoType[cargoType] or 0) + amount

                    end

                end

            end

        end

    end

    local entries = {}

    for cargoType, amount in pairs(totalsByCargoType) do

        entries[#entries + 1] = {
            cargoType = cargoType,
            displayName = demand.getCargoTypeDisplayName(cargoType),
            amount = amount
        }

    end

    if #entries == 0 then

        rows[1].label:setText(
            "No waiting cargo detected at this hub right now.",
            560
        )

        return

    end

    table.sort(entries, function(a, b)
        return a.amount > b.amount
    end)

    local rowIndex = 1

    rows[rowIndex].label:setText(
        "Cargo Type                          Waiting",
        560
    )
    rowIndex = rowIndex + 1

    for _, entry in ipairs(entries) do

        if rowIndex > #rows then
            break
        end

        rows[rowIndex].label:setText(
            string.format(
                "%-36s %8d",
                tostring(entry.displayName):sub(1, 36),
                entry.amount
            ),
            560
        )

        rowIndex = rowIndex + 1

    end

end


return M
