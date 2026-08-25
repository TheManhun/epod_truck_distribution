local M = {}


-- ============================================================
-- ACTIVITY TAB (gui_manager.lua) -- PLACEHOLDER
--
-- GUI_Plan.md flagged this one as needing new infrastructure, not
-- just a new view: a small in-memory/persisted DD activity queue
-- (new line adopted, fleet plan calculated, vehicle reassigned,
-- terminal changed) doesn't exist yet -- the log is the only record
-- today, and this tab should NOT parse stdout. Needs that queue
-- built first; not started.
-- ============================================================

function M.getLabel()
    return "ACTIVITY"
end


function M.refresh(rows, hubStationGroupId)

    rows[1].label:setText(
        "ACTIVITY -- not built yet (needs a real activity log module first).",
        560
    )

end


return M
