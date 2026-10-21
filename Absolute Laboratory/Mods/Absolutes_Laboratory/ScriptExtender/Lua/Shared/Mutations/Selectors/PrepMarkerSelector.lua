---@class PrepMarkerSelector : SelectorInterface
PrepMarkerSelector = SelectorInterface:new("Prep Marker")

---@class PrepMarkerSelector : Selector
---@field criteriaValue Guid[]

---@param existingSelector PrepMarkerSelector
function PrepMarkerSelector:renderSelector(parent, existingSelector)
	parent:AddText(("!! Dry Running this selector will use the %ss in the Active Profile !!"):format(PrepPhaseMarkerMutator.name))

	existingSelector.criteriaValue = existingSelector.criteriaValue or {}

	local prepPhaseCategories = MutationConfigurationProxy.prepPhaseMarkers

	local markerTable = parent:AddTable("markerTable", 3)
	local row = markerTable:AddRow()

	for categoryId, prepPhaseCategory in pairs(prepPhaseCategories, function(key, value)
		return value.name
	end) do
		local box = row:AddCell():AddCheckbox(prepPhaseCategory.name, TableUtils:IndexOf(existingSelector.criteriaValue, categoryId) ~= nil)

		box.OnChange = function()
			local index = TableUtils:IndexOf(existingSelector.criteriaValue, categoryId)

			if index then
				existingSelector.criteriaValue[index] = nil
				TableUtils:ReindexNumericTable(existingSelector.criteriaValue)
			else
				table.insert(existingSelector.criteriaValue, categoryId)
			end
		end

		if prepPhaseCategory.description and prepPhaseCategory.description ~= "" then
			box:Tooltip():AddText("\t " .. prepPhaseCategory.description)
		end
	end
end

---@param selector PrepMarkerSelector
function PrepMarkerSelector:handleDependencies(export, selector, removeMissingDependencies)
	for i, markerId in ipairs(selector.criteriaValue) do
		local marker = MutationConfigurationProxy.prepPhaseMarkers[markerId]
		if not marker then
			selector.criteriaValue[i] = nil
		elseif not removeMissingDependencies then
			if marker.modId then
				selector.modDependencies = selector.modDependencies or {}
				if not selector.modDependencies[marker.modId] then
					local name, author, version = Helpers:BuildModFields(marker.modId)
					if author == "Larian" then
						goto continue
					end
					selector.modDependencies[marker.modId] = {
						modName = name,
						modAuthor = author,
						modVersion = version,
						modId = marker.modId,
						packagedItems = {}
					}
				end
				selector.modDependencies[marker.modId].packagedItems[markerId] = marker.name
			else
				export.prepPhaseMarkers[markerId] = TableUtils:DeeplyCopyTable(marker._real or marker)
			end
		end
		::continue::
	end
	TableUtils:ReindexNumericTable(selector.criteriaValue)
end

---@type {[Guid]: {[Guid]: SelectorPredicate}}
local cachedSelectors = nil
---@type {[string]: string[]}
local entityCache = nil

---@param selector PrepMarkerSelector
---@return fun(entity: (EntityHandle|EntityRecord), entityVar: MutatorEntityVar): boolean
function PrepMarkerSelector:predicate(selector)
	local activeProfile = MutationConfigurationProxy.profiles[Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile]

	return function(entity)
		Ext.Utils.ProfileBegin("PrepMarkerSelector")
		cachedSelectors = cachedSelectors or {}
		entityCache = entityCache or {}

		local id = entity.Uuid and entity.Uuid.EntityUuid or entity.Id

		if not entityCache[id] then
			Ext.Utils.ProfileBegin("Hydrating categories for " .. id)
			local appliedCategories = {}

			for i, mProfileRule in TableUtils:OrderedPairs(activeProfile.prepPhaseMutations) do
				local mutation = MutationConfigurationProxy.folders[mProfileRule.mutationFolderId].mutations[mProfileRule.mutationId]
				if not mutation then
					goto next
				end

				mutation = mutation._real or mutation

				---@type PrepMarkerCategory[]
				local assignableMarkers = mutation.mutators[1].values or {}
				if not next(assignableMarkers) then
					goto next
				end

				if not cachedSelectors[mProfileRule.mutationFolderId] then
					cachedSelectors[mProfileRule.mutationFolderId] = {}
				end
				if not cachedSelectors[mProfileRule.mutationFolderId][mProfileRule.mutationId] then
					cachedSelectors[mProfileRule.mutationFolderId][mProfileRule.mutationId] = SelectorInterface:createComposedPredicate(mutation.selectors)
				end

				if cachedSelectors[mProfileRule.mutationFolderId][mProfileRule.mutationId]:Test(entity) then
					for _, marker in pairs(assignableMarkers) do
						table.insert(appliedCategories, marker)
					end
				end

				::next::
			end

			entityCache[id] = appliedCategories
			Ext.Utils.ProfileEnd("Hydrating categories for " .. id)
		end

		Ext.Utils.ProfileEnd("PrepMarkerSelector")

		return TableUtils:HasOneMatchingElement(selector.criteriaValue, entityCache[id])
	end
end

function PrepMarkerSelector:cleanup()
	cachedSelectors = nil
	entityCache = nil
end

function PrepMarkerSelector:generateDocs()
end
