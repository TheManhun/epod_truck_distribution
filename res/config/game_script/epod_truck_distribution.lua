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
--   * Re-Organize Terminals -- always visible, re-runs just the
--     terminal-spread step on demand (e.g. after the player builds
--     more physical terminals at an already-settled hub) without
--     re-walking Split's line detection.
--   * Assign & Balance Fleet -- DEBUG-gated, moves real vehicles.
--   * Auto Redistribute (toggle) / Rename Fleet to Hub Identity /
--     Show Fleet Plan / Apply Fleet Plan -- DEBUG-gated, real
--     Planner + Opportunistic Dispatcher features (Decisions 29-40).
--     Disposable one-off tests (loaded-vehicle journey, Bug B,
--     vehicle rename/colour, file I/O, persistence counter, cargo
--     compatibility) have all been removed once their questions were
--     answered -- their underlying functions remain callable
--     manually in route_injector.lua/vehicles.lua if ever needed.
--
-- Every managed line's identity is tracked in a persistent registry
-- (managed_registry.lua, Decision 26), not by parsing the line's
-- display name -- the "●" prefix is cosmetic only.
--
-- Names are display-only.
-- Behaviour is driven by entity IDs.
--
-- data() also wires a real handleEvent (SimCargoSystem /
-- OnToArriveAtDestination, Decision 28) -- the Planner + Opportunistic
-- Dispatcher's real trigger: every AUTO_DISPATCH_DELIVERY_THRESHOLD
-- deliveries, if the Auto Redistribute toggle is ON, a "dispatch due"
-- flag is set and the actual dispatcher.applyPlan call happens from
-- guiUpdate instead (Decision 39 -- never from inside handleEvent
-- itself, which deterministically fails). The manual "Apply Fleet
-- Plan" button still exists alongside this for testing -- the toggle
-- only gates automatic execution, never the Planner's own calculation.
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
local line_adopter = require("epod_td.line_adopter")
local hub_registry = require("epod_td.hub_registry")
local line_ownership = require("epod_td.line_ownership")
local source_line_registry = require("epod_td.source_line_registry")
local operation_lock = require("epod_td.operation_lock")
local gui_manager = require("epod_td.gui_manager")
local gui_experiment = require("epod_td.gui_experiment")
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
    610

-- Width of the label portion of a destination row -- the direction
-- arrow + station name ONLY as of the WAITING_LABEL_WIDTH split
-- below, no longer carrying the "| Waiting: N" suffix. Must match
-- what rows are created with in ensureDistributionWindow (setText's
-- width argument does not retroactively resize a widget created
-- narrower).
local ROW_LABEL_WIDTH =
    260

-- LIVE-CONFIRMED BUG, real screenshot: with the destination name and
-- "| Waiting: N" sharing one 300px label box, "Barrow-in-Furness
-- Transfer" (the longest real destination name in play) plus a
-- 2-digit waiting count ("Waiting: 10") wrapped ugly onto a second
-- line -- a 1-digit count ("Waiting: 4") on the exact same
-- destination fit fine, confirming it's a width/wrap issue, not a
-- data bug (see DECISIONS.md). Every other destination has a shorter
-- name with enough spare room that it never showed. Fix: give the
-- waiting count its own small fixed box, same pattern already used
-- for cargo counts, instead of concatenating it into text that has
-- to wrap around however long the name happens to be -- so no future
-- long station name can push a number into an awkward wrap again.
-- Pixel widths above/below are a first estimate extrapolated from
-- the observed wrap point (~6.4px/char in this font), not yet
-- independently live-confirmed at these exact values.
local WAITING_LABEL_WIDTH =
    90

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

-- Separate throttle for checking the auto-dispatch "pending" flag
-- (Decision 39) -- deliberately NOT tied to AUTO_REFRESH_GUI_UPDATES
-- above, since that counter only increments while a station is
-- selected (guiUpdate returns early otherwise), but auto-dispatch
-- must keep working even while the player is elsewhere on the map.
-- settings.get() now does real disk I/O per call (Decision 35), so
-- this must stay throttled, not checked every single frame.
local AUTO_DISPATCH_POLL_INTERVAL =
    120

local autoDispatchPollCounter =
    0

-- New-line adoption (PROGRESS.md Not Started #5 / IDEAS.md "Automatic
-- Network Change Detection") is topological, not event-driven -- it
-- only needs to notice a line that now touches the hub, not react
-- within seconds. Polled far less often than dispatch itself so the
-- getLines() walk inside detectAndAdopt doesn't add per-frame cost.
local AUTO_ADOPT_POLL_INTERVAL =
    600

local autoAdoptPollCounter =
    0

local isLineAdoptionRunning =
    false


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

    -- Requested live: too many DEBUG/test buttons cluttering the
    -- main panel. Rather than move them into the new gui_manager.lua
    -- framework (deliberately built read-only, no buttons -- see its
    -- own header comment), this just collapses the genuinely
    -- diagnostic/one-off buttons behind a toggle on the SAME proven
    -- panel. Auto Redistribute and Open New GUI stay always visible
    -- (real operational controls, not diagnostics) -- see the
    -- "SHOW/HIDE DEBUG TOOLS" section below for which buttons this
    -- actually gates. Session-only (not persisted): purely a display
    -- preference, not gameplay state worth a settings.lua entry.
    debugToolsVisible =
        false,

    -- Decision 66, live-confirmed real crash: a native engine
    -- assertion ("it != components.end()") fired against a line
    -- entity mid-deletion when a SECOND hub's Distribution Hub setup
    -- was started while an EARLIER hub's setup chain (Split -> Rename
    -- -> Assign & Balance, all long chains of async sendCommand
    -- round-trips) was still running and deleted a fully-degenerate
    -- source line at the same moment the second hub's own scan was
    -- iterating every managed line. Not something a pcall or a safer
    -- read can fully prevent -- a native assertion crashes the whole
    -- process regardless. Refusing to start a second hub setup while
    -- one is already running removes the race entirely rather than
    -- trying to defend against it after the fact.
    --
    -- Decision 71: this flag itself moved out to operation_lock.lua
    -- so gui_manager.lua's action buttons can share the exact same
    -- lock -- a private field on this file's own distributionState
    -- table couldn't be reached from a different module, and the new
    -- GUI window is deliberately a second, independent window that
    -- can be open and clicked at the same time as this one.

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
        0,

    -- One-off research question (see the LINE CYCLE-TIME RESEARCH
    -- dump in updateDistributionWindow): fires at most once per
    -- session. Remove alongside that dump once answered.
    hasRunLineEntityDump =
        false,

    -- One-off research question (see the TOWN FIELD RESEARCH dump in
    -- updateDistributionWindow): fires at most once per session.
    -- Remove alongside that dump once answered.
    hasRunTownFieldDump =
        false

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
-- WRITE REPORT TO FILE (fresh overwrite each time)
--
-- Requested live: the two DEBUG report buttons (Dump All Managed
-- Lines, Fleet Balance Report) were dumping their full content into
-- the same ever-growing shared game log every click, on top of
-- everything else the engine logs -- reading the latest one meant
-- scrolling through megabytes of unrelated noise each time. Same
-- proven io.open pattern as hub_registry.lua/settings.lua/etc.: a
-- plain "w" mode write replaces the whole file's content every call,
-- no append, no cache -- so each report file always holds only its
-- own most recent run.
-- ============================================================

local function writeReportFile(fileName, lines)

    local ok, err =
        pcall(function()

            local file = io.open(fileName, "w")

            if file == nil then
                return
            end

            file:write(table.concat(lines, "\n"))
            file:write("\n")

            file:close()

        end)

    if not ok then

        logUi(
            "WRITE REPORT FILE FAILED ("
                .. tostring(fileName)
                .. "): "
                .. tostring(err)
        )

    end

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
    sourceLineIds,
    onAllDone
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
                                .. " line(s) -- see log) ]",
                            WINDOW_WIDTH
                        )

                    end

                    if onAllDone ~= nil then
                        onAllDone()
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

            if onAllDone ~= nil then
                onAllDone()
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
            sourceLineIds,
            onAllDone
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
                sourceLineIds,
                onAllDone
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

    -- Decision 66's reentrancy guard originally only covered the
    -- one-click "Distribution Hub" setup sequence -- but this button
    -- runs the exact same splitAllManagedLines/line_splitter machinery
    -- that setup sequence chains, so it carries the identical overlap
    -- risk (one run deleting/rewriting a line entity another run is
    -- mid-scan against) if triggered concurrently with a hub setup, or
    -- with itself at another hub. Now shares the same flag.
    if operation_lock.isRunning() then

        logUi(
            "SPLIT: another hub operation is still running -- "
                .. "wait for it to finish before starting this one."
        )

        return

    end

    operation_lock.begin()


    local stationGroupId =
        distributionState.selectedStationGroupId


    local ok, managedLines =
        pcall(
            vehicles.getManagedLinesForStation,
            stationGroupId
        )

    if not ok or managedLines == nil then

        operation_lock.finish()

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
        1,
        nil,

        function()

            operation_lock.finish()

        end
    )

end


