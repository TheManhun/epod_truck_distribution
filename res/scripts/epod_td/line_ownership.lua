local M = {}


-- ============================================================
-- MULTI-HUB: WHICH HUB OWNS A SHARED LINE
--
-- Same proven pattern as managed_registry.lua/hub_registry.lua:
-- direct file I/O, fresh read every call, no module-level cache.
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


function M.getOwner(lineId)

    if lineId == nil then
        return nil
    end

    local state = loadStateFromDisk()

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

    local state = loadStateFromDisk()

    if state[lineId] ~= hubStationGroupId then
        state[lineId] = hubStationGroupId
        saveStateToDisk(state)
    end

end


-- For lines that predate this module (Grain, manually-migrated "● "
-- lines, anything adopted/split before Decision 48) and so have no
-- recorded owner yet: the first hub whose planner run touches it
-- lazily claims it, exactly the same self-healing-on-first-contact
-- pattern managed_registry.lua's migration already uses. Returns
-- true if lineId is owned by some OTHER hub (caller should exclude
-- it), false if it's unowned (and now claimed for hubStationGroupId)
-- or already owned by hubStationGroupId itself.
function M.isOwnedByOther(lineId, hubStationGroupId)

    if lineId == nil or hubStationGroupId == nil then
        return false
    end

    local state = loadStateFromDisk()

    local owner = state[lineId]

    if owner == nil then

        state[lineId] = hubStationGroupId
        saveStateToDisk(state)

        return false

    end

    return owner ~= hubStationGroupId

end


return M
