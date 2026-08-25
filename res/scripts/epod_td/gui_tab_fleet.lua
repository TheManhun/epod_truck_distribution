local M = {}


-- ============================================================
-- FLEET TAB (gui_manager.lua) -- PLACEHOLDER
--
-- GUI_Plan.md: fleet-wide capability profile breakdown
-- (vehicles.getAllCapacities/getCompatibleCargoTypes) and per-service
-- empty/loaded counts (vehicles.getCargoLoad/isVehicleEmpty). Not
-- built yet.
--
-- STRONG CANDIDATE CONTENT (raised live, 6-hub stress test): the
-- DEBUG "Fleet Balance Report" button (epod_truck_distribution.lua)
-- already proves the exact data this tab wants -- one row per
-- managed line with vehicle count and waiting cargo, sorted
-- worst-backlog-first, flagging idle-capacity lines -- it just writes
-- to a file (epod_td_fleet_balance_report.txt) instead of showing
-- live in the panel. This tab is the natural real home for that same
-- logic, network-wide (every enabled hub, not just whichever one is
-- currently selected) rather than one hub at a time.
-- ============================================================

function M.getLabel()
    return "FLEET"
end


function M.refresh(rows, hubStationGroupId)

    rows[1].label:setText(
        "FLEET -- not built yet.",
        560
    )

end


return M
