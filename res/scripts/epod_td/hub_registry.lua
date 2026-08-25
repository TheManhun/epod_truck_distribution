local log = require("epod_td.log")
local stations = require("epod_td.stations")

local M = {}


-- ============================================================
-- MULTI-HUB: WHICH HUBS ARE AUTO-MANAGED
--
-- Same proven pattern as managed_registry.lua (Decision 26): direct
-- file I/O (io.open), fresh read on every call, no module-level
-- cache -- the exact thing that broke settings.lua and
-- managed_registry.lua under the multi-instance problem (Decision
-- 35) before both were rewritten to read fresh every time.
--
-- REPLACES settings.lua's old single "autoRedistribute" boolean +
-- single "autoDispatchHubStationGroupId" value (Decision 44). That
-- design could only ever auto-manage ONE hub game-wide, and turning
-- the toggle on while looking at a different station would silently
-- rebind it, dropping whatever hub was previously captured with no
-- warning. This is a genuine SET of hub stationGroup IDs, each
-- independently enabled/disabled -- the toggle button now only ever
-- affects whichever hub is currently selected, never any other.
--
-- Decision 63: this file used to claim staleness validation "doesn't
-- actually bite" -- live-confirmed wrong. This file (and
-- line_ownership.lua/source_line_registry.lua) writes to the game
-- install folder, not a per-savegame path (no reliable API exists to
-- read which save is active -- same gap documented in
-- managed_registry.lua). Loading a DIFFERENT save that happens to
-- reuse the same entity ID (confirmed live: two saves from the same
-- lineage genuinely share IDs for the same real stations) meant a
-- hub showed ON in a save that had never actually enabled it, and
-- fed a stale/wrong-context ID into a delete command elsewhere,
-- crashing the game. Now validates the same way managed_registry.lua
-- already does for line IDs: any stored hub ID that no longer
-- resolves to a real STATION_GROUP component is dropped on load,
-- rather than trusted blindly. This does not fully solve cross-save
-- confusion (an ID that happens to be valid in BOTH saves, as in the
-- crash above, still passes this check -- true per-save isolation
-- would need a save-identity fingerprint, which still doesn't exist)
-- but it closes the far more common case: a genuinely unrelated save
-- whose stale hub ID either doesn't exist at all, or exists as some
-- other now-invalid reference.
-- ============================================================

local STATE_FILE_PATH = "epod_td_enabled_hubs.txt"


local function loadStateFromDisk()

    local ok, result =
        pcall(function()

            local file = io.open(STATE_FILE_PATH, "r")

            if file == nil then
                return {}
            end

            local content = file:read("*a")
            file:close()

            local enabledHubIds = {}

            for token in content:gmatch("%-?%d+") do
                enabledHubIds[tonumber(token)] = true
            end

            return enabledHubIds

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

        for hubId, _ in pairs(state) do
            file:write(tostring(hubId) .. "\n")
        end

        file:close()

    end)

end


-- Decision 63: drops any stored hub ID that no longer resolves to a
-- real STATION_GROUP component (a different, unrelated save, or a
-- since-removed station) -- same validate-on-load discipline
-- managed_registry.lua already uses for line IDs. Cheap enough to run
-- on every load (typically a handful of enabled hubs, one
-- getComponent pcall each), so no per-instance throttle is needed
-- here the way managed_registry.lua's expensive getLines() walk
-- needs one.
local function loadAndValidate()

    local state = loadStateFromDisk()

    local changed = false

    for hubId, _ in pairs(state) do

        if stations.getStationGroup(hubId) == nil then

            log.info(
                "HUB REGISTRY: dropping stale entry "
                    .. tostring(hubId)
                    .. " (no longer a real station -- different save, "
                    .. "or removed)"
            )

            state[hubId] = nil
            changed = true

        end

    end

    if changed then
        saveStateToDisk(state)
    end

    return state

end


function M.isEnabled(hubStationGroupId)

    if hubStationGroupId == nil then
        return false
    end

    local state = loadAndValidate()

    return state[hubStationGroupId] == true

end


function M.enable(hubStationGroupId)

    if hubStationGroupId == nil then
        return
    end

    local state = loadAndValidate()

    if state[hubStationGroupId] ~= true then
        state[hubStationGroupId] = true
        saveStateToDisk(state)
    end

end


function M.disable(hubStationGroupId)

    if hubStationGroupId == nil then
        return
    end

    local state = loadAndValidate()

    if state[hubStationGroupId] == true then
        state[hubStationGroupId] = nil
        saveStateToDisk(state)
    end

end


-- Returns a plain array of every currently-enabled hub stationGroup
-- ID, in no particular order.
function M.getEnabledHubs()

    local state = loadAndValidate()

    local hubIds = {}

    for hubId, _ in pairs(state) do
        hubIds[#hubIds + 1] = hubId
    end

    return hubIds

end


return M
