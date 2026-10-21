Ext.Vars.RegisterModVariable(ModuleUUID, "ActiveMutationProfile", {
    Server = true,
    Client = true,
    WriteableOnServer = true,
    WriteableOnClient = true,
    SyncToClient = true,
    SyncToServer = true,
    SyncOnWrite = true
})

Ext.Vars.RegisterModVariable(ModuleUUID, "HasDisabledProfiles", {
    Server = true,
    Client = true,
    WriteableOnServer = true,
    WriteableOnClient = true,
    SyncToClient = true,
    SyncToServer = true,
    SyncOnWrite = true
})

---@type RX
RX = Ext.Require("Utilities/Reactivex/_init.lua")

---@class MutationProfileExecutionTracker
local trackerSeed = {
    ["Entities Processed"] = 0,
    ["Time Spent (ms)"] = 0,
    ["Number Of Ticks"] = 0,
    ---@type string?
    ["Error"] = nil
}

---@class MutationProfileExecutor
MutationProfileExecutor = {
    config = MutationConfigurationProxy,
    running = nil,
    ---@type boolean?
    runningUndo = nil,
    ---@type "Apply"|"Undo"
    currentAction = "Apply",
    ---@type {processed: number, total: number}
    progress = { processed = 0, total = 0 },
    ---@type integer?
    statusTimer = nil,
    tempState = {
        ---@type {[Guid] : {[Guid]: SelectorPredicate}}
        cachedSelectors = {},
        missingMutations = {}
    },
    lockTimer = nil,
    ---@type boolean?
    rerunTransientMutators = false,
    ---@type fun()?
    onFinishCallback = nil,
    ---@type DripScheduler?
    activeDripScheduler = nil,
    -- Targeted (combat-triggered) Applies that arrived while another pass was still running. Previously these
    -- were silently dropped by the "currently executing" early-return, so reinforcements/second waves joining a
    -- fight while the first batch was still being mutated never got mutated at all. Drained in completionFunc.
    ---@type {entities: Guid[], callbacks: fun()[]}
    pendingTargeted = { entities = {}, callbacks = {} },
    activeProfileInfo = {
        id = "",
        modId = "",
        displayName = "",
        ---@type MutationProfile
        profile = {},
        startTime = 0,
    },
}

---@param state "Started"|"Completed"|"Errored"
function MutationProfileExecutor:completionFunc(state)
    Logger.mode = "buffer"
    -- RunBriefly rather than advanceState("Running") - this only needs to stay subscribed long enough to
    -- catch a duplicate passive this pass itself might have just introduced, not for the rest of combat.
    -- See PassiveDuplicateRemoverUtility.lua's RunBriefly for why leaving it running indefinitely was a
    -- real, ongoing performance cost, separate from the Apply/Undo pass itself finishing.
    PassiveDupeRemoverUtility:RunBriefly(15000)
    ModEventsManager:MutationProfileExecuted(state)
    self:broadcastStatus(self.currentAction or "Apply", state == "Completed" and "Complete" or "Error")
    self:stopStatusTicker()

    -- If an entity errored mid-pipeline its permit is never checked back in, so the DripScheduler never sees
    -- "all permits returned" and its per-frame Tick handler stayed subscribed for the rest of the session -
    -- one more leaked handler per combat that hit an error. Always tear it down once the pass is over.
    if self.activeDripScheduler then
        self.activeDripScheduler:dispose()
        self.activeDripScheduler = nil
    end

    local wasApply = self.running
    self.running = nil
    self.runningUndo = nil
    -- NOT resetting ListConfigurationManager.progressionIndex here anymore - it's built from static data that
    -- never changes mid-session, and wiping it after every pass meant the first Spell/Passive List lookup of the
    -- NEXT pass rebuilt the hierarchy across every Progression in the game. Under Combat Only that rebuild
    -- happened at the start of every single fight. It's now reset once per level load instead.
    SelectorInterface:cleanup()

    if wasApply then
        local callback = self.onFinishCallback
        self.onFinishCallback = nil
        if callback then
            callback()
        end
    end

    self:drainPendingTargeted()
end

---@param entities Guid[]
---@param onFinishCallback fun()?
function MutationProfileExecutor:queueTargeted(entities, onFinishCallback)
    for _, entityId in ipairs(entities) do
        if not TableUtils:IndexOf(self.pendingTargeted.entities, entityId) then
            table.insert(self.pendingTargeted.entities, entityId)
        end
    end
    if onFinishCallback then
        table.insert(self.pendingTargeted.callbacks, onFinishCallback)
    end
end

function MutationProfileExecutor:drainPendingTargeted()
    if not next(self.pendingTargeted.entities) and not next(self.pendingTargeted.callbacks) then
        return
    end

    local pending = self.pendingTargeted
    self.pendingTargeted = { entities = {}, callbacks = {} }

    -- Deferred rather than inline, so this runs outside of whatever RX completion chain called completionFunc
    Ext.Timer.WaitFor(1, function()
        local function combinedCallback()
            for _, callback in ipairs(pending.callbacks) do
                callback()
            end
        end

        local stillNeedMutating = {}
        for _, entityId in ipairs(pending.entities) do
            local entity = Ext.Entity.Get(entityId)
            if entity and not entity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME] then
                table.insert(stillNeedMutating, entityId)
            end
        end

        if next(stillNeedMutating) then
            Logger:BasicInfo("Running queued combat Apply for %d entities that joined while the previous pass was running", #stillNeedMutating)
            self:ExecuteProfile(false, combinedCallback, table.unpack(stillNeedMutating))
        else
            combinedCallback()
        end
    end)
