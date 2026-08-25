local M = {}


-- ============================================================
-- TERMINALS TAB (gui_manager.lua) -- PLACEHOLDER
--
-- GUI_Plan.md: per-terminal line assignment for the focused hub
-- (stations.getTerminalCount + terminal_allocator.lua's own
-- demand-ranked assignment), plus a "Reorganize Terminals" button
-- calling terminal_allocator.spreadLinesAcrossTerminals. Not built
-- yet.
-- ============================================================

function M.getLabel()
    return "TERMINALS"
end


function M.refresh(rows, hubStationGroupId)

    rows[1].label:setText(
        "TERMINALS -- not built yet.",
        560
    )

end


return M
