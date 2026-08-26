local log = require("epod_td.log")
local gui = require("gui")
local hub_registry = require("epod_td.hub_registry")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local settings = require("epod_td.settings")

local M = {}


-- ============================================================
-- AUTO APPLY FLEET PLAN (on/off + interval)
--
-- Player's own idea, live-validated by hand: manually clicking "Apply
-- Fleet Plan" every 5-7 seconds took a badly imbalanced network
-- (deltas of +62, +25, +41) down to nearly flat within a couple of
-- minutes -- real proof this is worth automating, not just a guess.
-- dispatcher.applyPlan already has its OWN per-hub reentrancy guard
-- (applyPlanRunningByHub), so polling every enabled hub on a timer
-- needs no extra cross-hub coordination -- each hub's own guard
-- already prevents overlapping runs for that hub.
--
-- A real Slider was deliberately NOT used here: Decisions 72/73/75
-- documented a LIVE, REAL crash from mixing a raw api.gui.comp.Slider
-- into this exact window's gui.lua layout tree (a broken, unparented
-- native component survived to the engine's own shutdown consistency
-- check and hard-crashed the game). A cycling button through a fixed
-- set of values (OFF -> 5s -> 10s -> 15s -> 30s -> OFF) achieves the
-- same discrete choice using gui.lua's proven-safe button/textView
-- primitives, the exact same pattern every other toggle in this
-- codebase already uses.
-- ============================================================

local INTERVAL_CYCLE = { false, 5, 10, 15, 30 }


local function describeAutoApplyState(enabled, intervalSeconds)

    if enabled ~= true then
        return "OFF"
    end

    return "every " .. tostring(intervalSeconds) .. "s"

end


local function nextAutoApplyState(enabled, intervalSeconds)

    local currentIndex = 1

    for index, value in ipairs(INTERVAL_CYCLE) do

        if index == 1 then

            if enabled ~= true then
                currentIndex = index
            end

        elseif enabled == true and value == intervalSeconds then

            currentIndex = index

        end

    end

    local nextIndex = currentIndex + 1

    if nextIndex > #INTERVAL_CYCLE then
        nextIndex = 1
    end

    local nextValue = INTERVAL_CYCLE[nextIndex]

    if nextValue == false then
        return false, intervalSeconds
    end

    return true, nextValue

end