end

---@param action "Apply"|"Undo"
---@param stage "Starting"|"Running"|"Complete"|"Error"
---@param extra table?
---@return table
function MutationProfileExecutor:statusPayload(action, stage, extra)
    local payload = {
        action = action,
        stage = stage,
        profile = (action == "Apply" and self.activeProfileInfo.displayName ~= "" and self.activeProfileInfo.displayName) or nil,
        processed = self.progress.processed,
        total = self.progress.total,
        timeElapsed = self.activeProfileInfo.startTime and math.floor(Ext.Timer.MonotonicTime() - self.activeProfileInfo.startTime) or 0,
    }

    if extra then
        for k, v in pairs(extra) do
            payload[k] = v
        end
    end

    return payload
end

--- Sends a snapshot of current progress to every client's status window. No-ops if the user has turned the status window Off.
---@param action "Apply"|"Undo"
---@param stage "Starting"|"Running"|"Complete"|"Error"
---@param extra table?
function MutationProfileExecutor:broadcastStatus(action, stage, extra)
    if ConfigurationStructure.config.mutations.settings.profileExecution.statusView == "Off" then
        return
    end

    Channels.MutationExecutionStatus:Broadcast(self:statusPayload(action, stage, extra))
end

--- Starts a 500ms repeating broadcast of progress while running/runningUndo is true. Self-terminates once neither is true anymore.
---@param action "Apply"|"Undo"
function MutationProfileExecutor:startStatusTicker(action)
    if ConfigurationStructure.config.mutations.settings.profileExecution.statusView == "Off" then
        return
    end

    local function tick()
        if not (self.running or self.runningUndo) then
            return
        end

        self:broadcastStatus(action, "Running")
        self.statusTimer = Ext.Timer.WaitFor(500, tick)
    end

    tick()
end

function MutationProfileExecutor:stopStatusTicker()
    if self.statusTimer then
        Ext.Timer.Cancel(self.statusTimer)
        self.statusTimer = nil
    end
end

