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
-- boolean preference has no entity to go stale.
--
-- Values can be boolean or numeric. A numeric value CAN go stale
-- across a different save; unlike managed_registry.lua, this one
-- does not validate it against live game state -- callers already
-- degrade harmlessly to "nothing to do" against an invalid/stale
-- entity rather than erroring, so a dedicated validation pass here
-- would be solving a problem that doesn't actually bite.
--
-- Decision 44 (multi-hub): the single "autoRedistribute" boolean and
-- single "autoDispatchHubStationGroupId" value that used to live here
-- are RETIRED -- replaced by hub_registry.lua's actual set of
-- independently enabled hub IDs, since a single global value could
-- only ever auto-manage one hub game-wide. "autoDispatchPending"
-- below stays here: the trigger that sets it (the delivery-count
-- threshold, Decision 40) is still game-wide, not per-hub, so it
-- correctly means "run a dispatch pass for every enabled hub", not
-- anything tied to one specific hub.
--
-- NO MODULE-LEVEL CACHE (Decision 35, fixed after a real live bug):
-- this used to load once, lazily, and cache in a local `state` table
-- for the rest of the session -- exactly the assumption that broke
-- data()'s save/load (Decision 24). Live testing proved handleEvent
-- runs on a different script instance than guiUpdate; the toggle
-- click (GUI instance) writing a new key to disk was invisible to
-- the handleEvent instance's already-cached, never-refreshed
-- snapshot, so attemptAutoDispatch silently saw "no hub" forever
-- even after the file genuinely had one. Every M.get/M.set now reads
-- fresh from disk -- the only way to actually cross the instance
-- boundary, proven repeatedly in this project. Low call frequency
-- (button clicks, once per 50 delivery events) makes the extra
-- io.open cost a non-issue.
-- ============================================================

local STATE_FILE_PATH = "epod_td_settings.txt"

-- autoApplyFleetPlanEnabled/autoApplyFleetPlanIntervalSeconds: player's
-- own idea after manually clicking "Apply Fleet Plan" every 5-7 seconds
-- and watching a badly imbalanced network (deltas of +62, +25, +41)
-- converge to nearly-flat within a couple of minutes -- real, live
-- proof the mechanism works well when applied often, not just on the
-- rare 5000-delivery auto-trigger or a single manual click. Off by
-- default: this is still a real vehicle-moving action (same
-- dispatcher.applyPlan a manual click uses), so it stays an opt-in
-- setting rather than a silent behavior change, same as this
-- project's consistent stance on automating anything consequential.
local DEFAULTS = {
    autoApplyFleetPlanEnabled = false,
    autoApplyFleetPlanIntervalSeconds = 15,
}


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


local function saveStateToDisk(state)

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


function M.get(key)

    local state = loadStateFromDisk()

    if state[key] ~= nil then
        return state[key]
    end

    return DEFAULTS[key]

end


function M.set(key, value)

    local state = loadStateFromDisk()

    if state[key] ~= value then
        state[key] = value
        saveStateToDisk(state)
    end

end


return M
