Ext.Require("Server/MonsterLab/MonsterLabBaseProcessor.lua")

Ext.Vars.RegisterModVariable(ModuleUUID, "MonsterLab_SpawnedEntities", {
	Server = true,
	Client = true,
	WriteableOnServer = true,
	WriteableOnClient = true,
	SyncToClient = true,
	SyncToServer = true
})

ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME = "AbsolutesLaboratory_MonsterLab_Entity"

---@class MonsterLab_EntityVariable
---@field profileId Guid?
---@field folderId Guid
---@field encounterId Guid
---@field mlEntityId Guid
---@field cachedDatabaseEntries {[string]: MonsterLab_DatabaseEntry}
---@field originalStatName string?

Ext.Vars.RegisterUserVariable("AbsolutesLaboratory_MonsterLab_Entity", {
	Server = true,
	Client = true,
	WriteableOnServer = true,
	WriteableOnClient = true,
	SyncToClient = true,
	SyncToServer = true
})

MonsterLabEncounterManager = {
	mazzleLib = Mods.Mazzle_Lib,
	---@type Mazzle_Orbs
	mazzleOrbs = nil,
	---@type {[Guid]: {[string]: Guid}}
	encounterVisualizations = {},
	config = MonsterLabConfigurationProxy
}

Ext.Events.SessionLoaded:Subscribe(function(e)
	MonsterLabEncounterManager.mazzleLib = Mods.Mazzle_Lib

	if MonsterLabEncounterManager.mazzleLib then
		MonsterLabEncounterManager.mazzleOrbs = MonsterLabEncounterManager.mazzleLib.Mazzle_Orbs
		-- ---@type MLT_Collection_Metadata
		-- local collection_parameters = {
		-- 	allow_clear_removal = false,
		-- 	allow_manual_removal = false,
		-- 	allow_level_unload = true,
		-- 	allow_thinning = false,
		-- }

		-- mazzleObjectManager:Register_Collection("MonsterLab_EncounterVisualizations", "orb", collection_parameters)
	end
end)

---@class ManageDesignerModeRequest
---@field playersCanFight boolean
---@field playersCanDialogue boolean
Channels.ManageDesignerMode:SetHandler(
---@param request ManageDesignerModeRequest
	function(request)
		for _, playerTable in pairs(Osi.DB_Players:Get(nil)) do
			for _, summmonTable in pairs(Osi.DB_PlayerSummons:Get(playerTable[1])) do
				Osi.SetCanFight(summmonTable[1], request.playersCanFight and 1 or 0)
				Osi.SetCanJoinCombat(summmonTable[1], request.playersCanFight and 1 or 0)

				if request.playersCanDialogue then
					Osi.RemoveBoosts(summmonTable[1], "DialogueBlock();", 0, summmonTable[1], summmonTable[1])
				else
					Osi.AddBoosts(summmonTable[1], "DialogueBlock();", summmonTable[1], summmonTable[1])
				end
			end

			Osi.SetCanFight(playerTable[1], request.playersCanFight and 1 or 0)
			Osi.SetCanJoinCombat(playerTable[1], request.playersCanFight and 1 or 0)

			if request.playersCanDialogue then
				Osi.RemoveBoosts(playerTable[1], "DialogueBlock();", 0, playerTable[1], playerTable[1])
			else
				Osi.AddBoosts(playerTable[1], "DialogueBlock();", playerTable[1], playerTable[1])
			end
		end
	end)

---@class VisualizationRequest
---@field encounterId Guid
---@field coords number[]?
---@field context string?
---@field cleanup boolean?
---@field cleanupEncounter boolean?
---@field moonbeam number?

Channels.OrbAtPosition:SetHandler(
---@param data VisualizationRequest
	function(data)
		local self = MonsterLabEncounterManager
		if not self.mazzleLib then
			Logger:BasicWarning("MazzleLib isn't loaded?")
			return
		end

		self.encounterVisualizations[data.encounterId] = self.encounterVisualizations[data.encounterId] or {}
		local encounterVis = self.encounterVisualizations[data.encounterId]

		if data.cleanup then
			Osi.RequestDelete(encounterVis[data.context])
			encounterVis[data.context] = nil
		elseif data.cleanupEncounter then
			for _, vis in pairs(encounterVis) do
				Osi.RequestDelete(vis)
			end
			self.encounterVisualizations[data.encounterId] = nil
		else
			if not encounterVis[data.context] then
				encounterVis[data.context] = self.mazzleOrbs:Create_Debug_Orb(data.coords[1], data.coords[2], data.coords[3])
			else
				Osi.TeleportToPosition(encounterVis[data.context], data.coords[1], data.coords[2], data.coords[3])
			end

			if data.moonbeam then
				self.mazzleOrbs:Add_VFX_to_Object(encounterVis[data.context], "moonbeam", data.moonbeam)
			end
		end
	end)