---@param rerunTransient boolean?
---@param onFinishCallback fun()?
---@param ... Guid
function MutationProfileExecutor:ExecuteProfile(rerunTransient, onFinishCallback, ...)
    self.config = MutationConfigurationProxy

    local specifiedEntities = { ... }

    local trackerFile = FileUtils:LoadTableFile(EntityRecorder.trackerFilename)
    if trackerFile and next(trackerFile) then
        Logger:BasicInfo("Recorder is currently running - skipping Mutations")
        if onFinishCallback then onFinishCallback() end
        return
    end

    if self.running or self.runningUndo then
        if next(specifiedEntities) then
            Logger:BasicDebug("Mutation Profile is currently executing - queueing %d entities to run once it finishes", #specifiedEntities)
            self:queueTargeted(specifiedEntities, onFinishCallback)
        else
            Logger:BasicDebug("Mutation Profile is currently executing - duplicate call came from %s", debug.traceback())
            if onFinishCallback then onFinishCallback() end
        end
        return
    end

    if ForceCleanUtility and ForceCleanUtility.running then
        Logger:BasicDebug("A Force Clean is currently running - skipping this Apply until it finishes")
        if onFinishCallback then onFinishCallback() end
        return
    end

    PassiveDupeRemoverUtility:advanceState("Paused")

    if self:determineActiveProfile() then
        if not ConfigurationStructure.config.mutations.settings.profileExecution.viewedTutorial then
            Channels.LaunchTutorial:SendToClient(nil, Osi.GetReservedUserID(Osi.GetHostCharacter()))
        end

        self.running = true
        self.currentAction = "Apply"
        self.progress.processed = 0
        self.progress.total = 0

        ModEventsManager:MutationProfileExecuted("Started")
        self:broadcastStatus("Apply", "Starting")
        self:startStatusTicker("Apply")

        Logger:BasicInfo("======= Starting Mutation Profile %s =======\n", self.activeProfileInfo.displayName)

        Logger.mode = "timer"

        self.rerunTransientMutators = rerunTransient
        self.onFinishCallback = onFinishCallback

        ---@type string
        local currentLevel = Ext.Entity.Get(Osi.GetHostCharacter()).ServerCharacter.Level

        ---@type Observable
        local entitiesProducer

        if next(specifiedEntities) then
            entitiesProducer = RX.Subject.fromTable(specifiedEntities, pairs, false)
        else
            local hostCharId = Osi.GetHostCharacter()

            entitiesProducer = RX.Subject.fromCoroutine(self:checkLocks(), RX.TimerScheduler, 500, 500)
                :skipWhile(function(isLocked) return isLocked end)
                :first()
                :flatMap(function(_)
                    return RX.Subject.fromTable(Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter"), pairs, false)
                end)
                :filter(function(entity)
                    return entity
                        and entity.Health.Hp > 0
                        and entity.ServerCharacter.Level == currentLevel
                end)
                :map(function(entityHandle) return entityHandle.Uuid.EntityUuid end)
        end

        -- "Instant" mode intentionally skips the DripScheduler-gated permit pool entirely (rather than
        -- passing it an unlimited permit count, since that scheduler's internals aren't something this
        -- change touches) so every eligible entity flows through the pipeline in one burst instead of
        -- being spread across ticks. The tickScheduler-based :delayIf waits below are unrelated to this -
        -- they're a short, necessary pause for the engine to settle removed components - and still apply.
        local instantMode = ConfigurationStructure.config.mutations.settings.profileExecution.executionMode == "Instant"
        local dripScheduler = not instantMode and RX.DripScheduler.create() or nil
        self.activeDripScheduler = dripScheduler
        local tickScheduler = RX.TickScheduler.create()

        local startTime = Ext.Timer.MonotonicTime()

        local eligible, ineligible = 0, 0

        local pipeline = entitiesProducer
        if dripScheduler then
            pipeline = pipeline:limitRate(dripScheduler)
        end

        pipeline
            :filter(function(entityId)
                -- For entities that cease to exist during processing, like refugees in Act 3
                if not Ext.Entity.Get(entityId) then
                    if dripScheduler then
                        dripScheduler:checkinPermit()
                    end
                    return false
                else
                    return true
                end
            end)
            :map(function(entityId)
                local entity = Ext.Entity.Get(entityId)
                if self:isEntityEligible(entity, currentLevel) then
                    eligible = eligible + 1
                    self.progress.total = eligible + ineligible
                    return self:compileEligibleMutations(entity)
                else
                    ineligible = ineligible + 1
                    self.progress.total = eligible + ineligible
                    return entity, { appliedMutators = {}, originalValues = {} }
                end
            end)
            :transformIf(
                function(entity) return entity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME] end,
                function(entity, entityVar)
                    return RX.AsyncSubject.of(entity)
                        :tap(function(entity)
                            MutatorInterface:undoMutator(entity, entity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME], entityVar, rerunTransient)
                        end)
                        :map(function(entity) return entity.Uuid.EntityUuid, entityVar end)
                        :delayIf(2,
                            tickScheduler,
                            function(entityId)
                                local e = Ext.Entity.Get(entityId)
                                return e and e.Vars.Absolutes_Laboratory_Undone_Components
                            end)
                        :map(function(entityId, entityVar) return Ext.Entity.Get(entityId), entityVar end)
                        -- Entity can vanish/die during the 2-tick wait above - drop just that one (returning its
                        -- permit) instead of throwing, which used to abort every remaining entity in the batch
                        :filter(function(entity)
                            if not entity then
                                if dripScheduler then
                                    dripScheduler:checkinPermit()
                                end
                                return false
                            end
                            return true
                        end)
                        :tap(function(entity)
                            entity.Vars.Absolutes_Laboratory_Undone_Components = nil
                        end)
                end)
            :map(function(entity, entityVar)
                local funcs = next(entityVar.appliedMutators)
                    and MutatorInterface:applyMutator(entity, entityVar)
                    or {}

                return entity.Uuid.EntityUuid, funcs
            end)
            :delayIf(2,
                tickScheduler,
                function(_, finalizeFuncs)
                    return next(finalizeFuncs)
                end
            )
            :map(function(entityId, funcs)
                ---@type EntityHandle?
                local entity = Ext.Entity.Get(entityId)

                if entity then
                    if next(funcs) then
                        for _, func in ipairs(funcs) do
                            func(entity)
                        end
                    end
                else
                    if dripScheduler then
                        dripScheduler:checkinPermit()
                    end
                end

                return entity
            end)
            :catch(function(error)
                Logger:BasicWarning("Received error during processing - skipping the offending entity: %s", error)
                return RX.AsyncSubject.empty()
            end)
            :subscribe(function(entity)
                    Logger:BasicTrace("Checking in permit for %s", EntityRecorder:GetEntityName(entity))
                    if dripScheduler then
                        dripScheduler:checkinPermit()
                    end
                    self.progress.processed = self.progress.processed + 1
                end,
                function(message)
                    Logger:BasicError(message)
                    self:completionFunc("Errored")
                end,
                function()
                    Logger:BasicInfo("======= Processed %d eligible and %d ineligible entities in %dms under Mutation Profile %s =======\n",
                        eligible,
                        ineligible,
                        Ext.Timer.MonotonicTime() - startTime,
                        self.activeProfileInfo.displayName)

                    self:completionFunc("Completed")
                end)
    else
        Logger:BasicInfo("No active profile found, undoing all mutations")
        self:UndoAllMutations(onFinishCallback)
    end
end

