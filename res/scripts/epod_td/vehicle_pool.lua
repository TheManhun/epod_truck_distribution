local log = require("epod_td.log")
local vehicles = require("epod_td.vehicles")

local M = {}


-- ============================================================
-- TRUCK POOL (Decision 187)
--
-- Player's own idea: "I want to send excess trucks to the depo... then
-- other hubs could call them if they need them." The first genuinely
-- CROSS-HUB feature in this mod -- every other action (Split, Assign &
-- Balance, Push Full Reallocation, Fleet Needs) is deliberately hub-
-- scoped, with real guard code elsewhere (line_ownership.lua, Decisions
-- 45/48) specifically written to stop one hub's actions leaking into
-- another's. This is a deliberate, explicit exception to that rule, so
-- it stays narrow and player-triggered on both ends (send and pull),
-- never automatic.
--
-- Real, proven mechanics, not guesses:
--   * vehicles.sendToDepot (Decision 187) -- api.cmd.make.sendToDepot,
--     confirmed real by reading Line Manager's own source (Workshop
--     2581894757) -- sends a vehicle to its NEAREST depot automatically.
--     This mod never computes depot distance/location itself.
--   * vehicles.setLine -- already proven throughout this codebase for
--     ordinary cross-line reassignment (dispatcher.lua, fleet_
--     allocator.lua, line_splitter.lua) -- reassigning a parked pool
--     vehicle to a brand new line needs nothing extra on top of that.
--
-- PERSISTENCE: same direct-file-I/O, fresh-read-every-call, validate-
-- on-load pattern hub_registry.lua/managed_registry.lua/line_ownership.
-- lua all already use (Decision 35's multi-instance bug is the reason
-- none of those cache in a module-level table, and this file follows
-- suit). A stored entry whose vehicle no longer exists, or is no
-- longer actually empty (someone/something else put it back to work),
-- is silently dropped on the next read rather than trusted blindly.
-- ============================================================

local STATE_FILE_PATH = "epod_td_vehicle_pool.txt"


