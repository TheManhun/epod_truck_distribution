local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local hub_registry = require("epod_td.hub_registry")
local hub_setup = require("epod_td.hub_setup")
local operation_lock = require("epod_td.operation_lock")
local log = require("epod_td.log")

local M = {}


-- ============================================================
-- OVERVIEW TAB (gui_manager.lua)
--
-- GUI ONLY -- reads existing modules, calculates nothing of its own.
-- First real tab built against the new framework; the rest start as
-- placeholders (see gui_tab_hubs.lua etc.) and get filled in the same
-- way over time.
--
-- Decision 71: also the first tab to claim an action-button slot --
-- "Re-Organize Terminals" (terminal_allocator.spreadLinesAcrossTerminals),
-- guarded by the same shared operation_lock the old panel's
-- Split/Assign & Balance/Re-Organize Terminals/Distribution Hub
-- buttons already use, so this window can't race them. Deliberately
-- the FIRST action wired in, not all of them at once: it's already a
-- clean, public, single-call module function with no orchestration to
-- extract. Split/Assign & Balance/Distribution Hub ON-OFF were still
-- private composed sequences inside epod_truck_distribution.lua at the
-- time -- Split has since moved to hub_setup.lua (Decision 122) and is
-- now action slot 1 here too; Assign & Balance/Distribution Hub ON-OFF
-- remain the old panel's own private sequences, not yet extracted.
-- ============================================================

function M.getLabel()
    return "OVERVIEW"
end