--- Undoes every currently-applied Mutation on the current level, independent of whether a Profile is
--- active. This is what automatically runs when ExecuteProfile finds no active Profile, and is also what
--- backs the manual "Undo Mutations Now" button in the Mutations MCM tab - it does NOT change/clear the
--- active Profile, so re-entering combat (or clicking Apply Mutations Now) will simply re-mutate anything
--- that still matches the active Profile's selectors.
---@param onFinishCallback fun()?
function MutationProfileExecutor:UndoAllMutations(onFinishCallback)
    if self.running or self.runningUndo then
        Logger:BasicDebug("Mutation Profile is currently executing - skipping Undo request from %s", debug.traceback())
        if onFinishCallback then onFinishCallback() end
        return
    end

    if ForceCleanUtility and ForceCleanUtility.running then
        Logger:BasicDebug("A Force Clean is currently running - skipping this Undo until it finishes")
        if onFinishCallback then onFinishCallback() end
        return
    end

    self.runningUndo = true
    self.currentAction = "Undo"
    self.activeProfileInfo.startTime = Ext.Timer.MonotonicTime()
    self.progress.processed = 0
    self.progress.total = 0

    PassiveDupeRemoverUtility:advanceState("Paused")
    ModEventsManager:MutationProfileExecuted("Started")
    self:broadcastStatus("Undo", "Starting")
    self:startStatusTicker("Undo")

    local instantMode = ConfigurationStructure.config.mutations.settings.profileExecution.executionMode == "Instant"
    local tickScheduler = RX.TickScheduler.create()
    local dripScheduler = not instantMode and RX.DripScheduler.create() or nil
    self.activeDripScheduler = dripScheduler

    Logger.mode = "timer"

    ---@type string
    local currentLevel = Ext.Entity.Get(Osi.GetHostCharacter()).ServerCharacter.Level

    local pipeline = RX.Subject.fromTable(Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter"), pairs, false)
        :filter(function(entity)
            return entity.Health.Hp > 0
                and entity.ServerCharacter.Level == currentLevel
        end)

    if dripScheduler then
        pipeline = pipeline:limitRate(dripScheduler)
    end

    pipeline
        :transformIf(
            function(entity)
                local hasMutations = entity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME] ~= nil
                if hasMutations then
                    self.progress.total = self.progress.total + 1
                end
                return hasMutations
            end,
            function(entity)
                return RX.AsyncSubject.of(entity)
                    :tap(function(entity)
                        MutatorInterface:undoMutator(entity, entity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME], nil, true)
                    end)
                    :map(function(entity) return entity.Uuid.EntityUuid end)
                    :delayIf(1,
                        tickScheduler,
                        function(entityId) return Ext.Entity.Get(entityId).Vars.Absolutes_Laboratory_Undone_Components end)
                    :map(function(entityId) return Ext.Entity.Get(entityId) end)
                    :tap(function(entity)
                        entity.Vars.Absolutes_Laboratory_Undone_Components = nil
                        self.progress.processed = self.progress.processed + 1
                    end)
            end)
        :catch(function(error)
            Logger:BasicWarning("Received error during processing - skipping the offending entity: %s", error)
            return RX.AsyncSubject.empty()
        end)
        :subscribe(function(...)
                if dripScheduler then
                    dripScheduler:checkinPermit()
                end
            end,
            function(message)
                Logger:BasicError(message)
                self:completionFunc("Errored")
                if onFinishCallback then
                    onFinishCallback()
                end
            end,
            function()
                Ext.Timer.WaitFor(10000, function()
                    Logger:BasicInfo("All mutations on living entities undone")
                    self:completionFunc("Completed")
                    if onFinishCallback then
                        onFinishCallback()
                    end
                end)
            end)
end

---@returns boolean?
function MutationProfileExecutor:determineActiveProfile()
    local activeProfile = self.config.profiles[Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile]
    if not activeProfile then
        Logger:BasicDebug("Couldn't find saved profile - stored in memory: %s", Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile or "None stored")
        Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = nil

        if not Ext.Vars.GetModVariables(ModuleUUID).HasDisabledProfiles then
            local defaultProfile = ConfigurationStructure.config.mutations.settings.defaultProfile
            if defaultProfile then
                if self.config.profiles[defaultProfile] then
                    Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = defaultProfile
                    activeProfile = self.config.profiles[defaultProfile]
                    Logger:BasicInfo("Default Profile %s activated", activeProfile.name)
                else
                    Logger:BasicWarning("Profile %s is set as the default, but can't be found", defaultProfile)
                end
            else
                Logger:BasicDebug("No Default Profile present, skipping")
            end
        else
            Logger:BasicDebug("The default profile is disabled, skipping")
        end
    end

    if activeProfile then
        self.activeProfileInfo.id = Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile
        self.activeProfileInfo.modId = activeProfile.modId
        self.activeProfileInfo.displayName = ("%s%s (%s)"):format(activeProfile.name,
            activeProfile.modId and (" from mod [%s]"):format(Ext.Mod.GetMod(activeProfile.modId).Info.Name) or "",
            self.activeProfileInfo.id:sub(-12)
        )
        self.activeProfileInfo.startTime = Ext.Timer.MonotonicTime()
        self.activeProfileInfo.profile = activeProfile

        return true
    else
        Logger:BasicInfo("No Mutation Profile is active, skipping")
    end
end

---@return thread
function MutationProfileExecutor:checkLocks()
    return coroutine.create(function(...)
        while (Ext.Entity.Get(Osi.GetHostCharacter()).ServerCharacter.Dialog == 1) do
            Logger:BasicDebug("Host character is in dialogue, waiting again")

            coroutine.yield(true)
        end

        coroutine.yield(false)
    end)
end

