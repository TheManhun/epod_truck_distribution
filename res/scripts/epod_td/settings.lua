local M = {}


-- ============================================================
-- PERSISTED PLAYER SETTINGS
--
-- Same proven pattern as managed_registry.lua (Decision 26): direct
-- file I/O (io.open), not data()'s save/load hooks -- see
-- DECISIONS.md Decision 24 for why those turned out to be unusable.
-- Deliberately its own small module rather than folded into
-- managed_registry.lua -- that module is specifically about line
-- identity; this one is genuinely-unrelated player preferences, and
-- is expected to grow (more toggles later) without blurring either
-- module's purpose.
--
-- No validation step is needed here the way managed_registry.lua
-- needs one (stale entity IDs from a different save) -- a plain
-- boolean preference has no entity to go stale. Read once per
-- session, lazily, on first access.
--
-- Values can be boolean or numeric (added for autoDispatchHub-
-- StationGroupId, Decision 35 -- a persisted entity ID, not a
-- boolean). A numeric value CAN go stale across a different save the
-- same way managed_registry.lua's entity IDs can; unlike that
-- module, this one does not validate it against live game state --
-- callers (dispatcher.applyPlan via attemptAutoDispatch) already
-- degrade harmlessly to "nothing to do" against an invalid/stale
-- entity rather than erroring, so a dedicated validation pass here
-- would be solving a problem that doesn't actually bite.
-- ============================================================

local STATE_FILE_PATH = "epod_td_settings.txt"

local DEFAULTS = {
    autoRedistribute = false
}

local state = nil


local function loadStateFromDisk()

    local ok, result =
        pcall(function()

            local file = io.open(STATE_FILE_PATH, "r")

            if file == nil then
                return {}
            end

            local content = file:read("*a")
            file:close()

            local loaded = {}

            for key, value in content:gmatch("(%a+)=([^\r\n]+)") do

                if value == "true" then
                    loaded[key] = true
                elseif value == "false" then
                    loaded[key] = false
                else

                    local number = tonumber(value)

                    if number ~= nil then
                        loaded[key] = number
                    end

                end

            end

            return loaded

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

        for key, value in pairs(state) do

            file:write(
                tostring(key)
                    .. "="
                    .. tostring(value)
                    .. "\n"
            )

        end

        file:close()

    end)

end


local function ensureLoaded()

    if state == nil then
        state = loadStateFromDisk()
    end

end


function M.get(key)

    ensureLoaded()

    if state[key] ~= nil then
        return state[key]
    end

    return DEFAULTS[key]

end


function M.set(key, value)

    ensureLoaded()

    if state[key] ~= value then
        state[key] = value
        saveStateToDisk()
    end

end


return M
