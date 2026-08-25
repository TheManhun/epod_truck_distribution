local vehicles = require("epod_td.vehicles")
local stations = require("epod_td.stations")
local lines = require("epod_td.lines")

local M = {}


-- ============================================================
-- TERMINALS TAB (gui_manager.lua)
--
-- GUI ONLY -- reads stations.getTerminalCount + each managed line's
-- own hub-side stop terminal (lines.getStopTerminal, a small new
-- structural getter -- no allocation decision lives here, that stays
-- terminal_allocator.lua's job). Groups managed lines by which
-- terminal they're currently on; +1 on display to match the game's
-- own shown terminal numbers (Decision 21's confirmed UI offset).
-- ============================================================

function M.getLabel()
    return "TERMINALS"
end


-- Display-only: managed lines are themselves renamed with a "● "
-- marker (the mechanism managed_registry.lua's self-heal relies on to
-- recognize its own lines). Every row in this tab is a managed line
-- by definition, so the marker is 100% redundant here -- just clutter
-- eating into the already-tight truncated name space. Stripped for
-- display only; the real line name (and the self-heal mechanism that
-- depends on it) is untouched.
local function stripManagedLineMarker(name)

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

    local terminalCount = stations.getTerminalCount(hubStationGroupId)

    local ok, managedLines = pcall(vehicles.getManagedLinesForStation, hubStationGroupId)

    if not ok or managedLines == nil then

        rows[1].label:setText(
            "TERMINALS: could not read managed lines for this hub.",
            560
        )

        return

    end

    local byTerminal = {}
    local unassigned = {}

    for _, lineInfo in ipairs(managedLines) do

        local terminal = lines.getStopTerminal(lineInfo.id, hubStationGroupId)

        if terminal ~= nil then

            if byTerminal[terminal] == nil then
                byTerminal[terminal] = {}
            end

            table.insert(byTerminal[terminal], stripManagedLineMarker(lineInfo.name))

        else

            unassigned[#unassigned + 1] = stripManagedLineMarker(lineInfo.name)

        end

    end

    local rowIndex = 1

    rows[rowIndex].label:setText(
        "Terminals at this hub: " .. tostring(terminalCount),
        560
    )
    pcall(rows[rowIndex].label.setStyleClassList, rows[rowIndex].label, { "EpodTdTableHeader" })
    rowIndex = rowIndex + 1

    for terminal = 0, math.max(terminalCount - 1, 0) do

        if rowIndex > #rows then
            break
        end

        local lineNames = byTerminal[terminal]
        local text = "T" .. tostring(terminal + 1) .. "    "
        local isEmpty = lineNames == nil or #lineNames == 0

        if isEmpty then
            text = text .. "(empty)"
        else
            text = text .. table.concat(lineNames, ", ")
        end

        rows[rowIndex].label:setText(text, 560)

        if isEmpty then
            pcall(rows[rowIndex].label.setStyleClassList, rows[rowIndex].label, { "EpodTdMutedText" })
        end

        rowIndex = rowIndex + 1

    end

    if #unassigned > 0 and rowIndex <= #rows then

        rows[rowIndex].label:setText(
            "Unassigned/unreadable: " .. table.concat(unassigned, ", "),
            560
        )

        pcall(rows[rowIndex].label.setStyleClassList, rows[rowIndex].label, { "EpodTdWarningText" })

    end

end


return M