---@class MonsterLabEntity_Spawned : MonsterLabEntity
---@field realEntityId Guid
---@field nonCachedTemplateId Guid

---@class MonsterLabEncounter_Spawned : MonsterLabEncounter
---@field entities {[Guid]: MonsterLabEntity_Spawned}

---@alias MonsterLab_SpawnedEntities {[Guid]: MonsterLabEncounter_Spawned}

---@class ManageEncounterRequest
---@field folderId Guid
---@field encounterId Guid
---@field encounter MonsterLabEncounter? not present if delete is true
---@field profileId Guid?
---@field delete boolean?

---@type MonsterLab_SpawnedEntities
local allSpawnedEntities

---@param request ManageEncounterRequest
---@return MonsterLab_EncounterProcessor?
function MonsterLabEncounterManager:ManageEncounterSpawns(request)
	Logger:BasicTrace("Processing Encounter Request: \n%s", request)

	if not allSpawnedEntities then
		allSpawnedEntities = Ext.Vars.GetModVariables(ModuleUUID).MonsterLab_SpawnedEntities or {}
	end

	if next(allSpawnedEntities) then
		for encounterId, spawnedEncounter in pairs(allSpawnedEntities) do
			local encounterExists = false

			for _, folder in pairs(MonsterLabConfigurationProxy.folders) do
				if folder.encounters[encounterId] then
					encounterExists = true
					break
				end
			end

			if not encounterExists then
				local encounterProcessor = EncounterProcessor:begin(request, nil, spawnedEncounter, request.profileId ~= nil)
				encounterProcessor:delete("Encounter no longer exists in the local or mod-sourced config(s)/active profile", true)
				encounterProcessor:complete()

				allSpawnedEntities[encounterId] = nil

				Ext.Vars.GetModVariables(ModuleUUID).MonsterLab_SpawnedEntities = allSpawnedEntities
			end
		end
	end

	if not request.encounterId or (request.delete and not allSpawnedEntities[request.encounterId]) then
		return
	end

	local altEncounterInfo = request.encounter and TableUtils:DeeplyCopyTable(request.encounter)
	if request.encounter then
		request.encounter.encounterId = request.encounterId
		altEncounterInfo.entities = nil
	end

	allSpawnedEntities[request.encounterId] = allSpawnedEntities[request.encounterId] or altEncounterInfo or {}

	local spawnedEncounter = allSpawnedEntities[request.encounterId]
	spawnedEncounter.encounterId = request.encounterId
	spawnedEncounter.entities = spawnedEncounter.entities or {}

	local encounter = EncounterProcessor:begin(request, request.encounter, spawnedEncounter, request.profileId == nil)
	if not encounter then
		Logger:BasicError("Couldn't construct an encounter processor instance for request %s", request)
		return
	end

	local success, error = xpcall(function()
		if request.delete then
			encounter:delete(("Requested by %s"):format(request.profileId and "Profile Executor" or "Designer"))
			if not next(spawnedEncounter.entities) then
				allSpawnedEntities[request.encounterId] = nil
			end
		else
			for entityId, entityProcessor in pairs(encounter.entities) do
				local success, error = xpcall(function(...)
					entityProcessor:spawn()
				end, debug.traceback)

				if not success then
					entityProcessor:queueLog(Logger.BasicError, "Encountered error while processing entity %s (%s) under encounter %s (%s - %s): \n%s",
						entityId,
						entityProcessor.mlEntity.displayName,
						request.encounter.name,
						request.encounter.gameLevel,
						request.encounterId,
						error)
				end
			end
		end
	end, debug.traceback)

	if not success then
		Logger:BasicError("Fatal error occured while processing %s - %s", request.encounterId, error)
		Ext.Vars.GetModVariables(ModuleUUID).MonsterLab_SpawnedEntities = allSpawnedEntities
	end

	if not request.profileId then
		encounter:complete()
	else
		self:checkEncounterCompletion(encounter)
	end
	return encounter
end

