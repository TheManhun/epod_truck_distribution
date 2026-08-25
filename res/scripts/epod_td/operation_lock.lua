local M = {}


-- ============================================================
-- SHARED HUB-OPERATION REENTRANCY LOCK (Decision 66, 68, 71)
--
-- Live-confirmed real crash (Decision 66): a native engine assertion
-- fired against a line entity mid-deletion when a second hub's setup
-- sequence started while an earlier one was still running, deleting a
-- fully-degenerate source line at the same moment the second hub's own
-- scan was iterating every managed line. Not something a pcall can
-- catch -- a native assertion crashes the whole process regardless.
-- Refusing to start a second hub-mutating operation while one is
-- already running removes the race entirely.
--
-- Originally a private field on epod_truck_distribution.lua's own
-- distributionState table (Decision 66), then extended to cover the
-- older manual Split/Assign & Balance/Re-Organize Terminals buttons
-- too (Decision 68). Moved out to this tiny standalone module
-- (Decision 71) so gui_manager.lua's action buttons can share the
-- exact same lock -- the new GUI window is a deliberately separate,
-- independent window that can be open and clicked at the same time as
-- the existing panel, so a private field on one file's own state
-- table can no longer be the only thing guarding against overlap.
--
-- Deliberately in-memory only, not persisted -- same as the field it
-- replaces. A stuck-true lock would only ever last until the next
-- game session, and nothing about "was a hub setup running" is
-- meaningful information to carry across a save/reload anyway.
-- ============================================================

local isRunning = false


function M.isRunning()
    return isRunning
end


function M.begin()
    isRunning = true
end


function M.finish()
    isRunning = false
end


return M
