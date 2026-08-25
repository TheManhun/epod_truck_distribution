local M = {}


-- ============================================================
-- SERVICES TAB (gui_manager.lua) -- PLACEHOLDER
--
-- GUI_Plan.md: per-line table (Managed | Service | Current | Target |
-- Waiting | Delta) for the focused hub, sourced from
-- vehicles.getManagedLinesForStation + planner.calculateTargetAllocation.
-- Not built yet.
-- ============================================================

function M.getLabel()
    return "SERVICES"
end


function M.refresh(rows, hubStationGroupId)

    rows[1].label:setText(
        "SERVICES -- not built yet.",
        560
    )

end


return M