---@param encounter MonsterLab_EncounterProcessor
---@param count number?
function MonsterLabEncounterManager:checkEncounterCompletion(encounter, count)
	count = count or 1

	if count <= 10 then
		for _, entityProcessor in pairs(encounter.entities) do
			if not entityProcessor.completed then
				Ext.Timer.WaitFor(33, function()
					self:checkEncounterCompletion(encounter, count + 1)
				end)
				return
			end
		end
	else
		local unfinishedEntities = {}
		for _, entityProcessor in pairs(encounter.entities) do
			if not entityProcessor.completed then
				unfinishedEntities[entityProcessor.mlEntity.mlEntityId] = entityProcessor.mlEntity
			end
		end

		encounter:queueLog(Logger.BasicWarning, "Had to force encounter %s (%s - %s) to complete after 10 retries",
			encounter.encounter.name,
			encounter.encounter.gameLevel,
			encounter.encounter.encounterId)

		encounter:queueLog(Logger.BasicDebug, "Unfinished entities: %s", unfinishedEntities)
	end

	encounter:complete()

	Ext.Vars.GetModVariables(ModuleUUID).MonsterLab_SpawnedEntities = allSpawnedEntities
end

Channels.ManageEncounterSpawns:SetHandler(
---@param request ManageEncounterRequest
	function(request)
		MonsterLabEncounterManager:ManageEncounterSpawns(request)
	end)

function MonsterLabEncounterManager:MutateAllEncounters()
	Ext.Utils.ProfileBegin("Monster Lab Mutate All Entities")
	Logger:BasicDebug("=========== Starting Mutation Of All Encounters ===========")
	if allSpawnedEntities then
		local success, error = xpcall(function(...)
			for encounterId, spawnedEncounter in pairs(allSpawnedEntities) do
				local folderId = TableUtils:IndexOf(MonsterLabConfigurationProxy.folders, function(value)
					return value.encounters[encounterId] ~= nil
				end)

				local encounter

				if folderId then
					encounter = MonsterLabConfigurationProxy.folders[folderId].encounters[encounterId]
				end

				if not encounter then
					Logger:BasicWarning("Could not find an entry for encounterId %s", encounterId)

					goto continue
				end

				Logger:BasicDebug("======= Starting Mutation Of Encounter %s =======", encounter.name or encounterId)
				for mlEntityId, entity in pairs(spawnedEncounter.entities) do
					---@type MutatorEntityVar
					local entityVar = {
						appliedMutators = {},
						appliedMutatorsPath = {},
						originalValues = {}
					}

					---@type EntityHandle
					local entityHandle = Ext.Entity.Get(entity.realEntityId)

					if entityHandle and entityHandle.Vars[ABSOLUTES_LABORATORY_MONSTERLAB_ENTITY_VAR_NAME] then
						local rulesetRules = MonsterLabProfileExecutor:GetRulesetForEntity(entityHandle)

						MutationProfileExecutor:compileMutatorsForEntity(entityVar, rulesetRules.mutators, rulesetRules, 9999)

						if entityHandle.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME] then
							MutatorInterface:undoMutator(entityHandle, entityVar)

							Ext.Timer.WaitFor(100, function()
								MutatorInterface:applyMutator(entityHandle, entityVar)
								entityHandle.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME] = entityVar
							end)
						else
							MutatorInterface:applyMutator(entityHandle, entityVar)
							entityHandle.Vars[ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME] = entityVar
						end
					else
						Logger:BasicDebug("Entity %s couldn't be loaded", mlEntityId)
					end
				end
				Logger:BasicDebug("======= Finished Mutation Of Encounter %s =======", spawnedEncounter.name or encounterId)

				::continue::
			end
		end, debug.traceback)

		if not success then
			Logger:BasicError("Unrecoverable error: %s", error)
		end
	end

	Logger:BasicDebug("=========== Finished Mutation Of All Encounters ===========")
	Ext.Utils.ProfileEnd("Monster Lab Mutate All Entities")
end

