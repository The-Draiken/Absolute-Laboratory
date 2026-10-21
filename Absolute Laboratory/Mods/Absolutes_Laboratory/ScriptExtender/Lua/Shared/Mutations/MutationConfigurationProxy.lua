Ext.Require("Shared/Mutations/External/MutationModProxy.lua")

local config = ConfigurationStructure.config

if Ext.IsServer() then
	Channels.UpdateConfiguration:SetHandler(function(payload, user)
		ConfigurationStructure:InitializeConfig()
	end)
end

---@param target string
---@return metatable
local buildMeta = function(target)
	return {
		__index = function(t, k)
			return config.mutations[target][k] or MutationModProxy.ModProxy[target][k]
		end,
		__newindex = function(t, k, v)
			config.mutations[target][k] = v
		end,
		__pairs = function(t)
			local combined = {}

			for id, profile in TableUtils:CombinedPairs(config.mutations[target], MutationModProxy.ModProxy[target]) do
				combined[id] = profile
			end

			return pairs(combined)
		end
	}
end

---@type MutationsConfig
---@diagnostic disable-next-line: missing-fields
MutationConfigurationProxy = {
	profiles = setmetatable({}, buildMeta("profiles")),
	folders = setmetatable({}, buildMeta("folders")),
	prepPhaseMarkers = setmetatable({}, {
		__index = function(t, k)
			return config.mutations.prepPhaseMarkers[k] or MutationModProxy.ModProxy.prepPhaseMarkers[k]
		end,
		__pairs = function(t)
			---@type {[Guid]: PrepMarkerCategory}
			local markerCategories = TableUtils:DeeplyCopyTable(config.mutations.prepPhaseMarkers)

			for _, modCache in pairs(MutationModProxy.ModProxy.prepPhaseMarkers) do
				---@cast modCache +LocalModCache

				if modCache.prepPhaseMarkers and next(modCache.prepPhaseMarkers) then
					for markerId, markerObject in pairs(modCache.prepPhaseMarkers) do
						markerCategories[markerId] = markerObject
					end
				end
			end

			return TableUtils:OrderedPairs(markerCategories, function(key, value)
				return (value.modId or "_") .. value.name
			end)
		end
	}),
	lists = {
		spellLists = setmetatable({}, {
			__index = function(t, k)
				return config.mutations.lists.spellLists[k] or MutationModProxy.ModProxy.lists.spellLists[k]
			end,
			__pairs = function(t)
				---@type {[Guid]: CustomList}
				local spellLists = TableUtils:DeeplyCopyTable(config.mutations.lists.spellLists._real or config.mutations.lists.spellLists)

				for _, modCache in pairs(MutationModProxy.ModProxy.lists.spellLists) do
					---@cast modCache +LocalModCache

					if modCache.lists and modCache.lists.spellLists and next(modCache.lists.spellLists) then
						for spellListId in pairs(modCache.lists.spellLists) do
							spellLists[spellListId] = MutationModProxy.ModProxy.lists.spellLists[spellListId]
						end
					end
				end

				return TableUtils:OrderedPairs(spellLists, function(key, value)
					return (value.modId or "_") .. value.name
				end)
			end
		}),
		passiveLists = setmetatable({}, {
			__index = function(t, k)
				return config.mutations.lists.passiveLists[k] or MutationModProxy.ModProxy.lists.passiveLists[k]
			end,
			__pairs = function(t)
				---@type {[Guid]: CustomList}
				local passiveLists = TableUtils:DeeplyCopyTable(config.mutations.lists.passiveLists._real or config.mutations.lists.passiveLists)

				for _, modCache in pairs(MutationModProxy.ModProxy.lists.passiveLists) do
					---@cast modCache +LocalModCache

					if modCache.lists and modCache.lists.passiveLists and next(modCache.lists.passiveLists) then
						for passiveListId in pairs(modCache.lists.passiveLists) do
							passiveLists[passiveListId] = MutationModProxy.ModProxy.lists.passiveLists[passiveListId]
						end
					end
				end

				return TableUtils:OrderedPairs(passiveLists, function(key, value)
					return (value.modId or "_") .. value.name
				end)
			end
		}),
		statusLists = setmetatable({}, {
			__index = function(t, k)
				return config.mutations.lists.statusLists[k] or MutationModProxy.ModProxy.lists.statusLists[k]
			end,
			__pairs = function(t)
				---@type {[Guid]: CustomList}
				local statusLists = TableUtils:DeeplyCopyTable(config.mutations.lists.statusLists._real or config.mutations.lists.statusLists)

				for _, modCache in pairs(MutationModProxy.ModProxy.lists.statusLists) do
					---@cast modCache +LocalModCache

					if modCache.lists and modCache.lists.statusLists and next(modCache.lists.statusLists) then
						for statusListId in pairs(modCache.lists.statusLists) do
							statusLists[statusListId] = MutationModProxy.ModProxy.lists.statusLists[statusListId]
						end
					end
				end

				return TableUtils:OrderedPairs(statusLists, function(key, value)
					return (value.modId or "_") .. value.name
				end)
			end
		}),
		blacklists = setmetatable({}, {
			__index = function(t, k)
				return config.mutations.lists.blacklists[k] or MutationModProxy.ModProxy.lists.blacklists[k]
			end
		}),
		entryReplacerDictionary = setmetatable({}, {
			__index = function(t, k)
				return config.mutations.lists.entryReplacerDictionary[k] or MutationModProxy.ModProxy.lists.entryReplacerDictionary[k]
			end
		}),
	}
}
