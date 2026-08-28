local log = require("epod_td.log")
local vehicles = require("epod_td.vehicles")
local line_splitter = require("epod_td.line_splitter")
local terminal_allocator = require("epod_td.terminal_allocator")
local industry_naming = require("epod_td.industry_naming")
local fleet_allocator = require("epod_td.fleet_allocator")
local source_line_registry = require("epod_td.source_line_registry")
local fleet_naming = require("epod_td.fleet_naming")
local hub_registry = require("epod_td.hub_registry")
local stations = require("epod_td.stations")

local M = {}


-- ============================================================
-- SPLIT INTO LINES + ORGANIZE TERMINALS (Stage 1 + Stage 4)
--
-- Decision 122: extracted from epod_truck_distribution.lua's own
-- private handleSplitButtonClick/splitAllManagedLines -- the LAST
-- piece of real orchestration logic still trapped in the old panel's
-- file, per gui_tab_overview.lua's own header comment ("Split/Assign
-- & Balance/Distribution Hub ON-OFF are still private composed
-- sequences ... not done yet -- next step"). Moved here so BOTH the
-- old panel's button and the new GUI's OVERVIEW tab action button can
-- call the exact same real sequence, instead of one calling private
-- logic the other has no access to.
--
-- Combined into one call: creating the dedicated per-destination
-- lines (Stage 1) and spreading them across terminals by demand
-- (Stage 4, terminal_allocator.lua) -- neither one touches vehicle
-- cargo or moves a vehicle, so neither carries the still-open Bug A/B
-- risk (PROGRESS.md) that keeps "Assign & Balance Fleet" separate and
-- DEBUG-gated.
--
-- Status updates go through `onStatusUpdate(text)` rather than
-- writing to any specific label directly -- lets each caller (a
-- gui.lua textView on the old panel, a gui_manager.lua action-button
-- slot on the new GUI) display progress on whatever widget it
-- actually owns, without this module knowing either exists.
--
-- Does NOT manage operation_lock itself: this is the same category of
-- hub-mutating action as Assign & Balance / Re-Organize Terminals /
-- Chain Builder, all of which share ONE global lock so they can never
-- race each other regardless of which button triggered them -- the
-- CALLER is expected to call operation_lock.begin()/finish() around
-- this, exactly like every other caller of those already does.
-- ============================================================

