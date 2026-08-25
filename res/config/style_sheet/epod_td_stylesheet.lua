local ssu = require "stylesheetutil"


-- ============================================================
-- EPOD-TD STYLE SHEET (Decision 76)
--
-- Same real mechanism confirmed live in the "Move It Enhanced" mod's
-- own res/config/style_sheet/moveit_stylesheet.lua -- a style class
-- defined here (with the "!" prefix) becomes usable anywhere in this
-- mod via component:addStyleClass("EpodTdXxx"), on any component
-- built with the raw api.gui.comp.*/api.gui.layout.* system. Not
-- wired to anything in mod.lua -- like res/config/game_script/*.lua,
-- this path is loaded by convention, same auto-load pattern this
-- project's own main game script already relies on.
--
-- Deliberately small and disposable for now -- just enough to prove
-- the mechanism works and give the raw-system experiment window a
-- distinct, intentional look, not a finished design system.
--
-- Decision 80: also applied to "DD Central Manager" (gui_manager.lua
-- and its gui_tab_*.lua tabs), which is built on the OTHER object
-- system (gui.lua's ID-string wrapper, not the raw api.gui.comp.*
-- system this file was first written for). componentMetatable in
-- res/scripts/gui.lua (read directly from the TF2 install dir) shows
-- every gui.lua-wrapped object -- window/textView/imageView/button/
-- table/scrollArea -- already forwards a genuine
-- setStyleClassList(list) call straight to
-- game.gui.component_setStyleClassList(id, list), the same native
-- style-class mechanism this style sheet's selectors already hook
-- into. Same style classes, same style sheet file, used from BOTH
-- object systems -- the classes below aren't tied to one or the
-- other. Not yet live-verified from the gui.lua side specifically
-- (only the raw side was live-confirmed working, Decision 76) -- each
-- call site wraps this in its own pcall so a mismatch fails
-- harmlessly (falls back to unstyled text) rather than breaking the
-- window.
-- ============================================================

function data()

    local result = {}
    local a = ssu.makeAdder(result)

    a("!EpodTdHeader", {
        backgroundColor = ssu.makeColor(40, 70, 60, 220),
        padding = { 8, 12, 8, 12 }
    })

    a("!EpodTdHeader TextView", {
        fontSize = 22
    })

    a("!EpodTdPrimaryButton", {
        backgroundColor = ssu.makeColor(70, 140, 110, 210),
        borderColor = ssu.makeColor(0, 0, 0, 150)
    })

    a("!EpodTdPrimaryButton:hover", {
        backgroundColor = ssu.makeColor(95, 175, 140, 220)
    })

    a("!EpodTdPrimaryButton:active", {
        backgroundColor = ssu.makeColor(130, 210, 175, 230)
    })

    a("!EpodTdPrimaryButton:disabled", {
        backgroundColor = ssu.makeColor(120, 120, 120, 80)
    })

    a("!EpodTdSegmentButton", {
        backgroundColor = ssu.makeColor(255, 255, 255, 20),
        padding = { 4, 14, 4, 14 }
    })

    a("!EpodTdSegmentButton:selected", {
        backgroundColor = ssu.makeColor(70, 140, 110, 200)
    })

    a("!EpodTdSectionLabel", {
        color = { 0.7, 0.9, 0.8, 1 }
    })

    -- Decision 80 additions -- DD Central Manager polish pass.

    a("!EpodTdTabActive", {
        backgroundColor = ssu.makeColor(70, 140, 110, 200)
    })

    a("!EpodTdTabInactive", {
        backgroundColor = ssu.makeColor(255, 255, 255, 15)
    })

    -- Decision 82: original 0.85/0.85/0.95 header color and 0.75/0.75/
    -- 0.78 muted color were live-confirmed nearly indistinguishable
    -- from this window's default (near-white) text -- both bumped to
    -- actually read as visually distinct against default text AND
    -- against each other.
    a("!EpodTdTableHeader", {
        color = { 0.95, 0.8, 0.5, 1 }
    })

    a("!EpodTdWarningText", {
        color = { 0.95, 0.55, 0.4, 1 }
    })

    a("!EpodTdMutedText", {
        color = { 0.5, 0.55, 0.55, 1 }
    })

    return result

end
