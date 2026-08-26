local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")
local stations = require("epod_td.stations")

local M = {}


-- ============================================================
-- LINES TAB (gui_manager.lua)
--
-- Decision 121: player asked to move the old panel's full per-line,
-- per-destination breakdown (name, vehicle/waiting totals, and a
-- cargo-icon row per real destination) into the new GUI, full icon
-- parity with the old panel rather than a text-only summary. GUI
-- ONLY, same rule as every gui_tab_*.lua file -- reads
-- vehicles.getManagedLinesForStation / demand.scan / stations.lua,
-- calculates nothing of its own. The actual layout/rendering logic
-- below mirrors epod_truck_distribution.lua's own
-- renderManagedLineRows as closely as this shared framework allows;
-- see that function for the original, live-proven version this was
-- built from.
--
-- Uses the SEPARATE `lineRows` pool (gui_manager.lua's 4th refresh
-- argument, additive -- every other tab still only takes 3), not the
-- plain `rows` pool every other tab shares: that pool's rows are a
-- single full-width text label, with no room for a waiting-count
-- column or cargo icons without breaking every tab that already
-- relies on the full width for its own padded text tables.
-- ============================================================

local MAX_DESTINATIONS_PER_LINE = 6

-- Must match gui_manager.lua's LINE_ROW_CARGO_SLOTS -- how many
-- icon/count pairs actually exist per row in the pool it built.
local LINE_ROW_CARGO_SLOTS = 3


function M.getLabel()
    return "LINES"
end


local function formatWaitingLabel(scanResult, stationGroupId)

    if scanResult == nil or scanResult.error ~= nil then
        return "Waiting: ?"
    end

    local destination = demand.getDestination(scanResult, stationGroupId)

    if destination == nil then
        return "Waiting: 0"
    end

    return "Waiting: " .. tostring(destination.total or 0)

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
            countView:setText("", 70)

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
                    70
                )

            else

                iconView:setImage(iconPath)
                pcall(iconView.setTransparent, iconView, false)
                pcall(countView.setTransparent, countView, false)

                countView:setText(tostring(cargo.count), 70)

            end

        end

    end

end


function M.refresh(rows, hubStationGroupId, actionButtons, lineRows)

    if lineRows == nil then

        if rows ~= nil and rows[1] ~= nil then
            rows[1].label:setText("LINES tab needs a newer DD Central Manager window -- reopen it.", 560)
        end

        return

    end

    if hubStationGroupId == nil then
        lineRows[1].label:setText("No hub selected -- select a station on the map first.", 560)
        return
    end

    local ok, managedLines = pcall(vehicles.getManagedLinesForStation, hubStationGroupId)

    if not ok or managedLines == nil or #managedLines == 0 then
        lineRows[1].label:setText("No managed services at this hub yet.", 560)
        return
    end

    local rowIndex = 1

    for _, lineInfo in ipairs(managedLines) do

        if rowIndex > #lineRows then
            break
        end

        local scanResult = demand.scan(lineInfo.id, hubStationGroupId)
        local lineWaiting = (scanResult ~= nil and scanResult.totalWaiting) or 0

        -- Display-only "● " marker, matching every managed line's own
        -- real name convention (managed_registry.lua) -- not
        -- double-prefixed if the real name already carries it.
        local displayLineName = tostring(lineInfo.name)

        if displayLineName:sub(1, 4) ~= "\xE2\x97\x8f " then
            displayLineName = "\xE2\x97\x8f " .. displayLineName
        end

        lineRows[rowIndex].label:setText(displayLineName, 260)
        pcall(lineRows[rowIndex].label.setStyleClassList, lineRows[rowIndex].label, { "EpodTdTableHeader" })
        rowIndex = rowIndex + 1

        if rowIndex > #lineRows then
            break
        end

        lineRows[rowIndex].label:setText(
            tostring(lineInfo.vehicleCount or 0) .. " vehicles   |   " .. tostring(lineWaiting) .. " waiting",
            260
        )
        rowIndex = rowIndex + 1

        if lineInfo.destinations ~= nil then

            -- A destination's row is only worth showing if it has
            -- actually produced/received something at some point in
            -- its history -- same "not just currently 0" rule as the
            -- old panel (stations.getItemTotals), so a structurally
            -- pure drop-off town doesn't get a permanent, always-empty
            -- "<- Town" row.
            local hubReturnHasNeverProduced = true

            for _, otherDestination in ipairs(lineInfo.destinations) do

                if otherDestination.stationGroup ~= hubStationGroupId then

                    local okTotals, otherTotals = pcall(stations.getItemTotals, otherDestination.stationGroup)

                    if okTotals and otherTotals ~= nil and otherTotals.loaded > 0 then
                        hubReturnHasNeverProduced = false
                    end

                end

            end

            local visibleDestinationCount = 0

            for _, destination in ipairs(lineInfo.destinations) do

                if rowIndex > #lineRows then
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

                    local directionArrow = isHubReturnRow and "<-" or "->"

                    lineRows[rowIndex].label:setText(
                        "    " .. directionArrow .. " " .. tostring(destination.name),
                        260
                    )

                    if lineRows[rowIndex].waitingLabel ~= nil then

                        lineRows[rowIndex].waitingLabel:setText(
                            formatWaitingLabel(scanResult, destination.stationGroup),
                            90
                        )

                    end

                    renderCargoIcons(lineRows[rowIndex], scanResult, destination.stationGroup)

                    rowIndex = rowIndex + 1

                end

            end

        end

    end

end


return M