local function splitAllManagedLines(stationGroupId, managedLines, index, sourceLineIds, onStatusUpdate, onAllDone)

    sourceLineIds = sourceLineIds or {}

    local lineInfo = managedLines[index]

    if lineInfo == nil then

        log.info(
            "SPLIT ALL: finished processing " .. tostring(#managedLines)
                .. " managed line(s). Organizing terminals..."
        )

        onStatusUpdate("[ Organizing terminals... ]")

        -- LIVE-CONFIRMED BUG (Decision, original panel): without
        -- excluding the line(s) just split, stockTakeExistingLoad
        -- (terminal_allocator.lua) treats the ORIGINAL combined line
        -- -- still alive right now, about to be deleted by a LATER
        -- "Assign & Balance Fleet" click -- as real, permanent
        -- occupancy exactly like any other line. Passing the
        -- just-split source line IDs through so stock-take can
        -- exclude them too (same treatment as already-managed lines)
        -- fixes this without depending on deletion having already
        -- happened.
        local ok, err =
            pcall(
                terminal_allocator.spreadLinesAcrossTerminals,
                stationGroupId,
                sourceLineIds,

                function(processedCount)

                    onStatusUpdate(
                        "[ Split & Organize Terminals (done: "
                            .. tostring(processedCount)
                            .. " line(s)) ]"
                    )

                    if onAllDone ~= nil then
                        onAllDone()
                    end

                end
            )

        if not ok then

            log.info("SPLIT ALL (terminal step) FAILED: " .. tostring(err))

            onStatusUpdate("[ Split & Organize Terminals (crashed) ]")

            if onAllDone ~= nil then
                onAllDone()
            end

        end

        return

    end

    local realCount = 0

    for _, destination in ipairs(lineInfo.destinations or {}) do

        if destination.stationGroup ~= stationGroupId then
            realCount = realCount + 1
        end

    end

    -- A genuine "coal -> steel -> hub" industry chain must never be
    -- split -- doing so would break it into disconnected hub<->coal
    -- and hub<->steel lines, destroying the production sequence. Same
    -- proximity-based chain detection industry_naming uses for its
    -- own line-naming (line_adopter.buildAdoptedLineName).
    local okChain, chainName =
        pcall(industry_naming.buildChainName, lineInfo.destinations, stationGroupId)

    local isChainLine = okChain and chainName ~= nil

    if realCount < 2 or isChainLine then

        local reasonText

        if isChainLine then

            reasonText =
                "detected as an industry chain line (\"" .. tostring(chainName)
                    .. "\") -- splitting would break the production sequence"

        else

            reasonText = tostring(realCount) .. " real destination(s), nothing to split"

        end

        log.info(
            "SPLIT ALL: skipping '" .. tostring(lineInfo.name) .. "' (" .. reasonText .. ")."
        )

        splitAllManagedLines(stationGroupId, managedLines, index + 1, sourceLineIds, onStatusUpdate, onAllDone)

        return

    end

    sourceLineIds[#sourceLineIds + 1] = lineInfo.id

    line_splitter.splitLineIntoDestinations(
        stationGroupId,
        lineInfo,

        function(createdCount, totalCount)

            splitAllManagedLines(stationGroupId, managedLines, index + 1, sourceLineIds, onStatusUpdate, onAllDone)

        end
    )

end


-- Entry point. `onStatusUpdate(text)` is called at every progress
-- step ("Splitting...", "Organizing terminals...", "done: N line(s)",
-- "crashed"); `onComplete()` fires exactly once, at the very end,
-- regardless of success or failure -- callers use it the same way
-- every other async chain in this codebase does, to release
-- operation_lock.
function M.splitStationLines(stationGroupId, onStatusUpdate, onComplete)

    onStatusUpdate = onStatusUpdate or function() end

    local ok, managedLines = pcall(vehicles.getManagedLinesForStation, stationGroupId)

    if not ok or managedLines == nil then

        log.info("SPLIT: could not read managed lines: " .. tostring(managedLines))

        if onComplete ~= nil then
            onComplete()
        end

        return

    end

    log.info("SPLIT ALL: starting for " .. tostring(#managedLines) .. " managed line(s).")

    onStatusUpdate("[ Splitting... ]")

    splitAllManagedLines(stationGroupId, managedLines, 1, nil, onStatusUpdate, onComplete)

end


-- ============================================================
-- ASSIGN & BALANCE FLEET (Stage 2 + Stage 3)
--
-- Decision 122: extracted from epod_truck_distribution.lua's own
-- private processSourceLineNext/handleAssignAndBalanceButtonClick --
-- the second piece of orchestration still trapped in the old panel's
-- file, and the one both the standalone "Assign & Balance Fleet"
-- (DEBUG) button AND the "Distribution Hub: ON" one-click setup
-- sequence depend on. Combines Stage 2
-- (line_splitter.assignVehiclesAndRetireStops) and Stage 3
-- (fleet_allocator.redistributeSpareVehiclesByDemand), run back-to-
-- back per source line, then attempts to delete each source line once
-- it's down to 0 vehicles and 0 real destinations.
--
-- A hub can legitimately have split more than one original combined
-- line (Decision 53 -- real case: a hub with two lines each genuinely
-- touching it), so source_line_registry records a SET per hub, and
-- every recorded source line gets its own full assign+balance+delete
-- pass here, one at a time.
-- ============================================================

local function processSourceLineNext(sourceLineIds, index, hubStationGroupId, totals, onStatusUpdate, onAllDone)

    local sourceLineId = sourceLineIds[index]

    if sourceLineId == nil then
        onAllDone()
        return
    end

    local ok, err =
        pcall(
            line_splitter.assignVehiclesAndRetireStops,
            sourceLineId,
            hubStationGroupId,

            function(assignedCount)

                totals.assigned = totals.assigned + assignedCount

                local ok2, err2 =
                    pcall(
                        fleet_allocator.redistributeSpareVehiclesByDemand,
                        sourceLineId,
                        hubStationGroupId,

                        function(redistributedCount)

                            totals.redistributed = totals.redistributed + redistributedCount

                            -- Third step: if assign+balance left this
                            -- source line with 0 vehicles and 0 real
                            -- destinations, delete it -- it is now a
                            -- degenerate hub-only loop serving
                            -- nothing. deleteEmptySourceLine refuses
                            -- to delete anything that still has
                            -- either, so this is safe to always
                            -- attempt rather than needing a separate
                            -- confirmation click.
                            local function finishSourceLine(deleted, reason)

                                if deleted then

                                    totals.deleted = totals.deleted + 1
                                    source_line_registry.removeSourceLine(hubStationGroupId, sourceLineId)

                                elseif reason == "source-line-unreadable" then

                                    -- This ID doesn't correspond to a
                                    -- real line anymore at all --
                                    -- unlike "still-has-vehicles"/
                                    -- "still-has-destinations" (a real
                                    -- line just not ready yet), there's
                                    -- nothing left to ever finish here.
                                    -- Forget it now rather than
                                    -- burning a full Stage 2/3 pass
                                    -- against it, uselessly, every
                                    -- future Assign & Balance run.
                                    source_line_registry.removeSourceLine(hubStationGroupId, sourceLineId)

                                    totals.kept[#totals.kept + 1] =
                                        tostring(sourceLineId) .. " (stale registry entry -- forgotten)"

                                else

                                    totals.kept[#totals.kept + 1] =
                                        tostring(sourceLineId) .. " (" .. tostring(reason) .. ")"

                                end

                                processSourceLineNext(sourceLineIds, index + 1, hubStationGroupId, totals, onStatusUpdate, onAllDone)

                            end

                            local ok3, err3 =
                                pcall(
                                    line_splitter.deleteEmptySourceLine,
                                    sourceLineId,
                                    hubStationGroupId,

                                    function(deleted, reason)

                                        -- "still-has-vehicles"
                                        -- specifically means 0 real
                                        -- destinations are left (the
                                        -- ONLY other refusal reason,
                                        -- "still-has-destinations", is
                                        -- a different situation and is
                                        -- not retried here) -- so any
                                        -- vehicle still on this line
                                        -- has nowhere left to
                                        -- legitimately go via the
                                        -- normal demand-weighted pass.
                                        -- Mop up any CONFIRMED-EMPTY
                                        -- leftovers once, then retry
                                        -- the delete, rather than
                                        -- leaving 1-3 trucks stuck
                                        -- looping a dead line forever.
                                        if not deleted and reason == "still-has-vehicles" then

                                            local ok4, err4 =
                                                pcall(
                                                    fleet_allocator.forceDistributeRemainingSpares,
                                                    sourceLineId,
                                                    hubStationGroupId,

                                                    function(distributedCount)

                                                        totals.redistributed = totals.redistributed + distributedCount

                                                        local ok5, err5 =
                                                            pcall(
                                                                line_splitter.deleteEmptySourceLine,
                                                                sourceLineId,
                                                                hubStationGroupId,
                                                                finishSourceLine
                                                            )

                                                        if not ok5 then

                                                            log.info(
                                                                "ASSIGN & BALANCE (retry delete step) FAILED for line "
                                                                    .. tostring(sourceLineId) .. ": " .. tostring(err5)
                                                            )

                                                            finishSourceLine(false, "retry-delete-crashed")

                                                        end

                                                    end
                                                )

                                            if not ok4 then

                                                log.info(
                                                    "ASSIGN & BALANCE (force-distribute step) FAILED for line "
                                                        .. tostring(sourceLineId) .. ": " .. tostring(err4)
                                                )

                                                finishSourceLine(false, reason)

                                            end

                                            return

                                        end

                                        finishSourceLine(deleted, reason)

                                    end
                                )

                            if not ok3 then

                                -- Must still call onAllDone (not just
                                -- log+onStatusUpdate) -- otherwise a
                                -- synchronous crash here would leave
                                -- the caller's operation_lock guard
                                -- stuck true forever, permanently
                                -- disabling hub setup for the rest of
                                -- the session. Stops processing
                                -- further source lines for this hub,
                                -- but still finishes the overall
                                -- sequence.
                                log.info(
                                    "ASSIGN & BALANCE (delete step) FAILED for line "
                                        .. tostring(sourceLineId) .. ": " .. tostring(err3)
                                )

                                onStatusUpdate("[ Assign & Balance Fleet (crashed) ]")

                                onAllDone()

                            end

                        end
                    )

                if not ok2 then

                    log.info(
                        "ASSIGN & BALANCE (balance step) FAILED for line "
                            .. tostring(sourceLineId) .. ": " .. tostring(err2)
                    )

                    onStatusUpdate("[ Assign & Balance Fleet (crashed) ]")

                    onAllDone()

                end

            end
        )

    if not ok then

        log.info(
            "ASSIGN & BALANCE (assign step) FAILED for line "
                .. tostring(sourceLineId) .. ": " .. tostring(err)
        )

        onStatusUpdate("[ Assign & Balance Fleet (crashed) ]")

        onAllDone()

    end

end


-- Entry point. Same onStatusUpdate(text)/onComplete() contract as
-- M.splitStationLines. Does NOT manage operation_lock -- same reason
-- as splitStationLines, the caller coordinates with every other
-- hub-mutating action through the one shared lock.
function M.assignAndBalanceStationLines(hubStationGroupId, onStatusUpdate, onComplete)

    onStatusUpdate = onStatusUpdate or function() end

    local sourceLineIds = source_line_registry.getSourceLines(hubStationGroupId)

    if #sourceLineIds == 0 then

        log.info(
            "ASSIGN & BALANCE: no recorded source line for this hub -- "
                .. "run Split Into Lines & Organize Terminals here first."
        )

        onStatusUpdate("[ Assign & Balance Fleet (no source line) ]")

        if onComplete ~= nil then
            onComplete()
        end

        return

    end

    local totals = { assigned = 0, redistributed = 0, deleted = 0, kept = {} }

    processSourceLineNext(
        sourceLineIds, 1, hubStationGroupId, totals, onStatusUpdate,

        function()

            local keptText =
                #totals.kept > 0
                    and (" | kept: " .. table.concat(totals.kept, ", "))
                    or ""

            onStatusUpdate(
                "[ Assign & Balance Fleet (done: "
                    .. tostring(totals.assigned) .. " assigned, "
                    .. tostring(totals.redistributed) .. " balanced, "
                    .. tostring(totals.deleted) .. " source line(s) deleted"
                    .. keptText
                    .. ") ]"
            )

            if onComplete ~= nil then
                onComplete()
            end

        end
    )

end


-- ============================================================
-- DISTRIBUTION HUB ON/OFF TOGGLE
--
-- Decision 122: extracted from epod_truck_distribution.lua's own
-- private handleAutoRedistributeToggleButtonClick/
-- runNewHubSetupSequence -- the last piece of hub-setup orchestration
-- still trapped in the old panel's file. OFF is synchronous (disable,
-- strip the "● " prefix, clean up empty owned lines); ON runs the full
-- first-time setup sequence (Split -> Rename Fleet -> Assign &
-- Balance) rather than just flipping the flag, chaining the same real
-- module calls those three individual actions already use.
--
-- Same onStatusUpdate(text)/onComplete() contract, and the same "does
-- NOT manage operation_lock itself" rule, as M.splitStationLines and
-- M.assignAndBalanceStationLines above -- the caller is expected to
-- guard this the same way, even for the OFF branch (synchronous and
-- fast, but keeping the lock discipline uniform is simpler than a
-- special case).
-- ============================================================

function M.toggleDistributionHub(hubStationGroupId, onStatusUpdate, onComplete)

    onStatusUpdate = onStatusUpdate or function() end
    onComplete = onComplete or function() end

    if hub_registry.isEnabled(hubStationGroupId) then

        hub_registry.disable(hubStationGroupId)

        log.info("DISTRIBUTION HUB: turned OFF for hub " .. tostring(hubStationGroupId))

        -- Strip the "● " prefix back off the station name, mirroring
        -- the ON branch below. Only touches it if the prefix is
        -- actually there, so this is safe to run even on a hub whose
        -- name was never changed by this mod.
        do

            local currentName = stations.getRawEntityName(hubStationGroupId)

            if currentName ~= nil and currentName:sub(1, 4) == "\xE2\x97\x8f " then
                pcall(stations.setEntityName, hubStationGroupId, currentName:sub(5))
            end

        end

        -- Clean up empty lines this hub claimed while it was enabled
        -- -- otherwise they just sit there forever as orphaned
        -- clutter. Only ever deletes lines with 0 vehicles.
        pcall(
            line_splitter.deleteEmptyOwnedLines,
            hubStationGroupId,

            function(deletedCount)

                if deletedCount > 0 then

                    log.info(
                        "DISTRIBUTION HUB: cleaned up " .. tostring(deletedCount)
                            .. " empty line(s) this hub left behind."
                    )

                end

            end
        )

        onStatusUpdate("[ Distribution Hub: OFF for this hub ]")
        onComplete()

        return

    end

    hub_registry.enable(hubStationGroupId)

    -- Mark the station itself as a converted hub, same "● " convention
    -- already used for managed lines -- so a converted hub is visible
    -- at a glance (station list, map). Only renames if not already
    -- prefixed, so re-enabling an already-renamed hub doesn't double
    -- up the bullet.
    do

        local currentName = stations.getRawEntityName(hubStationGroupId)

        if currentName ~= nil and currentName:sub(1, 4) ~= "\xE2\x97\x8f " then
            pcall(stations.setEntityName, hubStationGroupId, "\xE2\x97\x8f " .. currentName)
        end

    end

    log.info("DISTRIBUTION HUB: turned ON for hub " .. tostring(hubStationGroupId) .. " -- setting it up now.")

    onStatusUpdate("[ Setting up Distribution Hub... ]")

    local ok, err =
        pcall(
            M.splitStationLines,
            hubStationGroupId,

            function(text)
                log.info("DISTRIBUTION HUB SETUP: Split -- " .. tostring(text))
            end,

            function()

                local okRename, errRename =
                    pcall(
                        fleet_naming.renameFleetToHubIdentity,
                        hubStationGroupId,

                        function(renamedCount)

                            log.info("DISTRIBUTION HUB SETUP: renamed " .. tostring(renamedCount) .. " vehicle(s).")

                            M.assignAndBalanceStationLines(
                                hubStationGroupId,

                                function(text)
                                    log.info("DISTRIBUTION HUB SETUP: Assign & Balance -- " .. tostring(text))
                                end,

                                function()

                                    log.info("DISTRIBUTION HUB SETUP COMPLETE for hub " .. tostring(hubStationGroupId) .. ".")

                                    onStatusUpdate("[ Distribution Hub: ON for this hub ]")
                                    onComplete()

                                end
                            )

                        end
                    )

                if not okRename then

                    log.info("DISTRIBUTION HUB SETUP (rename step) FAILED: " .. tostring(errRename))

                    onStatusUpdate("[ Distribution Hub (setup crashed) ]")
                    onComplete()

                end

            end
        )

    if not ok then

        log.info("DISTRIBUTION HUB SETUP FAILED: " .. tostring(err))

        onStatusUpdate("[ Distribution Hub (setup crashed) ]")
        onComplete()

    end

end


return M
