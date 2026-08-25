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
-- No staleness validation (unlike managed_registry.lua's line IDs):
-- same reasoning settings.lua already documented for the single-hub
-- version -- a stale/invalid hub ID already degrades harmlessly
-- (planner.calculateTargetAllocation returns zero candidates,
-- dispatcher.applyPlan finds nothing to do) rather than erroring, so
-- a dedicated validation pass would be solving a problem that
-- doesn't actually bite.
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


function M.isEnabled(hubStationGroupId)

    if hubStationGroupId == nil then
        return false
    end

    local state = loadStateFromDisk()

    return state[hubStationGroupId] == true

end


function M.enable(hubStationGroupId)

    if hubStationGroupId == nil then
        return
    end

    local state = loadStateFromDisk()

    if state[hubStationGroupId] ~= true then
        state[hubStationGroupId] = true
        saveStateToDisk(state)
    end

end


function M.disable(hubStationGroupId)

    if hubStationGroupId == nil then
        return
    end

    local state = loadStateFromDisk()

    if state[hubStationGroupId] == true then
        state[hubStationGroupId] = nil
        saveStateToDisk(state)
    end

end


-- Returns a plain array of every currently-enabled hub stationGroup
-- ID, in no particular order.
function M.getEnabledHubs()

    local state = loadStateFromDisk()

    local hubIds = {}

    for hubId, _ in pairs(state) do
        hubIds[#hubIds + 1] = hubId
    end

    return hubIds

end


return M
