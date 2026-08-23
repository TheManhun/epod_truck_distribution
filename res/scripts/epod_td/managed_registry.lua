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
-- crashes. File I/O has no equivalent problem: it doesn't depend on
-- which script instance the engine happens to be running, so a
-- plain module-level `state` table is safe here in a way it wasn't
-- for the save/load proof-of-concept.
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

local state = nil
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


local function saveStateToDisk()

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


local function ensureLoaded()

    if state == nil then
        state = loadStateFromDisk()
    end

end


-- Drops any registered line ID that no longer resolves to a real
-- line (stale from a different save, or since deleted -- see the
-- big comment above), then migrates any currently-existing "● "
-- line not already registered. Runs at most once per session,
-- lazily, on the first real registry query -- avoids a game-wide
-- getLines() walk on every single isManaged() check.
local function migrateAndValidate()

    if hasMigratedThisSession then
        return
    end

    hasMigratedThisSession = true

    ensureLoaded()

    local ok, allLineIds =
        pcall(function()
            return game.interface.getLines()
        end)

    if not ok or allLineIds == nil then
        return
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
        saveStateToDisk()
    end

end


function M.isManaged(lineId)

    if lineId == nil then
        return false
    end

    migrateAndValidate()
    ensureLoaded()

    return state[lineId] == true

end


-- Called by the split pipeline whenever it creates a new managed
-- line (Stage 1) -- the persistent record, not the "● " name, is
-- what actually makes a line managed from this point on.
function M.register(lineId)

    if lineId == nil then
        return
    end

    ensureLoaded()

    if state[lineId] ~= true then
        state[lineId] = true
        saveStateToDisk()
    end

end


-- Called by the safe-delete path (deleteEmptySourceLine and
-- similar) once a managed line is actually gone.
function M.unregister(lineId)

    if lineId == nil then
        return
    end

    ensureLoaded()

    if state[lineId] == true then
        state[lineId] = nil
        saveStateToDisk()
    end

end


return M