Ext.RegisterConsoleCommand("Lab_MonsterLab_DatabaseParityCheck", function(cmd, ...)
	---@type string[]
	local entityIds = { ... }
	if not next(entityIds) then
		Logger:BasicError("Must supply 1-many MonsterLab spawned entityIds, or the ALL keyword")
		return
	end

	---@type EntityHandle[]
	local entities = {}

	if entityIds[1]:upper() == "ALL" then
		for _, entityId in pairs(Ext.Vars.GetEntitiesWithVariable("AbsolutesLaboratory_MonsterLab_Entity")) do
			local entity = Ext.Entity.Get(entityId)
			if entity then
				if not entity.ServerCharacter then
					Logger:BasicError("Entity %s must exist and be a character", entityId)
					return
				end

				table.insert(entities, Ext.Entity.Get(entity))
			end
		end
	else
		for _, entityId in ipairs(entityIds) do
			---@type EntityHandle
			local entity = Ext.Entity.Get(entityId)

			if not entity or not entity.ServerCharacter then
				Logger:BasicError("Entity must exist and be a character")
				return
			end

			table.insert(entities, entity)
		end
	end

	for _, entity in ipairs(entities) do
		if not entity.Vars.AbsolutesLaboratory_MonsterLab_Entity then
			Logger:BasicError("Entity %s must have been spawned by Monster Lab", entity.Uuid.EntityUuid)
		end

		local _, prettyList = ClientHelpers:getDBEntries_ForEntity(entity.Uuid.EntityUuid, nil, true)

		local dbKey = entity.ServerCharacter.Template.Name .. "_" .. entity.Uuid.EntityUuid

		local cachedDbs = (entity.Vars.AbsolutesLaboratory_MonsterLab_Entity --[[@as MonsterLab_EntityVariable]]).cachedDatabaseEntries or {}

		local extraDbs = {}

		for _, pretty in TableUtils:OrderedPairs(prettyList, function(key, value)
			return value
		end) do
			if not cachedDbs[pretty]
				and not cachedDbs[pretty:gsub(Helpers:SanitizeStringForFind(dbKey), entity.Uuid.EntityUuid)]
				and not cachedDbs[pretty:gsub(Helpers:SanitizeStringForFind(entity.Uuid.EntityUuid), dbKey)]
			then
				table.insert(extraDbs, pretty)
			end
		end

		if not next(extraDbs) then
			Logger:BasicInfo("Entity %s (%s) is not present in any extra databases - current DB list: %s", EntityRecorder:GetEntityName(entity), entity.Uuid.EntityUuid, prettyList)
		else
			local keys = {}
			for key in TableUtils:OrderedPairs(cachedDbs) do
				table.insert(keys, key)
			end
			Logger:BasicInfo("Entity %s (%s) is present in extra databases.\n Extras: %s\nBase List: %s", EntityRecorder:GetEntityName(entity), entity.Uuid.EntityUuid, extraDbs,
				keys)
		end

		Logger:BasicInfo("==============================================================")
	end
end)

Ext.RegisterConsoleCommand("Lab_ResetMonsterLabDatabases", function(cmd, ...)
	---@type string[]
	local entityIds = { ... }
	if not next(entityIds) then
		Logger:BasicError("Must supply 1-many MonsterLab spawned entityIds, or the ALL keyword")
		return
	end

	---@type EntityHandle[]
	local entities = {}

	if entityIds[1]:upper() == "ALL" then
		for _, entityId in pairs(Ext.Vars.GetEntitiesWithVariable("AbsolutesLaboratory_MonsterLab_Entity")) do
			local entity = Ext.Entity.Get(entityId)
			if entity then
				table.insert(entities, Ext.Entity.Get(entity))
			end
		end
	else
		for _, entityId in ipairs(entityIds) do
			---@type EntityHandle
			local entity = Ext.Entity.Get(entityId)

			if not entity or not entity.ServerCharacter then
				Logger:BasicError("Entity %s must exist and be a character", entityId)
				return
			end

			table.insert(entities, entity)
		end
	end

	for _, entity in pairs(entities) do
		---@type MonsterLab_EntityVariable
		local entityVar = entity.Vars.AbsolutesLaboratory_MonsterLab_Entity

		if not entity.Vars.AbsolutesLaboratory_MonsterLab_Entity then
			Logger:BasicError("Entity %s must have been spawned by Monster Lab", entity.Uuid.EntityUuid)
		end

		local databaseList = ClientHelpers:getDBEntries_ForEntity(entity.Uuid.EntityUuid, nil, true)

		for databaseName, paramList in pairs(databaseList) do
			Logger:BasicInfo("Deleting all %d entries from database %s for entity %s", #paramList, databaseName, EntityRecorder:GetEntityName(entity))
			for _, params in ipairs(paramList) do
				Osi[databaseName]:Delete(Helpers:unpackParamTable(params, #params))
			end
		end

		entityVar.cachedDatabaseEntries = {}

		entity.Vars.AbsolutesLaboratory_MonsterLab_Entity = entityVar
	end

	Logger:BasicWarning("All Database Entries cleared for all spawned Monster Lab entities - save and reload your game to rehydrate the databases with the current config")
end)
