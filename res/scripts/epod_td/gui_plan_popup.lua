local gui = require("epod_td.raw_gui_compat")
local log = require("epod_td.log")

local M = {}


-- ============================================================
-- REUSABLE PLAN / DETAIL POPUP
--
-- Player's request: "if you press turn into Hub it will then present
-- the player with a full report on what it plans to do... Rename 45
-- trucks", confirmed to gate the real action behind an explicit
-- [ Confirm ] click rather than converting immediately. Built as a
-- standalone module (not part of gui_central_raw.lua) specifically so
-- gui_tab_overview.lua can require it directly with no risk of a
-- require cycle -- gui_central_raw.lua is the one requiring every
-- gui_tab_*.lua file, never the reverse.
--
-- Generic on purpose: `M.show(title, lines, confirmHandler)` -- pass a
-- real function for confirmHandler to show a real [ Confirm ] button
-- (Make Hub's plan preview), or nil for a view-only report with just
-- [ Close ] (a future per-station "Detail" report can reuse this
-- unchanged).
-- ============================================================

local WINDOW_WIDTH = 560
local MAX_ROWS = 30

-- Fixed visible height for the scrollable row area (Decision 173) --
-- deliberately shorter than MAX_ROWS' full content height, so a report
-- longer than roughly a dozen-odd rows visibly needs to scroll rather
-- than the popup just growing tall enough to show everything. A
-- starting guess, not tuned against real rendered row height yet.
local ROWS_VIEWPORT_HEIGHT = 360

local state = {
    window = nil,
    visible = false,
    titleLabel = nil,
    rows = {},
    confirmButton = nil,
    confirmButtonLabel = nil,
    confirmHandler = nil
}


local function setRowsVisibleUpTo(count)

    for index, label in ipairs(state.rows) do
        pcall(label.setVisible, label, index <= count)
    end

end


local function ensureWindow()

    if state.window ~= nil then
        return state.window
    end

    local layout = gui.boxLayout_create(nil, "VERTICAL")

    state.titleLabel = gui.textView_create(nil, "", WINDOW_WIDTH, false)
    pcall(state.titleLabel.setStyleClassList, state.titleLabel, { "EpodTdSectionHeading" })
    layout:addItem(state.titleLabel)

    -- Decision 173: real rows overflowing this popup's fixed height was
    -- exactly the class of bug just hit live (the clipped Fleet Needs
    -- Report row) -- rows now live inside their own scrollable viewport
    -- instead of being added straight to the window's layout, so a
    -- report longer than MAX_ROWS visible rows scrolls instead of
    -- clipping or needing pagination. NOT yet independently live-tested
    -- by this mod -- see raw_gui_compat.lua's scrollArea_create header.
    local rowsContainer = gui.container_create(nil)
    local rowsLayout = gui.boxLayout_create(nil, "VERTICAL")
    rowsContainer:setLayout(rowsLayout)

    state.rows = {}

    for rowIndex = 1, MAX_ROWS do

        local label = gui.textView_create(nil, "", WINDOW_WIDTH, false)
        rowsLayout:addItem(label)

        state.rows[rowIndex] = label

    end

    local rowsScrollArea = gui.scrollArea_create(nil, rowsContainer)
    pcall(rowsScrollArea.setMinimumSize, rowsScrollArea, WINDOW_WIDTH, ROWS_VIEWPORT_HEIGHT)
    pcall(rowsScrollArea.setMaximumSize, rowsScrollArea, WINDOW_WIDTH, ROWS_VIEWPORT_HEIGHT)
    layout:addItem(rowsScrollArea)

    local buttonRow = gui.boxLayout_create(nil, "HORIZONTAL")

    local confirmLabel = gui.textView_create(nil, "[ Confirm ]", 220, false)
    local confirmButton = gui.button_create(nil, confirmLabel)
    pcall(confirmButton.setMaximumSize, confirmButton, 220, 2000)

    confirmButton:onClick(function()

        if state.confirmHandler ~= nil then

            local handler = state.confirmHandler
            state.confirmHandler = nil

            M.hide()

            local ok, err = pcall(handler)

            if not ok then
                log.info("GUI PLAN POPUP: confirm handler failed: " .. tostring(err))
            end

        end

    end)

    pcall(confirmButton.setStyleClassList, confirmButton, { "EpodTdPrimaryButton" })
    buttonRow:addItem(confirmButton)

    state.confirmButton = confirmButton
    state.confirmButtonLabel = confirmLabel

    local closeLabel = gui.textView_create(nil, "[ Cancel ]", 220, false)
    local closeButton = gui.button_create(nil, closeLabel)
    pcall(closeButton.setMaximumSize, closeButton, 220, 2000)

    closeButton:onClick(function()
        state.confirmHandler = nil
        M.hide()
    end)

    buttonRow:addItem(closeButton)

    layout:addItem(buttonRow)

    local window = gui.window_create(nil, "Station Report", layout)

    pcall(window.addHideOnCloseHandler, window)

    window:onClose(function()
        state.visible = false
        state.confirmHandler = nil
    end)

    pcall(window.setPosition, window, 80, 80)

    -- Decision 173: shrunk from a fixed 720 now that rows scroll within
    -- their own ROWS_VIEWPORT_HEIGHT instead of the window itself
    -- needing to be tall enough to show all MAX_ROWS at once -- title
    -- (~30) + scroll viewport (ROWS_VIEWPORT_HEIGHT) + button row (~50)
    -- plus margin. A starting guess, not pixel-tuned yet.
    pcall(window.setSize, window, WINDOW_WIDTH + 40, ROWS_VIEWPORT_HEIGHT + 160)

    state.window = window

    return window

end


-- `lines` is a plain array, one entry per row (capped at MAX_ROWS -- a
-- hub with more planned lines than that gets truncated, same
-- "reasonable ceiling, not exact-fit" convention every other pool in
-- this codebase uses). Each entry is either a plain string (default
-- text styling, unchanged from before) or a table
-- `{ text = "...", style = "warning" }` for a row that needs to stand
-- out -- "warning" reuses this codebase's own proven `EpodTdDeltaNegative`
-- red (Decision 182, player's request: "show as red if there is a need
-- for trucks say over 10"), rather than inventing a new style class.
-- `confirmHandler`, if given, shows a real [ Confirm ] button that runs
-- it (and clears/hides the popup first); omit or pass nil for a view-
-- only report with just [ Cancel ].
local ROW_STYLE_CLASSES = {
    warning = { "EpodTdDeltaNegative" }
}

function M.show(title, lines, confirmHandler)

    local window = ensureWindow()

    pcall(state.titleLabel.setText, state.titleLabel, tostring(title or ""), WINDOW_WIDTH)

    local rowIndex = 0

    for _, entry in ipairs(lines or {}) do

        rowIndex = rowIndex + 1

        if rowIndex > #state.rows then
            break
        end

        local text = entry
        local styleClasses = {}

        if type(entry) == "table" then
            text = entry.text
            styleClasses = ROW_STYLE_CLASSES[entry.style] or {}
        end

        state.rows[rowIndex]:setText(tostring(text or ""), WINDOW_WIDTH)
        pcall(state.rows[rowIndex].setStyleClassList, state.rows[rowIndex], styleClasses)

    end

    setRowsVisibleUpTo(rowIndex)

    state.confirmHandler = confirmHandler
    pcall(state.confirmButton.setVisible, state.confirmButton, confirmHandler ~= nil)

    state.visible = true
    pcall(window.setVisible, window, true)

end


function M.hide()

    if state.window ~= nil then
        pcall(state.window.setVisible, state.window, false)
    end

    state.visible = false

end


return M
