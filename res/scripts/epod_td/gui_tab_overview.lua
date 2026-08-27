local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local hub_registry = require("epod_td.hub_registry")
local hub_setup = require("epod_td.hub_setup")
local operation_lock = require("epod_td.operation_lock")
local truck_station_finder = require("epod_td.truck_station_finder")
local log = require("epod_td.log")

local M = {}

-- Must match gui_central_raw.lua's own copies of these same constants
-- exactly -- the actual widgets are created at these widths.
local TRUCK_STATION_LABEL_WIDTH = 380
local TRUCK_STATION_HUB_BUTTON_WIDTH = 140

-- Decision 151: cached scan result + current page, same shape as
-- gui_tab_lines.lua's own state.currentPage. Deliberately module-level
-- (survives across refreshes) rather than re-scanning every guiUpdate
-- tick -- a full-map stationSystem.forEach scan is real work, meant to
-- run only when the player explicitly asks (Refresh button, first
-- open, or right after a hub toggle completes).
local truckStationState = {
    list = nil,
    currentPage = 1
}


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
-- Decision 152: LIVE-CONFIRMED real bug -- adding the truck-station
-- list pushed OVERVIEW's total content past the window's fixed size
-- (no scroll capability, confirmed failing back in Decision 75/76) and
-- the whole window ballooned past the screen edges. Root cause: the
-- shared MAX_ROWS=24 plain-row pool (buildSimplePanel/buildOverview
-- Panel) is sized for whichever simple tab uses the most rows, but
-- OVERVIEW only ever fills 6 of them -- clearRows blanks the other 18
-- to "" every refresh but never hides them, so they've silently held
-- their full row height this whole time (same root cause as the hub-
-- button list gap, Decision 144, and the LINES accordion gap, Decision
-- 132, just never surfaced before because total content happened to
-- still fit). Same proven fix: setVisible(false) on whatever's unused.
local function setRowsVisibleUpTo(rows, usedCount)

    for rowIndex, row in ipairs(rows) do
        pcall(row.label.setVisible, row.label, rowIndex <= usedCount)
    end

end


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


