-- ============================================================
-- TF2 Truck Distribution
-- epod_truck_distribution.lua
--
-- MANUALLY-TRIGGERED DISTRIBUTION MANAGER
--
-- Started as a read-only monitor; now runs the real pipeline
-- (Decisions 19-23) whenever the player presses a button:
--   * Split Into Lines & Organize Terminals -- always visible,
--     purely additive, never touches the source line.
--   * Assign & Balance Fleet -- DEBUG-gated, moves real vehicles.
--   * Test Bug B / Park-Stop -- DEBUG-gated diagnostic.
--
-- Every managed line's identity is tracked in a persistent registry
-- (managed_registry.lua, Decision 26), not by parsing the line's
-- display name -- the "●" prefix is cosmetic only.
--
-- Names are display-only.
-- Behaviour is driven by entity IDs.
--
-- data() also wires a real handleEvent (SimCargoSystem /
-- OnToArriveAtDestination, Decision 28) -- now the Planner +
-- Opportunistic Dispatcher's real trigger: every
-- AUTO_DISPATCH_DELIVERY_THRESHOLD deliveries, if the Auto
-- Redistribute toggle is ON, dispatcher.applyPlan runs automatically
-- against the currently selected hub (attemptAutoDispatch). The
-- manual "Apply Fleet Plan" button still exists alongside this for
-- testing -- the toggle only gates automatic execution, never the
-- Planner's own calculation.
-- ============================================================

local config = require("epod_td.config")
local demand = require("epod_td.demand")
local lines = require("epod_td.lines")
local vehicles = require("epod_td.vehicles")
local stations = require("epod_td.stations")
local route_injector = require("epod_td.route_injector")
local line_splitter = require("epod_td.line_splitter")
local fleet_allocator = require("epod_td.fleet_allocator")
local terminal_allocator = require("epod_td.terminal_allocator")
local managed_registry = require("epod_td.managed_registry")
local settings = require("epod_td.settings")
local fleet_naming = require("epod_td.fleet_naming")
local planner = require("epod_td.planner")
local dispatcher = require("epod_td.dispatcher")
local gui = require("gui")


-- ============================================================
-- CONSTANTS
-- ============================================================

local WINDOW_ID =
    "truckDistributionWindow"

-- 520 was tried and confirmed too wide live: the window rendered
-- fine, but its screen POSITION (wherever the engine's default
-- placement put it) meant part of it clipped off the screen edge.
-- Now that positionDistributionWindow() below explicitly clamps
-- the window's position to fit within the real screen size, width
-- is no longer the thing that causes clipping, so it's safe to go
-- wider again to cut down the vertical "skyscraper" shape.
local WINDOW_WIDTH =
    560

-- Width of the label portion of a row now that label + cargo icons
-- share one horizontal row instead of two separate vertical rows.
-- Must match what rows are created with in ensureDistributionWindow
-- (setText's width argument does not retroactively resize a widget
-- created narrower).
local ROW_LABEL_WIDTH =
    300

