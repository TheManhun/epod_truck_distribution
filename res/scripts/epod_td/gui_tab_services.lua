local planner = require("epod_td.planner")
local dispatcher = require("epod_td.dispatcher")
local operation_lock = require("epod_td.operation_lock")
local log = require("epod_td.log")

local M = {}


-- ============================================================
-- SERVICES TAB (gui_manager.lua)
--
-- GUI ONLY -- reads planner.calculateTargetAllocation, calculates
-- nothing of its own. One row per managed line at the focused hub:
-- current vehicles, the Planner's own target, waiting cargo, and the
-- delta between them -- exactly the numbers the Planner already
-- computes for real dispatch decisions (Decisions 29/30), just shown
-- instead of only logged.
--
-- Decision 84: claims action slot 1 for "Apply Fleet Plan"
-- (dispatcher.applyPlan) -- previously only reachable via a DEBUG-
-- gated button on the old panel. Real live data (a hub with two lines
-- sitting 5-7 vehicles OVER their planner-computed target while five
-- others sat 2-5 vehicles under theirs, tens of thousands of waiting
-- cargo) showed automatic dispatch alone can take a long time to
-- close a gap this size -- it only triggers every 5000 deliveries
-- network-wide and moves at most 5 vehicles per run (dispatcher.lua's
-- own conservative caps, added after two real crash incidents,
-- Decisions 36-38). This button is the same manual override the old
-- panel already had, just surfaced where the imbalance is actually
-- visible instead of behind DEBUG mode -- still entirely player-
-- triggered, no new automation. Guarded by the same shared
-- operation_lock as every other hub-mutating action button (Decision
-- 71's precedent) since dispatcher.applyPlan moves real vehicles
-- between lines, the same category of action as Re-Organize
-- Terminals/Split/Assign & Balance.
-- ============================================================

function M.getLabel()
    return "SERVICES"
end


-- Display-only: managed lines are themselves renamed with a "● "
-- marker (managed_registry.lua's self-heal relies on it). Every row
-- here is a managed line by definition, so it's pure clutter eating
-- into the already-tight truncated name space -- stripped for display
-- only, real line name untouched.
local function stripManagedLineMarker(name)

    if type(name) == "string" and name:sub(1, 4) == "\xE2\x97\x8f " then
        return name:sub(5)
    end

    return name

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

            slot.label:setText("[ Apply Fleet Plan (busy -- another hub operation running) ]", 560)
            slot.handler = nil

        else

            slot.label:setText("[ Apply Fleet Plan ]", 560)
            pcall(slot.button.setStyleClassList, slot.button, { "EpodTdPrimaryButton" })

            slot.handler = function()

                if operation_lock.isRunning() then

                    log.info("SERVICES TAB: another hub operation is still running -- ignoring click.")
                    return

                end

                operation_lock.begin()

                -- Deliberately does NOT try to write a "done: N moved"
                -- confirmation onto the button label (Decision 71's own
                -- precedent -- Re-Organize Terminals only logs too):
                -- M.refresh runs every guiUpdate frame and would
                -- overwrite any such text on the very next frame,
                -- immediately after operation_lock.finish() makes
                -- isRunning() false again -- effectively invisible to a
                -- player. The SERVICES table's own rows already show
                -- the real result (updated Current/Waiting/Delta
                -- columns) on the next refresh; the log has the count.
                local ok, err =
                    pcall(
                        dispatcher.applyPlan,
                        hubStationGroupId,

                        function(movesMade)
                            operation_lock.finish()
                            log.info("SERVICES TAB: Apply Fleet Plan done (" .. tostring(movesMade) .. " vehicle(s) moved).")
                        end
                    )

                if not ok then
                    operation_lock.finish()
                    log.info("SERVICES TAB: Apply Fleet Plan failed: " .. tostring(err))
                end

            end

        end

    end

    local ok, plan = pcall(planner.calculateTargetAllocation, hubStationGroupId)

    if not ok or plan == nil then

        rows[1].label:setText(
            "SERVICES: could not calculate the fleet plan for this hub.",
            560
        )

        return

    end

    if #plan.lines == 0 then

        rows[1].label:setText(
            "No managed services at this hub yet.",
            560
        )

        return

    end

    -- Worst-backlog-first, same convention as the DEBUG Fleet Balance
    -- Report -- the line needing the most attention should be the
    -- first thing the player sees, not wherever it happens to fall in
    -- scan order.
    local sortedLines = {}

    for _, lineInfo in ipairs(plan.lines) do
        sortedLines[#sortedLines + 1] = lineInfo
    end

    table.sort(sortedLines, function(a, b)
        return a.waiting > b.waiting
    end)

    local rowIndex = 1

    rows[rowIndex].label:setText(
        "Service                              Current  Target  Waiting  Delta",
        560
    )
    pcall(rows[rowIndex].label.setStyleClassList, rows[rowIndex].label, { "EpodTdTableHeader" })
    rowIndex = rowIndex + 1

    for _, lineInfo in ipairs(sortedLines) do

        if rowIndex > #rows then
            break
        end

        local deltaText =
            lineInfo.delta > 0
                and ("+" .. tostring(lineInfo.delta))
                or tostring(lineInfo.delta)

        rows[rowIndex].label:setText(
            string.format(
                "%-36s %7d %7d %8d %7s",
                stripManagedLineMarker(tostring(lineInfo.name)):sub(1, 36),
                lineInfo.currentVehicleCount,
                lineInfo.targetVehicleCount,
                lineInfo.waiting,
                deltaText
            ),
            560
        )

        -- delta = target - current (planner.lua): positive means this
        -- service is short of the fleet it needs -- the row worth a
        -- player's attention first.
        if lineInfo.delta > 0 then

            pcall(rows[rowIndex].label.setStyleClassList, rows[rowIndex].label, { "EpodTdWarningText" })

        end

        rowIndex = rowIndex + 1

    end

end


return M
