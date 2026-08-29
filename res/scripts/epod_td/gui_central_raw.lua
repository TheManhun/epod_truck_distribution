local log = require("epod_td.log")
local gui = require("epod_td.raw_gui_compat")
local hub_registry = require("epod_td.hub_registry")
local stations = require("epod_td.stations")

local tab_overview = require("epod_td.gui_tab_overview")
local tab_lines = require("epod_td.gui_tab_lines")
local tab_cargo = require("epod_td.gui_tab_cargo")
local tab_settings = require("epod_td.gui_tab_settings")

-- Decision 137: FLEET dropped from this window -- player's call,
-- "I'm all for dropping the Fleet page. Less the better ;)" -- once
-- its one distinct signal (the idle flag) moved into SERVICES.
-- gui_tab_fleet.lua itself is NOT deleted -- gui_manager.lua (the
-- "Central Manager (Legacy)" fallback) still lists it as one of its
-- own 8 tabs and must keep working unmodified.
--
-- Decision 139: ACTIVITY dropped the same way -- it was ALWAYS a
-- placeholder ("not built yet -- needs a real activity log module
-- first," gui_tab_activity.lua's own header comment), so this loses
-- nothing real. Part of the 8-tabs-to-4 consolidation the player
-- agreed to start (batch 1, the cheap/low-risk wins). gui_tab_
-- activity.lua stays untouched for the same Legacy-fallback reason as
-- gui_tab_fleet.lua above.
--
-- Decision 141: TERMINALS dropped the same way, once Decision 139's
-- own terminal-number-in-LINES addition made it genuinely redundant --
-- player's own confirmation, "safe to remove the terminals tab now
-- too ;)" after seeing real T-numbers on the LINES accordion.
-- gui_tab_terminals.lua stays untouched for the Legacy fallback.
--
-- Decision 143: HUBS dropped the same way -- its one job (list enabled
-- hubs, toggle Distribution Hub) is now genuinely absorbed into
-- OVERVIEW: the hub list moved there as real clickable buttons (see
-- buildOverviewPanel/state.viewedHubStationGroupId below), and
-- OVERVIEW already had its own Distribution Hub toggle since Decision
-- 124. gui_tab_hubs.lua stays untouched for the Legacy fallback.
--
-- Decision 145: SERVICES dropped -- player's own conclusion after
-- seeing LINES and SERVICES side by side: "now that I can see them
-- side-by-side, I would combine Lines and Services. They are largely
-- two views of the same underlying thing." Target/delta merged
-- straight into LINES' own per-line summary (colored red/white/green
-- by delta sign), Apply Fleet Plan moved to LINES, Build Supply Chains
-- moved to CARGO. gui_tab_services.lua stays untouched for the Legacy
-- fallback -- its full Current/Target/Waiting/Delta table is also
-- still reachable live via Debug Tests' "Show Fleet Plan (DEBUG)"
-- (planner.logTargetAllocation), so nothing is actually lost for
-- diagnostic purposes, just no longer a live GUI tab.

local M = {}