---@param entity EntityHandle
---@param currentLevel string
---@return boolean
function MutationProfileExecutor:isEntityEligible(entity, currentLevel)
    return entity.ServerCharacter
        and entity.Health.Hp > 0
        and entity.ServerCharacter.Level == currentLevel
        and (
            (Osi.IsPartyMember(entity.Uuid.EntityUuid, 0) == 0 or Osi.IsPartyFollower(entity.Uuid.EntityUuid) == 1)
            and entity.CampPresence == nil
        )
        and (Osi.CanJoinCombat(entity.Uuid.EntityUuid) == 1
            -- https://bg3.norbyte.dev/search?id=04a90774-cd81-4173-8918-1c0f7dc8ec2a - BLOCK_BOSS_DISTURBANCES - Bosses often aren't flagged as being able to fight, this seems like a good way to cover em
            or Osi.IsTagged(entity.Uuid.EntityUuid, "04a90774-cd81-4173-8918-1c0f7dc8ec2a") == 1
            -- For the rest, like needle blights, this seems to be a good catch-all for scripted ambush entities
            or Osi.HasPassive(entity.Uuid.EntityUuid, "Surprise_Immunity") == 1
            -- For the rest of the rest
            or Osi.HasActiveStatus(entity.Uuid.EntityUuid, "AMBUSHING") == 1
        )
        -- Entities that are unconcious become un-unconcious when their health changes at all, can't risk mutating them. Isn't just the health mutator, _anything_ that changes health at all qualifies
        and (Osi.HasActiveStatusWithGroup(entity.Uuid.EntityUuid, "SG_Unconscious") == 0 or entity.Health.Hp > 1)
        or false
end

---@param entity EntityHandle
---@return EntityHandle, MutatorEntityVar
function MutationProfileExecutor:compileEligibleMutations(entity)
    local isFollower = Osi.IsPartyFollower(entity.Uuid.EntityUuid)

    self.tempState.cachedSelectors = self.tempState.cachedSelectors or {}

    self.tempState.missingMutations = self.tempState.missingMutations or {}

    ---@type MutatorEntityVar
    local entityVar = {
        appliedMutators = {},
        appliedMutatorsPath = {},
        originalValues = {}
    }

    Ext.Utils.ProfileBegin("Lab Profiles - Selecting and Building Pool On " .. EntityRecorder:GetEntityName(entity))
    for i, mProfileRule in TableUtils:OrderedPairs(self.activeProfileInfo.profile.mutationRules) do
        -- Was `not folders[x] and folders[x].mutations[y]`, which indexes nil whenever the folder is missing (throwing
        -- and aborting the whole batch) and never fires for a missing mutation in an existing folder. Also only
        -- skipped the first time it was seen - every later entity fell through and indexed nil.
        local folder = MutationConfigurationProxy.folders[mProfileRule.mutationFolderId]
        if not (folder and folder.mutations[mProfileRule.mutationId]) then
            if not TableUtils:IndexOf(self.tempState.missingMutations, i) then
                Logger:BasicError("Couldn't find Mutation at index %d - folderId: %s | mutationId: %s", i, mProfileRule.mutationFolderId, mProfileRule.mutationId)
                self.tempState.missingMutations[#self.tempState.missingMutations + 1] = i
            end
            goto continue
        end

        local mutation = MutationConfigurationProxy.folders[mProfileRule.mutationFolderId].mutations[mProfileRule.mutationId]

        if not self.tempState.cachedSelectors[mProfileRule.mutationFolderId] then
            self.tempState.cachedSelectors[mProfileRule.mutationFolderId] = {}
        end
        if not self.tempState.cachedSelectors[mProfileRule.mutationFolderId][mProfileRule.mutationId] then
            self.tempState.cachedSelectors[mProfileRule.mutationFolderId][mProfileRule.mutationId] = SelectorInterface:createComposedPredicate(mutation.selectors)
        end

        entity.Vars[IS_PARTY_FOLLOWER_VAR_NAME] = nil

        if self.tempState.cachedSelectors[mProfileRule.mutationFolderId][mProfileRule.mutationId]:Test(entity, entityVar) then
            -- This is a dirty, dirty hack. Essentially users wanted to be able to run a different set of Mutations on specific NPCs when they join the party vs when they're an enemy boss
            -- This is set by the IsPartyFollowerSelector
            if isFollower == 0 or entity.Vars[IS_PARTY_FOLLOWER_VAR_NAME] then
                self:compileMutatorsForEntity(entityVar,
                    mutation.mutators,
                    mProfileRule,
                    i)
            end
        end
        ::continue::
    end

    local monsterLabRulesetRule = MonsterLabProfileExecutor:GetRulesetForEntity(entity)
    if monsterLabRulesetRule and next(monsterLabRulesetRule.mutators) then
        self:compileMutatorsForEntity(entityVar,
            monsterLabRulesetRule.mutators,
            monsterLabRulesetRule,
            9999)
    end

    Ext.Utils.ProfileEnd("Lab Profiles - Selecting and Building Pool On " .. EntityRecorder:GetEntityName(entity))

    return entity, entityVar
end

---@param entityVar MutatorEntityVar
---@param mutators Mutator[]
---@param profileRule MonsterLab_RulesetRule|MutationProfileRule
---@param profileRuleIndex any
function MutationProfileExecutor:compileMutatorsForEntity(entityVar, mutators, profileRule, profileRuleIndex)
    for _, mutator in pairs(mutators) do
        if entityVar.appliedMutators[mutator.targetProperty]
            and (profileRule.additive or profileRule.composable)
            and MutatorInterface.registeredMutators[mutator.targetProperty]:canBeAdditive(mutator, entityVar.appliedMutators[mutator.targetProperty])
        then
            if entityVar.appliedMutators[mutator.targetProperty][1] then
                table.insert(entityVar.appliedMutators[mutator.targetProperty], mutator)
            else
                entityVar.appliedMutators[mutator.targetProperty] = { entityVar.appliedMutators[mutator.targetProperty], mutator }
            end

            entityVar.appliedMutatorsPath[mutator.targetProperty][profileRuleIndex] = profileRule
        else
            entityVar.appliedMutators[mutator.targetProperty] = mutator
            entityVar.appliedMutatorsPath[mutator.targetProperty] = { [profileRuleIndex] = profileRule }
        end
    end
end

-- When Apply Trigger is set to "Combat Only" (Mutations tab / Execution Hub), this skips the full-level
-- sweep that would otherwise run on level load, leaving every eligible entity unmutated until the
-- EnteredCombat listener below picks them up individually as they actually join a fight - the whole
-- point being to avoid ever touching entities that never end up in combat at all.
--
-- "Off" goes further and skips this ENTIRELY, including the automatic Undo that ExecuteProfile itself
-- runs when no Profile is active (that's a deliberate safety net for "I just disabled my Profile and
-- haven't reloaded yet", but it still means a full-level scan runs on every level load and every combat
-- entry even when it never finds anything to undo). "Off" is for someone who has already confirmed
-- everything is clean (e.g. via Force Clean or the Undo button) and wants Lab to do absolutely nothing
-- automatically from then on - the manual Apply/Undo Mutations Now buttons still work regardless, since
-- those are an explicit action, not something running in the background.
local function maybeExecuteFullLevelProfile()
    local applyTrigger = ConfigurationStructure.config.mutations.settings.profileExecution.applyTrigger

    if applyTrigger == "Off" then
        Logger:BasicInfo("Apply Trigger is Off - skipping the level-load Mutation sweep entirely, including the automatic no-Profile Undo")
        return
    end

    if applyTrigger == "CombatOnly" then
        Logger:BasicInfo("Apply Trigger is Combat Only - skipping the level-load Mutation sweep, entities will be mutated as they enter combat instead")
        return
    end

    MutationProfileExecutor:ExecuteProfile()
end

Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function(levelName, isEditorMode)
    if levelName == "SYS_CC_I" then return end

    Logger:BasicDebug("Current level is %s", levelName)

    -- Once per level instead of after every pass - see completionFunc
    ListConfigurationManager.progressionIndex()

    local completionFunc = MonsterLabProfileExecutor:ExecuteProfile()

    if not completionFunc or completionFunc() then
        maybeExecuteFullLevelProfile()
    else
        local function checkMLCompletion()
            if not completionFunc() then
                Ext.Timer.WaitFor(34, function()
                    checkMLCompletion()
                end)
                return
            else
                maybeExecuteFullLevelProfile()
            end
        end

        checkMLCompletion()
    end
end)