-- Decision 151: player's request -- "put it on the front page at the
-- bottom showing only 10 stations per page ... City Name - How many
-- lines - Trucks allocated ... with the ones with cities at top."
-- `truckStationRows` is the MAX_TRUCK_STATION_ROWS_PER_PAGE pool
-- gui_central_raw.lua's buildOverviewPanel built (each slot: infoLabel
-- + a "Make Hub"/"HUB" button); `truckStationPagination` is the same
-- {prevButton, nextButton, pageLabel} shape LINES already proves out;
-- `truckStationRefreshButton` is a single {label, button, handler}
-- slot. Renders unconditionally, even with hubStationGroupId == nil --
-- this list is global (every truck station on the map), not scoped to
-- whichever hub happens to be selected.
--
-- Sorting (grouped by city, busiest station first within a city) is
-- truck_station_finder.scan()'s own job, not this file's -- see that
-- module's header comment for the full live-proven field list
-- (Decisions 148-150) this reads.
local function renderTruckStationList(truckStationRows, truckStationPagination, truckStationRefreshButton)

    if truckStationRows == nil then
        return
    end

    if truckStationRefreshButton ~= nil then

        truckStationRefreshButton.handler = function()

            local ok, result = pcall(truck_station_finder.scan)

            if ok then

                truckStationState.list = result
                truckStationState.currentPage = 1

            else
                log.info("OVERVIEW TAB: truck station scan failed: " .. tostring(result))
            end

        end

    end

    if truckStationState.list == nil then

        -- First time this window's been opened this session -- run one
        -- scan automatically so the list isn't just empty forever until
        -- the player finds the Refresh button. Still only ONE scan, not
        -- one per guiUpdate tick.
        local ok, result = pcall(truck_station_finder.scan)

        if ok then
            truckStationState.list = result
        else

            truckStationState.list = {}
            log.info("OVERVIEW TAB: initial truck station scan failed: " .. tostring(result))

        end

    end

    local list = truckStationState.list
    local totalPages = math.max(1, math.ceil(#list / #truckStationRows))

    if truckStationState.currentPage > totalPages then
        truckStationState.currentPage = totalPages
    end

    if truckStationState.currentPage < 1 then
        truckStationState.currentPage = 1
    end

    if truckStationPagination ~= nil then

        if truckStationPagination.pageLabel ~= nil then

            truckStationPagination.pageLabel:setText(
                "Page " .. tostring(truckStationState.currentPage) .. " / " .. tostring(totalPages)
                    .. " (" .. tostring(#list) .. ")",
                160
            )

        end

        if truckStationPagination.prevButton ~= nil then

            truckStationPagination.prevButton.handler = function()

                if truckStationState.currentPage > 1 then
                    truckStationState.currentPage = truckStationState.currentPage - 1
                end

            end

        end

        if truckStationPagination.nextButton ~= nil then

            truckStationPagination.nextButton.handler = function()

                if truckStationState.currentPage < totalPages then
                    truckStationState.currentPage = truckStationState.currentPage + 1
                end

            end

        end

    end

    local startIndex = (truckStationState.currentPage - 1) * #truckStationRows + 1

    for rowIndex, row in ipairs(truckStationRows) do

        local entry = list[startIndex + rowIndex - 1]

        if entry == nil then

            row.infoLabel:setText("", TRUCK_STATION_LABEL_WIDTH)
            row.hubButtonLabel:setText("", TRUCK_STATION_HUB_BUTTON_WIDTH)
            row.handler = nil
            row.locateHandler = nil
            pcall(row.hubButton.setVisible, row.hubButton, false)
            pcall(row.infoButton.setVisible, row.infoButton, false)

        else

            pcall(row.hubButton.setVisible, row.hubButton, true)
            pcall(row.infoButton.setVisible, row.infoButton, true)
            pcall(row.infoButton.setStyleClassList, row.infoButton, { "EpodTdTabInactive" })

            local industryTag =
                entry.industryName ~= nil
                    and ("  <-- near " .. tostring(entry.industryName))
                    or ""

            row.infoLabel:setText(
                string.format(
                    "%-16s %-28s lines=%-3s trucks=%-3s%s",
                    tostring(entry.townName or "?"):sub(1, 16),
                    tostring(entry.name):sub(1, 28),
                    tostring(entry.lineCount),
                    tostring(entry.vehicleCount),
                    industryTag
                ),
                TRUCK_STATION_LABEL_WIDTH
            )

            -- Decision 155/156: navigation-only, deliberately separate
            -- from the hub-mutating handler below -- no operation_lock
            -- involved, this can never be "busy" or blocked, matching
            -- the player's own "always safe" framing. Same
            -- game.gui.setCamera call the DEBUG probe already proved
            -- live (Decision 155), fetching a fresh position at click
            -- time rather than caching one from scan time.
            do

                local locateStationGroupId = entry.stationGroupId

                row.locateHandler = function()

                    local ok, targetEntity = pcall(game.interface.getEntity, locateStationGroupId)

                    if ok and targetEntity ~= nil and targetEntity.position ~= nil then

                        local pos = targetEntity.position

                        pcall(game.gui.setCamera, { pos[1], pos[2], pos[3], -4.77, 0.2 })

                    else
                        log.info("OVERVIEW TAB: truck station list -- could not locate stationGroupId " .. tostring(locateStationGroupId))
                    end

                end

            end

            if entry.isHub then

                row.hubButtonLabel:setText("[ HUB ]", TRUCK_STATION_HUB_BUTTON_WIDTH)
                pcall(row.hubButton.setStyleClassList, row.hubButton, { "EpodTdTabActive" })
                row.handler = nil

            elseif operation_lock.isRunning() then

                -- Decision 153: LIVE-CONFIRMED gap -- player clicked
                -- "Make Hub" and nothing visibly happened, with no way
                -- to tell whether the click was silently ignored
                -- (another hub-mutating action -- Split/Assign & Balance/
                -- Distribution Hub toggle/Chain Builder/Push Full
                -- Reallocation, all sharing the ONE operation_lock --
                -- was already running) or genuinely broken. The other
                -- two OVERVIEW action buttons already show their own
                -- "(busy -- another hub operation running)" text for
                -- exactly this reason; this row never got the same
                -- treatment. Fixed: same busy text + cleared handler,
                -- so a blocked click is now visibly distinguishable
                -- from a silent failure.
                row.hubButtonLabel:setText("[ Busy... ]", TRUCK_STATION_HUB_BUTTON_WIDTH)
                pcall(row.hubButton.setStyleClassList, row.hubButton, {})
                row.handler = nil

            else

                row.hubButtonLabel:setText("[ Make Hub ]", TRUCK_STATION_HUB_BUTTON_WIDTH)
                pcall(row.hubButton.setStyleClassList, row.hubButton, { "EpodTdPrimaryButton" })

                local targetStationGroupId = entry.stationGroupId

                row.handler = function()

                    if operation_lock.isRunning() then

                        log.info("OVERVIEW TAB: another hub operation is still running -- ignoring click.")
                        return

                    end

                    log.info("OVERVIEW TAB: truck station list -- Make Hub clicked for stationGroupId " .. tostring(targetStationGroupId))

                    -- Decision 154: player's own observation -- the
                    -- whole setup sequence (Split -> Rename Fleet ->
                    -- Assign & Balance) resolves within a tick or two,
                    -- so the button was jumping straight from
                    -- "Make Hub" to "HUB" with no visible in-between
                    -- frame -- looked like the click did nothing.
                    -- Setting this directly on the button's own label
                    -- HERE, synchronously, rather than waiting for the
                    -- next M.refresh tick's operation_lock.isRunning()
                    -- check to catch up -- gives the player an instant
                    -- click response regardless of how fast the real
                    -- work finishes.
                    row.hubButtonLabel:setText("[ Building Hub... ]", TRUCK_STATION_HUB_BUTTON_WIDTH)
                    pcall(row.hubButton.setStyleClassList, row.hubButton, {})

                    operation_lock.begin()

                    local ok, err =
                        pcall(
                            hub_setup.toggleDistributionHub,
                            targetStationGroupId,

                            function(text)
                                log.info("OVERVIEW TAB: truck station list Distribution Hub -- " .. tostring(text))
                            end,

                            function()

                                operation_lock.finish()

                                -- Re-scan once so this row picks up its new
                                -- HUB state and refreshed line/truck counts
                                -- right away, without waiting on a manual
                                -- Refresh click.
                                local okRescan, result = pcall(truck_station_finder.scan)

                                if okRescan then
                                    truckStationState.list = result
                                end

                            end
                        )

                    if not ok then

                        operation_lock.finish()
                        log.info("OVERVIEW TAB: truck station list -- toggleDistributionHub crashed: " .. tostring(err))

                    end

                end

            end

        end

    end

end


function M.refresh(
    rows,
    hubStationGroupId,
    actionButtons,
    hubButtons,
    onSwitchHub,
    truckStationRows,
    truckStationPagination,
    truckStationRefreshButton
)

    renderHubButtons(hubButtons, hubStationGroupId, onSwitchHub)
    renderTruckStationList(truckStationRows, truckStationPagination, truckStationRefreshButton)

    if hubStationGroupId == nil then

        rows[1].label:setText(
            "No hub selected -- select a station on the map, or click a hub above.",
            560
        )

        setRowsVisibleUpTo(rows, 1)

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

    setRowsVisibleUpTo(rows, rowIndex)

end


return M
