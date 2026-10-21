Channels.UpdateRotation:SetHandler(function(data, user)
	if not data.rotation then
		return
	end

	local function updateRotation()
		---@type EntityHandle?
		local entity = Ext.Entity.Get(data.entityId)

		if not entity then
			Ext.OnNextTick(function(e)
				updateRotation()
			end)
			return
		else
			local function update()
				local entity = Ext.Entity.Get(data.entityId)
				Logger:BasicDebug("Updated rotation for %s from %s to %s",
					EntityRecorder:GetEntityName(entity),
					entity.Steering.TargetRotation,
					data.rotation)

				entity.Steering.TargetRotation = data.rotation
			end

			if not entity.ClientCharacter.Active then
				Ext.Entity.OnCreateDeferredOnce("Active", function(entity)
					local limit = 0
					local function waitForSteering()
						if entity.Steering.TargetRotation == 0. and limit < 33 then
							limit = limit + 1
							Ext.OnNextTick(function()
								waitForSteering()
							end)
						else
							update()
						end
					end

					waitForSteering()
				end, entity)
			else
				update()
			end
		end
	end

	updateRotation()
end)

local function createCustomStats()
	local count = 0
	for _, folder in pairs(MonsterLabConfigurationProxy.folders) do
		for _, encounter in pairs(folder.encounters) do
			for id, entity in pairs(encounter.entities) do
				---@type CharacterTemplate
				local template = not entity.stat and (Ext.ClientTemplate.GetTemplate(entity.template))

				if not entity.stat and not template then
					Logger:BasicDebug("Could not create dedicated stat for ML Entity (%s - %s) - a custom stat was not set and the template [%s] could not be loaded",
						entity.displayName,
						id,
						entity.template)
					goto next_entity
				end

				if not Ext.Stats.Get(entity.stat or template.Stats) then
					Logger:BasicWarning("Could not create dedicated stat for ML Entity (%s - %s) - the base stat [%s] does not exist",
						entity.displayName,
						id,
						entity.stat or template.Stats)

					goto next_entity
				end

				local trueStatName = ("LAB_%s_%s"):format(entity.stat or template.Stats, id:sub(-12))

				---@type Character
				local stat = Ext.Stats.Get(trueStatName)
				if not stat then
					Logger:BasicDebug("Creating Custom Stat [%s] for edits", trueStatName)

					stat = Ext.Stats.Create(trueStatName,
						"Character",
						(entity.stat or template.Stats)) --[[@as Character]]
				end

				count = count + 1

				::next_entity::
			end
		end
	end

	Logger:BasicInfo("Created %d custom stats for all Monster Lab entities", count)
end

Ext.Events.StatsLoaded:Subscribe(function(e)
	createCustomStats()
end, { Priority = 1000 })