-- One line per pooled vehicle: vehicleId|sourceHubId|sentAtGameTime|
-- cargoType1,cargoType2,... -- cargo types stored/compared as plain
-- strings (tostring on both ends) since this project has never
-- confirmed whether the game's own cargo-type keys are numbers or
-- strings, and string comparison works safely either way.
local function loadStateFromDisk()

    local ok, result =
        pcall(function()

            local file = io.open(STATE_FILE_PATH, "r")

            if file == nil then
                return {}
            end

            local content = file:read("*a")
            file:close()

            local entries = {}

            for line in content:gmatch("[^\r\n]+") do

                local vehicleIdStr, sourceHubIdStr, sentAtStr, cargoTypesStr =
                    line:match("^(%-?%d+)|(%-?%d+)|(%-?%d+)|(.*)$")

                if vehicleIdStr ~= nil then

                    local cargoTypes = {}

                    for cargoType in tostring(cargoTypesStr or ""):gmatch("[^,]+") do
                        cargoTypes[#cargoTypes + 1] = cargoType
                    end

                    entries[#entries + 1] = {
                        vehicleId = tonumber(vehicleIdStr),
                        sourceHubId = tonumber(sourceHubIdStr),
                        sentAtGameTime = tonumber(sentAtStr),
                        cargoTypes = cargoTypes
                    }

                end

            end

            return entries

        end)

    if ok and result ~= nil then
        return result
    end

    return {}

end


local function saveStateToDisk(entries)

    pcall(function()

        local file = io.open(STATE_FILE_PATH, "w")

        if file == nil then
            return
        end

        for _, entry in ipairs(entries) do

            file:write(
                tostring(entry.vehicleId) .. "|"
                    .. tostring(entry.sourceHubId) .. "|"
                    .. tostring(entry.sentAtGameTime) .. "|"
                    .. table.concat(entry.cargoTypes, ",")
                    .. "\n"
            )

        end

        file:close()

    end)

end


-- Drops any entry whose vehicle no longer exists, or is no longer
-- actually empty -- same validate-on-load discipline hub_registry.lua
-- already uses for hub IDs. Cheap enough to run every read (typically
-- a handful of pooled vehicles at most).
local function loadAndValidate()

    local entries = loadStateFromDisk()

    local validEntries = {}
    local changed = false

    for _, entry in ipairs(entries) do

        local vehicle = vehicles.get(entry.vehicleId)

        if vehicle == nil then

            log.info(
                "VEHICLE POOL: dropping stale entry for vehicle "
                    .. tostring(entry.vehicleId)
                    .. " (no longer a real vehicle -- different save, "
                    .. "sold, or removed)"
            )

            changed = true

        elseif vehicles.isVehicleEmpty(entry.vehicleId) ~= true then

            log.info(
                "VEHICLE POOL: dropping entry for vehicle "
                    .. tostring(entry.vehicleId)
                    .. " (no longer empty -- already back in service by "
                    .. "other means)"
            )

            changed = true

        else
            validEntries[#validEntries + 1] = entry
        end

    end

    if changed then
        saveStateToDisk(validEntries)
    end

    return validEntries

end


-- Sends a real, confirmed-empty vehicle to its nearest depot and
-- records it in the pool. Caller is responsible for confirming the
-- vehicle is actually a sensible one to give up (this module doesn't
-- second-guess which vehicle a hub chooses to release).
function M.sendToPool(vehicleId, sourceHubId, onComplete)

    onComplete = onComplete or function() end

    if vehicles.isVehicleEmpty(vehicleId) ~= true then

        log.info(
            "VEHICLE POOL: refused to pool vehicle "
                .. tostring(vehicleId)
                .. " -- not confirmed empty."
        )

        onComplete(false)
        return

    end

    local okCargoTypes, cargoTypes = pcall(vehicles.getCompatibleCargoTypes, vehicleId)

    local cargoTypeStrings = {}

    if okCargoTypes and cargoTypes ~= nil then

        for _, cargoType in ipairs(cargoTypes) do
            cargoTypeStrings[#cargoTypeStrings + 1] = tostring(cargoType)
        end

    end

    local okGameTime, gameTimeMs =
        pcall(function()
            return game.interface.getGameTime().time
        end)

    -- Same hold (setManualDeparture) -> real command -> release sequence
    -- every other vehicle reassignment in this codebase already uses
    -- (dispatcher.lua's own moveOneVehicle) -- avoids the vehicle
    -- departing mid-reassignment.
    vehicles.setManualDeparture(vehicleId, true, function(holdSuccess)

        if not holdSuccess then

            log.info("VEHICLE POOL: could not hold vehicle " .. tostring(vehicleId) .. " -- skipped.")
            onComplete(false)
            return

        end

        vehicles.sendToDepot(
            vehicleId,
            false,

            function(success)

                vehicles.setManualDeparture(vehicleId, false, function()

                    if not success then

                        log.info("VEHICLE POOL: sendToDepot command failed for vehicle " .. tostring(vehicleId))
                        onComplete(false)
                        return

                    end

                    local entries = loadAndValidate()

                    entries[#entries + 1] = {
                        vehicleId = vehicleId,
                        sourceHubId = sourceHubId,
                        sentAtGameTime = (okGameTime and gameTimeMs) or 0,
                        cargoTypes = cargoTypeStrings
                    }

                    saveStateToDisk(entries)

                    log.info(
                        "VEHICLE POOL: sent vehicle " .. tostring(vehicleId)
                            .. " to pool from hub " .. tostring(sourceHubId)
                            .. "."
                    )

                    onComplete(true)

                end)

            end
        )

    end)

end


-- Returns the first pooled entry compatible with cargoType, or nil.
-- Real-validated (loadAndValidate) every call -- never trusts a stale
-- on-disk record.
function M.findPoolVehicleForCargoType(cargoType)

    local cargoTypeString = tostring(cargoType)

    for _, entry in ipairs(loadAndValidate()) do

        for _, entryCargoType in ipairs(entry.cargoTypes) do

            if entryCargoType == cargoTypeString then
                return entry
            end

        end

    end

    return nil

end


local function finishClaim(vehicleId, targetLineId, success, onComplete)

    if not success then

        log.info(
            "VEHICLE POOL: claim failed for vehicle "
                .. tostring(vehicleId)
                .. " -> line " .. tostring(targetLineId)
        )

        onComplete(false)
        return

    end

    local entries = loadAndValidate()
    local remaining = {}

    for _, entry in ipairs(entries) do

        if entry.vehicleId ~= vehicleId then
            remaining[#remaining + 1] = entry
        end

    end

    saveStateToDisk(remaining)

    log.info(
        "VEHICLE POOL: claimed vehicle " .. tostring(vehicleId)
            .. " for line " .. tostring(targetLineId)
            .. "."
    )

    onComplete(true)

end


-- Reassigns a pooled vehicle to a real target line -- no buy, no depot
-- lookup needed, the exact same vehicles.setLine cross-line
-- reassignment this codebase already does constantly elsewhere.
-- Removes the entry from the pool on success; leaves it pooled on
-- failure so it can be retried.
function M.claimFromPool(vehicleId, targetLineId, onComplete)

    onComplete = onComplete or function() end

    -- Same hold -> setLine -> release sequence as dispatcher.lua's own
    -- moveOneVehicle -- stopIndex 0, matching that proven call shape
    -- exactly (not nil, which has never been tested against this API).
    vehicles.setManualDeparture(vehicleId, true, function(holdSuccess)

        if not holdSuccess then

            log.info("VEHICLE POOL: could not hold vehicle " .. tostring(vehicleId) .. " -- claim skipped.")
            onComplete(false)
            return

        end

        vehicles.setLine(vehicleId, targetLineId, 0, function(setLineSuccess)

            vehicles.setManualDeparture(vehicleId, false, function()
                finishClaim(vehicleId, targetLineId, setLineSuccess, onComplete)
            end)

        end)

    end)

end


function M.getPoolSize()
    return #loadAndValidate()
end


function M.getPoolEntries()
    return loadAndValidate()
end


return M
