local log = require("epod_td.log")
local hub_registry = require("epod_td.hub_registry")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")

local M = {}


-- ============================================================
-- RAW-SYSTEM GUI EXPERIMENT (Decision 75/76)
--
-- Completely separate from gui_manager.lua's "DD Central Manager"
-- window -- deliberately so. That window is built entirely on
-- gui.lua's ID-string wrapper; this one is built entirely on the raw
-- api.gui.comp.*/api.gui.layout.* class system, matching the exact
-- pattern confirmed working in a real, shipped mod ("Move It
-- Enhanced" -- res/scripts/move_it_enhanced/gui.lua/gui_util.lua).
-- The two object systems must never mix (Decision 73's crash was
-- exactly that) -- this file requires NOTHING from require("gui"),
-- on purpose, so there is no way to accidentally cross the streams.
--
-- Real, working live data (enabled hubs, managed lines, a real cargo
-- icon), but the Slider/CheckBox/action button are demo-only for now
-- -- proving the components render and respond, not wired into real
-- dispatch decisions yet. That's a deliberate next step, not this
-- one.
-- ============================================================

local state = {
    window = nil,
    selectedHubId = nil,
    hubContentLabel = nil,
    sliderValueLabel = nil
}


local function findAnyLiveCargoIconPath()

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

                                    local path = demand.getCargoTypeIconPath(cargoType)

                                    if path ~= nil then
                                        return path
                                    end

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


local function refreshHubContent()

    if state.hubContentLabel == nil then
        return
    end

    if state.selectedHubId == nil then
        state.hubContentLabel:setText("No hub selected.")
        return
    end

    local ok, text =
        pcall(function()

            local hubName = stations.getEntityName(state.selectedHubId)
            local managedLines = vehicles.getManagedLinesForStation(state.selectedHubId)

            local totalVehicles = 0

            for _, lineInfo in ipairs(managedLines) do
                totalVehicles = totalVehicles + (lineInfo.vehicleCount or 0)
            end

            return tostring(hubName) .. "  --  "
                .. tostring(#managedLines) .. " service(s), "
                .. tostring(totalVehicles) .. " vehicle(s)"

        end)

    state.hubContentLabel:setText(ok and text or "Could not read hub data.")

end


local function buildHubSegments(outerLayout)

    local hubIds = hub_registry.getEnabledHubs()

    if #hubIds == 0 then

        local none = api.gui.comp.TextView.new("(no enabled hubs yet)")
        outerLayout:addItem(none)
        return

    end

    local group = api.gui.comp.ToggleButtonGroup.new(api.gui.util.Alignment.HORIZONTAL, 10, false)

    for _, hubId in ipairs(hubIds) do

        local hubName = stations.getEntityName(hubId)

        local segmentText = api.gui.comp.TextView.new(tostring(hubName))
        local segmentButton = api.gui.comp.ToggleButton.new(segmentText)

        segmentButton:addStyleClass("EpodTdSegmentButton")

        segmentButton:onToggle(function(selected)

            if selected then
                state.selectedHubId = hubId
                refreshHubContent()
            end

        end)

        group:add(segmentButton)

        if state.selectedHubId == nil then
            state.selectedHubId = hubId
            segmentButton:setSelected(true, false)
        end

    end

    group:setOneButtonMustAlwaysBeSelected(true)
    outerLayout:addItem(group)

end


local function buildWindow()

    local root = api.gui.layout.BoxLayout.new("VERTICAL")

    -- Header: real cargo icon (live data) + title, styled via the new
    -- style sheet (Decision 76).
    local header = api.gui.layout.BoxLayout.new("HORIZONTAL")
    local headerContainer = api.gui.comp.Component.new("")
    headerContainer:setLayout(header)
    headerContainer:addStyleClass("EpodTdHeader")

    local iconPath = findAnyLiveCargoIconPath()

    if iconPath ~= nil then

        local ok, icon =
            pcall(function()

                local view = api.gui.comp.ImageView.new(iconPath)
                view:setMinimumSize(api.gui.util.Size.new(28, 28))
                view:setMaximumSize(api.gui.util.Size.new(28, 28))
                return view

            end)

        if ok and icon ~= nil then
            header:addItem(icon)
        end

    end

    header:addItem(api.gui.comp.TextView.new("DYNAMIC DISTRIBUTION"))
    root:addItem(headerContainer)

    -- Hub picker: real, live enabled hubs, as a segmented toggle group
    -- -- the working replacement for last night's crashed ComboBox
    -- attempt, this time never mixed with gui.lua.
    local hubSectionLabel = api.gui.comp.TextView.new("Select hub:")
    hubSectionLabel:addStyleClass("EpodTdSectionLabel")
    root:addItem(hubSectionLabel)

    local segmentRow = api.gui.layout.BoxLayout.new("HORIZONTAL")
    buildHubSegments(segmentRow)
    root:addItem(segmentRow)

    state.hubContentLabel = api.gui.comp.TextView.new("")
    root:addItem(state.hubContentLabel)
    refreshHubContent()

    -- Demo slider -- the player's own "manually favour a line with
    -- more trucks" idea. Logs/reflects live, not yet wired to any
    -- real dispatch decision.
    local sliderRow = api.gui.layout.BoxLayout.new("HORIZONTAL")
    local sliderLabel = api.gui.comp.TextView.new("Truck bias (demo):")
    sliderLabel:addStyleClass("EpodTdSectionLabel")
    sliderRow:addItem(sliderLabel)

    local slider = api.gui.comp.Slider.new(true)
    slider:setMinimum(-10)
    slider:setMaximum(10)
    slider:setStep(1)
    slider:setPageStep(1)
    slider:setValue(0, false)

    state.sliderValueLabel = api.gui.comp.TextView.new("0")

    slider:onValueChanged(function()

        local value = slider:getValue()
        state.sliderValueLabel:setText(tostring(value))
        log.info("GUI EXPERIMENT (raw system): truck bias slider changed to " .. tostring(value))

    end)

    sliderRow:addItem(slider)
    sliderRow:addItem(state.sliderValueLabel)
    root:addItem(sliderRow)

    -- Demo checkbox.
    local checkBox = api.gui.comp.CheckBox.new("Auto Redistribute (demo only, not wired up)")
    checkBox:setTooltip("Proof-of-concept only -- does not change any real hub setting yet.")

    checkBox:onToggle(function(selected)
        log.info("GUI EXPERIMENT (raw system): demo checkbox changed to " .. tostring(selected))
    end)

    root:addItem(checkBox)

    -- Styled action button.
    local actionButton = api.gui.comp.Button.new(api.gui.comp.TextView.new("Test Action"), false)
    actionButton:addStyleClass("EpodTdPrimaryButton")

    actionButton:onClick(function()
        log.info("GUI EXPERIMENT (raw system): Test Action clicked, hub=" .. tostring(state.selectedHubId))
    end)

    root:addItem(actionButton)

    local window = api.gui.comp.Window.new("DD -- Raw UI Experiment", root)
    window:addHideOnCloseHandler()
    window:setVisible(false, false)

    return window

end


function M.toggleVisibility()

    if state.window == nil then

        local ok, result = pcall(buildWindow)

        if not ok or result == nil then

            log.info("GUI EXPERIMENT (raw system): window build failed: " .. tostring(result))
            return

        end

        state.window = result

    end

    local ok, err =
        pcall(function()

            local currentlyVisible = state.window:isVisible()
            state.window:setVisible(not currentlyVisible, false)

        end)

    if not ok then
        log.info("GUI EXPERIMENT (raw system): toggleVisibility failed: " .. tostring(err))
    end

end


return M
