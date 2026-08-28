# Icons — TF2 Truck Distribution

Tracks every icon this mod uses or might want: which ones are our own custom art, which are free reuse of base-game assets, and what's still just an idea.

## How the pipeline works (confirmed, live-proven)

- Format: **8-bit grayscale TGA**, `res/textures/ui/<name>.tga`
- Referenced in Lua as `"ui/<name>.tga"` — no mod-id prefix
- `ImageView:setImage(path, false)` — the second argument is required; omitting it was a real bug once (cargo icons never rendered until fixed)
- No image-editing tools are available in this environment (no Python, no ImageMagick) — a real PNG has to be supplied by the player, then converted to TGA via a one-off PowerShell script (`System.Drawing.Bitmap`, manual 18-byte TGA header). This is the only way NEW custom art gets into the mod.
- The base game's own icons are full color (not grayscale) — our conversion script has only ever been used for the grayscale tab icons below. A colored custom icon (if we ever want one) would need the script adjusted first; not yet done, not yet needed.

## Our own custom icons (already made, already wired in)

All 8 exist as real `.tga` files in `res/textures/ui/`. Only 4 are currently wired into the live Central Manager's tab bar (`gui_central_raw.lua`'s `TABS`); the other 4 are reserved for the Legacy 8-tab window (`gui_manager.lua`) and aren't actively shown right now.

| File | Tab | Status |
| --- | --- | --- |
| `epodtd_tab_overview.tga` | OVERVIEW | Live |
| `epodtd_tab_lines.tga` | LINES | Live |
| `epodtd_tab_cargo.tga` | CARGO | Live |
| `epodtd_tab_settings.tga` | SETTINGS | Live |
| `epodtd_tab_hubs.tga` | HUBS | Legacy only (tab dropped from the main window, Decision 143) |
| `epodtd_tab_services.tga` | SERVICES | Legacy only (tab dropped, Decision 145) |
| `epodtd_tab_fleet.tga` | FLEET | Legacy only (tab dropped, Decision 137) |
| `epodtd_tab_terminals.tga` | TERMINALS | Legacy only (tab dropped, Decision 141) |
| `epodtd_tab_activity.tga` | ACTIVITY | Legacy only (tab dropped, Decision 139) |

## Base-game icons we reuse for free (no art needed, ever)

**Cargo type icons** — the colored grain/wood/steel/etc. icons on the LINES tab's destination rows. These are TF2's OWN icons, not ours: `demand.getCargoTypeIconPath()` resolves a numeric cargo type via `api.res.cargoTypeRep.get()` to a real base-game texture (`hud/cargo_<id>_small.tga`, confirmed present in the base game's `ui.zip` for every core cargo type). Nothing to design or maintain here — if TF2 ships a cargo type, its icon just works.

## Open ideas — not yet built

- **Station-type marker (drop-off vs. real cargo station)**: currently a plain text tag, `"[D] "`, prepended to a destination's name on LINES when `truck_station_finder.isDropOffStation()` returns true (Decision 160). Player's idea: a small colored icon instead of text. Nothing built yet — would need a real source PNG supplied (same as the tab icons), a decision on whether it replaces or sits alongside the `[D]` text, and (since base-game icons are full color) possibly extending the grayscale-only conversion script if a colored icon is wanted rather than a flat grayscale glyph.
