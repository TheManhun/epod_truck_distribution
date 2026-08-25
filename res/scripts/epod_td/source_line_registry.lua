local M = {}


-- ============================================================
-- MULTI-HUB: WHICH LINE(S) WERE EACH HUB'S ORIGINAL COMBINED LINES
--
-- Same proven file-I/O pattern as managed_registry.lua/hub_registry.
-- lua/line_ownership.lua: fresh read every call, no module-level
-- cache.
--
-- Decision 46 (live-confirmed real bug): "Assign & Balance Fleet"
-- used to find its source line via a single hardcoded name,
-- config.SOURCE_LINE_NAME = "Truck - CD - Hendon" -- literally
-- Hendon East's own original line name from early in this project.
-- That could only ever work for Hendon East. This module replaces
-- the hardcoded lookup: line_splitter.lua records which line it
-- actually split FOR a given hub at the one moment that's genuinely
-- known.
--
-- Decision 53 (live-confirmed real bug, this version's fix): the
-- first version of this module stored a SINGLE line ID per hub,
-- overwritten on every split. A real test split TWO combined lines
-- at Yarm East in the same click (Line 6 AND Line 7, since Line 7
-- genuinely touches Yarm East too as part of its real inter-hub
-- route) -- the second split silently overwrote the first's record,
-- so "Assign & Balance Fleet" only ever knew about whichever one was
-- split LAST. The other (Line 7) split correctly but was never
-- retired -- it just kept sitting there with all its original
-- vehicles, exactly as the player observed live ("it didnt transfer
-- like line 6 did"). A hub can legitimately have split more than one
-- original combined line, so this now stores a SET per hub, not a
-- single value.
-- ============================================================

local STATE_FILE_PATH = "epod_td_source_lines.txt"


local function loadStateFromDisk()

    local ok, result =
        pcall(function()

            local file = io.open(STATE_FILE_PATH, "r")

            if file == nil then
                return {}
            end

            local content = file:read("*a")
            file:close()

            local sourceLinesByHub = {}

            for hubId, lineId in content:gmatch("(%-?%d+):(%-?%d+)") do

                hubId = tonumber(hubId)
                lineId = tonumber(lineId)

                if sourceLinesByHub[hubId] == nil then
                    sourceLinesByHub[hubId] = {}
                end

                sourceLinesByHub[hubId][lineId] = true

            end

            return sourceLinesByHub

        end)

    if ok and result ~= nil then
        return result
    end

    return {}

end


local function saveStateToDisk(state)

    pcall(function()

        local file = io.open(STATE_FILE_PATH, "w")

        if file == nil then
            return
        end

        for hubId, lineIdSet in pairs(state) do

            for lineId, _ in pairs(lineIdSet) do
                file:write(tostring(hubId) .. ":" .. tostring(lineId) .. "\n")
            end

        end

        file:close()

    end)

end


-- Returns a plain array of every line ID Stage 1 has ever split FOR
-- this hub -- a hub can legitimately have more than one, if the
-- player had multiple separate combined lines touching it. Empty
-- array if this hub has never had a split run recorded.
function M.getSourceLines(hubStationGroupId)

    if hubStationGroupId == nil then
        return {}
    end

    local state = loadStateFromDisk()

    local lineIdSet = state[hubStationGroupId]

    if lineIdSet == nil then
        return {}
    end

    local lineIds = {}

    for lineId, _ in pairs(lineIdSet) do
        lineIds[#lineIds + 1] = lineId
    end

    return lineIds

end


-- Called by line_splitter.lua at the moment it actually knows which
-- line it's splitting FOR which hub. ADDS to this hub's set rather
-- than replacing it -- a hub can have split more than one original
-- combined line, and each one still needs its own retirement pass.
function M.addSourceLine(hubStationGroupId, lineId)

    if hubStationGroupId == nil or lineId == nil then
        return
    end

    local state = loadStateFromDisk()

    if state[hubStationGroupId] == nil then
        state[hubStationGroupId] = {}
    end

    if state[hubStationGroupId][lineId] ~= true then
        state[hubStationGroupId][lineId] = true
        saveStateToDisk(state)
    end

end


-- Called once a recorded source line is confirmed actually deleted
-- (line_splitter.deleteEmptySourceLine's deleted == true callback
-- result). Without this, a fully-retired source line's ID stayed in
-- this registry forever -- live-observed real bug: every later
-- "Assign & Balance Fleet" click on that hub re-attempted processing
-- the now-nonexistent line too, alongside whatever real work was
-- left, and every candidate on that hub logged a "Could not re-read
-- source line" failure for it. Harmless (the failure path still
-- calls its callback, so real work was never blocked) but pure log
-- noise that would repeat on every future click, forever.
function M.removeSourceLine(hubStationGroupId, lineId)

    if hubStationGroupId == nil or lineId == nil then
        return
    end

    local state = loadStateFromDisk()

    local lineIdSet = state[hubStationGroupId]

    if lineIdSet == nil or lineIdSet[lineId] == nil then
        return
    end

    lineIdSet[lineId] = nil
    saveStateToDisk(state)

end


return M
