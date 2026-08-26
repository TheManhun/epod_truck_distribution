local log = require("epod_td.log")
local gui = require("gui")

local tab_overview = require("epod_td.gui_tab_overview")
local tab_hubs = require("epod_td.gui_tab_hubs")
local tab_lines = require("epod_td.gui_tab_lines")
local tab_services = require("epod_td.gui_tab_services")
local tab_fleet = require("epod_td.gui_tab_fleet")
local tab_terminals = require("epod_td.gui_tab_terminals")
local tab_cargo = require("epod_td.gui_tab_cargo")
local tab_activity = require("epod_td.gui_tab_activity")
local tab_settings = require("epod_td.gui_tab_settings")

local M = {}


-- ============================================================
-- DD CENTRAL MANAGER -- NEW GUI FRAMEWORK (GUI ONLY)
--
-- Proposed in documents/GUI_Plan.md: a tabbed central window,
-- separate from the existing "Truck Distribution" panel, that reads
-- state from existing modules and calls their public functions --
-- it must never calculate fleet allocations, move vehicles, or
-- duplicate planner/dispatcher/demand logic itself. Each tab is its
-- own small file (gui_tab_*.lua), exposing just getLabel() and
-- refresh(rows, hubStationGroupId).
--
-- DELIBERATELY ADDITIVE, NOT A REPLACEMENT: this is a second,
-- independent window, toggled by its own temporary button on the
-- existing panel (config.DEBUG-gated). The existing "Truck
-- Distribution" window and all of its logic are completely
-- untouched -- if anything here breaks or turns out wrong, the
-- proven panel keeps working exactly as it always has. Matches the
-- player's own explicit framing: build the framework, plug in real
-- content one tab at a time, keep what already works.
--
-- TAB SWITCHING, DELIBERATELY LOW-RISK: rather than betting on a
-- native TF2 tab-widget API that has never been used anywhere in
-- this codebase (an unproven-API risk this project has been burned
-- by tonight already -- see Decision 50), tabs are plain buttons
-- (gui.button_create, proven dozens of times over) that switch which
-- tab is "active" and share ONE pool of row widgets, exactly the
-- same "pre-allocate once, refill with setText" pattern the existing
-- panel already uses for its own managed-line rows (native TF2 UI
-- component IDs cannot be recreated on demand). Switching tabs
-- clears the shared rows and asks the newly active tab to refill
-- them -- no new GUI API surface beyond what's already proven.
-- ============================================================

local WINDOW_ID = "ddCentralManagerWindow"
local WINDOW_WIDTH = 560
local ROW_WIDTH = WINDOW_WIDTH

-- Decision 121: raised from 24 now that the row pool lives inside a
-- scroll area (see ensureWindow below) instead of a fixed-height
-- window that just grew taller with every row -- headroom is now
-- cheap since a tall pool just scrolls rather than pushing the window
-- off-screen.
local MAX_ROWS = 60

-- Decision 121: a SECOND, separate row pool purpose-built for the new
-- LINES tab's per-destination cargo-icon breakdown (full parity with
-- the old panel's own managed-line display). Deliberately NOT folded
-- into the plain `state.rows` pool above: every other tab already
-- relies on a single full-width text row (e.g. SERVICES' padded
-- "Service / Current / Target / Waiting / Delta" table) -- narrowing
-- that shared pool's label to make room for a waiting-count column and
-- cargo icons would break every one of those tabs' formatting. Same
-- "pre-allocate once" reasoning as the plain pool; both pools live
-- inside the same scroll area (see ensureWindow) so an unused pool
-- just costs (blank) scroll space, not permanent window height.
local MAX_LINE_ROWS = 48
local LINE_ROW_LABEL_WIDTH = 260
local LINE_ROW_WAITING_WIDTH = 90
local LINE_ROW_CARGO_SLOTS = 3
local LINE_ROW_CARGO_COUNT_WIDTH = 70

-- setTransparent(true) does not hide an imageView's image content
-- (confirmed live in the old panel: unused slots rendered a visible
-- placeholder glyph instead of nothing), only setText("") reliably
-- hides text -- same real texture swap the old panel already uses to
-- hide unused icon slots.
local BLANK_CARGO_ICON = "ui/hud/empty12.tga"