Ext.RegisterConsoleCommand("Lab_TraceEntities", function(cmd, ...)
    ChangePrinter.logger:ClearLogFile()
    Printer:Start(100, ...)
    MutationProfileExecutor:ExecuteProfile()
end)


Ext.RegisterConsoleCommand("Lab_TestTransient", function(cmd, ...)
    MutationProfileExecutor:ExecuteProfile(true)
end)

Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", function(character)
    ---@type EntityHandle
    local charEntity = Ext.Entity.Get(character)
    if charEntity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME] and Osi.IsSummon(character) == 0 then
        Logger:BasicInfo("%s_%s joined the party, undoing the Mutations that were applied.", EntityRecorder:GetEntityName(charEntity), charEntity.Uuid.EntityUuid)
        MutatorInterface:undoMutator(charEntity, charEntity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME], nil, true)
    end
end)

-- Catches any entity that enters combat without having been mutated yet - normally just stragglers that
-- the level-load sweep missed (spawned late, etc.), but under Apply Trigger "Combat Only" this is the ONLY
-- place Mutations ever get applied from, by design - see maybeExecuteFullLevelProfile above. Debounced
-- 300ms (per Combat instance, not globally) so every entity that joins the SAME fight in that window
-- gets batched into one targeted Apply (and one status window pop-up) instead of one per entity.
--
-- Gated on isEntityEligible (plus an explicit IsSummon check) so a party member or a summoned creature
-- joining combat doesn't queue an Apply of its own - they were always going to be filtered out as
-- ineligible once ExecuteProfile actually ran anyway, but without this check they still queued one, which
-- under "Combat Only" meant the status window (and a real, if wasted, Apply pass) fired every single time
-- an ally or summon entered a fight - not just when an actual mutation candidate did.
--
-- ALSO gated on the Combat actually involving the player: BG3 can have entirely separate combats going
-- on in the world that have nothing to do with the party (two enemy factions fighting each other, a
-- scripted fight elsewhere on the level), and EnteredCombat fires for those too. playerInvolvedCombats
-- tracks, per Combat guid, whether a party member (or the host) has entered that specific Combat; the
-- decision of whether to actually Apply is deferred to the debounce timer below rather than made
-- immediately, since an enemy's own EnteredCombat can fire slightly before or after the party's for the
-- same fight - by the time the 300ms timer for that Combat guid fires, the party's own entry (if any)
-- should have been recorded too.
---@type {[Guid]: boolean}
local playerInvolvedCombats = {}
---@type {[Guid]: Guid[]}
local entitiesEnteringCombatByGuid = {}
---@type {[Guid]: integer}
local combatTimersByGuid = {}

