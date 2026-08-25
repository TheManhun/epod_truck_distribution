local log = require("epod_td.log")
local gui = require("gui")

local tab_overview = require("epod_td.gui_tab_overview")
local tab_hubs = require("epod_td.gui_tab_hubs")
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
local MAX_ROWS = 24

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


local function clearRow(row)

    row.label:setText("", ROW_WIDTH)

end


local function clearAllRows()

    if state.rows == nil then
        return
    end

    for _, row in ipairs(state.rows) do
        clearRow(row)
    end

end


-- Blanks every action-button slot's label and drops its handler --
-- same "reset before refill" treatment as clearAllRows above, so a
-- tab that only needs 2 of the 8 slots doesn't leave some other tab's
-- stale button (and stale handler) sitting there clickable.
local function clearActionButtons()

    if state.actionButtons == nil then
        return
    end

    for _, slot in ipairs(state.actionButtons) do
        slot.label:setText("", WINDOW_WIDTH)
        slot.handler = nil
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
    clearActionButtons()

    local activeTab = TABS[state.activeTabIndex]

    if activeTab == nil then
        return
    end

    local ok, err =
        pcall(activeTab.refresh, state.rows, hubStationGroupId, state.actionButtons)

    if not ok then

        log.info(
            "GUI MANAGER: refresh failed for tab \""
                .. tostring(activeTab.getLabel())
                .. "\": " .. tostring(err)
        )

    end

end


local function selectTab(tabIndex, hubStationGroupId)

    state.activeTabIndex = tabIndex

    for index, label in ipairs(state.tabButtonLabels) do

        local tabModule = TABS[index]
        local text = "[ " .. tostring(tabModule.getLabel()) .. " ]"

        if index == tabIndex then
            text = "[ *" .. tostring(tabModule.getLabel()) .. "* ]"
        end

        label:setText(text, WINDOW_WIDTH / #TABS)

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

    state.rows = {}

    for rowIndex = 1, MAX_ROWS do

        local label =
            gui.textView_create(
                WINDOW_ID .. ".row." .. tostring(rowIndex) .. ".label",
                "",
                ROW_WIDTH,
                false
            )

        layout:addItem(label)

        state.rows[rowIndex] = { label = label }

    end

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