-- Decision 143: hub-list rendering, moved here from the now-dropped
-- HUBS tab. `hubButtons` is a pool of {label, button, handler} slots
-- gui_central_raw.lua's buildOverviewPanel built; `onSwitchHub` is a
-- plain callback (state.viewedHubStationGroupId's setter) it hands us
-- so this file never touches that state directly -- see gui_central_
-- raw.lua's own header comment for why. Renders unconditionally, even
-- with hubStationGroupId == nil, so the player can pick their first
-- hub straight from this list rather than needing one already
-- selected on the map. Active/inactive reuses the exact same
-- EpodTdTabActive/EpodTdTabInactive classes the tab bar itself uses --
-- same green-vs-dark look, no new styling risk.
local function renderHubButtons(hubButtons, hubStationGroupId, onSwitchHub)

    if hubButtons == nil then
        return
    end

    local okHubs, enabledHubs = pcall(hub_registry.getEnabledHubs)

    if not okHubs or enabledHubs == nil then
        enabledHubs = {}
    end

    for hubSlotIndex, slot in ipairs(hubButtons) do

        local enabledHubId = enabledHubs[hubSlotIndex]

        if enabledHubId == nil then

            -- Decision 144: LIVE-CONFIRMED -- blanking a slot's text
            -- doesn't collapse its height, same root cause as the LINES
            -- accordion's own spacing bug (Decision 132) -- a 12-slot
            -- pool with only 3 real hubs left 9 button-heights' worth
            -- of visible empty space below the list. Same proven fix:
            -- hide the whole slot via setVisible, not just its text.
            pcall(slot.button.setVisible, slot.button, false)
            slot.label:setText("", 560)
            slot.handler = nil
            pcall(slot.button.setStyleClassList, slot.button, {})

        else

            local okName, hubName = pcall(stations.getEntityName, enabledHubId)
            local isActive = enabledHubId == hubStationGroupId

            pcall(slot.button.setVisible, slot.button, true)

            slot.label:setText(
                okName and tostring(hubName) or ("hub " .. tostring(enabledHubId)),
                560
            )

            pcall(slot.button.setStyleClassList, slot.button, { isActive and "EpodTdTabActive" or "EpodTdTabInactive" })

            slot.handler = function()

                if onSwitchHub ~= nil then
                    onSwitchHub(enabledHubId)
                end

            end

        end

    end

end


function M.refresh(rows, hubStationGroupId, actionButtons, hubButtons, onSwitchHub)

    renderHubButtons(hubButtons, hubStationGroupId, onSwitchHub)

    if hubStationGroupId == nil then

        rows[1].label:setText(
            "No hub selected -- select a station on the map, or click a hub above.",
            560
        )

        return

    end

    -- Decision 122: same real sequence as the old panel's "Split Into
    -- Lines & Organize Terminals" button, via hub_setup.lua (extracted
    -- specifically so this tab and the old panel can both call it).
    -- Status text is logged rather than written back onto the button
    -- (see gui_tab_services.lua's own comment on this same tradeoff --
    -- M.refresh runs every guiUpdate frame and would overwrite any
    -- "done: N" text on the very next frame anyway).
    if actionButtons ~= nil and actionButtons[1] ~= nil then

        local slot = actionButtons[1]

        if operation_lock.isRunning() then

            slot.label:setText("[ Split Into Lines & Organize Terminals (busy -- another hub operation running) ]", 560)
            slot.handler = nil

        else

            slot.label:setText("[ Split Into Lines & Organize Terminals ]", 560)
            pcall(slot.button.setStyleClassList, slot.button, { "EpodTdPrimaryButton" })

            slot.handler = function()

                if operation_lock.isRunning() then

                    log.info("OVERVIEW TAB: another hub operation is still running -- ignoring click.")
                    return

                end

                operation_lock.begin()

                hub_setup.splitStationLines(
                    hubStationGroupId,

                    function(text)
                        log.info("OVERVIEW TAB: Split -- " .. tostring(text))
                    end,

                    function()
                        operation_lock.finish()
                    end
                )

            end

        end

    end

    -- Decision 142: "Re-Organize Terminals" moved off OVERVIEW onto
    -- LINES (gui_tab_lines.lua now owns this action) -- player's call,
    -- "we still want the resort terminals button, but that could go
    -- onto the Lines page, logical sense" now that LINES shows each
    -- line's own terminal number (Decision 139) and TERMINALS itself
    -- was dropped (Decision 141). Distribution Hub toggle renumbered
    -- from slot 3 down to slot 2 to fill the gap -- OVERVIEW now claims
    -- 2 action slots, not 3 (see gui_central_raw.lua's
    -- ACTION_BUTTON_COUNTS).
    --
    -- Decision 124: player's request, "We should have Distribution
    -- Hub On/off toggle on the Overview page" -- same real
    -- hub_setup.toggleDistributionHub call HUBS tab's own toggle uses
    -- (Decision 122). Deliberately kept on HUBS too, not moved --
    -- OVERVIEW is the page a player lands on for a hub, HUBS is where
    -- they'd go to see every enabled hub at once; both are legitimate
    -- places to flip it, and unlike the old-panel-vs-new-GUI double-up
    -- this cleanup removed elsewhere, two tabs within the SAME window
    -- offering the same action costs nothing (only one tab is ever
    -- visible at a time).
    if actionButtons ~= nil and actionButtons[2] ~= nil then

        local slot = actionButtons[2]

        if operation_lock.isRunning() then

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

                    log.info("OVERVIEW TAB: another hub operation is still running -- ignoring click.")
                    return

                end

                operation_lock.begin()

                hub_setup.toggleDistributionHub(
                    hubStationGroupId,

                    function(text)
                        log.info("OVERVIEW TAB: Distribution Hub -- " .. tostring(text))
                    end,

                    function()
                        operation_lock.finish()
                    end
                )

            end

        end

    end

    -- Decision 142: "Open Lines" (Decision 129's own action slot 4,
    -- opening the then-separate gui_lines_window.lua) removed outright
    -- -- LINES has been a real tab in this window since Decision 131,
    -- so a button opening a whole separate window for it stopped
    -- making sense a while ago. Was already effectively dead here
    -- (OVERVIEW has only ever claimed 3, then 2, action-button slots
    -- since -- actionButtons[4] was always nil).

    local hubName = stations.getEntityName(hubStationGroupId)
    local managedLines = vehicles.getManagedLinesForStation(hubStationGroupId)
    local terminalCount = stations.getTerminalCount(hubStationGroupId)
    local autoRedistributeOn = hub_registry.isEnabled(hubStationGroupId)

    local totalVehicles = 0
    local totalWaiting = 0

    for _, lineInfo in ipairs(managedLines) do

        totalVehicles = totalVehicles + (lineInfo.vehicleCount or 0)

        local scanResult = demand.scan(lineInfo.id, hubStationGroupId)

        totalWaiting =
            totalWaiting + ((scanResult ~= nil and scanResult.totalWaiting) or 0)

    end

    local rowIndex = 1

    rows[rowIndex].label:setText(tostring(hubName), 560)
    pcall(rows[rowIndex].label.setStyleClassList, rows[rowIndex].label, { "EpodTdTableHeader" })
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Managed lines: " .. tostring(#managedLines),
        560
    )
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Total vehicles: " .. tostring(totalVehicles),
        560
    )
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Total waiting: " .. tostring(totalWaiting),
        560
    )
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Terminals: " .. tostring(terminalCount),
        560
    )
    rowIndex = rowIndex + 1

    rows[rowIndex].label:setText(
        "Auto Redistribute: " .. (autoRedistributeOn and "ON" or "OFF"),
        560
    )

    if not autoRedistributeOn then
        pcall(rows[rowIndex].label.setStyleClassList, rows[rowIndex].label, { "EpodTdWarningText" })
    end

end


return M
