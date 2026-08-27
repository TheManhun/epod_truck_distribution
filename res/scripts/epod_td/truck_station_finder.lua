local industry_naming = require("epod_td.industry_naming")
local hub_registry = require("epod_td.hub_registry")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local log = require("epod_td.log")

local M = {}


-- ============================================================
-- TRUCK STATION FINDER
--
-- Production version of the DEBUG "Truck Station Survey" probe
-- (epod_truck_distribution.lua) that proved every piece of this live
-- on a real 250-year savegame -- see Decisions 148/149/150. Every
-- field read here is the SAME one confirmed there, not a fresh guess:
--
--   - game.interface.getEntity(stationEntity), NOT the raw STATION
--     component (api.engine.getComponent), carries .cargo, .carriers,
--     .stationGroup, and .town. The raw component only ever exposed
--     .cargo (matches official docs) and isn't even enumerable via
--     pairs() -- opaque userdata, not a plain table.
--   - api.engine.system.lineSystem.getLineStops(stationGroupEntity)
--     itself returns engine-side userdata (type() == "userdata"), not
--     a Lua table -- iterate with pairs(), not ipairs(), and don't
--     gate on type(...) == "table" first (that silently skipped
--     iteration entirely on the first live attempt). Its entries are
--     plain line-entity numbers, not {lineEntity, stopIndex} pairs as
--     the official doc text implied.
--   - vehicles.getVehiclesForLine and industry_naming.findNearest
--     Industry are this mod's own, already-proven-live helpers.
--
-- Deliberately NOT cached or throttled inside this module -- a full-
-- map stationSystem.forEach scan is real work (223 stations on the
-- test save, each doing a line-stop walk + industry-proximity search).
-- M.scan() is meant to be called only on an explicit player action
-- (opening the list, clicking Refresh, or right after a hub toggle
-- completes) -- see gui_tab_overview.lua's own caching of the last
-- result. Never wire this into something that runs every guiUpdate
-- tick.
-- ============================================================

function M.scan()

    local results = {}
    local seenGroups = {}

    local ok, err =
        pcall(function()

            api.engine.system.stationSystem.forEach(function(stationEntity)

                local entity
                pcall(function() entity = game.interface.getEntity(stationEntity) end)

                if entity == nil or entity.cargo ~= true then
                    return
                end

                local carriers = entity.carriers

                if type(carriers) ~= "table" or carriers.ROAD ~= true then
                    return
                end

                local stationGroupId = entity.stationGroup

                if type(stationGroupId) ~= "number"
                    or stationGroupId < 0
                    or seenGroups[stationGroupId]
                then
                    return
                end

                seenGroups[stationGroupId] = true

                local name = "?"
                pcall(function() name = stations.getEntityName(stationGroupId) or "?" end)

                local isHub = false
                pcall(function() isHub = hub_registry.isEnabled(stationGroupId) end)

                local townName = nil

                if entity.town ~= nil then
                    pcall(function() townName = stations.getEntityName(entity.town) end)
                end

                local industryName = nil

                pcall(function()

                    local groupEntity = game.interface.getEntity(stationGroupId)

                    if groupEntity ~= nil and groupEntity.position ~= nil then
                        local _, foundName = industry_naming.findNearestIndustry(groupEntity.position)
                        industryName = foundName
                    end

                end)

                local lineCount = 0
                local vehicleCount = 0

                pcall(function()

                    local lineStops = api.engine.system.lineSystem.getLineStops(stationGroupId)
                    local seenLines = {}

                    for _, stopEntry in pairs(lineStops) do

                        local lineEntity =
                            (type(stopEntry) == "table" and stopEntry[1])
                                or (type(stopEntry) == "number" and stopEntry)
                                or nil

                        if type(lineEntity) == "number" and not seenLines[lineEntity] then

                            seenLines[lineEntity] = true
                            lineCount = lineCount + 1

                            local ok2, vehicleIds = pcall(vehicles.getVehiclesForLine, lineEntity)

                            if ok2 and vehicleIds ~= nil then
                                vehicleCount = vehicleCount + #vehicleIds
                            end

                        end

                    end

                end)

                results[#results + 1] = {
                    stationGroupId = stationGroupId,
                    name = name,
                    townName = townName,
                    isHub = isHub,
                    industryName = industryName,
                    lineCount = lineCount,
                    vehicleCount = vehicleCount
                }

            end)

        end)

    if not ok then
        log.info("TRUCK STATION FINDER: scan failed: " .. tostring(err))
        return {}
    end

    -- Player's own requests: "with the ones with cities at top" (read
    -- as grouping by city name -- every station sampled live resolved
    -- a real town) and "prioritise ones with more than one line" --
    -- within a city, highest line count first, then busiest (most
    -- allocated trucks), station name as the final tiebreaker. A
    -- station with no resolvable town (not seen in live testing, but
    -- not impossible) sorts after every named city rather than
    -- crashing the compare.
    table.sort(results, function(a, b)

        local townA = a.townName or "\255\255\255"
        local townB = b.townName or "\255\255\255"

        if townA ~= townB then
            return townA < townB
        end

        if a.lineCount ~= b.lineCount then
            return a.lineCount > b.lineCount
        end

        if a.vehicleCount ~= b.vehicleCount then
            return a.vehicleCount > b.vehicleCount
        end

        return tostring(a.name) < tostring(b.name)

    end)

    return results

end


return M