-- Combat pausing while a combat-triggered Apply runs.
--
-- Lab's mutators don't just add statuses/passives the way e.g. Absolute Wrath does - Classes And Subclasses
-- rewrites the Classes component, Character Level rewrites AvailableLevel/EocLevel, Spell List queues spellbook
-- removals/additions through the SpellSystem, Undo forces a full stats reload, and several of these then
-- Replicate to the client over the following ticks. At level load that's fine, nobody is acting. Under
-- Combat Only it all happens while the fight is already starting: initiative is rolled, the first enemy's AI
-- starts scoring its spellbook, the client builds your hotbar/portraits - against entities whose components
-- are mid-rebuild. Lab's own status window warns "do not perform any actions while this is running - you may
-- softlock your game", and Combat Only guarantees it runs exactly when the game itself is performing actions.
--
-- So: pause the combat (same Osiris call the game's own scripts use for in-combat cinematics) for the duration
-- of the Apply, plus a short settle window for Replicate/ReloadStats, then resume. A hard failsafe guarantees a
-- resume even if the Apply never reports back, and combats paused by something else (dialogue, a cinematic)
-- are left strictly alone - neither paused nor resumed by Lab.
local COMBAT_RESUME_SETTLE_MS = 300
local COMBAT_PAUSE_FAILSAFE_MS = 20000

-- Number of outstanding Applies holding each combat paused - reinforcements joining the same fight while its
-- first batch is still being mutated get queued behind it, and the fight must stay paused until BOTH are done
---@type {[Guid]: integer}
local combatPauseHolds = {}
---@type {[Guid]: boolean}
local combatsPausedExternally = {}
---@type {[Guid]: integer}
local combatPauseFailsafeTimers = {}

local function shouldPauseCombat()
    -- nil (setting not yet saved by the client) counts as enabled
    return ConfigurationStructure.config.mutations.settings.profileExecution.pauseCombatWhileMutating ~= false
end

---@param combatGuid Guid
local function forceResumeCombat(combatGuid)
    if combatPauseFailsafeTimers[combatGuid] then
        Ext.Timer.Cancel(combatPauseFailsafeTimers[combatGuid])
        combatPauseFailsafeTimers[combatGuid] = nil
    end

    if combatPauseHolds[combatGuid] then
        combatPauseHolds[combatGuid] = nil
        if not combatsPausedExternally[combatGuid] and Osi.CombatIsActive(combatGuid) == 1 then
            Logger:BasicDebug("Resuming combat %s now that its Mutations have been applied", combatGuid)
            Osi.ResumeCombat(combatGuid)
        end
    end
end

---@param combatGuid Guid
---@return fun() onFinished
local function pauseCombatForApply(combatGuid)
    if not combatPauseHolds[combatGuid] then
        if not shouldPauseCombat()
            or combatsPausedExternally[combatGuid]
            or Osi.CombatIsActive(combatGuid) ~= 1
        then
            return function() end
        end

        Logger:BasicDebug("Pausing combat %s while its entities are mutated", combatGuid)
        combatPauseHolds[combatGuid] = 0
        Osi.PauseCombat(combatGuid)

        combatPauseFailsafeTimers[combatGuid] = Ext.Timer.WaitFor(COMBAT_PAUSE_FAILSAFE_MS, function()
            combatPauseFailsafeTimers[combatGuid] = nil
            if combatPauseHolds[combatGuid] then
                Logger:BasicWarning("Mutations for combat %s didn't report finishing within %dms - resuming the combat anyway", combatGuid, COMBAT_PAUSE_FAILSAFE_MS)
                forceResumeCombat(combatGuid)
            end
        end)
    end

    combatPauseHolds[combatGuid] = combatPauseHolds[combatGuid] + 1

    local finished = false
    return function()
        if finished then return end
        finished = true
        -- Give Replicate/ReloadStats/SpellSystem queues a moment to flush before turns start running again
        Ext.Timer.WaitFor(COMBAT_RESUME_SETTLE_MS, function()
            -- nil if the failsafe or CombatEnded already released it
            if combatPauseHolds[combatGuid] then
                combatPauseHolds[combatGuid] = combatPauseHolds[combatGuid] - 1
                if combatPauseHolds[combatGuid] <= 0 then
                    forceResumeCombat(combatGuid)
                end
            end
        end)
    end
end

Ext.Osiris.RegisterListener("CombatPaused", 1, "after", function(combatGuid)
    if not combatPauseHolds[combatGuid] then
        combatsPausedExternally[combatGuid] = true
    end
end)

Ext.Osiris.RegisterListener("CombatResumed", 1, "after", function(combatGuid)
    combatsPausedExternally[combatGuid] = nil
end)

Ext.Osiris.RegisterListener("EnteredCombat", 2, "before", function(entityId, combatGuid)
    if entityId == Osi.GetHostCharacter() or Osi.IsPartyMember(entityId, 0) == 1 then
        playerInvolvedCombats[combatGuid] = true
    end

    ---@type EntityHandle
    local entity = Ext.Entity.Get(entityId)
    ---@type string
    local currentLevel = Ext.Entity.Get(Osi.GetHostCharacter()).ServerCharacter.Level

    if entity
        and ConfigurationStructure.config.mutations.settings.profileExecution.applyTrigger ~= "Off"
        and not entity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME]
        and Osi.IsSummon(entityId) == 0
        and MutationProfileExecutor:isEntityEligible(entity, currentLevel)
    then
        entitiesEnteringCombatByGuid[combatGuid] = entitiesEnteringCombatByGuid[combatGuid] or {}
        table.insert(entitiesEnteringCombatByGuid[combatGuid], entityId)

        if combatTimersByGuid[combatGuid] then
            Ext.Timer.Cancel(combatTimersByGuid[combatGuid])
        end
        combatTimersByGuid[combatGuid] = Ext.Timer.WaitFor(300, function()
            local entities = entitiesEnteringCombatByGuid[combatGuid]
            entitiesEnteringCombatByGuid[combatGuid] = nil
            combatTimersByGuid[combatGuid] = nil

            if not playerInvolvedCombats[combatGuid] then
                Logger:BasicDebug("Combat %s doesn't involve the player - skipping the Mutation Apply for entities: %s", combatGuid, entities)
                return
            end

            Logger:BasicInfo("Entities have entered a Combat the player is part of (%s) and hasn't been mutated - executing profile! Entities: %s", combatGuid, entities)
            MutationProfileExecutor:ExecuteProfile(false, pauseCombatForApply(combatGuid), table.unpack(entities))
        end)
    end
end)

