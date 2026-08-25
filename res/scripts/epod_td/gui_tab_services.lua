local planner = require("epod_td.planner")

local M = {}


-- ============================================================
-- SERVICES TAB (gui_manager.lua)
--
-- GUI ONLY -- reads planner.calculateTargetAllocation, calculates
-- nothing of its own. One row per managed line at the focused hub:
-- current vehicles, the Planner's own target, waiting cargo, and the
-- delta between them -- exactly the numbers the Planner already
-- computes for real dispatch decisions (Decisions 29/30), just shown
-- instead of only logged.
-- ============================================================

function M.getLabel()
    return "SERVICES"
end


function M.refresh(rows, hubStationGroupId)

    if hubStationGroupId == nil then

        rows[1].label:setText(
            "No hub selected -- select a station on the map first.",
            560
        )

        return

    end

    local ok, plan = pcall(planner.calculateTargetAllocation, hubStationGroupId)

    if not ok or plan == nil then

        rows[1].label:setText(
            "SERVICES: could not calculate the fleet plan for this hub.",
            560
        )

        return

    end

    if #plan.lines == 0 then

        rows[1].label:setText(
            "No managed services at this hub yet.",
            560
        )

        return

    end

    -- Worst-backlog-first, same convention as the DEBUG Fleet Balance
    -- Report -- the line needing the most attention should be the
    -- first thing the player sees, not wherever it happens to fall in
    -- scan order.
    local sortedLines = {}

    for _, lineInfo in ipairs(plan.lines) do
        sortedLines[#sortedLines + 1] = lineInfo
    end

    table.sort(sortedLines, function(a, b)
        return a.waiting > b.waiting
    end)

    local rowIndex = 1

    rows[rowIndex].label:setText(
        "Service                              Current  Target  Waiting  Delta",
        560
    )
    rowIndex = rowIndex + 1

    for _, lineInfo in ipairs(sortedLines) do

        if rowIndex > #rows then
            break
        end

        local deltaText =
            lineInfo.delta > 0
                and ("+" .. tostring(lineInfo.delta))
                or tostring(lineInfo.delta)

        rows[rowIndex].label:setText(
            string.format(
                "%-36s %7d %7d %8d %7s",
                tostring(lineInfo.name):sub(1, 36),
                lineInfo.currentVehicleCount,
                lineInfo.targetVehicleCount,
                lineInfo.waiting,
                deltaText
            ),
            560
        )

        rowIndex = rowIndex + 1

    end

end


return M
