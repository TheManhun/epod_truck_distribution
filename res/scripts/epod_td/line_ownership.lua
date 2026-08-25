local log = require("epod_td.log")
local lines = require("epod_td.lines")

local M = {}


-- ============================================================
-- MULTI-HUB: WHICH HUB OWNS A SHARED LINE
--
-- Same proven pattern as managed_registry.lua/hub_registry.lua:
-- direct file I/O, fresh read every call, no module-level cache.
--
-- Decision 63: writes to the game install folder, not a per-savegame
-- path (same documented gap as hub_registry.lua/managed_registry.lua
-- -- no reliable API exists to read which save is active). Confirmed
-- live: a stale line ID from a different save fed into a delete
-- command elsewhere crashed the game (deleteLine on a nonexistent
-- line is a native crash, not a Lua error). Now validates on load the
-- same way managed_registry.lua already does -- any stored line ID
-- that no longer resolves to a real line is dropped rather than
-- trusted blindly.
--
-- Decision 45 fixed a planner bug that made every hub see EVERY
-- managed line in the game as its own. Fixing that exposed the real,
-- underlying case it had been masking: a line that genuinely touches
-- more than one enabled hub (e.g. a real inter-hub transfer route)
-- gets treated as a legitimate candidate by BOTH hubs' independent
-- planners, with nothing coordinating between them. Live-confirmed
-- (Decision 48): three hubs sharing one real bridging line pulled its
-- vehicle count in three different directions across consecutive
-- automatic runs -- not violent flapping (the existing per-line
-- direction cooldown still blocks immediate reversal), but a slow,
-- never-settling tug-of-war, because each hub's plan was locally
-- "correct" with no idea the other hubs were also laying claim to the
-- same line.
--
-- This module makes a shared line belong to exactly ONE hub. Every
-- OTHER hub's planner excludes it as a candidate even though it
-- structurally touches them too -- the whole point is to stop
-- multiple dispatchers from fighting over the same vehicles.
-- ============================================================

local STATE_FILE_PATH = "epod_td_line_ownership.txt"

-- Per-instance throttle on the expensive game.interface.getLines()
-- walk only -- NOT a cache of the registry's own contents (every
-- actual read/write still goes through loadStateFromDisk()/
-- saveStateToDisk() fresh). Same pattern as managed_registry.lua's
-- hasMigratedThisSession.
local hasValidatedThisSession = false


local function loadStateFromDisk()

    local ok, result =
        pcall(function()

            local file = io.open(STATE_FILE_PATH, "r")

            if file == nil then
                return {}
            end

            local content = file:read("*a")
            file:close()

            local ownerByLine = {}

            for lineId, hubId in content:gmatch("(%-?%d+)=(%-?%d+)") do
                ownerByLine[tonumber(lineId)] = tonumber(hubId)
            end

            return ownerByLine

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

        for lineId, hubId in pairs(state) do
            file:write(tostring(lineId) .. "=" .. tostring(hubId) .. "\n")
        end

        file:close()

    end)

end


-- Decision 63: drops any stored line ID that no longer resolves to a
-- real line (a different, unrelated save, or a since-deleted line) --
-- same validate-on-load discipline managed_registry.lua already uses.
-- Runs the expensive getLines() walk at most once per script instance;
-- the state itself is still loaded fresh from disk on every call.
local function loadAndValidate()

    local state = loadStateFromDisk()

    if hasValidatedThisSession then
        return state
    end

    hasValidatedThisSession = true

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then
        return state
    end

    local realLineIds = {}

    for _, lineId in ipairs(allLineIds) do
        realLineIds[lineId] = true
    end

    local changed = false

    for lineId, _ in pairs(state) do

        if not realLineIds[lineId] then

            log.info(
                "LINE OWNERSHIP: dropping stale entry "
                    .. tostring(lineId)
                    .. " (no longer a real line -- different save, "
                    .. "or deleted)"
            )

            state[lineId] = nil
            changed = true

        end

    end

    if changed then
        saveStateToDisk(state)
    end

    return state

end


function M.getOwner(lineId)

    if lineId == nil then
        return nil
    end

    local state = loadAndValidate()

    return state[lineId]

end


-- Unconditionally records hubStationGroupId as lineId's owner --
-- used at the deterministic moment ownership is actually decided
-- (line_splitter.lua creating a line FOR a specific hub,
-- line_adopter.lua adopting a line INTO a specific hub). Overwrites
-- any previous owner on purpose: those are the two places that
-- genuinely know which hub a line belongs to, more authoritative
-- than a lazy first-touch guess.
function M.claim(lineId, hubStationGroupId)

    if lineId == nil or hubStationGroupId == nil then
        return
    end

    local state = loadAndValidate()

    if state[lineId] ~= hubStationGroupId then
        state[lineId] = hubStationGroupId
        saveStateToDisk(state)
    end

end


-- For lines that predate this module (Grain, manually-migrated "● "
-- lines, anything adopted/split before Decision 48) and so have no
-- recorded owner yet: lazily claimed the moment some hub's planner
-- run touches it, same self-healing-on-first-contact pattern
-- managed_registry.lua's migration already uses. Returns true if
-- lineId is owned by some OTHER hub (caller should exclude it),
-- false if it's unowned (and now claimed) or already owned by
-- hubStationGroupId itself.
--
-- Decision 67 fix: the lazy claim used to unconditionally credit
-- whichever hub happened to call this first -- live-confirmed real
-- bug where a line's actual structural hub (repeated 7 times in its
-- own stops) lost ownership to a different enabled hub that merely
-- appeared once, as an ordinary destination, because that hub's scan
-- ran first. Now finds the line's real dominant stop (the repeated
-- stationGroup, lines.findDominantStationGroup) and claims it for
-- THAT hub instead, if there is one -- only falls back to crediting
-- the caller when no repeated anchor exists at all (e.g. a plain,
-- already-split 2-stop line with no obvious "hub" of its own).
function M.isOwnedByOther(lineId, hubStationGroupId)

    if lineId == nil or hubStationGroupId == nil then
        return false
    end

    local state = loadAndValidate()

    local owner = state[lineId]

    if owner == nil then

        local dominantGroup = lines.findDominantStationGroup(lineId)

        local claimFor =
            dominantGroup ~= nil
                and dominantGroup
                or hubStationGroupId

        state[lineId] = claimFor
        saveStateToDisk(state)

        return claimFor ~= hubStationGroupId

    end

    return owner ~= hubStationGroupId

end


-- Decision 60: the reverse of getOwner -- every line currently
-- recorded as owned by this hub. Used when a hub gets disabled to
-- find what it leaves behind (see line_splitter.deleteEmptyOwnedLines)
-- rather than leaving orphaned empty lines sitting around forever.
function M.getLinesOwnedBy(hubStationGroupId)

    if hubStationGroupId == nil then
        return {}
    end

    local state = loadAndValidate()

    local lineIds = {}

    for lineId, ownerId in pairs(state) do

        if ownerId == hubStationGroupId then
            lineIds[#lineIds + 1] = lineId
        end

    end

    return lineIds

end


return M
