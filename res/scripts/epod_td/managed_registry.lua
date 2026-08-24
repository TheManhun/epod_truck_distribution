local log = require("epod_td.log")
local lines = require("epod_td.lines")

local M = {}


-- ============================================================
-- PERSISTENT MANAGED-LINE IDENTITY
--
-- IDEAS.md PRIORITY: whether a line is managed by Dynamic
-- Distribution must be determined by DD's own persistent record of
-- line entity IDs, not by parsing the "● " name prefix on every
-- check. The name stays as a cosmetic player-facing hint (Decision
-- 22 onward); this module is the actual authority.
--
-- Uses direct file I/O (io.open), not data()'s save/load hooks --
-- see DECISIONS.md Decision 24 for why save/load turned out to be
-- unusable here after eight live-tested attempts across two hard
-- crashes.
--
-- NO MODULE-LEVEL STATE CACHE (Decision 35, corrected after a real
-- live bug elsewhere): this file used to claim a plain module-level
-- `state` table was safe here "in a way it wasn't for the save/load
-- proof-of-concept" -- that claim was wrong, just never yet exposed.
-- settings.lua had the identical pattern (load once, cache forever)
-- and live testing proved it broken: a value written by one script
-- instance was invisible to another instance's already-cached,
-- never-refreshed snapshot. The same risk applies here -- a line
-- registered by the GUI instance (a fresh Stage 1 split) could be
-- invisible to isManaged() calls from a different instance (e.g.
-- inside dispatcher.applyPlan, called from handleEvent) if that
-- instance had already cached its own copy of state earlier. Every
-- read now goes through loadStateFromDisk() fresh -- file I/O is the
-- one thing proven to actually cross the instance boundary, not a
-- module-level Lua table regardless of what backs it.
--
-- Per-savegame scoping: no reliable API was found for reading the
-- current save's name/identity from Lua (searched the shipped
-- script set), so the file itself is not scoped per save. Instead,
-- every load is followed by VALIDATION -- exactly what IDEAS.md's
-- own "Persistence Integration" section specifies ("Validate stored
-- entities still exist"): any stored line ID that no longer
-- resolves to a real line in the CURRENT game (a different save, or
-- a line since deleted) is silently dropped, not trusted. This
-- makes the file safe to reuse across different saves without
-- needing to know which save is active -- stale entries just fail
-- validation and get cleaned up automatically.
-- ============================================================

local STATE_FILE_PATH = "epod_td_managed_lines.txt"

-- Per-instance throttle on the expensive game.interface.getLines()
-- walk only -- NOT a cache of the registry's contents (see the big
-- comment above). Each script instance still does its own one-time
-- validate/migrate pass; every actual read/write of the registry
-- itself goes through loadStateFromDisk()/saveStateToDisk() fresh.
local hasMigratedThisSession = false


local function loadStateFromDisk()

    local ok, result =
        pcall(function()

            local file = io.open(STATE_FILE_PATH, "r")

            if file == nil then
                return {}
            end

            local content = file:read("*a")
            file:close()

            local managedLineIds = {}

            for token in content:gmatch("%-?%d+") do
                managedLineIds[tonumber(token)] = true
            end

            return managedLineIds

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

        for lineId, _ in pairs(state) do
            file:write(tostring(lineId) .. "\n")
        end

        file:close()

    end)

end


-- Drops any registered line ID that no longer resolves to a real
-- line (stale from a different save, or since deleted -- see the
-- big comment above), then migrates any currently-existing "● "
-- line not already registered. The expensive getLines() walk runs at
-- most once per script instance (hasMigratedThisSession); the state
-- itself is always loaded fresh from disk on every call, so a call
-- after this instance's own migration still picks up whatever
-- another instance has written since. Returns the resulting state
-- table.
local function migrateAndValidate()

    local state = loadStateFromDisk()

    if hasMigratedThisSession then
        return state
    end

    hasMigratedThisSession = true

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
                "MANAGED REGISTRY: dropping stale entry "
                    .. tostring(lineId)
                    .. " (no longer a real line -- different save, "
                    .. "or deleted)"
            )

            state[lineId] = nil
            changed = true

        end

    end

    for _, lineId in ipairs(allLineIds) do

        if state[lineId] ~= true then

            local name = lines.getName(lineId)

            if name ~= nil and name:sub(1, 4) == "● " then

                log.info(
                    "MANAGED REGISTRY: migrating \""
                        .. tostring(name)
                        .. "\" (id="
                        .. tostring(lineId)
                        .. ") from name prefix -- not yet in the "
                        .. "persistent record"
                )

                state[lineId] = true
                changed = true

            end

        end

    end

    if changed then
        saveStateToDisk(state)
    end

    return state

end


function M.isManaged(lineId)

    if lineId == nil then
        return false
    end

    local state = migrateAndValidate()

    return state[lineId] == true

end


-- Called by the split pipeline whenever it creates a new managed
-- line (Stage 1) -- the persistent record, not the "● " name, is
-- what actually makes a line managed from this point on.
function M.register(lineId)

    if lineId == nil then
        return
    end

    local state = loadStateFromDisk()

    if state[lineId] ~= true then
        state[lineId] = true
        saveStateToDisk(state)
    end

end


-- Called by the safe-delete path (deleteEmptySourceLine and
-- similar) once a managed line is actually gone.
function M.unregister(lineId)

    if lineId == nil then
        return
    end

    local state = loadStateFromDisk()

    if state[lineId] == true then
        state[lineId] = nil
        saveStateToDisk(state)
    end

end


return M