-- ============================================================
-- CENTRAL MANAGER -- RAW SYSTEM (Decisions 131/132/133)
--
-- Decision 131 proved OVERVIEW and LINES could coexist as real
-- show/hide panels in ONE window via api.gui.comp.Component:
-- setVisible, backed by raw_gui_compat.lua so every gui_tab_*.lua file
-- (already written against gui.lua's shape) runs UNCHANGED against a
-- raw-built window. Decision 132 turned LINES into a real accordion.
-- Decision 133: player asked to "put it into main GUI" -- ported the
-- remaining 6 tabs (Hubs, Services, Fleet, Terminals, Cargo, Activity,
-- Settings) the same way and made THIS the window that auto-opens on
-- station selection (see epod_truck_distribution.lua's
-- handleStationSelection/guiUpdate). gui_manager.lua (the old,
-- 8-tab gui.lua-based window) is NOT deleted -- kept as a reachable
-- fallback via Debug Tests ("Open Central Manager (Legacy)") until
-- this window has proven itself across every tab live, matching this
-- project's own established pattern of not deleting a working thing
-- until its
-- replacement is confirmed.
--
-- Every tab EXCEPT LINES shares one generic panel shape (a small
-- pool of action-button slots, a MAX_ROWS pool of plain text rows) --
-- see buildSimplePanel. LINES keeps its own bespoke accordion+
-- pagination panel (buildLinesPanel, Decision 132). SETTINGS'
-- M.build(layout) experiment (Decision 72's one-off ImageView/
-- dumpGameGuiModule proof) is deliberately NOT invoked here -- it
-- hardcodes `require("gui")` internally (gui.lua, not this file's raw
-- compat layer), so calling it against a raw-built layout would fail;
-- it already served its purpose (confirmed ImageView-in-gui.lua-tree
-- works, and dumpGameGuiModule's findings are long since captured in
-- DECISIONS.md/TECHNICAL_RESEARCH.md) and doesn't need to keep running.
-- ============================================================

local WINDOW_WIDTH = 560
local ROW_WIDTH = WINDOW_WIDTH
local MAX_ROWS = 24
local ACTION_BUTTON_WIDTH = 260

-- Decision 176: shared fixed allowance reserved for a ScrollArea's own
-- vertical scrollbar track when sizing a scrolled box's WIDTH from its
-- real row content -- see TRUCK_STATION_ROWS_VIEWPORT_WIDTH's and
-- LINES_GROUPS_VIEWPORT_WIDTH's own comments for the real bug this
-- fixes. A starting guess, not pixel-measured against the real
-- scrollbar yet.
local SCROLLBAR_WIDTH_ALLOWANCE = 30

-- Decision 180: fixed visible height for the shared OVERVIEW/CARGO/
-- SETTINGS summary-rows scroll viewport -- shows roughly 6-7 rows
-- before needing to scroll. A starting guess, same category as every
-- other viewport height added this session.
local SUMMARY_ROWS_VIEWPORT_HEIGHT = 210

-- Must match gui_tab_lines.lua's own copies of these same constants
-- exactly -- the actual widgets are created at these widths/slot
-- counts.
--
-- Decision 174: bumped 8 -> 24 now that the group pool lives inside a
-- real ScrollArea (Decision 173's proven pattern) instead of only
-- Prev/Next pagination -- fewer real hubs will ever need to click Next
-- at all now, Prev/Next kept as the fallback for a hub with more than
-- 24 real managed lines. Still a bounded, pre-built-once pool, not
-- unlimited -- see LINES_GROUPS_VIEWPORT_HEIGHT's own comment for why
-- (this window refreshes on every guiUpdate tick, so rebuilding
-- widgets per-refresh instead of reusing a fixed pool was never an
-- option considered here).
local MAX_LINE_GROUPS_PER_PAGE = 24
local MAX_DESTINATIONS_PER_LINE = 6

-- Fixed visible height for the LINES groups scroll viewport -- shows
-- roughly 6-8 collapsed headers (or fewer with one expanded) before
-- needing to scroll. A starting guess, not tuned against real rendered
-- row height yet, same as gui_plan_popup.lua's own ROWS_VIEWPORT_HEIGHT.
local LINES_GROUPS_VIEWPORT_HEIGHT = 420
local LINE_ROW_LABEL_WIDTH = 350
local LINE_ROW_WAITING_WIDTH = 60
local LINE_ROW_CARGO_SLOTS = 3
local LINE_ROW_CARGO_COUNT_WIDTH = 45
local BLANK_CARGO_ICON = "ui/hud/empty12.tga"

-- Decision 145: SERVICES merged into LINES -- the old single
-- LINE_SUMMARY_WIDTH replaced with three widths for the three
-- separately-colorable widgets a line's summary is now built from
-- (see gui_tab_lines.lua's own copies of these same constants, which
-- must match exactly).
local LINE_VEHICLES_WIDTH = 110
local LINE_DELTA_WIDTH = 45
local LINE_WAITING_TERMINAL_WIDTH = 150

-- Decision 176: same real clipping bug as TRUCK_STATION_ROWS_VIEWPORT_
-- WIDTH above, same fix -- a header row's real content
-- (LINE_ROW_LABEL_WIDTH + LINE_VEHICLES_WIDTH + LINE_DELTA_WIDTH +
-- LINE_WAITING_TERMINAL_WIDTH = 655) already exceeds WINDOW_WIDTH
-- (560), so the scroll area's box must be sized from the real content
-- width plus scrollbar allowance, not WINDOW_WIDTH.
local LINES_GROUPS_VIEWPORT_WIDTH =
    LINE_ROW_LABEL_WIDTH + LINE_VEHICLES_WIDTH + LINE_DELTA_WIDTH + LINE_WAITING_TERMINAL_WIDTH + SCROLLBAR_WIDTH_ALLOWANCE

-- Decision 145: SERVICES dropped -- its two real actions moved
-- (Apply Fleet Plan to LINES, Build Supply Chains to CARGO), and its
-- diagnostic table remains reachable via Debug Tests' existing
-- "Show Fleet Plan (DEBUG)" (planner.logTargetAllocation -- the exact
-- same Current/Target/Waiting/Delta data, already logged, nothing new
-- needed there). gui_tab_services.lua stays untouched for the Legacy
-- fallback.
local TABS = {
    tab_overview,
    tab_lines,
    tab_cargo,
    tab_settings
}

-- How many action-button slots each simple tab claims -- matches how
-- many `actionButtons[N]` indices that tab's own M.refresh actually
-- checks (see each gui_tab_*.lua's own action-button block). Anything
-- not listed here defaults to 0. LINES isn't listed -- it's built by
-- buildLinesPanel instead, never buildSimplePanel (it gets its own
-- small dedicated action-button pool there, see LINES_ACTION_BUTTON_
-- COUNT below).
--
-- Decision 142: tab_overview dropped from 3 to 2 -- "Re-Organize
-- Terminals" (its old slot 2) moved onto LINES; Distribution Hub
-- toggle renumbered down to fill the gap.
--
-- Decision 145: tab_cargo gains 1 -- "Build Supply Chains" moved here
-- from the now-dropped SERVICES tab.
local ACTION_BUTTON_COUNTS = {
    [tab_overview] = 2,
    [tab_cargo] = 1,
    [tab_settings] = 2
}

-- Decision 142/145/146/171: LINES' own action-button pool -- separate
-- from ACTION_BUTTON_COUNTS above since LINES is built by
-- buildLinesPanel, never buildSimplePanel. Slot 1 is Re-Organize
-- Terminals (Decision 142), slot 2 is Apply Fleet Plan (Decision 145,
-- moved from SERVICES), slot 3 is Push Full Reallocation (Decision
-- 146), slot 4 is Fleet Needs Report (Decision 171).
local LINES_ACTION_BUTTON_COUNT = 4

-- Decision 151/161: player's request ("put it on the front page at the
-- bottom showing only 10 stations per page") -- a full-map truck-
-- station browser at the bottom of OVERVIEW. Decision 161 merged the
-- former separate hub-button column into this same list (a "Hubs"
-- filter mode replaces it). Same "reasonable ceiling, not exact-fit"
-- pool sizing and same Prev/Next pagination pattern as LINES
-- (MAX_LINE_GROUPS_PER_PAGE), reached across as many pages as
-- truck_station_finder.scan() actually finds (86 on the test save at
-- the time, up to 223 real stations on the later 250-year save).
--
-- Decision 174: bumped 10 -> 40 now that the row pool lives inside a
-- real ScrollArea instead of relying on Prev/Next alone -- far fewer
-- clicks needed to browse a large map's full station list, Prev/Next
-- kept as the fallback beyond 40. Still a bounded, pre-built-once pool
-- (this window refreshes on every guiUpdate tick -- see Decision 173's
-- own reasoning for why per-refresh widget creation was never an
-- option here), not literally every station on the map at once.
local MAX_TRUCK_STATION_ROWS_PER_PAGE = 40
local TRUCK_STATION_LABEL_WIDTH = 460
local TRUCK_STATION_HUB_BUTTON_WIDTH = 140

-- Fixed visible height for the truck-station scroll viewport -- shows
-- roughly the same ~10 rows the player originally asked for before
-- needing to scroll, same "starting guess" caveat as every other new
-- viewport height added this session.
local TRUCK_STATION_ROWS_VIEWPORT_HEIGHT = 300

-- Decision 176, LIVE-CONFIRMED BUG: a row's real content
-- (TRUCK_STATION_LABEL_WIDTH + TRUCK_STATION_HUB_BUTTON_WIDTH = 600) is
-- already wider than WINDOW_WIDTH (560) -- harmless before Decision
-- 174 since rows were added straight to panelLayout with no fixed-
-- width box around them, so a slightly-over-560 row just rendered fine
-- inside the much wider real window. Wrapping the pool in a
-- ScrollArea's own fixed-width box made that width a real, enforced
-- clip boundary for the first time, and the vertical scrollbar itself
-- (real screen-space, not accounted for by any width constant here)
-- then ate further into what little margin was left -- live-confirmed
-- as the button label text getting cut off ("[ Make H", "[ HUB")
-- exactly once the scrollbar appeared. Fixed by sizing the scroll
-- area's box from the row's own real content width plus a fixed
-- allowance for the scrollbar track, instead of reusing the unrelated
-- WINDOW_WIDTH constant. SCROLLBAR_WIDTH_ALLOWANCE is declared once,
-- near WINDOW_WIDTH itself, and shared with LINES_GROUPS_VIEWPORT_
-- WIDTH's own identical fix below.
local TRUCK_STATION_ROWS_VIEWPORT_WIDTH =
    TRUCK_STATION_LABEL_WIDTH + TRUCK_STATION_HUB_BUTTON_WIDTH + SCROLLBAR_WIDTH_ALLOWANCE

-- Decision 177: player's real complaint -- even after Decision 175's
-- content-fit HEIGHT, the window still rendered close to full screen
-- WIDTH, because `lockedWidth` (below, in ensureWindow) was a screen-
-- percentage guess (60% of screen width, Decision 136) completely
-- untethered from how wide this window's content actually is.
--
-- Deliberately NOT solved with calcMinimumSize the way height was --
-- all four tab panels share ONE window and only one is visible at a
-- time, so a per-tab content-fit WIDTH (recomputed on every tab
-- switch, same as applyContentFitHeight does for height) would make
-- the window visibly change WIDTH switching tabs, exactly the
-- resizing-on-tab-switch annoyance Decision 136 originally fixed.
-- Width has to stay ONE fixed value across every tab, so it's computed
-- once here from the known real widths of the widest actual content in
-- the whole window (LINES' own 4-button action row turns out to be the
-- true widest single row anywhere in this window, wider than either
-- scroll box) -- not a new live API call, just arithmetic over
-- constants already defined above.
local CONTENT_FIT_WIDTH_MARGIN = 40
local CONTENT_FIT_WIDTH =
    math.max(
        LINES_ACTION_BUTTON_COUNT * ACTION_BUTTON_WIDTH,
        LINES_GROUPS_VIEWPORT_WIDTH,
        TRUCK_STATION_ROWS_VIEWPORT_WIDTH,
        WINDOW_WIDTH
    ) + CONTENT_FIT_WIDTH_MARGIN

-- Decision 181: player's request -- LINES' own groups scroll box
-- (sized to LINES_GROUPS_VIEWPORT_WIDTH, its OWN narrowest real
-- content) looked like a narrow column with a big dead gap beside it,
-- since the WINDOW itself is wider than that (the LINES action row,
-- 1040px, is the real widest thing and drives CONTENT_FIT_WIDTH).
-- Every scrollable pool in the window now sizes its box to the same
-- FULL_WIDTH_SCROLL_AREA_WIDTH (the window's own real content width)
-- instead of each pool's own narrower natural content width, so every
-- list visually fills the window instead of leaving a gap beside it.
-- `ensureWindow`'s own `lockedWidth` isn't known yet when these pools
-- are built (screen size hasn't been queried at that point) -- this
-- reuses CONTENT_FIT_WIDTH directly instead, which `lockedWidth` equals
-- in the normal case (it's only ever clamped narrower on an unusually
-- small screen).
local FULL_WIDTH_SCROLL_AREA_WIDTH = CONTENT_FIT_WIDTH - CONTENT_FIT_WIDTH_MARGIN

-- Decision 180: player's real complaint, repeated across several
-- rounds of trying to derive height from `calcMinimumSize` (Decisions
-- 175/178/179) -- that call kept producing inconsistent results (too
-- tall on a full page, then too short after a flat scale-down was
-- applied on top of it) because it was trying to measure genuinely
-- variable per-tab content. Once every variable-length pool in the
-- window is wrapped in a fixed-height ScrollArea (this decision --
-- OVERVIEW/CARGO/SETTINGS' shared summary-rows pool, the last one that
-- wasn't), NOTHING in this window can grow past a known bound any more
-- -- so, exactly like CONTENT_FIT_WIDTH just above, height can be
-- computed ONCE from real known constants instead of any live
-- calcMinimumSize call, and locked, same as width already is
-- (Decision 177). `calcMinimumSize`-based dynamic per-tab height
-- (applyContentFitHeight/currentTabScrollOverflow) is removed entirely
-- -- height is now ONE fixed value for every tab, exactly mirroring
-- width's own "must never jump switching tabs" rule.
--
-- ROW_HEIGHT_ESTIMATE approximates one plain text/button row -- not
-- pixel-measured, same "starting guess" caveat as every viewport height
-- this session. CHROME_HEIGHT_ESTIMATE covers the tab bar, section
-- heading, STATUS bar, and window title bar/margins, none of which are
-- tab-specific.
local ROW_HEIGHT_ESTIMATE = 30
local CHROME_HEIGHT_ESTIMATE = 160

local OVERVIEW_BODY_HEIGHT =
    ROW_HEIGHT_ESTIMATE -- action row
    + SUMMARY_ROWS_VIEWPORT_HEIGHT -- summary rows
    + ROW_HEIGHT_ESTIMATE -- "TRUCK STATIONS" heading + Refresh
    + ROW_HEIGHT_ESTIMATE -- Hubs/Stations/All filter row
    + TRUCK_STATION_ROWS_VIEWPORT_HEIGHT -- truck-station rows
    + ROW_HEIGHT_ESTIMATE -- Prev/Next pagination

local LINES_BODY_HEIGHT =
    ROW_HEIGHT_ESTIMATE -- action row
    + LINES_GROUPS_VIEWPORT_HEIGHT -- groups
    + ROW_HEIGHT_ESTIMATE -- Prev/Next pagination

local SIMPLE_TAB_BODY_HEIGHT =
    ROW_HEIGHT_ESTIMATE -- action row
    + SUMMARY_ROWS_VIEWPORT_HEIGHT -- summary rows (CARGO/SETTINGS)

local CONTENT_FIT_HEIGHT =
    CHROME_HEIGHT_ESTIMATE
    + math.max(OVERVIEW_BODY_HEIGHT, LINES_BODY_HEIGHT, SIMPLE_TAB_BODY_HEIGHT)

-- Decision 136: player's request -- full tab names ("OVERVIEW",
-- "TERMINALS", "ACTIVITY"...) were getting cut off regardless of
-- however wide each tab button actually ends up. Short, fixed-width-
-- friendly codes for the tab bar itself; the full name still shows
-- prominently via state.sectionHeadingLabel just below the tab row
-- (getLabel() is untouched -- log messages and the heading both still
-- use the real full name).
local TAB_SHORT_LABELS = {
    [tab_overview] = "OVW",
    [tab_lines] = "LNS",
    [tab_cargo] = "CGO",
    [tab_settings] = "SET"
}

-- Decision 138: player made real custom icon assets (confirmed real
-- format via research against two shipped Workshop mods -- 8-bit
-- grayscale .tga, res/textures/ui/<name>.tga, referenced bare as
-- "ui/<name>.tga" with no mod-id prefix -- LineManager's own
-- moveit_button.tga/timetable icons use exactly this). Player's
-- originals arrived as .png (untested for ImageView.new -- no shipped
-- mod anywhere was found using .png for this call); converted
-- losslessly to matching 8-bit grayscale .tga via a small PowerShell
-- script (no image tooling available in this environment) rather than
-- risk shipping an unconfirmed format -- LINES/SERVICES/CARGO arrived
-- the same way in a follow-up batch, same conversion applied. Full set
-- now covers every tab this window has (Fleet's icon exists too, from
-- before Decision 137 dropped that tab -- unused here but harmless).
local TAB_ICON_PATHS = {
    [tab_overview] = "ui/epodtd_tab_overview.tga",
    [tab_lines] = "ui/epodtd_tab_lines.tga",
    [tab_cargo] = "ui/epodtd_tab_cargo.tga",
    [tab_settings] = "ui/epodtd_tab_settings.tga"
}

local TAB_ICON_BUTTON_SIZE = 40

local state = {
    window = nil,
    visible = false,
    closedByUser = false,
    activeTabIndex = 1,

    tabButtonLabels = {},
    tabButtons = {},
    sectionHeadingLabel = nil,

    -- state.simplePanels[tabIndex] = { panel, rows, actionButtons } for
    -- every tab except LINES.
    simplePanels = {},

    -- Decision 143: hub-switcher state. viewedHubStationGroupId, when
    -- set, "wins" over whatever station is actually selected on the
    -- map -- cleared back to nil the moment a NEW map selection comes
    -- in (tracked via lastMapHubStationGroupId, compared every tick in
    -- M.refresh) so a deliberate fresh map click always overrides a
    -- stale in-GUI hub choice rather than fighting it forever.
    viewedHubStationGroupId = nil,
    lastMapHubStationGroupId = nil,
    hubButtons = nil,

    -- Decision 168: player's request -- a persistent status bar along
    -- the bottom of the window, always visible regardless of which
    -- tab is active (added directly to the window's own root layout,
    -- outside every per-tab panel, unlike everything else in `state`
    -- that only OVERVIEW/LINES own). The real step-by-step text
    -- (hub_setup.lua's "Splitting...", "Setting up Distribution
    -- Hub...", "Assign & Balance Fleet (done: N assigned...)", etc.)
    -- already existed and was only ever going to log.info -- this
    -- just gives it a second, always-visible destination.
    statusLabel = nil,
    statusText = "",

    linesPanel = nil,
    lineGroups = nil,
    linesPagination = nil,
    linesActionButtons = nil,

    -- Decision 134: player's explicit preference, "I'd prefer this
    -- [toolbar button] then the player can decide when they want to
    -- use the mod" -- opens on demand instead of forcing itself open
    -- on every station click. lastHubStationGroupId is tracked every
    -- tick (M.refresh) regardless of visibility, purely so the toolbar
    -- button's onClick -- which fires independently of the guiUpdate
    -- tick -- knows which station to open the window against.
    toolbarButtonAdded = false,
    lastHubStationGroupId = nil
}


local function describeHeader(hubStationGroupId)

    if hubStationGroupId == nil then
        return "No station selected"
    end

    local okName, name = pcall(stations.getEntityName, hubStationGroupId)
    local displayName = okName and tostring(name) or ("station " .. tostring(hubStationGroupId))

    local okEnabled, isEnabled = pcall(hub_registry.isEnabled, hubStationGroupId)

    if okEnabled and isEnabled then
        return "Distribution Hub - " .. displayName
    end

    return "Truck Station - " .. displayName

end


-- Decision 139: the separate green "Distribution Hub - X" banner row
-- (state.headerLabel, sat above the tab bar) is gone -- folded into
-- the SAME heading that already names the active section (Decision
-- 136), one row instead of two. " | " rather than an em dash or other
-- untested glyph -- only "*" and the arrow character have ever been
-- confirmed to render in this font (the line-naming glyph test); a
-- pipe is plain ASCII, already proven throughout this codebase's own
-- "N vehicles | N waiting" text.
local function describeSectionHeading(tabIndex, hubStationGroupId)

    local tabModule = TABS[tabIndex]
    local tabName = tabModule ~= nil and tostring(tabModule.getLabel()) or ""

    return tabName .. " | " .. describeHeader(hubStationGroupId)

end


local function clearRows(rows)

    if rows == nil then
        return
    end

    for _, row in ipairs(rows) do
        row.label:setText("", ROW_WIDTH)
        pcall(row.label.setStyleClassList, row.label, {})
    end

end


local function clearActionButtons(actionButtons)

    if actionButtons == nil then
        return
    end

    for _, slot in ipairs(actionButtons) do
        slot.label:setText("", ACTION_BUTTON_WIDTH)
        slot.handler = nil
        pcall(slot.button.setStyleClassList, slot.button, {})
    end

end


-- Decision 143: the only mutation gui_tab_overview.lua is ever handed
-- -- passed into its M.refresh as a plain callback rather than letting
-- it reach into this file's own state directly, keeping the "GUI tabs
-- only render, they don't own window-level state" boundary intact
-- (same reasoning every other gui_tab_*.lua file's "GUI ONLY" header
-- comment already states).
local function switchViewedHub(newHubStationGroupId)
    state.viewedHubStationGroupId = newHubStationGroupId
end


-- Decision 168: passed down to every tab's M.refresh the same way
-- switchViewedHub already is, so no gui_tab_*.lua file ever needs to
-- require this module back (would risk a require cycle -- this module
-- is the one that requires them). Any tab can call setStatus(text) to
-- post real progress text to the always-visible bottom bar; nil/""
-- clears it back to blank.
local function setStatus(text)

    state.statusText = tostring(text or "")

    if state.statusLabel ~= nil then
        pcall(state.statusLabel.setText, state.statusLabel, state.statusText, WINDOW_WIDTH)
    end

end


-- Decision 134: injects a small, always-visible toggle button directly
-- into the game's own bottom "gameInfo" bar -- the real, live-verified
-- technique from LineManager's own shipped source (checked against the
-- actual cached workshop file, not just the player-relayed claim):
-- `api.gui.util.getById("gameInfo"):getLayout():addItem(...)`, a
-- divider/button/divider trio. Runs from M.refresh so it's attempted
-- every tick until it succeeds once (gameInfo might not exist yet on
-- the very first ticks) -- `state.toolbarButtonAdded` makes every
-- later call a no-op. Deliberately NOT a gui.lua object and NOT added
-- to this window's own layout -- it's a raw component living in a
-- completely different part of the UI tree (the base game's own bar),
-- so there is no risk of the Decision 73 mixing crash here.
local function ensureToolbarButton()

    if state.toolbarButtonAdded then
        return
    end

    if api == nil or api.gui == nil or api.gui.util == nil then
        return
    end

    local ok, err =
        pcall(function()

            local gameInfo = api.gui.util.getById("gameInfo")

            if gameInfo == nil then
                return
            end

            local gameInfoLayout = gameInfo:getLayout()

            local buttonLabel = api.gui.comp.TextView.new("DD")
            local button = api.gui.comp.Button.new(buttonLabel, true)

            -- Decision 143: reads state.lastMapHubStationGroupId (the
            -- raw map selection), NOT state.lastHubStationGroupId (the
            -- EFFECTIVE, possibly hub-switched value) -- M.refresh's
            -- own precedence logic needs the raw signal to correctly
            -- detect "did a new map selection actually happen," and
            -- feeding it the effective value here would corrupt that
            -- tracking (e.g. reopening after switching to a different
            -- hub in the GUI would look like a fresh map click,
            -- silently discarding the in-GUI choice). The chosen hub
            -- itself (state.viewedHubStationGroupId) isn't lost by
            -- toggling the window closed/open either way -- it's a
            -- separate field, untouched by this call.
            button:onClick(function()
                M.toggleVisibility(state.lastMapHubStationGroupId)
            end)

            gameInfoLayout:addItem(api.gui.comp.Component.new("VerticalLine"))
            gameInfoLayout:addItem(button)
            gameInfoLayout:addItem(api.gui.comp.Component.new("VerticalLine"))

            state.toolbarButtonAdded = true

        end)

    if not ok then
        log.info("GUI CENTRAL RAW: toolbar button injection failed: " .. tostring(err))
    end

end


function M.refresh(hubStationGroupId)

    ensureToolbarButton()

    -- Decision 143: a genuinely NEW map selection always overrides
    -- whatever hub the player chose inside the GUI itself -- detected
    -- by comparing against the last RAW map selection seen (NOT the
    -- effective/viewed one), so re-refreshing on the SAME still-
    -- selected station doesn't keep resetting the player's in-GUI
    -- choice every single tick. Runs regardless of window visibility
    -- so the precedence stays correct even while the window is closed.
    if hubStationGroupId ~= state.lastMapHubStationGroupId then
        state.viewedHubStationGroupId = nil
        state.lastMapHubStationGroupId = hubStationGroupId
    end

    local effectiveHubStationGroupId = state.viewedHubStationGroupId or hubStationGroupId

    state.lastHubStationGroupId = effectiveHubStationGroupId

    if not state.visible or state.window == nil then
        return
    end

    -- Updated every tick (not just on tab switch) so it stays current
    -- if the player selects a different station on the map, or a
    -- different hub inside the GUI itself, while already open on the
    -- same tab.
    if state.sectionHeadingLabel ~= nil then

        pcall(
            state.sectionHeadingLabel.setText,
            state.sectionHeadingLabel,
            describeSectionHeading(state.activeTabIndex, effectiveHubStationGroupId),
            WINDOW_WIDTH
        )

    end

    local activeTabModule = TABS[state.activeTabIndex]

    if activeTabModule == nil then
        return
    end

    if activeTabModule == tab_lines then

        clearActionButtons(state.linesActionButtons)

        local ok, err = pcall(tab_lines.refresh, nil, effectiveHubStationGroupId, state.linesActionButtons, state.lineGroups, state.linesPagination, setStatus)

        if not ok then
            log.info("GUI CENTRAL RAW: LINES refresh failed: " .. tostring(err))
        end

        return

    end

    local panelState = state.simplePanels[state.activeTabIndex]

    if panelState == nil then
        return
    end

    clearRows(panelState.rows)
    clearActionButtons(panelState.actionButtons)

    -- switchViewedHub/truckStation* are passed to EVERY simple tab's
    -- refresh, not just OVERVIEW's -- harmless extra arguments for tabs
    -- whose M.refresh doesn't declare/use them (Lua ignores extra call
    -- arguments a function doesn't name), and keeps this dispatch
    -- generic rather than special-casing OVERVIEW here too.
    local ok, err = pcall(
        activeTabModule.refresh,
        panelState.rows,
        effectiveHubStationGroupId,
        panelState.actionButtons,
        switchViewedHub,
        state.truckStationRows,
        state.truckStationPagination,
        state.truckStationRefreshButton,
        state.truckStationFilterButtons,
        setStatus
    )

    if not ok then
        log.info("GUI CENTRAL RAW: " .. tostring(activeTabModule.getLabel()) .. " refresh failed: " .. tostring(err))
    end

end


-- Decision 180: the per-tab dynamic height dance that used to live here
-- (applyContentFitHeight/currentTabScrollOverflow, Decisions 175/178/
-- 179) is gone -- `calcMinimumSize`-driven height kept producing
-- inconsistent real results (correct on a short page, oversized on a
-- full one, then undersized once a flat scale-down was layered on top
-- to compensate). Height is now a single fixed value for the window's
-- whole lifetime, computed once in ensureWindow from CONTENT_FIT_HEIGHT
-- -- exactly the same treatment CONTENT_FIT_WIDTH already gets, and for
-- the same reason: every variable-length pool in this window is now
-- wrapped in its own bounded ScrollArea, so nothing can grow past a
-- known bound any more and a live measurement is no longer needed.


local function selectTab(tabIndex, hubStationGroupId)

    state.activeTabIndex = tabIndex

    -- Decision 138: iterates TABS, not state.tabButtonLabels -- icon
    -- tabs deliberately leave that slot nil (no text to update), and
    -- ipairs stops dead at the first nil hole it finds, which would
    -- have silently skipped almost this entire loop the moment tab 1
    -- (OVERVIEW) got an icon.
    for index, tabModule in ipairs(TABS) do

        local isActive = index == tabIndex
        local label = state.tabButtonLabels[index]

        if label ~= nil then

            local shortLabel = TAB_SHORT_LABELS[tabModule] or tostring(tabModule.getLabel())
            local text = (isActive and "> " or "  ") .. shortLabel

            label:setText(text, WINDOW_WIDTH / #TABS)

        end

        local button = state.tabButtons[index]

        if button ~= nil then
            pcall(button.setStyleClassList, button, { isActive and "EpodTdTabActive" or "EpodTdTabInactive" })
        end

    end

    -- state.sectionHeadingLabel is updated inside M.refresh (called at
    -- the end of this function anyway) rather than here -- it needs to
    -- reflect the current hub too, not just the tab name, and M.refresh
    -- already runs on every tick regardless of whether the tab changed.

    -- Whole-panel visibility, backed by the live-confirmed
    -- Component:setVisible -- no shared pool to clear/refill anymore.
    for index, tabModule in ipairs(TABS) do

        local isActive = index == tabIndex

        if tabModule == tab_lines then

            if state.linesPanel ~= nil then
                state.linesPanel:setVisible(isActive)
            end

        else

            local panelState = state.simplePanels[index]

            if panelState ~= nil and panelState.panel ~= nil then
                panelState.panel:setVisible(isActive)
            end

        end

    end

    M.refresh(hubStationGroupId)

end


-- Decision 143: extracted out of buildSimplePanel so buildOverviewPanel
-- can build its own action-button row the exact same way, rather than
-- duplicating this loop. Behaviour unchanged from before the
-- extraction -- same "wire onClick once, dispatch through a .handler
-- field reassigned every refresh" pattern, same per-button
-- setMaximumSize fix (Decision 135).
local function buildActionButtons(panelLayout, actionButtonCount)

    if actionButtonCount <= 0 then
        return nil
    end

    local actionRow = gui.boxLayout_create(nil, "HORIZONTAL")
    local actionButtons = {}

    for slotIndex = 1, actionButtonCount do

        local label = gui.textView_create(nil, "", ACTION_BUTTON_WIDTH, false)
        local button = gui.button_create(nil, label)

        pcall(button.setMaximumSize, button, ACTION_BUTTON_WIDTH, 2000)

        button:onClick(function()

            local slot = actionButtons[slotIndex]

            if slot ~= nil and slot.handler ~= nil then

                local ok, err = pcall(slot.handler)

                if not ok then
                    log.info("GUI CENTRAL RAW: action button " .. tostring(slotIndex) .. " handler failed: " .. tostring(err))
                end

            end

        end)

        actionRow:addItem(button)

        actionButtons[slotIndex] = { label = label, button = button, handler = nil }

    end

    panelLayout:addItem(actionRow)

    return actionButtons

end


-- Decision 184 cleanup: extracted out of buildSimplePanel/
-- buildOverviewPanel, which had built this exact same
-- container+layout+row-loop+ScrollArea block verbatim, independently,
-- since Decision 180 added it to both -- same "shared widget-building
-- logic belongs in one place" precedent buildActionButtons above
-- already set (Decision 143). Behavior unchanged: a MAX_ROWS pool of
-- plain text rows wrapped in a fixed-size scrollable viewport, added to
-- `panelLayout`, returning the row pool for the caller to fill.
local function buildScrollableSummaryRows(panelLayout)

    local rowsContainer = gui.container_create(nil)
    local rowsLayout = gui.boxLayout_create(nil, "VERTICAL")
    rowsContainer:setLayout(rowsLayout)

    local rows = {}

    for rowIndex = 1, MAX_ROWS do

        local label = gui.textView_create(nil, "", ROW_WIDTH, false)
        rowsLayout:addItem(label)

        rows[rowIndex] = { label = label }

    end

    local rowsScrollArea = gui.scrollArea_create(nil, rowsContainer)
    pcall(rowsScrollArea.setMinimumSize, rowsScrollArea, FULL_WIDTH_SCROLL_AREA_WIDTH, SUMMARY_ROWS_VIEWPORT_HEIGHT)
    pcall(rowsScrollArea.setMaximumSize, rowsScrollArea, FULL_WIDTH_SCROLL_AREA_WIDTH, SUMMARY_ROWS_VIEWPORT_HEIGHT)
    panelLayout:addItem(rowsScrollArea)

    return rows

end


-- Generic panel builder for every tab except LINES and OVERVIEW: a
-- small pool of action-button slots (0 is fine -- most tabs use none)
-- plus a MAX_ROWS pool of plain text rows. Every gui_tab_*.lua file
-- besides gui_tab_lines.lua/gui_tab_overview.lua already only calls
-- this exact shape (setText(text,width) / setStyleClassList(list) on
-- whatever it's handed), proven first by OVERVIEW in Decision 131.
local function buildSimplePanel(panelId, actionButtonCount)

    local panel = gui.container_create(panelId)
    local panelLayout = gui.boxLayout_create(nil, "VERTICAL")
    panel:setLayout(panelLayout)

    local actionButtons = buildActionButtons(panelLayout, actionButtonCount)
    local rows = buildScrollableSummaryRows(panelLayout)

    return panel, rows, actionButtons

end


-- Decision 161: player's own redesign -- the separate hub-switcher
-- button column (Decision 143) and the truck-station list (Decision
-- 151) were two different widget pools doing overlapping jobs (both
-- ultimately just "list some stations"). Merged into ONE list: every
-- enabled hub now appears as a normal row in the SAME truck-station
-- pool below (switching which one an existing hub row's name-click
-- does -- switch the viewed hub, per the player's own confirmation,
-- "if you click the Hub button that's the one in focus for all the
-- data" -- instead of a camera jump), with a 3-way filter (Hubs /
-- Stations / All) replacing the old always-shown hub column. The old
-- 12-slot hubButtonsColumn is gone outright, not just hidden -- same
-- lesson as Decision 152: an unused pre-allocated pool in this non-
-- scrolling window always costs real height whether or not it's
-- ever populated.
local function buildOverviewPanel(panelId, actionButtonCount)

    local panel = gui.container_create(panelId)
    local panelLayout = gui.boxLayout_create(nil, "VERTICAL")
    panel:setLayout(panelLayout)

    local actionButtons = buildActionButtons(panelLayout, actionButtonCount)
    local rows = buildScrollableSummaryRows(panelLayout)

    -- Decision 151: truck-station browser at the bottom of OVERVIEW.
    -- Heading + a dedicated Refresh button (a full-map scan is real
    -- work -- truck_station_finder.scan() is never called automatically
    -- on every guiUpdate tick, only on this explicit click, same
    -- "player-triggered, not silently-continuous" philosophy every
    -- other hub-mutating/expensive action in this window already
    -- follows), then a MAX_TRUCK_STATION_ROWS_PER_PAGE pool of rows
    -- (info label + a per-row "Make Hub"/"HUB" button), then the same
    -- Prev/Next pagination pattern LINES already proved out.
    local truckStationHeadingRow = gui.boxLayout_create(nil, "HORIZONTAL")

    local truckStationHeading = gui.textView_create(nil, "TRUCK STATIONS", WINDOW_WIDTH - 140, false)
    pcall(truckStationHeading.setStyleClassList, truckStationHeading, { "EpodTdTableHeader" })
    truckStationHeadingRow:addItem(truckStationHeading)

    local refreshButtonLabel = gui.textView_create(nil, "[ Refresh ]", 130, false)
    local refreshButton = gui.button_create(nil, refreshButtonLabel)
    pcall(refreshButton.setMaximumSize, refreshButton, 130, 2000)

    refreshButton:onClick(function()

        if state.truckStationRefreshButton ~= nil and state.truckStationRefreshButton.handler ~= nil then

            local ok, err = pcall(state.truckStationRefreshButton.handler)

            if not ok then
                log.info("GUI CENTRAL RAW: truck station Refresh failed: " .. tostring(err))
            end

        end

    end)

    truckStationHeadingRow:addItem(refreshButton)
    panelLayout:addItem(truckStationHeadingRow)

    state.truckStationRefreshButton = { label = refreshButtonLabel, button = refreshButton, handler = nil }

    -- Decision 161: 3-way filter replacing the old separate hub-button
    -- column -- "Hubs" shows only your enabled hubs (this list's own
    -- name-click now switches the viewed hub for a row like that,
    -- instead of the camera-jump every other row does), "Stations"
    -- shows only non-hub candidates, "All" is everything (still never
    -- includes drop-offs -- Decision 159 stays in effect regardless of
    -- filter). Same 3-button row-of-toggles shape as the tab bar
    -- itself, reusing EpodTdTabActive/EpodTdTabInactive.
    local filterRow = gui.boxLayout_create(nil, "HORIZONTAL")

    state.truckStationFilterButtons = {}

    local filterModes = { "HUBS", "STATIONS", "ALL" }
    local filterLabels = { HUBS = "[ Hubs ]", STATIONS = "[ Stations ]", ALL = "[ All ]" }

    for _, filterMode in ipairs(filterModes) do

        local label = gui.textView_create(nil, filterLabels[filterMode], 120, false)
        local button = gui.button_create(nil, label)
        pcall(button.setMaximumSize, button, 120, 2000)

        button:onClick(function()

            local slot = state.truckStationFilterButtons[filterMode]

            if slot ~= nil and slot.handler ~= nil then

                local ok, err = pcall(slot.handler)

                if not ok then
                    log.info("GUI CENTRAL RAW: truck station filter '" .. tostring(filterMode) .. "' failed: " .. tostring(err))
                end

            end

        end)

        filterRow:addItem(button)

        state.truckStationFilterButtons[filterMode] = { label = label, button = button, handler = nil }

    end

    panelLayout:addItem(filterRow)

    -- Decision 174: row pool now lives inside its own scrollable
    -- viewport (real ScrollArea, proven in Decision 173) instead of
    -- being added straight to panelLayout -- see
    -- TRUCK_STATION_ROWS_VIEWPORT_HEIGHT's own comment above.
    local truckStationRowsContainer = gui.container_create(nil)
    local truckStationRowsLayout = gui.boxLayout_create(nil, "VERTICAL")
    truckStationRowsContainer:setLayout(truckStationRowsLayout)

    state.truckStationRows = {}

    for stationSlotIndex = 1, MAX_TRUCK_STATION_ROWS_PER_PAGE do

        local rowLayout = gui.boxLayout_create(nil, "HORIZONTAL")

        -- Decision 155/156: the info text is now a real button, not a
        -- plain TextView -- player's request, click the station NAME
        -- to jump the camera there (game.gui.setCamera, LIVE-CONFIRMED
        -- working from this mod's own DEBUG probe). Deliberately a
        -- SEPARATE widget/handler from hubButton below -- player's own
        -- framing, "I'd keep Make Hub as a separate button so clicking
        -- the name is always safe/navigation-only" -- so a mis-click on
        -- the name can never accidentally trigger a real hub mutation.
        local infoLabel = gui.textView_create(nil, "", TRUCK_STATION_LABEL_WIDTH, false)
        local infoButton = gui.button_create(nil, infoLabel)
        pcall(infoButton.setMaximumSize, infoButton, TRUCK_STATION_LABEL_WIDTH, 2000)

        infoButton:onClick(function()

            local slot = state.truckStationRows[stationSlotIndex]

            if slot ~= nil and slot.locateHandler ~= nil then

                local ok, err = pcall(slot.locateHandler)

                if not ok then
                    log.info("GUI CENTRAL RAW: truck station row " .. tostring(stationSlotIndex) .. " locate handler failed: " .. tostring(err))
                end

            end

        end)

        rowLayout:addItem(infoButton)

        local hubButtonLabel = gui.textView_create(nil, "", TRUCK_STATION_HUB_BUTTON_WIDTH, false)
        local hubButton = gui.button_create(nil, hubButtonLabel)
        pcall(hubButton.setMaximumSize, hubButton, TRUCK_STATION_HUB_BUTTON_WIDTH, 2000)

        hubButton:onClick(function()

            local slot = state.truckStationRows[stationSlotIndex]

            if slot ~= nil and slot.handler ~= nil then

                local ok, err = pcall(slot.handler)

                if not ok then
                    log.info("GUI CENTRAL RAW: truck station row " .. tostring(stationSlotIndex) .. " handler failed: " .. tostring(err))
                end

            end

        end)

        rowLayout:addItem(hubButton)

        local rowContainer = gui.container_create("centralRaw.truckStationRow." .. tostring(stationSlotIndex))
        rowContainer:setLayout(rowLayout)
        truckStationRowsLayout:addItem(rowContainer)

        state.truckStationRows[stationSlotIndex] = {
            container = rowContainer,
            infoLabel = infoLabel,
            infoButton = infoButton,
            hubButton = hubButton,
            hubButtonLabel = hubButtonLabel,
            handler = nil,
            locateHandler = nil
        }

    end

    local truckStationRowsScrollArea = gui.scrollArea_create(nil, truckStationRowsContainer)
    pcall(truckStationRowsScrollArea.setMinimumSize, truckStationRowsScrollArea, FULL_WIDTH_SCROLL_AREA_WIDTH, TRUCK_STATION_ROWS_VIEWPORT_HEIGHT)
    pcall(truckStationRowsScrollArea.setMaximumSize, truckStationRowsScrollArea, FULL_WIDTH_SCROLL_AREA_WIDTH, TRUCK_STATION_ROWS_VIEWPORT_HEIGHT)
    panelLayout:addItem(truckStationRowsScrollArea)

    local truckStationPaginationRow = gui.boxLayout_create(nil, "HORIZONTAL")

    local truckStationPrevLabel = gui.textView_create(nil, "[ Prev ]", 100, false)
    local truckStationPrevButton = gui.button_create(nil, truckStationPrevLabel)
    pcall(truckStationPrevButton.setMaximumSize, truckStationPrevButton, 100, 2000)

    truckStationPrevButton:onClick(function()

        if truckStationPrevButton.handler ~= nil then

            local ok, err = pcall(truckStationPrevButton.handler)

            if not ok then
                log.info("GUI CENTRAL RAW: truck station Prev failed: " .. tostring(err))
            end

        end

    end)

    truckStationPaginationRow:addItem(truckStationPrevButton)

    local truckStationPageLabel = gui.textView_create(nil, "", 120, false)
    truckStationPaginationRow:addItem(truckStationPageLabel)

    local truckStationNextLabel = gui.textView_create(nil, "[ Next ]", 100, false)
    local truckStationNextButton = gui.button_create(nil, truckStationNextLabel)
    pcall(truckStationNextButton.setMaximumSize, truckStationNextButton, 100, 2000)

    truckStationNextButton:onClick(function()

        if truckStationNextButton.handler ~= nil then

            local ok, err = pcall(truckStationNextButton.handler)

            if not ok then
                log.info("GUI CENTRAL RAW: truck station Next failed: " .. tostring(err))
            end

        end

    end)

    truckStationPaginationRow:addItem(truckStationNextButton)
    panelLayout:addItem(truckStationPaginationRow)

    state.truckStationPagination = {
        prevButton = truckStationPrevButton,
        nextButton = truckStationNextButton,
        pageLabel = truckStationPageLabel
    }

    return panel, rows, actionButtons

end


-- Decision 132 accordion rewrite: each "line group" is a permanent
-- header row (a clickable button showing the line's name + a summary
-- label alongside it, always visible) plus a detail panel of
-- destination rows that gui_tab_lines.lua setVisible-collapses unless
-- that specific line is the one currently expanded. Only
-- MAX_LINE_GROUPS_PER_PAGE groups exist -- more managed lines than
-- that are reached via the Prev/Next pagination row at the bottom,
-- not by growing the pool. Each destination row is ALSO individually
-- wrapped in its own hideable container (Decision 132 spacing fix) so
-- an expanded line with only 1-2 real destinations doesn't leave a
-- gap where its unused destination slots would otherwise still be.
local function buildLinesPanel()

    local panel = gui.container_create("centralRaw.linesPanel")
    local panelLayout = gui.boxLayout_create(nil, "VERTICAL")
    panel:setLayout(panelLayout)

    -- Decision 142: "Re-Organize Terminals" moved here from OVERVIEW --
    -- player's call, "we still want the resort terminals button, but
    -- that could go onto the Lines page, logical sense" now that LINES
    -- shows each line's own terminal number. Same "wire onClick once,
    -- dispatch through a .handler field reassigned every refresh"
    -- pattern buildSimplePanel's action buttons already use.
    local actionRow = gui.boxLayout_create(nil, "HORIZONTAL")

    state.linesActionButtons = {}

    for slotIndex = 1, LINES_ACTION_BUTTON_COUNT do

        local label = gui.textView_create(nil, "", ACTION_BUTTON_WIDTH, false)
        local button = gui.button_create(nil, label)

        pcall(button.setMaximumSize, button, ACTION_BUTTON_WIDTH, 2000)

        button:onClick(function()

            local slot = state.linesActionButtons[slotIndex]

            if slot ~= nil and slot.handler ~= nil then

                local ok, err = pcall(slot.handler)

                if not ok then
                    log.info("GUI CENTRAL RAW: LINES action button " .. tostring(slotIndex) .. " handler failed: " .. tostring(err))
                end

            end

        end)

        actionRow:addItem(button)

        state.linesActionButtons[slotIndex] = { label = label, button = button, handler = nil }

    end

    panelLayout:addItem(actionRow)

    -- Decision 174: group pool now lives inside its own scrollable
    -- viewport (real ScrollArea, proven in Decision 173) instead of
    -- being added straight to panelLayout -- see
    -- LINES_GROUPS_VIEWPORT_HEIGHT's own comment above. Each group's
    -- accordion-expand detail panel still lives INSIDE this same
    -- scrolled container (unchanged setVisible-toggle behavior,
    -- gui_tab_lines.lua's own expand/collapse logic doesn't need to
    -- know this container is now scrollable at all) -- not yet
    -- independently live-tested whether expanding a group deep in a
    -- long scrolled list behaves sensibly (e.g. whether the scroll
    -- position jumps), flagged for live-test same as everything else
    -- new this session.
    local lineGroupsContainer = gui.container_create(nil)
    local lineGroupsLayout = gui.boxLayout_create(nil, "VERTICAL")
    lineGroupsContainer:setLayout(lineGroupsLayout)

    state.lineGroups = {}

    for groupIndex = 1, MAX_LINE_GROUPS_PER_PAGE do

        local headerRow = gui.boxLayout_create(nil, "HORIZONTAL")

        local headerButtonLabel = gui.textView_create(nil, "", LINE_ROW_LABEL_WIDTH, false)
        local headerButton = gui.button_create(nil, headerButtonLabel)

        -- Decision 135: cap the button itself, not just its label.
        pcall(headerButton.setMaximumSize, headerButton, LINE_ROW_LABEL_WIDTH, 2000)

        headerButton:onClick(function()

            local group = state.lineGroups[groupIndex]

            if group ~= nil and group.handler ~= nil then

                local ok, err = pcall(group.handler)

                if not ok then
                    log.info("GUI CENTRAL RAW: LINES group " .. tostring(groupIndex) .. " handler failed: " .. tostring(err))
                end

            end

        end)

        headerRow:addItem(headerButton)

        -- Decision 145: three separately-colorable widgets instead of
        -- one combined summaryLabel -- the delta needs its own
        -- red/white/green styling independent of the vehicle/waiting
        -- text either side of it, and a style class colors an ENTIRE
        -- TextView's string, never a sub-span within one.
        local vehiclesLabel = gui.textView_create(nil, "", LINE_VEHICLES_WIDTH, false)
        headerRow:addItem(vehiclesLabel)

        local deltaLabel = gui.textView_create(nil, "", LINE_DELTA_WIDTH, false)
        headerRow:addItem(deltaLabel)

        local waitingTerminalLabel = gui.textView_create(nil, "", LINE_WAITING_TERMINAL_WIDTH, false)
        headerRow:addItem(waitingTerminalLabel)

        lineGroupsLayout:addItem(headerRow)

        local detailPanel = gui.container_create("centralRaw.lineGroup." .. tostring(groupIndex) .. ".detail")
        local detailLayout = gui.boxLayout_create(nil, "VERTICAL")
        detailPanel:setLayout(detailLayout)
        detailPanel:setVisible(false)

        local destinationRows = {}

        for destIndex = 1, MAX_DESTINATIONS_PER_LINE do

            local rowLayout = gui.boxLayout_create(nil, "HORIZONTAL")

            local labelView = gui.textView_create(nil, "", LINE_ROW_LABEL_WIDTH, false)
            rowLayout:addItem(labelView)

            local waitingView = gui.textView_create(nil, "", LINE_ROW_WAITING_WIDTH, false)
            rowLayout:addItem(waitingView)

            local cargoIcons = {}
            local cargoCounts = {}

            for cargoSlotIndex = 1, LINE_ROW_CARGO_SLOTS do

                local iconView = gui.imageView_create(nil, BLANK_CARGO_ICON)
                local countView = gui.textView_create(nil, "", LINE_ROW_CARGO_COUNT_WIDTH, false)

                pcall(iconView.setTransparent, iconView, true)
                pcall(countView.setTransparent, countView, true)

                rowLayout:addItem(iconView)
                rowLayout:addItem(countView)

                cargoIcons[cargoSlotIndex] = iconView
                cargoCounts[cargoSlotIndex] = countView

            end

            local rowContainer = gui.container_create("centralRaw.lineGroup." .. tostring(groupIndex) .. ".dest." .. tostring(destIndex))
            rowContainer:setLayout(rowLayout)

            destinationRows[destIndex] = {
                container = rowContainer,
                label = labelView,
                waitingLabel = waitingView,
                cargoIcons = cargoIcons,
                cargoCounts = cargoCounts
            }

            detailLayout:addItem(rowContainer)

        end

        lineGroupsLayout:addItem(detailPanel)

        state.lineGroups[groupIndex] = {
            headerButton = headerButton,
            headerButtonLabel = headerButtonLabel,
            vehiclesLabel = vehiclesLabel,
            deltaLabel = deltaLabel,
            waitingTerminalLabel = waitingTerminalLabel,
            detailPanel = detailPanel,
            destinationRows = destinationRows,
            handler = nil
        }

    end

    local lineGroupsScrollArea = gui.scrollArea_create(nil, lineGroupsContainer)
    pcall(lineGroupsScrollArea.setMinimumSize, lineGroupsScrollArea, FULL_WIDTH_SCROLL_AREA_WIDTH, LINES_GROUPS_VIEWPORT_HEIGHT)
    pcall(lineGroupsScrollArea.setMaximumSize, lineGroupsScrollArea, FULL_WIDTH_SCROLL_AREA_WIDTH, LINES_GROUPS_VIEWPORT_HEIGHT)
    panelLayout:addItem(lineGroupsScrollArea)

    local paginationRow = gui.boxLayout_create(nil, "HORIZONTAL")

    local prevButtonLabel = gui.textView_create(nil, "[ Prev ]", 100, false)
    local prevButton = gui.button_create(nil, prevButtonLabel)

    pcall(prevButton.setMaximumSize, prevButton, 100, 2000)

    prevButton:onClick(function()

        if prevButton.handler ~= nil then

            local ok, err = pcall(prevButton.handler)

            if not ok then
                log.info("GUI CENTRAL RAW: LINES Prev failed: " .. tostring(err))
            end

        end

    end)

    paginationRow:addItem(prevButton)

    local pageLabel = gui.textView_create(nil, "", 120, false)
    paginationRow:addItem(pageLabel)

    local nextButtonLabel = gui.textView_create(nil, "[ Next ]", 100, false)
    local nextButton = gui.button_create(nil, nextButtonLabel)

    pcall(nextButton.setMaximumSize, nextButton, 100, 2000)

    nextButton:onClick(function()

        if nextButton.handler ~= nil then

            local ok, err = pcall(nextButton.handler)

            if not ok then
                log.info("GUI CENTRAL RAW: LINES Next failed: " .. tostring(err))
            end

        end

    end)

    paginationRow:addItem(nextButton)

    panelLayout:addItem(paginationRow)

    state.linesPagination = {
        prevButton = prevButton,
        nextButton = nextButton,
        pageLabel = pageLabel
    }

    return panel

end


-- Decision 135: no longer gated on state.closedByUser -- that guard
-- made sense under gui_manager.lua's model (a window genuinely
-- destroyed on close, rebuilt fresh next time), but this window is
-- built once and toggled via setVisible from here on, so "closedByUser"
-- is now purely informational state for M.toggleVisibility, not a
-- reason to refuse building/returning the window.
local function ensureWindow(hubStationGroupId)

    if state.window ~= nil then
        return state.window
    end

    local layout = gui.boxLayout_create(nil, "VERTICAL")

    local tabRow = gui.boxLayout_create(nil, "HORIZONTAL")

    state.tabButtonLabels = {}
    state.tabButtons = {}

    for index, tabModule in ipairs(TABS) do

        local iconPath = TAB_ICON_PATHS[tabModule]
        local button

        if iconPath ~= nil then

            -- Decision 138: icon tab -- no text label to update on
            -- selection, active/inactive is conveyed entirely by the
            -- button's own background style below (EpodTdTabActive/
            -- EpodTdTabInactive), same as it already was for text tabs.
            local icon = gui.imageView_create(nil, iconPath)
            button = gui.button_create(nil, icon)

            pcall(button.setMaximumSize, button, TAB_ICON_BUTTON_SIZE, TAB_ICON_BUTTON_SIZE)

            state.tabButtonLabels[index] = nil

        else

            local shortLabel = TAB_SHORT_LABELS[tabModule] or tostring(tabModule.getLabel())
            local label = gui.textView_create(nil, "  " .. shortLabel, WINDOW_WIDTH / #TABS, false)
            button = gui.button_create(nil, label)

            -- Decision 135: cap the button itself, not just its label
            -- -- see the matching comment in buildSimplePanel's
            -- action-button loop for why this matters.
            pcall(button.setMaximumSize, button, WINDOW_WIDTH / #TABS, 2000)

            state.tabButtonLabels[index] = label

        end

        -- Decision 143: reads state.lastMapHubStationGroupId at click
        -- time, NOT the `hubStationGroupId` parameter closed over here
        -- -- this closure is built once, ever (ensureWindow only runs
        -- once), so that parameter is permanently frozen at whatever
        -- station was selected the moment the window first opened.
        -- Harmless before Decision 143 (the very next guiUpdate tick's
        -- own M.refresh call always overwrote it with the current
        -- value anyway), but would now actively fight the hub-switcher:
        -- passing a stale value into M.refresh would make it look like
        -- a genuinely new map selection happened, silently discarding
        -- whatever hub the player had just chosen via the OVERVIEW list.
        button:onClick(function()
            selectTab(index, state.lastMapHubStationGroupId)
        end)

        tabRow:addItem(button)

        state.tabButtons[index] = button

    end

    layout:addItem(tabRow)

    -- Decision 136: player's request -- a big, prominent heading
    -- naming the current section, since the tab bar itself now only
    -- shows short codes (TAB_SHORT_LABELS). Styled via a new, larger
    -- style class (EpodTdSectionHeading) rather than reusing
    -- EpodTdHeader (that one's already claimed by the hub-name banner
    -- above the tab row).
    state.sectionHeadingLabel = gui.textView_create(nil, "", WINDOW_WIDTH, false)
    pcall(state.sectionHeadingLabel.setStyleClassList, state.sectionHeadingLabel, { "EpodTdSectionHeading" })
    layout:addItem(state.sectionHeadingLabel)

    state.simplePanels = {}

    for index, tabModule in ipairs(TABS) do

        if tabModule == tab_lines then

            state.linesPanel = buildLinesPanel()
            layout:addItem(state.linesPanel)

        elseif tabModule == tab_overview then

            local actionButtonCount = ACTION_BUTTON_COUNTS[tabModule] or 0
            local panel, rows, actionButtons = buildOverviewPanel("centralRaw.panel." .. tostring(index), actionButtonCount)

            layout:addItem(panel)

            state.simplePanels[index] = { panel = panel, rows = rows, actionButtons = actionButtons }

        else

            local actionButtonCount = ACTION_BUTTON_COUNTS[tabModule] or 0
            local panel, rows, actionButtons = buildSimplePanel("centralRaw.panel." .. tostring(index), actionButtonCount)

            layout:addItem(panel)

            state.simplePanels[index] = { panel = panel, rows = rows, actionButtons = actionButtons }

        end

    end

    -- Decision 168: added to `layout` directly (the window's own root
    -- box), NOT inside any per-tab panel above -- so it stays visible
    -- across every tab, exactly like the tab bar and section heading
    -- already do, instead of disappearing whenever the player switches
    -- away from whichever tab happened to be running something.
    state.statusLabel = gui.textView_create(nil, "", WINDOW_WIDTH, false)
    pcall(state.statusLabel.setStyleClassList, state.statusLabel, { "EpodTdMutedText" })
    layout:addItem(state.statusLabel)

    local window = gui.window_create(nil, "Central Manager", layout)

    window:onClose(function()
        state.closedByUser = true
        state.visible = false
        log.info("GUI CENTRAL RAW: window closed by user.")
    end)

    -- Player's request: open top-left, and lock the width so switching
    -- tabs/pages doesn't keep resizing the window (a wide SERVICES row
    -- or a LINES page with more destinations no longer makes the whole
    -- window jump width -- content wraps/clips to this fixed width
    -- instead). game.gui.getContentRect("mainView") is the same real,
    -- shipped-code-confirmed call guidesystem.lua itself uses for
    -- screen-relative positioning -- an index-based {x,y,width,height}
    -- table (confirmed by guidesystem.lua's own screenSize[3]/[4]
    -- usage), not the raw system's own named-field getContentRect().
    local margin = 20

    pcall(window.setPosition, window, margin, margin)

    local okScreenRect, screenRect = pcall(game.gui.getContentRect, "mainView")

    log.info(
        "GUI CENTRAL RAW: screenRect lookup ok=" .. tostring(okScreenRect)
        .. " value=" .. tostring(screenRect)
        .. (screenRect ~= nil and (" [1]=" .. tostring(screenRect[1]) .. " [2]=" .. tostring(screenRect[2]) .. " [3]=" .. tostring(screenRect[3]) .. " [4]=" .. tostring(screenRect[4])) or "")
    )

    if okScreenRect and screenRect ~= nil and screenRect[3] ~= nil then

        -- Decision 136: LIVE-CONFIRMED -- setMinimumSize/setMaximumSize
        -- both reported ok=true against the correct screen values
        -- (3840x2400 -> halfWidth 1920) yet had ZERO visible effect on
        -- this window's actual rendered width. Switched to setSize --
        -- a direct "set the current size to this" call rather than a
        -- negotiated min/max range, which this window type apparently
        -- doesn't respect for its own auto-computed size.
        --
        -- Decision 177: player's live complaint -- 60% of screen width
        -- (the original choice above) rendered close to full-screen on
        -- a wide monitor, while this window's real widest content
        -- (CONTENT_FIT_WIDTH, computed above from known constants) is
        -- nowhere near that big. Replaced the screen-percentage guess
        -- with that real content-derived width -- clamped to 90% of
        -- screen width only as a sanity floor for an unusually narrow
        -- screen, not as the normal driver of the number any more.
        --
        -- Decision 180: HEIGHT now gets the exact same treatment,
        -- locked to CONTENT_FIT_HEIGHT once here, for the SAME reason
        -- and the same way, instead of the per-tab calcMinimumSize
        -- dance (Decisions 175/178/179) that kept producing
        -- inconsistent results across different tabs/content amounts.
        -- Both width and height are now ONE fixed value for the whole
        -- window's lifetime -- never recomputed on tab switch, exactly
        -- mirroring width's own original anti-jump rule (Decision 136).
        local lockedWidth = math.min(CONTENT_FIT_WIDTH, screenRect[3] * 0.9)
        local lockedHeight = math.min(CONTENT_FIT_HEIGHT, (screenRect[4] or 2000) * 0.9)

        local okSize, errSize = window.setSize(window, lockedWidth, lockedHeight)

        -- Kept as a secondary attempt alongside setSize, not instead
        -- of it -- costs nothing since both already report success
        -- with no observed downside, and might still matter for
        -- manual-resize bounds even if they don't drive initial size.
        window.setMinimumSize(window, lockedWidth, lockedHeight)
        window.setMaximumSize(window, lockedWidth, lockedHeight)

        log.info(
            "GUI CENTRAL RAW: size lock lockedWidth=" .. tostring(lockedWidth)
            .. " lockedHeight=" .. tostring(lockedHeight)
            .. " setSize ok=" .. tostring(okSize) .. " err=" .. tostring(errSize)
        )

    end

    state.window = window

    return window

end


-- Decision 135: LIVE-CONFIRMED BUG -- "after closing the 1st time, DD
-- refused to reopen." `window:close()` is a genuinely destructive
-- close (unlike setVisible), so the window object left in state.window
-- was dead; the next call's `ensureWindow` just returned that same
-- dead reference (state.window ~= nil short-circuits it) with no way
-- to actually show anything again. setVisible is the correct,
-- reversible toggle here -- the exact mechanism gui_experiment.lua's
-- OWN toggleVisibility already uses successfully
-- (`state.window:setVisible(not currentlyVisible, false)`), and the
-- same one this whole accordion feature is built on. The native X
-- button still works via addHideOnCloseHandler (Decision 134) -- that
-- hides, it doesn't destroy, so it stays compatible with this model.
function M.toggleVisibility(hubStationGroupId)

    local window = ensureWindow(hubStationGroupId)

    if window == nil then
        log.info("GUI CENTRAL RAW: could not create window.")
        return
    end

    state.visible = not state.visible
    state.closedByUser = not state.visible

    pcall(window.setVisible, window, state.visible)

    if state.visible then
        selectTab(state.activeTabIndex, hubStationGroupId)
    end

end


-- Decision 134: no longer called from anywhere -- the window now opens
-- only via its own toolbar button (ensureToolbarButton/
-- M.toggleVisibility), per the player's explicit preference. Left
-- defined (unreachable) rather than deleted, same contract as
-- gui_manager.M.ensureVisible, in case a hybrid auto-open-plus-toolbar
-- design is ever wanted later.
function M.ensureVisible(hubStationGroupId)

    if state.visible then
        return
    end

    if state.closedByUser then
        return
    end

    local window = ensureWindow(hubStationGroupId)

    if window == nil then
        return
    end

    state.visible = true

    selectTab(state.activeTabIndex, hubStationGroupId)

end


-- Called once per fresh station selection (not every guiUpdate tick) --
-- resets closedByUser so a new selection reopens the window even if
-- the player closed it while looking at a different station. Same
-- contract as gui_manager.M.onStationSelected.
function M.onStationSelected(hubStationGroupId)

    state.closedByUser = false

    M.ensureVisible(hubStationGroupId)

end


return M
