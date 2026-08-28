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

                -- Player's question: can a "drop-off only" station (a
                -- small roadside stop, no real cargo yard -- e.g.
                -- "Barking Industrial") be told apart from a real full
                -- truck station (e.g. "Barking Machines factory")?
                -- Neither the raw STATION component nor getEntity()'s
                -- own fields (cargo/carriers/stationGroup/town/position/
                -- name/type/id -- Decisions 148-150) carry anything
                -- resembling a capacity flag, so the difference, if
                -- detectable at all, is a CONSTRUCTION-level one (which
                -- physical building was placed), not a station-data one.
                -- Same exact proven chain `industry_recipes.lua`'s
                -- `getIndustryFileName` already uses for factories
                -- (there via getConstructionEntityForSimBuilding) --
                -- here via the station-specific equivalent, confirmed
                -- real via AI Builder's own reference source.
                local fileName = nil

                pcall(function()

                    local constructionId =
                        api.engine.system.streetConnectorSystem.getConstructionEntityForStation(stationEntity)

                    if constructionId ~= nil and constructionId >= 0 then

                        local construction =
                            api.engine.getComponent(constructionId, api.type.ComponentType.CONSTRUCTION)

                        if construction ~= nil then
                            fileName = construction.fileName
                        end

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
                    vehicleCount = vehicleCount,
                    fileName = fileName
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


-- ============================================================
-- LIGHTWEIGHT SINGLE-STATION DROP-OFF CHECK
--
-- M.scan() above is a full-map enumeration (223 stations on the test
-- save) -- far too expensive to call once per destination on every
-- LINES tab refresh (which runs every guiUpdate tick). This is the
-- cheap, single-station equivalent: given a stationGroupId (exactly
-- what a line destination already carries), read ONE station out of
-- its group and check whether IT has a construction entity, same
-- fileName-presence signal Decision 157 already proved distinguishes
-- real cargo stations from drop-off/auto-generated ones.
--
-- `STATION_GROUP.stations` (the array of individual station entities
-- belonging to a group) was unproven live in THIS mod when this
-- function was first written -- confirmed live via a capped
-- diagnostic (removed now that it served its purpose; see Decisions
-- 160/163's live-confirmed "[D] Bedford Industrial" result).
-- ============================================================

function M.isDropOffStation(stationGroupId)

    if type(stationGroupId) ~= "number" or stationGroupId < 0 then
        return nil
    end

    local isDropOff = nil

    pcall(function()

        local groupComponent =
            api.engine.getComponent(stationGroupId, api.type.ComponentType.STATION_GROUP)

        if groupComponent == nil
            or groupComponent.stations == nil
            or groupComponent.stations[1] == nil
        then
            return
        end

        local firstStationId = groupComponent.stations[1]

        local constructionId =
            api.engine.system.streetConnectorSystem.getConstructionEntityForStation(firstStationId)

        isDropOff = (constructionId == nil or constructionId < 0)

    end)

    return isDropOff

end


return M
