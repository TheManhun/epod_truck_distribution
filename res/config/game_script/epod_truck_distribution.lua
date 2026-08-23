-- ============================================================
-- TF2 Truck Distribution
-- epod_truck_distribution.lua
--
-- READ-ONLY DISTRIBUTION MONITOR
--
-- Responsibilities:
--   * follow the currently selected station/stationGroup
--   * discover managed truck lines using that station
--   * count assigned trucks
--   * read waiting cargo by destination
--   * display the information in the Truck Distribution window
--
-- DOES NOT:
--   * alter the real "Truck - CD - Hendon" or "Grain" lines
--   * assign vehicles
--   * dispatch vehicles
--   * modify cargo
--
-- EXCEPTION, config.DEBUG only: fires route_injector.
-- runCreateLineTest() once at script load -- a self-contained,
-- self-cleaning proof-of-concept for api.cmd.make.createLine that
-- creates one throwaway 2-stop test line, verifies it, deletes it,
-- and verifies the deletion, all logged. See route_injector.lua
-- for why this exists and what it deliberately does not touch.
--
-- Names are display-only.
-- Behaviour is driven by entity IDs.
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
        0

}


-- ============================================================
-- PERSISTENCE PROOF OF CONCEPT (save/load hooks)
--
-- Nothing in this codebase has ever persisted any state across a
-- save/reload -- flagged as a foundational gap in PROGRESS.md/
-- Outstanding Unknowns, blocking almost everything past it (a
-- network fingerprint, remembering which hub is "managed", any of
-- the autonomous-brain ideas in IDEAS.md).
--
-- The mechanism found: `save`/`load` fields on the same table
-- data() already returns alongside guiHandleEvent/guiUpdate.
-- Confirmed live in two independent shipped base-game scripts:
-- res/scripts/guidesystem.lua and res/scripts/mission/
-- arrivaltracker.lua.
--
-- Full history of what was tried, live-tested, and why each attempt
-- failed is in DECISIONS.md Decision 24 -- summarized here:
--   v1: crashed the game. load() mutated state every call; TF2's
--       engine calls load() more than once per session as its own
--       internal consistency check and hard-crashes if two save()
--       snapshots taken close together disagree (CGame::StartGameSim,
--       Game.cpp:330).
--   v2-v3: stopped the crash (load()/save() made fully passive), but
--       the counting mechanism itself (guiUpdate-driven, "once per
--       process") was never the right trigger -- save()/load() fire
--       continuously throughout ordinary gameplay for reasons
--       unrelated to the player actually saving/loading.
--   v4: moved mutation to a deliberate DEBUG button, fully decoupled
--       from load()/save()'s own cadence -- but still didn't survive
--       a real save/quit/relaunch/load cycle.
--   v5-v6: two different "adopt incoming state only once" guards,
--       each reasoned through carefully, each disproven live by
--       checking the actual on-disk .sav.lua file directly (not just
--       the log) -- the guard kept latching on stale/pre-button data.
--   v7: gated on the player's action instead of guessing load()'s
--       timing -- still failed the same way when checked against
--       the .sav.lua file.
--   FINDING #7, LIVE-CONFIRMED (this is the one that actually
--       explains it): added a per-instance fingerprint to every
--       save()/load()/button-click log line. Proved THREE separate
--       module instances existed within one session, and the
--       button's mutation landed on a DIFFERENT instance than the
--       one whose save() was actually being used for real
--       serialization -- two disconnected Lua closures, entirely
--       unreachable from each other. No guard logic inside load()/
--       save() can fix this; a `local` cannot be shared across
--       separate executions of the same chunk. The engine appears to
--       re-execute this script's top-level code more than once per
--       session (matches the early boot log's repeated "Mods
--       changed, recreating data..." messages) and, evidently, keeps
--       GUI bindings (guiUpdate/button clicks) pointed at a later
--       instantiation than the one its save/load registration used.
--
-- v8 (current, working design): persistedState now lives in a
-- uniquely-namespaced Lua GLOBAL instead of a module-level `local`.
-- Globals live in the single shared _G table for the whole Lua VM,
-- so even if this chunk's top-level code gets re-executed multiple
-- times, every instantiation reads/writes the SAME underlying data
-- -- there is no more "which instance" question. save()/load() are
-- still fully passive (Decision 24's crash constraint is untouched
-- by WHERE the data lives, only by whether load()/save() compute
-- anything, which they still never do).
local PERSISTED_STATE_GLOBAL_KEY = "__EPOD_TD_PERSISTED_STATE__"

-- The mutation guard must ALSO live in _G, not as a module-level
-- `local`, for the exact same reason persistedState does: since
-- Finding #7 proved multiple separate instances of this chunk can
-- be alive at once, a per-instance guard would only protect the ONE
-- instance whose button actually got clicked. A DIFFERENT instance
-- -- whose own guard was never flipped, since it never received the
-- click -- would still freely let its own load() calls overwrite the
-- now-shared global state out from under the click's instance.
local HAS_MUTATED_PERSISTED_STATE_GLOBAL_KEY = "__EPOD_TD_HAS_MUTATED_PERSISTED_STATE__"

if _G[PERSISTED_STATE_GLOBAL_KEY] == nil then
    _G[PERSISTED_STATE_GLOBAL_KEY] = {
        loadCount = 0
    }
end

local function getPersistedState()
    return _G[PERSISTED_STATE_GLOBAL_KEY]
end

local function savePersistedState()
    return getPersistedState()
end

local function loadPersistedState(state, reset)

    if _G[HAS_MUTATED_PERSISTED_STATE_GLOBAL_KEY] then
        return
    end

    if state == nil
        or type(state) ~= "table"
        or next(state) == nil
        or reset
    then
        return
    end

    _G[PERSISTED_STATE_GLOBAL_KEY] = state

end

local function bumpPersistenceTestCounter()

    _G[HAS_MUTATED_PERSISTED_STATE_GLOBAL_KEY] = true

    local persistedState = getPersistedState()

    persistedState.loadCount =
        (persistedState.loadCount or 0) + 1

    print(
        "[EPOD-TD] PERSISTENCE TEST: counter bumped to "
            .. tostring(persistedState.loadCount)
            .. ". Save the game, fully quit and relaunch TF2, then "
            .. "load that save and check this counter's value in the "
            .. "log -- if it's still "
            .. tostring(persistedState.loadCount)
            .. " (not reset to 0), save/load is genuinely round-tripping."
    )

end


-- ============================================================
-- FILE I/O PROOF OF CONCEPT (alternative persistence path)
--
-- v8's shared-global fix (above) STILL failed live -- loadCount
-- stayed 0 on disk even though save()/load()/persistedState were
-- moved into _G, which should have made every script instance read
-- and write the exact same data. That points to something even more
-- fundamental than instance-sharing within one Lua state: TF2's mod
-- sandbox may give each script instantiation a genuinely ISOLATED
-- Lua environment, where not even _G is actually shared -- in which
-- case NO in-Lua storage mechanism (local or global) could ever
-- bridge across instances, and the engine's own save/load hooks
-- would be the only thing capable of crossing that boundary (which
-- is presumably why they exist as engine-level hooks in the first
-- place, rather than something a mod could reimplement in pure Lua).
--
-- This tests a completely different, orthogonal approach: real file
-- I/O via Lua's io library, writing our own file directly rather
-- than going through the engine's save/load hooks at all. Wrapped in
-- pcall throughout since it's unknown whether io is even exposed to
-- game_script mods -- no shipped base-game script under
-- res/config/game_script/ was found using it (grepped), which is a
-- hint, not proof, that it may be sandboxed out entirely.
-- ============================================================

-- LIVE-CONFIRMED: io.open works in this sandbox. First test wrote
-- successfully and read the content back within the same session,
-- landing at the TF2 install directory root (not ideal for a real
-- feature long-term -- Steam can touch that folder on verify/update,
-- and it isn't scoped per-savegame -- but fine for proving the
-- mechanism itself). This version turns it into a counter, exactly
-- like the save/load proof-of-concept, so a single quit/relaunch
-- cycle can directly test whether a value survives a real process
-- restart: read whatever's currently on disk (if anything), bump it,
-- write it back. If a fresh process reads back a HIGHER number than
-- the previous process wrote, this crosses process boundaries
-- cleanly -- unlike save()/load(), completely independent of
-- whatever multi-instantiation behavior broke Decision 24.
local FILE_IO_TEST_PATH = "epod_td_file_io_test.txt"

local function testFileIo()

    local previousCount = 0

    local readOk, readResult = pcall(function()

        local file = io.open(FILE_IO_TEST_PATH, "r")

        if file == nil then
            return nil
        end

        local content = file:read("*a")
        file:close()

        return tonumber(content)

    end)

    if readOk and readResult ~= nil then
        previousCount = readResult
    end

    local newCount = previousCount + 1

    local writeOk, writeErr = pcall(function()

        local file, openErr = io.open(FILE_IO_TEST_PATH, "w")

        if file == nil then
            error("io.open (write mode) failed: " .. tostring(openErr))
        end

        file:write(tostring(newCount))
        file:close()

    end)

    if not writeOk then

        print(
            "[EPOD-TD] FILE IO TEST: WRITE FAILED -- "
                .. tostring(writeErr)
        )

        return

    end

    print(
        "[EPOD-TD] FILE IO TEST: read "
            .. tostring(previousCount)
            .. " from disk, wrote "
            .. tostring(newCount)
            .. " back. Save the game, fully quit and relaunch TF2 (or "
            .. "even just click this again in a moment), then click "
            .. "this button again -- if the number keeps climbing "
            .. "across a real process restart, file I/O genuinely "
            .. "persists independent of the engine's save/load hooks."
    )

end


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
    index
)

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


        local ok, err =
            pcall(
                terminal_allocator.spreadLinesAcrossTerminals,
                stationGroupId,

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
            index + 1
        )

        return

    end


    line_splitter.splitLineIntoDestinations(
        stationGroupId,
        lineInfo,

        function(createdCount, totalCount)

            splitAllManagedLines(
                stationGroupId,
                managedLines,
                index + 1
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
-- LOADED VEHICLE JOURNEY TEST (config.DEBUG only)
--
-- Two clicks: first picks a real, currently-loaded, single-vehicle
-- managed line and reassigns that vehicle exactly the way Stage 2
-- does; second (click again after a few real minutes of play)
-- reports on that same vehicle. Answers the two open Partial safety
-- items in PROGRESS.md -- loaded-cargo survival through actual
-- delivery, and whether Decision 12's Truck Park bug is actually
-- triggered by Stage 2's bare setLine -- from one real observation
-- instead of an inconclusive aggregate. See
-- route_injector.M.runLoadedVehicleJourneyTestStep for the full
-- protocol.
-- ============================================================

local function handleJourneyTestButtonClick()

    if distributionState.textViews ~= nil
        and distributionState.textViews.journeyTestButtonLabel ~= nil
    then

        distributionState.textViews.journeyTestButtonLabel:setText(
            "[ Working... (see log) ]",
            WINDOW_WIDTH
        )

    end


    local ok, err =
        pcall(
            route_injector.runLoadedVehicleJourneyTestStep,

            function(success, reason)

                if distributionState.textViews ~= nil
                    and distributionState.textViews.journeyTestButtonLabel ~= nil
                then

                    local label =
                        "[ Test Loaded Vehicle Journey ("
                            .. tostring(reason)
                            .. " -- see log) ]"

                    if reason == "watching" then

                        label =
                            "[ Test Loaded Vehicle Journey "
                                .. "(watching -- click again later) ]"

                    end

                    distributionState.textViews.journeyTestButtonLabel:setText(
                        label,
                        WINDOW_WIDTH
                    )

                end

            end
        )

    if not ok then

        logUi(
            "JOURNEY TEST FAILED: "
                .. tostring(err)
        )

        if distributionState.textViews ~= nil
            and distributionState.textViews.journeyTestButtonLabel ~= nil
        then

            distributionState.textViews.journeyTestButtonLabel:setText(
                "[ Test Loaded Vehicle Journey (crashed -- see log) ]",
                WINDOW_WIDTH
            )

        end

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
-- BUMP PERSISTENCE TEST COUNTER (config.DEBUG only)
--
-- See the big comment above persistedState's declaration
-- (Decision 24) for why this mutation lives in a deliberate button
-- click rather than inside load()/save() or any guiUpdate-driven
-- one-shot guard -- both were tried, both were wrong, because
-- load()/save() fire continuously for reasons unrelated to a real
-- player save/load, and the guiUpdate guard is scoped to "once per
-- process," not "once per load." This handler is the only thing
-- that ever mutates persistedState.loadCount.
-- ============================================================

local function handlePersistenceBumpButtonClick()
    bumpPersistenceTestCounter()
end


-- ============================================================
-- TEST FILE I/O (config.DEBUG only)
--
-- See the big comment above testFileIo's declaration for why this
-- exists -- an orthogonal, engine-save-hook-independent way to
-- persist data, being tried because the save/load approach (Decision
-- 24) failed live even after moving state into a shared Lua global.
-- ============================================================

local function handleFileIoTestButtonClick()
    testFileIo()
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


        distributionState.textViews.journeyTestButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".journeyTestButtonLabel",
                "[ Test Loaded Vehicle Journey (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local journeyTestButton =
            gui.button_create(
                WINDOW_ID .. ".journeyTestButton",
                distributionState.textViews.journeyTestButtonLabel
            )

        journeyTestButton:onClick(
            handleJourneyTestButtonClick
        )

        distributionState.journeyTestButton =
            journeyTestButton

        fixedViews[#fixedViews + 1] =
            journeyTestButton


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


        local persistenceBumpButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".persistenceBumpButtonLabel",
                "[ Bump Persistence Counter (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local persistenceBumpButton =
            gui.button_create(
                WINDOW_ID .. ".persistenceBumpButton",
                persistenceBumpButtonLabel
            )

        persistenceBumpButton:onClick(
            handlePersistenceBumpButtonClick
        )

        distributionState.persistenceBumpButton =
            persistenceBumpButton

        fixedViews[#fixedViews + 1] =
            persistenceBumpButton


        local fileIoTestButtonLabel =
            gui.textView_create(
                WINDOW_ID .. ".fileIoTestButtonLabel",
                "[ Test File I/O (DEBUG) ]",
                WINDOW_WIDTH,
                false
            )

        local fileIoTestButton =
            gui.button_create(
                WINDOW_ID .. ".fileIoTestButton",
                fileIoTestButtonLabel
            )

        fileIoTestButton:onClick(
            handleFileIoTestButtonClick
        )

        distributionState.fileIoTestButton =
            fileIoTestButton

        fixedViews[#fixedViews + 1] =
            fileIoTestButton

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


            -- ------------------------------------------------
            -- CONNECTED STATIONS DIAGNOSTIC
            --
            -- Logs every stop connected to this line -- including
            -- the hub's own bucket, now that buildDestinationMap
            -- covers every stop rather than only ones adjacent to
            -- the hub (see demand.lua). This is data-gathering
            -- only: it does not change what the GUI renders, which
            -- still only shows non-hub destinations (see the GUI
            -- layout work still pending). demand.printReport()
            -- re-scans internally rather than reusing lineInfo.demand
            -- above; harmless here since this is a debug-only,
            -- read-only diagnostic, not a hot path.
            -- ------------------------------------------------

            if config.DEBUG then

                demand.printReport(
                    lineInfo.id,
                    stationGroupId
                )

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

    dumpAvailableCommands()

    if config.DEBUG then
        route_injector.runCreateLineTest()
    end

    -- The glyph naming question is settled (● and ↔ safe, ◆ ■ ►
    -- tofu -- TECHNICAL_RESEARCH.md) and baked into line_splitter.lua's
    -- naming convention, so there's no reason to keep recreating the
    -- comparison line every boot. Clean up whatever's left of it
    -- instead -- requested live once it had been sitting as clutter
    -- in every screenshot since the finding was made.
    if config.DEBUG then
        route_injector.cleanupLineNamingGlyphTest()
    end

    if config.DEBUG then

        local ok, err =
            pcall(
                function()

                    local _, hubStop =
                        stations.findStopByNameAnywhere(
                            config.HUB_NAME
                        )

                    if hubStop == nil then

                        logUi(
                            "Cannot dump hub terminals: "
                                .. config.HUB_NAME
                                .. " stop not found."
                        )

                        return

                    end

                    local hubStationGroup =
                        lines.safeField(
                            hubStop,
                            "stationGroup"
                        )

                    stations.dumpStationGroupTerminals(
                        hubStationGroup
                    )

                end
            )

        if not ok then

            logUi(
                "Hub terminal dump failed: "
                    .. tostring(err)
            )

        end

    end

    -- Read-only: does game.interface.getEntity() expose anything
    -- about a vehicle's current onboard cargo/load? It already does
    -- for LINE, STATION_GROUP, and STATION (see the "Auto Line
    -- Namer" workshop mod's bundled reference dump), but this has
    -- never been checked for a VEHICLE entity in this codebase --
    -- TRANSPORT_VEHICLE's own component fields do not include one.
    -- Answering this directly (rather than guessing) is the
    -- prerequisite for a "skip vehicles currently carrying a load"
    -- check before Stage 2/3 reassign anything, requested live.
    if config.DEBUG then

        local ok, err =
            pcall(
                function()

                    local allLineIds =
                        game.interface.getLines()

                    for _, lineId in ipairs(allLineIds or {}) do

                        local name = lines.getName(lineId)

                        if managed_registry.isManaged(lineId) then

                            local vehicleIds =
                                vehicles.getVehiclesForLine(lineId)

                            if #vehicleIds > 0 then

                                vehicles.dumpEntityInfo(
                                    vehicleIds[1],
                                    "SAMPLE MANAGED-LINE VEHICLE "
                                        .. "(game.interface.getEntity)"
                                )

                                return

                            end

                        end

                    end

                    logUi(
                        "No managed (\"● \") line with a vehicle "
                            .. "was found to sample."
                    )

                end
            )

        if not ok then

            logUi(
                "Sample vehicle entity dump failed: "
                    .. tostring(err)
            )

        end

    end

    -- Read-only: raised live -- "can you detect if it's only a drop
    -- off station?" -- e.g. a destination that structurally never
    -- sends anything back toward the hub, versus one that's just
    -- currently at 0 waiting but could have real demand later. A
    -- destination's game.interface.getEntity() (STATION_GROUP)
    -- already exposes itemsLoaded/itemsUnloaded historical totals
    -- (confirmed real fields in the "Auto Line Namer" workshop mod's
    -- bundled reference dump) -- the hypothesis is that a station
    -- whose itemsLoaded has never had anything in it is a genuine
    -- pure drop-off point (loading is the act of putting cargo ONTO
    -- a vehicle FROM that station), which would be a reliable signal
    -- for the "don't show a permanently-0 return row" panel idea.
    -- Untested until now -- dumps every real destination currently
    -- known for the focused hub so that hypothesis can be checked
    -- against real data before any display logic is built on it.
    if config.DEBUG then

        local ok, err =
            pcall(
                function()

                    local _, hubStop =
                        stations.findStopByNameAnywhere(
                            config.HUB_NAME
                        )

                    if hubStop == nil then
                        return
                    end

                    local hubStationGroup =
                        lines.safeField(hubStop, "stationGroup")

                    local managedLines =
                        vehicles.getManagedLinesForStation(hubStationGroup)

                    local seen = {}

                    for _, lineInfo in ipairs(managedLines) do

                        for _, destination in ipairs(lineInfo.destinations or {}) do

                            if destination.stationGroup ~= hubStationGroup
                                and not seen[destination.stationGroup]
                            then

                                seen[destination.stationGroup] = true

                                vehicles.dumpEntityInfo(
                                    destination.stationGroup,
                                    "DESTINATION STATION_GROUP ("
                                        .. tostring(destination.name)
                                        .. ")"
                                )

                            end

                        end

                    end

                end
            )

        if not ok then

            logUi(
                "Destination itemsLoaded/itemsUnloaded dump failed: "
                    .. tostring(err)
            )

        end

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

        save =
            savePersistedState,

        load =
            loadPersistedState

    }

end