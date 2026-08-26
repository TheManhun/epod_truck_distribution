local log = require("epod_td.log")
local lines = require("epod_td.lines")
local stations = require("epod_td.stations")
local vehicles = require("epod_td.vehicles")
local managed_registry = require("epod_td.managed_registry")
local line_ownership = require("epod_td.line_ownership")
local industry_naming = require("epod_td.industry_naming")
local industry_recipes = require("epod_td.industry_recipes")

local M = {}


-- ============================================================
-- BUILD REAL SUPPLY CHAINS: MERGE TWO SEPARATE HUB<->INDUSTRY LINES
-- INTO ONE HUB<->SOURCE->CONSUMER CHAIN LINE
--
-- Player's own finding, from a real dump: a hub commonly runs TWO
-- completely separate single-stop lines -- one to a raw producer (e.g.
-- Goole Coal mine) and one to a consumer that needs that exact cargo
-- (e.g. Goole Steel mill, confirmed via industry_recipes.lua's RECIPE
-- CHECK to be genuinely short on COAL, and independently confirmed via
-- the player's own screenshot of TF2's native industry panel). Coal
-- gets hauled to the hub, then whatever happens on the separate
-- hub<->mill line is incidental -- nothing in this mod's dispatcher
-- reacts to an industry's INPUT need at all, only to OUTBOUND waiting
-- cargo. A genuine 3-stop chain line (hub -> source -> consumer,
-- looping back to hub) fixes this at the root: the same truck picks up
-- coal at the mine and drops it directly at the mill, no hub
-- hand-off required.
--
-- TWO STAGES, same deliberate split as line_splitter.lua's own
-- Stage 1 / Stage 2 (and for the identical reason): Stage 1
-- (M.buildChainLine) is purely additive -- creates the new line,
-- touches neither old line, moves no vehicle. Stage 2
-- (M.migrateVehiclesAndCleanup) is the more consequential step that
-- actually moves real vehicles and deletes the old lines, using the
-- exact same proven hold -> setLine -> release sequence and
-- empty-vehicle-only guard (vehicles.isVehicleEmpty) already relied on
-- everywhere else in this codebase that reassigns a vehicle
-- mid-service. A vehicle currently carrying cargo is left on its old
-- line for THIS run -- Stage 2 is safe to re-run later once it
-- delivers and goes empty (same "try again" partial-progress model
-- line_splitter's own Stage 2 already uses).
--
-- Detection is proximity + real-recipe based, not a cargo-flow audit:
-- a "chain candidate" is a hub with one simple line to an industry
-- producing cargo type X (industry_recipes.getOutputCargoType) and
-- another simple line to a DIFFERENT industry whose recipe currently
-- shows X as its most-needed input (industry_recipes.
-- findMostNeededInput, the exact signal already live-confirmed twice
-- against the player's own screenshots). Only ever considers a line
-- with exactly ONE real (non-hub) destination -- an already-more-
-- complex line (a hand-built chain, Decision 106) is left alone.
-- ============================================================


local function findStopByStationGroup(line, stationGroupId)

    local stops = lines.safeField(line, "stops")
    local count = lines.safeLength(stops)

    for index = 1, count do

        local stop = stops[index]

        if stop ~= nil
            and lines.safeField(stop, "stationGroup") == stationGroupId
        then
            return stop
        end

    end

    return nil

end


-- Classifies a hub's simple (single real destination) managed lines
-- into PRODUCER (industry with a known output cargo type) and
-- CONSUMER (industry with a known input ratio AND a real current
-- shortfall) roles, then pairs up any consumer's most-needed cargo
-- type with a producer of that exact type at the SAME hub.
function M.findChainCandidates(hubStationGroupId)

    local candidates = {}

    local okLines, managedLines =
        pcall(vehicles.getManagedLinesForStation, hubStationGroupId)

    if not okLines or managedLines == nil then
        return candidates
    end

    local producersByCargoType = {}
    local consumers = {}

    for _, lineInfo in ipairs(managedLines) do

        local realDestinations = {}

        for _, destination in ipairs(lineInfo.destinations or {}) do

            if destination.stationGroup ~= hubStationGroupId then
                realDestinations[#realDestinations + 1] = destination
            end

        end

        -- Only ever a plain, un-chained single-stop line -- an
        -- already-multi-stop line (including a hand-built or
        -- previously-machine-built chain) is left alone entirely.
        if #realDestinations == 1 then

            local destination = realDestinations[1]

            local okEntity, destinationEntity =
                pcall(game.interface.getEntity, destination.stationGroup)

            local position =
                okEntity
                    and destinationEntity ~= nil
                    and destinationEntity.position
                    or nil

            if position ~= nil then

                local industryId, industryName =
                    industry_naming.findNearestIndustry(position)

                if industryId ~= nil then

                    local outputCargoType =
                        industry_recipes.getOutputCargoType(industryId)

                    if outputCargoType ~= nil
                        and producersByCargoType[outputCargoType] == nil
                    then

                        producersByCargoType[outputCargoType] = {
                            lineId = lineInfo.id,
                            stationGroup = destination.stationGroup,
                            industryId = industryId,
                            industryName = industryName,
                        }

                    end

                    local ratio = industry_recipes.getInputRatio(industryId)

                    if ratio ~= nil then

                        local unloadedAmounts =
                            stations.getUnloadedAmountsByType(
                                destination.stationGroup
                            )

                        local mostNeeded =
                            industry_recipes.findMostNeededInput(
                                industryId,
                                unloadedAmounts
                            )

                        if mostNeeded ~= nil then

                            consumers[#consumers + 1] = {
                                lineId = lineInfo.id,
                                stationGroup = destination.stationGroup,
                                industryId = industryId,
                                industryName = industryName,
                                neededCargoType = mostNeeded,
                            }

                        end

                    end

                    -- Single-input industries (fuel refinery, tools
                    -- factory, etc.) have no ratio to compare -- a
                    -- direct chain to a real producer of their one
                    -- input is unconditionally worth it, no imbalance
                    -- check needed. Confirmed live missing before this:
                    -- a Stow-on-the-Wold Oil refinery and Carnforth
                    -- Fuel refinery sat as two separate single-stop
                    -- lines at the same hub, exactly the coal/steel
                    -- pattern, invisible to the ratio-only check above.
                    local singleInputType =
                        industry_recipes.getSingleInputType(industryId)

                    if singleInputType ~= nil then

                        consumers[#consumers + 1] = {
                            lineId = lineInfo.id,
                            stationGroup = destination.stationGroup,
                            industryId = industryId,
                            industryName = industryName,
                            neededCargoType = singleInputType,
                        }

                    end

                end

            end

        end

    end

    for _, consumer in ipairs(consumers) do

        local producer = producersByCargoType[consumer.neededCargoType]

        if producer ~= nil
            and producer.stationGroup ~= consumer.stationGroup
            and producer.lineId ~= consumer.lineId
        then

            candidates[#candidates + 1] = {
                hubStationGroupId = hubStationGroupId,
                cargoType = consumer.neededCargoType,
                sourceLineId = producer.lineId,
                sourceStationGroup = producer.stationGroup,
                sourceIndustryName = producer.industryName,
                consumerLineId = consumer.lineId,
                consumerStationGroup = consumer.stationGroup,
                consumerIndustryName = consumer.industryName,
            }

        end

    end

    return candidates

end


-- STAGE 1: purely additive. Builds a new hub -> source -> consumer
-- line (looping back to the hub, TF2's own default for any line) and
-- registers it as managed. Does not touch either old line or move any
-- vehicle.
function M.buildChainLine(candidate, playerEntity, onComplete)

    local sourceLine = lines.get(candidate.sourceLineId)
    local consumerLine = lines.get(candidate.consumerLineId)

    if sourceLine == nil or consumerLine == nil then

        log.info("CHAIN BUILDER: source or consumer line no longer exists -- skipping.")

        if onComplete ~= nil then
            onComplete(nil)
        end

        return

    end

    local hubStop = findStopByStationGroup(sourceLine, candidate.hubStationGroupId)
    local sourceStop = findStopByStationGroup(sourceLine, candidate.sourceStationGroup)
    local consumerStop = findStopByStationGroup(consumerLine, candidate.consumerStationGroup)

    if hubStop == nil or sourceStop == nil or consumerStop == nil then

        log.info("CHAIN BUILDER: could not find one of the three real stops -- skipping.")

        if onComplete ~= nil then
            onComplete(nil)
        end

        return

    end

    local hubName = stations.getEntityName(candidate.hubStationGroupId)

    local newLineName =
        "●* "
            .. tostring(candidate.sourceIndustryName)
            .. " -> "
            .. tostring(candidate.consumerIndustryName)
            .. " <-> "
            .. tostring(hubName)

    local existingLineId = lines.findByName(newLineName)

    if existingLineId ~= nil then

        log.info("CHAIN BUILDER: a line named \"" .. newLineName .. "\" already exists -- skipping.")

        if onComplete ~= nil then
            onComplete(existingLineId)
        end

        return

    end

    local newLine = api.type.Line.new()

    if newLine == nil then

        log.info("CHAIN BUILDER FAILED: api.type.Line.new() returned nil.")

        if onComplete ~= nil then
            onComplete(nil)
        end

        return

    end

    local newStops = lines.safeField(newLine, "stops")

    if newStops == nil then

        log.info("CHAIN BUILDER FAILED: new native Line has no stops container.")

        if onComplete ~= nil then
            onComplete(nil)
        end

        return

    end

    for _, sourceStopEntry in ipairs({ hubStop, sourceStop, consumerStop }) do

        local nativeStop = lines.makeNativeStopCopy(sourceStopEntry)
        local ok, err = lines.appendNativeStop(newStops, nativeStop)

        if not ok then

            log.info("CHAIN BUILDER FAILED appending stop: " .. tostring(err))

            if onComplete ~= nil then
                onComplete(nil)
            end

            return

        end

    end

    local okColor, color = pcall(api.type.Vec3f.new, 0.85, 0.5, 0.15)

    if not okColor or color == nil then

        log.info("CHAIN BUILDER FAILED building color: " .. tostring(color))

        if onComplete ~= nil then
            onComplete(nil)
        end

        return

    end

    local okCommand, commandOrError =
        pcall(api.cmd.make.createLine, newLineName, color, playerEntity, newLine)

    if not okCommand then

        log.info("CHAIN BUILDER FAILED creating command: " .. tostring(commandOrError))

        if onComplete ~= nil then
            onComplete(nil)
        end

        return

    end

    log.info("CHAIN BUILDER: creating \"" .. newLineName .. "\"")

    local okSend, sendErr =
        pcall(function()

            api.cmd.sendCommand(commandOrError, function(cmd, success)

                log.info("CHAIN BUILDER: create result: " .. tostring(success))

                if not success then

                    if onComplete ~= nil then
                        onComplete(nil)
                    end

                    return

                end

                local newLineId = lines.findByName(newLineName)

                if newLineId ~= nil then
                    managed_registry.register(newLineId)
                    line_ownership.claim(newLineId, candidate.hubStationGroupId)
                end

                if onComplete ~= nil then
                    onComplete(newLineId)
                end

            end)

        end)

    if not okSend then

        log.info("CHAIN BUILDER FAILED sending command: " .. tostring(sendErr))

        if onComplete ~= nil then
            onComplete(nil)
        end

    end

end


-- Moves whichever vehicles on oldLineId are CURRENTLY EMPTY onto
-- newLineId, one at a time (hold -> setLine -> release, the same
-- proven sequence used everywhere else in this codebase for a
-- mid-service reassignment). A vehicle still carrying cargo is left
-- exactly where it is -- safe to try again once it delivers.
local function migrateEmptyVehiclesNext(vehicleIds, index, newLineId, movedCount, onComplete)

    local vehicleId = vehicleIds[index]

    if vehicleId == nil then
        onComplete(movedCount)
        return
    end

    if vehicles.isVehicleEmpty(vehicleId) ~= true then

        migrateEmptyVehiclesNext(vehicleIds, index + 1, newLineId, movedCount, onComplete)
        return

    end

    vehicles.setManualDeparture(vehicleId, true, function(holdSuccess)

        if not holdSuccess then

            migrateEmptyVehiclesNext(vehicleIds, index + 1, newLineId, movedCount, onComplete)
            return

        end

        vehicles.setLine(vehicleId, newLineId, 0, function(setLineSuccess)

            vehicles.setManualDeparture(vehicleId, false, function()

                log.info(
                    "CHAIN BUILDER: moved vehicle "
                        .. tostring(vehicleId)
                        .. " onto chain line "
                        .. tostring(newLineId)
                        .. ": "
                        .. tostring(setLineSuccess)
                )

                migrateEmptyVehiclesNext(
                    vehicleIds,
                    index + 1,
                    newLineId,
                    setLineSuccess and (movedCount + 1) or movedCount,
                    onComplete
                )

            end)

        end)

    end)

end


-- Deletes oldLineId if (and only if) it is now genuinely empty and
-- still resolves to a real line -- api.cmd.make.deleteLine on a
-- stale/unreadable ID is a native engine crash, not a catchable Lua
-- error, so this NEVER attempts the delete without both checks
-- passing first (same discipline as line_splitter.deleteEmptyManagedLine).
local function deleteIfEmpty(oldLineId, onComplete)

    if lines.get(oldLineId) == nil then
        onComplete()
        return
    end

    if #vehicles.getVehiclesForLine(oldLineId) > 0 then

        log.info(
            "CHAIN BUILDER: old line "
                .. tostring(oldLineId)
                .. " still has vehicle(s) carrying cargo -- left in place, retry later."
        )

        onComplete()
        return

    end

    local okCommand, commandOrError = pcall(api.cmd.make.deleteLine, oldLineId)

    if not okCommand then

        log.info("CHAIN BUILDER: delete command error for line " .. tostring(oldLineId) .. ": " .. tostring(commandOrError))

        onComplete()
        return

    end

    local okSend, sendErr =
        pcall(function()

            api.cmd.sendCommand(commandOrError, function(cmd, success)

                log.info("CHAIN BUILDER: deleted old line " .. tostring(oldLineId) .. ": " .. tostring(success))

                if success then
                    managed_registry.unregister(oldLineId)
                end

                onComplete()

            end)

        end)

    if not okSend then

        log.info("CHAIN BUILDER: delete send error for line " .. tostring(oldLineId) .. ": " .. tostring(sendErr))

        onComplete()

    end

end


-- STAGE 2: migrates whatever empty vehicles exist right now from BOTH
-- old lines onto the new chain line, then deletes each old line if (and
-- only if) it ends up fully empty. A vehicle still mid-trip with cargo
-- is left on its old line -- safe to run this again later.
function M.migrateVehiclesAndCleanup(candidate, newLineId, onComplete)

    local sourceVehicleIds = vehicles.getVehiclesForLine(candidate.sourceLineId)
    local consumerVehicleIds = vehicles.getVehiclesForLine(candidate.consumerLineId)

    migrateEmptyVehiclesNext(sourceVehicleIds, 1, newLineId, 0, function(movedFromSource)

        migrateEmptyVehiclesNext(consumerVehicleIds, 1, newLineId, 0, function(movedFromConsumer)

            deleteIfEmpty(candidate.sourceLineId, function()

                deleteIfEmpty(candidate.consumerLineId, function()

                    if onComplete ~= nil then
                        onComplete(movedFromSource + movedFromConsumer)
                    end

                end)

            end)

        end)

    end)

end


-- Runs Stage 1 + Stage 2 for every chain candidate found at this hub,
-- one at a time. Read-only detection first (M.findChainCandidates),
-- then each candidate's own build + migrate before moving to the next.
local function processChainCandidateNext(candidates, index, playerEntity, builtCount, movedCount, onComplete)

    local candidate = candidates[index]

    if candidate == nil then

        log.info(
            "CHAIN BUILDER COMPLETE: "
                .. tostring(builtCount)
                .. " chain line(s) built, "
                .. tostring(movedCount)
                .. " vehicle(s) moved."
        )

        if onComplete ~= nil then
            onComplete(builtCount, movedCount)
        end

        return

    end

    M.buildChainLine(candidate, playerEntity, function(newLineId)

        if newLineId == nil then

            processChainCandidateNext(candidates, index + 1, playerEntity, builtCount, movedCount, onComplete)
            return

        end

        M.migrateVehiclesAndCleanup(candidate, newLineId, function(moved)

            processChainCandidateNext(
                candidates,
                index + 1,
                playerEntity,
                builtCount + 1,
                movedCount + moved,
                onComplete
            )

        end)

    end)

end


function M.runChainBuilderForHub(hubStationGroupId, onComplete)

    log.info("----------------------------------------")
    log.info("CHAIN BUILDER: scanning hub " .. tostring(hubStationGroupId))
    log.info("----------------------------------------")

    local candidates = M.findChainCandidates(hubStationGroupId)

    if #candidates == 0 then

        log.info("CHAIN BUILDER: no chain candidates found.")

        if onComplete ~= nil then
            onComplete(0, 0)
        end

        return

    end

    for _, candidate in ipairs(candidates) do

        log.info(
            "CHAIN BUILDER CANDIDATE: "
                .. tostring(candidate.sourceIndustryName)
                .. " -> "
                .. tostring(candidate.consumerIndustryName)
                .. " (cargo: "
                .. tostring(candidate.cargoType)
                .. ")"
        )

    end

    local okPlayer, playerEntity = pcall(api.engine.util.getPlayer)

    if not okPlayer or playerEntity == nil then

        log.info("CHAIN BUILDER FAILED: api.engine.util.getPlayer() unavailable: " .. tostring(playerEntity))

        if onComplete ~= nil then
            onComplete(0, 0)
        end

        return

    end

    processChainCandidateNext(candidates, 1, playerEntity, 0, 0, onComplete)

end


return M
