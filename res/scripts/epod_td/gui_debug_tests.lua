local log = require("epod_td.log")
local gui = require("gui")

local M = {}


-- ============================================================
-- DEBUG TESTS WINDOW
--
-- Decision 120: player's request to "migrate everything to gui" --
-- the genuinely diagnostic/one-off buttons (Assign & Balance Fleet,
-- Rename Fleet to Hub Identity, Show Fleet Plan, Dump All Managed
-- Lines, Fleet Balance Report, Cargo Balance Inspector, Industry
-- Discovery, Dedupe Shared Route Lines) used to live directly on the
-- old "Truck Distribution" panel, behind a "Show/Hide Debug Tools"
-- toggle. They now live in their own standalone window, opened via a
-- button on the new GUI's SETTINGS tab, matching the same "declutter
-- the main panel" goal that toggle was originally built for -- just
-- a separate window instead of a collapsed section on the same one.
--
-- GUI ONLY, same rule as every gui_tab_*.lua file: this module owns
-- no logic of its own. epod_truck_distribution.lua calls
-- M.registerActions(...) once, at load time, handing over the SAME
-- handler functions the old panel's buttons used to call directly --
-- nothing about what any button actually DOES has changed, only
-- where its button lives. A handler that needs to write "busy"/
-- "done" status back onto its own button (Assign & Balance, Rename
-- Fleet, Dedupe Shared Route Lines) does so via M.getLabel(key),
-- looked up by the same key it was registered under.
--
-- Built entirely from gui.lua's proven-safe primitives (window /
-- boxLayout / button / textView), the same library every other
-- window in this codebase already uses safely -- no raw api.gui.
-- comp.* objects cross into this layout tree (see Decisions 72/73/75
-- for why that mix is the one thing that has ever crashed this mod).
-- ============================================================

local WINDOW_ID = "ddDebugToolsWindow"
local WINDOW_WIDTH = 560

local actions = {}

local state = {
    window = nil,
    visible = false,
    closedByUser = false,
    labels = {}
}


function M.registerActions(actionList)
    actions = actionList or {}
end


-- Lets a caller (the SETTINGS tab's "Open Debug Tests" button) avoid
-- showing an entry point to an empty window -- true only once a
-- non-empty action list has actually been registered (config.DEBUG
-- builds only, see epod_truck_distribution.lua).
function M.hasActions()
    return #actions > 0
end


-- Returns the live textView for a registered action's button, keyed
-- by the same `key` it was registered under -- nil until the window
-- has been opened at least once this session (same "allocated once,
-- on first build" rule as gui_manager.lua's row/action-button pools).
function M.getLabel(key)
    return state.labels[key]
end


local function ensureWindow()

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

    state.labels = {}

    local layout =
        gui.boxLayout_create(WINDOW_ID .. ".layout", "VERTICAL")

    local window =
        gui.window_create(WINDOW_ID, "Debug Tests", layout)

    window:onClose(function()
        state.closedByUser = true
        state.visible = false
        log.info("DEBUG TOOLS: window closed by user.")
    end)

    for _, action in ipairs(actions) do

        local label =
            gui.textView_create(
                WINDOW_ID .. "." .. action.key .. ".label",
                "[ " .. action.label .. " ]",
                WINDOW_WIDTH,
                false
            )

        local button =
            gui.button_create(
                WINDOW_ID .. "." .. action.key .. ".button",
                label
            )

        button:onClick(function()

            local ok, err = pcall(action.handler)

            if not ok then

                log.info(
                    "DEBUG TOOLS: \"" .. tostring(action.label)
                        .. "\" handler failed: " .. tostring(err)
                )

            end

        end)

        layout:addItem(button)

        state.labels[action.key] = label

    end

    state.window = window

    return window

end


-- Shows the window (creating it once, on first call) if hidden, hides
-- it if shown -- same toggle pattern as gui_manager.M.toggleVisibility
-- and gui_experiment.M.toggleVisibility.
function M.toggleVisibility()

    if state.visible then

        if state.window ~= nil then
            pcall(function() state.window:close() end)
        end

        state.visible = false

        return

    end

    state.closedByUser = false

    local window = ensureWindow()

    if window == nil then
        log.info("DEBUG TOOLS: could not create window.")
        return
    end

    state.visible = true

end


return M