-- Decision 71: a pool of pre-allocated, reusable action-button slots,
-- same "pre-allocate once, refill on tab switch" reasoning as the row
-- pool above (native TF2 UI component IDs cannot be created on demand
-- -- see this file's own header comment). A tab's refresh() function
-- claims however many of these it needs each time it runs (e.g.
-- OVERVIEW's Split/Distribution Hub/Assign & Balance/Re-Organize
-- Terminals/Rename Fleet buttons) by setting a slot's label text and
-- .handler function; unused slots are blanked the same way unused text
-- rows already are. Every slot's onClick is wired exactly ONCE, at
-- window-creation time, to call whatever .handler is CURRENTLY set on
-- that slot -- deliberately avoids ever needing to call :onClick a
-- second time on the same button (whether that stacks or replaces
-- handlers has never been tested in this codebase, so this sidesteps
-- the question entirely rather than assuming either answer).
local ACTION_BUTTON_COUNT = 8

local TABS = {
    tab_overview,
    tab_lines,
    tab_hubs,
    tab_services,
    tab_fleet,
    tab_terminals,
    tab_cargo,
    tab_activity,
    tab_settings
}

local state = {
    window = nil,
    visible = false,
    activeTabIndex = 1,
    tabButtonLabels = {},
    tabButtons = {},
    headerLabel = nil,
    rows = nil,
    lineRows = nil,
    actionButtons = nil,
    closedByUser = false
}


local function positionWindow()

    if game == nil or game.gui == nil then
        return
    end

    local okRect, screenRect =
        pcall(game.gui.getContentRect, "mainView")

    if not okRect or screenRect == nil then
        return
    end

    -- Top-LEFT, deliberately opposite corner from the existing Truck
    -- Distribution window (which docks top-right) -- both can be open
    -- side by side during testing without overlapping.
    local margin = 20

    pcall(
        game.gui.window_setPosition,
        WINDOW_ID,
        margin,
        margin
    )

end


-- Decision 81: also resets style class list, not just text. Rows are
-- a shared, reused pool across every tab and every refresh (native
-- component IDs can't be recreated on demand -- this file's own
-- header comment) -- a style class set by one tab's refresh (e.g.
-- FLEET flagging row 4 as idle) otherwise stays on that row object
-- forever, silently bleeding into whatever the NEXT tab (or the same
-- tab's next non-flagged render) puts in that row. Live-confirmed
-- real bug: OVERVIEW's plain "Total vehicles"/"Total waiting"/
-- "Terminals" rows and even an "Auto Redistribute: ON" row all showed
-- the orange warning color, despite gui_tab_overview.lua never
-- setting a style on them -- leftover from whichever tab/condition
-- last touched those row indices.
local function clearRow(row)

    row.label:setText("", ROW_WIDTH)
    pcall(row.label.setStyleClassList, row.label, {})

end


local function clearAllRows()

    if state.rows == nil then
        return
    end

    for _, row in ipairs(state.rows) do
        clearRow(row)
    end

end


-- Same reused-object leak as clearRow above, extended to the richer
-- LINES-tab row shape (waiting count + cargo icon/count pairs).
local function clearLineRow(row)

    row.label:setText("", LINE_ROW_LABEL_WIDTH)
    pcall(row.label.setStyleClassList, row.label, {})

    row.waitingLabel:setText("", LINE_ROW_WAITING_WIDTH)

    for slotIndex = 1, LINE_ROW_CARGO_SLOTS do

        row.cargoIcons[slotIndex]:setImage(BLANK_CARGO_ICON)
        pcall(row.cargoIcons[slotIndex].setTransparent, row.cargoIcons[slotIndex], true)

        pcall(row.cargoCounts[slotIndex].setTransparent, row.cargoCounts[slotIndex], true)
        row.cargoCounts[slotIndex]:setText("", LINE_ROW_CARGO_COUNT_WIDTH)

    end

end


local function clearAllLineRows()

    if state.lineRows == nil then
        return
    end

    for _, row in ipairs(state.lineRows) do
        clearLineRow(row)
    end

end


-- Blanks every action-button slot's label, drops its handler, AND
-- resets its style class list (Decision 81 -- same reused-object
-- leak as clearRow above, applies equally to buttons).
local function clearActionButtons()

    if state.actionButtons == nil then
        return
    end

    for _, slot in ipairs(state.actionButtons) do
        slot.label:setText("", WINDOW_WIDTH)
        slot.handler = nil
        pcall(slot.button.setStyleClassList, slot.button, {})
    end

end


-- Re-renders whichever tab is currently active into the shared row
-- pool. Safe to call often -- it's just setText calls, same cost
-- profile as the existing panel's own refresh.
function M.refresh(hubStationGroupId)

    if not state.visible or state.window == nil then
        return
    end

    if state.rows == nil then
        return
    end

    clearAllRows()
    clearAllLineRows()
    clearActionButtons()

    local activeTab = TABS[state.activeTabIndex]

    if activeTab == nil then
        return
    end

    -- lineRows is a 4th, additive argument -- every existing tab's
    -- refresh(rows, hubStationGroupId, actionButtons) signature still
    -- works unchanged; only gui_tab_lines.lua reads the extra value.
    local ok, err =
        pcall(activeTab.refresh, state.rows, hubStationGroupId, state.actionButtons, state.lineRows)

    if not ok then

        log.info(
            "GUI MANAGER: refresh failed for tab \""
                .. tostring(activeTab.getLabel())
                .. "\": " .. tostring(err)
        )

    end

end


-- Decision 80: tab look now driven primarily by style class (via the
-- shared button, not just its label -- a button's background is what
-- actually reads as a "tab" visually), with the old bracket text kept
-- as a cheap fallback marker in case setStyleClassList turns out not
-- to apply from gui.lua's wrapper side (unverified from this side --
-- see the style sheet's own Decision 80 note). Either signal alone is
-- enough to tell tabs apart; having both costs nothing.
local function selectTab(tabIndex, hubStationGroupId)

    state.activeTabIndex = tabIndex

    for index, label in ipairs(state.tabButtonLabels) do

        local tabModule = TABS[index]
        local isActive = index == tabIndex
        local text = (isActive and "> " or "  ") .. tostring(tabModule.getLabel())

        label:setText(text, WINDOW_WIDTH / #TABS)

        local button = state.tabButtons[index]

        if button ~= nil then

            pcall(
                button.setStyleClassList,
                button,
                { isActive and "EpodTdTabActive" or "EpodTdTabInactive" }
            )

        end

    end

    M.refresh(hubStationGroupId)

end


local function ensureWindow(hubStationGroupId)

    if state.closedByUser then
        return nil
    end

    if api == nil or api.gui == nil or api.gui.util == nil then
        return nil
    end

    local existing = api.gui.util.getById(WINDOW_ID)

    if existing ~= nil then
        return existing
    end

    state.rows = nil

    local layout =
        gui.boxLayout_create(WINDOW_ID .. ".layout", "VERTICAL")

    local window =
        gui.window_create(WINDOW_ID, "DD Central Manager (TEST)", layout)

    window:onClose(function()
        state.closedByUser = true
        state.visible = false
        log.info("GUI MANAGER: window closed by user.")
    end)

    state.headerLabel =
        gui.textView_create(
            WINDOW_ID .. ".header",
            "DD Central Manager -- HUBS/ACTIVITY/SETTINGS still placeholders",
            WINDOW_WIDTH,
            false
        )

    pcall(state.headerLabel.setStyleClassList, state.headerLabel, { "EpodTdHeader" })

    layout:addItem(state.headerLabel)

    local tabRow =
        gui.boxLayout_create(WINDOW_ID .. ".tabRow", "HORIZONTAL")

    state.tabButtonLabels = {}
    state.tabButtons = {}

    for index, tabModule in ipairs(TABS) do

        local label =
            gui.textView_create(
                WINDOW_ID .. ".tabLabel." .. tostring(index),
                "[ " .. tostring(tabModule.getLabel()) .. " ]",
                WINDOW_WIDTH / #TABS,
                false
            )

        local button =
            gui.button_create(
                WINDOW_ID .. ".tabButton." .. tostring(index),
                label
            )

        button:onClick(function()
            selectTab(index, hubStationGroupId)
        end)

        tabRow:addItem(button)

        state.tabButtonLabels[index] = label
        state.tabButtons[index] = button

    end

    layout:addItem(tabRow)

    -- Decision 71: pre-allocated action-button pool, shared across
    -- tabs the same way the row pool below is. Positioned above the
    -- info rows so a tab's controls read naturally above its display
    -- content.
    state.actionButtons = {}

    for slotIndex = 1, ACTION_BUTTON_COUNT do

        local label =
            gui.textView_create(
                WINDOW_ID .. ".actionLabel." .. tostring(slotIndex),
                "",
                WINDOW_WIDTH,
                false
            )

        local button =
            gui.button_create(
                WINDOW_ID .. ".actionButton." .. tostring(slotIndex),
                label
            )

        button:onClick(function()

            local slot = state.actionButtons[slotIndex]

            if slot ~= nil and slot.handler ~= nil then

                local ok, err = pcall(slot.handler)

                if not ok then

                    log.info(
                        "GUI MANAGER: action button "
                            .. tostring(slotIndex)
                            .. " handler failed: " .. tostring(err)
                    )

                end

            end

        end)

        layout:addItem(button)

        state.actionButtons[slotIndex] = { label = label, button = button, handler = nil }

    end

    -- Decision 121 follow-up (LIVE-CONFIRMED FAILURE): gui.scrollArea_
    -- create was tried here to wrap the row pools, on the theory that
    -- it's the one scroll primitive that stays inside the gui.lua
    -- wrapper system (see the old comment this replaced, and the
    -- research trail in DECISIONS.md). Live result: the header and tab
    -- row rendered fine, but the ENTIRE scrolled content area came up
    -- completely blank -- not merely unscrollable, genuinely invisible,
    -- across every tab including ones with no scrolling-related change
    -- at all. gui.lua's own scrollAreaMetatable is empty (no exposed
    -- size hint / scroll-bar-policy setter), so the scroll area
    -- apparently collapses to a zero/near-zero preferred size with
    -- nothing telling it otherwise, hiding its own children. Reverted:
    -- `contentLayout` (holding both row pools) is added DIRECTLY to
    -- the window again, exactly like before this attempt -- a working,
    -- non-scrolling window beats a broken scrolling one. Real
    -- scrolling in this window remains an open problem; MAX_ROWS/
    -- MAX_LINE_ROWS stay raised since bigger pre-allocated pools are
    -- harmless even without a scroll area, just unused headroom.
    local contentLayout =
        gui.boxLayout_create(WINDOW_ID .. ".contentLayout", "VERTICAL")

    state.rows = {}

    for rowIndex = 1, MAX_ROWS do

        local label =
            gui.textView_create(
                WINDOW_ID .. ".row." .. tostring(rowIndex) .. ".label",
                "",
                ROW_WIDTH,
                false
            )

        contentLayout:addItem(label)

        state.rows[rowIndex] = { label = label }

    end

    -- Decision 121: LINES tab's icon-rich row pool -- one horizontal
    -- boxLayout per row (label + waiting count + LINE_ROW_CARGO_SLOTS
    -- icon/count pairs), exactly the same per-row structure the old
    -- panel's own ensureDistributionWindow already proved live, just
    -- rebuilt here for the new GUI's shared framework.
    state.lineRows = {}

    for rowIndex = 1, MAX_LINE_ROWS do

        local rowPrefix = WINDOW_ID .. ".lineRow." .. tostring(rowIndex)

        local rowLayout =
            gui.boxLayout_create(rowPrefix .. ".row", "HORIZONTAL")

        local labelView =
            gui.textView_create(rowPrefix .. ".label", "", LINE_ROW_LABEL_WIDTH, false)

        rowLayout:addItem(labelView)

        local waitingView =
            gui.textView_create(rowPrefix .. ".waiting", "", LINE_ROW_WAITING_WIDTH, false)

        rowLayout:addItem(waitingView)

        local cargoIcons = {}
        local cargoCounts = {}

        for cargoSlotIndex = 1, LINE_ROW_CARGO_SLOTS do

            local iconView =
                gui.imageView_create(
                    rowPrefix .. ".cargoIcon." .. tostring(cargoSlotIndex),
                    BLANK_CARGO_ICON
                )

            local countView =
                gui.textView_create(
                    rowPrefix .. ".cargoCount." .. tostring(cargoSlotIndex),
                    "",
                    LINE_ROW_CARGO_COUNT_WIDTH,
                    false
                )

            pcall(iconView.setTransparent, iconView, true)
            pcall(countView.setTransparent, countView, true)

            rowLayout:addItem(iconView)
            rowLayout:addItem(countView)

            cargoIcons[cargoSlotIndex] = iconView
            cargoCounts[cargoSlotIndex] = countView

        end

        contentLayout:addItem(rowLayout)

        state.lineRows[rowIndex] = {
            label = labelView,
            waitingLabel = waitingView,
            cargoIcons = cargoIcons,
            cargoCounts = cargoCounts
        }

    end

    layout:addItem(contentLayout)

    -- Decision 72: SETTINGS tab's one-time GUI-element experiment
    -- (slider/comboBox/toggleButton/imageView). Wrapped in this file's
    -- OWN pcall too, on top of every individual element's own internal
    -- pcall in gui_tab_settings.lua -- this is genuinely unproven code,
    -- and a failure here must never take down the rest of the window
    -- (header/tabs/action buttons/rows are already built above this
    -- point either way).
    if tab_settings.build ~= nil then

        local okSettingsBuild, settingsBuildErr = pcall(tab_settings.build, layout)

        if not okSettingsBuild then

            log.info(
                "GUI MANAGER: SETTINGS tab experimental build failed: "
                    .. tostring(settingsBuildErr)
            )

        end

    end

    state.window = window

    positionWindow()

    return window

end


-- Shows the window (creating it once, on first call) if hidden,
-- hides it if shown. Called from a temporary button on the existing
-- panel -- see epod_truck_distribution.lua.
function M.toggleVisibility(hubStationGroupId)

    if state.visible then

        if state.window ~= nil then
            pcall(function() state.window:close() end)
        end

        state.visible = false

        return

    end

    state.closedByUser = false

    local window = ensureWindow(hubStationGroupId)

    if window == nil then
        log.info("GUI MANAGER: could not create window.")
        return
    end

    state.visible = true

    selectTab(state.activeTabIndex, hubStationGroupId)

end


return M