-- Raised live: a player adding MORE physical terminals to a hub
-- that's already fully split and settled has no way to make DD use
-- them -- spreadLinesAcrossTerminals only ever runs from Split (which
-- would needlessly re-walk every line's split logic just to force a
-- re-spread) or from a fresh line adoption. This calls the same
-- terminal step directly, on demand, for whatever's currently
-- selected -- same excludeList = {} already proven at the other call
-- site (processHubAdoptionNext) that has no "just split" line to
-- exclude. Always visible, not DEBUG-gated: same reasoning as folding
-- the original "Spread Lines Across Terminals" button into Split --
-- it never touches vehicle cargo, so it carries none of the Bug A/B
-- risk the DEBUG-only buttons below are gated for.
local function handleReorganizeTerminalsButtonClick()

    if distributionState.selectedStationGroupId == nil then

        logUi(
            "REORGANIZE TERMINALS: no station selected."
        )

        return

    end

    -- Same overlap risk as Split (see its own comment above) --
    -- spreadLinesAcrossTerminals reads every line at the hub, including
    -- ones a concurrent hub setup could be mid-deleting.
    if operation_lock.isRunning() then

        logUi(
            "REORGANIZE TERMINALS: another hub operation is still "
                .. "running -- wait for it to finish before starting "
                .. "this one."
        )

        return

    end

    operation_lock.begin()


    local stationGroupId =
        distributionState.selectedStationGroupId


    if distributionState.textViews ~= nil
        and distributionState.textViews.reorganizeTerminalsButtonLabel ~= nil
    then

        distributionState.textViews.reorganizeTerminalsButtonLabel:setText(
            "[ Reorganizing... (see log) ]",
            WINDOW_WIDTH
        )

    end


    local ok, err =
        pcall(
            terminal_allocator.spreadLinesAcrossTerminals,
            stationGroupId,
            {},

            function(processedCount)

                operation_lock.finish()

                if distributionState.textViews ~= nil
                    and distributionState.textViews.reorganizeTerminalsButtonLabel ~= nil
                then

                    distributionState.textViews.reorganizeTerminalsButtonLabel:setText(
                        "[ Re-Organize Terminals (done: "
                            .. tostring(processedCount)
                            .. " line(s) -- see log) ]",
                        WINDOW_WIDTH
                    )

                end

            end
        )

    if not ok then

        operation_lock.finish()

        logUi(
            "REORGANIZE TERMINALS FAILED: "
                .. tostring(err)
        )

        if distributionState.textViews ~= nil
            and distributionState.textViews.reorganizeTerminalsButtonLabel ~= nil
        then

            distributionState.textViews.reorganizeTerminalsButtonLabel:setText(
                "[ Re-Organize Terminals (crashed -- see log) ]",
                WINDOW_WIDTH
            )

        end

    end

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

-- Decision 53 fix: a hub can legitimately have split more than one
-- original combined line (live-confirmed real case: Yarm East had
-- BOTH "Line 6" and "Line 7" split in the same click, since Line 7
-- genuinely touches Yarm East too as part of its real inter-hub
-- route). source_line_registry now records a SET per hub, not a
-- single value, so every recorded source line gets its own full
-- assign+balance+delete pass here, one at a time -- not just
-- whichever one happened to be split last.
local function processSourceLineNext(sourceLineIds, index, hubStationGroupId, totals, setDoneLabel, onAllDone)

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

                            totals.redistributed =
                                totals.redistributed + redistributedCount

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

                                    source_line_registry.removeSourceLine(
                                        hubStationGroupId,
                                        sourceLineId
                                    )

                                elseif reason == "source-line-unreadable" then

                                    -- Decision 61: this ID doesn't
                                    -- correspond to a real line
                                    -- anymore at all -- unlike
                                    -- "still-has-vehicles"/
                                    -- "still-has-destinations"
                                    -- (a real line just not ready
                                    -- yet), there's nothing left to
                                    -- ever finish here. Forget it
                                    -- now rather than burning a
                                    -- full Stage 2/3 pass against
                                    -- it, uselessly, every future
                                    -- Assign & Balance click.
                                    source_line_registry.removeSourceLine(
                                        hubStationGroupId,
                                        sourceLineId
                                    )

                                    totals.kept[#totals.kept + 1] =
                                        tostring(sourceLineId)
                                            .. " (stale registry entry -- forgotten)"

                                else

                                    totals.kept[#totals.kept + 1] =
                                        tostring(sourceLineId)
                                            .. " (" .. tostring(reason) .. ")"

                                end

                                processSourceLineNext(
                                    sourceLineIds,
                                    index + 1,
                                    hubStationGroupId,
                                    totals,
                                    setDoneLabel,
                                    onAllDone
                                )

                            end

                            local ok3, err3 =
                                pcall(
                                    line_splitter.deleteEmptySourceLine,
                                    sourceLineId,
                                    hubStationGroupId,

                                    function(deleted, reason)

                                        -- Decision 65: "still-has-vehicles"
                                        -- specifically means 0 real
                                        -- destinations are left (the ONLY
                                        -- other refusal reason,
                                        -- "still-has-destinations", is a
                                        -- different situation and is not
                                        -- retried here) -- so any vehicle
                                        -- still on this line has nowhere
                                        -- left to legitimately go via the
                                        -- normal demand-weighted pass.
                                        -- Mop up any CONFIRMED-EMPTY
                                        -- leftovers once, then retry the
                                        -- delete, rather than leaving 1-3
                                        -- trucks stuck looping a dead line
                                        -- forever.
                                        if not deleted and reason == "still-has-vehicles" then

                                            local ok4, err4 =
                                                pcall(
                                                    fleet_allocator.forceDistributeRemainingSpares,
                                                    sourceLineId,
                                                    hubStationGroupId,

                                                    function(distributedCount)

                                                        totals.redistributed =
                                                            totals.redistributed + distributedCount

                                                        local ok5, err5 =
                                                            pcall(
                                                                line_splitter.deleteEmptySourceLine,
                                                                sourceLineId,
                                                                hubStationGroupId,
                                                                finishSourceLine
                                                            )

                                                        if not ok5 then

                                                            logUi(
                                                                "ASSIGN & BALANCE (retry delete step) FAILED for line "
                                                                    .. tostring(sourceLineId) .. ": "
                                                                    .. tostring(err5)
                                                            )

                                                            finishSourceLine(false, "retry-delete-crashed")

                                                        end

                                                    end
                                                )

                                            if not ok4 then

                                                logUi(
                                                    "ASSIGN & BALANCE (force-distribute step) FAILED for line "
                                                        .. tostring(sourceLineId) .. ": "
                                                        .. tostring(err4)
                                                )

                                                finishSourceLine(false, reason)

                                            end

                                            return

                                        end

                                        finishSourceLine(deleted, reason)

                                    end
                                )

                            if not ok3 then

                                -- Decision 66: must still call onAllDone
                                -- (not just log+setDoneLabel) -- otherwise
                                -- a synchronous crash here would leave the
                                -- caller's operation_lock guard stuck true
                                -- forever, permanently disabling hub setup
                                -- for the rest of the session.
                                -- Stops processing further source lines
                                -- for this hub, but still finishes the
                                -- overall sequence.
                                logUi(
                                    "ASSIGN & BALANCE (delete step) FAILED for line "
                                        .. tostring(sourceLineId) .. ": "
                                        .. tostring(err3)
                                )

                                setDoneLabel(
                                    "[ Assign & Balance Fleet (crashed -- see log) ]"
                                )

                                onAllDone()

                            end

                        end
                    )

                if not ok2 then

                    logUi(
                        "ASSIGN & BALANCE (balance step) FAILED for line "
                            .. tostring(sourceLineId) .. ": "
                            .. tostring(err2)
                    )

                    setDoneLabel(
                        "[ Assign & Balance Fleet (crashed -- see log) ]"
                    )

                    onAllDone()

                end

            end
        )

    if not ok then

        logUi(
            "ASSIGN & BALANCE (assign step) FAILED for line "
                .. tostring(sourceLineId) .. ": "
                .. tostring(err)
        )

        setDoneLabel(
            "[ Assign & Balance Fleet (crashed -- see log) ]"
        )

        onAllDone()

    end

end

