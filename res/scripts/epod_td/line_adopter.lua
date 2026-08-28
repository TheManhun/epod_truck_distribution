local log = require("epod_td.log")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local managed_registry = require("epod_td.managed_registry")
local line_ownership = require("epod_td.line_ownership")
local industry_naming = require("epod_td.industry_naming")

local M = {}


-- ============================================================
-- AUTOMATIC NEW-LINE DETECTION AND ADOPTION
--
-- IDEAS.md "Automatic Network Change Detection" / PROGRESS.md Not
-- Started #5, finally built after two manual proof-of-concept
-- adoptions tonight (Grain, Hendon East - Main Street) both worked by
-- renaming a brand-new player-created line with the "● " prefix by
-- hand and waiting for managed_registry.migrateAndValidate() to pick
-- it up. This closes that manual step: any road/truck line touching
-- the hub that isn't already in the persistent registry gets renamed
-- to match the hub's own naming convention (line_splitter.lua's
-- "● <hub> ↔ <destination>") and registered directly, with no player
-- action required. Scope decision (explicit, player-confirmed):
-- anything touching the hub is swept in, no opt-out yet -- a per-line
-- "leave this one alone" toggle (e.g. a "○" prefix, or a confirmation
-- popup -- "New line detected at <hub>, auto-manage it?") is a
-- follow-up, not built here.
--
-- TWO THINGS THIS FILE ASSUMES BUT HAS NOT YET LIVE-CONFIRMED --
-- flagged rather than silently trusted, per this project's
-- evidence-first rule:
--
--   1. api.cmd.make.setName is LIVE-CONFIRMED on a VEHICLE entity
--      (fleet_naming.lua, route_injector.lua) but has never been
--      tried against a LINE entity in this codebase -- every line so
--      far got its name baked in at api.cmd.make.createLine time
--      (line_splitter.lua), never renamed after the fact. If setName
--      fails/no-ops on a LINE, the rename step below will log it
--      plainly. Registration does NOT depend on the rename
--      succeeding (Decision 22/26: the persistent registry, not the
--      name, is the real authority) -- so adoption still works, just
--      without the cosmetic "●" match, if this turns out unsupported.
--
--   2. vehicles.getManagedLinesForStation() only returns lines it can
--      classify as ROAD (i.e. at least one currently-assigned
--      vehicle to check the carrier of -- see classifyLineCarrier).
--      A line created with literally zero vehicles will not appear
--      here until the player assigns at least one -- same constraint
--      the panel display already has. Matches the real workflow seen
--      tonight (both Grain and Hendon East already had vehicles
--      before being noticed), not a new gap introduced here.
-- ============================================================

-- LIVE-CONFIRMED BUG (real screenshot, first adoption of a genuinely
-- new line): vehicles.getManagedLinesForStation's destinations list
-- deliberately INCLUDES the hub's own stop (added so the panel could
-- show real return-direction demand -- see that file's comment), but
-- that means it isn't safe to use unfiltered as "everywhere this line
-- goes other than the hub" the way line_splitter.lua's naming always
-- assumes. Unfiltered, "Hendon East ↔ School Lane" came out as
-- "Hendon East ↔ Hendon East + School Lane". Filtering out any
-- destination whose stationGroup matches the hub fixes it.
-- Player's idea: a line that genuinely chains through multiple
-- industries (coal -> steel -> hub) gets its own naming convention
-- instead of the ordinary "+"-joined destination list -- "●*" marks
-- it as both a managed line ("●") AND industry-linked ("*", matching
-- industry_naming.lua's own station-naming prefix), so it reads as
-- distinct from an ordinary adopted line at a glance. See
-- industry_naming.buildChainName's own header for why this is
-- proximity-based, not a real cargo audit.
local function buildAdoptedLineName(hubStationGroup, hubName, destinations)

    local okChain, chainName =
        pcall(industry_naming.buildChainName, destinations, hubStationGroup)

    if okChain and chainName ~= nil then
        return "●* " .. chainName .. " <-> " .. tostring(hubName)
    end

    local destinationNames = {}

    for _, destination in ipairs(destinations) do

        if destination.stationGroup ~= hubStationGroup then
            destinationNames[#destinationNames + 1] = destination.name
        end

    end

    local destinationText =
        #destinationNames > 0
            and table.concat(destinationNames, " + ")
            or "Unknown"

    return "● " .. tostring(hubName) .. " ↔ " .. destinationText

end


local function processAdoptNext(candidates, hubStationGroup, hubName, index, adoptedCount, onComplete)

    local candidate = candidates[index]

    if candidate == nil then

        log.info("----------------------------------------")

        log.info(
            "LINE ADOPTION COMPLETE: "
                .. tostring(adoptedCount)
                .. " of "
                .. tostring(#candidates)
                .. " new line(s) adopted."
        )

        log.info("----------------------------------------")

        if onComplete ~= nil then
            onComplete(adoptedCount)
        end

        return

    end

    local newName =
        buildAdoptedLineName(hubStationGroup, hubName, candidate.destinations)

    log.info(
        "LINE ADOPTION: new line detected -- \""
            .. tostring(candidate.name)
            .. "\" (id=" .. tostring(candidate.id) .. ") -> \""
            .. newName .. "\""
    )

    local function finishThisCandidate()
        managed_registry.register(candidate.id)
        line_ownership.claim(candidate.id, hubStationGroup)
        processAdoptNext(candidates, hubStationGroup, hubName, index + 1, adoptedCount + 1, onComplete)
    end

    local okCommand, commandOrError =
        pcall(
            api.cmd.make.setName,
            candidate.id,
            newName
        )

    if not okCommand then

        log.info(
            "LINE ADOPTION: setName command error for line "
                .. tostring(candidate.id)
                .. " (registering anyway, unrenamed): "
                .. tostring(commandOrError)
        )

        finishThisCandidate()
        return

    end

    local okSend, sendErr =
        pcall(
            function()

                api.cmd.sendCommand(
                    commandOrError,

                    function(cmd, success)

                        log.info(
                            "LINE ADOPTION: rename result for line "
                                .. tostring(candidate.id)
                                .. ": " .. tostring(success)
                        )

                        finishThisCandidate()

                    end
                )

            end
        )

    if not okSend then

        log.info(
            "LINE ADOPTION: setName send error for line "
                .. tostring(candidate.id)
                .. " (registering anyway, unrenamed): "
                .. tostring(sendErr)
        )

        finishThisCandidate()

    end

end


-- Scans every road/truck line touching hubStationGroup and adopts any
-- that isn't already in the persistent registry. Safe to call
-- repeatedly -- lines already registered are skipped every time.
function M.detectAndAdopt(hubStationGroup, onComplete)

    if hubStationGroup == nil then

        if onComplete ~= nil then
            onComplete(0)
        end

        return

    end

    local hubName = stations.getEntityName(hubStationGroup)

    local touchingLines =
        vehicles.getManagedLinesForStation(hubStationGroup)

    local candidates = {}

    for _, lineInfo in ipairs(touchingLines) do

        if not managed_registry.isManaged(lineInfo.id) then
            candidates[#candidates + 1] = lineInfo
        end

    end

    if #candidates == 0 then

        if onComplete ~= nil then
            onComplete(0)
        end

        return

    end

    log.info("----------------------------------------")

    log.info(
        "LINE ADOPTION: " .. tostring(#candidates)
            .. " unmanaged line(s) touching \"" .. tostring(hubName)
            .. "\" -- adopting automatically."
    )

    processAdoptNext(candidates, hubStationGroup, hubName, 1, 0, onComplete)

end


return M
