local M = {}


-- ============================================================
-- HUBS TAB (gui_manager.lua) -- PLACEHOLDER
--
-- GUI_Plan.md: list every enabled hub (hub_registry.getEnabledHubs())
-- with a per-hub summary, click to switch which hub the other tabs
-- focus on. Not built yet -- framework proof of concept is
-- gui_tab_overview.lua; this and the remaining tabs get filled in one
-- at a time.
-- ============================================================

function M.getLabel()
    return "HUBS"
end


function M.refresh(rows, hubStationGroupId)

    rows[1].label:setText(
        "HUBS -- not built yet. See gui_tab_overview.lua for the first real tab.",
        560
    )

end


return M