-- ============================================================
-- SETTINGS TAB (gui_manager.lua) -- PLACEHOLDER
--
-- GUI_Plan.md: Auto Redistribute / rename-fleet toggles per hub,
-- sourced from hub_registry.lua and settings.lua. Not built yet --
-- these already exist as buttons on the current panel; this tab
-- would just present the same state differently.
--
-- Decision 72/73/75: this tab was briefly repurposed as a GUI-element
-- experiment (Slider/ComboBox/ToggleButton/ImageView via raw
-- api.gui.comp.* constructors) passed into THIS window's gui.lua-based
-- layout tree. LIVE-CONFIRMED REAL CRASH: the ComboBox object was
-- created, but layout:addItem(comboBox) -- a gui.lua boxLayout method
-- that expects child.id to be a string -- threw a native "value is
-- not a string" exception, leaving a broken, unparented native
-- component in memory. On the next game close, the engine's own
-- shutdown consistency check (`CComponent::NumInstances() == 0`)
-- found that orphaned component still alive and hard-crashed.
--
-- CORRECTED CONCLUSION (Decision 75, after reading a real, mature,
-- shipped mod's source -- "Move It Enhanced"): it was never that
-- Slider/ComboBox/ToggleButton/CheckBox/List are unsafe components --
-- it's that mixing a raw api.gui.comp.* object into a gui.lua method
-- (which only knows how to forward a plain id string) is unsafe. Used
-- CONSISTENTLY within the raw system -- never crossed into gui.lua --
-- all of these are real and safe; see gui_experiment.lua, a
-- completely separate window built entirely on the raw system with a
-- working Slider/CheckBox/ToggleButtonGroup/styled Button, live-
-- confirmed with no crash on close. gui.lua's own wrapper still only
-- covers window/button/textView/boxLayout/imageView/table/scrollArea/
-- component -- so THIS window (built on gui.lua) still can't safely
-- use Slider/ComboBox/etc. directly; ImageView (via the real
-- gui.imageView_create wrapper) remains the one experiment element
-- confirmed safe to build on here. See DECISIONS.md Decisions 72/73/75
-- for the full evidence trail.
-- ============================================================

local WINDOW_WIDTH = 560


function M.getLabel()
    return "SETTINGS"
end


-- Opportunistically grabs one real, live numeric cargoType off
-- whatever any enabled hub's managed lines currently have waiting, so
-- an icon test uses a real value instead of a guessed one --
-- demand.getCargoTypeIconPath expects the raw numeric SIM_CARGO type,
-- not a string like "FOOD".
local function findAnyLiveCargoType()

    local ok, result =
        pcall(function()

            local hubIds = hub_registry.getEnabledHubs()

            for _, hubId in ipairs(hubIds) do

                local managedLines = vehicles.getManagedLinesForStation(hubId)

                for _, lineInfo in ipairs(managedLines) do

                    local scanResult = demand.scan(lineInfo.id, hubId)

                    if scanResult ~= nil and scanResult.destinations ~= nil then

                        for _, destination in pairs(scanResult.destinations) do

                            if destination.cargoTypes ~= nil then

                                for cargoType, _ in pairs(destination.cargoTypes) do
                                    return cargoType
                                end

                            end

                        end

                    end

                end

            end

            return nil

        end)

    if not ok then
        return nil
    end

    return result

end


-- Decision 74: pure read-only enumeration, no construction or
-- mutation calls at all -- zero risk, same reasoning as
-- dumpAvailableCommands elsewhere in this codebase. res/scripts/
-- gui.lua (read directly from the TF2 install dir) showed every
-- gui.xxx_create function is a thin wrapper that just calls the
-- matching game.gui.xxx_create(...) and stores the id string --
-- meaning game.gui is the REAL underlying native table, and gui.lua
-- only chose to wrap 9 of whatever it actually contains. This checks
-- directly whether game.gui exposes more component kinds (e.g. a
-- native tabWidget_create) that gui.lua simply never wrapped, rather
-- than assuming gui.lua's own subset is the full extent of what's
-- reachable.
local function dumpGameGuiModule()

    if game == nil or game.gui == nil then
        log.info("GUI EXPERIMENT: game.gui is not accessible from this context.")
        return
    end

    local names = {}

    local ok, err =
        pcall(function()

            for key, _ in pairs(game.gui) do
                names[#names + 1] = tostring(key)
            end

        end)

    if not ok then
        log.info("GUI EXPERIMENT: could not enumerate game.gui: " .. tostring(err))
        return
    end

    table.sort(names)

    log.info("----------------------------------------")
    log.info("GUI EXPERIMENT: game.gui contents (" .. tostring(#names) .. " entries)")
    log.info("----------------------------------------")

    for _, name in ipairs(names) do
        log.info("  " .. name)
    end

    log.info("----------------------------------------")

end


-- The one experiment element confirmed SAFE (Decision 72/73) -- built
-- via the real gui.imageView_create wrapper, not the raw comp.*
-- fallback that caused the ComboBox crash. Left in as a small,
-- harmless proof that a cargo icon can render in the new GUI.
function M.build(layout)

    dumpGameGuiModule()

    local cargoType = findAnyLiveCargoType()
    local iconPath = cargoType ~= nil and demand.getCargoTypeIconPath(cargoType) or nil

    if iconPath == nil then
        return
    end

    local ok, err =
        pcall(function()

            if gui.imageView_create ~= nil then

                local imageView =
                    gui.imageView_create("ddSettingsExperiment.image", iconPath)

                layout:addItem(imageView)

                log.info(
                    "GUI EXPERIMENT: ImageView -- added with path \""
                        .. tostring(iconPath) .. "\"."
                )

            end

        end)

    if not ok then

        log.info(
            "GUI EXPERIMENT: ImageView -- failed on this attempt: "
                .. tostring(err)
        )

    end

end


function M.refresh(rows, hubStationGroupId, actionButtons)

    if actionButtons ~= nil and actionButtons[1] ~= nil then

        local slot = actionButtons[1]

        local enabled = settings.get("autoApplyFleetPlanEnabled")
        local intervalSeconds = settings.get("autoApplyFleetPlanIntervalSeconds")

        slot.label:setText(
            "[ Auto Apply Fleet Plan: "
                .. describeAutoApplyState(enabled, intervalSeconds)
                .. " ]",
            WINDOW_WIDTH
        )

        pcall(slot.button.setStyleClassList, slot.button, { "EpodTdPrimaryButton" })

        slot.handler = function()

            local newEnabled, newInterval =
                nextAutoApplyState(enabled, intervalSeconds)

            settings.set("autoApplyFleetPlanEnabled", newEnabled)
            settings.set("autoApplyFleetPlanIntervalSeconds", newInterval)

            log.info(
                "SETTINGS: Auto Apply Fleet Plan -> "
                    .. describeAutoApplyState(newEnabled, newInterval)
            )

        end

    end

    rows[1].label:setText(
        "Moves real vehicles between managed lines, same as a manual "
            .. "\"Apply Fleet Plan\" click, just run automatically for "
            .. "every enabled hub on the interval above (5 vehicles max "
            .. "per hub per run, same safety cap as the manual button).",
        WINDOW_WIDTH
    )

    rows[2].label:setText(
        "GUI element experiment result (Decisions 72/73/75): Slider/ComboBox/"
            .. "ToggleButton are safe in the SEPARATE raw-API window "
            .. "(\"Open Raw UI Experiment\"), but not safe to mix into THIS "
            .. "window's gui.lua layout tree (that mix is what crashed once "
            .. "-- see DECISIONS.md). This is why the interval above cycles "
            .. "through a fixed button instead of a real slider.",
        WINDOW_WIDTH
    )

end


return M
