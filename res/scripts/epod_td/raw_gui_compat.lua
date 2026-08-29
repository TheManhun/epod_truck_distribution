local M = {}


-- ============================================================
-- RAW GUI COMPAT LAYER (Decision 131)
--
-- Exposes gui.lua's exact public shape (window_create/boxLayout_create/
-- textView_create/imageView_create/button_create, and each returned
-- object's setText(text,width)/setStyleClassList(list)/onClick(fn)/
-- onClose(fn)/close()/addItem(child)/setImage(path)/setTransparent(bool))
-- but backed entirely by the RAW api.gui.comp.*/api.gui.layout.*
-- system (the one gui_experiment.lua already uses safely, Decisions
-- 72/73/75) instead of gui.lua's game.gui ID-string wrapper. Written so
-- gui_tab_*.lua files -- already built against gui.lua's shape --
-- run UNCHANGED against a window built on this instead: only the
-- `require("gui")` line at the top of the window-owning file needs to
-- point here.
--
-- Two real, deliberate differences from gui.lua, both confirmed
-- against the official bundled api.gui.md reference (shipped with the
-- "Auto Line Namer" workshop mod) before writing this:
--
-- (1) The `id` argument every _create function takes is UNUSED --
--     raw components are tracked purely by the Lua object reference
--     returned, same as gui_experiment.lua already does, not by a
--     global ID string the way game.gui works. Kept as a parameter
--     anyway purely so call sites written against gui.lua don't need
--     editing.
--
-- (2) setStyleClassList(list) is built on top of raw's
--     addStyleClass(class)/removeStyleClass(class) single-class calls
--     -- raw has no "replace the whole list in one call" method the
--     way game.gui does. Each wrapper tracks which classes it
--     currently has applied and diffs against the new list.
--
-- setVisible(visible) is additionally exposed on every wrapped object
-- -- real, live-confirmed on api.gui.comp.Component (the visibility
-- probe in gui_experiment.lua, screenshots + stdout.txt "ok=true"
-- across five toggles) and confirmed present on the base Component
-- class by the official docs. gui.lua's own objects never exposed
-- this at all (Decision 130 found no such thing anywhere in
-- game.gui's own component metatable) -- this is the whole reason a
-- raw-backed window is worth building.
-- ============================================================


local function attachCommon(raw)

    local wrapper = {
        _raw = raw,
        _styleClasses = {}
    }

    wrapper.setStyleClassList = function(self, list)

        for _, existingClass in ipairs(self._styleClasses) do
            pcall(self._raw.removeStyleClass, self._raw, existingClass)
        end

        self._styleClasses = {}

        for _, newClass in ipairs(list or {}) do
            pcall(self._raw.addStyleClass, self._raw, newClass)
            table.insert(self._styleClasses, newClass)
        end

    end

    wrapper.setToolTip = function(self, text)
        pcall(self._raw.setTooltip, self._raw, text)
    end

    wrapper.setTransparent = function(self, transparent)
        pcall(self._raw.setTransparent, self._raw, transparent)
    end

    -- New capability gui.lua's own objects never had -- see header.
    wrapper.setVisible = function(self, visible)
        pcall(self._raw.setVisible, self._raw, visible, false)
    end

    wrapper.setLayout = function(self, layout)
        pcall(self._raw.setLayout, self._raw, layout._raw)
    end

    -- Generic on the base Component class per the official docs, so
    -- exposed on every wrapper (windows included) rather than only
    -- internally via applyFixedWidth. Rounds for the same reason
    -- applyFixedWidth does -- Size.new rejects non-integer arguments
    -- (Decision 134's live-confirmed crash). Returns ok/err (unlike
    -- every other wrapper method here) specifically so a caller doing
    -- diagnostic logging can tell a real failure apart from silent
    -- success -- wrapping an already-pcall'd function in another pcall
    -- always reports ok=true trivially, which is a real trap in this
    -- codebase's own established pattern; this is the one method that
    -- needs to break from it to actually be diagnosable.
    wrapper.setMinimumSize = function(self, width, height)

        local okSize, sizeOrErr = pcall(api.gui.util.Size.new, math.floor(width + 0.5), math.floor(height + 0.5))

        if not okSize then
            return false, "Size.new failed: " .. tostring(sizeOrErr)
        end

        return pcall(self._raw.setMinimumSize, self._raw, sizeOrErr)

    end

    wrapper.setMaximumSize = function(self, width, height)

        local okSize, sizeOrErr = pcall(api.gui.util.Size.new, math.floor(width + 0.5), math.floor(height + 0.5))

        if not okSize then
            return false, "Size.new failed: " .. tostring(sizeOrErr)
        end

        return pcall(self._raw.setMaximumSize, self._raw, sizeOrErr)

    end

    -- Decision 175: real, widely-used pattern across multiple OTHER
    -- installed Workshop mods (Move It Enhanced's gui_util.lua and its
    -- near-identical move_it_script.lua both call `slider:
    -- calcMinimumSize()` to size a widget to its own real content
    -- instead of a guessed/fixed number) -- confirmed real on the base
    -- Component class the same way setMinimumSize/setMaximumSize
    -- already were. Returns ok/sizeOrErr like those two, for the same
    -- "don't let an outer pcall hide a real failure" reason -- the
    -- caller decides what a nil/failed result should fall back to.
    -- NOT yet proven on THIS window type specifically -- Decision 136's
    -- own note that setMinimumSize/setMaximumSize had zero visible
    -- effect on this window's rendered WIDTH is a real reason for
    -- caution, flagged for live verification.
    wrapper.calcMinimumSize = function(self)
        return pcall(self._raw.calcMinimumSize, self._raw)
    end

    return wrapper

end


-- Approximates gui.lua's textView_setText(id, text, width) fixed-
-- column behaviour -- raw TextView:setText() takes no width argument
-- at all (confirmed via the official docs), so a fixed column width
-- has to come from setMinimumSize/setMaximumSize instead. Height is
-- deliberately left generous (2000) rather than tightly capped -- the
-- goal is a fixed WIDTH column, not a clipped height; unverified
-- whether this matches gui.lua's exact visual result pixel-for-pixel,
-- flagged for live-test tuning rather than assumed correct.
--
-- Decision 134: LIVE-CONFIRMED CRASH -- api.gui.util.Size.new(w, h)
-- rejects non-integer arguments ("sol: no matching function call
-- takes this number of arguments and the specified types"). Every
-- width this codebase ever passed here used to be a plain integer
-- constant, until gui_central_raw.lua started dividing WINDOW_WIDTH by
-- the real tab count (560 / 9 = 62.222...) for the tab bar -- Lua's
-- `/` always produces a float, and unlike a "whole" float (e.g.
-- 560/2 = 280.0, which coerces to int fine), a fractional one has no
-- valid int conversion. Rounding here, once, protects every caller
-- rather than requiring every division at every call site to remember
-- to round itself.
local function applyFixedWidth(raw, width)

    if width == nil then
        return
    end

    local roundedWidth = math.floor(width + 0.5)

    pcall(raw.setMinimumSize, raw, api.gui.util.Size.new(roundedWidth, 0))
    pcall(raw.setMaximumSize, raw, api.gui.util.Size.new(roundedWidth, 2000))

end


function M.window_create(id, title, layout)

    local raw = api.gui.comp.Window.new(title, layout._raw)

    -- Decision 135: LIVE-CONFIRMED bug -- "the X close box does not
    -- work." Per the official docs, comp.Window:addHideOnCloseHandler
    -- "Adds a default handler for onClose that hides the window when
    -- it is closed" -- hiding-on-close is opt-in, not automatic. Our
    -- own onClose callback below was firing fine (state.closedByUser
    -- was updating correctly), but nothing ever told the actual native
    -- window to disappear, so clicking X visually did nothing. Same
    -- call gui_experiment.lua's window already makes successfully.
    pcall(raw.addHideOnCloseHandler, raw)

    local wrapper = attachCommon(raw)

    -- Real native callback (comp.Window:onClose(callback), confirmed
    -- in the official docs) -- unlike gui.lua's onClose, which is just
    -- a Lua-side table lookup (gui.windowcallbacks[self.id]) relying on
    -- game.gui to actually invoke it by id.
    wrapper.onClose = function(self, fn)
        pcall(self._raw.onClose, self._raw, fn)
    end

    wrapper.close = function(self)
        pcall(self._raw.close, self._raw)
    end

    wrapper.setTitle = function(self, newTitle)
        pcall(self._raw.setTitle, self._raw, newTitle)
    end

    -- comp.Window:setPosition(x, y), confirmed in the official docs.
    wrapper.setPosition = function(self, x, y)
        pcall(self._raw.setPosition, self._raw, math.floor(x + 0.5), math.floor(y + 0.5))
    end

    -- Decision 136: comp.Window:setSize(size), confirmed in the
    -- official docs -- a direct "set the current size to this" call,
    -- distinct from setMinimumSize/setMaximumSize (which apparently
    -- only bound manual-resize range on this window type, not the
    -- actual rendered size -- both reported ok=true live yet had zero
    -- visible effect, confirmed via Decision 135's own diagnostic
    -- logging). Returns ok/err like setMinimumSize/setMaximumSize, for
    -- the same "don't let an outer pcall hide a real failure" reason.
    wrapper.setSize = function(self, width, height)

        local okSize, sizeOrErr = pcall(api.gui.util.Size.new, math.floor(width + 0.5), math.floor(height + 0.5))

        if not okSize then
            return false, "Size.new failed: " .. tostring(sizeOrErr)
        end

        return pcall(self._raw.setSize, self._raw, sizeOrErr)

    end

    return wrapper

end


function M.boxLayout_create(id, orientation)

    local raw = api.gui.layout.BoxLayout.new(orientation)

    return {
        _raw = raw,
        addItem = function(self, child)
            pcall(self._raw.addItem, self._raw, child._raw)
        end
    }

end


-- Not part of gui.lua's own shape at all -- gui.lua never needed a
-- bare, generic container since it has no equivalent to raw's
-- Component-with-a-layout-set-on-it pattern (see gui_experiment.lua's
-- own headerContainer for the original use of this). Needed here
-- specifically so a "tab panel" can be its own Component with its own
-- BoxLayout, addable to the window's layout and independently
-- setVisible-toggled.
function M.container_create(id)
    return attachCommon(api.gui.comp.Component.new(id or ""))
end


function M.textView_create(id, text, width, iaHintSupport)

    local raw = api.gui.comp.TextView.new(text or "")
    local wrapper = attachCommon(raw)

    applyFixedWidth(raw, width)

    wrapper.setText = function(self, newText, newWidth)

        pcall(self._raw.setText, self._raw, newText or "")

        if newWidth ~= nil then
            applyFixedWidth(self._raw, newWidth)
        end

    end

    return wrapper

end


function M.imageView_create(id, path)

    local raw = api.gui.comp.ImageView.new(path or "")
    local wrapper = attachCommon(raw)

    -- Decision 140: LIVE-CONFIRMED BUG -- "we lost the icons" on the
    -- LINES accordion. Real shipped mods (TPF2-Timetables, AI Builder)
    -- ALWAYS call `imageView:setImage(path, bool)` with a second
    -- argument -- this wrapper was calling it with only one. Against a
    -- strict sol2 binding that almost certainly throws "no matching
    -- function" (the same class of error Decision 134 already found
    -- for Size.new), silently swallowed by this method's own internal
    -- pcall -- the icon was never actually updated past its initial
    -- blank placeholder, on every single row, since the raw port. The
    -- second argument's exact meaning is unconfirmed (shipped mods use
    -- both `true` and `false` in different places -- plausibly a
    -- resize/rescale flag) -- `false` matches the large majority of
    -- real usages seen.
    wrapper.setImage = function(self, newPath)
        pcall(self._raw.setImage, self._raw, newPath, false)
    end

    return wrapper

