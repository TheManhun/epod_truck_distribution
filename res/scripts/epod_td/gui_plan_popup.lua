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

    state.rows = {}

    for rowIndex = 1, MAX_ROWS do

        local label = gui.textView_create(nil, "", WINDOW_WIDTH, false)
        layout:addItem(label)

        state.rows[rowIndex] = label

    end

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
    pcall(window.setSize, window, WINDOW_WIDTH + 40, 720)

    state.window = window

    return window

end


-- `lines` is a plain array of strings, one per row (capped at
-- MAX_ROWS -- a hub with more planned lines than that gets truncated,
-- same "reasonable ceiling, not exact-fit" convention every other
-- pool in this codebase uses). `confirmHandler`, if given, shows a
-- real [ Confirm ] button that runs it (and clears/hides the popup
-- first); omit or pass nil for a view-only report with just [ Cancel ].
function M.show(title, lines, confirmHandler)

    local window = ensureWindow()

    pcall(state.titleLabel.setText, state.titleLabel, tostring(title or ""), WINDOW_WIDTH)

    local rowIndex = 0

    for _, text in ipairs(lines or {}) do

        rowIndex = rowIndex + 1

        if rowIndex > #state.rows then
            break
        end

        state.rows[rowIndex]:setText(tostring(text), WINDOW_WIDTH)

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
