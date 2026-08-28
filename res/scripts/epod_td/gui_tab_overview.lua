local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local hub_registry = require("epod_td.hub_registry")
local hub_setup = require("epod_td.hub_setup")
local operation_lock = require("epod_td.operation_lock")
local truck_station_finder = require("epod_td.truck_station_finder")
local gui_plan_popup = require("epod_td.gui_plan_popup")
local log = require("epod_td.log")

local M = {}

-- Must match gui_central_raw.lua's own copies of these same constants
-- exactly -- the actual widgets are created at these widths.
local TRUCK_STATION_LABEL_WIDTH = 460
local TRUCK_STATION_HUB_BUTTON_WIDTH = 140

-- Decision 159/161: player's call after seeing drop-off stations sit in
-- the list as permanently-disabled "[ Drop-off ]" rows -- "would it
-- not be best just to not list them? ... no need to see them" -- and,
-- separately, the player's redesign merging the old hub-button column
-- into this same list with a Hubs/Stations/All filter. Applied at
-- RENDER time against the cached RAW scan (never re-scans just to
-- switch filter mode) -- truck_station_finder.scan() itself stays
-- generic/unfiltered so any future feature can still use the full set.
local function applyListFilter(rawList, filterMode)

    local filtered = {}

    for _, entry in ipairs(rawList or {}) do

        local passesDropOff = entry.fileName ~= nil or entry.isHub

        local passesMode =
            (filterMode == "HUBS" and entry.isHub)
                or (filterMode == "STATIONS" and not entry.isHub)
                or (filterMode ~= "HUBS" and filterMode ~= "STATIONS")

        if passesDropOff and passesMode then
            filtered[#filtered + 1] = entry
        end

    end

    return filtered

end


-- Decision 151/161: cached RAW scan result + current page/filter mode,
-- same shape as gui_tab_lines.lua's own state.currentPage. Deliberately
-- module-level (survives across refreshes) rather than re-scanning
-- every guiUpdate tick -- a full-map stationSystem.forEach scan is real
-- work, meant to run only when the player explicitly asks (Refresh
-- button, first open, or right after a hub toggle completes).
local truckStationState = {
    rawList = nil,
    currentPage = 1,
    filterMode = "ALL"
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


-- Decision 143 introduced a dedicated hub-button column here; Decision
-- 161 removed it outright and merged hub-switching into the truck-
-- station list below instead (see renderTruckStationList's own header
-- comment). `onSwitchHub` is still the same plain callback
-- (state.viewedHubStationGroupId's setter) gui_central_raw.lua hands
-- this file so it never touches that state directly.
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


-- Decision 161: player's redesign, moved to buildOverviewPanel/
-- renderTruckStationList below -- see that function's own header
-- comment.

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
--
-- Decision 161: player's redesign -- the separate hub-button column
-- (Decision 143) is gone; an enabled hub is now just a row in THIS
-- list like any other, reachable via the new Hubs/Stations/All filter
-- (`truckStationFilterButtons`, built by gui_central_raw.lua's
-- buildOverviewPanel). Clicking a HUB row's name now switches which
-- hub the whole OVERVIEW page focuses on (via `onSwitchHub`, the same
-- callback the old hub-button column used) IN ADDITION to the camera
-- jump every row's name-click already does -- player's own
-- confirmation, "if you click the Hub button that's the one in focus
-- for all the data."
local function renderTruckStationList(truckStationRows, truckStationPagination, truckStationRefreshButton, truckStationFilterButtons, onSwitchHub, hubStationGroupId, setStatus)

    if truckStationRows == nil then
        return
    end

    if truckStationRefreshButton ~= nil then

        truckStationRefreshButton.handler = function()

            local ok, result = pcall(truck_station_finder.scan)

            if ok then

                truckStationState.rawList = result
                truckStationState.currentPage = 1

            else
                log.info("OVERVIEW TAB: truck station scan failed: " .. tostring(result))
            end

        end

    end

    if truckStationFilterButtons ~= nil then

        for filterMode, slot in pairs(truckStationFilterButtons) do

            local isActive = truckStationState.filterMode == filterMode

            pcall(slot.button.setStyleClassList, slot.button, { isActive and "EpodTdTabActive" or "EpodTdTabInactive" })

            slot.handler = function()
                truckStationState.filterMode = filterMode
                truckStationState.currentPage = 1
            end

        end

    end

    if truckStationState.rawList == nil then

        -- First time this window's been opened this session -- run one
        -- scan automatically so the list isn't just empty forever until
        -- the player finds the Refresh button. Still only ONE scan, not
        -- one per guiUpdate tick.
        local ok, result = pcall(truck_station_finder.scan)

        if ok then
            truckStationState.rawList = result
        else

            truckStationState.rawList = {}
            log.info("OVERVIEW TAB: initial truck station scan failed: " .. tostring(result))

        end

    end

    local list = applyListFilter(truckStationState.rawList, truckStationState.filterMode)
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

            -- Decision 165: player's own report -- station names were
            -- getting cut off ("Braintree Chemical plant - B..."). Two
            -- real causes fixed together: the field was cramming a
            -- full "lines=" / "trucks=" label into every row (shortened
            -- to "L:"/"T:", saving ~10 characters for the name itself),
            -- and the label width itself (TRUCK_STATION_LABEL_WIDTH)
            -- was too narrow for what it was being asked to hold --
            -- widened to match (also updated in gui_central_raw.lua,
            -- which must keep its own copy of this constant in sync --
            -- the actual widget is built there).
            row.infoLabel:setText(
                string.format(
                    "%-14s %-34s L:%-3s T:%-3s",
                    tostring(entry.townName or "?"):sub(1, 14),
                    tostring(entry.name):sub(1, 34),
                    tostring(entry.lineCount),
                    tostring(entry.vehicleCount)
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
            --
            -- Decision 161: for a HUB row specifically, this SAME
            -- name-click now also switches the viewed hub (via
            -- onSwitchHub) -- replaces the old dedicated hub-button
            -- column's only job, on top of the camera jump every row
            -- already does. Never mutates anything either way -- both
            -- halves are pure navigation.
            do

                local locateStationGroupId = entry.stationGroupId
                local isHubRow = entry.isHub

                row.locateHandler = function()

                    if isHubRow and onSwitchHub ~= nil then
                        onSwitchHub(locateStationGroupId)
                    end

                    local ok, targetEntity = pcall(game.interface.getEntity, locateStationGroupId)

                    if ok and targetEntity ~= nil and targetEntity.position ~= nil then

                        local pos = targetEntity.position

                        pcall(game.gui.setCamera, { pos[1], pos[2], pos[3], -4.77, 0.2 })

                    else
                        log.info("OVERVIEW TAB: truck station list -- could not locate stationGroupId " .. tostring(locateStationGroupId))
                    end

                end

            end

            -- A hub row that's ALSO the currently-viewed hub gets the
            -- active tab-bar green, same visual language the old hub-
            -- button column and the tab bar itself already use.
            local isViewedHub = entry.isHub and entry.stationGroupId == hubStationGroupId
            pcall(row.infoButton.setStyleClassList, row.infoButton, { isViewedHub and "EpodTdTabActive" or "EpodTdTabInactive" })

            if entry.isHub then

                -- Decision 163: LIVE-CONFIRMED real gap -- the player's
                -- click never reached row.locateHandler at all (no
                -- diagnostic file written), meaning they were almost
                -- certainly clicking the green "[ HUB ]" badge itself,
                -- not the plain station-name text next to it -- a
                -- completely reasonable assumption given every OTHER
                -- row's right-side badge ("Make Hub") IS the actionable
                -- button. This badge's handler was left nil for hub
                -- rows. Now points at the SAME switch-hub-and-locate
                -- function the name already uses, so either click
                -- works.
                row.hubButtonLabel:setText("[ HUB ]", TRUCK_STATION_HUB_BUTTON_WIDTH)
                pcall(row.hubButton.setStyleClassList, row.hubButton, { "EpodTdTabActive" })
                row.handler = row.locateHandler

            elseif entry.fileName == nil then

                -- Decision 157/158: player's own conclusion after the
                -- construction survey -- a station with NO construction
                -- entity at all (auto-generated town-zone delivery
                -- point, not a real player-built cargo yard -- e.g.
                -- "Barking Industrial") can't hold real stock, so it
                -- shouldn't be offered as a hub candidate at all. Left
                -- VISIBLE in the list (still useful info -- the name/
                -- city/line/truck data and Locate button all still
                -- work) but the conversion action itself is disabled,
                -- same "show why, don't just remove" philosophy as the
                -- Busy state above.
                row.hubButtonLabel:setText("[ Drop-off ]", TRUCK_STATION_HUB_BUTTON_WIDTH)
                pcall(row.hubButton.setStyleClassList, row.hubButton, { "EpodTdMutedText" })
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
                local targetStationName = entry.name

                -- Decision 170: player's request -- clicking Make Hub
                -- now shows a real preview (predicted new lines,
                -- estimated truck rename count -- hub_setup.
                -- previewConversion, a pure read-only mirror of the
                -- real Split decision logic) before anything happens,
                -- with a real [ Confirm ] button in gui_plan_popup.lua
                -- gating the actual conversion. This closure is the
                -- SAME real conversion logic that used to run
                -- immediately on click -- now it only runs if/when the
                -- popup's Confirm is pressed.
                local function performConversion()

                    if operation_lock.isRunning() then

                        log.info("OVERVIEW TAB: another hub operation is still running -- ignoring click.")
                        return

                    end

                    log.info("OVERVIEW TAB: truck station list -- Make Hub confirmed for stationGroupId " .. tostring(targetStationGroupId))

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
                    setStatus("Converting " .. tostring(targetStationName) .. " to a Distribution Hub...")

                    local ok, err =
                        pcall(
                            hub_setup.toggleDistributionHub,
                            targetStationGroupId,

                            function(text)
                                log.info("OVERVIEW TAB: truck station list Distribution Hub -- " .. tostring(text))
                                setStatus(text)
                            end,

                            function()

                                operation_lock.finish()
                                setStatus("")

                                -- Re-scan once so this row picks up its new
                                -- HUB state and refreshed line/truck counts
                                -- right away, without waiting on a manual
                                -- Refresh click.
                                local okRescan, result = pcall(truck_station_finder.scan)

                                if okRescan then
                                    truckStationState.rawList = result
                                end

                                -- Decision 167, LIVE-CONFIRMED root cause
                                -- (diagnostic showed actualIndexInFiltered
                                -- List=nil under filterMode=STATIONS): a
                                -- successful conversion correctly makes
                                -- entry.isHub true, but the "Stations"
                                -- filter deliberately EXCLUDES hubs -- so
                                -- the just-converted row vanishes from view
                                -- the instant it succeeds, and whichever
                                -- real station shifts into that same row
                                -- position next reads as "it reverted."
                                -- Not a data bug at all -- the conversion
                                -- always worked in one click. Fix: switch
                                -- to "All" so the just-converted station
                                -- stays visible and the player actually
                                -- sees the [ HUB ] confirmation, rather
                                -- than staying on a filter guaranteed to
                                -- hide the very thing that just happened.
                                if truckStationState.filterMode == "STATIONS" then
                                    truckStationState.filterMode = "ALL"
                                end

                            end
                        )

                    if not ok then

                        operation_lock.finish()
                        setStatus("")
                        log.info("OVERVIEW TAB: truck station list -- toggleDistributionHub crashed: " .. tostring(err))

                    end

                end

                row.handler = function()

                    if operation_lock.isRunning() then

                        log.info("OVERVIEW TAB: another hub operation is still running -- ignoring click.")
                        return

                    end

                    local okPreview, plan = pcall(hub_setup.previewConversion, targetStationGroupId)

                    if not okPreview or plan == nil then

                        log.info("OVERVIEW TAB: preview failed, converting without one: " .. tostring(plan))
                        performConversion()
                        return

                    end

                    local lines = {
                        "Currently has " .. tostring(plan.currentLineCount) .. " line(s).",
                        ""
                    }

                    if #plan.plannedNewLines > 0 then

                        lines[#lines + 1] =
                            "Plan: break into " .. tostring(#plan.plannedNewLines) .. " dedicated line(s):"

                        for index, planned in ipairs(plan.plannedNewLines) do
                            lines[#lines + 1] = "  Line " .. tostring(index) .. ": " .. tostring(planned.name)
                        end

                        lines[#lines + 1] = ""

                    end

                    if #plan.skippedLines > 0 then

                        lines[#lines + 1] = "Kept as-is (" .. tostring(#plan.skippedLines) .. " line(s)):"

                        for _, skipped in ipairs(plan.skippedLines) do
                            lines[#lines + 1] = "  " .. tostring(skipped.name) .. " -- " .. tostring(skipped.reason)
                        end

                        lines[#lines + 1] = ""

                    end

                    lines[#lines + 1] =
                        "Estimated trucks to rename: " .. tostring(plan.estimatedRenameCount)

                    gui_plan_popup.show(
                        "Make Hub: " .. tostring(targetStationName),
                        lines,
                        performConversion
                    )

                end

            end

        end

    end

end


function M.refresh(
    rows,
    hubStationGroupId,
    actionButtons,
    onSwitchHub,
    truckStationRows,
    truckStationPagination,
    truckStationRefreshButton,
    truckStationFilterButtons,
    setStatus
)

    setStatus = setStatus or function() end

    renderTruckStationList(truckStationRows, truckStationPagination, truckStationRefreshButton, truckStationFilterButtons, onSwitchHub, hubStationGroupId, setStatus)

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
                        setStatus(text)
                    end,

                    function()
                        operation_lock.finish()
                        setStatus("")
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
                        setStatus(text)
                    end,

                    function()
                        operation_lock.finish()
                        setStatus("")
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