local function handleAssignAndBalanceButtonClick()

    if distributionState.selectedStationGroupId == nil then

        logUi(
            "ASSIGN & BALANCE: no station selected."
        )

        return

    end

    -- Same overlap risk as Split/Reorganize Terminals (see their own
    -- comments above) -- this walks and mutates lines at the hub too.
    if operation_lock.isRunning() then

        logUi(
            "ASSIGN & BALANCE: another hub operation is still running -- "
                .. "wait for it to finish before starting this one."
        )

        return

    end

    operation_lock.begin()


    if distributionState.textViews ~= nil
        and distributionState.textViews.assignBalanceButtonLabel ~= nil
    then

        distributionState.textViews.assignBalanceButtonLabel:setText(
            "[ Working... (see log) ]",
            WINDOW_WIDTH
        )

    end


    local hubStationGroupId =
        distributionState.selectedStationGroupId

    -- Decision 46/53 fix: this used to look up config.SOURCE_LINE_NAME,
    -- a single hardcoded line name ("Truck - CD - Hendon") that only
    -- ever matched Hendon East's own original line, then a single
    -- per-hub record that a second split at the same hub could
    -- silently overwrite. Now reads every source line
    -- line_splitter.lua has ever recorded for this hub.
    local sourceLineIds =
        source_line_registry.getSourceLines(
            hubStationGroupId
        )

    if #sourceLineIds == 0 then

        operation_lock.finish()

        logUi(
            "ASSIGN & BALANCE: no recorded source line for this hub -- "
                .. "run \"Split Into Lines & Organize Terminals\" here "
                .. "first."
        )

        if distributionState.textViews ~= nil
            and distributionState.textViews.assignBalanceButtonLabel ~= nil
        then

            distributionState.textViews.assignBalanceButtonLabel:setText(
                "[ Assign & Balance Fleet (no source line -- see log) ]",
                WINDOW_WIDTH
            )

        end

        return

    end

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

    local totals = {
        assigned = 0,
        redistributed = 0,
        deleted = 0,
        kept = {}
    }

    processSourceLineNext(
        sourceLineIds,
        1,
        hubStationGroupId,
        totals,
        setDoneLabel,

        function()

            operation_lock.finish()

            local keptText =
                #totals.kept > 0
                    and (" | kept: " .. table.concat(totals.kept, ", "))
                    or ""

            setDoneLabel(
                "[ Assign & Balance Fleet (done: "
                    .. tostring(totals.assigned) .. " assigned, "
                    .. tostring(totals.redistributed) .. " balanced, "
                    .. tostring(totals.deleted) .. " source line(s) deleted"
                    .. keptText
                    .. " -- see log) ]"
            )

        end
    )

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
-- DUMP ALL MANAGED LINES (config.DEBUG only)
--
-- Requested live as a direct alternative to screenshots, which kept
-- failing to upload during multi-hub testing: a full, game-wide dump
-- of every managed line -- every stop, current vehicle count, and
-- (Decision 48) which single hub actually OWNS it versus every
-- enabled hub it merely happens to touch. Read-only, same as Show
-- Fleet Plan -- moves nothing, just reports what's really there so
-- the ownership fix (or anything else) can be checked straight from
-- the log instead of a picture.
-- ============================================================