end


-- ============================================================
-- SCROLL AREA (Decision 173)
--
-- Not part of gui.lua's own shape at all -- gui.lua has no equivalent.
-- Confirmed real and usable by reading a second, unrelated installed
-- Workshop mod ("Small Minimap", Workshop 3256290611)'s own real
-- source, which builds one via `api.gui.comp.ScrollArea.new(component,
-- id)` and explicit `setHorizontalScrollBarPolicy`/
-- `setVerticalScrollBarPolicy` calls (`api.gui.comp.ScrollBarPolicy.
-- AS_NEEDED`/`ALWAYS_OFF`/`ALWAYS_ON`, per that mod's own comment).
-- Not yet independently live-tested by THIS mod -- flagged for
-- verification the same way every other newly-added raw call in this
-- file was (Decisions 134/135/136/140 all started as "confirmed
-- against a reference, not yet proven here").
--
-- `innerWrapper` is expected to be one of THIS module's own wrapped
-- components (typically a container_create() with a boxLayout_create()
-- layout already set on it) -- its `._raw` is unwrapped the same way
-- boxLayout_create's own addItem already does, for consistency with
-- the rest of this file. Every size/visibility/style method this
-- wrapper exposes comes from the same attachCommon every other wrapper
-- in this file already shares -- setMinimumSize/setMaximumSize are how
-- a caller constrains the visible scroll viewport height.
function M.scrollArea_create(id, innerWrapper)

    local raw = api.gui.comp.ScrollArea.new(innerWrapper._raw, id or "")
    local wrapper = attachCommon(raw)

    pcall(raw.setHorizontalScrollBarPolicy, raw, api.gui.comp.ScrollBarPolicy.ALWAYS_OFF)
    pcall(raw.setVerticalScrollBarPolicy, raw, api.gui.comp.ScrollBarPolicy.AS_NEEDED)

    return wrapper

end


function M.button_create(id, content)

    local raw = api.gui.comp.Button.new(content._raw, false)
    local wrapper = attachCommon(raw)

    wrapper.onClick = function(self, fn)
        pcall(self._raw.onClick, self._raw, fn)
    end

    return wrapper

end


return M