-- Best-effort cleanup so playerInvolvedCombats doesn't just grow for the rest of the session - if this
-- particular event ever doesn't fire for some reason, the only cost is a handful of stale Guid keys
-- sitting unused in memory, since a Combat guid is never reused, so it can't cause a wrong match later.
Ext.Osiris.RegisterListener("CombatEnded", 1, "after", function(combatGuid)
    playerInvolvedCombats[combatGuid] = nil
    entitiesEnteringCombatByGuid[combatGuid] = nil
    if combatTimersByGuid[combatGuid] then
        Ext.Timer.Cancel(combatTimersByGuid[combatGuid])
        combatTimersByGuid[combatGuid] = nil
    end
    if combatPauseFailsafeTimers[combatGuid] then
        Ext.Timer.Cancel(combatPauseFailsafeTimers[combatGuid])
        combatPauseFailsafeTimers[combatGuid] = nil
    end
    combatPauseHolds[combatGuid] = nil
    combatsPausedExternally[combatGuid] = nil
end)

Ext.RegisterConsoleCommand("Lab_FullMutationReset", function(cmd, ...)
    local tickScheduler = RX.TickScheduler.create()

    Logger.mode = "timer"

    ---@type string
    local currentLevel = Ext.Entity.Get(Osi.GetHostCharacter()).ServerCharacter.Level

    RX.Subject.fromTable(Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter"), pairs, false)
        :filter(function(entity)
            return entity.Health.Hp > 0
                and entity.ServerCharacter.Level == currentLevel
                and MutationProfileExecutor:isEntityEligible(entity, currentLevel)
        end)
        :transformIf(
            function(entity) return entity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME] end,
            function(entity)
                return RX.AsyncSubject.of(entity)
                    :tap(function(entity)
                        MutatorInterface:undoMutator(entity, entity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME], nil, true)
                    end)
                    :map(function(entity) return entity.Uuid.EntityUuid end)
                    :delayIf(1,
                        tickScheduler,
                        function(entityId) return Ext.Entity.Get(entityId).Vars.Absolutes_Laboratory_Undone_Components end)
                    :map(function(entityId) return Ext.Entity.Get(entityId) end)
                    :tap(function(entity)
                        entity.Vars.Absolutes_Laboratory_Undone_Components = nil
                    end)
            end)
        :transformIf(function(entity) return Osi.IsPartyMember(entity.Uuid.EntityUuid, 0) == 0 and entity.CampPresence == nil end,
            function(entity)
                return RX.AsyncSubject.of(entity)
                    :tap(function(entity)
                        entity:RemoveComponent("Classes")
                        entity:CreateComponent("Classes")

                        Ext.Timer.WaitFor(10000, function()
                            Ext.System.ServerStats.ReloadStats[entity] = true
                        end)
                    end)
            end)
        :subscribe(function(...)
            end,
            function(message)
                Logger:BasicError(message)
                Logger.mode = "buffer"
            end,
            function()
                Ext.Timer.WaitFor(10000, function()
                    Logger:BasicInfo("Finished Reset")
                end)
                Logger.mode = "buffer"
            end)
end)


-- Backs the "Apply Mutations Now" button in the Mutations MCM tab - lets the active Profile be (re)applied
-- to the current level without saving/reloading. If no Profile is active this just undoes everything, same
-- as ExecuteProfile always has when called with nothing active.
Channels.ManualApplyMutations:SetHandler(function(data, user)
    Logger:BasicInfo("Manual 'Apply Mutations Now' requested from MCM")
    MutationProfileExecutor:ExecuteProfile()
end)

-- Backs the "Undo Mutations Now" button in the Mutations MCM tab.
Channels.ManualUndoMutations:SetHandler(function(data, user)
    Logger:BasicInfo("Manual 'Undo Mutations Now' requested from MCM")
    MutationProfileExecutor:UndoAllMutations()
end)

Ext.RegisterConsoleCommand("Lab_CheckShouldBeMutated", function()
    ---@type string
    local currentLevel = Ext.Entity.Get(Osi.GetHostCharacter()).ServerCharacter.Level
    for _, entity in pairs(Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter")) do
        if not entity.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME]
            and MutationProfileExecutor:isEntityEligible(entity, currentLevel)
            and Osi.GetDistanceTo(Osi.GetHostCharacter(), entity.Uuid.EntityUuid)
        then
            Logger:BasicWarning("Entity %s (%s) was not mutated, though they should have been!", EntityRecorder:GetEntityName(entity), entity.Uuid.EntityUuid)
        end
    end
end)