-- These three are pre-allocation ceilings, not real limits: every
-- slot up to the max is created once at window-creation time (TF2
-- component IDs cannot be created/destroyed on demand) and an
-- unused slot's row still occupies its row height even when its
-- text/icon content is cleared -- confirmed again by this exact
-- fix: the screenshot that showed only 4 of 6 real lines also
-- showed a real block of dead space below the last visible line,
-- from the 8 already-unused rows in the old 24-row ceiling. So this
-- is a genuine trade-off, not just "raise it as high as possible":
-- too low silently truncates real lines (today's bug); too high
-- reintroduces the "skyscraper" window this panel was deliberately
-- compacted out of earlier.
--
-- Originally sized at 4/24 total rows for what testing had shown at
-- the time (2 managed lines). Confirmed live that this was too low:
-- once line_splitter.lua's Stage 1-3 produced 6 real managed lines
-- at Hendon East (Grain + 5 destination splits), the panel silently
-- truncated to the first 4 -- Queens Road and Park Avenue were
-- missing from the mod's own panel despite being real, working
-- lines visible in the vanilla LINE STATISTICS panel. Raised to give
-- modest headroom above the current real network size (6 lines)
-- rather than truncating exactly at it, without ballooning the
-- ceiling so far that most sessions render a mostly-empty panel.
local MAX_MANAGED_LINES =
    8

-- Soft per-line cap: bounds how many destination rows one single
-- line can claim from the shared MAX_TOTAL_ROWS pool below, so one
-- very busy line cannot silently starve the others of any display
-- space at all.
local MAX_DESTINATIONS_PER_LINE =
    6

local MAX_CARGO_TYPES_PER_DESTINATION =
    4

-- All rows (both line name/info headers and destination rows) are
-- drawn from ONE shared flat pool, consumed sequentially as real
-- content is rendered, rather than each line reserving its own
-- fixed-size sub-block. A per-line reservation is what produced
-- the large dead-space gap under a line with few destinations
-- sitting next to a line with many: reserving a fixed destination
-- sub-block per line means an underused line's slack space cannot
-- be reclaimed by another line, and an unused row still occupies
-- its row height even with empty content. A shared sequential pool
-- has no such per-line slack -- unused capacity only ever trails
-- at the very end of the whole list, after all real content.
--
-- Raised alongside MAX_MANAGED_LINES above for the same reason: 6
-- real managed lines with 2 destination rows each (hub-return plus
-- one real destination, the steady state once a line is split) is
-- 24 rows exactly -- the previous ceiling -- leaving zero headroom
-- for a 7th line or a not-yet-split line with more than one real
-- destination. 32 gives MAX_MANAGED_LINES's new headroom (2 extra
-- lines' worth at the current 4-rows-per-line steady state) without
-- jumping straight to a worst-case ceiling (8 lines x up to 8 rows
-- each = 64) that would sit mostly empty, and mostly-blank, in the
-- common case.
local MAX_TOTAL_ROWS =
    32

-- setTransparent(true) does not hide an imageView's image content
-- (confirmed live: unused slots rendered a visible placeholder
-- glyph instead of nothing), only setText("") reliably hides text.
-- So unused/empty slots are hidden by swapping to a genuinely
-- blank texture instead of relying on setTransparent.
local BLANK_CARGO_ICON =
    "ui/hud/empty12.tga"

-- guiUpdate can fire very frequently.
--
-- Waiting cargo scanning walks SIM_ENTITY_AT_TERMINAL entities,
-- so we do not want to perform that work every GUI frame.
--
-- Selection changes refresh immediately.
-- This counter provides occasional live refreshes afterward.
local AUTO_REFRESH_GUI_UPDATES =
    120


-- ============================================================
-- STATE
-- ============================================================

local distributionState = {

    selectedEntity =
        nil,

    selectedEntityId =
        nil,

    selectedStationGroupId =
        nil,

    textViews =
        nil,

    rows =
        nil,

    -- guiUpdate() runs on every GUI frame as long as a station is
    -- selected, and previously called ensureDistributionWindow()
    -- unconditionally -- which recreated the native window on the
    -- very next tick after the player closed it with the X button,
    -- since ensureDistributionWindow() only checks whether the
    -- native window still exists, not whether the player wanted it
    -- closed. This flag, set via window:onClose(), lets the window
    -- actually stay closed until the player reselects a station.
    windowClosedByUser =
        false,

    dirty =
        false,

    guiUpdateCounter =
        0,

    -- Event-trigger research (PROGRESS.md Not Started #3, IDEAS.md
    -- "Event-Driven Demand Reassessment"): counts real
    -- OnToArriveAtDestination fires so we can confirm live whether
    -- the event actually fires reliably before any Planner logic
    -- depends on it. Kept as a running count rather than logging
    -- every fire -- this event is game-wide (every cargo delivery
    -- in the whole save, not just our hubs), and logging each one
    -- would repeat the "logs getting full" problem already fixed
    -- once this session.
    deliveryEventCount =
        0

}


-- ============================================================
-- LOGGING
-- ============================================================

local function logUi(message)

    print(
        "[TD-UI] "
        .. tostring(message)
    )

end


-- ============================================================
-- SAFE ENGINE ACCESS
-- ============================================================

local function safeGetComponent(
    entityId,
    componentType
)

    if type(entityId) ~= "number"
        or entityId < 0
    then
        return nil
    end

    local ok, component =
        pcall(
            api.engine.getComponent,
            entityId,
            componentType
        )

    if not ok then
        return nil
    end

    return component

end


local function getEntityName(entityId)

    if type(entityId) ~= "number"
        or entityId < 0
    then
        return "N/A"
    end

    local nameComponent =
        safeGetComponent(
            entityId,
            api.type.ComponentType.NAME
        )

    if nameComponent ~= nil
        and nameComponent.name ~= nil
        and nameComponent.name ~= ""
    then
        return nameComponent.name
    end

    local ok, name =
        pcall(
            game.interface.getName,
            entityId
        )

    if ok
        and name ~= nil
        and name ~= ""
    then
        return name
    end

    return "Entity "
        .. tostring(entityId)

end


-- ============================================================
-- EVENT PAYLOAD HANDLING
--
-- TF2 has supplied both numeric IDs and table payloads during
-- earlier GUI testing.
--
-- Keep this defensive so an unexpected payload can never be
-- passed directly into api.engine.getComponent().
-- ============================================================

local function extractNumericEntityId(value)

    if type(value) == "number" then
        return value
    end

    if type(value) ~= "table" then
        return nil
    end


    local candidateKeys = {

        "entityId",
        "entity",
        "id",
        "station",
        "stationGroup",
        "stationGroupId",
        "groupId",
        "number"

    }


    for _, key
        in ipairs(
            candidateKeys
        )
    do

        local candidate =
            value[key]

        if type(candidate) == "number" then
            return candidate
        end


        if type(candidate) == "table" then

            for _, nestedKey
                in ipairs(
                    candidateKeys
                )
            do

                local nestedCandidate =
                    candidate[
                        nestedKey
                    ]

                if type(nestedCandidate)
                    == "number"
                then
                    return nestedCandidate
                end

            end

        end

    end


    if type(value[1]) == "number" then
        return value[1]
    end


    return nil

end


-- ============================================================
-- STATION -> STATION GROUP
-- ============================================================

local function resolveStationGroup(entityId)

    if type(entityId) ~= "number"
        or entityId < 0
    then
        return nil
    end


    local station =
        safeGetComponent(
            entityId,
            api.type.ComponentType.STATION
        )


    if station ~= nil then

        local stationGroup =
            lines.safeField(
                station,
                "stationGroup"
            )

        if type(stationGroup) == "number"
            and stationGroup >= 0
        then
            return stationGroup
        end

    end


    local stationGroup =
        safeGetComponent(
            entityId,
            api.type.ComponentType.STATION_GROUP
        )


    if stationGroup ~= nil then
        return entityId
    end


    return nil

end


-- ============================================================
-- CARGO DISPLAY HELPERS
-- ============================================================

local function sortedCargoTypes(cargoTypes)

    local result = {}

    if cargoTypes == nil then
        return result
    end


    for cargoType, count
        in pairs(
            cargoTypes
        )
    do

        if count ~= nil
            and count > 0
        then

            result[
                #result + 1
            ] = {

                cargoType =
                    cargoType,

                count =
                    count

            }

        end

    end


    table.sort(
        result,
        function(a, b)

            if type(a.cargoType) == "number"
                and type(b.cargoType) == "number"
            then

                return a.cargoType
                    < b.cargoType

            end


            return tostring(
                a.cargoType
            )
                <
                tostring(
                    b.cargoType
                )

        end
    )


    return result

end


local function formatDestinationLabel(
    scanResult,
    destinationStationGroup
)

    if scanResult == nil then
        return "Waiting: ?"
    end


    if scanResult.error ~= nil then

        return "Waiting: unavailable"

    end


    local destination =
        demand.getDestination(
            scanResult,
            destinationStationGroup
        )


    if destination == nil then

        return "Waiting: 0"

    end


    return "Waiting: "
        .. tostring(
            destination.total
            or 0
        )

end


-- Cargo icon rows need the raw sorted list rather than a single
-- concatenated text string.
local function getDestinationCargoTypes(
    scanResult,
    destinationStationGroup
)

    if scanResult == nil
        or scanResult.error ~= nil
    then
        return {}
    end


    local destination =
        demand.getDestination(
            scanResult,
            destinationStationGroup
        )


    if destination == nil then
        return {}
    end


    return sortedCargoTypes(
        destination.cargoTypes
    )

end


-- ============================================================
-- EXPLICIT WINDOW POSITIONING
--
-- Confirmed live: the engine's default placement for a newly
-- created window can push it partly off the screen edge (observed
-- with this window docked beside another pinned panel). This uses
-- the same base-game pattern as res/scripts/guidesystem.lua's tip
-- window (getContentRect + calcMinimumSize + window_setPosition)
-- to clamp our window to a position that is guaranteed to fit
-- within the actual screen size, rather than trusting the default.
--
-- Called once, right after creation, never again -- the player can
-- still drag the window afterward, and we must not fight that by
-- repositioning it on every update.
-- ============================================================

local function positionDistributionWindow()

    if game == nil or game.gui == nil then

        logUi(
            "Cannot position window: game.gui unavailable."
        )

        return

    end


    local okRect, screenRect =
        pcall(
            game.gui.getContentRect,
            "mainView"
        )

    if not okRect or screenRect == nil then

        logUi(
            "Cannot position window: getContentRect failed: "
                .. tostring(screenRect)
        )

        return

    end


    local margin =
        20

    -- Uses WINDOW_WIDTH directly rather than
    -- game.gui.calcMinimumSize(WINDOW_ID): that call is made
    -- immediately after window creation, before the native UI has
    -- had a chance to actually lay out and measure the widgets, and
    -- confirmed live to still produce a clipped-off-screen window
    -- -- almost certainly because it returned a stale/placeholder
    -- size rather than the real ~560px content width. WINDOW_WIDTH
    -- is already known exactly, so there's no need to ask the
    -- engine to measure something we already know.
    local x =
        screenRect[3]
        - WINDOW_WIDTH
        - margin

    local y =
        margin

    if x < margin then
        x = margin
    end


    logUi(
        "Positioning window at x="
            .. tostring(x)
            .. " y="
            .. tostring(y)
            .. " (screen width="
            .. tostring(screenRect[3])
            .. ", WINDOW_WIDTH="
            .. tostring(WINDOW_WIDTH)
            .. ")"
    )


    local okSet, setErr =
        pcall(
            game.gui.window_setPosition,
            WINDOW_ID,
            x,
            y
        )

    if not okSet then

        logUi(
            "window_setPosition failed: "
                .. tostring(setErr)
        )

    end

end


-- ============================================================
-- SPLIT INTO LINES + ORGANIZE TERMINALS (Stage 1 + Stage 4)
--
-- Combined into one always-visible button: creating the dedicated
-- per-destination lines (Stage 1) and spreading them across
-- terminals by demand (Stage 4, terminal_allocator.lua) neither one
-- touches vehicle cargo or moves a vehicle -- Stage 1 is purely
-- additive, and Stage 4 only ever writes a Line.Stop.terminal value.
-- Neither carries the still-open Bug A/B risk (PROGRESS.md) that
-- keeps "Assign & Balance Fleet" DEBUG-gated and separate, so
-- combining these two specifically (not that one) was the safe half
-- of the "combine what we know works" request.
--
-- Lines processed one at a time, each waiting for the previous
-- createLine callback, rather than firing several at once into a
-- situation only tested with a single line so far. Terminal
-- organizing runs only after every split line has been created,
-- since terminal_allocator.lua needs the full "● " line set to rank
-- by demand.
-- ============================================================

local function splitAllManagedLines(
    stationGroupId,
    managedLines,
    index,
    sourceLineIds
)

    sourceLineIds =
        sourceLineIds or {}

    local lineInfo =
        managedLines[index]

    if lineInfo == nil then

        logUi(
            "SPLIT ALL: finished processing "
                .. tostring(#managedLines)
                .. " managed line(s). Organizing terminals..."
        )

        if distributionState.textViews ~= nil
            and distributionState.textViews.splitButtonLabel ~= nil
        then

            distributionState.textViews.splitButtonLabel:setText(
                "[ Organizing terminals... (see log) ]",
                WINDOW_WIDTH
            )

        end


        -- LIVE-CONFIRMED BUG: without excluding the line(s) just
        -- split, stockTakeExistingLoad (terminal_allocator.lua)
        -- treats the ORIGINAL combined line -- still alive right now,
        -- about to be deleted by a LATER "Assign & Balance Fleet"
        -- click -- as real, permanent occupancy exactly like Grain.
        -- That ties every terminal it touches with Grain's terminal
        -- on line count, and the load tiebreak then picks Grain's
        -- terminal for the first freshly-split candidate, doubling
        -- them up unnecessarily. Player hit this live: Grain and the
        -- highest-ranked new line shared terminal 1, the other 4 new
        -- lines spread fine, and re-running the whole button a
        -- SECOND time (after the source line had since been deleted
        -- by a separate Assign & Balance click) "fixed" it --
        -- coincidentally, not because retrying helped. Passing the
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

                    if distributionState.textViews ~= nil
                        and distributionState.textViews.splitButtonLabel ~= nil
                    then

                        distributionState.textViews.splitButtonLabel:setText(
                            "[ Split & Organize Terminals (done: "
                                .. tostring(processedCount)
                                .. " terminal(s) -- see log) ]",
                            WINDOW_WIDTH
                        )

                    end

                end
            )

        if not ok then

            logUi(
                "SPLIT ALL (terminal step) FAILED: "
                    .. tostring(err)
            )

            if distributionState.textViews ~= nil
                and distributionState.textViews.splitButtonLabel ~= nil
            then

                distributionState.textViews.splitButtonLabel:setText(
                    "[ Split & Organize Terminals (crashed -- see log) ]",
                    WINDOW_WIDTH
                )

            end

        end

        return

    end


    local realCount =
        0

    for _, destination
        in ipairs(lineInfo.destinations or {})
    do

        if destination.stationGroup ~= stationGroupId then
            realCount = realCount + 1
        end

    end


    if realCount < 2 then

        logUi(
            "SPLIT ALL: skipping '"
                .. tostring(lineInfo.name)
                .. "' ("
                .. tostring(realCount)
                .. " real destination(s), nothing to split)."
        )

        splitAllManagedLines(
            stationGroupId,
            managedLines,
            index + 1,
            sourceLineIds
        )

        return

    end


    sourceLineIds[#sourceLineIds + 1] =
        lineInfo.id


    line_splitter.splitLineIntoDestinations(
        stationGroupId,
        lineInfo,

        function(createdCount, totalCount)

            splitAllManagedLines(
                stationGroupId,
                managedLines,
                index + 1,
                sourceLineIds
            )

        end
    )

end


local function handleSplitButtonClick()

    if distributionState.selectedStationGroupId == nil then

        logUi(
            "SPLIT: no station selected."
        )

        return

    end


    local stationGroupId =
        distributionState.selectedStationGroupId


    local ok, managedLines =
        pcall(
            vehicles.getManagedLinesForStation,
            stationGroupId
        )

    if not ok or managedLines == nil then

        logUi(
            "SPLIT: could not read managed lines: "
                .. tostring(managedLines)
        )

        return

    end


    logUi(
        "SPLIT ALL: starting for "
            .. tostring(#managedLines)
            .. " managed line(s)."
    )

    if distributionState.textViews ~= nil
        and distributionState.textViews.splitButtonLabel ~= nil
    then

        distributionState.textViews.splitButtonLabel:setText(
            "[ Splitting... (see log) ]",
            WINDOW_WIDTH
        )

    end


    splitAllManagedLines(
        stationGroupId,
        managedLines,
        1
    )

end


-- ============================================================
-- ASSIGN & BALANCE FLEET (config.DEBUG only)
--
-- Combines Stage 2 (line_splitter.M.assignVehiclesAndRetireStops)
-- and Stage 3 (fleet_allocator.M.redistributeSpareVehiclesByDemand)
-- into one button, run back-to-back -- these were always meant to
-- be run as a pair (Stage 3 exists specifically to deal with the
-- spare fleet Stage 2's own retirement leaves behind), and having
-- them as two separate DEBUG buttons was exactly the kind of
-- confusing button sprawl this panel was cleaned up to avoid.
--
-- The old separate "Test Loaded Vehicle Move" diagnostic is gone
-- entirely, not just hidden: its purpose (checking whether setLine
-- reassignment is safe) is now something Stage 2/3 answer far more
-- thoroughly just by being run for real, across every managed line,
-- with visible in-game results -- keeping a redundant single-vehicle
-- test around after that would just be more clutter, not more
-- evidence.
--
-- Manually-triggered, not auto-run: this moves real vehicles off
-- the real production line AND rewrites that line's real route, so
-- it should only ever fire when the player deliberately asks for
-- it. See DECISIONS.md Decisions 20/21 and Outstanding Unknowns for
-- what is and is not yet proven about this.
-- ============================================================

local function handleAssignAndBalanceButtonClick()

    if distributionState.selectedStationGroupId == nil then

        logUi(
            "ASSIGN & BALANCE: no station selected."
        )

        return

    end


    if distributionState.textViews ~= nil
        and distributionState.textViews.assignBalanceButtonLabel ~= nil
    then

        distributionState.textViews.assignBalanceButtonLabel:setText(
            "[ Working... (see log) ]",
            WINDOW_WIDTH
        )

    end


    local sourceLineId =
        lines.findByName(
            config.SOURCE_LINE_NAME
        )

    local hubStationGroupId =
        distributionState.selectedStationGroupId

    local function setDoneLabel(text)

        if distributionState.textViews ~= nil
            and distributionState.textViews.assignBalanceButtonLabel ~= nil
        then

            distributionState.textViews.assignBalanceButtonLabel:setText(
                text,
                WINDOW_WIDTH
            )

        end

    end

    local ok, err =
        pcall(
            line_splitter.assignVehiclesAndRetireStops,
            sourceLineId,
            hubStationGroupId,

            function(assignedCount)

                local ok2, err2 =
                    pcall(
                        fleet_allocator.redistributeSpareVehiclesByDemand,
                        sourceLineId,
                        hubStationGroupId,

                        function(redistributedCount)

                            -- Third step: if assign+balance left the
                            -- source line with 0 vehicles and 0 real
                            -- destinations, delete it -- it is now a
                            -- degenerate hub-only loop serving
                            -- nothing. deleteEmptySourceLine refuses
                            -- to delete anything that still has
                            -- either, so this is safe to always
                            -- attempt rather than needing a separate
                            -- confirmation click.
                            local ok3, err3 =
                                pcall(
                                    line_splitter.deleteEmptySourceLine,
                                    sourceLineId,
                                    hubStationGroupId,

                                    function(deleted, reason)

                                        local sourceLineText =
                                            deleted
                                                and "source line deleted"
                                                or (
                                                    "source line kept: "
                                                        .. tostring(reason)
                                                )

                                        setDoneLabel(
                                            "[ Assign & Balance Fleet (done: "
                                                .. tostring(assignedCount)
                                                .. " assigned, "
                                                .. tostring(redistributedCount)
                                                .. " balanced, "
                                                .. sourceLineText
                                                .. " -- see log) ]"
                                        )

                                    end
                                )

                            if not ok3 then

                                logUi(
                                    "ASSIGN & BALANCE (delete step) FAILED: "
                                        .. tostring(err3)
                                )

                                setDoneLabel(
                                    "[ Assign & Balance Fleet (crashed -- see log) ]"
                                )

                            end

                        end
                    )

                if not ok2 then

                    logUi(
                        "ASSIGN & BALANCE (balance step) FAILED: "
                            .. tostring(err2)
                    )

                    setDoneLabel(
                        "[ Assign & Balance Fleet (crashed -- see log) ]"
                    )

                end

            end
        )

    if not ok then

        logUi(
            "ASSIGN & BALANCE (assign step) FAILED: "
                .. tostring(err)
        )

        setDoneLabel(
            "[ Assign & Balance Fleet (crashed -- see log) ]"
        )

    end

end


-- ============================================================
-- BUG B TEST BUTTON (config.DEBUG only)
--
-- Two clicks, same pattern as the journey test above but for a
-- different question: does a CONFIRMED-EMPTY vehicle, reassigned via
-- the exact bare setLine Stage 2 actually uses, pick up cargo at its
-- new destination's first stop (Decision 12's Park-stop problem,
-- PROGRESS.md Not Started #1)? See
-- route_injector.M.runBugBTestStep for the full protocol.
-- ============================================================

local function handleBugBTestButtonClick()

    if distributionState.textViews ~= nil
        and distributionState.textViews.bugBTestButtonLabel ~= nil
    then

        distributionState.textViews.bugBTestButtonLabel:setText(
            "[ Working... (see log) ]",
            WINDOW_WIDTH
        )

    end


    local ok, err =
        pcall(
            route_injector.runBugBTestStep,

            function(success, reason)

                if distributionState.textViews ~= nil
                    and distributionState.textViews.bugBTestButtonLabel ~= nil
                then

                    local label =
                        "[ Test Bug B / Park-Stop ("
                            .. tostring(reason)
                            .. " -- see log) ]"

                    if reason == "watching" then

                        label =
                            "[ Test Bug B / Park-Stop "
                                .. "(watching -- click again later) ]"

                    end

                    distributionState.textViews.bugBTestButtonLabel:setText(
                        label,
                        WINDOW_WIDTH
                    )

                end

            end
        )

    if not ok then

        logUi(
            "BUG B TEST FAILED: "
                .. tostring(err)
        )

        if distributionState.textViews ~= nil
            and distributionState.textViews.bugBTestButtonLabel ~= nil
        then

            distributionState.textViews.bugBTestButtonLabel:setText(
                "[ Test Bug B / Park-Stop (crashed -- see log) ]",
                WINDOW_WIDTH
            )

        end

    end

end


-- ============================================================
-- VEHICLE RENAME / COLOUR TEST BUTTON (config.DEBUG only)
--
-- Single click, immediate. See
-- route_injector.M.testVehicleRenameAndColor for the full protocol
-- -- settles whether setName/setColor actually work on a vehicle
-- entity (IDEAS.md's vehicle-naming idea currently has zero live
-- evidence either way for this).
-- ============================================================

local function handleVehicleRenameTestButtonClick()

    local ok, err =
        pcall(route_injector.testVehicleRenameAndColor)

    if not ok then

        logUi(
            "VEHICLE RENAME/COLOUR TEST FAILED: "
                .. tostring(err)
        )

    end

end


-- ============================================================
-- RENAME FLEET TO HUB IDENTITY (config.DEBUG only)
--
-- Real feature, not a disposable test -- see fleet_naming.lua for
-- the full design. Renames every managed vehicle at the currently
-- selected hub to "● <Hub Name> - Fleet (N)" and leaves it renamed;
-- unlike the single-vehicle test above, there is no restore step.
-- Player-triggered only, per Decision 4 / the player's own "stay in
-- our lane" feedback on automation -- this never runs on its own.
-- ============================================================

local function handleRenameFleetButtonClick()

    if distributionState.selectedStationGroupId == nil then

        logUi(
            "RENAME FLEET: no station selected."
        )

        return

    end

    if distributionState.textViews ~= nil
        and distributionState.textViews.renameFleetButtonLabel ~= nil
    then

        distributionState.textViews.renameFleetButtonLabel:setText(
            "[ Working... (see log) ]",
            WINDOW_WIDTH
        )

    end

    local hubStationGroupId =
        distributionState.selectedStationGroupId

    local ok, err =
        pcall(
            fleet_naming.renameFleetToHubIdentity,
            hubStationGroupId,

            function(renamedCount)

                if distributionState.textViews ~= nil
                    and distributionState.textViews.renameFleetButtonLabel ~= nil
                then

                    distributionState.textViews.renameFleetButtonLabel:setText(
                        "[ Rename Fleet to Hub Identity (done: "
                            .. tostring(renamedCount)
                            .. " renamed -- see log) ]",
                        WINDOW_WIDTH
                    )

                end

            end
        )

    if not ok then

        logUi(
            "RENAME FLEET FAILED: "
                .. tostring(err)
        )

        if distributionState.textViews ~= nil
            and distributionState.textViews.renameFleetButtonLabel ~= nil
        then

            distributionState.textViews.renameFleetButtonLabel:setText(
                "[ Rename Fleet to Hub Identity (crashed -- see log) ]",
                WINDOW_WIDTH
            )

        end

    end

end


-- ============================================================
-- SHOW FLEET PLAN (config.DEBUG only)
--
-- First real piece of the Planner (planner.lua, PROGRESS.md Not
-- Started #4 / IDEAS.md "Runtime Fleet Rebalancing"). Read-only --
-- logs the target vehicle count per managed line at the selected
-- hub, weighted by current demand.scan() waiting cargo, against a
-- per-line floor. Does not move a single vehicle; exists so the
-- Planner's numbers can be sanity-checked against what's actually
-- happening at the hub before anything is ever allowed to act on
-- them. Same staged approach every other stage in this mod has used
-- (build additive/read-only first, prove it live, only then
-- consider automation).
-- ============================================================

local function handleShowFleetPlanButtonClick()

    if distributionState.selectedStationGroupId == nil then

        logUi(
            "SHOW FLEET PLAN: no station selected."
        )

        return

    end

    local hubStationGroupId =
        distributionState.selectedStationGroupId

    local hubName =
        stations.getEntityName(hubStationGroupId)

    local ok, err =
        pcall(
            planner.logTargetAllocation,
            hubStationGroupId,
            hubName
        )

    if not ok then

        logUi(
            "SHOW FLEET PLAN FAILED: "
                .. tostring(err)
        )

    end

end


-- ============================================================
-- APPLY FLEET PLAN (config.DEBUG only)
--
-- First real piece of the Opportunistic Dispatcher (dispatcher.lua,
-- PROGRESS.md Not Started #4). Moves real, empty, compatible
-- vehicles between managed lines toward the Planner's target
-- allocation -- capped at a handful per click (dispatcher.lua's
-- MAX_MOVES_PER_RUN) rather than rebalancing an entire fleet blind
-- on the first live test. Manually triggered only -- does not read
-- the Auto Redistribute toggle. Same staged approach as every
-- earlier stage: prove it live via a manual button first.
-- ============================================================

local function handleApplyFleetPlanButtonClick()

    if distributionState.selectedStationGroupId == nil then

        logUi(
            "APPLY FLEET PLAN: no station selected."
        )

        return

    end

    if distributionState.textViews ~= nil
        and distributionState.textViews.applyFleetPlanButtonLabel ~= nil
    then

        distributionState.textViews.applyFleetPlanButtonLabel:setText(
            "[ Working... (see log) ]",
            WINDOW_WIDTH
        )

    end

    local hubStationGroupId =
        distributionState.selectedStationGroupId

    local ok, err =
        pcall(
            dispatcher.applyPlan,
            hubStationGroupId,

            function(movesMade)

                if distributionState.textViews ~= nil
                    and distributionState.textViews.applyFleetPlanButtonLabel ~= nil
                then

                    distributionState.textViews.applyFleetPlanButtonLabel:setText(
                        "[ Apply Fleet Plan (done: "
                            .. tostring(movesMade)
                            .. " moved -- see log) ]",
                        WINDOW_WIDTH
                    )

                end

            end
        )

    if not ok then

        logUi(
            "APPLY FLEET PLAN FAILED: "
                .. tostring(err)
        )

        if distributionState.textViews ~= nil
            and distributionState.textViews.applyFleetPlanButtonLabel ~= nil
        then

            distributionState.textViews.applyFleetPlanButtonLabel:setText(
                "[ Apply Fleet Plan (crashed -- see log) ]",
                WINDOW_WIDTH
            )

        end

    end

end


-- ============================================================
-- AUTO REDISTRIBUTE TOGGLE (config.DEBUG only)
--
-- Built and persisted (settings.lua, same io.open pattern as
-- managed_registry.lua -- Decision 26) before any real behavior
-- depended on it, per the design agreed live: this toggle only ever
-- controls whether the Dispatcher is ALLOWED to execute its plan
-- automatically -- it never controls whether the Planner calculates
-- at all (the Planner always runs, gating happens one layer up).
-- Turning this off means "ask me first," not "stop thinking."
--
-- REAL, AND FIXED FOR THE MULTI-INSTANCE PROBLEM (Decision 35):
-- attemptAutoDispatch runs from handleEvent, which live testing
-- proved runs on a DIFFERENT script instance than guiUpdate -- the
-- same class of bug that broke data()'s save/load (Decision 24).
-- That instance's own distributionState.selectedStationGroupId never
-- saw what the panel had selected, so auto-dispatch silently never
-- fired even with the toggle on. Fix: persist WHICH hub is being
-- auto-managed (settings.lua's autoDispatchHubStationGroupId) at the
-- moment the toggle is turned ON, rather than depending on whatever
-- happens to be selected right now -- file I/O is the one thing
-- already confirmed to cross the instance boundary reliably. This is
-- also better behavior, not just a workaround: auto-dispatch now
-- keeps running for that hub even while the player is looking at
-- something else on the map, instead of requiring the panel to stay
-- focused on it.
-- ============================================================

local function autoRedistributeLabelText()

    if settings.get("autoRedistribute") then

        local hubId =
            settings.get("autoDispatchHubStationGroupId")

        if hubId == nil then
            return "[ Auto Redistribute: ON (no hub captured yet) ]"
        end

        return "[ Auto Redistribute: ON (hub " .. tostring(hubId) .. ") ]"

    end

    return "[ Auto Redistribute: OFF ]"

end

local function handleAutoRedistributeToggleButtonClick()

    local newValue =
        not settings.get("autoRedistribute")

    settings.set("autoRedistribute", newValue)

    if newValue then

        if distributionState.selectedStationGroupId ~= nil then

            settings.set(
                "autoDispatchHubStationGroupId",
                distributionState.selectedStationGroupId
            )

            logUi(
                "AUTO REDISTRIBUTE: now managing hub "
                    .. tostring(distributionState.selectedStationGroupId)
            )

        else

            logUi(
                "AUTO REDISTRIBUTE: turned ON, but no hub is currently "
                    .. "selected -- select one and toggle again to "
                    .. "capture it."
            )

        end

    end

    if distributionState.textViews ~= nil
        and distributionState.textViews.autoRedistributeButtonLabel ~= nil
    then

        distributionState.textViews.autoRedistributeButtonLabel:setText(
            autoRedistributeLabelText(),
            WINDOW_WIDTH
        )

    end

    logUi(
        "AUTO REDISTRIBUTE setting: "
            .. tostring(newValue)
    )

end


-- ============================================================
-- CREATE THE DISTRIBUTION WINDOW
--
-- IMPORTANT TF2 UI RULE LEARNED DURING TESTING:
--
-- UI component IDs must not be recreated repeatedly.
--
-- Therefore all managed-line / destination text views are
-- allocated ONCE and reused with setText().
-- ============================================================

local function ensureDistributionWindow()

    if distributionState.selectedEntityId == nil then
        return nil
    end


    if distributionState.windowClosedByUser then
        return nil
    end


    if api == nil
        or api.gui == nil
        or api.gui.util == nil
    then

        logUi(
            "GUI API unavailable."
        )

        return nil

    end


    local existing =
        api.gui.util.getById(
            WINDOW_ID
        )


    if existing ~= nil then
        return existing
    end


    -- If the player previously closed the window, old Lua
    -- references should not be reused when the native window no
    -- longer exists.

    distributionState.textViews =
        nil

    distributionState.rows =
        nil


    local layout =
        gui.boxLayout_create(
            WINDOW_ID .. ".layout",
            "VERTICAL"
        )


    local window =
        gui.window_create(
            WINDOW_ID,
            "Truck Distribution",
            layout
        )


    if window == nil then

        logUi(
            "Unable to create Truck Distribution window."
        )

        return nil

    end


    -- Base-game pattern (see res/scripts/guidesystem.lua's tip
    -- window): window:onClose() fires when the native window
    -- closes, including via the X button, independent of our own
    -- guiHandleEvent. Without this, guiUpdate() would recreate the
    -- window on the very next frame after the player closed it.
    window:onClose(
        function()

            distributionState.windowClosedByUser =
                true

            logUi(
                "Truck Distribution window closed by user."
            )

        end
    )


    -- Merged from the original 7 rows (title, status, station,
    -- entity, lines, trucks, managedLinesHeader) down to 4, to cut
    -- fixed vertical space -- confirmed live that the window was
    -- reading as too tall/thin.

    -- Down to one row. The native window chrome already shows
    -- "Truck Distribution" as the title bar (see gui.window_create
    -- below), so repeating it in the body was pure duplication.
    -- "Status: Read-only" doesn't change and isn't player-relevant
    -- ongoing information, so it's dropped from the persistent
    -- display; the entity ID is dev-only detail, kept in the
    -- [TD-UI] log line instead of the visible panel.

    distributionState.textViews = {

        summary =
            gui.textView_create(
                WINDOW_ID .. ".summary",
                "Station: N/A",
                WINDOW_WIDTH,
                false
            ),

        -- Content widget for the split button below. gui.lua's
        -- button:onClick() is unverified in this mod (never used
        -- before this), but it's the same shared callback-table
        -- pattern as window:onClose(), which was confirmed working
        -- live -- reasonable confidence, not proof.
        splitButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".splitButtonLabel",
                "[ Split Into Lines & Organize Terminals ]",
                WINDOW_WIDTH,
                false
            )

    }


    local splitButton =
        gui.button_create(
            WINDOW_ID .. ".splitButton",
            distributionState.textViews.splitButtonLabel
        )

    splitButton:onClick(
        handleSplitButtonClick
    )

    distributionState.splitButton =
        splitButton


    local fixedViews = {

        distributionState.textViews.summary,
        splitButton

    }


    -- config.DEBUG only: "Assign & Balance Fleet" moves real
    -- vehicles and still carries the two open Bug A/B safety
    -- questions (PROGRESS.md), and the journey test moves a real
    -- vehicle too -- neither widget is even created for a non-debug
    -- build. "Spread Lines Across Terminals" used to be its own
    -- third button here; folded into the always-visible
    -- "Split Into Lines & Organize Terminals" button above instead,
    -- since it doesn't touch vehicle cargo and carries none of this
    -- block's risk.
    if config.DEBUG then

        distributionState.textViews.assignBalanceButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".assignBalanceButtonLabel",
                "[ Assign & Balance Fleet (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local assignBalanceButton =
            gui.button_create(
                WINDOW_ID .. ".assignBalanceButton",
                distributionState.textViews.assignBalanceButtonLabel
            )

        assignBalanceButton:onClick(
            handleAssignAndBalanceButtonClick
        )

        distributionState.assignBalanceButton =
            assignBalanceButton

        fixedViews[#fixedViews + 1] =
            assignBalanceButton


        distributionState.textViews.bugBTestButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".bugBTestButtonLabel",
                "[ Test Bug B / Park-Stop (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local bugBTestButton =
            gui.button_create(
                WINDOW_ID .. ".bugBTestButton",
                distributionState.textViews.bugBTestButtonLabel
            )

        bugBTestButton:onClick(
            handleBugBTestButtonClick
        )

        distributionState.bugBTestButton =
            bugBTestButton

        fixedViews[#fixedViews + 1] =
            bugBTestButton


        -- Initial label reflects whatever was actually persisted
        -- (settings.lua), not a hardcoded "OFF" -- the toggle should
        -- show its real state immediately on window creation,
        -- including after a save/reload.
        distributionState.textViews.autoRedistributeButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".autoRedistributeButtonLabel",
                autoRedistributeLabelText(),
                WINDOW_WIDTH,
                false
            )

        local autoRedistributeButton =
            gui.button_create(
                WINDOW_ID .. ".autoRedistributeButton",
                distributionState.textViews.autoRedistributeButtonLabel
            )

        autoRedistributeButton:onClick(
            handleAutoRedistributeToggleButtonClick
        )

        distributionState.autoRedistributeButton =
            autoRedistributeButton

        fixedViews[#fixedViews + 1] =
            autoRedistributeButton


        distributionState.textViews.vehicleRenameTestButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".vehicleRenameTestButtonLabel",
                "[ Test Vehicle Rename/Colour (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local vehicleRenameTestButton =
            gui.button_create(
                WINDOW_ID .. ".vehicleRenameTestButton",
                distributionState.textViews.vehicleRenameTestButtonLabel
            )

        vehicleRenameTestButton:onClick(
            handleVehicleRenameTestButtonClick
        )

        distributionState.vehicleRenameTestButton =
            vehicleRenameTestButton

        fixedViews[#fixedViews + 1] =
            vehicleRenameTestButton


        distributionState.textViews.renameFleetButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".renameFleetButtonLabel",
                "[ Rename Fleet to Hub Identity (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local renameFleetButton =
            gui.button_create(
                WINDOW_ID .. ".renameFleetButton",
                distributionState.textViews.renameFleetButtonLabel
            )

        renameFleetButton:onClick(
            handleRenameFleetButtonClick
        )

        distributionState.renameFleetButton =
            renameFleetButton

        fixedViews[#fixedViews + 1] =
            renameFleetButton


        distributionState.textViews.showFleetPlanButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".showFleetPlanButtonLabel",
                "[ Show Fleet Plan (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local showFleetPlanButton =
            gui.button_create(
                WINDOW_ID .. ".showFleetPlanButton",
                distributionState.textViews.showFleetPlanButtonLabel
            )

        showFleetPlanButton:onClick(
            handleShowFleetPlanButtonClick
        )

        distributionState.showFleetPlanButton =
            showFleetPlanButton

        fixedViews[#fixedViews + 1] =
            showFleetPlanButton


        distributionState.textViews.applyFleetPlanButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".applyFleetPlanButtonLabel",
                "[ Apply Fleet Plan (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local applyFleetPlanButton =
            gui.button_create(
                WINDOW_ID .. ".applyFleetPlanButton",
                distributionState.textViews.applyFleetPlanButtonLabel
            )

        applyFleetPlanButton:onClick(
            handleApplyFleetPlanButtonClick
        )

        distributionState.applyFleetPlanButton =
            applyFleetPlanButton

        fixedViews[#fixedViews + 1] =
            applyFleetPlanButton

    end


    for _, view
        in ipairs(
            fixedViews
        )
    do

        layout:addItem(
            view
        )

    end


    -- All rows (line headers and destinations alike) are drawn
    -- from this one shared, sequentially-consumed pool. See the
    -- MAX_TOTAL_ROWS comment above for why.

    distributionState.rows =
        {}


    for rowIndex = 1,
        MAX_TOTAL_ROWS
    do

        local rowPrefix =
            WINDOW_ID
            .. ".row."
            .. tostring(
                rowIndex
            )


        -- One horizontal row per stop instead of two vertical
        -- rows (a label row, then a separate cargo-icon row) --
        -- confirmed live that spending two rows per destination was
        -- most of why the panel read as too tall even after the
        -- earlier width/positioning fixes. The label and every
        -- cargo icon/count pair now live in the same rowLayout, so
        -- only ONE child gets added to the outer vertical layout.

        local rowLayout =
            gui.boxLayout_create(
                rowPrefix .. ".row",
                "HORIZONTAL"
            )


        local labelView =
            gui.textView_create(
                rowPrefix .. ".label",
                "",
                ROW_LABEL_WIDTH,
                false
            )

        rowLayout:addItem(
            labelView
        )


        local cargoIcons = {}
        local cargoCounts = {}


        for cargoSlotIndex = 1,
            MAX_CARGO_TYPES_PER_DESTINATION
        do

            local iconView =
                gui.imageView_create(
                    rowPrefix
                    .. ".cargoIcon."
                    .. tostring(cargoSlotIndex),
                    BLANK_CARGO_ICON
                )

            local countView =
                gui.textView_create(
                    rowPrefix
                    .. ".cargoCount."
                    .. tostring(cargoSlotIndex),
                    "",
                    70,
                    false
                )

            iconView:setTransparent(true)
            countView:setTransparent(true)

            rowLayout:addItem(iconView)
            rowLayout:addItem(countView)

            cargoIcons[cargoSlotIndex] = iconView
            cargoCounts[cargoSlotIndex] = countView

        end


        layout:addItem(
            rowLayout
        )


        distributionState.rows[
            rowIndex
        ] = {

            label =
                labelView,

            cargoIcons =
                cargoIcons,

            cargoCounts =
                cargoCounts

        }

    end


    logUi(
        "Truck Distribution window created."
    )


    positionDistributionWindow()


    return window

end


-- ============================================================
-- CLEAR / HIDE A SINGLE ROW
--
-- Used by clearAllRows(), which blanks every row up front before
-- each render pass; renderManagedLineRows() then only overwrites
-- the rows it actually has content for, so whatever rows go
-- unused this frame are left blank rather than needing a separate
-- cleanup pass afterward.
-- ============================================================

local function clearRow(row)

    row.label:setText(
        "",
        ROW_LABEL_WIDTH
    )

    for cargoSlotIndex = 1,
        MAX_CARGO_TYPES_PER_DESTINATION
    do

        row.cargoIcons[
            cargoSlotIndex
        ]:setImage(BLANK_CARGO_ICON)

        row.cargoIcons[
            cargoSlotIndex
        ]:setTransparent(true)

        row.cargoCounts[
            cargoSlotIndex
        ]:setTransparent(true)

        row.cargoCounts[
            cargoSlotIndex
        ]:setText("", 70)

    end

end


-- ============================================================
-- CLEAR ALL REUSABLE ROWS
-- ============================================================

local function clearAllRows()

    if distributionState.rows
        == nil
    then
        return
    end


    for rowIndex = 1,
        MAX_TOTAL_ROWS
    do

        local row =
            distributionState.rows[
                rowIndex
            ]

        if row ~= nil then
            clearRow(row)
        end

    end

end


-- ============================================================
-- UPDATE WINDOW CONTENT
-- ============================================================

local function updateDistributionWindow()

    if distributionState.selectedEntityId == nil
        or distributionState.selectedEntity == nil
    then

        if distributionState.textViews ~= nil then

            distributionState.textViews.summary:setText(
                "Station: N/A",
                WINDOW_WIDTH
            )

            clearAllRows()

        end


        distributionState.dirty =
            false

        return

    end


    local window =
        ensureDistributionWindow()


    if window == nil
        or distributionState.textViews == nil
    then
        return
    end


    local selectedEntityId =
        distributionState.selectedEntityId


    local selectedName =
        getEntityName(
            selectedEntityId
        )


    local stationGroupId =
        resolveStationGroup(
            selectedEntityId
        )


    distributionState.selectedStationGroupId =
        stationGroupId


    local managedLines =
        {}

    local managedLineCount =
        0

    local managedTruckCount =
        0


    if stationGroupId ~= nil then

        managedLines =
            vehicles.getManagedLinesForStation(
                stationGroupId
            )


        managedLineCount =
            #managedLines


        for _, lineInfo
            in ipairs(
                managedLines
            )
        do

            managedTruckCount =
                managedTruckCount
                + (
                    lineInfo.vehicleCount
                    or 0
                )


            -- ------------------------------------------------
            -- READ-ONLY DEMAND SCAN
            --
            -- Both arguments are numeric entity IDs.
            -- No station or line names drive behaviour.
            -- ------------------------------------------------

            lineInfo.demand =
                demand.scan(
                    lineInfo.id,
                    stationGroupId
                )


            -- demand.printReport() used to fire here every refresh,
            -- for every managed line -- a full second re-scan
            -- (demand.scan already runs above, into lineInfo.demand)
            -- purely to print a diagnostic report. IDEAS.md's
            -- "Refresh Cost at Late-Game Scale" already flagged this
            -- exact call as doubling the single most expensive part
            -- of a refresh for no reason once the panel itself
            -- doesn't need it -- removed at the player's request when
            -- logs were getting too full each run. Still available
            -- to call manually (demand.printReport(lineId,
            -- stationGroupId)) if a specific line's destination
            -- breakdown is ever needed for debugging again.

        end

    end


    -- --------------------------------------------------------
    -- HEADER
    -- --------------------------------------------------------

    distributionState.textViews.summary:setText(
        tostring(
            selectedName
        )
        .. "   |   "
        .. tostring(
            managedLineCount
        )
        .. " line"
        .. (
            managedLineCount == 1
                and ""
                or "s"
        )
        .. "   |   "
        .. tostring(
            managedTruckCount
        )
        .. " vehicle"
        .. (
            managedTruckCount == 1
                and ""
                or "s"
        ),
        WINDOW_WIDTH
    )


    clearAllRows()


    if distributionState.rows
        == nil
    then

        distributionState.dirty =
            false

        return

    end


    -- --------------------------------------------------------
    -- MANAGED LINE / DESTINATION ROWS
    --
    -- Rows are consumed sequentially from the shared flat pool:
    -- a line's name row, its info row, then its destination rows,
    -- then straight on to the next line's name row -- no reserved
    -- per-line sub-block, so a sparsely-served line leaves no gap
    -- before the next line's content. See MAX_TOTAL_ROWS above.
    -- --------------------------------------------------------

    local rowCursor =
        1

    local function nextRow()

        if rowCursor > MAX_TOTAL_ROWS then
            return nil
        end

        local row =
            distributionState.rows[
                rowCursor
            ]

        rowCursor =
            rowCursor + 1

        return row

    end

    local function renderManagedLineRows()

        for lineIndex, lineInfo
            in ipairs(
                managedLines
            )
        do

            if lineIndex > MAX_MANAGED_LINES then
                return
            end


            -- Two-row card per line: name alone, then vehicle/
            -- waiting counts. Confirmed live that cramming name +
            -- vehicles + waiting onto one row wrapped ugly once a
            -- line name was long ("Truck - CD - Hendon | Vehicles:
            -- 50 | Waiting: 526" wrapped mid-number). Splitting
            -- avoids that regardless of name length, without
            -- needing to widen the whole window again. The line
            -- entity ID is dev-only detail; it's dropped from this
            -- player-facing text and logged instead, same treatment
            -- as the station entity ID elsewhere in this file.
            -- "Trucks" renamed to "Vehicles": the network-discovery
            -- logic doesn't actually care that these happen to be
            -- trucks, so the label shouldn't bake that assumption
            -- in either.

            local nameRow =
                nextRow()

            if nameRow == nil then
                return
            end


            local countsRow =
                nextRow()

            if countsRow == nil then
                return
            end


            local lineWaiting =
                0

            if lineInfo.demand ~= nil then

                lineWaiting =
                    lineInfo.demand.totalWaiting
                    or 0

            end


            logUi(
                "line="
                    .. tostring(lineInfo.name)
                    .. " id="
                    .. tostring(lineInfo.id)
            )


            -- Every line shown in this panel has already passed
            -- getManagedLinesForStation's road/stop-matching check,
            -- so it is "managed" here regardless of whether this
            -- mod created it (line_splitter.lua's own "● " lines) or
            -- it already existed in the player's save (e.g. "Grain").
            -- The bullet used to only appear on mod-created lines'
            -- real TF2 names; requested live to mark every line the
            -- same way for visual consistency. This is DISPLAY ONLY
            -- -- it does not rename the underlying TF2 line -- so
            -- lines that already carry the bullet in their real name
            -- are not double-prefixed.
            local displayLineName =
                tostring(lineInfo.name)

            if displayLineName:sub(1, 4) ~= "● " then
                displayLineName = "● " .. displayLineName
            end

            nameRow.label:setText(
                displayLineName,
                WINDOW_WIDTH
            )


            countsRow.label:setText(

                tostring(
                    lineInfo.vehicleCount
                    or 0
                )
                .. " vehicles   |   "
                .. tostring(
                    lineWaiting
                )
                .. " waiting",

                WINDOW_WIDTH

            )


            if lineInfo.destinations ~= nil then

                -- A destination's "-> Name | Waiting" row, or the
                -- hub's own "<- Hendon East | Waiting" row, is only
                -- ever worth showing if the relevant station has
                -- actually produced/received something at some
                -- point in its history -- not just "currently 0."
                -- LIVE-CONFIRMED via stations.getItemTotals: 5 real
                -- town destinations (Queens Road, Alexander Road,
                -- The Grove, Park Avenue, Highfield Road) all show
                -- itemsLoaded._sum == 0 across their whole history
                -- (structurally pure drop-off points, so their "<-"
                -- row can never be anything but 0), while
                -- Barrow-in-Furness Transfer shows itemsLoaded._sum
                -- == 13661 GRAIN (a real producer, just currently
                -- between deliveries) -- its "<-" row stays. The
                -- hub-return bucket can be fed by more than one real
                -- destination on a multi-stop line, so it is only
                -- hidden if EVERY real destination on this line has
                -- itemsLoaded._sum == 0 -- otherwise a genuine
                -- (if currently quiet) producer elsewhere on the
                -- line would be masked.
                local hubReturnHasNeverProduced = true

                for _, otherDestination in ipairs(lineInfo.destinations) do

                    if otherDestination.stationGroup ~= stationGroupId then

                        local otherTotals =
                            stations.getItemTotals(otherDestination.stationGroup)

                        if otherTotals.loaded > 0 then
                            hubReturnHasNeverProduced = false
                        end

                    end

                end


                local visibleDestinationCount = 0

                for _, destination
                    in ipairs(
                        lineInfo.destinations
                    )
                do

                    local isHubReturnRow =
                        destination.stationGroup == stationGroupId

                    local skipRow = false

                    if isHubReturnRow then

                        skipRow = hubReturnHasNeverProduced

                    else

                        local destinationTotals =
                            stations.getItemTotals(destination.stationGroup)

                        skipRow = destinationTotals.unloaded == 0

                    end

                    if not skipRow then

                    visibleDestinationCount =
                        visibleDestinationCount + 1

                    if visibleDestinationCount
                        > MAX_DESTINATIONS_PER_LINE
                    then
                        break
                    end


                    local destRow =
                        nextRow()

                    if destRow == nil then
                        return
                    end


                    local labelText =
                        formatDestinationLabel(
                            lineInfo.demand,
                            destination.stationGroup
                        )

                    local cargoTypes =
                        getDestinationCargoTypes(
                            lineInfo.demand,
                            destination.stationGroup
                        )


                    -- Plain ASCII arrows, not the ↔/● glyphs proven
                    -- safe in native TF2 line names: this text
                    -- renders through gui.textView_create inside our
                    -- own custom window, a different rendering path
                    -- that has never been glyph-tested, so this
                    -- sticks to characters known to render anywhere.
                    -- "->" = cargo waiting at the hub bound for this
                    -- destination; "<-" = cargo waiting at this
                    -- destination bound back for the hub (previously
                    -- labelled with a "(return)" text suffix on the
                    -- hub's own bucket instead -- see vehicles.lua).
                    local directionArrow =
                        destination.stationGroup == stationGroupId
                            and "<-"
                            or "->"

                    destRow.label:setText(

                        "    "
                        .. directionArrow
                        .. " "
                        .. tostring(
                            destination.name
                        )
                        .. " | "
                        .. labelText,

                        ROW_LABEL_WIDTH

                    )


                    for cargoSlotIndex = 1,
                        MAX_CARGO_TYPES_PER_DESTINATION
                    do

                        local iconView =
                            destRow.cargoIcons[
                                cargoSlotIndex
                            ]

                        local countView =
                            destRow.cargoCounts[
                                cargoSlotIndex
                            ]

                        local cargo =
                            cargoTypes[
                                cargoSlotIndex
                            ]


                        if cargo == nil then

                            iconView:setImage(BLANK_CARGO_ICON)
                            iconView:setTransparent(true)
                            countView:setTransparent(true)
                            countView:setText("", 70)

                        else

                            local iconPath =
                                demand.getCargoTypeIconPath(
                                    cargo.cargoType
                                )


                            if iconPath == nil then

                                -- Icon lookup failed (or has not
                                -- been proven yet) -- fall back to
                                -- a readable text label rather than
                                -- an invisible or broken icon.
                                iconView:setImage(BLANK_CARGO_ICON)
                                iconView:setTransparent(true)

                                countView:setTransparent(false)
                                countView:setText(
                                    demand.getCargoTypeDisplayName(
                                        cargo.cargoType
                                    )
                                    .. ": "
                                    .. tostring(cargo.count),
                                    200
                                )

                            else

                                iconView:setImage(iconPath)
                                iconView:setTransparent(false)

                                countView:setTransparent(false)
                                countView:setText(
                                    tostring(cargo.count),
                                    70
                                )

                            end

                        end

                    end

                    end

                end

            end

        end

    end

    renderManagedLineRows()


    logUi(
        "entity="
        .. tostring(
            selectedEntityId
        )
        .. " stationGroup="
        .. tostring(
            stationGroupId
        )
        .. " managedLines="
        .. tostring(
            managedLineCount
        )
        .. " managedTrucks="
        .. tostring(
            managedTruckCount
        )
    )


    distributionState.dirty =
        false

    distributionState.guiUpdateCounter =
        0

end


-- ============================================================
-- STATION SELECTION
-- ============================================================

local function handleStationSelection(value)

    if value == nil then

        distributionState.selectedEntity =
            nil

        distributionState.selectedEntityId =
            nil

        distributionState.selectedStationGroupId =
            nil

        distributionState.dirty =
            true

        -- Requested live: close our panel when the station is
        -- deselected, rather than leaving an empty shell open.
        -- guiHandleEvent already fires this same "deselect" path on
        -- mainView regardless of what specifically triggered it (the
        -- player clicking away on the map, or -- most likely, since
        -- the game's own station-info panel only exists while
        -- something is selected -- pressing that panel's own X).
        -- Confirmed live from the base game's own res/scripts/gui.lua:
        -- window:close() is a real method (game.gui.window_close),
        -- the same underlying id onClose already uses. Whether the
        -- vanilla panel's X specifically triggers this path has not
        -- been independently confirmed -- worth watching for on the
        -- next test.
        local existingWindow =
            api ~= nil
                and api.gui ~= nil
                and api.gui.util ~= nil
                and api.gui.util.getById(WINDOW_ID)
                or nil

        if existingWindow ~= nil then

            local okClose, closeErr =
                pcall(function()
                    existingWindow:close()
                end)

            if not okClose then

                logUi(
                    "Failed closing window on deselect: "
                        .. tostring(closeErr)
                )

            end

        end

        updateDistributionWindow()

        return

    end


    local entityId =
        extractNumericEntityId(
            value
        )


    if type(entityId) ~= "number" then

        logUi(
            "Selection payload contained no numeric entity ID."
        )

        return

    end


    local ok, entity =
        pcall(
            game.interface.getEntity,
            entityId
        )


    if not ok
        or entity == nil
    then

        logUi(
            "Unable to resolve selected entity "
            .. tostring(
                entityId
            )
        )

        return

    end


    distributionState.selectedEntity =
        entity

    distributionState.selectedEntityId =
        entityId

    distributionState.selectedStationGroupId =
        resolveStationGroup(
            entityId
        )

    -- stations.dumpItemHistory used to fire here once per session --
    -- answered "do itemsLoaded/itemsUnloaded's _lastMonth/_lastYear
    -- sub-tables break down by cargo type" -- yes, confirmed live
    -- (Decision 28): { _sum=0, CONSTRUCTION_MATERIALS=0, FUEL=0,
    -- FOOD=0 } etc., real per-type keys, not just an opaque total.
    -- Removed now that the question is answered, matching this
    -- session's own log-volume discipline -- still available to call
    -- manually (stations.dumpItemHistory(stationGroupId, label)) if
    -- ever needed again.

    -- A fresh selection means the player wants the window again,
    -- even if they closed it earlier this session.
    distributionState.windowClosedByUser =
        false

    distributionState.dirty =
        true


    ensureDistributionWindow()

    updateDistributionWindow()

end


-- ============================================================
-- COMMAND SURFACE DIAGNOSTIC
--
-- One-time, read-only investigation: does TF2 expose a distinct
-- "create a new line" command, or is api.cmd.make.updateLine (the
-- only line-related command proven so far, used by
-- route_injector.lua to rewrite an EXISTING line's stops) the only
-- one available? No shipped base-game or campaign-mission script
-- anywhere calls any api.cmd.make.* command that creates rather
-- than updates a line -- TECHNICAL_RESEARCH.md notes line creation
-- as "documented" from an earlier pass over the official API
-- reference, but the exact command name was never independently
-- confirmed against this game version. Rather than guess a name,
-- this just enumerates every key TF2 actually registers under
-- api.cmd.make, settling it directly instead of by inference.
--
-- Does not call any command -- pairs() over the table only reads
-- its keys, no game state is touched.
-- ============================================================

local function dumpAvailableCommands()

    if not config.DEBUG then
        return
    end

    if api == nil or api.cmd == nil or api.cmd.make == nil then

        logUi(
            "COMMAND SURFACE DIAGNOSTIC: api.cmd.make unavailable."
        )

        return

    end

    local ok, err =
        pcall(
            function()

                logUi(
                    "----------------------------------------"
                )

                logUi(
                    "COMMAND SURFACE DIAGNOSTIC: api.cmd.make.*"
                )

                logUi(
                    "----------------------------------------"
                )

                local count =
                    0

                for commandName, _
                    in pairs(
                        api.cmd.make
                    )
                do

                    logUi(
                        "  " .. tostring(commandName)
                    )

                    count =
                        count + 1

                end

                logUi(
                    "Total commands: "
                        .. tostring(count)
                )

                logUi(
                    "----------------------------------------"
                )

            end
        )

    if not ok then

        logUi(
            "COMMAND SURFACE DIAGNOSTIC FAILED: "
                .. tostring(err)
        )

    end

end


-- ============================================================
-- GUI UPDATE
--
-- Do not recreate widgets here.
--
-- Refresh immediately when selection/data is marked dirty.
-- Otherwise occasionally rescan waiting cargo so the panel can
-- change while the game runs.
-- ============================================================

-- ============================================================
-- ONE-SHOT STARTUP DIAGNOSTICS
--
-- Confirmed live: calling these directly from data() crashes with
-- "attempt to index field 'interface' (a nil value)" in
-- lines.findByName -- game.interface is not yet available at the
-- point data()'s body runs (that call is registration-time, before
-- the live game session bindings exist). Every other place in this
-- file that touches game.interface only ever runs from inside
-- guiUpdate/guiHandleEvent, which fire after the session is live;
-- this brings the diagnostics in line with that same rule instead
-- of special-casing them. hasRunStartupDiagnostics ensures they
-- still only fire once despite guiUpdate running continuously.
--
-- Placed here, after dumpAvailableCommands()'s own definition
-- (not before it, where guiUpdate originally sat): Lua's
-- "local function" only becomes callable-by-name from the point of
-- its own declaration onward in the chunk. Defining this block
-- earlier meant runStartupDiagnosticsOnce() referenced
-- dumpAvailableCommands and guiUpdate referenced
-- runStartupDiagnosticsOnce before either existed as a local in
-- scope yet, which would have resolved to a nil global and crashed
-- the moment guiUpdate actually ran -- a second latent bug sitting
-- right behind the first one this same fix addresses.
-- ============================================================

local hasRunStartupDiagnostics =
    false

local function runStartupDiagnosticsOnce()

    if hasRunStartupDiagnostics then
        return
    end

    hasRunStartupDiagnostics =
        true

    -- A one-off, disposable Bug B check used to fire here --
    -- hardcoded to the 10 real vehicle IDs dispatcher.lua's first
    -- two live runs moved (Alexander Road -> The Grove, Decision 31).
    -- Answered and removed: vehicle 131092 was carrying real cargo
    -- (CONSTRUCTION_MATERIALS=5), a second independent clean-positive
    -- data point for Bug B alongside the dedicated Bug B test's own
    -- result (PROGRESS.md). Hardcoded to those specific vehicle IDs,
    -- so it can't be reused for a future Dispatcher run's different
    -- vehicles -- served its one-time purpose.

    dumpAvailableCommands()

    -- route_injector.runCreateLineTest() used to fire here every
    -- session -- a self-cleaning createLine/deleteLine proof-of-
    -- concept, useful while that command surface was unproven.
    -- createLine is now used for real in every Stage 1 split, so the
    -- once-per-boot self-test just added log volume for no ongoing
    -- purpose. Removed at the player's request when logs were
    -- getting too full each run -- still available to call manually
    -- (route_injector.M.runCreateLineTest) if ever needed again.

    -- The glyph naming question is settled (● and ↔ safe, ◆ ■ ►
    -- tofu -- TECHNICAL_RESEARCH.md) and baked into line_splitter.lua's
    -- naming convention, so there's no reason to keep recreating the
    -- comparison line every boot. Clean up whatever's left of it
    -- instead -- requested live once it had been sitting as clutter
    -- in every screenshot since the finding was made.
    if config.DEBUG then
        route_injector.cleanupLineNamingGlyphTest()
    end

    -- A "STATION GROUP TERMINAL DUMP" (stations.dumpStationGroupTerminals)
    -- used to fire here every session too -- answered "can we read a
    -- station's real terminal count/structure," which is long since
    -- resolved and in real use (Stage 4's terminal_allocator.lua,
    -- PROGRESS.md/Done/Foundation). Removed for the same reason as
    -- the two below -- still available to call manually
    -- (stations.dumpStationGroupTerminals(stationGroupId)) if needed.

    -- Two more one-time research dumps used to fire here every
    -- session: a "SAMPLE MANAGED-LINE VEHICLE" entity dump (answered
    -- "can we read a vehicle's onboard cargo/capacities at all" --
    -- yes, see cargoLoad/capacities/allCapacities, PROGRESS.md/Done/
    -- Foundation and Decision 27) and a "DESTINATION STATION_GROUP"
    -- dump per connected destination (answered "can we detect a
    -- pure drop-off station" -- yes, see the permanently-zero-rows
    -- panel logic, PROGRESS.md/Done/Panel-GUI). Both questions are
    -- fully resolved and documented; removed at the player's request
    -- when logs were getting too full each run. vehicles.dumpEntityInfo
    -- is still available to call manually against any entity ID if a
    -- full raw field dump is ever needed again.

end


-- ============================================================
-- SIMULATION EVENT TRIGGER TEST
--
-- `handleEvent` is a separate field on data()'s returned table from
-- `guiHandleEvent` -- confirmed real via shipped code
-- (res/scripts/mission/arrivaltracker.lua), never actually wired up
-- in this mod until now. Only reason to build this first: it's the
-- load-bearing assumption behind "Event-Driven Demand Reassessment"
-- (IDEAS.md) and the Planner (PROGRESS.md Not Started #3/#4) --
-- if OnToArriveAtDestination doesn't fire the way the shipped
-- reference code implies, that whole design needs rethinking before
-- any of it gets built.
--
-- Detail is logged only for the first few fires (enough to see a
-- real param/entity id and confirm the shape), then collapses to a
-- periodic count -- this event fires per cargo delivery GAME-WIDE,
-- not just at our hubs, so logging every one would be exactly the
-- kind of log spam already removed once this session.
-- ============================================================

local DELIVERY_EVENT_DETAIL_LOG_LIMIT = 5
local DELIVERY_EVENT_MILESTONE_INTERVAL = 100

-- ============================================================
-- AUTO DISPATCH TRIGGER (material-change threshold)
--
-- OnToArriveAtDestination is genuinely high-frequency and game-wide
-- (500-1300+ fires in a single session, Decision 28) -- calling
-- dispatcher.applyPlan on every single fire would be far too often
-- and would defeat the whole point of the cooldown guards (Decisions
-- 32/33): the plan needs real time to settle between runs, not a
-- reassessment on every delivery anywhere in the game.
--
-- Deliberately a simple GLOBAL delivery count, not scoped to the
-- selected hub's own deliveries specifically -- Decision 29 flagged
-- that whether a delivery event's targetEntity reliably identifies a
-- managed hub's own destinations is still unconfirmed, and this
-- shouldn't wait on that research. Using the already-proven raw fire
-- count as a rough "enough time/activity has passed" clock is an
-- honest, if crude, stand-in: every AUTO_DISPATCH_DELIVERY_THRESHOLD
-- deliveries anywhere, reassess the auto-managed hub. A material-
-- change threshold scoped to just this hub's own deliveries is a
-- real future refinement once targetEntity scoping is proven, not a
-- blocker for a first working version.
--
-- AUTO_DISPATCH_DELIVERY_THRESHOLD is a first guess, not tuned --
-- needs live observation of how often it actually fires relative to
-- real demand changes before trusting the number.
--
-- Reads settings.get("autoDispatchHubStationGroupId") rather than
-- distributionState.selectedStationGroupId -- live testing proved
-- handleEvent runs on a different script instance than guiUpdate
-- (Decision 35), so this function's own copy of distributionState
-- never sees what the panel has selected. File I/O is the one thing
-- already confirmed to cross that boundary reliably.
-- ============================================================

local AUTO_DISPATCH_DELIVERY_THRESHOLD = 50

local function attemptAutoDispatch()

    if not settings.get("autoRedistribute") then
        return
    end

    local hubStationGroupId =
        settings.get("autoDispatchHubStationGroupId")

    if hubStationGroupId == nil then
        return
    end

    logUi(
        "AUTO DISPATCH: material-change threshold reached ("
            .. tostring(AUTO_DISPATCH_DELIVERY_THRESHOLD)
            .. " deliveries) -- running Dispatcher on hub "
            .. tostring(hubStationGroupId)
            .. "."
    )

    local ok, err =
        pcall(
            dispatcher.applyPlan,
            hubStationGroupId,

            function(movesMade)

                logUi(
                    "AUTO DISPATCH: "
                        .. tostring(movesMade)
                        .. " vehicle(s) moved."
                )

            end
        )

    if not ok then

        logUi(
            "AUTO DISPATCH FAILED: "
                .. tostring(err)
        )

    end

end


local function handleDeliveryEvent(src, id, name, param)

    if id ~= "SimCargoSystem"
        or name ~= "OnToArriveAtDestination"
    then
        return
    end

    distributionState.deliveryEventCount =
        distributionState.deliveryEventCount + 1

    local count =
        distributionState.deliveryEventCount

    if count <= DELIVERY_EVENT_DETAIL_LOG_LIMIT then

        local okEntity, entity =
            pcall(game.interface.getEntity, param)

        local fieldsText = "<unreadable>"

        if okEntity and entity ~= nil then

            local okIter, iterErr =
                pcall(function()

                    local parts = {}

                    for key, value in pairs(entity) do
                        parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
                    end

                    fieldsText = "{ " .. table.concat(parts, ", ") .. " }"

                end)

            if not okIter then
                fieldsText = "<not enumerable: " .. tostring(iterErr) .. ">"
            end

        end

        logUi(
            "DELIVERY EVENT #" .. tostring(count)
                .. ": src=" .. tostring(src)
                .. " param=" .. tostring(param)
                .. " entity=" .. fieldsText
        )

    elseif count % DELIVERY_EVENT_MILESTONE_INTERVAL == 0 then

        logUi(
            "DELIVERY EVENT: " .. tostring(count) .. " total fires so far this session."
        )

    end

    if count % AUTO_DISPATCH_DELIVERY_THRESHOLD == 0 then
        attemptAutoDispatch()
    end

end


local function guiUpdate()

    runStartupDiagnosticsOnce()


    if distributionState.selectedEntityId == nil then
        return
    end


    ensureDistributionWindow()


    distributionState.guiUpdateCounter =
        distributionState.guiUpdateCounter + 1


    if distributionState.dirty
        or distributionState.guiUpdateCounter
            >= AUTO_REFRESH_GUI_UPDATES
    then

        updateDistributionWindow()

    end

end


-- ============================================================
-- GAME SCRIPT
-- ============================================================

function data()

    return {

        guiHandleEvent =
            function(
                id,
                name,
                param
            )

                if id == "mainView"
                    and name == "select"
                then

                    handleStationSelection(
                        param
                    )

                elseif id == "mainView"
                    and name == "deselect"
                then

                    handleStationSelection(
                        nil
                    )

                end

            end,

        guiUpdate =
            guiUpdate,

        handleEvent =
            handleDeliveryEvent

    }

end