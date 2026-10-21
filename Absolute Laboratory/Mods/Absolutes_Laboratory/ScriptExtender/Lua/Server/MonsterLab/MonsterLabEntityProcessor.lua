---@class MonsterLab_EntityProcessor : MonsterLab_BaseProcessor
MonsterLab_EntityProcessor = MonsterLab_BaseProcessor:new()

MonsterLab_EntityProcessor.completed = false

---@type MonsterLabEntity?
MonsterLab_EntityProcessor.mlEntity = nil

---@type MonsterLabEntity_Spawned?
MonsterLab_EntityProcessor.spawnedMLEntity = nil

---@type CharacterTemplate
MonsterLab_EntityProcessor.cachedTemplate = nil

MonsterLab_EntityProcessor.freshSpawn = false

---@type EntityHandle?
MonsterLab_EntityProcessor.entityHandle = nil

---@type MonsterLab_EncounterProcessor
MonsterLab_EntityProcessor.encounter = nil

---@type MonsterLab_RulesetRule?
MonsterLab_EntityProcessor.activeRuleset = nil

MonsterLab_EntityProcessor.requiresSaveAndLoadForTemplateChanges = false

MonsterLab_EntityProcessor.designerModeActive = false

---@param encounter MonsterLab_EncounterProcessor
---@param mlEntityId Guid?
---@param mlEntity MonsterLabEntity?
---@param spawnedMLEntity MonsterLabEntity_Spawned?
---@return MonsterLab_EntityProcessor?
function MonsterLab_EntityProcessor:new(encounter, mlEntityId, mlEntity, spawnedMLEntity, designerModeActive)
    if not mlEntity and not spawnedMLEntity then
        return
    end

    ---@type MonsterLab_EntityProcessor
    local instance = {}

    setmetatable(instance, self)
    self.__index = self

    instance.encounter = encounter
    instance.queuedLogs = {}
    instance.mlEntity = mlEntity or spawnedMLEntity
    instance.mlEntity.mlEntityId = mlEntityId
    instance.designerModeActive = designerModeActive
    instance.spawnedMLEntity = spawnedMLEntity
    instance.entityHandle = spawnedMLEntity and spawnedMLEntity.realEntityId and Ext.Entity.Get(spawnedMLEntity.realEntityId)


    instance:queueLog(Logger.BasicDebug,
        "### Start Processing Entity %s - (%s) (%s) ###",
        instance.mlEntity.displayName, instance.mlEntity.title ~= "" and instance.mlEntity.title or "(No Title)", instance.mlEntity.mlEntityId
    )

    instance:queueLog(Logger.BasicTrace, "Details: \n%s", instance.mlEntity)

    if mlEntity and mlEntity.template and not Ext.ServerTemplate.GetTemplate(mlEntity.template) then
        instance:queueLog(Logger.BasicWarning,
            "Template [%s] for Entity %s - (%s) (%s) does not exist - performing cleanup and skipping processing",
            mlEntity.template,
            instance.mlEntity.displayName,
            instance.mlEntity.title ~= "" and instance.mlEntity.title or "(No Title)",
            instance.mlEntity.mlEntityId
        )

        instance:clearDatabaseEntries()

        if instance.encounter and instance.encounter.spawnedEncounter then
            instance.encounter.spawnedEncounter.entities[instance.mlEntity.mlEntityId] = nil
        end

        return instance:complete()
    end

    if spawnedMLEntity and spawnedMLEntity.realEntityId and not instance.entityHandle then
        instance:queueLog(Logger.BasicDebug, "A realEntityId exists for this entity, but couldn't get their entity handle - wiping the var")

        instance:clearDatabaseEntries()
        instance.encounter.spawnedEncounter.entities[instance.mlEntity.mlEntityId] = nil
        instance.spawnedMLEntity = nil
    end

    if mlEntityId then
        instance.activeRuleset = MonsterLabProfileExecutor:GetRulesetForEntityVar({
            encounterId = encounter.encounter.encounterId,
            folderId = encounter.request.folderId,
            mlEntityId = mlEntityId,
            profileId = encounter.request.profileId,
            cachedDatabaseEntries = {}
        })
    end

    return instance
end

