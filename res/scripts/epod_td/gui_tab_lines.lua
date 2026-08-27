local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local stations = require("epod_td.stations")
local lines = require("epod_td.lines")
local terminal_allocator = require("epod_td.terminal_allocator")
local operation_lock = require("epod_td.operation_lock")
local planner = require("epod_td.planner")
local dispatcher = require("epod_td.dispatcher")
local log = require("epod_td.log")

local M = {}


-- ============================================================
-- LINES rendering logic
--
-- Decision 121: player asked to move the old panel's full per-line,
-- per-destination breakdown (name, vehicle/waiting totals, and a
-- cargo-icon row per real destination) into the new GUI, full icon
-- parity with the old panel rather than a text-only summary.
--
-- Decision 129: moved off "DD Central Manager"'s shared row pool into
-- its own standalone window (gui_lines_window.lua) -- sharing one
-- pool with every other tab never let both coexist without one
-- permanently pushing the other down (Decisions 121/123/125/127/128
-- all tried and failed).
--
-- Decision 131: accordion + pagination rewrite. Once
-- api.gui.comp.Component:setVisible was live-confirmed to actually
-- show/hide a CHILD component while its parent window stays open (the
-- gui_experiment.lua visibility probe), the old "one flat pool of
-- rows, print everything" design became unnecessary -- a hub with 19
-- managed lines used to mean 19 lines' worth of destination detail all
-- visible at once. Now each line is its own clickable header button
-- (always visible, with its "N vehicles | N waiting" summary) plus a
-- detail panel of destination rows that's setVisible-collapsed unless
-- that line is the one currently expanded. Only one line expands at a
-- time (state.expandedLineKey, keyed by the real line entity id so it
-- survives page/hub switches correctly rather than pointing at
-- "whatever's now in slot 3"). Lines beyond one page's worth
-- (MAX_LINE_GROUPS_PER_PAGE) are reached via Prev/Next controls
-- instead of an ever-taller window.
--
-- GUI ONLY, same rule as every gui_tab_*.lua file -- reads
-- vehicles.getManagedLinesForStation / demand.scan / stations.lua,
-- calculates nothing of its own. state.expandedLineKey/currentPage is
-- UI-only interaction state owned by this tab (same precedent as
-- gui_tab_settings.lua's own experimental-widget state), not
-- simulation state -- it just remembers what the player clicked.
-- ============================================================

local MAX_LINE_GROUPS_PER_PAGE = 8
local MAX_DESTINATIONS_PER_LINE = 6

-- Must match the window-building file's own copies of these same
-- constants exactly -- the actual widgets are created at these
-- widths/slot counts.
local LINE_ROW_CARGO_SLOTS = 3
local LINE_ROW_LABEL_WIDTH = 350
local LINE_ROW_WAITING_WIDTH = 60
local LINE_ROW_CARGO_COUNT_WIDTH = 45

-- Decision 145: SERVICES merged into LINES -- the old single
-- summaryLabel ("N vehicles | N waiting | T2") split into three
-- separately-colorable widgets, since a style class colors an ENTIRE
-- TextView's text, never a sub-span within one. Player's request: the
-- delta number specifically needs its own red/white/green coloring
-- independent of the vehicle/waiting text either side of it.
local LINE_VEHICLES_WIDTH = 110
local LINE_DELTA_WIDTH = 45
local LINE_WAITING_TERMINAL_WIDTH = 150

local state = {
    expandedLineKey = nil,
    currentPage = 1
}


function M.getLabel()
    return "LINES"
end


local function formatWaitingLabel(scanResult, stationGroupId)

    if scanResult == nil or scanResult.error ~= nil then
        return "?"
    end

    local destination = demand.getDestination(scanResult, stationGroupId)

    if destination == nil then
        return "0"
    end

    return tostring(destination.total or 0)

end


local function renderCargoIcons(row, scanResult, stationGroupId)

    if row.cargoIcons == nil or row.cargoCounts == nil then
        return
    end

    local cargoTypes = demand.getSortedCargoTypesForDestination(scanResult, stationGroupId)

    for slotIndex = 1, LINE_ROW_CARGO_SLOTS do

        local iconView = row.cargoIcons[slotIndex]
        local countView = row.cargoCounts[slotIndex]
        local cargo = cargoTypes[slotIndex]

        if iconView == nil or countView == nil then

            -- pool doesn't support this many slots -- nothing to do

        elseif cargo == nil then

            pcall(iconView.setTransparent, iconView, true)
            pcall(countView.setTransparent, countView, true)
            countView:setText("", LINE_ROW_CARGO_COUNT_WIDTH)

        else

            local iconPath = demand.getCargoTypeIconPath(cargo.cargoType)

            if iconPath == nil then

                -- Icon lookup failed -- fall back to a readable text
                -- label rather than an invisible/broken icon, same
                -- fallback the old panel already uses.
                pcall(iconView.setTransparent, iconView, true)
                pcall(countView.setTransparent, countView, false)

                countView:setText(
                    demand.getCargoTypeDisplayName(cargo.cargoType) .. ": " .. tostring(cargo.count),
                    120
                )

            else

                iconView:setImage(iconPath)
                pcall(iconView.setTransparent, iconView, false)
                pcall(countView.setTransparent, countView, false)

                countView:setText(tostring(cargo.count), LINE_ROW_CARGO_COUNT_WIDTH)

            end

        end

    end

end


local function clearDestinationRow(row)

    if row.container ~= nil then
        row.container:setVisible(false)
    end

    row.label:setText("", LINE_ROW_LABEL_WIDTH)
    pcall(row.label.setStyleClassList, row.label, {})

    if row.waitingLabel ~= nil then
        row.waitingLabel:setText("", LINE_ROW_WAITING_WIDTH)
        pcall(row.waitingLabel.setStyleClassList, row.waitingLabel, {})
    end

    if row.cargoIcons ~= nil then

        for slotIndex = 1, LINE_ROW_CARGO_SLOTS do

            pcall(row.cargoIcons[slotIndex].setTransparent, row.cargoIcons[slotIndex], true)
            pcall(row.cargoCounts[slotIndex].setTransparent, row.cargoCounts[slotIndex], true)
            row.cargoCounts[slotIndex]:setText("", LINE_ROW_CARGO_COUNT_WIDTH)

        end

    end

end


local function clearGroup(group)

    group.headerButtonLabel:setText("", LINE_ROW_LABEL_WIDTH)
    pcall(group.headerButtonLabel.setStyleClassList, group.headerButtonLabel, {})

    group.vehiclesLabel:setText("", LINE_VEHICLES_WIDTH)
    pcall(group.vehiclesLabel.setStyleClassList, group.vehiclesLabel, {})

    group.deltaLabel:setText("", LINE_DELTA_WIDTH)
    pcall(group.deltaLabel.setStyleClassList, group.deltaLabel, {})

    group.waitingTerminalLabel:setText("", LINE_WAITING_TERMINAL_WIDTH)
    pcall(group.waitingTerminalLabel.setStyleClassList, group.waitingTerminalLabel, {})

    group.handler = nil

    if group.detailPanel ~= nil then
        group.detailPanel:setVisible(false)
    end

    for _, row in ipairs(group.destinationRows) do
        clearDestinationRow(row)
    end

end


-- Same "not just currently 0" visibility rule as the old panel
-- (stations.getItemTotals) -- a structurally pure drop-off town
-- doesn't get a permanent, always-empty "<- Town" row.
local function renderDestinations(group, lineInfo, hubStationGroupId, scanResult)

    if lineInfo.destinations == nil then
        return
    end

    local hubReturnHasNeverProduced = true

    for _, otherDestination in ipairs(lineInfo.destinations) do

        if otherDestination.stationGroup ~= hubStationGroupId then

            local okTotals, otherTotals = pcall(stations.getItemTotals, otherDestination.stationGroup)

            if okTotals and otherTotals ~= nil and otherTotals.loaded > 0 then
                hubReturnHasNeverProduced = false
            end

        end

    end

    local destinationRowIndex = 1
    local visibleDestinationCount = 0

    for _, destination in ipairs(lineInfo.destinations) do

        if destinationRowIndex > #group.destinationRows then
            break
        end

        local isHubReturnRow = destination.stationGroup == hubStationGroupId
        local skipRow = false

        if isHubReturnRow then

            skipRow = hubReturnHasNeverProduced

        else

            local okTotals, destinationTotals = pcall(stations.getItemTotals, destination.stationGroup)
            skipRow = (not okTotals) or destinationTotals == nil or destinationTotals.unloaded == 0

        end

        if not skipRow then

            visibleDestinationCount = visibleDestinationCount + 1

            if visibleDestinationCount > MAX_DESTINATIONS_PER_LINE then
                break
            end

            local row = group.destinationRows[destinationRowIndex]
            local directionArrow = isHubReturnRow and "<-" or "->"

            if row.container ~= nil then
                row.container:setVisible(true)
            end

            row.label:setText("    " .. directionArrow .. " " .. tostring(destination.name), LINE_ROW_LABEL_WIDTH)

            if row.waitingLabel ~= nil then

                row.waitingLabel:setText(formatWaitingLabel(scanResult, destination.stationGroup), LINE_ROW_WAITING_WIDTH)
                pcall(row.waitingLabel.setStyleClassList, row.waitingLabel, { "EpodTdMutedText" })

            end

            renderCargoIcons(row, scanResult, destination.stationGroup)

            destinationRowIndex = destinationRowIndex + 1

        end

    end

    for remainingIndex = destinationRowIndex, #group.destinationRows do
        clearDestinationRow(group.destinationRows[remainingIndex])
    end

end


-- Decision 146: player's request -- a stronger "push for reallocation"
-- than a single Apply Fleet Plan click, for a hub with many small
-- imbalances scattered across different lines (exactly what prompted
-- this: Poole Sidings showing +1/-2/0/+1/+1/0/+1/-1 across 8 lines on
-- one page). dispatcher.applyPlan's own MAX_MOVES_PER_RUN (5) and
-- MAX_ATTEMPTS_PER_RUN (8) caps exist for real safety reasons (added
-- after real crash incidents, per dispatcher.lua's own header) and are
-- NOT bypassed here -- this just chains multiple genuinely-complete
-- applyPlan runs back to back (each one only starts once the previous
-- one's onComplete has actually fired, so the SAME reentrancy guard
-- that would refuse an overlapping call is never triggered). Also does
-- NOT bypass the per-vehicle/per-line-direction cooldowns (Decisions
-- 32/33, added after real observed flapping -- a line's correction
-- reversing itself one run later) -- a line/vehicle touched by run 1
-- will correctly sit out run 2, which is exactly why chaining stops
-- naturally once nothing NEW is eligible, capped at
-- MAX_PUSH_ITERATIONS as a hard ceiling regardless.
local MAX_PUSH_ITERATIONS = 5

local function runPushIteration(hubStationGroupId, iterationsDone, totalMoved)

    if iterationsDone >= MAX_PUSH_ITERATIONS then

        operation_lock.finish()

        log.info(
            "LINES TAB: Push Full Reallocation stopped at the "
                .. tostring(MAX_PUSH_ITERATIONS) .. "-pass ceiling, "
                .. tostring(totalMoved) .. " total vehicle(s) moved."
        )

        return

    end

    local ok, err =
        pcall(
            dispatcher.applyPlan,
            hubStationGroupId,

            function(movesMade)

                local newTotal = totalMoved + movesMade

                if movesMade > 0 then

                    runPushIteration(hubStationGroupId, iterationsDone + 1, newTotal)

                else

                    operation_lock.finish()

                    log.info(
                        "LINES TAB: Push Full Reallocation done -- "
                            .. tostring(newTotal) .. " total vehicle(s) moved across "
                            .. tostring(iterationsDone + 1) .. " pass(es) (stopped: nothing "
                            .. "further eligible this click -- may still be cooling down, "
                            .. "see Decisions 32/33)."
                    )

                end

            end
        )

    if not ok then
        operation_lock.finish()
        log.info("LINES TAB: Push Full Reallocation failed: " .. tostring(err))
    end

end


-- `groups` is a pool of MAX_LINE_GROUPS_PER_PAGE pre-built {headerButton,
-- headerButtonLabel, vehiclesLabel, deltaLabel, waitingTerminalLabel,
-- detailPanel, destinationRows, handler} slots -- see gui_central_raw.
-- lua's buildLinesPanel for how they're built (Decision 145: the old
-- single `summaryLabel` split into three separately-colorable widgets).
-- `pagination` is {prevButton, nextButton, pageLabel}, all pre-built
-- the same way, with `.handler` set fresh here every call (same "wire
-- onClick once, dispatch through .handler" pattern every action button
-- in this codebase already uses -- see gui_manager.lua's own header
-- comment). `actionButtons[1]` is Re-Organize Terminals (Decision 142),
-- `actionButtons[2]` is Apply Fleet Plan (Decision 145),
-- `actionButtons[3]` is Push Full Reallocation (Decision 146).
function M.refresh(rows, hubStationGroupId, actionButtons, groups, pagination)

    if groups == nil then

        if rows ~= nil and rows[1] ~= nil then
            rows[1].label:setText("Lines window needs to be reopened.", 560)
        end

        return

    end

    for _, group in ipairs(groups) do
        clearGroup(group)
    end

    if hubStationGroupId == nil then
        groups[1].headerButtonLabel:setText("No hub selected -- select a station on the map first.", 560)
        return
    end

    -- Decision 142: "Re-Organize Terminals" moved here from OVERVIEW --
    -- player's call, "we still want the resort terminals button, but
    -- that could go onto the Lines page, logical sense" now that LINES
    -- shows each line's own terminal number (Decision 139). Same
    -- operation_lock-guarded sequence OVERVIEW's own slot used, just
    -- relocated -- terminal_allocator.spreadLinesAcrossTerminals itself
    -- is unchanged.
    if actionButtons ~= nil and actionButtons[1] ~= nil then

        local slot = actionButtons[1]

        if operation_lock.isRunning() then

            slot.label:setText("[ Re-Organize Terminals (busy -- another hub operation running) ]", 560)
            slot.handler = nil

        else

            slot.label:setText("[ Re-Organize Terminals ]", 560)
            pcall(slot.button.setStyleClassList, slot.button, { "EpodTdPrimaryButton" })

            slot.handler = function()

                if operation_lock.isRunning() then

                    log.info("LINES TAB: another hub operation is still running -- ignoring click.")
                    return

                end

                operation_lock.begin()

                local ok, err =
                    pcall(
                        terminal_allocator.spreadLinesAcrossTerminals,
                        hubStationGroupId,
                        {},

                        function(processedCount)
                            operation_lock.finish()
                            log.info("LINES TAB: Re-Organize Terminals done (" .. tostring(processedCount) .. " line(s)).")
                        end
                    )

                if not ok then
                    operation_lock.finish()
                    log.info("LINES TAB: Re-Organize Terminals failed: " .. tostring(err))
                end

            end

        end

    end

    -- Decision 145: "Apply Fleet Plan" moved here from the now-dropped
    -- SERVICES tab -- same operation_lock-guarded dispatcher.applyPlan
    -- call, just relocated next to the per-line target/delta numbers
    -- it actually acts on, instead of a separate page.
    if actionButtons ~= nil and actionButtons[2] ~= nil then

        local slot = actionButtons[2]

        if operation_lock.isRunning() then

            slot.label:setText("[ Apply Fleet Plan (busy -- another hub operation running) ]", 560)
            slot.handler = nil

        else

            slot.label:setText("[ Apply Fleet Plan ]", 560)
            pcall(slot.button.setStyleClassList, slot.button, { "EpodTdPrimaryButton" })

            slot.handler = function()

                if operation_lock.isRunning() then

                    log.info("LINES TAB: another hub operation is still running -- ignoring click.")
                    return

                end

                operation_lock.begin()

                local ok, err =
                    pcall(
                        dispatcher.applyPlan,
                        hubStationGroupId,

                        function(movesMade)
                            operation_lock.finish()
                            log.info("LINES TAB: Apply Fleet Plan done (" .. tostring(movesMade) .. " vehicle(s) moved).")
                        end
                    )

                if not ok then
                    operation_lock.finish()
                    log.info("LINES TAB: Apply Fleet Plan failed: " .. tostring(err))
                end

            end

        end

    end

    -- Decision 146: "Push Full Reallocation" -- chains multiple
    -- dispatcher.applyPlan runs in one click (see runPushIteration's
    -- own header comment for exactly what safety mechanisms this does
    -- and doesn't bypass).
    if actionButtons ~= nil and actionButtons[3] ~= nil then

        local slot = actionButtons[3]

        if operation_lock.isRunning() then

            slot.label:setText("[ Push Full Reallocation (busy -- another hub operation running) ]", 560)
            slot.handler = nil

        else

            slot.label:setText("[ Push Full Reallocation ]", 560)
            pcall(slot.button.setStyleClassList, slot.button, { "EpodTdPrimaryButton" })

            slot.handler = function()

                if operation_lock.isRunning() then

                    log.info("LINES TAB: another hub operation is still running -- ignoring click.")
                    return

                end

                operation_lock.begin()

                runPushIteration(hubStationGroupId, 0, 0)

            end

        end

    end

    local ok, managedLines = pcall(vehicles.getManagedLinesForStation, hubStationGroupId)

    if not ok or managedLines == nil or #managedLines == 0 then
        groups[1].headerButtonLabel:setText("No managed services at this hub yet.", 560)
        return
    end

    -- Decision 145: Planner's target/delta, computed ONCE per refresh
    -- (not once per line) and looked up by real line id -- confirmed
    -- real key, planner.lua's own calculateTargetAllocation sets
    -- `id = candidate.id` on every result entry, the same id
    -- vehicles.getManagedLinesForStation's own lineInfo.id already
    -- uses (this is the same id dispatcher.applyPlan already moves
    -- real vehicles by, so the two id spaces are already proven to
    -- match). "delta = target - current" (planner.lua's own comment):
    -- positive means short of target, negative means over-supplied.
    local planByLineId = {}

    local okPlan, plan = pcall(planner.calculateTargetAllocation, hubStationGroupId)

    if okPlan and plan ~= nil and plan.lines ~= nil then

        for _, planLine in ipairs(plan.lines) do
            planByLineId[planLine.id] = planLine
        end

    end

    local totalPages = math.max(1, math.ceil(#managedLines / #groups))

    if state.currentPage > totalPages then
        state.currentPage = totalPages
    end

    if state.currentPage < 1 then
        state.currentPage = 1
    end

    if pagination ~= nil then

        if pagination.pageLabel ~= nil then
            pagination.pageLabel:setText("Page " .. tostring(state.currentPage) .. " / " .. tostring(totalPages), 120)
        end

        if pagination.prevButton ~= nil then

            pagination.prevButton.handler = function()

                if state.currentPage > 1 then
                    state.currentPage = state.currentPage - 1
                end

            end

        end

        if pagination.nextButton ~= nil then

            pagination.nextButton.handler = function()

                if state.currentPage < totalPages then
                    state.currentPage = state.currentPage + 1
                end

            end

        end

    end

    local startIndex = (state.currentPage - 1) * #groups + 1

    for groupIndex, group in ipairs(groups) do

        local lineInfo = managedLines[startIndex + groupIndex - 1]

        if lineInfo ~= nil then

            local scanResult = demand.scan(lineInfo.id, hubStationGroupId)
            local lineWaiting = (scanResult ~= nil and scanResult.totalWaiting) or 0
            local isExpanded = state.expandedLineKey == lineInfo.id

            -- Display-only "\xE2\x97\x8f " marker, matching every managed
            -- line's own real name convention (managed_registry.lua) --
            -- not double-prefixed if the real name already carries it.
            local displayLineName = tostring(lineInfo.name)

            if displayLineName:sub(1, 4) ~= "\xE2\x97\x8f " then
                displayLineName = "\xE2\x97\x8f " .. displayLineName
            end

            group.headerButtonLabel:setText(
                (isExpanded and "[-] " or "[+] ") .. displayLineName,
                LINE_ROW_LABEL_WIDTH
            )

            pcall(group.headerButtonLabel.setStyleClassList, group.headerButtonLabel, { "EpodTdTableHeader" })

            -- Decision 139: terminal number folded in here (first cheap
            -- win of the 8-tabs-to-4 consolidation) -- same +1 display
            -- offset TERMINALS already uses (Decision 21's confirmed
            -- UI-vs-raw indexing gap), read via the same real
            -- lines.getStopTerminal(...) getter, no new logic.
            local okTerminal, terminal = pcall(lines.getStopTerminal, lineInfo.id, hubStationGroupId)
            local terminalText = (okTerminal and terminal ~= nil) and (" | T" .. tostring(terminal + 1)) or ""

            group.vehiclesLabel:setText(tostring(lineInfo.vehicleCount or 0) .. " vehicles", LINE_VEHICLES_WIDTH)
            pcall(group.vehiclesLabel.setStyleClassList, group.vehiclesLabel, { "EpodTdMutedText" })

            -- Decision 145: player's request -- delta colored red
            -- (negative -- over-supplied relative to target) / white,
            -- i.e. unstyled (zero -- exactly at target) / green
            -- (positive -- short of target), independent of the
            -- vehicle/waiting text either side of it. Only a TextView's
            -- WHOLE string can carry one style class -- this is why the
            -- old single summaryLabel had to split into three widgets.
            local planLine = planByLineId[lineInfo.id]

            if planLine ~= nil then

                local delta = planLine.delta or 0
                local deltaText = delta > 0 and ("+" .. tostring(delta)) or tostring(delta)

                group.deltaLabel:setText(deltaText, LINE_DELTA_WIDTH)

                if delta < 0 then
                    pcall(group.deltaLabel.setStyleClassList, group.deltaLabel, { "EpodTdDeltaNegative" })
                elseif delta > 0 then
                    pcall(group.deltaLabel.setStyleClassList, group.deltaLabel, { "EpodTdDeltaPositive" })
                else
                    pcall(group.deltaLabel.setStyleClassList, group.deltaLabel, {})
                end

            else

                -- Decision 147: LIVE-CONFIRMED -- a blank cell here
                -- read as a rendering bug ("the Quarry line is missing
                -- a number"). Real, existing cause, not a new bug:
                -- planner.lua's own collectManagedLineCandidates
                -- excludes any line owned by a DIFFERENT hub
                -- (line_ownership.isOwnedByOther) or that doesn't
                -- resolve to a single destination -- criteria stricter
                -- than vehicles.getManagedLinesForStation's own (looser)
                -- rules for which lines even appear in this list at
                -- all. Most likely explanation for a shared/dual-hub
                -- line: its target is calculated once, by whichever hub
                -- actually owns it, not duplicated here. "n/a" makes
                -- that a deliberate, readable state instead of an
                -- unexplained gap.
                group.deltaLabel:setText("n/a", LINE_DELTA_WIDTH)
                pcall(group.deltaLabel.setStyleClassList, group.deltaLabel, { "EpodTdMutedText" })

            end

            group.waitingTerminalLabel:setText(
                tostring(lineWaiting) .. " waiting" .. terminalText,
                LINE_WAITING_TERMINAL_WIDTH
            )

            pcall(group.waitingTerminalLabel.setStyleClassList, group.waitingTerminalLabel, { "EpodTdMutedText" })

            local lineId = lineInfo.id

            group.handler = function()

                if state.expandedLineKey == lineId then
                    state.expandedLineKey = nil
                else
                    state.expandedLineKey = lineId
                end

            end

            if group.detailPanel ~= nil then
                group.detailPanel:setVisible(isExpanded)
            end

            if isExpanded then
                renderDestinations(group, lineInfo, hubStationGroupId, scanResult)
            end

        end

    end

end


return M
