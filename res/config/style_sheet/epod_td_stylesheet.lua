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

    return result

end
