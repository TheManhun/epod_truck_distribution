local M = {}


-- ============================================================
-- REAL INDUSTRY INPUT RATIOS -- "does this factory need more coal or
-- more iron?"
--
-- Player's question: can we detect what a factory actually needs (a
-- real ratio, e.g. "iron:coal 5:1"), and flag when real deliveries are
-- out of balance with it?
--
-- CONFIRMED, evidence-first, no guessing -- the full chain was traced
-- through real files, not assumed:
--
--   1. A live industry entity (SIM_BUILDING, same entity type
--      industry_naming.lua already finds via
--      game.interface.getEntities({type="SIM_BUILDING"})) has a real,
--      documented, live path to its construction:
--      api.engine.system.streetConnectorSystem.
--      getConstructionEntityForSimBuilding(industryEntity) -- this
--      EXACT call is used live in the real "AI Builder" traffic mod
--      (workshop 2820656841, ai_builder_base_util.lua's
--      util.getFarmFields), not guessed at.
--
--   2. api.engine.getComponent(constructionId,
--      api.type.ComponentType.CONSTRUCTION) returns a real, documented
--      Construction table (api.type.md) with a `.fileName` field (e.g.
--      "industry/steel_mill.con") -- also confirmed via the same real
--      mod's util.getConstruction helper, which does exactly this.
--
--   3. That fileName's actual recipe ratio was read directly from the
--      REAL vanilla construction files
--      (res/construction/industry/*.con, extracted from the base
--      game's construction.zip) -- NOT from the "AI Builder" mod's own
--      inputCargoTypeForAiBuilder/sourcesCountForAiBuilder params,
--      which turned out to be a NON-VANILLA addition requiring a
--      separate companion patch mod (confirmed absent from every real
--      vanilla industry file checked). The real mechanism is
--      `industryutil.lua`'s addIndustryData(name, era, data, constr,
--      stockListConfig), where stockListConfig.stocks (input cargo
--      types, positional) and stockListConfig.rule.input (positional
--      ratio weights) are baked into the construction's own
--      result.rule at build time.
--
-- Checked the FULL vanilla industry roster this way, not just the
-- steel mill: every raw-material producer (coal/iron/oil wells,
-- quarry, farm, forest) has no inputs at all (correct -- they're
-- extraction industries, nothing to balance). Every single-input
-- processor (chemical plant, construction materials plant, food
-- processing plant, fuel refinery, oil refinery, saw mill, tools
-- factory) has only one input, so there's no ratio question for those.
-- Exactly three vanilla industries have a genuine multi-input ratio to
-- balance:
--   steel_mill:       IRON_ORE : COAL   = 2 : 2  (1:1)
--   goods_factory:    PLASTIC  : STEEL  = 1 : 1
--   machines_factory: PLANKS   : STEEL  = 1 : 1
-- Every real vanilla ratio turned out to be 1:1 -- the "5:1" example
-- in the original question was illustrative, not a real number this
-- game ships with. The mechanism below works for whatever ratio an
-- industry actually has (including a genuinely asymmetric one), so a
-- DLC or modded industry with a real non-1:1 ratio would still be
-- handled correctly once added to the table below.
-- ============================================================

local INPUT_RATIOS = {
    ["industry/steel_mill.con"] = { IRON_ORE = 2, COAL = 2 },
    ["industry/goods_factory.con"] = { PLASTIC = 1, STEEL = 1 },
    ["industry/machines_factory.con"] = { PLANKS = 1, STEEL = 1 },

    -- First modded industry added, from the "Industry Expanded" pack
    -- (workshop 1950013035), confirmed by reading its real .con file
    -- the same way as the vanilla roster. Real data: stocks = {
    -- "PLASTIC", "PLANKS", "PAPER", "SILVER" }, rule.input =
    -- { 1, 1, 0, 0 } -- PLASTIC and PLANKS are the real required
    -- inputs; PAPER and SILVER are weight-0 (an "OR"-style optional
    -- alternate, same pattern as advanced_food_processing_plant's
    -- MEAT/COFFEE/ALCOHOL). Deliberately excluded from this table:
    -- findMostNeededInput divides delivered amount by ratio weight, so
    -- a weight of 0 would divide by zero. Shares vanilla goods_
    -- factory.con's display name ("Goods factory") but is a genuinely
    -- different, larger fileName/recipe -- confirmed live via the
    -- player's own screenshot of a real running instance.
    ["industry/advanced_goods_factory.con"] = { PLASTIC = 1, PLANKS = 1 },

    -- Batch-added the rest of "Industry Expanded"'s roster in one pass
    -- (player's own suggestion -- read every remaining unknown file
    -- directly rather than waiting to discover them one at a time
    -- in-game). Real data: stocks = { "IRON_ORE", "COAL" },
    -- rule.input = { 2, 2 } -- identical ratio to vanilla steel_mill,
    -- just a bigger-capacity variant (confirmed earlier via both the
    -- file and the native industry panel showing capacity 400 vs
    -- vanilla's 200).
    ["industry/advanced_steel_mill.con"] = { IRON_ORE = 2, COAL = 2 },

    -- Real data: stocks = { "SILVER", "STEEL" }, rule.input = { 1, 1 }
    -- -- both genuinely required, unlike most of this batch.
    ["industry/advanced_machines_factory.con"] = { SILVER = 1, STEEL = 1 },
}

-- Same real vanilla files, this time the single-input processors
-- (chemical plant, construction materials plant, food processing
-- plant, fuel refinery, oil refinery, saw mill, tools factory) --
-- kept SEPARATE from INPUT_RATIOS above rather than folded in as a
-- one-entry ratio, deliberately: findMostNeededInput's whole job is a
-- RELATIVE comparison between multiple real inputs (is coal further
-- behind than iron?) -- with only one input, there is nothing to
-- compare against, so "most needed" would trivially always be that
-- one type regardless of real supply, a meaningless signal. Used
-- instead by chain_builder.lua's own consumer detection: a
-- single-input industry unconditionally benefits from a direct chain
-- to a real producer of its one input, no imbalance check needed --
-- more efficient delivery is never a downside here. Confirmed live
-- missing case: this hub's Stow-on-the-Wold Oil refinery (produces
-- OIL) and Carnforth Fuel refinery (needs OIL, its only input) sat
-- right next to each other in the player's own save as two separate
-- single-stop lines, invisible to chain_builder before this table
-- existed because getInputRatio only ever covered the three
-- multi-input cases above.
local SINGLE_INPUT_TYPES = {
    ["industry/chemical_plant.con"] = "OIL",
    ["industry/construction_material.con"] = "STONE",
    ["industry/food_processing_plant.con"] = "GRAIN",
    ["industry/fuel_refinery.con"] = "OIL",
    ["industry/oil_refinery.con"] = "CRUDE",
    ["industry/saw_mill.con"] = "LOGS",
    ["industry/tools_factory.con"] = "PLANKS",

    -- Second modded industry added -- player spotted this one live:
    -- a Morley Silver mill running plain hub<->mill (no chain), with
    -- its real input (Dukinfield Silver ore mine) also running
    -- plain hub<->mine separately, exactly the coal/steel hub-detour
    -- pattern. Real data confirmed from the file: stocks = {
    -- "SILVER_ORE" }, rule.input = { 2 } -- single input, same
    -- category as fuel refinery/tools factory above.
    ["industry/silver_mill.con"] = "SILVER_ORE",

    -- Rest of "Industry Expanded"'s roster, batch-added from real
    -- file data (weight-0 entries in a multi-stock list, e.g.
    -- meat_processing_plant's real FISH slot, are treated as optional
    -- alternates and omitted -- same reasoning as advanced_goods_
    -- factory's PAPER/SILVER above):
    ["industry/advanced_chemical_plant.con"] = "GRAIN",
    ["industry/advanced_construction_material.con"] = "SLAG",
    ["industry/advanced_food_processing_plant.con"] = "MEAT",
    ["industry/advanced_fuel_refinery.con"] = "OIL_SAND",
    ["industry/advanced_tools_factory.con"] = "STEEL",
    ["industry/alcohol_distillery.con"] = "GRAIN",
    ["industry/coffee_refinery.con"] = "COFFEE_BERRIES",
    ["industry/livestock_farm.con"] = "GRAIN",
    ["industry/meat_processing_plant.con"] = "LIVESTOCK",
    ["industry/paper_mill.con"] = "LOGS",
}

-- Same real vanilla files, this time each industry's `output = {...}`
-- field -- needed by chain_builder.lua to match a producer's real
-- output against a consumer's real shortest input (e.g. does anything
-- at this hub actually PRODUCE the COAL the steel mill needs?). Every
-- vanilla industry has exactly one output type; one modded exception
-- (advanced_fuel_refinery.con, real TWO outputs) is called out
-- explicitly below where it's added -- this table only ever tracks a
-- single output per fileName.
local OUTPUT_CARGO_TYPES = {
    ["industry/chemical_plant.con"] = "PLASTIC",
    ["industry/coal_mine.con"] = "COAL",
    ["industry/construction_material.con"] = "CONSTRUCTION_MATERIALS",
    ["industry/farm.con"] = "GRAIN",
    ["industry/food_processing_plant.con"] = "FOOD",
    ["industry/forest.con"] = "LOGS",
    ["industry/fuel_refinery.con"] = "FUEL",
    ["industry/goods_factory.con"] = "GOODS",
    ["industry/iron_ore_mine.con"] = "IRON_ORE",
    ["industry/machines_factory.con"] = "MACHINES",
    ["industry/oil_refinery.con"] = "OIL",
    ["industry/oil_well.con"] = "CRUDE",
    ["industry/quarry.con"] = "STONE",
    ["industry/saw_mill.con"] = "PLANKS",
    ["industry/steel_mill.con"] = "STEEL",
    ["industry/tools_factory.con"] = "TOOLS",

    ["industry/advanced_goods_factory.con"] = "GOODS",
    ["industry/silver_ore_mine.con"] = "SILVER_ORE",
    ["industry/silver_mill.con"] = "SILVER",

    ["industry/advanced_steel_mill.con"] = "STEEL",
    ["industry/advanced_machines_factory.con"] = "MACHINES",
    ["industry/advanced_chemical_plant.con"] = "PLASTIC",
    ["industry/advanced_construction_material.con"] = "CONSTRUCTION_MATERIALS",
    ["industry/advanced_food_processing_plant.con"] = "FOOD",

    -- Real data: output = { FUEL=1, SAND=1 } -- the first industry
    -- seen with TWO real outputs (every other one checked, vanilla or
    -- modded, has exactly one). This table only tracks a single output
    -- per industry -- FUEL registered as the primary (matches the
    -- industry's own name/purpose); the SAND byproduct is a real,
    -- known gap, not modeled. A producer/consumer chain built around
    -- this industry's SAND output specifically would not be detected.
    ["industry/advanced_fuel_refinery.con"] = "FUEL",

    ["industry/advanced_tools_factory.con"] = "TOOLS",
    ["industry/alcohol_distillery.con"] = "ALCOHOL",
    ["industry/coffee_farm.con"] = "COFFEE_BERRIES",
    ["industry/coffee_refinery.con"] = "COFFEE",
    ["industry/fishery.con"] = "FISH",
    ["industry/livestock_farm.con"] = "LIVESTOCK",
    ["industry/marble_mine.con"] = "MARBLE",
    ["industry/meat_processing_plant.con"] = "MEAT",
    ["industry/oil_sand_mine.con"] = "OIL_SAND",
    ["industry/paper_mill.con"] = "PAPER",
}

-- LIVE-TESTED AND RULED OUT: api.engine.system.simEntityAtStockSystem.
-- getStockCount(industryEntityId, index-1) (index-1 as a guessed
-- positional stockId, matching stockListConfig.stocks's real file
-- order) was tried as a way to read TF2's own native industry panel's
-- "Stored" number directly (the player screenshotted Goole Steel mill
-- showing IRON_ORE=4330, COAL=14 stored). The live test came back
-- ok=true but a flat 0 for every cargo type on every industry checked
-- -- not an error, just the wrong number, and not close enough to be
-- an off-by-one or scaling issue either. No real mod anywhere uses
-- this call to confirm the correct parameter shape against, so rather
-- than guess further this was removed instead of left as a
-- misleading, always-wrong signal in the Cargo Balance Inspector.
-- getStockCount most likely tracks cargo queued for pickup by a
-- vehicle (matching the Entity At Stock System's own doc wording,
-- "obtains the amount of item WAITING at a given stock"), not an
-- industry's raw-material reserve level -- a genuinely different
-- concept from the panel's "Stored" figure. The RECIPE CHECK signal
-- above (real all-time delivered totals) remains the trusted
-- mechanism -- it independently agreed with this exact screenshot's
-- real imbalance (Goole Steel mill needing more COAL) both times.


-- Returns the construction fileName for a given industry (SIM_BUILDING)
-- entity, or nil if anything along the chain fails.
function M.getIndustryFileName(industryEntityId)

    if industryEntityId == nil or industryEntityId < 0 then
        return nil
    end

    local okConstruction, constructionId =
        pcall(
            api.engine.system.streetConnectorSystem.getConstructionEntityForSimBuilding,
            industryEntityId
        )

    if not okConstruction
        or constructionId == nil
        or constructionId < 0
    then
        return nil
    end

    local okComponent, construction =
        pcall(
            api.engine.getComponent,
            constructionId,
            api.type.ComponentType.CONSTRUCTION
        )

    if not okComponent or construction == nil then
        return nil
    end

    return construction.fileName

end


-- Returns this industry's single real output cargo type (e.g. "COAL"),
-- or nil if its fileName isn't in the known table.
function M.getOutputCargoType(industryEntityId)

    local fileName = M.getIndustryFileName(industryEntityId)

    if fileName == nil then
        return nil
    end

    return OUTPUT_CARGO_TYPES[fileName]

end


-- Returns { cargoType = ratioWeight, ... } for a known multi-input
-- industry, or nil (unknown fileName, or a real single/zero-input
-- industry with nothing to balance).
function M.getInputRatio(industryEntityId)

    local fileName = M.getIndustryFileName(industryEntityId)

    if fileName == nil then
        return nil
    end

    return INPUT_RATIOS[fileName]

end


-- Returns this industry's single input cargo type (e.g. "OIL" for a
-- fuel refinery), or nil (unknown fileName, a multi-input industry
-- covered by getInputRatio instead, or a real zero-input producer).
function M.getSingleInputType(industryEntityId)

    local fileName = M.getIndustryFileName(industryEntityId)

    if fileName == nil then
        return nil
    end

    return SINGLE_INPUT_TYPES[fileName]

end


-- ============================================================
-- DISCOVERY: WHICH INDUSTRIES DOES THIS MAP ACTUALLY HAVE THAT WE
-- DON'T RECOGNIZE?
--
-- Player's question: full automatic ratio discovery isn't proven
-- feasible -- the real, resolved recipe (result.rule, computed inside
-- an industry's own updateFn at build time) isn't exposed on any
-- live-queryable component found so far, and reading an arbitrary
-- mod's raw .con file back out at runtime isn't a proven mechanism
-- either. Every lookup above already degrades safely for an unknown
-- fileName (returns nil, silently skipped, never crashes) -- but
-- "silently unsupported" isn't the same as "known to be missing."
--
-- api.res.constructionRep.getAll() is a REAL, confirmed function --
-- used live in the "AI Builder" mod (workshop 2820656841) to
-- enumerate every loaded construction, vanilla or modded, filtering
-- for "industry/" in the path (excluding "industry/extension/", the
-- exact same filter that mod uses). This turns "silently unsupported"
-- into a concrete list: which real industry fileNames exist on THIS
-- map that aren't in OUTPUT_CARGO_TYPES yet -- the fastest path to
-- extending real support to a modded economy (add heavier industry
-- packs, get a real fileName list back, extend the tables above by
-- hand using the same real-file-reading method Decision 108 already
-- proved out) rather than a live "universal detector" that has not
-- been shown to be possible.
-- ============================================================

function M.isKnownIndustry(fileName)
    return OUTPUT_CARGO_TYPES[fileName] ~= nil
end


-- Every construction fileName currently loaded whose path contains
-- "industry/" (same filter AI Builder's own real code uses), vanilla
-- or modded alike.
function M.findAllIndustryFileNames()

    local result = {}

    local ok, allFileNames =
        pcall(function()
            return api.res.constructionRep.getAll()
        end)

    if not ok or allFileNames == nil then
        return result
    end

    for _, fileName in pairs(allFileNames) do

        if type(fileName) == "string"
            and fileName:find("industry")
            and not fileName:find("industry/extension/")
        then
            result[#result + 1] = fileName
        end

    end

    return result

end


-- Compares REAL delivered amounts (the same shape stations.
-- getUnloadedAmountsByType already produces, e.g. {IRON_ORE=800,
-- COAL=200}) against the recipe's real ratio, and returns the cargo
-- type that is proportionally MOST short relative to what the recipe
-- actually wants -- or nil if this industry has no known multi-input
-- ratio at all.
--
-- Delivered amounts are normalized by their ratio weight before
-- comparing, so a genuinely asymmetric ratio (say 4:1) is judged
-- correctly: "4 units of iron delivered, 1 unit of coal delivered" is
-- perfectly ON-TARGET for a 4:1 recipe, not "iron is 4x ahead."
function M.findMostNeededInput(industryEntityId, unloadedAmountsByType)

    local ratio = M.getInputRatio(industryEntityId)

    if ratio == nil then
        return nil
    end

    local worstCargoType = nil
    local worstNormalized = nil

    for cargoType, ratioWeight in pairs(ratio) do

        local delivered =
            (unloadedAmountsByType and unloadedAmountsByType[cargoType]) or 0

        local normalized = delivered / ratioWeight

        if worstNormalized == nil or normalized < worstNormalized then
            worstNormalized = normalized
            worstCargoType = cargoType
        end

    end

    return worstCargoType

end


return M
