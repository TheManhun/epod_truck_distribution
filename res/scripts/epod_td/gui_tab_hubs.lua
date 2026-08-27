local hub_registry = require("epod_td.hub_registry")
local stations = require("epod_td.stations")
local hub_setup = require("epod_td.hub_setup")
local operation_lock = require("epod_td.operation_lock")
local log = require("epod_td.log")

local M = {}


-- ============================================================
-- HUBS TAB (gui_manager.lua)
--
-- Decision 122: real content, replacing the old placeholder. Action
-- slot 1 is the Distribution Hub ON/OFF toggle for the currently
-- focused hub -- the last of the old panel's real per-hub controls to
-- move into the new GUI, via hub_setup.toggleDistributionHub (same
-- module the old panel's own toggle now calls). Rows list every
-- currently enabled hub, per this tab's own original design goal
-- (GUI_Plan.md) -- read-only, hub_registry.getEnabledHubs() +
-- stations.getEntityName, calculates nothing of its own.
-- ============================================================

function M.getLabel()
    return "HUBS"
end


function M.refresh(rows, hubStationGroupId, actionButtons)

    if actionButtons ~= nil and actionButtons[1] ~= nil then

        local slot = actionButtons[1]

        if hubStationGroupId == nil then

            slot.label:setText("[ Distribution Hub: select a hub first ]", 560)
            slot.handler = nil

        elseif operation_lock.isRunning() then

            slot.label:setText("[ Distribution Hub (busy -- another hub operation running) ]", 560)
            slot.handler = nil

        else

            local isEnabled = hub_registry.isEnabled(hubStationGroupId)

            slot.label:setText(
                isEnabled
                    and "[ Distribution Hub: ON for this hub ]"
                    or "[ Distribution Hub: OFF for this hub ]",
                560
            )

            pcall(slot.button.setStyleClassList, slot.button, { "EpodTdPrimaryButton" })

            slot.handler = function()

                if operation_lock.isRunning() then

                    log.info("HUBS TAB: another hub operation is still running -- ignoring click.")
                    return

                end

                operation_lock.begin()

                hub_setup.toggleDistributionHub(
                    hubStationGroupId,

                    function(text)
                        log.info("HUBS TAB: Distribution Hub -- " .. tostring(text))
                    end,

                    function()
                        operation_lock.finish()
                    end
                )

            end

        end

    end

    local ok, enabledHubs = pcall(hub_registry.getEnabledHubs)

    if not ok or enabledHubs == nil or #enabledHubs == 0 then

        rows[1].label:setText("No hubs enabled yet -- use the toggle above on a selected station.", 560)

        return

    end

    rows[1].label:setText("Enabled hubs (" .. tostring(#enabledHubs) .. ")", 560)
    pcall(rows[1].label.setStyleClassList, rows[1].label, { "EpodTdTableHeader" })

    local rowIndex = 2

    for _, enabledHubId in ipairs(enabledHubs) do

        if rowIndex > #rows then
            break
        end

        local okName, hubName = pcall(stations.getEntityName, enabledHubId)

        local isFocused = enabledHubId == hubStationGroupId
        local prefix = isFocused and "> " or "  "

        rows[rowIndex].label:setText(
            prefix .. (okName and tostring(hubName) or ("hub " .. tostring(enabledHubId))),
            560
        )

        if isFocused then
            pcall(rows[rowIndex].label.setStyleClassList, rows[rowIndex].label, { "EpodTdTableHeader" })
        end

        rowIndex = rowIndex + 1

    end

end


return M
