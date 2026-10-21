---@class MonsterLab_EncounterProcessor : MonsterLab_BaseProcessor
EncounterProcessor = MonsterLab_BaseProcessor:new()

---@type number
EncounterProcessor.startTime = nil

EncounterProcessor.completed = false

---@type ManageEncounterRequest
EncounterProcessor.request = nil

---@type MonsterLabEncounter?
EncounterProcessor.encounter = nil
---@type MonsterLabEncounter_Spawned?
EncounterProcessor.spawnedEncounter = nil
EncounterProcessor.designerModeActive = false

---@type {[Guid]: MonsterLab_EntityProcessor}
EncounterProcessor.entities = {}

---@param request ManageEncounterRequest
---@param encounter MonsterLabEncounter?
---@param spawnedEncounter MonsterLabEncounter_Spawned?
---@param designerModeActive boolean?
---@return MonsterLab_EncounterProcessor?
function EncounterProcessor:begin(request, encounter, spawnedEncounter, designerModeActive)
    if not encounter and not spawnedEncounter then
        return nil
    end

    ---@type MonsterLab_EncounterProcessor
    local instance = {}

    setmetatable(instance, self)
    self.__index = self

    instance.startTime = Ext.Timer.MonotonicTime()
    instance.request = request
    instance.queuedLogs = {}
    instance.encounter = encounter or spawnedEncounter
    instance.spawnedEncounter = spawnedEncounter
    instance.designerModeActive = designerModeActive or false
    instance.entities = {}

    instance:queueLog(Logger.BasicDebug,
        "====== Start Processing Encounter %s (%s) (%s) ======",
        instance.encounter.name, instance.encounter.gameLevel, instance.encounter.encounterId or "N/A"
    )

    instance:queueLog(Logger.BasicDebug,
        "|Designer Mode: %s | Provided Encounter: %s | Provided Spawned Encounter: %s|\n",
        designerModeActive or false,
        request.encounter ~= nil,
        spawnedEncounter ~= nil)

    for mlEntityId, mlEntity in pairs(encounter and encounter.entities or spawnedEncounter.entities) do
        instance.entities[mlEntityId] = MonsterLab_EntityProcessor:new(instance,
            mlEntityId,
            mlEntity,
            spawnedEncounter and spawnedEncounter.entities[mlEntityId],
            designerModeActive)
    end

    if encounter and spawnedEncounter and spawnedEncounter.entities and (not designerModeActive or #encounter.entities > 1) then
        for entityId, spawnedEntity in pairs(spawnedEncounter.entities) do
            if not instance.entities[entityId] and spawnedEntity.realEntityId then
                local entity = MonsterLab_EntityProcessor:new(instance, entityId, nil, spawnedEntity, designerModeActive)
                if entity then
                    entity:delete("Does Not Exist In the Encounter", true)
                    entity:complete()
                end
            end
        end
    end

    return instance
end

function EncounterProcessor:complete()
    if not self.completed then
        for _, entityProcessor in pairs(self.entities) do
            entityProcessor:complete()
        end

        self:flushLogs()

        if not self.designerModeActive then
            Logger:BasicInfo("====== Finished Processing Encounter %s (%s) (%s) after %dms ======\n",
                self.encounter.name,
                self.encounter.gameLevel,
                self.encounter.encounterId,
                Ext.Timer.MonotonicTime() - self.startTime)
        end

        self.completed = true
    end
end

---@param reason string
---@param force boolean?
function EncounterProcessor:delete(reason, force)
    if self.spawnedEncounter and self.spawnedEncounter.entities then
        self:queueLog(Logger.BasicDebug, "Deleting Due To: %s", reason)

        for entityId, entityProcessor in pairs(self.entities) do
            if entityProcessor:delete(reason, force) then
                entityProcessor:complete()
                self.spawnedEncounter.entities[entityId] = nil
            end
        end
    end
end