local function handleDumpAllManagedLinesButtonClick()

    local output = {}

    output[#output + 1] = "========================================"
    output[#output + 1] = "DUMP ALL MANAGED LINES"
    output[#output + 1] = "========================================"

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then

        logUi("DUMP ALL MANAGED LINES: could not read the line list.")

        return

    end

    local enabledHubs = hub_registry.getEnabledHubs()
    local enabledHubNames = {}

    for _, hubId in ipairs(enabledHubs) do
        enabledHubNames[hubId] = getEntityName(hubId)
    end

    local dumpedCount = 0
    local totalVehicleCount = 0

    for _, lineId in ipairs(allLineIds) do

        if managed_registry.isManaged(lineId) then

            dumpedCount = dumpedCount + 1

            local lineName = lines.getName(lineId)
            local vehicleCount = #vehicles.getVehiclesForLine(lineId)

            totalVehicleCount = totalVehicleCount + vehicleCount
            local ownerHubId = line_ownership.getOwner(lineId)

            local ownerText = "unclaimed (no hub has run a plan against it yet)"

            if ownerHubId ~= nil then

                ownerText =
                    tostring(enabledHubNames[ownerHubId] or getEntityName(ownerHubId))
                        .. " (" .. tostring(ownerHubId) .. ")"

            end

            output[#output + 1] = "----------------------------------------"

            output[#output + 1] =
                "Line: " .. tostring(lineName)
                    .. " (id=" .. tostring(lineId) .. ")"

            output[#output + 1] = "  owner hub: " .. ownerText
            output[#output + 1] = "  vehicles: " .. tostring(vehicleCount)
            output[#output + 1] = "  stops:"

            local line = lines.get(lineId)
            local stops = line ~= nil and lines.safeField(line, "stops") or nil
            local stopCount = lines.safeLength(stops)

            local touchingHubs = {}

            for index = 1, stopCount do

                local stop = stops[index]

                if stop ~= nil then

                    local stationGroup = lines.safeField(stop, "stationGroup")
                    local stopName = stations.getEntityName(stationGroup)

                    output[#output + 1] =
                        "    [" .. tostring(index - 1) .. "] "
                            .. tostring(stopName)
                            .. " (stationGroup=" .. tostring(stationGroup) .. ")"

                    if stationGroup ~= nil and enabledHubNames[stationGroup] ~= nil then

                        touchingHubs[#touchingHubs + 1] =
                            tostring(enabledHubNames[stationGroup])
                                .. " (" .. tostring(stationGroup) .. ")"

                    end

                end

            end

            if #touchingHubs > 0 then
                output[#output + 1] =
                    "  touches enabled hub(s): " .. table.concat(touchingHubs, ", ")
            end

        end

    end

    output[#output + 1] = "----------------------------------------"

    output[#output + 1] =
        "DUMP ALL MANAGED LINES COMPLETE: "
            .. tostring(dumpedCount) .. " managed line(s), "
            .. tostring(totalVehicleCount) .. " total vehicle(s)."

    output[#output + 1] = "========================================"

    writeReportFile("epod_td_dump_managed_lines.txt", output)

    logUi(
        "DUMP ALL MANAGED LINES: wrote "
            .. tostring(dumpedCount) .. " managed line(s), "
            .. tostring(totalVehicleCount) .. " total vehicle(s) to "
            .. "epod_td_dump_managed_lines.txt (in the game install folder)."
    )

end


-- ============================================================
-- FLEET BALANCE REPORT (config.DEBUG only)
--
-- Requested live: "Dump All Managed Lines" already shows vehicle
-- count per line but not waiting cargo, so spotting an imbalance --
-- like a manually-forced 39-vehicle line sitting at 0 waiting right
-- next to an 8-vehicle sibling backlogged at 126 -- meant eyeballing
-- two separate screens. This is a compact, one-row-per-line report
-- instead of the full stop-by-stop detail dump: name, owner hub,
-- vehicle count, waiting total. Sorted highest-waiting-first so the
-- worst backlogs surface immediately, with a plain-language flag on
-- any line carrying vehicles but 0 waiting -- the same "sitting on
-- idle capacity" signature spotted live. Read-only, moves nothing,
-- same as Dump All Managed Lines and Show Fleet Plan.
-- ============================================================

-- Sums current cargo load and per-vehicle capacity across every
-- vehicle on a line -- requested live to fill a real gap in the
-- report: "waiting" only counts cargo still sitting at the stop, not
-- cargo already picked up and in transit, so a line could look worse
-- than it really is. Capacity uses the MAX single value found in
-- each vehicle's allCapacities (matching the single number TF2's own
-- UI shows per vehicle, e.g. "Cargo: 0/77") rather than summing
-- every compatible cargo type together, which would overstate a
-- vehicle that can carry several types but never all at once. One
-- pcall per vehicle so a single bad read can't lose the whole line's
-- total, same discipline as every other native-data loop in this
-- mod.
local function sumLineCargo(vehicleIds)

    local totalCarrying = 0
    local totalCapacity = 0

    for _, vehicleId in ipairs(vehicleIds) do

        pcall(function()

            local cargoLoad = vehicles.getCargoLoad(vehicleId)

            if cargoLoad ~= nil then

                for _, amount in pairs(cargoLoad) do
                    totalCarrying = totalCarrying + (amount or 0)
                end

            end

            local allCapacities = vehicles.getAllCapacities(vehicleId)

            if allCapacities ~= nil then

                local vehicleCapacity = 0

                for _, amount in pairs(allCapacities) do

                    if (amount or 0) > vehicleCapacity then
                        vehicleCapacity = amount
                    end

                end

                totalCapacity = totalCapacity + vehicleCapacity

            end

        end)

    end

    return totalCarrying, totalCapacity

end


local function handleFleetBalanceReportButtonClick()

    local output = {}

    output[#output + 1] = "========================================"
    output[#output + 1] = "FLEET BALANCE REPORT"
    output[#output + 1] = "========================================"

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then

        logUi("FLEET BALANCE REPORT: could not read the line list.")

        return

    end

    local rows = {}

    for _, lineId in ipairs(allLineIds) do

        if managed_registry.isManaged(lineId) then

            local ownerHubId = line_ownership.getOwner(lineId)

            local vehicleIds = vehicles.getVehiclesForLine(lineId)
            local vehicleCount = #vehicleIds

            local waiting = 0

            if ownerHubId ~= nil then

                local okScan, scanResult =
                    pcall(demand.scan, lineId, ownerHubId)

                if okScan and scanResult ~= nil then
                    waiting = scanResult.totalWaiting or 0
                end

            end

            local carrying, capacity = sumLineCargo(vehicleIds)

            rows[#rows + 1] = {
                name = lines.getName(lineId),
                ownerHubId = ownerHubId,
                vehicleCount = vehicleCount,
                waiting = waiting,
                carrying = carrying,
                capacity = capacity
            }

        end

    end

    table.sort(rows, function(a, b)
        return a.waiting > b.waiting
    end)

    local totalVehicles = 0
    local totalWaiting = 0
    local totalCarrying = 0
    local totalCapacity = 0

    for _, row in ipairs(rows) do

        totalVehicles = totalVehicles + row.vehicleCount
        totalWaiting = totalWaiting + row.waiting
        totalCarrying = totalCarrying + row.carrying
        totalCapacity = totalCapacity + row.capacity

        local ownerText =
            row.ownerHubId ~= nil
                and getEntityName(row.ownerHubId)
                or "unclaimed"

        local flag = ""

        if row.vehicleCount > 0 and row.waiting == 0 then
            flag = "  <-- idle capacity (0 waiting)"
        end

        local utilizationPercent =
            row.capacity > 0
                and math.floor((row.carrying / row.capacity) * 100)
                or 0

        output[#output + 1] =
            tostring(row.name)
                .. "  |  owner=" .. tostring(ownerText)
                .. "  |  vehicles=" .. tostring(row.vehicleCount)
                .. "  |  waiting=" .. tostring(row.waiting)
                .. "  |  in-transit=" .. tostring(row.carrying)
                    .. "/" .. tostring(row.capacity)
                    .. " (" .. tostring(utilizationPercent) .. "%)"
                .. flag

    end

    output[#output + 1] = "----------------------------------------"

    local totalUtilizationPercent =
        totalCapacity > 0
            and math.floor((totalCarrying / totalCapacity) * 100)
            or 0

    output[#output + 1] =
        "FLEET BALANCE REPORT COMPLETE: "
            .. tostring(#rows) .. " line(s), "
            .. tostring(totalVehicles) .. " total vehicle(s), "
            .. tostring(totalWaiting) .. " total waiting, "
            .. tostring(totalCarrying) .. "/" .. tostring(totalCapacity)
            .. " in-transit (" .. tostring(totalUtilizationPercent) .. "% fleet utilization)."

    output[#output + 1] = "========================================"

    writeReportFile("epod_td_fleet_balance_report.txt", output)

    logUi(
        "FLEET BALANCE REPORT: wrote "
            .. tostring(#rows) .. " line(s), "
            .. tostring(totalVehicles) .. " total vehicle(s), "
            .. tostring(totalWaiting) .. " total waiting, "
            .. tostring(totalCarrying) .. "/" .. tostring(totalCapacity)
            .. " in-transit (" .. tostring(totalUtilizationPercent) .. "%) to "
            .. "epod_td_fleet_balance_report.txt (in the game install folder)."
    )

end


-- ============================================================
-- CARGO BALANCE INSPECTOR (config.DEBUG only, Decision 77)
--
-- Requested live: the mod is destination-aware (Fleet Balance Report
-- shows total waiting per line) but not production-recipe-aware -- a
-- destination needing two inputs (e.g. a steel mill needing both
-- IRON_ORE and COAL) just shows as one combined waiting total today,
-- so a truck line can fill up almost entirely with whichever cargo
-- type happens to be more abundant while the other genuinely starves.
-- Read-only, Stage 1 of a two-stage plan: this just reports the real
-- per-cargo-type imbalance so a control mechanism (Stage 2) can be
-- chosen from real evidence rather than guessed.
--
-- Deliberately does NOT claim to know a destination's actual required
-- input ratio -- no API for that has been confirmed, and this project
-- has already been burned once (the terminal-allocator stock-take
-- bug, Decision 22) by treating an aggregate observation as more
-- meaningful than it was. "Comparatively under-served" here is purely
-- relative to the busiest cargo type AT THE SAME destination -- a
-- real, honest signal, not a claim about the true recipe.
--
-- Deliberately does NOT touch alternativeTerminals/cargo-filter
-- territory -- that's the exact undocumented Line.Stop sub-field area
-- that crashed the game twice (Decisions 56/57). This stays read-only
-- on purpose until real evidence justifies the next, riskier step.
-- ============================================================

local function handleCargoBalanceInspectorButtonClick()

    local output = {}

    output[#output + 1] = "========================================"
    output[#output + 1] = "CARGO BALANCE INSPECTOR (read-only)"
    output[#output + 1] = "========================================"
    output[#output + 1] = "Compares CURRENT waiting cargo (by type) against ALL-TIME"
    output[#output + 1] = "unloaded history (by type) at every managed destination with"
    output[#output + 1] = "more than one real cargo type. Flags whichever type looks"
    output[#output + 1] = "comparatively under-served relative to the busiest type at"
    output[#output + 1] = "THAT destination -- this is a relative signal, not a claim"
    output[#output + 1] = "about the destination's actual required input ratio (no API"
    output[#output + 1] = "for that has been confirmed)."
    output[#output + 1] = "----------------------------------------"

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then

        logUi("CARGO BALANCE INSPECTOR: could not read the line list.")

        return

    end

    local reportedDestinations = {}
    local flaggedCount = 0

    for _, lineId in ipairs(allLineIds) do

        if managed_registry.isManaged(lineId) then

            local ownerHubId = line_ownership.getOwner(lineId)

            if ownerHubId ~= nil then

                local okScan, scanResult = pcall(demand.scan, lineId, ownerHubId)

                if okScan and scanResult ~= nil and scanResult.destinations ~= nil then

                    for _, destination in pairs(scanResult.destinations) do

                        if destination.stationGroup ~= ownerHubId
                            and not reportedDestinations[destination.stationGroup]
                        then

                            -- Decision 78: demand.scan's cargoTypes is keyed
                            -- by the raw numeric SIM_CARGO type id;
                            -- stations.getUnloadedAmountsByType is keyed by
                            -- the uppercase string constant (e.g.
                            -- "IRON_ORE"). Confirmed live these are
                            -- genuinely different key spaces for the same
                            -- real cargo type -- normalize the waiting side
                            -- onto the string-constant key (via
                            -- demand.getCargoTypeId) before merging, or
                            -- "Iron ore" and "CargoType IRON_ORE" show up as
                            -- two separate, wrong rows for one real thing.
                            local waitingByType = {}
                            local displayNameByKey = {}

                            for cargoType, amount in pairs(destination.cargoTypes or {}) do

                                local normalizedKey =
                                    demand.getCargoTypeId(cargoType)
                                        or ("unresolved:" .. tostring(cargoType))

                                waitingByType[normalizedKey] =
                                    (waitingByType[normalizedKey] or 0) + amount

                                displayNameByKey[normalizedKey] =
                                    demand.getCargoTypeDisplayName(cargoType)

                            end

                            local okUnloaded, unloadedByType =
                                pcall(stations.getUnloadedAmountsByType, destination.stationGroup)

                            if not okUnloaded then
                                unloadedByType = {}
                            end

                            -- Only interesting if this destination genuinely
                            -- involves 2+ distinct cargo types -- combines
                            -- current waiting AND all-time history so a type
                            -- with 0 waiting right now but a real delivery
                            -- history still counts.
                            local allTypes = {}

                            for cargoType, _ in pairs(waitingByType) do
                                allTypes[cargoType] = true
                            end

                            for cargoType, _ in pairs(unloadedByType) do
                                allTypes[cargoType] = true
                            end

                            local typeCount = 0

                            for _ in pairs(allTypes) do
                                typeCount = typeCount + 1
                            end

                            if typeCount >= 2 then

                                reportedDestinations[destination.stationGroup] = true

                                output[#output + 1] =
                                    tostring(destination.name)
                                        .. "  (served via "
                                        .. tostring(getEntityName(ownerHubId))
                                        .. ")"

                                local rows = {}

                                for cargoType, _ in pairs(allTypes) do

                                    -- displayNameByKey only has an entry when
                                    -- this cargo type was seen on the waiting
                                    -- side (the only side that can resolve a
                                    -- real name via cargoTypeRep -- see
                                    -- Decision 78). A type seen ONLY in
                                    -- all-time unloaded history has no
                                    -- resolvable name; fall back to a plain
                                    -- prettified version of the raw constant
                                    -- ("IRON_ORE" -> "Iron Ore") rather than
                                    -- the confusing "CargoType IRON_ORE".
                                    local displayName = displayNameByKey[cargoType]

                                    if displayName == nil then

                                        displayName =
                                            tostring(cargoType)
                                                :gsub("_", " ")
                                                :gsub("(%a)([%w']*)", function(first, rest)
                                                    return first:upper() .. rest:lower()
                                                end)

                                    end

                                    rows[#rows + 1] = {
                                        displayName = displayName,
                                        waiting = waitingByType[cargoType] or 0,
                                        unloaded = unloadedByType[cargoType] or 0
                                    }

                                end

                                table.sort(rows, function(a, b)
                                    return a.waiting > b.waiting
                                end)

                                local maxWaiting = 0

                                for _, row in ipairs(rows) do

                                    if row.waiting > maxWaiting then
                                        maxWaiting = row.waiting
                                    end

                                end

                                for _, row in ipairs(rows) do

                                    local flag = ""

                                    if maxWaiting > 0
                                        and row.waiting <= maxWaiting * 0.25
                                    then

                                        flag = "  <-- comparatively under-served"
                                        flaggedCount = flaggedCount + 1

                                    end

                                    output[#output + 1] =
                                        "  " .. tostring(row.displayName)
                                            .. "  |  waiting=" .. tostring(row.waiting)
                                            .. "  |  unloaded (all-time)=" .. tostring(row.unloaded)
                                            .. flag

                                end

                                output[#output + 1] = "----------------------------------------"

                            end

                        end

                    end

                end

            end

        end

    end

    local destinationCount = 0

    for _ in pairs(reportedDestinations) do
        destinationCount = destinationCount + 1
    end

    output[#output + 1] =
        "CARGO BALANCE INSPECTOR COMPLETE: "
            .. tostring(destinationCount) .. " multi-cargo destination(s), "
            .. tostring(flaggedCount) .. " comparatively-under-served flag(s)."

    output[#output + 1] = "========================================"

    writeReportFile("epod_td_cargo_balance_report.txt", output)

    logUi(
        "CARGO BALANCE INSPECTOR: wrote "
            .. tostring(destinationCount)
            .. " multi-cargo destination(s), "
            .. tostring(flaggedCount)
            .. " flag(s) to epod_td_cargo_balance_report.txt "
            .. "(in the game install folder)."
    )

end


-- ============================================================
-- DEDUPE SHARED ROUTE LINES (config.DEBUG only)
--
-- Decision 59: a line touching two enabled hubs at once could get
-- split independently from both hubs' perspectives before the
-- line_ownership check in line_splitter.splitLineIntoDestinations
-- existed (or from a save that already has the leftover duplicates
-- from before this fix), leaving two separate managed lines
-- connecting the exact same two stations. Runs
-- line_splitter.dedupeSharedRouteLines network-wide -- only ever
-- deletes a duplicate with 0 vehicles, same safety discipline as
-- every other delete in this codebase.
-- ============================================================
local function handleDedupeSharedRouteLinesButtonClick()

    if distributionState.textViews ~= nil
        and distributionState.textViews.dedupeSharedRouteLinesButtonLabel ~= nil
    then

        distributionState.textViews.dedupeSharedRouteLinesButtonLabel:setText(
            "[ Deduping... (see log) ]",
            WINDOW_WIDTH
        )

    end

    local ok, err =
        pcall(
            line_splitter.dedupeSharedRouteLines,

            function(deletedCount)

                if distributionState.textViews ~= nil
                    and distributionState.textViews.dedupeSharedRouteLinesButtonLabel ~= nil
                then

                    distributionState.textViews.dedupeSharedRouteLinesButtonLabel:setText(
                        "[ Dedupe Shared Route Lines (done: "
                            .. tostring(deletedCount)
                            .. " deleted -- see log) ]",
                        WINDOW_WIDTH
                    )

                end

                logUi(
                    "DEDUPE SHARED ROUTE LINES: deleted "
                        .. tostring(deletedCount)
                        .. " duplicate line(s)."
                )

            end
        )

    if not ok then

        logUi(
            "DEDUPE SHARED ROUTE LINES FAILED: "
                .. tostring(err)
        )

        if distributionState.textViews ~= nil
            and distributionState.textViews.dedupeSharedRouteLinesButtonLabel ~= nil
        then

            distributionState.textViews.dedupeSharedRouteLinesButtonLabel:setText(
                "[ Dedupe Shared Route Lines (crashed -- see log) ]",
                WINDOW_WIDTH
            )

        end

    end

end


-- ============================================================
-- OPEN NEW GUI (config.DEBUG only, TEMPORARY)
--
-- Toggles the new gui_manager.lua "DD Central Manager" framework
-- window -- see documents/GUI_Plan.md. Deliberately a separate,
-- additive window: this button and gui_manager.lua are the ONLY
-- things that know it exists. Nothing about the existing "Truck
-- Distribution" window/logic changes. Remove this button once the
-- new GUI is far enough along to replace the old panel outright, not
-- before.
-- ============================================================

local function handleOpenNewGuiButtonClick()

    local ok, err =
        pcall(
            gui_manager.toggleVisibility,
            distributionState.selectedStationGroupId
        )

    if not ok then

        logUi(
            "OPEN NEW GUI FAILED: " .. tostring(err)
        )

    end

end


-- Decision 75/76: completely separate raw-api.gui.comp.* experiment,
-- deliberately never touching gui_manager.lua's gui.lua-based tree
-- (see gui_experiment.lua's own header for why mixing the two systems
-- is the exact thing that crashed the game in Decision 73).
local function handleOpenRawUiExperimentButtonClick()

    local ok, err =
        pcall(gui_experiment.toggleVisibility)

    if not ok then

        logUi(
            "OPEN RAW UI EXPERIMENT FAILED: " .. tostring(err)
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
-- MULTI-HUB (Decision 44): this used to persist ONE globally-captured
-- hub ID (settings.lua's autoDispatchHubStationGroupId), rebound to
-- whatever station happened to be selected the moment the toggle was
-- clicked ON -- meaning turning it on while looking at a second hub
-- silently dropped the first hub's automation with no warning. Now
-- backed by hub_registry.lua's actual set of enabled hub IDs: this
-- button always acts on whichever hub is CURRENTLY SELECTED only,
-- toggling that one hub's membership in the set without touching any
-- other hub already enabled. The label is refreshed both here and in
-- updateDistributionWindow() (on every panel refresh, keyed by
-- whichever station is selected at the time) so switching between two
-- hubs shows each one's own real state rather than a stale value left
-- over from whichever hub was last clicked.
--
-- Still relies on the Decision 35 file-I/O-crosses-instances fix:
-- attemptAutoDispatch/pollAutoDispatchPending run from a different
-- script instance than the GUI click handler, so hub_registry.lua
-- reads fresh from disk every call, same as every other registry in
-- this mod.
-- ============================================================

local function autoRedistributeLabelText(hubStationGroupId)

    if hubStationGroupId == nil then
        return "[ Distribution Hub: select a hub first ]"
    end

    if hub_registry.isEnabled(hubStationGroupId) then
        return "[ Distribution Hub: ON for this hub ]"
    end

    return "[ Distribution Hub: OFF for this hub ]"

end


-- ============================================================
-- NEW HUB SETUP SEQUENCE (Decision 62)
--
-- Player's idea: turning a hub's Distribution Hub toggle ON for the
-- very first time shouldn't require then separately remembering to
-- click Split, Rename Fleet, and Assign & Balance in the right order
-- -- just chain the three existing, already-proven steps together.
-- No new logic: this calls the exact same module functions those
-- three buttons already call, just threaded through real callbacks
-- instead of each one updating its own separate button label.
--
-- Deliberately NOT a background/polling feature (raised live: not
-- everyone runs this mod on a bare vanilla setup, keep it minimal) --
-- this runs once, synchronously-chained, on the single moment the
-- player clicks ON, then reports a plain final status and stops.
-- Anything it can't finish immediately (e.g. a vehicle still
-- mid-delivery, same as Decision 61's loaded-vehicle safety check)
-- is just named in that final status -- the player can click Assign
-- & Balance again later if they want to chase it, exactly as before
-- this feature existed.
-- ============================================================

local function runNewHubSetupSequence(hubStationGroupId, onAllDone)

    local ok, managedLines =
        pcall(
            vehicles.getManagedLinesForStation,
            hubStationGroupId
        )

    if not ok or managedLines == nil then

        logUi(
            "DISTRIBUTION HUB SETUP FAILED: could not read managed lines: "
                .. tostring(managedLines)
        )

        if onAllDone ~= nil then
            onAllDone()
        end

        return

    end

    splitAllManagedLines(
        hubStationGroupId,
        managedLines,
        1,
        nil,

        function()

            local okRename, errRename =
                pcall(
                    fleet_naming.renameFleetToHubIdentity,
                    hubStationGroupId,

                    function(renamedCount)

                        logUi(
                            "DISTRIBUTION HUB SETUP: renamed "
                                .. tostring(renamedCount)
                                .. " vehicle(s)."
                        )

                        local sourceLineIds =
                            source_line_registry.getSourceLines(hubStationGroupId)

                        if #sourceLineIds == 0 then

                            logUi(
                                "DISTRIBUTION HUB SETUP COMPLETE for hub "
                                    .. tostring(hubStationGroupId)
                                    .. " (nothing needed splitting)."
                            )

                            if onAllDone ~= nil then
                                onAllDone()
                            end

                            return

                        end

                        local totals = {
                            assigned = 0,
                            redistributed = 0,
                            deleted = 0,
                            kept = {}
                        }

                        processSourceLineNext(
                            sourceLineIds,
                            1,
                            hubStationGroupId,
                            totals,
                            function() end,

                            function()

                                local keptText =
                                    #totals.kept > 0
                                        and (" -- still settling: " .. table.concat(totals.kept, ", "))
                                        or ""

                                logUi(
                                    "DISTRIBUTION HUB SETUP COMPLETE: "
                                        .. tostring(totals.assigned) .. " assigned, "
                                        .. tostring(totals.redistributed) .. " balanced, "
                                        .. tostring(totals.deleted) .. " source line(s) cleaned up"
                                        .. keptText
                                        .. "."
                                )

                                if onAllDone ~= nil then
                                    onAllDone()
                                end

                            end
                        )

                    end
                )

            if not okRename then

                logUi(
                    "DISTRIBUTION HUB SETUP (rename step) FAILED: "
                        .. tostring(errRename)
                )

                if onAllDone ~= nil then
                    onAllDone()
                end

            end

        end
    )

end


local function handleAutoRedistributeToggleButtonClick()

    local hubStationGroupId =
        distributionState.selectedStationGroupId

    if hubStationGroupId == nil then

        logUi(
            "DISTRIBUTION HUB: no hub is currently selected -- "
                .. "select one first."
        )

        return

    end

    if hub_registry.isEnabled(hubStationGroupId) then

        hub_registry.disable(hubStationGroupId)

        logUi(
            "DISTRIBUTION HUB: turned OFF for hub "
                .. tostring(hubStationGroupId)
        )

        -- Decision 64: strip the "● " prefix back off the station
        -- name, mirroring the ON branch below. Only touches it if the
        -- prefix is actually there, so this is safe to run even on a
        -- hub whose name was never changed by this mod.
        do

            local currentName =
                stations.getRawEntityName(hubStationGroupId)

            if currentName ~= nil
                and currentName:sub(1, 4) == "● "
            then

                pcall(
                    stations.setEntityName,
                    hubStationGroupId,
                    currentName:sub(5)
                )

            end

        end

        -- Decision 60: clean up empty lines this hub claimed while it
        -- was enabled -- otherwise they just sit there forever as
        -- orphaned clutter (exactly what happened with Thatcham
        -- Sidings). Only ever deletes lines with 0 vehicles.
        pcall(
            line_splitter.deleteEmptyOwnedLines,
            hubStationGroupId,

            function(deletedCount)

                if deletedCount > 0 then

                    logUi(
                        "DISTRIBUTION HUB: cleaned up "
                            .. tostring(deletedCount)
                            .. " empty line(s) this hub left behind."
                    )

                end

            end
        )

        if distributionState.textViews ~= nil
            and distributionState.textViews.autoRedistributeButtonLabel ~= nil
        then

            distributionState.textViews.autoRedistributeButtonLabel:setText(
                autoRedistributeLabelText(hubStationGroupId),
                WINDOW_WIDTH
            )

        end

        return

    end

    -- Decision 66: refuse to start a second hub's setup while an
    -- earlier one is still running -- live-confirmed real crash
    -- (native engine assertion) when two setup chains overlapped and
    -- one deleted a line entity the other was mid-scan against.
    if operation_lock.isRunning() then

        logUi(
            "DISTRIBUTION HUB: another hub's setup is still running -- "
                .. "wait for it to finish before starting this one."
        )

        return

    end

    operation_lock.begin()

    -- Decision 62: turning ON now also runs the full first-time setup
    -- sequence (Split -> Rename Fleet -> Assign & Balance) rather than
    -- just flipping the flag and leaving the player to click each of
    -- those three separately.
    hub_registry.enable(hubStationGroupId)

    -- Decision 64: mark the station itself as a converted hub, same
    -- "● " convention already used for managed lines -- requested
    -- live so a converted hub is visible at a glance (station list,
    -- map) without opening this panel. setName is documented
    -- entity-agnostic and already proven on vehicles/lines elsewhere
    -- in this codebase; this is the first use on a station. Only
    -- renames if not already prefixed, so re-enabling an
    -- already-renamed hub doesn't double up the bullet.
    do

        local currentName =
            stations.getRawEntityName(hubStationGroupId)

        if currentName ~= nil
            and currentName:sub(1, 4) ~= "● "
        then

            pcall(
                stations.setEntityName,
                hubStationGroupId,
                "● " .. currentName
            )

        end

    end

    logUi(
        "DISTRIBUTION HUB: turned ON for hub "
            .. tostring(hubStationGroupId)
            .. " -- setting it up now."
    )

    if distributionState.textViews ~= nil
        and distributionState.textViews.autoRedistributeButtonLabel ~= nil
    then

        distributionState.textViews.autoRedistributeButtonLabel:setText(
            "[ Setting up Distribution Hub... (see log) ]",
            WINDOW_WIDTH
        )

    end

    local ok, err =
        pcall(
            runNewHubSetupSequence,
            hubStationGroupId,

            function()

                operation_lock.finish()

                if distributionState.textViews ~= nil
                    and distributionState.textViews.autoRedistributeButtonLabel ~= nil
                then

                    distributionState.textViews.autoRedistributeButtonLabel:setText(
                        autoRedistributeLabelText(hubStationGroupId),
                        WINDOW_WIDTH
                    )

                end

            end
        )

    if not ok then

        operation_lock.finish()

        logUi(
            "DISTRIBUTION HUB SETUP FAILED: "
                .. tostring(err)
        )

        if distributionState.textViews ~= nil
            and distributionState.textViews.autoRedistributeButtonLabel ~= nil
        then

            distributionState.textViews.autoRedistributeButtonLabel:setText(
                "[ Distribution Hub (setup crashed -- see log) ]",
                WINDOW_WIDTH
            )

        end

    end

end


-- ============================================================
-- SHOW/HIDE DEBUG TOOLS (config.DEBUG only)
--
-- Requested live: gates the genuinely diagnostic/one-off buttons
-- (Assign & Balance Fleet, Rename Fleet, Show Fleet Plan, Dump All
-- Managed Lines, Fleet Balance Report, Dedupe Shared Route Lines,
-- Apply Fleet Plan) behind a toggle so the main panel stays short by
-- default. Auto Redistribute and Open New GUI are deliberately left
-- OUTSIDE this gate -- real operational controls the player reaches
-- for regularly, not diagnostics.
--
-- No native "hide this one widget" API has ever been proven in this
-- codebase (the only proven visibility control is the whole native
-- window's own close(), used below), so this works the same way the
-- station-deselect handler already does: close the native window
-- entirely and let it rebuild fresh next tick, this time with (or
-- without) the gated buttons included. windowClosedByUser must be
-- reset straight after -- close() fires the same window:onClose()
-- callback either way, and leaving that flag set would make
-- ensureDistributionWindow() refuse to rebuild at all until the
-- player reselects a station.
-- ============================================================
local function handleToggleDebugToolsButtonClick()

    distributionState.debugToolsVisible =
        not distributionState.debugToolsVisible

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
                "Failed closing window for debug-tools toggle: "
                    .. tostring(closeErr)
            )

        end

    end

    distributionState.windowClosedByUser =
        false

    distributionState.dirty =
        true

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


    distributionState.textViews.reorganizeTerminalsButtonLabel =
        gui.textView_create(
            WINDOW_ID .. ".reorganizeTerminalsButtonLabel",
            "[ Re-Organize Terminals ]",
            WINDOW_WIDTH,
            false
        )

    local reorganizeTerminalsButton =
        gui.button_create(
            WINDOW_ID .. ".reorganizeTerminalsButton",
            distributionState.textViews.reorganizeTerminalsButtonLabel
        )

    reorganizeTerminalsButton:onClick(
        handleReorganizeTerminalsButtonClick
    )

    distributionState.reorganizeTerminalsButton =
        reorganizeTerminalsButton


    local fixedViews = {

        distributionState.textViews.summary,
        splitButton,
        reorganizeTerminalsButton

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

        distributionState.textViews.toggleDebugToolsButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".toggleDebugToolsButtonLabel",
                distributionState.debugToolsVisible
                    and "[ Hide Debug Tools ]"
                    or "[ Show Debug Tools ]",
                WINDOW_WIDTH,
                false
            )

        local toggleDebugToolsButton =
            gui.button_create(
                WINDOW_ID .. ".toggleDebugToolsButton",
                distributionState.textViews.toggleDebugToolsButtonLabel
            )

        toggleDebugToolsButton:onClick(
            handleToggleDebugToolsButtonClick
        )

        distributionState.toggleDebugToolsButton =
            toggleDebugToolsButton

        fixedViews[#fixedViews + 1] =
            toggleDebugToolsButton


        if distributionState.debugToolsVisible then

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

        end


        -- Test Bug B / Park-Stop button removed here -- its question
        -- (does a bare setLine reassignment fail to pick up cargo at
        -- the new destination) is answered by now via hundreds of
        -- real, organic Dispatcher reassignments across live sessions
        -- with zero sign of the bug, far stronger evidence than the
        -- original dedicated single-run test. route_injector.
        -- runBugBTestStep remains callable manually if ever needed.

        -- Auto Redistribute stays always visible (outside the debug-
        -- tools gate above) -- a real operational per-hub toggle, not
        -- a diagnostic.

        -- Initial label reflects whatever was actually persisted
        -- (settings.lua), not a hardcoded "OFF" -- the toggle should
        -- show its real state immediately on window creation,
        -- including after a save/reload.
        distributionState.textViews.autoRedistributeButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".autoRedistributeButtonLabel",
                autoRedistributeLabelText(distributionState.selectedStationGroupId),
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


        -- Test Vehicle Rename/Colour button removed here -- its
        -- question (does setName/setColor work on a vehicle entity)
        -- is long since answered and superseded by the real "Rename
        -- Fleet to Hub Identity" feature below. route_injector.
        -- testVehicleRenameAndColor remains callable manually if
        -- ever needed.

        if distributionState.debugToolsVisible then

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


        distributionState.textViews.dumpAllManagedLinesButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".dumpAllManagedLinesButtonLabel",
                "[ Dump All Managed Lines (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local dumpAllManagedLinesButton =
            gui.button_create(
                WINDOW_ID .. ".dumpAllManagedLinesButton",
                distributionState.textViews.dumpAllManagedLinesButtonLabel
            )

        dumpAllManagedLinesButton:onClick(
            handleDumpAllManagedLinesButtonClick
        )

        distributionState.dumpAllManagedLinesButton =
            dumpAllManagedLinesButton

        fixedViews[#fixedViews + 1] =
            dumpAllManagedLinesButton


        distributionState.textViews.fleetBalanceReportButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".fleetBalanceReportButtonLabel",
                "[ Fleet Balance Report (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local fleetBalanceReportButton =
            gui.button_create(
                WINDOW_ID .. ".fleetBalanceReportButton",
                distributionState.textViews.fleetBalanceReportButtonLabel
            )

        fleetBalanceReportButton:onClick(
            handleFleetBalanceReportButtonClick
        )

        distributionState.fleetBalanceReportButton =
            fleetBalanceReportButton

        fixedViews[#fixedViews + 1] =
            fleetBalanceReportButton


        distributionState.textViews.cargoBalanceInspectorButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".cargoBalanceInspectorButtonLabel",
                "[ Cargo Balance Inspector (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local cargoBalanceInspectorButton =
            gui.button_create(
                WINDOW_ID .. ".cargoBalanceInspectorButton",
                distributionState.textViews.cargoBalanceInspectorButtonLabel
            )

        cargoBalanceInspectorButton:onClick(
            handleCargoBalanceInspectorButtonClick
        )

        distributionState.cargoBalanceInspectorButton =
            cargoBalanceInspectorButton

        fixedViews[#fixedViews + 1] =
            cargoBalanceInspectorButton


        distributionState.textViews.dedupeSharedRouteLinesButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".dedupeSharedRouteLinesButtonLabel",
                "[ Dedupe Shared Route Lines (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local dedupeSharedRouteLinesButton =
            gui.button_create(
                WINDOW_ID .. ".dedupeSharedRouteLinesButton",
                distributionState.textViews.dedupeSharedRouteLinesButtonLabel
            )

        dedupeSharedRouteLinesButton:onClick(
            handleDedupeSharedRouteLinesButtonClick
        )

        distributionState.dedupeSharedRouteLinesButton =
            dedupeSharedRouteLinesButton

        fixedViews[#fixedViews + 1] =
            dedupeSharedRouteLinesButton

        end


        -- Open New GUI stays always visible (outside the debug-tools
        -- gate above) -- per the player's own explicit request.
        distributionState.textViews.openNewGuiButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".openNewGuiButtonLabel",
                "[ Open New GUI (TEST) ]",
                WINDOW_WIDTH,
                false
            )

        local openNewGuiButton =
            gui.button_create(
                WINDOW_ID .. ".openNewGuiButton",
                distributionState.textViews.openNewGuiButtonLabel
            )

        openNewGuiButton:onClick(
            handleOpenNewGuiButtonClick
        )

        distributionState.openNewGuiButton =
            openNewGuiButton

        fixedViews[#fixedViews + 1] =
            openNewGuiButton


        -- Decision 75/76: same always-visible treatment as Open New
        -- GUI above -- a real operational experiment, not a
        -- diagnostic. Built entirely on the raw api.gui.comp.* system
        -- (see gui_experiment.lua); this button itself is a normal
        -- gui.lua button like every other on this panel, since it
        -- only ever calls a plain Lua function (toggleVisibility) --
        -- no GUI object crosses between the two systems here.
        local rawUiExperimentButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".rawUiExperimentButtonLabel",
                "[ Open Raw UI Experiment (TEST) ]",
                WINDOW_WIDTH,
                false
            )

        local rawUiExperimentButton =
            gui.button_create(
                WINDOW_ID .. ".rawUiExperimentButton",
                rawUiExperimentButtonLabel
            )

        rawUiExperimentButton:onClick(
            handleOpenRawUiExperimentButtonClick
        )

        fixedViews[#fixedViews + 1] =
            rawUiExperimentButton


        if distributionState.debugToolsVisible then

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


        -- Destination rows only (line header rows leave this blank
        -- -- see clearRow/renderManagedLineRows). Its own fixed box
        -- so a long destination name in labelView can never push
        -- this number into a wrap the way concatenating them into
        -- one string used to.
        local waitingView =
            gui.textView_create(
                rowPrefix .. ".waiting",
                "",
                WAITING_LABEL_WIDTH,
                false
            )

        rowLayout:addItem(
            waitingView
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

            waitingLabel =
                waitingView,

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

    row.waitingLabel:setText(
        "",
        WAITING_LABEL_WIDTH
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


    -- MULTI-HUB (Decision 44): re-evaluate for whichever hub is
    -- selected right now, every refresh -- otherwise switching from
    -- an enabled hub to a disabled one (or vice versa) would leave
    -- the button showing the PREVIOUS hub's state until the next
    -- click, since this label is only otherwise touched at window
    -- creation and inside the click handler itself.
    if distributionState.textViews ~= nil
        and distributionState.textViews.autoRedistributeButtonLabel ~= nil
    then

        distributionState.textViews.autoRedistributeButtonLabel:setText(
            autoRedistributeLabelText(stationGroupId),
            WINDOW_WIDTH
        )

    end


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


        -- ONE-OFF, DISPOSABLE: research question raised live -- does
        -- a LINE entity already expose a round-trip/cycle-time
        -- statistic (TF2's own LINE STATISTICS panel shows
        -- frequency-like numbers, so this seems plausible), which
        -- would let the Planner factor travel distance into how many
        -- vehicles a line actually needs without us tracking
        -- anything ourselves. Reuses vehicles.dumpEntityInfo
        -- (already proven generic -- entity-agnostic, works on any
        -- entity type, not just vehicles) against every line
        -- currently shown in the panel. Fires once per session, on
        -- the first refresh with real lines to dump. Remove once
        -- answered.
        if config.DEBUG
            and not distributionState.hasRunLineEntityDump
            and #managedLines > 0
        then

            distributionState.hasRunLineEntityDump =
                true

            for _, lineInfo in ipairs(managedLines) do

                vehicles.dumpEntityInfo(
                    lineInfo.id,
                    "LINE CYCLE-TIME RESEARCH: " .. tostring(lineInfo.name)
                )

            end

        end


        -- ONE-OFF, DISPOSABLE: research question raised live -- does
        -- a STATION entity expose which town/district it belongs to?
        -- If so, a duplicate-named destination (real case tonight:
        -- two different physical "Park Lane" stations) could be
        -- disambiguated with something player-readable ("Park Lane,
        -- Oldham") instead of line_splitter.lua's current fallback
        -- (the raw stationGroup entity ID appended in parentheses).
        -- Dumps every real destination stationGroup currently shown
        -- in the panel via vehicles.dumpEntityInfo (already proven
        -- entity-agnostic). Fires once per session. Remove once
        -- answered.
        if config.DEBUG
            and not distributionState.hasRunTownFieldDump
            and #managedLines > 0
        then

            distributionState.hasRunTownFieldDump =
                true

            local dumpedStationGroups = {}

            for _, lineInfo in ipairs(managedLines) do

                for _, destinationInfo in ipairs(lineInfo.destinations or {}) do

                    local destinationStationGroupId = destinationInfo.stationGroup

                    if destinationStationGroupId ~= nil
                        and not dumpedStationGroups[destinationStationGroupId]
                    then

                        dumpedStationGroups[destinationStationGroupId] = true

                        vehicles.dumpEntityInfo(
                            destinationStationGroupId,
                            "TOWN FIELD RESEARCH: " .. tostring(destinationInfo.name)
                        )

                    end

                end

            end

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
                        ),

                        ROW_LABEL_WIDTH

                    )


                    destRow.waitingLabel:setText(
                        labelText,
                        WAITING_LABEL_WIDTH
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

-- Shared by both a real deselect and by selecting something that
-- isn't a station (a vehicle, a line, anything else) -- in both
-- cases the panel has nothing to show and should behave exactly like
-- a deselect, not linger open with stale/irrelevant content.
local function closeDistributionWindowAndClearSelection()

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

end


local function handleStationSelection(value)

    if value == nil then

        closeDistributionWindowAndClearSelection()

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


    local stationGroupId =
        resolveStationGroup(
            entityId
        )

    -- Requested live: selecting a vehicle (or a line, or anything
    -- else that isn't a real station/station group) was popping this
    -- panel open too, since everything past this point used to run
    -- unconditionally for any resolvable entity. resolveStationGroup
    -- already correctly returns nil for a vehicle -- a
    -- TRANSPORT_VEHICLE has neither a STATION nor STATION_GROUP
    -- component -- so a nil result here means the player selected
    -- something this panel has nothing to say about. Treat it exactly
    -- like a deselect rather than opening/refreshing the window for
    -- irrelevant content.
    if stationGroupId == nil then

        closeDistributionWindowAndClearSelection()

        return

    end


    distributionState.selectedEntity =
        entity

    distributionState.selectedEntityId =
        entityId

    distributionState.selectedStationGroupId =
        stationGroupId

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
-- AUTO_DISPATCH_DELIVERY_THRESHOLD -- RAISED FROM 50 AFTER A REAL
-- LIVE INCIDENT (Decision 36): 50 was far too low relative to real
-- observed delivery rates -- during a delivery burst (the player had
-- deliberately stacked up extra deliveries to stress-test), this
-- could trigger a full Planner+Dispatcher cycle multiple times per
-- second, and the resulting pile of real, synchronous vehicle-move
-- commands made the game unresponsive with audio stutter badly
-- enough to require a force-close. dispatcher.lua now also has a
-- hard reentrancy guard (Decision 36) so overlapping runs can never
-- pile up regardless of this number -- but the number itself still
-- matters for not feeling frantic even when it's technically safe.
-- 500 is a safer starting point, still a first guess -- needs live
-- observation of real firing frequency before trusting it further.
--
-- RAISED AGAIN, 500 -> 5000 (Decision 40): once Decision 39 made
-- automatic dispatch actually succeed instead of fast-failing, the
-- player reported a small, regular pause roughly every second with
-- Auto Redistribute on. This save's delivery rate turned out to be
-- extreme (17,800+ logged in one session) -- at 500, the threshold
-- was being crossed every few seconds, so real dispatch cycles (real
-- vehicle-move commands, not the near-free failure path from before)
-- were firing far more often than intended. Still an untuned first
-- guess at the new value, not a measured "correct" number -- the
-- underlying fix (Decision 29's cargo-profile floor already exists;
-- a REAL per-hub delivery count, not a global one, is the eventual
-- right answer once Decision 29's targetEntity scoping is resolved)
-- is still the right long-term direction, this is a stopgap.
--
-- Reads hub_registry.getEnabledHubs() rather than
-- distributionState.selectedStationGroupId -- live testing proved
-- handleEvent runs on a different script instance than guiUpdate
-- (Decision 35), so this function's own copy of distributionState
-- never sees what the panel has selected. File I/O is the one thing
-- already confirmed to cross that boundary reliably.
--
-- MULTI-HUB (Decision 44): this only ever checks whether AT LEAST ONE
-- hub is enabled -- the trigger itself is still a single game-wide
-- delivery count (see above), not scoped per hub, so there's exactly
-- one "pending" flag for the whole mod. pollAutoDispatchPending below
-- is what actually walks every enabled hub once the flag fires.
--
-- DOES NOT CALL dispatcher.applyPlan DIRECTLY (Decision 39, after a
-- conclusively-diagnosed live incident): a controlled comparison
-- showed 10/10 manual "Apply Fleet Plan" clicks succeeding and
-- ~45/45 automatic triggers failing, every single time -- not bad
-- luck, deterministic. handleEvent fires from INSIDE the engine's
-- own delivery-processing callback; issuing a real
-- api.cmd.make.*/sendCommand command synchronously from there hits
-- TF2's engine while it's still "between changes" from the delivery
-- that triggered the callback (the exact ecs::Engine::BeginModification
-- assertion from Decisions 37/38). A manual button click happens from
-- ordinary player input, never from inside that callback, so it
-- never hits this. This function now only sets a persisted "a
-- dispatch is due" flag; the real dispatcher.applyPlan call happens
-- from guiUpdate instead (see below) -- an ordinary per-frame poll,
-- the same call context the manual button already uses successfully.
-- Bonus: every real applyPlan call now runs in the SAME script
-- instance (the GUI one), so dispatcher.lua's cooldowns and
-- reentrancy guard -- previously silently split across separate
-- per-instance copies -- now actually apply consistently across
-- manual and automatic triggers alike.
-- ============================================================

local AUTO_DISPATCH_DELIVERY_THRESHOLD = 5000

local function attemptAutoDispatch()

    if #hub_registry.getEnabledHubs() == 0 then
        return
    end

    logUi(
        "AUTO DISPATCH: material-change threshold reached ("
            .. tostring(AUTO_DISPATCH_DELIVERY_THRESHOLD)
            .. " deliveries) -- flagging a dispatch as due "
            .. "(actual run deferred to the next frame update)."
    )

    settings.set("autoDispatchPending", true)

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


-- Runs the actually-deferred Dispatcher call (Decision 39) from an
-- ordinary per-frame poll -- never from inside handleEvent, which is
-- what caused every automatic attempt to fail (see attemptAutoDispatch's
-- comment above). Throttled independently of station selection.
--
-- MULTI-HUB (Decision 44): walks every enabled hub SEQUENTIALLY, one
-- at a time, only starting the next hub's applyPlan once the previous
-- one's callback has actually fired -- deliberately not firing all
-- enabled hubs' applyPlan calls at once. dispatcher.lua's reentrancy
-- guard is now per-hub, so two disjoint hubs running concurrently
-- would likely be fine (they never touch the same vehicle or line),
-- but nothing has live-confirmed that overlapping command chains
-- across hubs are actually safe at the engine level -- Decisions 37
-- and 38's incidents came from exactly this class of "should be fine"
-- assumption. Sequential processing here costs nothing (this whole
-- poll already only runs once every AUTO_DISPATCH_POLL_INTERVAL
-- frames) and matches the same one-at-a-time async chain pattern used
-- everywhere else in this mod (line_splitter.processNext,
-- fleet_naming.processRenameNext, line_adopter.processAdoptNext,
-- terminal_allocator.processCandidateNext).
local function processHubDispatchNext(hubIds, index)

    local hubStationGroupId = hubIds[index]

    if hubStationGroupId == nil then
        return
    end

    logUi(
        "AUTO DISPATCH: running deferred Dispatcher on hub "
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
                        .. " vehicle(s) moved for hub "
                        .. tostring(hubStationGroupId)
                        .. "."
                )

                processHubDispatchNext(hubIds, index + 1)

            end
        )

    if not ok then

        logUi(
            "AUTO DISPATCH FAILED for hub "
                .. tostring(hubStationGroupId)
                .. ": "
                .. tostring(err)
        )

        processHubDispatchNext(hubIds, index + 1)

    end

end

local function pollAutoDispatchPending()

    autoDispatchPollCounter = autoDispatchPollCounter + 1

    if autoDispatchPollCounter < AUTO_DISPATCH_POLL_INTERVAL then
        return
    end

    autoDispatchPollCounter = 0

    if not settings.get("autoDispatchPending") then
        return
    end

    settings.set("autoDispatchPending", false)

    local enabledHubs = hub_registry.getEnabledHubs()

    if #enabledHubs == 0 then
        return
    end

    processHubDispatchNext(enabledHubs, 1)

end


-- Runs line_adopter.detectAndAdopt from an ordinary per-frame poll,
-- same call context as pollAutoDispatchPending above and for the same
-- reason (Decision 39): setName/register issue real commands, so this
-- must never run from inside handleEvent. Gated on hub_registry's
-- enabled-hub set, same as auto-dispatch -- adoption without a hub to
-- adopt INTO would be meaningless, and a hub the player never enabled
-- should see no automatic renaming at all. Reentrancy-guarded the
-- same way dispatcher.applyPlan is: the
-- adoption chain in line_adopter.lua is itself asynchronous
-- (setName -> sendCommand -> register, one candidate at a time), so a
-- second poll firing mid-chain would double up exactly like the
-- Decision 36 incident this is modeled after avoiding.
--
-- MULTI-HUB (Decision 44): walks every enabled hub sequentially, same
-- one-at-a-time reasoning as processHubDispatchNext above. A single
-- isLineAdoptionRunning flag still correctly guards the WHOLE
-- multi-hub sequence (not per-hub) because hubs are only ever
-- processed one after another here -- the flag just means "a poll
-- cycle is still working through its hub list", which remains true
-- until every enabled hub has been checked.
--
-- ALSO RE-APPLIES THE SHARED TERMINAL POOL (Decision 46): adoption
-- alone used to leave a newly-adopted line's terminal wherever it
-- already was -- only a manual "Split Into Lines & Organize
-- Terminals" click ever called terminal_allocator.
-- spreadLinesAcrossTerminals. Requested live: a hands-off hub should
-- organize a new line's terminal the same way it dispatches vehicles
-- to it, with no separate manual step. Only runs when adoptedCount >
-- 0 -- spreadLinesAcrossTerminals re-writes EVERY managed line's
-- alternativeTerminals every time it's called, so gating it behind
-- "something actually changed" avoids re-sending identical commands
-- to every line on every poll cycle for no reason.
local function processHubAdoptionNext(hubIds, index)

    local hubStationGroupId = hubIds[index]

    if hubStationGroupId == nil then
        isLineAdoptionRunning = false
        return
    end

    local ok, err =
        pcall(
            line_adopter.detectAndAdopt,
            hubStationGroupId,

            function(adoptedCount)

                if adoptedCount == 0 then
                    processHubAdoptionNext(hubIds, index + 1)
                    return
                end

                logUi(
                    "AUTO ADOPT: " .. tostring(adoptedCount)
                        .. " new line(s) adopted into management "
                        .. "for hub " .. tostring(hubStationGroupId)
                        .. "."
                )

                distributionState.dirty = true

                local okTerminals, errTerminals =
                    pcall(
                        terminal_allocator.spreadLinesAcrossTerminals,
                        hubStationGroupId,
                        {},

                        function(processedCount)

                            logUi(
                                "AUTO ADOPT: shared terminal pool "
                                    .. "re-applied to "
                                    .. tostring(processedCount)
                                    .. " line(s) for hub "
                                    .. tostring(hubStationGroupId)
                                    .. "."
                            )

                            processHubAdoptionNext(hubIds, index + 1)

                        end
                    )

                if not okTerminals then

                    logUi(
                        "AUTO ADOPT: terminal pool re-apply FAILED "
                            .. "for hub " .. tostring(hubStationGroupId)
                            .. ": " .. tostring(errTerminals)
                    )

                    processHubAdoptionNext(hubIds, index + 1)

                end

            end
        )

    if not ok then

        logUi(
            "AUTO ADOPT FAILED for hub " .. tostring(hubStationGroupId)
                .. ": " .. tostring(err)
        )

        processHubAdoptionNext(hubIds, index + 1)

    end

end

local function pollNewLineAdoption()

    autoAdoptPollCounter = autoAdoptPollCounter + 1

    if autoAdoptPollCounter < AUTO_ADOPT_POLL_INTERVAL then
        return
    end

    autoAdoptPollCounter = 0

    if isLineAdoptionRunning then
        return
    end

    local enabledHubs = hub_registry.getEnabledHubs()

    if #enabledHubs == 0 then
        return
    end

    isLineAdoptionRunning = true

    processHubAdoptionNext(enabledHubs, 1)

end


local function guiUpdate()

    runStartupDiagnosticsOnce()

    pollAutoDispatchPending()
    pollNewLineAdoption()

    -- New GUI framework (gui_manager.lua) is a separate window, not
    -- gated on station selection the way the existing panel is --
    -- refreshed here regardless, before the early return below, so it
    -- keeps working even with nothing selected (its Overview tab
    -- handles hubStationGroupId == nil gracefully).
    pcall(gui_manager.refresh, distributionState.selectedStationGroupId)


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