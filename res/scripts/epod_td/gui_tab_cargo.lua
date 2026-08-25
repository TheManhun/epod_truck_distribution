local vehicles = require("epod_td.vehicles")
local demand = require("epod_td.demand")

local M = {}


-- ============================================================
-- CARGO TAB (gui_manager.lua)
--
-- GUI ONLY -- reads demand.scan's per-destination cargoTypes
-- breakdown plus demand.buildDestinationCargoRows (Decision 79, the
-- same shared helper the DEBUG "Cargo Balance Inspector" report uses)
-- for every destination at the focused hub. Calculates nothing of its
-- own -- shows the SAME per-destination, comparatively-under-served
-- signal the DEBUG report already proved correct (Goole Steel Plant's
-- real 4:1 iron/coal imbalance), live, without needing DEBUG mode or
-- a file dump.
--
-- Deliberately per-destination rather than one combined hub total
-- (the tab's original shape): a single combined number hides exactly
-- the imbalance this view exists to surface -- see Decision 78's
-- discovery and documents/IDEAS.md's "Cargo-Type-Aware Allocation"
-- entry.
-- ============================================================

function M.getLabel()
    return "CARGO"
end


-- Display-only: a destination's raw name can itself carry the "● "
-- hub marker (Decision 69) if that same station is ALSO one of the
-- player's enabled hubs elsewhere in the network -- real, meaningful
-- information, just visual noise in a per-destination cargo list
-- where every row already reads "this is a destination." Stripped
-- here for display only; the underlying stationGroup id and hub
-- registry are completely untouched.
local function stripHubMarker(name)

    if type(name) == "string" and name:sub(1, 4) == "\xE2\x97\x8f " then
        return name:sub(5)
    end

    return name

end


function M.refresh(rows, hubStationGroupId)

    if hubStationGroupId == nil then

        rows[1].label:setText(
            "No hub selected -- select a station on the map first.",
            560
        )

        return

    end

    local ok, managedLines = pcall(vehicles.getManagedLinesForStation, hubStationGroupId)

    if not ok or managedLines == nil or #managedLines == 0 then

        rows[1].label:setText(
            "No managed services at this hub yet.",
            560
        )

        return

    end

    local reportedDestinations = {}
    local destinationEntries = {}

    for _, lineInfo in ipairs(managedLines) do

        local scanResult = demand.scan(lineInfo.id, hubStationGroupId)

        if scanResult ~= nil and scanResult.destinations ~= nil then

            for _, destination in pairs(scanResult.destinations) do

                if destination.stationGroup ~= hubStationGroupId
                    and not reportedDestinations[destination.stationGroup]
                then

                    local cargoRows = demand.buildDestinationCargoRows(destination)

                    if cargoRows ~= nil then

                        reportedDestinations[destination.stationGroup] = true

                        local totalWaiting = 0

                        for _, cargoRow in ipairs(cargoRows) do
                            totalWaiting = totalWaiting + cargoRow.waiting
                        end

                        destinationEntries[#destinationEntries + 1] = {
                            name = stripHubMarker(destination.name),
                            rows = cargoRows,
                            totalWaiting = totalWaiting
                        }

                    end

                end

            end

        end

    end

    if #destinationEntries == 0 then

        rows[1].label:setText(
            "No multi-cargo-type destinations at this hub right now"
                .. " (single-cargo destinations have nothing to compare).",
            560
        )

        return

    end

    table.sort(destinationEntries, function(a, b)
        return a.totalWaiting > b.totalWaiting
    end)

    local rowIndex = 1

    for _, entry in ipairs(destinationEntries) do

        if rowIndex > #rows then
            break
        end

        rows[rowIndex].label:setText(tostring(entry.name), 560)
        pcall(rows[rowIndex].label.setStyleClassList, rows[rowIndex].label, { "EpodTdTableHeader" })
        rowIndex = rowIndex + 1

        for _, cargoRow in ipairs(entry.rows) do

            if rowIndex > #rows then
                break
            end

            local flag = cargoRow.underServed and "  <-- under-served" or ""

            rows[rowIndex].label:setText(
                string.format(
                    "  %-34s %8d waiting  %8d all-time%s",
                    tostring(cargoRow.displayName):sub(1, 34),
                    cargoRow.waiting,
                    cargoRow.unloaded,
                    flag
                ),
                560
            )

            pcall(
                rows[rowIndex].label.setStyleClassList,
                rows[rowIndex].label,
                { cargoRow.underServed and "EpodTdWarningText" or "EpodTdMutedText" }
            )

            rowIndex = rowIndex + 1

        end

        rowIndex = rowIndex + 1

    end

end


return M
