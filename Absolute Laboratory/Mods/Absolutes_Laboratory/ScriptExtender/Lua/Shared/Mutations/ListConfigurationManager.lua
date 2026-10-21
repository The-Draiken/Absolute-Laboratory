---@class ProgressionLevel
local progressionLevel = {
	---@type Guid
	id = nil,
	---@type Guid
	modId = nil,
	---@type number
	level = nil,
	---@type ProgressionType
	type = nil,
	---@class ProgressionSpells
	spellLists = {
		---@type string[]
		AddSpells = {},
		---@type string[]
		SelectSpells = {}
	},
	---@class ProgressionPassives
	passiveLists = {
		---@type string[]
		PassivePrototypesAdded = {},
		---@type string[]
		PassivePrototypesRemoved = {},
		---@type string[]
		SelectPassives = {}
	}
}

---@class ProgressionTable
---@field progressionLevels ProgressionLevel[]
---@field name string
---@field tableId tableUUID

---@alias tableUUID Guid

ListConfigurationManager = {
	progressionHierarchy = {},
	---@type {[tableUUID] : ProgressionTable}
	progressionIndex = setmetatable({}, {
		__mode = Ext.IsClient() and "v" or nil,
		__index = function(t, k)
			ListConfigurationManager:buildProgressionIndex(k)
			return rawget(t, k)
		end,
		__call = function(t, ...)
			for key in pairs(ListConfigurationManager.progressionIndex) do
				t[key] = nil
			end
			ListConfigurationManager.progressionHierarchy = {}
		end
	}),
	---@type Guid[]
	progressionTables = {},
	---@enum ProgressionNodes
	progressionNodes = {
		["AddSpells"] = 1,
		["PassivePrototypesAdded"] = 2,
		["PassivePrototypesRemoved"] = 3,
		["PassivesAdded"] = 4,
		["PassivesRemoved"] = 5,
		["SelectPassives"] = 6,
		["SelectSpells"] = 7,
		[1] = "AddSpells",
		[2] = "PassivePrototypesAdded",
		[3] = "PassivePrototypesRemoved",
		[4] = "PassivesAdded",
		[5] = "PassivesRemoved",
		[6] = "SelectPassives",
		[7] = "SelectSpells",
	},
	settings = ConfigurationStructure.config.mutations.settings.customLists,
	listsConfig = ConfigurationStructure.config.mutations.lists
}

