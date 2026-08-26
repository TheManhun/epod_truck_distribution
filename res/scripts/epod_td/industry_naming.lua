local log = require("epod_td.log")
local stations = require("epod_td.stations")
local hub_registry = require("epod_td.hub_registry")
local lines = require("epod_td.lines")
local managed_registry = require("epod_td.managed_registry")

local M = {}


-- ============================================================
-- AUTO-NAME NON-HUB TRUCK STATIONS AFTER THEIR NEAREST INDUSTRY
--
-- Player's idea, checked against two real Steam Workshop mods directly
-- rather than guessed at. "Auto Line Namer" (workshop 3360333659) is
-- NOT what it first looked like -- it renames whole LINES from town
-- names (api.engine.system.stationSystem.getTown), cargo types and
-- vehicle mode; no industry-proximity logic exists in it at all.
--
-- The real, working mechanism came from reading the "AI Builder"
-- traffic mod (workshop 2820656841) directly -- a large, real, live
-- mod that uses game.interface.getEntities({radius=N, pos=...},
-- {type="SIM_BUILDING", includeData=true}) extensively. Confirmed real
-- fields read off each returned entry throughout that mod's own code:
-- .name, .position, .id (e.g. ai_builder_base_util.lua lines 4563,
-- 6908, 7150, 7210; ai_builder_new_connections_evaluation.lua lines
-- 1086-1165). SIM_BUILDING is also the confirmed ComponentType (=27)
-- covering industries per api.type.md -- this is the type both
-- industries and town buildings share.
--
-- NOT YET LIVE-CONFIRMED (flagging honestly, per this project's own
-- evidence-first rule): the STATION-side fields below (.cargo,
-- .carriers.ROAD, .position, .stationGroup, .town) are confirmed real
-- from a genuine game.interface.getEntity(stationId) dump (Linemanager
-- mod's general.lua notes), but that was the singular getEntity call,
-- not getEntities' includeData path used here for the map-wide station
-- walk. Almost certainly the same shape (same interface family, same
-- pattern SIM_BUILDING already confirmed above) -- but needs a real
-- in-game log check before being trusted blindly.
--
-- TWO NAMING BRANCHES (player's own refinement after seeing the first
-- version -- a plain industry-proximity label with no way to tell
-- which hub, if any, a station actually serves, or to disambiguate
-- several stations near the same factory):
--
--   CONNECTED (a real managed line already links this station to a
--   hub): "* IndustryName <-> HubName - NN", NN a running count PER
--   (industry, hub) PAIR so several stations feeding the same factory
--   into the same hub are told apart. The "* " prefix visually marks
--   these as industry-linked, distinct from a hub's own "● " prefix.
--
--   NOT CONNECTED (no managed line ties this station to any hub yet):
--   "IndustryName - TownName" -- no "* " prefix, no hub reference
--   (there isn't one yet), uses the station's own nearest town instead
--   (STATION.town, confirmed field per the dump above) so the name is
--   still informative on its own.
--
-- Only ever touches stations that are NOT Distribution Hubs ("● "
-- prefix / hub_registry.isEnabled) and haven't already been touched by
-- this module ("* " prefix already present).
--
-- Persisted-processed-set file follows the exact same proven pattern
-- as hub_registry.lua (plain IDs, one per line, io.open, validated on
-- load) so a station is only ever evaluated once, not re-scanned on
-- every poll forever. KNOWN LIMITATION, accepted deliberately rather
-- than built around: a station evaluated before it has any line at all
-- gets the NOT-CONNECTED name permanently -- it is never retroactively
-- upgraded to the CONNECTED/hub-numbered name if a line links it to a
-- hub later. Same "good enough for now, not proven to need more" call
-- fleet_naming.lua already made about its own renumbering-on-rerun
-- behavior.
-- ============================================================

local STATE_FILE_PATH = "epod_td_industry_named_stations.txt"
local COUNTER_FILE_PATH = "epod_td_industry_hub_counters.txt"
local NAME_PREFIX = "* "

-- ai_builder's own isPointInsideIndustry treats ~120m as an
-- industry's own footprint radius (real comment: "industry is approx
-- 160 square, so worst case distance to center is hypot(80,80) ~
-- 120"). 150 gives a plain truck stop sitting just outside that
-- footprint room to still match its neighbour.
local INDUSTRY_SEARCH_RADIUS = 150


-- Two tags, not just a flat "seen" flag -- LIVE-CONFIRMED real bug
-- (player loaded an earlier save -- "save -3" -- and NOTHING renamed
-- at all, even stations that had never been touched in that save's
-- own timeline). Root cause: this file lives in the game install
-- folder, not per-save (same limitation hub_registry.lua already
-- documented), so a station renamed while testing on a LATER save
-- stays permanently marked "done" here even after loading an EARLIER
-- save where that rename never happened -- the in-game name rolls
-- back with the save, but this flat file did not.
--
-- RENAMED_TAG: this station got the durable, marker-bearing
-- "* Industry <-> Hub - NN" name. Validated on load against the
-- REAL live name (same "trust the save over a stale flag" principle
-- as hub_registry.lua's Decision 63) -- if the marker is gone, the
-- rename evidently didn't happen in this save's timeline, so the
-- entry is dropped and the station gets reconsidered fresh.
--
-- NONE_TAG: either no industry was ever found nearby, or the station
-- was never eligible at all (hub, wrong type, etc.) -- a property of
-- the physical map/station type, not of this save's line history, so
-- safe to remember permanently without a live-name check.
--
-- A third case -- eligible, industry found, but NOT YET connected to
-- a hub -- is deliberately NEVER persisted here at all (see
-- collectCandidates below): re-evaluated fresh every poll, since
-- "connected to a hub" is exactly the kind of thing that changes
-- as the player builds lines, and it has no stable marker to
-- validate against on load anyway.
local RENAMED_TAG = "renamed"
local NONE_TAG = "none"


local function loadProcessedSet()

    local processed = {}

    pcall(function()

        local file = io.open(STATE_FILE_PATH, "r")

        if file == nil then
            return
        end

        for line in file:lines() do

            local idText, tag = line:match("^(%-?%d+)\t(%a+)$")

            if idText ~= nil then
                processed[tonumber(idText)] = tag
            end

        end

        file:close()

    end)

    return processed

end


local function saveProcessedSet(processed)

    pcall(function()

        local file = io.open(STATE_FILE_PATH, "w")

        if file == nil then
            return
        end

        for id, tag in pairs(processed) do
            file:write(tostring(id) .. "\t" .. tostring(tag) .. "\n")
        end

        file:close()

    end)

end


local function loadAndValidateProcessedSet()

    local processed = loadProcessedSet()

    local changed = false

    for id, tag in pairs(processed) do

        if stations.getStationGroup(id) == nil then

            -- Same staleness guard as hub_registry.loadAndValidate:
            -- drops any stored ID that no longer resolves to a real
            -- STATION_GROUP (a different, unrelated save, or a
            -- since-removed station).
            processed[id] = nil
            changed = true

        elseif tag == RENAMED_TAG
            and stations.getRawEntityName(id):sub(1, #NAME_PREFIX) ~= NAME_PREFIX
        then

            processed[id] = nil
            changed = true

        end

    end

    if changed then
        saveProcessedSet(processed)
    end

    return processed

end


-- Counters keyed by "industryName\thubName", tab-separated on disk
-- (industry/hub names can contain spaces and hyphens, but not tabs).
-- Persisted the same io.open way as the rest of this file so numbering
-- keeps counting up across save/reload rather than resetting.
local function loadCounters()

    local counters = {}

    pcall(function()

        local file = io.open(COUNTER_FILE_PATH, "r")

        if file == nil then
            return
        end

        for line in file:lines() do

            local industryName, hubName, countText =
                line:match("^(.-)\t(.-)\t(%-?%d+)$")

            if industryName ~= nil then
                counters[industryName .. "\t" .. hubName] =
                    tonumber(countText)
            end

        end

        file:close()

    end)

    return counters

end


local function saveCounters(counters)

    pcall(function()

        local file = io.open(COUNTER_FILE_PATH, "w")

        if file == nil then
            return
        end

        for key, count in pairs(counters) do
            file:write(key .. "\t" .. tostring(count) .. "\n")
        end

        file:close()

    end)

end


local function distanceSquared(a, b)
    local dx = (a[1] or 0) - (b[1] or 0)
    local dy = (a[2] or 0) - (b[2] or 0)
    return dx * dx + dy * dy
end


-- Returns bestId, bestName for the nearest industry within
-- INDUSTRY_SEARCH_RADIUS, or nil, nil. Exposed as M.findNearestIndustry
-- below so industry_recipes.lua can pair a destination with the real
-- industry entity it needs (findNearestIndustryName keeps the
-- name-only shape every existing call site in this file already uses).
local function findNearestIndustry(position)

    local ok, industries =
        pcall(
            game.interface.getEntities,
            { radius = INDUSTRY_SEARCH_RADIUS, pos = position },
            { type = "SIM_BUILDING", includeData = true }
        )

    if not ok or industries == nil then
        return nil, nil
    end

    local bestId = nil
    local bestName = nil
    local bestDistanceSquared = nil

    for _, industry in pairs(industries) do

        if industry ~= nil
            and industry.position ~= nil
            and industry.name ~= nil
            and industry.id ~= nil
        then

            local candidateDistanceSquared =
                distanceSquared(position, industry.position)

            if bestDistanceSquared == nil
                or candidateDistanceSquared < bestDistanceSquared
            then
                bestDistanceSquared = candidateDistanceSquared
                bestId = industry.id
                bestName = industry.name
            end

        end

    end

    return bestId, bestName

end


local function findNearestIndustryName(position)
    local _, bestName = findNearestIndustry(position)
    return bestName
end


function M.findNearestIndustry(position)
    return findNearestIndustry(position)
end


local function findNearestEnabledHub(position, positionByStationGroup)

    local enabledHubs = hub_registry.getEnabledHubs()

    local bestHubId = nil
    local bestDistanceSquared = nil

    for _, hubStationGroupId in ipairs(enabledHubs) do

        local hubPosition = positionByStationGroup[hubStationGroupId]

        if hubPosition ~= nil then

            local candidateDistanceSquared =
                distanceSquared(position, hubPosition)

            if bestDistanceSquared == nil
                or candidateDistanceSquared < bestDistanceSquared
            then
                bestDistanceSquared = candidateDistanceSquared
                bestHubId = hubStationGroupId
            end

        end

    end

    return bestHubId

end


-- Is stationGroupId actually linked to hubStationGroupId by a real
-- managed line today? Same "walk every line, check its stops" shape
-- as fleet_naming.lineTouchesHub, just checking for two specific
-- stationGroups on the same line instead of one.
local function isStationConnectedToHub(stationGroupId, hubStationGroupId)

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then
        return false
    end

    for _, lineId in ipairs(allLineIds) do

        if managed_registry.isManaged(lineId) then

            local line = lines.get(lineId)
            local stops = line ~= nil and lines.safeField(line, "stops") or nil
            local stopCount = lines.safeLength(stops)

            local touchesStation = false
            local touchesHub = false

            for index = 1, stopCount do

                local stop = stops[index]

                if stop ~= nil then

                    local stopStationGroup =
                        lines.safeField(stop, "stationGroup")

                    if stopStationGroup == stationGroupId then
                        touchesStation = true
                    end

                    if stopStationGroup == hubStationGroupId then
                        touchesHub = true
                    end

                end

            end

            if touchesStation and touchesHub then
                return true
            end

        end

    end

    return false

end


local function getTownName(townId)

    if townId == nil or townId < 0 then
        return nil
    end

    local ok, townComponent =
        pcall(
            api.engine.getComponent,
            townId,
            api.type.ComponentType.NAME
        )

    if ok
        and townComponent ~= nil
        and type(townComponent.name) == "string"
    then
        return townComponent.name
    end

    return nil

end


local function isEligibleTruckStation(stationEntry, stationGroupId)

    if stationGroupId == nil or stationGroupId < 0 then
        return false
    end

    if hub_registry.isEnabled(stationGroupId) then
        return false
    end

    local rawName = stations.getRawEntityName(stationGroupId)

    if rawName:sub(1, 4) == "● " then
        return false
    end

    if rawName:sub(1, #NAME_PREFIX) == NAME_PREFIX then
        return false
    end

    if stationEntry == nil or stationEntry.cargo ~= true then
        return false
    end

    local carriers = stationEntry.carriers

    return carriers ~= nil and carriers.ROAD == true

end


-- Returns newName, persistTag. persistTag tells the caller how (or
-- whether) to remember this outcome in the persisted processed-set:
--   RENAMED_TAG -- durable, marker-bearing name; safe to remember and
--                  validated against the live name on next load.
--   NONE_TAG    -- no industry anywhere nearby; a static map fact,
--                  safe to remember permanently.
--   nil         -- not connected to a hub (yet). Deliberately NOT
--                  persisted: re-evaluated fresh every poll so a
--                  station connected to a hub later gets upgraded to
--                  the hub-numbered name instead of being stuck with
--                  the fallback forever (Decision 105's own noted
--                  limitation). The idempotency check below avoids
--                  re-issuing an identical setName every single poll
--                  in the meantime.
local function buildCandidateName(stationEntry, stationGroupId, positionByStationGroup, counters)

    local position = stationEntry.position

    if position == nil then
        return nil, nil
    end

    local industryName = findNearestIndustryName(position)

    if industryName == nil then
        return nil, NONE_TAG
    end

    local hubStationGroupId =
        findNearestEnabledHub(position, positionByStationGroup)

    if hubStationGroupId ~= nil
        and isStationConnectedToHub(stationGroupId, hubStationGroupId)
    then

        local hubName = stations.getEntityName(hubStationGroupId)
        local counterKey = industryName .. "\t" .. hubName
        local nextNumber = (counters[counterKey] or 0) + 1
        counters[counterKey] = nextNumber

        local newName =
            NAME_PREFIX
                .. industryName
                .. " <-> "
                .. hubName
                .. " - "
                .. string.format("%02d", nextNumber)

        return newName, RENAMED_TAG

    end

    local townName = getTownName(stationEntry.town)

    if townName == nil then
        return nil, nil
    end

    local fallbackName = industryName .. " - " .. townName

    if stations.getRawEntityName(stationGroupId) == fallbackName then
        return nil, nil
    end

    return fallbackName, nil

end


local function collectCandidates(processed, counters)

    local candidates = {}

    local okStations, allStations =
        pcall(
            game.interface.getEntities,
            { radius = math.huge, pos = { 0, 0, 0 } },
            { type = "STATION", includeData = true }
        )

    if not okStations or allStations == nil then
        return candidates
    end

    -- Built for every station up front (not just eligible ones) so a
    -- Distribution Hub's own position is available for the nearest-hub
    -- distance check below, even though hubs themselves are excluded
    -- from being candidates.
    local positionByStationGroup = {}

    for _, stationEntry in pairs(allStations) do

        local stationGroupId =
            stationEntry ~= nil and stationEntry.stationGroup or nil

        if stationGroupId ~= nil and stationEntry.position ~= nil then
            positionByStationGroup[stationGroupId] = stationEntry.position
        end

    end

    for _, stationEntry in pairs(allStations) do

        local stationGroupId =
            stationEntry ~= nil and stationEntry.stationGroup or nil

        if stationGroupId ~= nil and processed[stationGroupId] == nil then

            if isEligibleTruckStation(stationEntry, stationGroupId) then

                local newName, persistTag =
                    buildCandidateName(
                        stationEntry,
                        stationGroupId,
                        positionByStationGroup,
                        counters
                    )

                if newName ~= nil then

                    candidates[#candidates + 1] = {
                        stationGroupId = stationGroupId,
                        newName = newName
                    }

                end

                if persistTag ~= nil then
                    processed[stationGroupId] = persistTag
                end

            else

                processed[stationGroupId] = NONE_TAG

            end

        end

    end

    return candidates

end


-- Same one-at-a-time chained-rename shape as fleet_naming.
-- processRenameNext -- setName issues a real command, and this
-- project's own established discipline (Decision 39/36) is to chain
-- write commands through their own completion callback rather than
-- firing several in the same frame.
local function processCandidateNext(candidates, index, renamedCount, onComplete)

    local candidate = candidates[index]

    if candidate == nil then

        log.info(
            "INDUSTRY NAMING COMPLETE: "
                .. tostring(renamedCount)
                .. " of "
                .. tostring(#candidates)
                .. " station(s) renamed."
        )

        if onComplete ~= nil then
            onComplete(renamedCount)
        end

        return

    end

    stations.setEntityName(
        candidate.stationGroupId,
        candidate.newName,

        function(success)

            log.info(
                "INDUSTRY NAMING: stationGroup "
                    .. tostring(candidate.stationGroupId)
                    .. " -> \"" .. candidate.newName .. "\": "
                    .. tostring(success)
            )

            processCandidateNext(
                candidates,
                index + 1,
                success and (renamedCount + 1) or renamedCount,
                onComplete
            )

        end
    )

end


-- ============================================================
-- CHAIN-LINE DETECTION ("coal -> steel -> hub" style lines)
--
-- Player's idea: a line whose non-hub stops each sit at a genuinely
-- DIFFERENT industry (a real production chain -- pick up coal, drop
-- it at a steel mill, continue to the hub) should never be treated
-- like an ordinary multi-destination line. line_splitter.lua's manual
-- "Split Into Lines & Organize Terminals" button currently splits ANY
-- line with 2+ real (non-hub) destinations -- exactly what would
-- break a chain like this into two disconnected hub<->coal and
-- hub<->steel lines, destroying the actual production sequence the
-- truck was running.
--
-- Reuses the exact same proximity detection findNearestIndustryName
-- already uses for station naming -- deliberately NOT verified
-- against actual cargo movement (e.g. checking the truck really does
-- carry COAL out of stop 1) -- that would need a real SIM_CARGO
-- sourceEntity/targetEntity audit, a meaningfully bigger check not
-- built here. Accepted simplification: a line only counts as a chain
-- if EVERY non-hub stop resolves to a distinct nearby industry --
-- if even one stop has no industry nearby, this returns nil and the
-- line is treated as an ordinary (non-chain) multi-destination line,
-- same as before this feature existed.
-- ============================================================

function M.buildChainName(destinations, hubStationGroupId)

    local industryNames = {}

    for _, destination in ipairs(destinations or {}) do

        if destination ~= nil
            and destination.stationGroup ~= hubStationGroupId
        then

            local ok, entity =
                pcall(game.interface.getEntity, destination.stationGroup)

            local position =
                ok and entity ~= nil and entity.position or nil

            if position == nil then
                return nil
            end

            local industryName = findNearestIndustryName(position)

            if industryName == nil then
                return nil
            end

            industryNames[#industryNames + 1] = industryName

        end

    end

    if #industryNames < 2 then
        return nil
    end

    return table.concat(industryNames, " -> ")

end


function M.detectAndNameStations(onComplete)

    local processed = loadAndValidateProcessedSet()
    local counters = loadCounters()

    local candidates = collectCandidates(processed, counters)

    saveProcessedSet(processed)
    saveCounters(counters)

    if #candidates == 0 then

        if onComplete ~= nil then
            onComplete(0)
        end

        return

    end

    log.info(
        "INDUSTRY NAMING: "
            .. tostring(#candidates)
            .. " new truck station(s) matched to a nearby industry."
    )

    processCandidateNext(candidates, 1, 0, onComplete)

end


return M
