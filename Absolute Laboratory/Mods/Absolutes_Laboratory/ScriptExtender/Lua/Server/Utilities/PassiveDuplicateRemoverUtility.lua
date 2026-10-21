---@diagnostic disable: param-type-mismatch

PassiveDupeRemoverUtility = {}

local config = ConfigurationStructure.config.utilities.passiveDupeRemover

---@param passiveId string
---@return boolean
local function shouldRemovePassive(passiveId)
    if config.whitelistMode then
        return TableUtils:IndexOf(config.whitelist, passiveId) == nil
    else
        return TableUtils:IndexOf(config.blacklist, passiveId) ~= nil
    end
end

---@class DupeRecord
---@field timesSeen number
---@field storedPassives {[string]: number}
---@field limited boolean

---@type {[Guid] : DupeRecord}
local traversedEntities = {}

-- Each resetTracker "chain" captures the loopToken value that was current when IT started. If the
-- shared token has since moved on (a newer chain started, or the deduplicator was unloaded), the call
-- stops recursing instead of rescheduling itself. This is deliberately a rising counter rather than a
-- plain boolean: a boolean can't tell an old chain's already-in-flight timer apart from a brand new
-- chain that happens to be active by the time that old timer fires, which would let the old chain
-- resume rescheduling itself ("resurrecting" a chain that should have died) - and with Combat Only
-- re-triggering a load/unload cycle on every combat, that could stack up into several concurrent
-- 6-second loops over a long play session instead of at most one.
local loopToken = 0

---@param myToken integer
local function resetTracker(myToken)
    for key, val in pairs(traversedEntities) do
        if not val.limited then
            traversedEntities[key] = nil
        else
            val.timesSeen = 0
        end
    end

    if myToken == loopToken then
        Ext.Timer.WaitFor(6000, function() resetTracker(myToken) end)
    end
end

---@type "Unloaded"|"Paused"|"Running"
local stateLock = "Unloaded"

local subId

-- Bumped on every advanceState call, so a RunBriefly's delayed auto-pause can tell whether it's still the
-- most recent request or whether something newer (another Mutation pass starting/finishing) has happened
-- since - see RunBriefly below.
local generation = 0

-- Tears the subscription down immediately, regardless of whether any PassiveContainer event happens
-- to fire again to notice a pending Pause. Used both by the subscription's own lazy check below (kept
-- for the mid-pass "just ignore changes until this Apply/Undo finishes" case, where another event is
-- imminent anyway) and directly by RunBriefly's grace-window timeout, which can't rely on a future
-- event ever showing up during genuine idle time.
local function unloadDeduper()
    if subId then
        Ext.Entity.Unsubscribe(subId)
        subId = nil
    end
    stateLock = "Unloaded"
    loopToken = loopToken + 1
end

local function loadDeduper()
    if not subId then
        loopToken = loopToken + 1
        resetTracker(loopToken)

        ---@param entity EntityHandle
        subId = Ext.Entity.Subscribe("PassiveContainer", function(entity)
            if stateLock == "Paused" or not config.enabled then
                unloadDeduper()
                return
            end

            local labVar = entity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME]
            if entity.ServerCharacter
                and labVar
                and labVar.appliedMutators
                and labVar.appliedMutators[PassiveListMutator.name]
                and (entity.Health and entity.Health.Hp > 0)
            then
                traversedEntities[entity.Uuid.EntityUuid] = traversedEntities[entity.Uuid.EntityUuid] or {
                    timesSeen = 0,
                    storedPassives = {},
                    limited = false
                }

                local record = traversedEntities[entity.Uuid.EntityUuid]
                if record.limited and record.timesSeen > 1 then
                    return
                elseif not record.limited and record.timesSeen > 3 then
                    Logger:BasicWarning(
                        "%s has been processed %d times in the past 6 seconds due to something constantly updating its PassiveContainer - ratelimiting them to one interaction per 6 seconds. Passives processed, if any: %s",
                        EntityRecorder:GetEntityName(entity), record.timesSeen, record.storedPassives)

                    record.limited = true

                    return
                end

                record.timesSeen = record.timesSeen + 1

                ---@type {[string]: EntityHandle[]}
                local passivesSeen = {}
                for _, passiveEntry in pairs(entity.PassiveContainer.Passives) do
                    if shouldRemovePassive(passiveEntry.Passive.PassiveId) then
                        passivesSeen[passiveEntry.Passive.PassiveId] = passivesSeen[passiveEntry.Passive.PassiveId] or {}
                        table.insert(passivesSeen[passiveEntry.Passive.PassiveId], passiveEntry)
                    end
                end

                local removedPassives = {}

                for passiveId, passiveHandles in pairs(passivesSeen) do
                    if #passiveHandles > 1 then
                        record.storedPassives[passiveId] = #passiveHandles
                        removedPassives[passiveId] = #passiveHandles - 1

                        for i = 2, #passiveHandles do
                            Ext.System.ServerPassive.RemovePassives[passiveHandles[i]] = true
                        end
                    end
                end

                if next(removedPassives) then
                    Logger:BasicDebug("Removed the following { passive(s) : numberOfDuplicates } from entity %s_%s due to duplication: %s",
                        EntityRecorder:GetEntityName(entity),
                        entity.Uuid.EntityUuid,
                        removedPassives)
                end
            end
        end)
    end
end

---@param desiredState "Paused"|"Running"
function PassiveDupeRemoverUtility:advanceState(desiredState)
    generation = generation + 1

    if stateLock == "Unloaded" then
        if desiredState == "Running" and config.enabled then
            Logger:BasicInfo("Starting Passive Deduplicator")
            loadDeduper()
        end
    else
        Logger:BasicInfo("Changing Passive Deduplicator State To: %s", desiredState)
        stateLock = desiredState
    end
end

--- Resumes the deduplicator (same as advanceState("Running")), but automatically pauses it again after
--- durationMs unless something newer has happened in the meantime (another Apply/Undo/RunBriefly call).
--- This is what MutationProfileExecutor now uses instead of a bare advanceState("Running") - the whole
--- point of this deduplicator is to catch a duplicate passive that Lab's OWN mutators might have just
--- introduced, which should show up (if at all) within a few seconds of that pass finishing, not to stay
--- subscribed to every PassiveContainer change on the level for the rest of the session/combat. Left
--- running indefinitely, its per-change handler doing real work (iterating passives, blacklist lookups)
--- every time ANY entity's passives change - not just ones Lab touched - was adding up to real, ongoing
--- cost during active combat, which is what "the status window disappeared but I'm still lagging" was.
---@param durationMs integer
function PassiveDupeRemoverUtility:RunBriefly(durationMs)
    self:advanceState("Running")

    local myGeneration = generation
    Ext.Timer.WaitFor(durationMs, function()
        if myGeneration == generation then
            -- Unloads directly rather than going through advanceState("Paused") - that only sets a flag
            -- the subscription notices on its NEXT PassiveContainer event, which may not come for a long
            -- time (or at all) if the player is genuinely idle outside combat. Tearing down here instead
            -- means this grace window is a hard upper bound on how long the deduplicator (and its 6-
            -- second reset loop) stays alive after a Mutation pass, not just a best-effort one.
            Logger:BasicInfo("Passive Deduplicator's grace window elapsed with no further Mutation activity since - unloading")
            unloadDeduper()
        end
    end)
end
