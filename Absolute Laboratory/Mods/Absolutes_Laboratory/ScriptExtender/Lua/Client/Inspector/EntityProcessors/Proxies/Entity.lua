EntityHandleProxy = EntityProxy:new()
EntityHandleProxy.fieldsToParse = {
	"ActionResources",
	"AddedSpells",
	"AttitudesToPlayers",
	"AttributeFlags",
	"AvailableLevel",
	"BaseHp",
	"BaseStats",
	"BoostsContainer",
	"CanDoActions",
	"CanBeDisarmed",
	"CanBeLooted",
	"Classes",
	"ClientEquipmentVisuals",
	"ClientVisualsDesiredState",
	"ClientEquipmentVisibilityState",
	-- "CombatParticipant", - Provides EntityHandles of every entity in combat, causes a shit ton of overwork from recurisve permutations
	"Concentration",
	"Data",
	"Databases",
	"DifficultyCheck",
	"DisplayName",
	"DualWielding",
	"EquipmentVisual",
	"EocLevel",
	"Expertise",
	"Faction",
	"FleeCapability",
	"HealBlock",
	"Health",
	"Hearing",
	"InterruptContainer",
	"InterruptPreferences",
	"InventoryOwner",
	"Invisibility",
	"LearnedSpells",
	"LevelUp",
	"Loot",
	"Movement",
	"ObjectInteraction",
	"OriginalTemplate",
	"ObjectSize",
	"PassiveContainer",
	"Proficiency",
	"ProgressionContainer",
	"Race",
	"Resistances",
	"ServerAiArchetype",
	"ServerAnubisTag",
	"ServerBaseProficiency",
	"ServerBaseStats",
	"ServerBoostBase",
	"ServerBoostTag",
	"ServerCharacter",
	"ServerItem",
	"ServerCanStartCombat",
	"ServerDelayDeathCause",
	"ServerPassiveBase",
	"ServerPassivePersistentData",
	"ServerPickpocket",
	"ServerShapeshiftStates",
	"ShapeshiftHealthReservation",
	"SpellAiConditions",
	"SpellBook",
	"SpellBookCooldowns",
	"SpellBookPrepares",
	"SpellCastCanBeTargeted",
	"SpellContainer",
	"Stats",
	"StatusContainer",
	"StatusImmunities",
	"Steering",
	"SurfacePathInfluences",
	"Transform",
	"Tag",
	"Uuid",
	"Visual",
	"WeaponSet"
}


EntityProxy:RegisterResourceProxy("Entity", EntityHandleProxy)
EntityProxy:RegisterResourceProxy("ItemEntity", EntityHandleProxy)
EntityProxy:RegisterResourceProxy("Owner", EntityHandleProxy)
EntityProxy:RegisterResourceProxy("Item", EntityHandleProxy)

---@param entity EntityHandle
function EntityHandleProxy:RenderDisplayWindow(entity, parent)
	if entity then
		Channels.GetEntityDump:RequestToServer({
			entity = entity.Uuid.EntityUuid,
			fields = self.fieldsToParse
		}, function(data)
			EntityProxy.entityId = entity.Uuid.EntityUuid

			---@type EntityHandle
			local entity = Ext.Entity.Get(EntityProxy.entityId)
			local components = entity:GetAllComponents()

			for _, key in TableUtils:OrderedPairs(self.fieldsToParse, nil, function(key, value)
				return data[value] == nil and components[value] ~= nil
			end) do
				data[key] = components[key]
			end

			data = CustomEntitySerializer:recursiveSerialization(data, nil, { Ext.Entity.HandleToUuid(entity) })

			local displayTable = Styler:TwoColumnTable(parent, EntityProxy.entityId)
			for key, value in TableUtils:OrderedPairs(data) do
				local row = displayTable:AddRow()
				row:AddCell():AddText(key)
				local valueCell = row:AddCell()
				EntityManager:RenderDisplayableValue(valueCell, value, key)
				if #valueCell.Children == 0 then
					row:Destroy()
				end
			end
		end)
	end
end

---@param entityId string
function EntityHandleProxy:RenderDisplayableValue(parent, entityId, resourceType)
	-- Stopping recursion
	if type(entityId) == "table" then
		EntityManager:RenderDisplayableValue(parent, entityId)
	else
		local entityIdSubbed = entityId:gsub("Entity: ", "")

		local entityIdSubbedForFind = Helpers:SanitizeStringForFind(entityId:sub(-36))

		---@param element ExtuiStyledRenderable
		---@return boolean, number
		local function isDeeplyNestedRecursion(element, numParents)
			numParents = numParents or 0

			local success, result, numberOfParents = pcall(function(...)
				if type(element.ParentElement.IDContext) == "string" and element.ParentElement.IDContext:find(entityIdSubbedForFind) and numParents > 1 then
					return true, numParents
				else
					return isDeeplyNestedRecursion(element.ParentElement, numParents + 1)
				end
			end)

			return success and result, (numberOfParents or numParents)
		end

		if entityIdSubbed
			and #entityIdSubbed >= 36
			and entityIdSubbed:sub(-36) ~= EntityProxy.entityId
			and not string.find(entityIdSubbed, "RECURSION")
		then
			local isNested, numberOfParents = isDeeplyNestedRecursion(parent)
			if isNested and numberOfParents > 1 then
				entityIdSubbed = "Entity (DEEP RECURSION): " .. entityIdSubbed
				Styler:SelectableText(parent, entityIdSubbed, entityIdSubbed)
			else
				Logger:BasicDebug("Requesting data for entity %s under resourceType %s - current entity id stored in proxy is %s",
					entityIdSubbed,
					resourceType,
					EntityProxy.entityId)

				local parentAlive = pcall(function(...)
					return parent.Handle
				end)

				if not parentAlive then
					Logger:BasicWarning("Skipping getting entity info for %s as somehow the parent element was destroyed", entityIdSubbed)
					return
				end

				Channels.GetEntityDump:RequestToServer({
					entity = entityIdSubbed,
					fields = self.fieldsToParse
				}, function(data)
					EntityProxy.entityId = data.Uuid or entityId

					---@type EntityHandle
					local entity = Ext.Entity.Get(EntityProxy.entityId)
					local components = entity:GetAllComponents()

					for _, key in TableUtils:OrderedPairs(self.fieldsToParse, nil, function(key, value)
						return data[value] == nil and components[value] ~= nil
					end) do
						data[key] = components[key]
					end

					data = CustomEntitySerializer:recursiveSerialization(data, nil, { Ext.Entity.HandleToUuid(entity) })

					local success, error = xpcall(function(...)
						local parent = parent:AddCollapsingHeader(Ext.Loca.GetTranslatedString(data.DisplayName.Name.Handle.Handle))
						parent.IDContext = EntityProxy.entityId
						local displayTable = Styler:TwoColumnTable(parent, EntityProxy.entityId)
						for key, value in TableUtils:OrderedPairs(data) do
							local row = displayTable:AddRow()
							row:AddCell():AddText(key)
							local valueCell = row:AddCell()
							EntityManager:RenderDisplayableValue(valueCell, value, key)
							if #valueCell.Children == 0 then
								row:Destroy()
							end
						end
					end, debug.traceback)

					if not success then
						Logger:BasicWarning("Couldn't create entity entry for %s due to %s", EntityProxy.entityId, error)
					end
				end)
			end
		else
			Styler:SelectableText(parent, entityIdSubbed, entityIdSubbed)
		end
	end
end