function MonsterLab_EntityProcessor:complete()
    if not self.completed then
        if self.entityHandle and not self.designerModeActive then
            if self.requiresSaveAndLoadForTemplateChanges then
                Ext.System.ServerCapabilities.TemplateChanged[self.entityHandle] = true
            end

            Ext.System.ServerStats.ReloadStats[self.entityHandle] = true
            Ext.System.ServerStats.CalculationRequests[self.entityHandle] = { "AttackRollBonusOnWeapon", "Abilities", "AC", "Skills", "MaxHP", "ProficiencyBonus", "Initiative" }
        end

        self:queueLog(Logger.BasicDebug,
            "### End Processing Entity %s - (%s) (%s) ###\n",
            self.mlEntity.displayName,
            self.mlEntity.title ~= "" and self.mlEntity.title or "(No Title)",
            self.mlEntity.mlEntityId
        )

        if self.encounter then
            for _, queueLog in ipairs(self.queuedLogs) do
                self.encounter:queueLog(queueLog.logFun, table.unpack(queueLog.params))
            end
        else
            self:flushLogs()
        end

        self.completed = true
    end
end

---@param reason string
---@param force boolean?
---@return boolean
function MonsterLab_EntityProcessor:delete(reason, force)
    if self.entityHandle then
        if force
            -- If we're executing a profile and the entity is alive,
            or (not self.designerModeActive and Osi.IsDead(self.entityHandle.Uuid.EntityUuid) == 0)
            -- or we're exiting designer mode and the entity was spawned as part of the designer functionality
            or not self.entityHandle.Vars[ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME].profileId
        then
            self:queueLog(Logger.BasicDebug, "Deleting because: %s", reason)

            self:clearDatabaseEntries()
            Osi.RequestDeleteTemporary(self.entityHandle.Uuid.EntityUuid)
            self.entityHandle = nil

            if (self.spawnedMLEntity and not self.spawnedMLEntity.realEntityId)
                and self.encounter
                and self.encounter.spawnedEncounter
                and self.encounter.spawnedEncounter.entities[self.mlEntity.mlEntityId]
            then
                self.encounter.spawnedEncounter.entities[self.mlEntity.mlEntityId] = nil
                self.spawnedMLEntity = nil
            end
        elseif Osi.IsDead(self.entityHandle.Uuid.EntityUuid) == 0 then
            self:queueLog(Logger.BasicDebug, "Resetting CanFight/CanJoinCombat back to 1 instead of deleting for reason: %s", reason)
            Osi.SetCanFight(self.entityHandle.Uuid.EntityUuid, 1)
            Osi.SetCanJoinCombat(self.entityHandle.Uuid.EntityUuid, 1)

            return false
        end
    else
        self:queueLog(Logger.BasicDebug, "Does not exist, skipping delete logic")
    end
    return true
end

