local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local hub_registry = require("epod_td.hub_registry")
local terminal_allocator = require("epod_td.terminal_allocator")
local operation_lock = require("epod_td.operation_lock")
local log = require("epod_td.log")

local M = {}


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
-- extract. Split/Assign & Balance/Distribution Hub ON-OFF are still
-- private composed sequences inside epod_truck_distribution.lua
-- (splitAllManagedLines/runNewHubSetupSequence/processSourceLineNext)
-- -- adding those here too needs them extracted into a proper shared
-- module first, so two different files aren't each maintaining their
-- own copy of the same multi-step chain. Not done yet -- next step.
-- ============================================================

function M.getLabel()
    return "OVERVIEW"
end


function M.refresh(rows, hubStationGroupId, actionButtons)

    if hubStationGroupId == nil then

        rows[1].label:setText(
            "No hub selected -- select a station on the map first.",
            560
        )

        return

    end

    if actionButtons ~= nil and actionButtons[1] ~= nil then

        local slot = actionButtons[1]

        if operation_lock.isRunning() then

            slot.label:setText("[ Re-Organize Terminals (busy -- another hub operation running) ]", 560)
            slot.handler = nil

        else

            slot.label:setText("[ Re-Organize Terminals ]", 560)

            slot.handler = function()

                if operation_lock.isRunning() then

                    log.info("OVERVIEW TAB: another hub operation is still running -- ignoring click.")
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
                            log.info("OVERVIEW TAB: Re-Organize Terminals done (" .. tostring(processedCount) .. " line(s)).")
                        end
                    )

                if not ok then
                    operation_lock.finish()
                    log.info("OVERVIEW TAB: Re-Organize Terminals failed: " .. tostring(err))
                end

            end

        end

    end

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

end


return M
