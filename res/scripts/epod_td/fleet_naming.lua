local log = require("epod_td.log")
local lines = require("epod_td.lines")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local managed_registry = require("epod_td.managed_registry")

local M = {}


-- ============================================================
-- RENAME MANAGED FLEET TO HUB IDENTITY
--
-- IDEAS.md "Vehicle Identity Naming and Fleet Colour-Coding": name a
-- DD-managed vehicle after its HOME HUB, not its current service --
-- a truck moves between Queens Road, Grain, The Grove etc. under the
-- pooled-fleet model, so a name tied to whichever line it's on right
-- now would go stale the moment it gets reassigned (the same lesson
-- already learned from the "●" line-name situation, Decision 26).
--
-- `setName` is now LIVE-CONFIRMED to work on a vehicle entity
-- (COMMANDS.md, tested via route_injector.testVehicleRenameAndColor
-- on vehicle 141339) -- this is the first REAL use of that finding,
-- not another disposable rename-then-restore test. Renamed vehicles
-- stay renamed; this is a deliberate, player-triggered action, never
-- automatic (Decision 4 / the player's own "stay in our lane"
-- feedback on automation).
--
-- Numbering: sequential 1..N based on current discovery order at the
-- moment this runs, not a stable per-vehicle ID that persists as the
-- fleet grows or shrinks. Simple and good enough for "which truck is
-- this" at a glance; re-running later will renumber everyone against
-- however many vehicles exist at that time. A stable, persisted
-- per-vehicle number is possible later (same io.open pattern as
-- managed_registry.lua/settings.lua) if the renumbering-on-rerun
-- behavior turns out to matter in practice -- not built now since
-- there's no evidence yet that it needs to be.
-- ============================================================

-- LIVE-CONFIRMED BUG, caught before shipping: without checking which
-- hub a managed line actually touches, this would collect vehicles
-- from EVERY managed line game-wide, not just this hub's -- harmless
-- today with one hub in play, but would silently rename another
-- hub's fleet too the moment a second hub exists. Every managed line
-- has exactly one stop matching its own hub (Decision 19/20's
-- one-line-per-destination model), so checking for that stop scopes
-- this correctly.
local function lineTouchesHub(lineId, hubStationGroup)

    local line = lines.get(lineId)
    local stops = line ~= nil and lines.safeField(line, "stops") or nil
    local stopCount = lines.safeLength(stops)

    for index = 1, stopCount do

        local stop = stops[index]

        if stop ~= nil then

            local stationGroup = lines.safeField(stop, "stationGroup")

            if stationGroup == hubStationGroup then
                return true
            end

        end

    end

    return false

end


local function collectManagedVehicleIds(hubStationGroup)

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    local vehicleIds = {}

    if not ok or allLineIds == nil then
        return vehicleIds
    end

    for _, lineId in ipairs(allLineIds) do

        if managed_registry.isManaged(lineId)
            and lineTouchesHub(lineId, hubStationGroup)
        then

            local lineVehicleIds =
                vehicles.getVehiclesForLine(lineId)

            for _, vehicleId in ipairs(lineVehicleIds) do
                vehicleIds[#vehicleIds + 1] = vehicleId
            end

        end

    end

    return vehicleIds

end


local function processRenameNext(vehicleIds, hubName, digitWidth, index, renamedCount, onComplete)

    local vehicleId = vehicleIds[index]

    if vehicleId == nil then

        log.info("----------------------------------------")

        log.info(
            "FLEET RENAME COMPLETE: "
                .. tostring(renamedCount)
                .. " of "
                .. tostring(#vehicleIds)
                .. " vehicle(s) renamed."
        )

        log.info("----------------------------------------")

        if onComplete ~= nil then
            onComplete(renamedCount)
        end

        return

    end

    -- Zero-padded, no parentheses -- requested live once a real
    -- fleet showed the plain-number version sorting as text in
    -- TF2's own vehicle list (Fleet 10-19 landing before Fleet 2).
    -- Width is based on the actual fleet size so small fleets don't
    -- carry pointless leading zeros (9 vehicles -> width 1) while
    -- large ones sort correctly (118 vehicles -> width 3, "001").
    local newName =
        "● "
            .. tostring(hubName)
            .. " - Fleet "
            .. string.format("%0" .. tostring(digitWidth) .. "d", index)

    local okCommand, commandOrError =
        pcall(
            api.cmd.make.setName,
            vehicleId,
            newName
        )

    if not okCommand then

        log.info(
            "FLEET RENAME: setName command error for vehicle "
                .. tostring(vehicleId)
                .. ": "
                .. tostring(commandOrError)
        )

        processRenameNext(vehicleIds, hubName, digitWidth, index + 1, renamedCount, onComplete)
        return

    end

    api.cmd.sendCommand(
        commandOrError,

        function(cmd, success)

            log.info(
                "FLEET RENAME: vehicle "
                    .. tostring(vehicleId)
                    .. " -> \""
                    .. newName
                    .. "\": "
                    .. tostring(success)
            )

            processRenameNext(
                vehicleIds,
                hubName,
                digitWidth,
                index + 1,
                success and (renamedCount + 1) or renamedCount,
                onComplete
            )

        end
    )

end


function M.renameFleetToHubIdentity(hubStationGroup, onComplete)

    log.info("----------------------------------------")
    log.info("RENAME FLEET TO HUB IDENTITY")
    log.info("----------------------------------------")

    local hubName =
        stations.getEntityName(hubStationGroup)

    local vehicleIds =
        collectManagedVehicleIds(hubStationGroup)

    if #vehicleIds == 0 then

        log.info("Nothing to do: no managed vehicles found at this hub.")

        if onComplete ~= nil then
            onComplete(0)
        end

        return { success = true, processedCount = 0 }

    end

    local digitWidth =
        #tostring(#vehicleIds)

    log.info(
        "Renaming "
            .. tostring(#vehicleIds)
            .. " vehicle(s) to \"● "
            .. tostring(hubName)
            .. " - Fleet "
            .. string.rep("0", digitWidth)
            .. "\" (zero-padded to "
            .. tostring(digitWidth)
            .. " digit(s))..."
    )

    processRenameNext(vehicleIds, hubName, digitWidth, 1, 0, onComplete)

    return { success = true, pending = true }

end


return M