function MonsterLab_EntityProcessor:clearDatabaseEntries()
    if self.spawnedMLEntity then
        local presentInDatabases = ClientHelpers:getDBEntries_ForEntity(self.spawnedMLEntity.realEntityId)

        for databaseName, paramList in pairs(presentInDatabases) do
            self:queueLog(Logger.BasicDebug, "Deleting all %d entries from database %s", #paramList, databaseName, self.spawnedMLEntity.displayName)
            for _, params in ipairs(paramList) do
                Osi[databaseName]:Delete(Helpers:unpackParamTable(params, #params))
            end
        end
    end
end

function MonsterLab_EntityProcessor:spawn()
    if not self.designerModeActive then
        if not self.activeRuleset or not self.activeRuleset.shouldSpawn then
            self:queueLog(Logger.BasicDebug, "Not eligible to spawn according to the active ruleset (or no ruleset could be applied)")
            return self:complete()
        elseif self.entityHandle and Osi.IsDead(self.entityHandle.Uuid.EntityUuid) == 1 then
            self:queueLog(Logger.BasicDebug, "Entity is currently dead and designer mode is not active - skipping updates to avoid respawning")
            return self:complete()
        end
    end

    if self.entityHandle
        and self.spawnedMLEntity.nonCachedTemplateId
        and self.spawnedMLEntity.nonCachedTemplateId ~= self.mlEntity.template
    then
        self:delete(("Desired template %s does not match the current template of %s, deleting entity to respawn with the correct one"):format(
            self.spawnedMLEntity.nonCachedTemplateId,
            self.mlEntity.template
        ), true)

        self.spawnedMLEntity.realEntityId = nil
    end

    if self.entityHandle then
        if not tostring(self.entityHandle.ServerCharacter.Template.TemplateStorageType):find("CacheTemplate") then
            self:queueLog(Logger.BasicDebug, "Has already been spawned in but template needs to be updated to Cached variant")

            self.spawnedMLEntity.nonCachedTemplateId = self.mlEntity.template
            self.cachedTemplate = self.entityHandle.ServerCharacter:CreateCacheTemplate()
        else
            self.cachedTemplate = self.entityHandle.ServerCharacter.Template
        end

        if not self.designerModeActive then
            self.entityHandle.Vars[ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME].profileId = self.encounter.request.profileId
        end

        if self.entityHandle.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME] then
            self:queueLog(Logger.BasicDebug, "Mutations are present, undoing them for a clean modification")

            MutatorInterface:undoMutator(self.entityHandle,
                self.entityHandle.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME],
                nil,
                true)

            Ext.Timer.WaitFor(33, function()
                self:processEntity()
            end)

            return
        end

        return self:processEntity()
    else
        if #self.mlEntity.coordinates ~= 3 or TableUtils:CompareLists(self.mlEntity.coordinates, { 0, 0, 0 }) then
            self:queueLog(Logger.BasicDebug, "Coordinates (%s) are invalid - can't spawn, skipping.", self.mlEntity.coordinates)

            return self:complete()
        end

        self:queueLog(Logger.BasicDebug, "Entity has not been spawned yet, spawning in instance of template %s", self.mlEntity.template)
        self.freshSpawn = true

        local template = Ext.ServerTemplate.GetRootTemplate(self.mlEntity.template)

        local entityId = Osi.CreateAt(template.TemplateStorageType == "RootTemplate" and self.mlEntity.template or template.TemplateName,
            self.mlEntity.coordinates[1],
            self.mlEntity.coordinates[2],
            self.mlEntity.coordinates[3],
            1,
            1,
            "")

        if not entityId then
            self:queueLog(Logger.BasicWarning, "Creating the entity with template %s at coords %s did not succeed - bypassing", self.mlEntity.template, self.mlEntity.coordinates)

            return self:complete()
        end

        self.entityHandle = Ext.Entity.Get(entityId)

        self.cachedTemplate = self.entityHandle.ServerCharacter:CreateCacheTemplate()

        if not self.spawnedMLEntity then
            self.spawnedMLEntity = TableUtils:DeeplyCopyTable(self.mlEntity)
            self.encounter.spawnedEncounter.entities[self.mlEntity.mlEntityId] = self.spawnedMLEntity
        end

        self.spawnedMLEntity.realEntityId = entityId
        self.spawnedMLEntity.nonCachedTemplateId = self.mlEntity.template

        -- Waiting just over 2 frames for the freshly spawned entity to finish updating various components
        local startTime = Ext.Timer.MonotonicTime()
        self:queueLog(Logger.BasicDebug, "Waiting a little over 2 frames for spawned entity to finish updating")

        Ext.Timer.WaitFor(70, function()
            self:queueLog(Logger.BasicDebug,
                "Fairly confident that the entity is fully setup after %dms. Final ID: %s",
                Ext.Timer.MonotonicTime() - startTime,
                self.spawnedMLEntity.realEntityId)

            self.entityHandle = Ext.Entity.Get(self.spawnedMLEntity.realEntityId)

            if not self.entityHandle then
                self:queueLog(Logger.BasicWarning, "No EntityHandle was returned for ML entity %s (%s) - not sure what happened", self.mlEntity.displayName,
                    self.mlEntity.mlEntityId)

                return self:complete()
            end

            self.entityHandle.Vars[ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME] = self.entityHandle.Vars[ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME] or {
                profileId = self.encounter.request.profileId,
                folderId = self.encounter.request.folderId,
                encounterId = self.encounter.request.encounterId,
                mlEntityId = self.mlEntity.mlEntityId,
                cachedDatabaseEntries = {}
            } --[[@as MonsterLab_EntityVariable]]

            return self:processEntity()
        end)
    end
end

function MonsterLab_EntityProcessor:processEntity()
    self:updateCachedTemplate()

    self:updateStatsEntry()

    self:updateOsirisProperties()

    self:updateDatabaseEntries()

    return self:complete()
end

function MonsterLab_EntityProcessor:updateCachedTemplate()
    if self.designerModeActive then
        self:queueLog(Logger.BasicDebug, "Skipping updating the cached template as designer mode is active")
        return
    end

    local baseTemplate = Ext.Template.GetTemplate(self.mlEntity.template) --[[@as CharacterTemplate]]

    if baseTemplate.TemplateStorageType ~= "RootTemplate" and self.freshSpawn then
        self:queueLog(Logger.BasicDebug,
            "Entity template %s is a %s, so it was spawned using the root template %s. Copying all fields from the global template over to the cached template",
            self.mlEntity.template,
            tostring(baseTemplate.TemplateStorageType),
            baseTemplate.TemplateName)

        local charTemplate = self.cachedTemplate

        for key, value in pairs(baseTemplate) do
            if key == "Id" or key == "Name" or key == "ParentTemplateId"
                or key == "TemplateName" or key == "LevelName" or key == "TemplateStorageType"
                or key == "TemplateType"
                or self.mlEntity[key]
                or (self.activeRuleset and self.activeRuleset.template and self.activeRuleset.template[key])
            then
                goto continue
            end

            local success, error = pcall(function(...)
                self:queueLog(Logger.BasicDebug, "Copying field [%s] with value [%s]", key, value)
                if type(value) == "table" then
                    charTemplate[key] = TableUtils:DeeplyCopyTable(value)
                elseif type(value) == "userdata" then
                    local objectType = Ext.Types.GetObjectType(value)
                    local typeInfo = Ext.Types.GetTypeInfo(objectType)
                    if typeInfo and typeInfo.IsBitfield then
                        charTemplate[key] = value.__Labels
                    elseif Ext.Enums[objectType] then
                        charTemplate[key] = tostring(value)
                    else
                        Ext.Types.Unserialize(charTemplate[key], Ext.Types.Serialize(value))
                    end
                else
                    charTemplate[key] = value
                end
            end)

            if not success then
                self:queueLog(Logger.BasicWarning, "Couldn't copy global template field [%s] with value [%s] over to the cached template for entity %s due to error: [%s]", key,
                    value, self.mlEntity.displayName, error)
            end

            ::continue::
        end

        self.requiresSaveAndLoadForTemplateChanges = true
    end


    ---@param templateConfig table
    ---@param configKey string
    ---@param baseComponentSupplier fun(tmpl:CharacterTemplate):table
    ---@param componentKey string
    ---@param finalizer fun()?
    local function processChange(templateConfig, configKey, baseComponentSupplier, componentKey, finalizer)
        local cachedComponent = baseComponentSupplier(self.cachedTemplate)
        local baseComponent = baseComponentSupplier(baseTemplate)

        if templateConfig[configKey] ~= nil and cachedComponent[componentKey] ~= templateConfig[configKey] then
            self:queueLog(Logger.BasicDebug,
                "Current %s value of [%s] does not match desired [%s] - updating",
                configKey,
                cachedComponent[componentKey],
                templateConfig[configKey])

            cachedComponent[componentKey] = templateConfig[configKey]

            if finalizer then
                finalizer()
            end

            self.requiresSaveAndLoadForTemplateChanges = true
        elseif templateConfig[configKey] == nil and baseComponent[componentKey] ~= cachedComponent[componentKey] then
            self:queueLog(Logger.BasicDebug, "No %s was provided and the current value of [%s] does not match the default [%s] - updating",
                configKey,
                cachedComponent[componentKey],
                baseComponent[componentKey])

            cachedComponent[componentKey] = baseComponent[componentKey]

            if finalizer then
                finalizer()
            end

            self.requiresSaveAndLoadForTemplateChanges = true
        end
    end

    processChange(self.mlEntity,
        "characterVisualResourceID",
        function(tmpl)
            return tmpl
        end,
        "CharacterVisualResourceID",
        function()
            Ext.System.ServerVisual.UpdateVisuals[self.entityHandle] = true
        end
    )

    processChange(self.mlEntity,
        "icon",
        function(tmpl)
            return tmpl
        end,
        "Icon"
    )

    processChange(
        self.mlEntity,
        "anubisConfigName",
        function(tmpl)
            return tmpl
        end,
        "AnubisConfigName"
    )

    if not self.activeRuleset or not self.activeRuleset.template then
        return
    end

    local templateConfig = self.activeRuleset.template

    processChange(templateConfig,
        "archetype",
        function(tmpl)
            return tmpl.CombatComponent
        end,
        "Archetype",
        function()
            self.entityHandle.ServerAiArchetype.ActiveArchetype = templateConfig.archetype
            self.entityHandle.ServerAiArchetype.BaseArchetype = templateConfig.archetype
        end
    )

    processChange(templateConfig, "equipment",
        function(tmpl)
            return tmpl
        end,
        "Equipment",
        function()
            Ext.System.ServerInventoryEquipment.EquipmentSet[self.entityHandle] = {
                Equipment = { templateConfig.equipment },
                RemoveOldEquipmentSets = true
            } --[[@as EsvInventoryEquipmentSetRequest]]
        end
    )

    processChange(templateConfig,
        "spellSet",
        function(tmpl)
            return tmpl
        end,
        "SpellSet"
    )

    processChange(templateConfig,
        "level",
        function(tmpl)
            return tmpl
        end,
        "LevelOverride",
        function()
            self.entityHandle.AvailableLevel.Level = self.cachedTemplate.LevelOverride
            self.entityHandle.EocLevel.Level = self.cachedTemplate.LevelOverride

            self.entityHandle:Replicate("AvailableLevel")
            self.entityHandle:Replicate("EocLevel")
        end
    )

    ---@param configKey string
    ---@param baseComponentSupplier fun(tmpl:CharacterTemplate):table
    ---@param componentKey string
    local function processListChange(configKey, baseComponentSupplier, componentKey)
        local cachedComponent = baseComponentSupplier(self.cachedTemplate)
        local baseComponent = baseComponentSupplier(baseTemplate)

        local hasListElements = next(Ext.Types.Serialize(cachedComponent[componentKey])) ~= nil
        if templateConfig[configKey].clearBase then
            if hasListElements then
                self:queueLog(Logger.BasicDebug, "Clearing %s values from the template per config", configKey)

                Ext.Types.Unserialize(cachedComponent[componentKey], {})
                self.requiresSaveAndLoadForTemplateChanges = true
            end
        elseif not hasListElements then
            local serializedBaseList = Ext.Types.Serialize(baseComponent[componentKey])

            if next(serializedBaseList) then
                self:queueLog(Logger.BasicDebug, "%s are not set to be cleared, but cachedTemplate has an empty list where the baseTemplate doesn't - syncing", configKey)
                Ext.Types.Unserialize(cachedComponent[componentKey], serializedBaseList)

                self.requiresSaveAndLoadForTemplateChanges = true
            end
        end
    end

    processListChange("skillList",
        function(tmpl)
            return tmpl
        end,
        "SkillList")

    processListChange("statuses",
        function(tmpl)
            return tmpl
        end,
        "StatusList")

    processListChange("treasures",
        function(tmpl)
            return tmpl
        end,
        "Treasures")

    processListChange("tradeTreasures",
        function(tmpl)
            return tmpl
        end,
        "TradeTreasures")
end

function MonsterLab_EntityProcessor:updateStatsEntry()
    ---@type MonsterLab_EntityVariable
    local var = self.entityHandle.Vars[ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME]

    ---@type CharacterTemplate
    local baseTemplate = Ext.ServerTemplate.GetRootTemplate(self.mlEntity.template)

    local trueStatName = ("LAB_%s_%s"):format(self.mlEntity.stat or baseTemplate.Stats, self.mlEntity.mlEntityId:sub(-12))

    ---@type Character
    local stat = Ext.Stats.Get(trueStatName)
    if not stat then
        self:queueLog(Logger.BasicDebug, "Creating Custom Stat [%s] for edits", trueStatName)
        stat = Ext.Stats.Create(trueStatName,
            "Character",
            (self.mlEntity.stat or baseTemplate.Stats)) --[[@as Character]]
    end

    if self.cachedTemplate.Stats ~= trueStatName then
        var.originalStatName = self.mlEntity.stat or baseTemplate.Stats

        self:queueLog(Logger.BasicDebug, "Current template stat [%s] does not match the configured one, [%s]. Updating", self.cachedTemplate.Stats, trueStatName)
        self.cachedTemplate.Stats = trueStatName
    end

    if self.entityHandle.Data.StatsId ~= trueStatName then
        self:queueLog(Logger.BasicDebug,
            "Current entity stat [%s] does not match the configured one, [%s]. Updating",
            self.entityHandle.Data.StatsId,
            trueStatName)

        self.entityHandle.Data.StatsId = trueStatName
        self.entityHandle:Replicate("Data")
    end

    if self.activeRuleset.stats then
        ---@type Character
        local originalStat = Ext.Stats.Get(var.originalStatName)

        local statConfig = self.activeRuleset.stats
        if statConfig.vitality then
            if statConfig.vitality == -1 and stat.Vitality ~= originalStat.Vitality then
                self:queueLog(Logger.BasicDebug, "Vitality is set to -1, and the current Vitality of [%d] does not match the original value of [%d], updating.",
                    stat.Vitality,
                    originalStat.Vitality)

                stat.Vitality = originalStat.Vitality
            elseif statConfig.vitality > 0 and stat.Vitality ~= statConfig.vitality then
                self:queueLog(Logger.BasicDebug, "Updating vitality from [%d] to [%d]", stat.Vitality, statConfig.vitality)
                stat.Vitality = statConfig.vitality
            end
        end

        if statConfig.abilityScores and next(statConfig.abilityScores) then
            for abilityId, score in pairs(statConfig.abilityScores) do
                if score == -1 and stat[abilityId] ~= originalStat[abilityId] then
                    self:queueLog(Logger.BasicDebug,
                        "Ability [%s] is set to -1, and the current value of [%d] does not match the original [%d] - updating",
                        abilityId,
                        stat[abilityId],
                        originalStat[abilityId])

                    stat[abilityId] = originalStat[abilityId]
                elseif score > 0 and stat[abilityId] ~= score then
                    self:queueLog(Logger.BasicDebug,
                        "Ability [%s] is set to [%d], which does not match the current value [%d] - updating",
                        abilityId,
                        score,
                        stat[abilityId])

                    stat[abilityId] = score
                end

                self.entityHandle.BaseStats.BaseAbilities[Ext.Enums.AbilityId[abilityId].Value + 1] = stat[abilityId]
            end

            self.entityHandle:Replicate("BaseStats")
        end
    end

    stat:Sync()
    self.entityHandle.Vars[ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME] = var
end

function MonsterLab_EntityProcessor:updateDatabaseEntries()
    ---@type MonsterLab_EntityVariable
    local var = self.entityHandle.Vars[ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME]

    if self.designerModeActive then
        self:queueLog(Logger.BasicDebug, "Skipping DB Entries update as entity is only spawned as part of Designer Mode")
        return
    end

    local mlEntityConstant = ConfigurationStructure.DynamicClassDefinitions.monsterLab.constants.entityParamPlaceholder
    local mlEntityDbKey = self.entityHandle.ServerCharacter.Template.Name .. "_" .. self.entityHandle.Uuid.EntityUuid

    local cachedDatabaseEntries = (self.entityHandle.Vars.AbsolutesLaboratory_MonsterLab_Entity --[[@as MonsterLab_EntityVariable]]).cachedDatabaseEntries or {}

    local newCachedDatabaseEntries = {}

    ---@param databaseCalls {[string] : MonsterLab_DatabaseEntry}
    local function updateDatabases(databaseCalls)
        for key, entry in pairs(TableUtils:DeeplyCopyTable(databaseCalls)) do
            if not entry.enabled then
                goto continue
            end

            if not entry.name or not next(entry.parameters) or TableUtils:IndexOf(entry.parameters, function(value)
                    return value.type == value.value or not value.value or value.value == ""
                end)
            then
                self:queueLog(Logger.BasicWarning,
                    "DB entry for ML Entity [%s] from Encounter [%s] under Mod [%s] is invalid - ensure a DB name was provided and all parameters are filled out. Entry: %s",
                    self.mlEntity.displayName,
                    self.encounter.encounter.name,
                    self.encounter.encounter.modId and Ext.Mod.GetMod(self.encounter.encounter.modId).Info.Name or "N/A",
                    entry)
                goto continue
            end

            local params = {}
            for _, param in ipairs(entry.parameters) do
                if param.value == mlEntityConstant then
                    param.value = mlEntityDbKey
                elseif param.type == "INTEGER" or param.type == "REAL" then
                    param.value = tonumber(param.value)
                end

                table.insert(params, param.value)
            end

            key = key:gsub(mlEntityConstant, mlEntityDbKey)

            if not cachedDatabaseEntries[key] then
                self:queueLog(Logger.BasicDebug, "Inserted entry into Database: %s", key)
                Osi[entry.name](Helpers:unpackParamTable(params, #params))
            else
                Logger:BasicTrace("Already exists in Database with entry %s", key)
            end
            newCachedDatabaseEntries[key] = entry
            ::continue::
        end
    end

    if self.encounter.encounter.databaseCalls and next(self.encounter.encounter.databaseCalls) then
        if Logger:IsLogLevelEnabled(Logger.PrintTypes.DEBUG) then
            local keys = {}
            for key in TableUtils:OrderedPairs(self.encounter.encounter.databaseCalls, nil, function(key, value)
                return value.enabled
            end) do
                table.insert(keys, key)
            end

            self:queueLog(Logger.BasicDebug, "Ensuring parity with Encounter-level DB calls: %s", keys)
        end

        updateDatabases(self.encounter.encounter.databaseCalls)
    end

    if self.mlEntity.databaseCalls and next(self.mlEntity.databaseCalls) then
        if Logger:IsLogLevelEnabled(Logger.PrintTypes.DEBUG) then
            local keys = {}
            for key in TableUtils:OrderedPairs(self.mlEntity.databaseCalls, nil, function(_, value)
                return value.enabled
            end) do
                table.insert(keys, key)
            end

            self:queueLog(Logger.BasicDebug, "Ensuring parity with Entity-level DB calls: %s", keys)
        end

        updateDatabases(self.mlEntity.databaseCalls)
    end

    for key, entry in pairs(cachedDatabaseEntries) do
        if not newCachedDatabaseEntries[key] then
            self:queueLog(Logger.BasicDebug, "Removing Entry from DB due to being inserted previously, but not being present or enabled in the current config. Entry: %s", entry)

            local correctedTable = {}
            for _, param in ipairs(entry.parameters) do
                table.insert(correctedTable, (param.type == "REAL" or param.type == "INTEGER") and tonumber(param.value) or param.value)
            end

            Osi[entry.name]:Delete(Helpers:unpackParamTable(correctedTable, #correctedTable))
        end
    end

    var.cachedDatabaseEntries = newCachedDatabaseEntries

    self.entityHandle.Vars.AbsolutesLaboratory_MonsterLab_Entity = var
end

function MonsterLab_EntityProcessor:updateOsirisProperties()
    local realEntityId = self.spawnedMLEntity.realEntityId

    if self.mlEntity.displayName and self.mlEntity.displayName ~= "" then
        self:queueLog(Logger.BasicDebug, "Updating Display Name to [%s]", self.mlEntity.displayName)
        Osi.SetStoryDisplayName(realEntityId, self.mlEntity.displayName)
    end

    local title = Ext.Loca.GetTranslatedString(Osi.ObjectGetTitle(realEntityId))
    if self.mlEntity.title and self.mlEntity.title ~= "" then
        if self.mlEntity.title ~= title then
            self:queueLog(Logger.BasicDebug, "Updating Title to [%s]", self.mlEntity.displayName)
            Osi.ObjectSetTitle(realEntityId, self.mlEntity.title)
        end
    elseif title ~= "" then
        self:queueLog(Logger.BasicDebug, "No Title is set, but entity has title [%s], so clearing it", title)
        Osi.ObjectSetTitle(realEntityId, "")
    end

    if self.encounter.encounter.faction and self.encounter.encounter.faction ~= Osi.GetFaction(realEntityId):sub(-36) then
        self:queueLog(Logger.BasicDebug, "Updating faction from [%s] to [%s]", Osi.GetFaction(realEntityId), self.encounter.encounter.faction)

        Osi.SetFaction(realEntityId, self.encounter.encounter.faction)
    end

    if self.encounter.encounter.combatGroupId and self.encounter.encounter.combatGroupId ~= Osi.GetCombatGroupID(realEntityId) then
        self:queueLog(Logger.BasicDebug, "Updating combatGroupId from [%s] to [%s]", Osi.GetCombatGroupID(realEntityId), self.encounter.encounter.combatGroupId)

        Osi.SetCombatGroupID(realEntityId, self.encounter.encounter.combatGroupId)
    end

    if self.freshSpawn or Osi.IsInCombat(realEntityId) == 0 then
        if not TableUtils:CompareLists(self.mlEntity.coordinates, self.spawnedMLEntity.coordinates) and #self.mlEntity.coordinates == 3 then
            self:queueLog(Logger.BasicDebug, "Updating coordinates from [%s] to [%s]", self.spawnedMLEntity.coordinates, self.mlEntity.coordinates)

            Osi.TeleportToPosition(realEntityId, self.mlEntity.coordinates[1], self.mlEntity.coordinates[2], self.mlEntity.coordinates[3])
            self.spawnedMLEntity.coordinates = self.mlEntity.coordinates
        end

        if self.mlEntity.rotation ~= self.spawnedMLEntity.rotation then
            self:queueLog(Logger.BasicDebug, "Updating rotation from [%s] to [%s]", self.spawnedMLEntity.rotation, self.mlEntity.rotation)

            self.entityHandle.Steering.TargetRotation = tonumber(self.mlEntity.rotation)
            self.spawnedMLEntity.rotation = self.mlEntity.rotation
        end

        Channels.UpdateRotation:Broadcast({
            entityId = self.entityHandle.Uuid.EntityUuid,
            rotation = tonumber(self.mlEntity.rotation),
            designerModeActive = self.designerModeActive
        })

        if self.mlEntity.animation.simple then
            if self.mlEntity.animation.simple ~= self.spawnedMLEntity.animation.simple then
                self:queueLog(Logger.BasicDebug, "Updating simple animation from [%s] to [%s]", self.spawnedMLEntity.animation.simple, self.mlEntity.animation.simple)
                Osi.PlayAnimation(realEntityId, self.mlEntity.animation.simple)
            end
        else
            if not TableUtils:CompareLists(self.mlEntity.animation.looping, self.spawnedMLEntity.animation.looping) then
                self:queueLog(Logger.BasicDebug, "Updating looping animation from [%s] to [%s]", self.spawnedMLEntity.animation.looping, self.mlEntity.animation.looping)

                local looping = self.mlEntity.animation.looping
                Osi.PlayLoopingAnimation(realEntityId,
                    looping.startAnimation,
                    looping.loopAnimation,
                    looping.endAnimation,
                    looping.loopVariation1,
                    looping.loopVariation2,
                    looping.loopVariation3,
                    looping.loopVariation4
                )
            end
        end
        self.spawnedMLEntity.animation = self.mlEntity.animation
    else
        self:queueLog(Logger.BasicDebug, "Entity is an existing spawn and in combat, skipping placement/animation edits")
    end

    if self.designerModeActive then
        self:queueLog(Logger.BasicDebug, "Designer Mode Is Active - setting CanFight and CanJoinCombat to 0")
        Osi.SetCanFight(realEntityId, 0)
        Osi.SetCanJoinCombat(realEntityId, 0)
    end
end

Ext.RegisterConsoleCommand("Lab_MonsterLab_DeleteDuplicates", function(cmd, _)
    local currentLevel = Ext.Entity.Get(Osi.GetHostCharacter()).ServerCharacter.Level

    ---@type MonsterLab_SpawnedEntities
    local allSpawned = Ext.Vars.GetModVariables(ModuleUUID).MonsterLab_SpawnedEntities or {}

    Logger:BasicDebug("%s", allSpawned)

    for _, entityId in pairs(Ext.Vars.GetEntitiesWithVariable(ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME)) do
        ---@type EntityHandle
        local entity = Ext.Entity.Get(entityId)

        ---@type MonsterLab_EntityVariable
        local entityVar = entity.Vars[ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME]

        Logger:BasicInfo("Processing %s - %s", entityId, entityVar.mlEntityId)

        if entity.Level.LevelName == currentLevel then
            local deleteEntity = false

            if not TableUtils:IndexOf(allSpawned, function(value)
                    return value.entities[entityVar.mlEntityId] ~= nil
                end)
            then
                deleteEntity = true
            else
                for _, encounter in pairs(allSpawned) do
                    for mlEntityId, spawnedEntity in pairs(encounter.entities) do
                        if spawnedEntity.mlEntityId == entityVar.mlEntityId and spawnedEntity.realEntityId ~= entityId then
                            deleteEntity = true
                            goto exit
                        end
                    end
                end
                ::exit::
            end

            if deleteEntity then
                Logger:BasicInfo("Deleting MonsterLab Entity %s (%s)", EntityRecorder:GetEntityName(entity), entityId)
                Osi.RequestDeleteTemporary(entityId)

                local presentInDatabases = ClientHelpers:getDBEntries_ForEntity(entityId)

                for databaseName, paramList in pairs(presentInDatabases) do
                    Logger:BasicInfo("Deleting from DB [%s]", databaseName)
                    for _, params in ipairs(paramList) do
                        Osi[databaseName]:Delete(Helpers:unpackParamTable(params, #params))
                    end
                end
            end
        end
    end
end)
