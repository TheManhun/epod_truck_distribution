local M = {}


-- ============================================================
-- SETTINGS TAB (gui_manager.lua) -- PLACEHOLDER
--
-- GUI_Plan.md: Auto Redistribute / rename-fleet toggles per hub,
-- sourced from hub_registry.lua and settings.lua. Not built yet --
-- these already exist as buttons on the current panel; this tab
-- would just present the same state differently.
-- ============================================================

function M.getLabel()
    return "SETTINGS"
end


function M.refresh(rows, hubStationGroupId)

    rows[1].label:setText(
        "SETTINGS -- not built yet.",
        560
    )

end


return M
