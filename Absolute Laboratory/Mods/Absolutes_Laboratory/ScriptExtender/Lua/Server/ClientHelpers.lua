ClientHelpers = {}

Channels.GetEntityIcon:SetRequestHandler(function(data, user)
	local entity = Ext.Entity.Get(data.target) --[[@as EntityHandle]]
	return { Result = entity.Icon and entity.Icon.Icon }
end)

Channels.GetCurrentHostLevel:SetRequestHandler(function(data, user)
	---@type EntityHandle
	local entity = Ext.Entity.Get(Osi.GetHostCharacter())

	return entity.Level.LevelName
end)

Channels.TeleportToLevel:SetHandler(function(data, user)
	Osi.TeleportPartiesToLevelWithMovie(data.LevelName, "", "")
end)

Channels.TeleportToCoords:SetHandler(function(data, user)
	Osi.TeleportToPosition(Osi.GetHostCharacter(), data.x, data.y, data.z)
end)

Channels.TeleportToEntity:SetHandler(function(data, user)
	Osi.TeleportTo(Osi.GetHostCharacter(), data)
end)

Channels.TeleportEntityToHost:SetHandler(function(data, user)
	Osi.AppearAt(data, Osi.GetHostCharacter(), 0, "", "")
end)

Channels.GetEntityStat:SetRequestHandler(function(data, user)
	local entity = Ext.Entity.Get(data.target) --[[@as EntityHandle]]
	return { Result = entity.Data and entity.Data.StatsId }
end)

Channels.IsEntityAlive:SetRequestHandler(function(data, user)
	return { Result = Osi.IsDead(data.target) == 0 }
end)