local didAllProgs = false
---@param tableUUID Guid?
function ListConfigurationManager:buildProgressionIndex(tableUUID)
	if tableUUID or not didAllProgs then
		if not tableUUID then
			didAllProgs = true
		end
		Ext.Utils.ProfileBegin(("Indexing Progression Index for %s"):format(tableUUID or "All Progressions"))

		if not next(self.progressionHierarchy) and tableUUID then
			Ext.Utils.ProfileBegin("Indexing Progression Hierarchy")
			for _, progressionId in pairs(Ext.StaticData.GetAll("Progression")) do
				---@type ResourceProgression
				local progression = Ext.StaticData.Get(progressionId, "Progression")

				self.progressionHierarchy[progression.TableUUID] = self.progressionHierarchy[progression.TableUUID] or {}

				table.insert(self.progressionHierarchy[progression.TableUUID], progressionId)
			end
			Ext.Utils.ProfileEnd("Indexing Progression Hierarchy")
		end

		local progressionSources = Ext.IsClient() and Ext.StaticData.GetSources("Progression") or nil
		for _, progressionId in pairs(not tableUUID and Ext.StaticData.GetAll("Progression") or self.progressionHierarchy[tableUUID] or {}) do
			---@type ResourceProgression
			local progression = Ext.StaticData.Get(progressionId, "Progression")

			if tableUUID and progression.TableUUID ~= tableUUID then
				goto continue
			end

			if not rawget(self.progressionIndex, progression.TableUUID) then
				local name = progression.Name
				if TableUtils:IndexOf(self.progressionIndex, function(value)
						return value.name == name
					end) then
					name = name .. (" (%s)"):format(progressionId:sub(#progressionId - 5))
				end

				self.progressionIndex[progression.TableUUID] = {
					name = name,
					tableId = progression.TableUUID,
					progressionLevels = {}
				}
			elseif TableUtils:IndexOf(self.progressionIndex[progression.TableUUID].progressionLevels, function(value)
					return value.id == progressionId
				end)
			then
				goto continue
			end

			---@type ProgressionLevel
			local progressionIndex = {
				id = progressionId,
				level = progression.Level,
				type = tostring(progression.ProgressionType)
			}

			local nodesToIterate = {}
			for node, nodeEntry in pairs(progression) do
				---@cast node string
				if self.progressionNodes[node]
					and ((type(nodeEntry) == "string" and nodeEntry ~= "")
						or (type(nodeEntry) == "userdata" and next(Ext.Types.Serialize(nodeEntry))))
				then
					local entries = {}
					if type(nodeEntry) == "table" or type(nodeEntry) == "userdata" then
						for _, entry in ipairs(nodeEntry) do
							table.insert(entries, entry)
						end
					else
						local splitTable = {}
						for _, val in string.gmatch(progression[node], "([^;]+)") do
							table.insert(splitTable, val)
						end
						if next(splitTable) then
							for _, entry in ipairs(splitTable) do
								table.insert(nodesToIterate[node], entry)
							end
						end
					end

					for _, entry in ipairs(entries) do
						if node:find("Spells") then
							---@cast entry ResourceProgressionSpell|ResourceProgressionAddedSpell

							---@type ResourceSpellList
							local progSpellList = Ext.StaticData.Get(entry.SpellUUID, "SpellList")

							if progSpellList then
								progressionIndex["spellLists"] = progressionIndex["spellLists"] or {}
								progressionIndex["spellLists"][node] = progressionIndex["spellLists"][node] or {}
								for _, spellName in pairs(progSpellList.Spells) do
									table.insert(progressionIndex["spellLists"][node], spellName)
								end
							else
								Logger:BasicWarning("SpellUUID %s from Progression %s (%s, Level %d) does not exist as a spell list",
									entry.SpellUUID,
									progressionId,
									progression.Name,
									progression.Level)
							end
						elseif node:find("Passive") then
							---@cast entry ResourceProgressionPassive|StatsPassivePrototype|string
							if type(entry) == "string" then
								progressionIndex["passiveLists"] = progressionIndex["passiveLists"] or {}
								progressionIndex["passiveLists"][node] = progressionIndex["passiveLists"][node] or {}
								table.insert(progressionIndex["passiveLists"][node], entry)
							elseif Ext.Types.GetObjectType(entry) == "stats::PassivePrototype" then
								progressionIndex["passiveLists"] = progressionIndex["passiveLists"] or {}
								progressionIndex["passiveLists"][node] = progressionIndex["passiveLists"][node] or {}
								table.insert(progressionIndex["passiveLists"][node], entry.Name)
							else
								---@type ResourcePassiveList
								local passiveList = Ext.StaticData.Get(entry.UUID, "PassiveList")

								if passiveList then
									progressionIndex["passiveLists"] = progressionIndex["passiveLists"] or {}
									progressionIndex["passiveLists"][node] = progressionIndex["passiveLists"][node] or {}
									for _, passiveName in pairs(passiveList.Passives) do
										table.insert(progressionIndex["passiveLists"][node], passiveName)
									end
								else
									Logger:BasicWarning("Passive UUID %s from Progression %s (%s, Level %d) does not exist as a spell list",
										entry.UUID,
										progressionId,
										progression.Name,
										progression.Level)
								end
							end
						end
					end
				end
			end

			if (progressionIndex["passiveLists"] or progressionIndex["spellLists"]) then
				if Ext.IsClient() then
					progressionIndex.modId = TableUtils:IndexOf(progressionSources, function(value)
						return TableUtils:IndexOf(value, progressionId) ~= nil
					end)
				end

				table.insert(self.progressionIndex[progression.TableUUID].progressionLevels, progressionIndex)
			end

			if not TableUtils:IndexOf(self.progressionTables, progression.TableUUID) then
				table.insert(self.progressionTables, progression.TableUUID)
			end

			::continue::
		end
		Ext.Utils.ProfileEnd(("Indexing Progression Index for %s"):format(tableUUID or "All Progressions"))
	end
end

---@param progressionTableId Guid
---@param level number
---@param entryName string
---@param configKey "spellLists"|"passiveLists"
---@return boolean
function ListConfigurationManager:hasSameEntryInLowerLevel(progressionTableId, level, entryName, configKey)
	if level <= 1 then
		return false
	end

	local profileName = ("Checking if %s offers the same entry in a level lower than %d"):format(self.progressionIndex[progressionTableId].name, level)
	Ext.Utils.ProfileBegin(profileName)
	for _, progEntry in pairs(self.progressionIndex[progressionTableId].progressionLevels) do
		if progEntry.level < level and progEntry[configKey] then
			if TableUtils:IndexOf(progEntry[configKey], function(value)
					return TableUtils:IndexOf(value, entryName) ~= nil
				end)
			then
				Ext.Utils.ProfileEnd(profileName)
				return true
			end
		end
	end
	Ext.Utils.ProfileEnd(profileName)

	return false
end

---@param export MutationsConfig
---@param mutator Mutator
---@param lists Guid[]
---@param removeMissingDependencies boolean?
function ListConfigurationManager:HandleDependences(export, mutator, lists, removeMissingDependencies, configKey)
	local progressionSources = Ext.StaticData.GetSources("Progression")


	---@param statName string
	---@param container table?
	---@return boolean?
	local function buildStatDependency(statName, container)
		---@type (SpellData|PassiveData|StatusData)?
		local stat = Ext.Stats.Get(statName)
		if stat then
			if not removeMissingDependencies then
				container = container or mutator
				container.modDependencies = container.modDependencies or {}
				if not container.modDependencies[stat.OriginalModId] then
					local name, author, version = Helpers:BuildModFields(stat.OriginalModId)
					if author == "Larian" then
						return true
					end

					container.modDependencies[stat.OriginalModId] = {
						modName = name,
						modAuthor = author,
						modVersion = version,
						modId = stat.OriginalModId,
						packagedItems = {}
					}
				end
				local name = Ext.Loca.GetTranslatedString(stat.DisplayName, statName)
				name = name == "" and statName or name
				container.modDependencies[stat.OriginalModId].packagedItems[statName] = name
			end
			return true
		else
			return false
		end
	end

	local replaceMap = removeMissingDependencies == true
		and export.lists.entryReplacerDictionary
		or TableUtils:DeeplyCopyTable(ConfigurationStructure.config.mutations.lists.entryReplacerDictionary._real)

	if replaceMap[configKey] and next(replaceMap[configKey]) then
		if not removeMissingDependencies then
			export.lists.entryReplacerDictionary = export.lists.entryReplacerDictionary or {}
			replaceMap.modDependencies = export.lists.entryReplacerDictionary.modDependencies
		end
		for statName, entriesToReplace in pairs(replaceMap[configKey]) do
			for i, statBeingReplaced in ipairs(entriesToReplace) do
				if not buildStatDependency(statBeingReplaced, replaceMap) then
					replaceMap[configKey][statName][i] = nil
				end
			end

			TableUtils:ReindexNumericTable(replaceMap[configKey][statName])
		end
		if not removeMissingDependencies then
			export.lists.entryReplacerDictionary.modDependencies = replaceMap.modDependencies
			export.lists.entryReplacerDictionary[configKey] = replaceMap[configKey]
		end
	end

	if not removeMissingDependencies then
		export.lists.blacklists = export.lists.blacklists or {}

		export.lists.blacklists[configKey] = TableUtils:DeeplyCopyTable(ConfigurationStructure.config.mutations.lists.blacklists[configKey])
	end

	for _, listId in pairs(lists) do
		---@type CustomList
		local list = MutationConfigurationProxy.lists[configKey][listId]
		if list then
			local listModId = list.modId
			if not listModId then
				--- @type CustomList
				local listDef = removeMissingDependencies == true
					and export.lists[configKey][listId]
					or TableUtils:DeeplyCopyTable(ConfigurationStructure.config.mutations.lists[configKey][listId]._real)

				if listDef.linkedProgressionTableIds then
					for i, progressionTableId in pairs(listDef.linkedProgressionTableIds) do
						local progressionTable = self.progressionIndex[progressionTableId]
						if progressionTable then
							for _, progressionLevel in pairs(progressionTable.progressionLevels) do
								local progressionId = progressionLevel.id
								local progressionSource = TableUtils:IndexOf(progressionSources, function(value)
									return TableUtils:IndexOf(value, progressionId) ~= nil
								end)
								if progressionSource then
									listDef.modDependencies = listDef.modDependencies or {}
									if not listDef.modDependencies[progressionSource] then
										local name, author, version = Helpers:BuildModFields(progressionSource)
										if author == "Larian" then
											goto continue
										end
										listDef.modDependencies[progressionSource] = {
											modName = name,
											modAuthor = author,
											modVersion = version,
											modId = progressionSource,
											packagedItems = {}
										}
									end
									listDef.modDependencies[progressionSource].packagedItems[progressionId] = progressionLevel.name
								end
								::continue::
							end
						elseif removeMissingDependencies then
							listDef.linkedProgressionTableIds[i] = nil
						end
					end
				end

				if listDef.linkedLists and next(listDef.linkedLists._real or listDef.linkedLists) then
					self:HandleDependences(export, mutator, listDef.linkedLists, removeMissingDependencies, configKey)
				end

				if listDef.levels then
					for level, levelSubList in pairs(listDef.levels) do
						if levelSubList.linkedProgressions then
							for progressionTableId, sublists in pairs(levelSubList.linkedProgressions) do
								if self.progressionIndex[progressionTableId] then
									for i, entry in pairs(sublists) do
										if not buildStatDependency(entry.name, listDef) then
											entry[i] = nil
										end
									end
									if not next(sublists._real or sublists) then
										sublists.delete = true
										levelSubList.linkedProgressions[progressionTableId] = nil
										goto nextProgression
									end

									for _, progressionLevel in pairs(self.progressionIndex[progressionTableId].progressionLevels) do
										if progressionLevel.level == level then
											local progressionId = progressionLevel.id

											---@type ResourceProgression
											local progression = Ext.StaticData.Get(progressionId, "Progression")
											if not progression then
												levelSubList.linkedProgressions[progressionTableId] = nil
											elseif not removeMissingDependencies then
												local progressionSource = TableUtils:IndexOf(progressionSources, function(value)
													return TableUtils:IndexOf(value, progressionId) ~= nil
												end)
												if progressionSource then
													listDef.modDependencies = listDef.modDependencies or {}
													if not listDef.modDependencies[progressionSource] then
														local name, author, version = Helpers:BuildModFields(progressionSource)
														if author == "Larian" then
															goto continue
														end
														listDef.modDependencies[progressionSource] = {
															modName = name,
															modAuthor = author,
															modVersion = version,
															modId = progressionSource,
															packagedItems = {}
														}
													end
													listDef.modDependencies[progressionSource].packagedItems[progressionId] = progression.Name
												end
												::continue::
											end
										end
									end
								end
								::nextProgression::
							end
						end

						if levelSubList.manuallySelectedEntries then
							for e, entry in pairs(levelSubList.manuallySelectedEntries) do
								if not buildStatDependency(entry.name, listDef) then
									levelSubList[e] = nil
								end
							end
							TableUtils:ReindexNumericTable(levelSubList.manuallySelectedEntries)
							if not next(levelSubList.manuallySelectedEntries._real or levelSubList.manuallySelectedEntries) then
								levelSubList.manuallySelectedEntries.delete = true
								levelSubList.manuallySelectedEntries = nil
							end
						end
					end
				end

				listDef.defaultPool = ConfigurationStructure.config.mutations.settings.customLists.defaultPool[configKey]
				export.lists[configKey] = export.lists[configKey] or {}
				if not export.lists[configKey][listId] then
					export.lists[configKey][listId] = listDef
				end
			else
				local name, author, version = Helpers:BuildModFields(listModId)
				mutator.modDependencies = mutator.modDependencies or {}
				mutator.modDependencies[listModId] = {
					modAuthor = author,
					modName = name,
					modVersion = version,
					modId = listModId,
					packagedItems = nil
				}
			end
		end
	end
end

local didGlobal = false
---@param configBase MutationsConfig?
function ListConfigurationManager:maintainLists(configBase)
	Ext.Utils.ProfileBegin("Maintaining Lists")
	configBase = configBase or ConfigurationStructure.config.mutations

	local translationTable = {
		["startOfCombatOnly"] = "combatStart",
		["onDeathOnly"] = "death",
		["onLoadOnly"] = "levelLoad"
	}

	if not didGlobal then
		local globalSettings = ConfigurationStructure.config.mutations.settings.customLists

		for key, default in pairs(globalSettings.defaultPool) do
			if translationTable[default] then
				globalSettings.defaultPool[key] = "guaranteed"
			end
		end

		for key, colour in pairs(globalSettings.subListColours) do
			if translationTable[key] then
				globalSettings.subListColours[translationTable[key]] = TableUtils:DeeplyCopyTable(colour)
				globalSettings.subListColours[key].delete = true
			end
		end
		didGlobal = true
	end

	---@param entry string
	---@param originalPool EntryCastOnTypes|EntryTypes
	---@param defaultPool EntryTypes
	---@return SubListEntry
	local function convertEntriesToClass(entry, originalPool, defaultPool)
		originalPool = originalPool:lower()
		return {
			name = entry,
			type = (originalPool == "randomized" or originalPool == "guaranteed" or originalPool == "blacklisted") and originalPool or defaultPool,
			weight = 1.0,
			castOn = translationTable[originalPool] or nil
		} --[[@as SubListEntry]]
	end

	---@class CustomSubList
	local customSubList = {
		---@type string[]?
		guaranteed = nil,
		---@type string[]?
		randomized = nil,
		---@type string[]?
		startOfCombatOnly = nil,
		---@type string[]?
		onLoadOnly = nil,
		---@type string[]?
		blackListed = nil,
		---@type string[]?
		onDeathOnly = nil
	}

	TableUtils:ConvertStringifiedNumberIndexes(configBase)
	for _, list in TableUtils:CombinedPairs(configBase.lists.passiveLists,
		configBase.lists.spellLists,
		configBase.lists.statusLists)
	do
		if list.defaultPool and (list.defaultPool ~= "guaranteed" and list.defaultPool ~= "randomized" and list.defaultPool ~= "blacklisted") then
			list.defaultPool = "guaranteed"
		end

		if list.levels then
			Ext.Utils.ProfileBegin("List Levels")
			for level, levelList in TableUtils:OrderedPairs(list.levels) do
				if levelList.linkedProgressions then
					for k, subList in TableUtils:OrderedPairs(levelList.linkedProgressions) do
						-- 1.10.0 conversion
						local nextKey, nextValue = next(subList._real or subList)
						if type(nextKey) == "string" or (type(nextValue) == "table" and type(next(nextValue)) == "number") then
							local copy = TableUtils:DeeplyCopyTable(subList)
							subList.delete = true
							levelList.linkedProgressions[k] = {}
							for pool, entry in TableUtils:OrderedPairs(copy) do
								if type(entry) == "string" then
									table.insert(levelList.linkedProgressions[k],
										convertEntriesToClass(entry, type(pool) == "string" and pool or (list.defaultPool or "randomized"), list.defaultPool or "randomized"))
								elseif type(entry) == "table" then
									for _, entry in TableUtils:OrderedPairs(entry) do
										table.insert(levelList.linkedProgressions[k],
											convertEntriesToClass(entry, type(pool) == "string" and pool or (list.defaultPool or "randomized"), list.defaultPool or "randomized"))
									end
								end
							end
						end
					end
				end

				if levelList.manuallySelectedEntries then
					local nextKey, nextValue = next(levelList.manuallySelectedEntries._real or levelList.manuallySelectedEntries)
					if type(nextKey) == "string" or (type(nextValue) == "table" and type(next(nextValue)) == "number") then
						local copy = TableUtils:DeeplyCopyTable(levelList.manuallySelectedEntries)
						levelList.manuallySelectedEntries.delete = true
						levelList.manuallySelectedEntries = {}
						for pool, entry in TableUtils:OrderedPairs(copy) do
							if type(entry) == "string" then
								table.insert(levelList.manuallySelectedEntries,
									convertEntriesToClass(entry, type(pool) == "string" and pool or (list.defaultPool or "randomized"), list.defaultPool or "randomized"))
							elseif type(entry) == "table" then
								for _, entry in TableUtils:OrderedPairs(entry) do
									table.insert(levelList.manuallySelectedEntries,
										convertEntriesToClass(entry, type(pool) == "string" and pool or (list.defaultPool or "randomized"), list.defaultPool or "randomized"))
								end
							end
						end
					end
				end
			end
			Ext.Utils.ProfileEnd("List Levels")
		end
	end

	Ext.Utils.ProfileBegin("Folders")
	for _, folder in TableUtils:OrderedPairs(configBase.folders) do
		for _, mutation in TableUtils:OrderedPairs(folder.mutations) do
			for _, mutator in TableUtils:OrderedPairs(mutation.mutators) do
				if mutator.targetProperty == SpellListMutator.name then
					---@cast mutator SpellListMutator
					for _, group in TableUtils:OrderedPairs(mutator.values) do
						if group.leveledSpellPool then
							for _, pool in TableUtils:OrderedPairs(group.leveledSpellPool) do
								if pool.spells and type(next(pool.spells)) == "string" then
									---@type CustomSubList
									local copy = TableUtils:DeeplyCopyTable(pool.spells --[[@as CustomSubList]])

									pool.spells.delete = true
									pool.spells = {}

									for sublistType, spells in TableUtils:OrderedPairs(copy) do
										for _, spell in TableUtils:OrderedPairs(spells) do
											if type(spell) == "string" then
												table.insert(pool.spells, {
													name = spell,
													type = translationTable[sublistType] or sublistType:lower(),
													weight = 1
												} --[[@as SubListEntry]])
											end
										end
									end
								end
							end
						end
					end
				elseif mutator.targetProperty == PassiveListMutator.name then
					---@cast mutator PassiveListMutator
					if mutator.values.passives and type(next(mutator.values.passives)) == "string" then
						---@type CustomSubList
						local copy = TableUtils:DeeplyCopyTable(mutator.values.passives --[[@as CustomSubList]])
						mutator.values.passives.delete = true
						mutator.values.passives = {}
						for sublistType, passives in TableUtils:OrderedPairs(copy) do
							if type(passives) == "table" then
								for _, passive in TableUtils:OrderedPairs(passives) do
									table.insert(mutator.values.passives, {
										name = passive,
										type = translationTable[sublistType] or sublistType:lower(),
										weight = 1
									} --[[@as CustomSubList]])
								end
							end
						end
					end
				elseif mutator.targetProperty == StatusListMutator.name then
					---@cast mutator StatusListMutator
					if mutator.values.statuses and type(next(mutator.values.statuses)) == "string" then
						---@type CustomSubList
						local copy = TableUtils:DeeplyCopyTable(mutator.values.statuses --[[@as CustomSubList]])
						mutator.values.statuses.delete = true
						mutator.values.statuses = {}
						for sublistType, statuses in TableUtils:OrderedPairs(copy) do
							if type(statuses) == "table" then
								for _, status in TableUtils:OrderedPairs(statuses) do
									table.insert(mutator.values.statuses, {
										name = status,
										type = translationTable[sublistType] or sublistType:lower(),
										weight = 1
									} --[[@as CustomSubList]])
								end
							end
						end
					end
				end
			end
		end
	end
	Ext.Utils.ProfileEnd("Folders")
	Ext.Utils.ProfileEnd("Maintaining Lists")
end

---@param sublist SubListEntry[]
---@param progressionTableId Guid
---@param level integer
---@return boolean? shouldDelete false if the progression needs to be deleted
function ListConfigurationManager:maintainProgressionEntries(sublist, progressionTableId, level)
	local profileString = string.format("Maintain Progression Entries (level %s - progressionTable %s)", level, progressionTableId)
	Ext.Utils.ProfileBegin(profileString)
	local progTable = self.progressionIndex[progressionTableId]
	if progTable then
		-- 1.10.0 ad infinitum - Removing any entries that don't exist in the progression for that level
		local shouldRemove = {}
		for _, levels in pairs(progTable.progressionLevels) do
			if levels.level == level then
				for _, progSublist in TableUtils:CombinedPairs(levels.passiveLists or {}, levels.spellLists or {}) do
					---@cast progSublist ProgressionSpells|ProgressionPassives
					for i, entry in TableUtils:OrderedPairs(sublist) do
						if TableUtils:IndexOf(progSublist, entry.name) then
							shouldRemove[i] = false

							if entry.type ~= "blacklisted" then
								local stat = Ext.Stats.GetCachedSpell(entry.name)

								if stat and (stat.AiFlags & Ext.Enums.AIFlags.CanNotUse) == Ext.Enums.AIFlags.CanNotUse then
									entry.type = "blacklisted"
									Logger:BasicDebug("Updated spell %s to blacklisted due to being flagged as unusable by AI", entry.name)
								end
							end
						elseif shouldRemove[i] ~= false then
							shouldRemove[i] = true
						end
					end
				end
			end
		end
		for index, shouldRemove in pairs(shouldRemove) do
			if shouldRemove then
				Logger:BasicDebug("Removed entry %s due to not being present at level %d for progression %s", sublist[index].name, level,
					progTable.name)
				sublist[index].delete = true
				sublist[index] = nil
			end
		end
	else
		Logger:BasicDebug("Removing progression %s as it doesn't exist", progressionTableId)
		sublist.delete = true
		Ext.Utils.ProfileEnd(profileString)
		return false
	end

	Ext.Utils.ProfileEnd(profileString)
end

Ext.RegisterConsoleCommand("Lab_DumpProgressions", function(cmd, ...)
	local self = ListConfigurationManager

	self.progressionIndex()
	self:buildProgressionIndex()

	local progLog = Logger:new("ProgressionDumper.txt", false)
	progLog:ClearLogFile()
	progLog:BasicDebug("%s", self.progressionIndex)
end)
