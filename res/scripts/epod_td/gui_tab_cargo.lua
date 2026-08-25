local M = {}


-- ============================================================
-- CARGO TAB (gui_manager.lua) -- PLACEHOLDER
--
-- GUI_Plan.md: waiting cargo totaled by cargo type across the
-- focused hub (demand.scan + demand.getCargoTypeDisplayName /
-- getCargoTypeIconPath), optionally grouped by service. Not built
-- yet.
-- ============================================================

function M.getLabel()
    return "CARGO"
end


function M.refresh(rows, hubStationGroupId)

    rows[1].label:setText(
        "CARGO -- not built yet.",
        560
    )

end


return M