---@param entityId Guid
---@param templateName string?
---@param shouldFilter boolean?
---@return { [string]: string[][] }
---@return string[]
function ClientHelpers:getDBEntries_ForEntity(entityId, templateName, shouldFilter)
	local dbKey
	if not templateName then
		---@type EntityHandle
		local entity = Ext.Entity.Get(entityId)

		if not entity or not entity.ServerCharacter then
			return {}, {}
		end

		dbKey = entity.ServerCharacter.Template.Name .. "_" .. entity.Uuid.EntityUuid
	else
		dbKey = templateName .. "_" .. entityId
	end

	local directory = Ext.Mod.GetMod(ModuleUUID).Info.Directory

	---@type {[string]: string[]}
	local dbDefs = FileUtils:LoadTableFile(string.format("Mods/%s/OsirisMetaData/CharacterIndexedDB.json", directory), "data")

	---@type string[]
	local stringResults = {}
	---@type {[string]: string[][]}
	local parameterizedResults = {}

	---@param params string[]
	---@param count number
	local function unpack(params, count, i)
		i = i or 1
		if i <= count then
			return params[i], unpack(params, count, i + 1)
		end
	end

	local callcount = 0
	for dbName, args in pairs(dbDefs) do
		if shouldFilter and (dbName == "DB_Sees" or dbName == "DB_Dead" or dbName:find("DB%_InternPlayer")) then
			goto continue
		end

		for i = 1, #args do
			if args[i] == "CHARACTER" then
				local currentParam = { [i] = dbKey }

				callcount = callcount + 1
				local result = Osi[dbName]:Get(unpack(currentParam, #args))
				if next(result) then
					parameterizedResults[dbName] = parameterizedResults[dbName] or {}
					for _, param in ipairs(result) do
						table.insert(parameterizedResults[dbName], TableUtils:DeeplyCopyTable(param))

						local formattedString = ""
						for y, entry in ipairs(param) do
							formattedString = formattedString .. entry
							if y < #param then
								formattedString = formattedString .. ", "
							end
						end

						table.insert(stringResults, string.format("%s(%s)", dbName, formattedString))
					end
				end
			end
		end
		::continue::
	end

	return parameterizedResults, stringResults
end

Channels.GetEntityDump:SetRequestHandler(function(data, user)
	Logger:BasicDebug("Generating Dump for entity %s", data.entity)

	---@type EntityHandle
	local entity = Ext.Entity.Get(data.entity)

	---@type string[]
	local fieldsToGet = data.fields

	local response = {}

	if entity then
		for componentName, field in pairs(entity:GetAllComponents()) do
			if TableUtils:IndexOf(fieldsToGet, componentName) then
				response[componentName] = field
			end
		end

		if TableUtils:IndexOf(fieldsToGet, "Databases") then
			response["Databases"] = ClientHelpers:getDBEntries_ForEntity(data.entity)
		end
	end

	return CustomEntitySerializer:recursiveSerialization(response, nil, { Ext.Entity.HandleToUuid(entity) })
end)

---@class GetDBEntriesRequest
---@field entityId string
---@field templateName string?

---@class GetDBEntriesResponse
---@field list {[string]: string[][]}
---@field pretty string[]

Channels.GetDBEntries_ForEntity:SetRequestHandler(
---@param data GetDBEntriesRequest
	function(data)
		local parameterizedResults, stringResults = ClientHelpers:getDBEntries_ForEntity(data.entityId, data.templateName, true)
		return {
			["list"] = parameterizedResults,
			["pretty"] = stringResults
		}
	end)

Ext.RegisterConsoleCommand("Lab_FindDBEntries", function(cmd, ...)
	local entityIds = { ... }

	for _, entityId in ipairs(entityIds) do
		_D(({ [entityId] = ClientHelpers:getDBEntries_ForEntity(entityId) }))
	end
end)

Ext.RegisterConsoleCommand("Lab_ParseDBs", function(cmd, ...)
	local directory = Ext.Mod.GetMod(ModuleUUID).Info.Directory

	---@type string[]
	local dbDefs = FileUtils:LoadTableFile(string.format("Mods/%s/OsirisMetaData/Databases.json", directory), "data")

	---@type {[string]: string[]}
	local results = {}

	for _, databaseCommand in ipairs(dbDefs) do
		if databaseCommand:match("(CHARACTER)%A") then
			---@type string
			local dbName = databaseCommand:match("(.*)%(")

			results[dbName] = {}

			for arg in databaseCommand:match("%((.*)%)"):gmatch("([%w%._-]+)") do
				table.insert(results[dbName], arg)
			end
		end
	end

	FileUtils:SaveTableToFile("CharacterIndexedDB.json", results)
end)

Channels.GetDBEntries_ForDatabase:SetRequestHandler(function(dbName, _)
	local directory = Ext.Mod.GetMod(ModuleUUID).Info.Directory

	---@type {[string]: string[]}
	local dbDefs = FileUtils:LoadTableFile(string.format("Mods/%s/OsirisMetaData/CharacterIndexedDB.json", directory), "data")

	---@param count number
	local function fillNils(count, i)
		i = i or 1
		if i <= count then
			return nil, fillNils(count, i + 1)
		end
	end

	local results = Osi[dbName]:Get(fillNils(#dbDefs[dbName]))

	return results
end)

---@class TriggerRequest
---@field radius number

---@class TriggerResponse
---@field entityId Guid
---@field position number[]
---@field bounds TriggerPhysicsBoundsInfo?

local TriggerEnum = {
	[2] = "ServerEocPointTrigger",
	[6] = "ServerFloorTrigger",
	[7] = "ServerRoomTrigger",
	[11] = "ServerEocAreaTrigger",
	[16] = "ServerEventTrigger",
	[23] = "TriggerExplorationArea",
}

Channels.GetNearbyTriggers:SetRequestHandler(function(request)
	---@cast request TriggerRequest

	---@type {[string] : TriggerResponse[]}
	local triggers = {}

	for _, trigger in pairs(Ext.Entity.GetAllEntitiesWithComponent("TriggerType")) do
		if TriggerEnum[trigger.TriggerType.Type] then
			---@type Trigger
			local triggerInfo = trigger[TriggerEnum[trigger.TriggerType.Type]]

			triggers[triggerInfo.TriggerType] = triggers[triggerInfo.TriggerType] or {}

			table.insert(triggers[triggerInfo.TriggerType], {
				entityId = trigger.Uuid.EntityUuid,
				position = trigger.Transform and trigger.Transform.Transform.Translate,
				bounds = triggerInfo.Bounds
			} --[[@as TriggerResponse]])
		end
	end

	Logger:BasicDebug("Sending triggers %s", triggers)

	return triggers
end)
