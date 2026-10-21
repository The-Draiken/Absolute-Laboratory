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

MutationProfileManager = {
	---@type ExtuiTable
	parentTable = nil,
	---@type ExtuiChildWindow
	selectionParent = nil,
	---@type ExtuiGroup
	profileGroup = nil,
	---@type ExtuiPopup
	popup = nil
}

Ext.Require("Client/Mutations/MutationDesigner.lua")
Ext.Require("Client/Mutations/MutationProfileExecutionHub.lua")

---@type string?
local activeProfileId

if Ext.Mod.IsModLoaded("755a8a72-407f-4f0d-9a33-274ac0f0b53d") then
	Mods.BG3MCM.IMGUIAPI:InsertModMenuTab(ModuleUUID, "Mutations",
		--- @param tabHeader ExtuiTabItem
		function(tabHeader)
			MutationProfileManager:init(tabHeader)
			MutationProfileManager:BuildFolderManager()
		end)
end

---@type ExtuiButton?
local activeMutationView

---@param parent ExtuiTreeParent
function MutationProfileManager:init(parent)
	if not self.parentTable then
		local hubButton = Styler:ScaledFont(parent:AddButton("Launch Profile Execution Hub"), Styler.FontSize.Medium)
		hubButton.UserData = "keep"
		hubButton.OnClick = function()
			MutationProfileExecutionHub:launchHubWindow()
		end

		local applyButton = Styler:ScaledFont(parent:AddButton("Apply Mutations Now"), Styler.FontSize.Medium)
		applyButton.UserData = "keep"
		applyButton.SameLine = true
		applyButton:Tooltip():AddText([[
Manually (re)applies your active Mutation Profile to the level you're currently on - no need to save and reload.
Uses whichever Execution Method (Tick-Based or Instant) is set in the Profile Execution Hub, and shows the status window while it's running (unless you've turned that off there too).]])
		applyButton.OnClick = function()
			Channels.ManualApplyMutations:SendToServer(nil)
		end

		local undoButton = Styler:ScaledFont(parent:AddButton("Undo Mutations Now"), Styler.FontSize.Medium)
		undoButton.UserData = "keep"
		undoButton.SameLine = true
		undoButton:Tooltip():AddText([[
Undoes every Mutation Lab has currently applied on this level - regardless of whether a Profile is active.
This does NOT deactivate your Profile - re-entering combat, or clicking Apply Mutations Now, will simply re-mutate anything that still matches it.]])
		undoButton.OnClick = function()
			Channels.ManualUndoMutations:SendToServer(nil)
		end

		local forceCleanButton = Styler:ScaledFont(parent:AddButton("Force Clean By Folder..."), Styler.FontSize.Medium)
		forceCleanButton.UserData = "keep"
		forceCleanButton.SameLine = true
		forceCleanButton:Tooltip():AddText([[
Recovery tool for when Undo Mutations Now has nothing to undo - most commonly because Absolute's Laboratory itself was fully uninstalled while mutations were still applied, then the save was reloaded, wiping the record of what to put back.
Instead of relying on that record, this checks every character on your current level directly against everything a chosen Mutation Folder could have granted (Passives/Statuses/Spells only) and strips whatever's actually present. See the tool's own window for exactly what it can't catch.]])
		forceCleanButton.OnClick = function()
			ForceCleanWindow:Launch()
		end

		self.popup = Styler:Popup(parent)
		self.popup.UserData = "closeOnSubmit"

		self.parentTable = Styler:TwoColumnTable(parent, "mutationsMain")
		self.parentTable.Borders = false
		self.parentTable.Resizable = false
		self.parentTable.ColumnDefs[1].Width = 300 * Styler:ScaleFactor()

		local row = self.parentTable:AddRow()

		self.selectionParent = row:AddCell():AddChildWindow("selectionParent")
		self.selectionParent.NoSavedSettings = true
		self.selectionParent.DragDropType = "MutationRules"
		self.selectionParent.OnDragDrop = function(group, dropped)
			for _, modSection in pairs(self.selectionParent.Children) do
				---@cast modSection ExtuiGroup
				for _, mutationGroup in pairs(modSection.Children) do
					---@cast mutationGroup ExtuiGroup
					if mutationGroup.UserData == dropped.UserData.mutationFolderId then
						for _, mutation in pairs(mutationGroup.Children) do
							---@cast mutation ExtuiSelectable

							if mutation.UserData and mutation.UserData.mutationId == dropped.UserData.mutationId then
								mutation.CanDrag = true
								mutation:SetColor("Text", { 0.86, 0.79, 0.68, 0.78 })

								for _, mutationRule in TableUtils:OrderedPairs(ConfigurationStructure.config.mutations.profiles[activeProfileId].mutationRules) do
									if mutationRule.mutationId == dropped.UserData.mutationId and mutationRule.mutationFolderId == dropped.UserData.mutationFolderId then
										mutationRule.delete = true
										break
									end
								end

								for _, mutationRule in TableUtils:OrderedPairs(ConfigurationStructure.config.mutations.profiles[activeProfileId].prepPhaseMutations) do
									if mutationRule.mutationId == dropped.UserData.mutationId and mutationRule.mutationFolderId == dropped.UserData.mutationFolderId then
										mutationRule.delete = true
										break
									end
								end

								activeMutationView = nil
								self:BuildRuleManager()
								return
							end
						end
					end
				end
			end
		end

		local rightPanel = row:AddCell()
		local collapseExpandUserFoldersButton = rightPanel:AddButton("<<")
		collapseExpandUserFoldersButton.OnClick = function()
			Helpers:CollapseExpand(
				collapseExpandUserFoldersButton.Label == "<<",
				300 * Styler:ScaleFactor(),
				function(width)
					if width then
						self.parentTable.ColumnDefs[1].Width = width
					end
					return self.parentTable.ColumnDefs[1].Width
				end,
				self.selectionParent,
				function()
					if collapseExpandUserFoldersButton.Label == "<<" then
						collapseExpandUserFoldersButton.Label = ">>"
					else
						collapseExpandUserFoldersButton.Label = "<<"
					end
				end)
		end

		local docs = MazzleDocs:addDocButton(rightPanel)
		docs.UserData = "keep"
		docs.SameLine = true

		rightPanel:AddSeparator()
		self.profileRulesParent = Styler:TwoColumnTable(rightPanel)
		self.profileRulesParent.Borders = false
		self.profileRulesParent.Resizable = false
		self.profileRulesParent.ColumnDefs[1].Width = Styler:ScaleFactor() * 300
		self.profileRulesParent.NoSavedSettings = true

		local profileRulesRow = self.profileRulesParent:AddRow()

		self.rulesOrderGroup = profileRulesRow:AddCell()
		self.rulesOrderGroup.UserData = "keep"

		local profilerManagerWindow = self.rulesOrderGroup:AddGroup("RulesOrder")
		profilerManagerWindow.UserData = "keep"
		Styler:MiddleAlignedColumnLayout(profilerManagerWindow, function(ele)
			self.profileManagerParent = ele
		end).UserData = "keep"

		self.rulesOrderGroup = self.rulesOrderGroup:AddChildWindow("rulesOrderGroup")

		self.mutationDesigner = profileRulesRow:AddCell():AddChildWindow("MutationDesigner")
		local collapseExpandRulesOrderButton = self.mutationDesigner:AddButton("<<")
		collapseExpandRulesOrderButton.UserData = "keep"
		collapseExpandRulesOrderButton.OnClick = function()
			Helpers:CollapseExpand(
				collapseExpandRulesOrderButton.Label == "<<",
				self.profileRulesParent.UserData or (Styler:ScaleFactor() * 300),
				function(width)
					if width then
						self.profileManagerParent.Visible = true
						self.profileRulesParent.ColumnDefs[1].Width = width
					end
					return self.profileRulesParent.ColumnDefs[1].Width
				end,
				self.rulesOrderGroup,
				function()
					if collapseExpandRulesOrderButton.Label == "<<" then
						collapseExpandRulesOrderButton.Label = ">>"
						self.profileManagerParent.Visible = false
					else
						collapseExpandRulesOrderButton.Label = "<<"
					end
				end)
		end

		local shrinkRulesOrderButton = self.mutationDesigner:AddButton("<")
		shrinkRulesOrderButton.UserData = "keep"
		shrinkRulesOrderButton.SameLine = true
		shrinkRulesOrderButton:Tooltip():AddText("\t Collapses the column a bit - temporary measure until i figure out why scaling isn't working")
		shrinkRulesOrderButton.OnClick = function()
			local width = self.profileRulesParent.ColumnDefs[1].Width
			self.profileRulesParent.ColumnDefs[1].Width = width - (width * 0.2)
			self.profileRulesParent.UserData = width - (width * 0.2)
		end

		local expandRulesOrderButton = self.mutationDesigner:AddButton(">")
		expandRulesOrderButton.UserData = "keep"
		expandRulesOrderButton.SameLine = true
		expandRulesOrderButton:Tooltip():AddText("\t Expands the column a bit - temporary measure until i figure out why scaling isn't working")
		expandRulesOrderButton.OnClick = function()
			local width = self.profileRulesParent.ColumnDefs[1].Width
			self.profileRulesParent.ColumnDefs[1].Width = width + (width * 0.2)
			self.profileRulesParent.UserData = width + (width * 0.2)
		end
	end
end

local folderState = {}

function MutationProfileManager:BuildFolderManager()
	activeMutationView = nil

	Helpers:KillChildren(self.selectionParent)

	local longestText = 300

	local groups = { ["User"] = self.selectionParent:AddGroup("user") }

	local userSep = groups["User"]:AddSeparatorText("Your Mutations (?)")
	userSep:SetStyle("SeparatorTextAlign", 0.5)
	userSep:Tooltip():AddText(
		"\t Right-click on folders or mutations under any user or mod section to manage them. Drag and Drop mutations into the profile section to add them to a profile")

	for folderId, folder in TableUtils:OrderedPairs(MutationConfigurationProxy.folders, function(key, value)
		return not value.modId and ("1" .. value.name) or ("2" .. Ext.Mod.GetMod(value.modId).Info.Name .. value.name)
	end) do
		local parent = groups[folder.modId or "User"]
		if not parent then
			groups[folder.modId] = self.selectionParent:AddGroup(folder.modId)
			parent = groups[folder.modId]
			local sep = parent:AddSeparatorText(Ext.Mod.GetMod(folder.modId).Info.Name .. " ( ? )")
			sep:Tooltip():AddText("\t  Right-Click this if you want to copy all profiles, mutations, and lists from this mod")
			sep.OnRightClick = function()
				self.popup:Open()
				Helpers:KillChildren(self.popup)

				---@type ExtuiSelectable
				local mutationsSelect = self.popup:AddSelectable("Clone All Mutations, Profiles, and Lists?", "DontClosePopups")
				mutationsSelect:Tooltip():AddText([[
	Clones all folders, mutations, and associated lists to your local config, generating new UUIDs for them. If folders already exist with the same name, '(COPY)' will be appended to them.
If you want to preserve the original UUIDs so you can overwrite them with a new version of the JSON file, use the Import Profile option in the Profiles settings.]])

				mutationsSelect.OnClick = function()
					if mutationsSelect.Label ~= "Clone All Mutations, Profiles, and Lists?" then
						---@type MutationsConfig
						local modConfig = TableUtils:DeeplyCopyTable(MutationModProxy:ImportMutation(folder.modId))
						ListConfigurationManager:maintainLists(modConfig)

						local serialized = Ext.Json.Stringify(modConfig, {
							Beautify = false,
							MaxDepth = 1000,
							AvoidRecursion = false,
						})

						for listId in TableUtils:CombinedPairs(modConfig.lists.spellLists, modConfig.lists.passiveLists, modConfig.lists.statusLists) do
							serialized = serialized:gsub(Helpers:SanitizeStringForFind(listId), FormBuilder:generateGUID())
						end

						for folderId in pairs(modConfig.folders) do
							serialized = serialized:gsub(Helpers:SanitizeStringForFind(folderId), FormBuilder:generateGUID())
						end

						for profileId in pairs(modConfig.profiles) do
							serialized = serialized:gsub(Helpers:SanitizeStringForFind(profileId), FormBuilder:generateGUID())
						end

						modConfig = { ["mutations"] = Ext.Json.Parse(serialized) }
						TableUtils:ConvertStringifiedNumberIndexes(modConfig)

						local depFunc = MutationExternalProfileUtility:importProfile(modConfig)
						if depFunc then
							depFunc()
						end
						self:BuildFolderManager()
					else
						mutationsSelect.Label = "Are You Sure?"
						mutationsSelect.DontClosePopups = false
					end
				end
			end
			sep:SetStyle("SeparatorTextAlign", 0.5)
		end

		local folderSelect = Styler:ScaledFont(parent:AddTree(folder.name), "Default")
		folderSelect.IDContext = folderId
		folderSelect.UserData = folderId
		folderSelect:SetOpen(folderState[folderId] == true, "Always")
		folderSelect.DefaultOpen = false
		folderSelect.SpanFullWidth = true
		if folder.description and folder.description ~= "" then
			folderSelect:Tooltip():AddText("\t " .. folder.description)
		end

		parent:AddDummy(50, 0)

		local mutationGroup = parent:AddGroup("mutations")
		mutationGroup.UserData = folderId
		mutationGroup.SameLine = true
		mutationGroup.Visible = folderState[folderId] == true

		folderSelect.OnClick = function()
			mutationGroup.Visible = not mutationGroup.Visible
			folderState[folderId] = mutationGroup.Visible
		end

		folderSelect.OnRightClick = function()
			Helpers:KillChildren(self.popup)
			self.popup:Open()

			if not folder.modId then
				FormBuilder:CreateForm(self.popup:AddMenu("Create a Mutation"), function(formResults)
						folder.mutations[FormBuilder:generateGUID()] = {
							name = formResults.Name,
							description = formResults.Description,
							selectors = {},
							mutators = {}
						} --[[@as Mutation]]

						self:BuildFolderManager()
					end,
					{
						{
							label = "Name",
							type = "Text",
							errorMessageIfEmpty = "Required Field"
						},
						{
							label = "Description",
							type = "Multiline"
						}
					}
				)

				---@param selectable ExtuiSelectable
				FormBuilder:CreateForm(self.popup:AddMenu("Edit Details"), function(formResults)
						folder.name = formResults.Name
						folder.description = formResults.Description

						self:BuildFolderManager()
					end,
					{
						{
							label = "Name",
							type = "Text",
							errorMessageIfEmpty = "Required Field",
							defaultValue = folder.name
						},
						{
							label = "Description",
							type = "Multiline",
							defaultValue = folder.description
						}
					}
				)
			end

			self.popup:AddSelectable("Copy Folder").OnClick = function()
				local folderCopy = {
					name = TableUtils:IndexOf(ConfigurationStructure.config.mutations.folders, function(value)
							return value.name == folder.name
						end)
						and (folder.name .. " (COPY)")
						or folder.name,
					description = folder.description,
					mutations = TableUtils:DeeplyCopyTable(folder.mutations)
				} --[[@as MutationFolder]]

				for _, mutation in pairs(folderCopy.mutations) do
					mutation.modId = nil
				end

				ConfigurationStructure.config.mutations.folders[FormBuilder:generateGUID()] = folderCopy
				self:BuildFolderManager()
			end

			if not folder.modId then
				---@param select ExtuiSelectable
				self.popup:AddSelectable("Delete Folder (and Mutations)", "DontClosePopups").OnClick = function(select)
					if select.Label ~= "Delete Folder (and Mutations)" then
						folder.delete = true

						for _, profile in TableUtils:OrderedPairs(ConfigurationStructure.config.mutations.profiles) do
							local largestIndex = 0

							local toDelete = {}
							for i, mutRule in TableUtils:OrderedPairs(profile.mutationRules) do
								largestIndex = i > largestIndex and i or largestIndex

								if mutRule.mutationFolderId == folderId then
									toDelete[#toDelete + 1] = i - #toDelete
								end
							end

							for _, indexToDelete in ipairs(toDelete) do
								for x = indexToDelete, largestIndex do
									if profile.mutationRules[x] then
										profile.mutationRules[x].delete = true
									end
									profile.mutationRules[x] = TableUtils:DeeplyCopyTable(profile.mutationRules._real[x + 1])
								end
							end
						end

						self:BuildFolderManager()
					else
						select.Label = "Are You Sure?"
						Styler:Color(select, "ErrorText")
						select.DontClosePopups = false
					end
				end
			end

			self.popup:AddSelectable("Expand All Folders In Group").OnClick = function()
				for _, folder in ipairs(parent.Children) do
					if folder.IDContext and not folderState[folder.IDContext] then
						pcall(function(...)
							---@cast folder ExtuiTree
							folder:SetOpen(true, "Always")
							folder.OnClick(folder)
						end)
					end
				end
			end

			self.popup:AddSelectable("Collapse All Folders In Group").OnClick = function()
				for _, folder in ipairs(parent.Children) do
					if folder.IDContext and folderState[folder.IDContext] then
						pcall(function(...)
							---@cast folder ExtuiTree
							folder:SetOpen(false, "Always")
							folder.OnClick(folder)
						end)
					end
				end
			end
		end

		for mutationId, mutation in TableUtils:OrderedPairs(folder.mutations, function(key, value)
			return value.name
		end) do
			---@type ExtuiSelectable
			local mutationSelectable = mutationGroup:AddSelectable(mutation.name)
			mutationSelectable.IDContext = mutationId

			longestText = Styler:calculateTextDimensions(mutation.name, longestText)

			if mutation.description ~= "" then
				mutationSelectable:Tooltip():AddText("\t " .. mutation.description)
			end
			mutationSelectable.CanDrag = true
			mutationSelectable.DragDropType = mutation.prepPhase and "PrepMutationRules" or "MutationRules"
			mutationSelectable.UserData = {
				mutationFolderId = folderId,
				mutationId = mutationId
			}

			mutationSelectable.OnRightClick = function()
				Helpers:KillChildren(self.popup)
				self.popup:Open()

				if not folder.modId then
					self.popup:AddSelectable("Copy").OnClick = function()
						---@type Mutation
						local mut = TableUtils:DeeplyCopyTable(mutation)
						mut.name = mut.name .. " (COPY)"

						folder.mutations[FormBuilder:generateGUID()] = mut
						self:BuildFolderManager()
					end

					---@type ExtuiSelectable
					local select = self.popup:AddSelectable(mutation.prepPhase and "Unmark As Prep Mutation (?)" or "Mark As Prep Mutation (?)", "DontClosePopups")
					select:Tooltip():AddText(
						"\t A Prep Mutation is a mutation that is run before all others, assigning specified categories to the selected entities so they can be reused by Selectors in main mutations, greatly simplifying regular mutators. Prep mutations are marked via (P) in their button name")
					select.OnClick = function()
						mutation.prepPhase = not mutation.prepPhase
						mutation.mutators.delete = true
						mutation.mutators = mutation.prepPhase and { {
								targetProperty = "Prep Phase Marker"
							} --[[@as Mutator]] }
							or {}

						mutationSelectable.Label = ("%s%s"):format(mutation.prepPhase and "(P) " or "", mutation.name)

						if not mutation.prepPhase then
							for _, mutationRule in TableUtils:OrderedPairs(ConfigurationStructure.config.mutations.profiles[activeProfileId].prepPhaseMutations) do
								if mutationRule.mutationId == mutationSelectable.UserData.mutationId and mutationRule.mutationFolderId == mutationSelectable.UserData.mutationFolderId then
									mutationRule.delete = true
									break
								end
							end
						else
							for _, mutationRule in TableUtils:OrderedPairs(ConfigurationStructure.config.mutations.profiles[activeProfileId].mutationRules) do
								if mutationRule.mutationId == mutationSelectable.UserData.mutationId and mutationRule.mutationFolderId == mutationSelectable.UserData.mutationFolderId then
									mutationRule.delete = true
									break
								end
							end
						end
						mutationSelectable:SetColor("Text", { 0.86, 0.79, 0.68, 0.78 })

						mutationSelectable:OnClick()
						for _, profile in TableUtils:OrderedPairs(ConfigurationStructure.config.mutations.profiles) do
							TableUtils:ReindexNumericTable(profile.mutationRules)
							TableUtils:ReindexNumericTable(profile.prepPhaseMutations)
						end
						self:BuildFolderManager()
					end

					FormBuilder:CreateForm(self.popup:AddMenu("Edit Details"), function(formResults)
							mutation.name = formResults.Name
							mutation.description = formResults.Description

							self:BuildFolderManager()
						end,
						{
							{
								label = "Name",
								type = "Text",
								errorMessageIfEmpty = "Required Field",
								defaultValue = mutation.name
							},
							{
								label = "Description",
								type = "Multiline",
								defaultValue = mutation.description
							}
						}
					)

					if TableUtils:CountElements(ConfigurationStructure.config.mutations.folders) > 1 then
						---@type ExtuiMenu
						local moveMenu = self.popup:AddMenu("Move To Folder")

						for otherfolderId, otherFolder in TableUtils:OrderedPairs(ConfigurationStructure.config.mutations.folders, function(key, value)
							return value.name
						end) do
							if otherfolderId ~= folderId then
								moveMenu:AddSelectable(otherFolder.name).OnClick = function()
									otherFolder.mutations[mutationId] = mutation._real
									mutation.delete = true
									for _, profile in TableUtils:OrderedPairs(ConfigurationStructure.config.mutations.profiles) do
										for _, mutRule in TableUtils:OrderedPairs(profile.mutationRules) do
											if mutRule.mutationFolderId == folderId and mutRule.mutationId == mutationId then
												mutRule.mutationFolderId = otherfolderId
											end
										end
										TableUtils:ReindexNumericTable(profile.mutationRules)
									end
									self:BuildFolderManager()
								end
							end
						end
					end
				end

				if folder.modId then
					---@type ExtuiMenu
					local copyMenu = self.popup:AddMenu("Copy Mutation To Folder")

					local mut = TableUtils:DeeplyCopyTable(mutation)
					mut.modId = nil

					for _, userFolder in TableUtils:OrderedPairs(ConfigurationStructure.config.mutations.folders, function(_, userFolder)
						return userFolder.name
					end) do
						copyMenu:AddSelectable(userFolder.name).OnClick = function()
							if TableUtils:IndexOf(userFolder.mutations, function(value)
									return value.name == mut.name
								end)
							then
								mut.name = mut.name .. " (COPY)"
							end

							userFolder.mutations[FormBuilder:generateGUID()] = mut
							self:BuildFolderManager()
						end
					end

					copyMenu:AddSelectable("Use Mod's Folder Name").OnClick = function()
						local folderCopy = {
							name = TableUtils:IndexOf(ConfigurationStructure.config.mutations.folders, function(value)
									return value.name == folder.name
								end)
								and (folder.name .. " (COPY)")
								or folder.name,
							description = folder.description,
							mutations = { [FormBuilder:generateGUID()] = mut }
						} --[[@as MutationFolder]]

						ConfigurationStructure.config.mutations.folders[FormBuilder:generateGUID()] = folderCopy
						self:BuildFolderManager()
					end

					self.popup:AddSelectable("Copy Whole Folder").OnClick = function()
						local folderCopy = {
							name = TableUtils:IndexOf(ConfigurationStructure.config.mutations.folders, function(value)
									return value.name == folder.name
								end)
								and (folder.name .. " (COPY)")
								or folder.name,
							description = folder.description,
							mutations = TableUtils:DeeplyCopyTable(folder.mutations)
						} --[[@as MutationFolder]]

						for _, mutation in pairs(folderCopy.mutations) do
							mutation.modId = nil
						end

						ConfigurationStructure.config.mutations.folders[FormBuilder:generateGUID()] = folderCopy
						self:BuildFolderManager()
					end
				end

				if activeProfileId and not MutationConfigurationProxy.profiles[activeProfileId].modId then
					local index = TableUtils:IndexOf(MutationConfigurationProxy.profiles[activeProfileId].mutationRules, function(value)
						return value.mutationFolderId == folderId and value.mutationId == mutationId
					end)
					if index then
						---@param select ExtuiSelectable
						self.popup:AddSelectable("Remove From Active Profile", "DontClosePopups").OnClick = function(select)
							if select.Label ~= "Remove From Active Profile" then
								MutationConfigurationProxy.profiles[activeProfileId].mutationRules[index].delete = true
								self:BuildFolderManager()
							else
								select.Label = "Are You Sure?"
								Styler:Color(select, "ErrorText")
								select.DontClosePopups = false
							end
						end
					end
				end


				if not folder.modId then
					---@param selectable ExtuiSelectable
					self.popup:AddSelectable("Delete", "DontClosePopups").OnClick = function(selectable)
						if selectable.Label ~= "Delete" then
							mutation.delete = true

							for _, profile in TableUtils:OrderedPairs(ConfigurationStructure.config.mutations.profiles) do
								local largestIndex = 0

								local toDelete = {}
								for i, mutRule in TableUtils:OrderedPairs(profile.mutationRules) do
									largestIndex = i > largestIndex and i or largestIndex

									if mutRule.mutationFolderId == folderId and mutRule.mutationId == mutationId then
										toDelete[#toDelete + 1] = i - #toDelete
									end
								end

								for _, indexToDelete in ipairs(toDelete) do
									for x = indexToDelete, largestIndex do
										if profile.mutationRules[x] then
											profile.mutationRules[x].delete = true
										end
										profile.mutationRules[x] = TableUtils:DeeplyCopyTable(profile.mutationRules._real[x + 1])
									end
								end
								TableUtils:ReindexNumericTable(profile.mutationRules)
							end

							self:BuildFolderManager()
						else
							selectable.Label = "Are You Sure? This Will Delete From All Profiles"
							Styler:Color(selectable, "ErrorText")
						end
					end
				end
			end
			mutationSelectable.OnClick = function()
				mutationSelectable.Selected = false
				Helpers:KillChildren(self.mutationDesigner)

				if activeMutationView then
					if activeMutationView.Handle then
						-- https://github.com/Norbyte/bg3se/blob/f8b982125c6c1997ceab2d65cfaa3c1a04908ea6/BG3Extender/Extender/Client/IMGUI/IMGUI.cpp#L1901C34-L1901C60
						activeMutationView:SetColor("Button", { 0.46, 0.40, 0.29, 0.5 })

						if not tonumber(activeMutationView.ParentElement.UserData) then
							activeMutationView.Selected = false
						end
					end
				end

				Styler:MiddleAlignedColumnLayout(self.mutationDesigner, function(ele)
					ele:AddText(folder.name .. "/" .. mutation.name).Font = "Big"
					Styler:CheapTextAlign(mutation.description, ele)
				end).SameLine = true
				MutationDesigner:RenderMutationManager(self.mutationDesigner:AddGroup("designer"), mutation)
			end

			---@param selectable ExtuiSelectable
			---@param preview ExtuiTreeParent
			mutationSelectable.OnDragStart = function(selectable, preview)
				preview:AddText(selectable.Label)
			end

			if activeProfileId and MutationConfigurationProxy.profiles[activeProfileId] then
				local profile = MutationConfigurationProxy.profiles[activeProfileId]
				if TableUtils:IndexOf(profile.mutationRules, function(mutationRule)
						return mutationRule.mutationFolderId == folderId and mutationRule.mutationId == mutationId
					end)
					or TableUtils:IndexOf(profile.prepPhaseMutations or {}, function(mutationRule)
						return mutationRule.mutationFolderId == folderId and mutationRule.mutationId == mutationId
					end)
				then
					mutationSelectable:SetColor("Text", { 0.86, 0.79, 0.68, 0.28 })
					mutationSelectable.CanDrag = false
				end
			end
		end
	end

	groups["User"]:AddNewLine()

	---@type ExtuiSelectable
	local createFolderButton = groups["User"]:AddSelectable("Create Folder")
	createFolderButton:SetStyle("SelectableTextAlign", 0.5)

	createFolderButton.OnClick = function()
		createFolderButton.Selected = false

		Helpers:KillChildren(self.popup)
		self.popup:Open()

		FormBuilder:CreateForm(self.popup, function(formResults)
				ConfigurationStructure.config.mutations.folders[FormBuilder:generateGUID()] = {
					name = formResults.Name,
					description = formResults.Description,
					mutations = {}
				} --[[@as MutationFolder]]

				self:BuildFolderManager()
			end,
			{
				{
					label = "Name",
					type = "Text",
					errorMessageIfEmpty = "Required Field"
				},
				{
					label = "Description",
					type = "Multiline"
				}
			}
		)
	end

	self.parentTable.ColumnDefs[1].Width = longestText

	self:BuildProfileManager()
end

local triedOnce
function MutationProfileManager:BuildProfileManager()
	if not activeProfileId and not triedOnce then
		triedOnce = true
		-- MCM seems to initialize the tab before the ModVars are loaded, so need to do a deferred load
		Ext.Timer.WaitFor(1000, function()
			activeProfileId = Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile
			if not MutationConfigurationProxy.profiles[activeProfileId] then
				Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = nil
				activeProfileId = nil
			end
			self:BuildFolderManager()
		end)
		return
	end

	local lastMutation = activeMutationView and activeMutationView.Label
	activeMutationView = nil

	local userProfiles = ConfigurationStructure.config.mutations.profiles
	Helpers:KillChildren(self.profileManagerParent, self.rulesOrderGroup, self.mutationDesigner)

	Styler:CheapTextAlign("Active Profile", self.profileManagerParent, "Large")

	local profileCombo = self.profileManagerParent:AddCombo("")
	profileCombo.WidthFitPreview = true

	local sIndex = -1
	local opt = {}
	if activeProfileId then
		table.insert(opt, "Disabled")
	end

	for profileId, profile in TableUtils:OrderedPairs(MutationConfigurationProxy.profiles, function(_, value)
		return value.name
	end) do
		table.insert(opt, profile.name .. (profile.modId and "(M)" or ""))
		if activeProfileId == profileId then
			sIndex = #opt
		end
	end

	profileCombo.Options = opt
	profileCombo.SelectedIndex = sIndex - 1
	profileCombo.OnChange = function()
		local selectedName = profileCombo.Options[profileCombo.SelectedIndex + 1]

		if selectedName == "Disabled" then
			activeProfileId = nil
			Ext.Vars.GetModVariables(ModuleUUID).HasDisabledProfiles = true
			Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = nil
		else
			local isModProfile = selectedName:sub(#selectedName - 2) == "(M)"

			activeProfileId = TableUtils:IndexOf(MutationConfigurationProxy.profiles, function(value)
				if isModProfile then
					if value.modId then
						return value.name == selectedName:sub(1, #selectedName - 3)
					else
						return false
					end
				elseif not value.modId then
					return value.name == selectedName
				end
				return false
			end)

			Ext.Vars.GetModVariables(ModuleUUID).HasDisabledProfiles = false
			Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = activeProfileId
		end

		Helpers:KillChildren(self.rulesOrderGroup, self.mutationDesigner)
		self:BuildFolderManager()
	end

	local manageProfileButton = Styler:ImageButton(self.profileManagerParent:AddImageButton("Manage", "ico_edit_d", { 32, 32 }))
	manageProfileButton.SameLine = true
	local manageProfilePopup = self.profileManagerParent:AddPopup("Manage Profiles")

	manageProfilePopup:AddSelectable("Create Profile").OnClick = function()
		Helpers:KillChildren(self.popup)
		self.popup:Open()

		FormBuilder:CreateForm(self.popup, function(formResults)
				local profileId = FormBuilder:generateGUID()
				userProfiles[profileId] = {
					name = formResults.Name,
					description = formResults.Description,
					defaultActive = formResults.defaultActive,
					mutationRules = {}
				} --[[@as MutationProfile]]

				if formResults.defaultActive then
					for name, profile in pairs(userProfiles) do
						if name ~= formResults.Name then
							profile.defaultActive = false
						end
					end
				end

				activeProfileId = profileId
				Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = profileId

				self:BuildProfileManager()
			end,
			{
				{
					label = "Name",
					type = "Text",
					errorMessageIfEmpty = "Required Field"
				},
				{
					label = "Description",
					type = "Multiline"
				}
			}
		)
	end

	local importSelect = manageProfilePopup:AddSelectable("Import Profile(s)", "DontClosePopups")

	local importGroup = manageProfilePopup:AddGroup("Import")
	importGroup.Visible = false

	importSelect.OnClick = function()
		if #importGroup.Children > 0 then
			Helpers:KillChildren(importGroup)
			importGroup.Visible = false
		else
			importGroup.Visible = true
			importGroup:AddText("Enter the full, EXACT (case-sensitive) file path + name relative to Lab's SE Folder")

			local fileNameInput = importGroup:AddInputText("")
			fileNameInput.Hint = "imported/otherProfile.json"
			fileNameInput:SetColor("Text", Styler:ConvertRGBAToIMGUI({ 1, 0, 0, 0.4 }))

			local importButton = importGroup:AddButton("Import")
			importButton.SameLine = true

			local errorGroup = importGroup:AddGroup("DepErrors")
			errorGroup.Visible = false

			local timer
			fileNameInput.OnChange = function()
				errorGroup.Visible = false

				if timer then
					Ext.Timer.Cancel(timer)
				end

				timer = Ext.Timer.WaitFor(200, function()
					if not FileUtils:LoadFile(fileNameInput.Text) then
						fileNameInput:SetColor("Text", Styler:ConvertRGBAToIMGUI({ 1, 0, 0, 0.4 }))
						importButton.Disabled = true
					else
						fileNameInput:SetColor("Text", { 0.86, 0.79, 0.68, 0.78 })
						importButton.Disabled = false
					end
				end)
			end

			importButton.OnClick = function()
				local importFunc, mods, failedDependencies, showDepWindowFunc = MutationExternalProfileUtility:importProfile(FileUtils:LoadTableFile(fileNameInput.Text))
				if not importFunc then
					self:BuildFolderManager()
				else
					errorGroup.Visible = true
					Helpers:KillChildren(errorGroup)

					errorGroup:AddSeparatorText("Missing Dependencies!"):SetColor("Separator", { 1, 0, 0, 0.4 })
					Styler:MiddleAlignedColumnLayout(errorGroup, function(ele)
						local continueButton = ele:AddButton("Continue")
						continueButton:Tooltip():AddText("\t This will remove all items that depend on a missing mod while importing - it will not affect the file")
						continueButton.OnClick = function()
							importFunc()
							self:BuildFolderManager()
						end

						local viewReport = ele:AddButton("View Report")
						viewReport.SameLine = true
						viewReport.OnClick = showDepWindowFunc
					end)

					local modTable = errorGroup:AddTable("Deps", 3)

					for modId, mod in TableUtils:OrderedPairs(mods, function(key, value)
						return value.modName
					end) do
						local row = modTable:AddRow()
						if failedDependencies[modId] then
							row:SetColor("Text", { 1, 0, 0, 0.6 })
						end

						row:AddCell():AddText(mod.modName)
						row:AddCell():AddText(table.concat(mod.modVersion, "."))
						row:AddCell():AddText(mod.modAuthor)
					end

					errorGroup:AddSeparatorText("Missing Dependencies!"):SetColor("Separator", { 1, 0, 0, 0.4 })
				end
			end
		end
	end

	---@type ExtuiMenu
	local exportProfilesMenu = manageProfilePopup:AddMenu("Export Profile(s)")

	local sep = manageProfilePopup:AddSeparatorText("Profiles")
	sep:SetStyle("SeparatorTextAlign", 0.5)

	for profileId, profile in TableUtils:OrderedPairs(MutationConfigurationProxy.profiles, function(key, value)
		return (value.modId and ("Z" .. value.modId) or "") .. value.name
	end) do
		if not profile.modId then
			exportProfilesMenu:AddCheckbox(profile.name .. "##" .. profileId).UserData = profileId
		end

		local isDefault = ConfigurationStructure.config.mutations.settings.defaultProfile == profileId

		---@type ExtuiMenu
		local profileMenu = manageProfilePopup:AddMenu((isDefault and "(D) " or "") .. profile.name .. (profile.modId and " (M)" or "") .. "##" .. profileId)

		if profile.modId then
			profileMenu:AddSeparatorText("From " .. Ext.Mod.GetMod(profile.modId).Info.Name):SetStyle("Alpha", 0.5)
		end

		if not isDefault then
			profileMenu:AddItem("Set as Default Profile").OnClick = function()
				ConfigurationStructure.config.mutations.settings.defaultProfile = profileId
				self:BuildProfileManager()
			end
		else
			profileMenu:AddItem("Unset as Default Profile").OnClick = function()
				ConfigurationStructure.config.mutations.settings.defaultProfile = nil
				self:BuildProfileManager()
			end
		end

		profileMenu:AddItem("Copy").OnClick = function()
			local copiedProfile = TableUtils:DeeplyCopyTable(profile)
			copiedProfile.name = copiedProfile.name .. " (COPY)"
			copiedProfile.modId = nil

			userProfiles[FormBuilder:generateGUID()] = copiedProfile

			self:BuildProfileManager()
		end

		if not profile.modId then
			profileMenu:AddItem("Edit").OnClick = function()
				Helpers:KillChildren(self.popup)
				self.popup:Open()
				FormBuilder:CreateForm(self.popup, function(formResults)
						profile.name = formResults.Name
						profile.description = formResults.Description
						profile.defaultActive = formResults.defaultActive

						if formResults.defaultActive then
							for id, profile in pairs(userProfiles) do
								if id ~= profileId then
									profile.defaultActive = false
								end
							end
						end

						self:BuildProfileManager()
					end,
					{
						{
							label = "Name",
							type = "Text",
							errorMessageIfEmpty = "Required Field",
							defaultValue = profile.name
						},
						{
							label = "Description",
							type = "Multiline",
							defaultValue = profile.description
						},
						{
							label = "Active By Default for New Games?",
							propertyField = "defaultActive",
							type = "Checkbox",
							defaultValue = profile.defaultActive
						}
					}
				)
			end

			if profile.mutationRules and next(profile.mutationRules) then
				profileMenu:AddItem("Export").OnClick = function()
					MutationExternalProfileUtility:exportProfile(false, profileId)
				end

				profileMenu:AddItem("Export For Mod").OnClick = function()
					MutationExternalProfileUtility:exportProfile(true, profileId)
				end
			end

			---@param menuItem ExtuiSelectable
			profileMenu:AddSelectable("Delete", "DontClosePopups").OnClick = function(menuItem)
				if menuItem.Label ~= "Delete" then
					userProfiles[profileId].delete = true
					if activeProfileId == profileId then
						activeProfileId = nil
						Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = activeProfileId
					end
					self:BuildProfileManager()
				else
					menuItem.Label = "Are You Sure?"
					Styler:Color(menuItem, "ErrorText")
					menuItem.DontClosePopups = false
				end
			end
		end
	end

	if #exportProfilesMenu.Children == 0 then
		exportProfilesMenu:Destroy()
	else
		Styler:MiddleAlignedColumnLayout(exportProfilesMenu, function(ele)
			local exportButton = ele:AddSelectable("Export")
			exportButton:SetStyle("SelectableTextAlign", 0.5)

			exportButton.OnClick = function()
				local profilesToExport = {}

				for _, child in pairs(exportProfilesMenu.Children) do
					if child.UserData and child.Checked then
						table.insert(profilesToExport, child.UserData)
					end
				end

				if next(profilesToExport) then
					MutationExternalProfileUtility:exportProfile(false, table.unpack(profilesToExport))
				end
			end

			local exportForModButton = ele:AddSelectable("Export For Mod")
			exportForModButton:SetStyle("SelectableTextAlign", 0.5)
			exportForModButton.OnClick = function()
				local profilesToExport = {}

				for _, child in pairs(exportProfilesMenu.Children) do
					if child.UserData and child.Checked then
						table.insert(profilesToExport, child.UserData)
					end
				end

				if next(profilesToExport) then
					MutationExternalProfileUtility:exportProfile(true, table.unpack(profilesToExport))
				end
			end
		end)
	end

	manageProfileButton.OnClick = function()
		manageProfilePopup:Open()
	end

	self:BuildRuleManager(lastMutation)
end

local prepHide = false
local mainHide = false


local activeMutation
---@param lastMutationActive string?
function MutationProfileManager:BuildRuleManager(lastMutationActive)
	lastMutationActive = lastMutationActive or activeMutation
	Helpers:KillChildren(self.rulesOrderGroup)
	activeMutationView = nil

	---@type MutationProfile
	local activeProfile
	if activeProfileId then
		activeProfile = MutationConfigurationProxy.profiles[activeProfileId]
	else
		return
	end

	local longestTextWidth = Styler:ScaleFactor() * 400

	local function buildSlots(prepPhase)
		if prepPhase then
			self.rulesOrderGroup:AddSeparatorText("Prep Mutations"):SetStyle("SeparatorTextAlign", 0.5)
		else
			self.rulesOrderGroup:AddSeparatorText("Main Mutations"):SetStyle("SeparatorTextAlign", 0.5)
		end
		local hideButton = Styler:ImageButton(self.rulesOrderGroup:AddImageButton("hideLevel" .. (prepPhase and "prep" or "not"), "Action_Hide", Styler:ScaleFactor({ 28, 28 })))
		hideButton.Visible = not ((prepPhase and prepHide) or (not prepPhase and mainHide))
		local showButton = Styler:ImageButton(self.rulesOrderGroup:AddImageButton("showLevel" .. (prepPhase and "prep" or "not"), "ico_concentration", Styler:ScaleFactor({ 28, 28 })))
		showButton.Visible = (prepPhase and prepHide) or (not prepPhase and mainHide)

		local group = self.rulesOrderGroup:AddGroup("Mutations" .. (prepPhase and "prep" or "not prep"))
		group.Visible = hideButton.Visible

		hideButton.OnClick = function()
			group.Visible = not group.Visible
			hideButton.Visible = not hideButton.Visible
			showButton.Visible = not showButton.Visible
			if prepPhase then
				prepHide = not prepHide
			else
				mainHide = not mainHide
			end
		end

		showButton.OnClick = hideButton.OnClick

		if prepPhase then
			activeProfile.prepPhaseMutations = activeProfile.prepPhaseMutations or {}
		end

		local rulesToUse = prepPhase and activeProfile.prepPhaseMutations or activeProfile.mutationRules

		TableUtils:ReindexNumericTable(rulesToUse)

		for counter = 1, TableUtils:CountElements(rulesToUse) + 1 do
			local row = group:AddGroup("MutationGroup" .. counter .. (prepPhase and "prep" or "main"))

			row.UserData = counter
			if not activeProfile.modId then
				row.DragDropType = prepPhase and "PrepMutationRules" or "MutationRules"
				---@param row ExtuiGroup
				---@param dropped ExtuiSelectable|ExtuiButton
				row.OnDragDrop = function(row, dropped)
					---@type number?
					local droppedIndex = tonumber(dropped.ParentElement.UserData)

					local rule = TableUtils:DeeplyCopyTable(droppedIndex
						and rulesToUse[droppedIndex]
						or dropped.UserData)

					if not droppedIndex then
						dropped:SetColor("Text", { 0.86, 0.79, 0.68, 0.28 })
						dropped.CanDrag = false
					else
						rulesToUse[droppedIndex].delete = true
					end

					droppedIndex = droppedIndex or TableUtils:CountElements(rulesToUse)

					if droppedIndex < row.UserData then
						for i = droppedIndex, row.UserData - 1, 1 do
							if rulesToUse[i + 1] then
								rulesToUse[i] = TableUtils:DeeplyCopyTable(rulesToUse[i + 1])
								rulesToUse[i + 1].delete = true
							end
						end
						rulesToUse[row.UserData] = rule
					else
						for i = droppedIndex, row.UserData, -1 do
							if rulesToUse[i] then
								rulesToUse[i + 1] = TableUtils:DeeplyCopyTable(rulesToUse[i])
								rulesToUse[i].delete = true
							end
						end

						rulesToUse[row.UserData] = rule
					end

					self:BuildRuleManager(activeMutationView and activeMutationView.Label)
				end
			end

			local orderNumberInput = row:AddInputInt("##" .. counter .. (prepPhase and "prep" or "main"), counter)
			orderNumberInput.Disabled = activeProfile.modId ~= nil
			orderNumberInput.AutoSelectAll = true
			orderNumberInput.ItemWidth = 40

			if activeProfile and rulesToUse[counter] then
				local mutationRule = rulesToUse[counter]

				local folders = MutationConfigurationProxy.folders

				if not folders[mutationRule.mutationFolderId] or not folders[mutationRule.mutationFolderId].mutations[mutationRule.mutationId] then
					Logger:BasicError("Couldn't find Mutation specified in Profile %s at index %d - folderId: %s | mutationId: %s",
						activeProfile.name,
						counter,
						mutationRule.mutationFolderId,
						mutationRule.mutationId)

					local mutationButton = row:AddButton("Missing Mutation! (?)")
					mutationButton.SameLine = true
					mutationButton.IDContext = mutationRule.mutationFolderId .. mutationRule.mutationId
					mutationButton.UserData = mutationRule._real or mutationRule

					Styler:Color(mutationButton, "ErrorText")
					mutationButton:Tooltip():AddText("\t " ..
						("Couldn't find Mutation specified in Profile %s at index %d - folderId: %s | mutationId: %s - copy-paste from log.txt or SE console"):format(
							activeProfile.name,
							counter,
							mutationRule.mutationFolderId,
							mutationRule.mutationId)
					)

					mutationButton.OnClick = function()
						Helpers:KillChildren(self.popup)
						self.popup:Open()

						self.popup:AddSelectable("Remove From Profile").OnClick = function()
							rulesToUse[row.UserData].delete = true
							rulesToUse[row.UserData] = nil
							self:BuildRuleManager(lastMutationActive)
						end
					end
				else
					orderNumberInput.OnDeactivate = function()
						if rulesToUse[row.UserData]
							and orderNumberInput.Value[1] ~= row.UserData
							and orderNumberInput.Value[1] > 0
						then
							local rule = TableUtils:DeeplyCopyTable(rulesToUse[row.UserData])

							rulesToUse[row.UserData].delete = true

							if row.UserData < orderNumberInput.Value[1] then
								for i = row.UserData, orderNumberInput.Value[1] - 1, 1 do
									if rulesToUse[i + 1] then
										rulesToUse[i] = TableUtils:DeeplyCopyTable(rulesToUse[i + 1])
										rulesToUse[i + 1].delete = true
									end
								end
								rulesToUse[orderNumberInput.Value[1]] = rule
							else
								for i = row.UserData, orderNumberInput.Value[1], -1 do
									if rulesToUse[i] then
										rulesToUse[i + 1] = TableUtils:DeeplyCopyTable(rulesToUse[i])
										rulesToUse[i].delete = true
									end
								end

								rulesToUse[orderNumberInput.Value[1]] = rule
							end

							self:BuildRuleManager(activeMutationView and activeMutationView.Label)
						end
					end

					local mutationButton = row:AddButton(folders[mutationRule.mutationFolderId].name ..
						"/" .. folders[mutationRule.mutationFolderId].mutations[mutationRule.mutationId].name)

					mutationButton.UserData = {
						additive = mutationRule.additive,
						mutationFolderId = mutationRule.mutationFolderId,
						mutationId = mutationRule.mutationId,
					}

					longestTextWidth = Styler:calculateTextDimensions(mutationButton.Label, longestTextWidth)

					if folders[mutationRule.mutationFolderId].mutations[mutationRule.mutationId].modId then
						mutationButton.Label = "(M) " .. mutationButton.Label
					end

					mutationButton.IDContext = mutationRule.mutationFolderId .. mutationRule.mutationId
					mutationButton.SameLine = true
					mutationButton.UserData = activeProfile.modId and mutationRule or mutationRule._real

					if not activeProfile.modId then
						mutationButton.CanDrag = true
						mutationButton.DragDropType = row.DragDropType
					end

					local mutation = folders[mutationRule.mutationFolderId].mutations[mutationRule.mutationId]
					if not mutation.modId and (not mutation.selectors() or not mutation.mutators()) then
						mutationButton:SetColor("Button", { 1, 0.02, 0, 0.4 })
						mutationButton:Tooltip():AddText("Missing a defined selector or mutator!")
					end

					---@param button ExtuiButton
					---@param preview ExtuiTreeParent
					mutationButton.OnDragStart = function(button, preview)
						preview:AddText(button.Label)
						self.selectionParent.DragDropType = prepPhase and "PrepMutationRules" or "MutationRules"
					end

					mutationButton.OnRightClick = function()
						for _, modSection in pairs(self.selectionParent.Children) do
							---@cast modSection ExtuiGroup
							for _, folderGroup in pairs(modSection.Children) do
								if folderGroup.UserData and folderGroup.UserData == mutationRule.mutationFolderId then
									for _, mutation in pairs(folderGroup.Children) do
										---@cast mutation ExtuiSelectable

										if mutation.UserData and mutation.UserData.mutationId == mutationRule.mutationId then
											return mutation:OnRightClick()
										end
									end
								end
							end
						end
					end
					mutationButton.OnClick = function()
						Helpers:KillChildren(self.mutationDesigner)

						local mutation = folders[mutationRule.mutationFolderId].mutations[mutationRule.mutationId]

						if not mutation.modId and (not mutation.selectors() or not mutation.mutators()) then
							mutationButton:SetColor("Button", { 1, 0.02, 0, 0.4 })
						end

						if activeMutationView then
							if activeMutationView.Handle then
								---@type MutationProfileRule
								local activeMutationRule = activeMutationView.UserData
								local mutationConfig = folders[activeMutationRule.mutationFolderId].mutations[activeMutationRule.mutationId]

								if not mutationConfig.modId and (not mutationConfig.selectors() or not mutationConfig.mutators()) then
									activeMutationView:SetColor("Button", { 1, 0.02, 0, 0.4 })
								else
									-- https://github.com/Norbyte/bg3se/blob/f8b982125c6c1997ceab2d65cfaa3c1a04908ea6/BG3Extender/Extender/Client/IMGUI/IMGUI.cpp#L1901C34-L1901C60
									activeMutationView:SetColor("Button", { 0.46, 0.40, 0.29, 0.5 })
								end

								if not tonumber(activeMutationView.ParentElement.UserData) then
									activeMutationView.Selected = false
								end

								if activeMutationView.Handle == mutationButton.Handle then
									activeMutationView = nil
									return
								end
							end
						end

						activeMutationView = mutationButton
						mutationButton:SetColor("Button", { 0.64, 0.40, 0.28, 0.5 })

						Styler:MiddleAlignedColumnLayout(self.mutationDesigner, function(ele)
							Styler:CheapTextAlign(folders[mutationRule.mutationFolderId].name ..
								"/" .. folders[mutationRule.mutationFolderId].mutations[mutationRule.mutationId].name, ele, "Big")

							local mut = folders[mutationRule.mutationFolderId].mutations[mutationRule.mutationId]

							if mut.modId then
								local modInfo = Ext.Mod.GetMod(mut.modId).Info
								Styler:CheapTextAlign("(" .. modInfo.Name .. ")", ele)
								Styler:CheapTextAlign(mut.description, ele)
							else
								Styler:CheapTextAlign(mut.description, ele)
							end
						end).SameLine = true

						activeMutation = mutationButton.Label
						MutationDesigner:RenderMutationManager(self.mutationDesigner:AddGroup("designer"), mutation)
					end

					if mutationButton.Label == lastMutationActive then
						mutationButton:OnClick()
						activeMutationView = mutationButton
					end

					if not prepPhase then
						if TableUtils:IndexOf(mutation.mutators, function(value)
								return MutatorInterface.registeredMutators[value.targetProperty]:canBeAdditive(value)
							end)
						then
							local additiveCheckbox = row:AddCheckbox("", mutationRule.additive)
							additiveCheckbox.Disabled = activeProfile.modId ~= nil
							additiveCheckbox:Tooltip():AddText(
								"\t If checked, relevant mutators under this mutation will be _composable_, meaning they will be combined with any mutators of the same type that are applicable from mutations earlier in the flow. See the documentation for each mutator to see when and how this applies.\n If unchecked, composable mutators of the same type from earlier mutations will be replaced with these.")

							additiveCheckbox.SameLine = true
							additiveCheckbox.OnChange = function()
								mutationRule.additive = additiveCheckbox.Checked
							end
						end
					end
				end
			else
				orderNumberInput.Disabled = true

				local cell = row:AddButton((" "):rep(15) .. "##" .. counter .. (prepPhase and "prep" or "main"))
				cell.SameLine = true
			end
		end
	end

	buildSlots(true)
	buildSlots()

	self.profileRulesParent.ColumnDefs[1].Width = math.max(300 * Styler:ScaleFactor(), longestTextWidth)
	self.profileRulesParent.UserData = self.profileRulesParent.ColumnDefs[1].Width
end

---@return MazzleDocsDocumentation
function MutationProfileManager:generateDocs()
	local docs = {
		{
			Topic = "Mutations",
			content = {
				{
					type = "Heading",
					text = "Console Commands"
				},
				{
					type = "Content",
					text =
					"This slide documents all SE Console Commands that Lab has created for use by anyone - the code examples are useful for copy-pasting into your own console if you want."
				},
				{
					type = "SubHeading",
					text = "Client Only"
				},
				{
					type = "Content",
					text =
					[[!Lab_MetaBlock <Mod UUIDs> - generates the meta.lsx Dependency block for the specified mods, printing them out in the console for whatever use you want ]]
				},
				{
					type = "Code",
					text = [[client
!Lab_MetaBlock 61e8471b-4eda-4493-829d-e3c29ecc36c3 a17a3a3d-5c16-404a-910a-68ae9e47f247
]]
				},
				{
					type = "SubHeading",
					text = "Server Only"
				},
				{
					type = "Content",
					text =
					[[!Lab_TestTransient - Reruns the active profile, fully completing the undo operations for all mutators, then applies them as normal. Useful for testing a profile without saving/reloading constantly.]]
				},
				{
					type = "Code",
					text = [[server
!Lab_TestTransient
]]
				},
				{
					type = "Separator"
				},
				{
					type = "Content",
					text = {
						"!Lab_GenerateMutationDiagram <entityId> - generates the code to render a Mermaid diagram for the specified Entity (only one can be specified), showing what mutations would apply to them in the current profile, and which mutators compose and overwrite each other.",
						"You can get the EntityUUID by copying it from the last field in the Inspector - alternatively, if you've already run your profile against an entity, you'll find a button to run this command for you in their Mutations tab within the Inspector.",
						"The output will also be written to %localappdata%/Larian Studios/Baldur's Gate 3/Script Extender/Absolutes_Laboratory/DiagramOutputs/<entity name - last 5 characters of their uuid>.txt"
					}
				},
				{
					type = "Code",
					text = [[server
!Lab_GenerateMutationDiagram cad1854b-8f41-4038-b640-156ee0272f81

Enter the generated code in https://www.mermaidchart.com/play (Hit Edit code in the bottom left)
]]
				},
				{
					type = "SubHeading",
					text = "Either Client or Server"
				},
				{
					type = "Content",
					text = {
						"!Lab_DumpProgressions - writes Lab's index of all progressions currently available in the game to %localappdata%/Larian Studios/Baldur's Gate 3/Script Extender/Absolutes_Laboratory/ProgressionDumper.txt.",
						"This is not a true representation of the progressions, only what Lab indexes for use in the List Mutators"
					}
				},
				{
					type = "Code",
					text = [[server
!Lab_DumpProgressions
]]
				}
			}
		},
		{
			Topic = "Mutations",
			SubTopic = "Profiles",
			content = {
				{
					type = "Heading",
					text = "What Are Profiles?"
				},
				{
					type = "Content",
					text = [[
Profiles represent an ordered group of Mutations that should run during the LevelGameplayReady Osiris Event.

You can have any number of profiles using any number of mutations, but only one profile can be active for a given save.

The active Profiles is saved to a ModVar, so it will only be available in saves created once it was activated and afterwards - loading a save before you activated a profile will not have it loaded (unless it's your default profile and you haven't disabled the default for that save).

Mutations are applied in the order specified - later Mutations override earlier ones, but certain mutators have a 'composable' property.

The details of what this means are specified in each applicable mutator's page, but you can allow these mutators to be composable by checking the checkbox next to the mutation - if this is not checked, simple override behavior will be used instead.

Create your profile using the Gear icon next to the dropdown - once your profile is created, drag and drop mutations from the left sidebar into the profile section, onto the buttons - you can do it for blank or populated buttons.]]
				},
				{
					type = "CallOut",
					centered = true,
					text = {
						"The ProfileExecutor will undo all non-transient mutators before executing all the mutations every time it runs (each LevelGameplayReady event or every player level up (see Level Mutator))!",
						"The ProfileExecutor will also attach the status `ABSOLUTES_LAB_UNDO_MUTATION_MARKER` for 1 round to every entity in the UNDO stage, giving stats modders a hook to remove their custom statuses if they need",
						"Users should only really notice this if they save in the middle of combat, then reload, and even then most mutators shouldn't cause any differences an average user would notice. This is an untested theory though, so please provide feedback!",
						"Mutations included in profiles are not unique to that profile - deleting or changing them in one profile will change them in every profile they're included in"
					}
				},
				{
					type = "Section",
					text = "Key Terms",
				},
				{
					type = "Bullet",
					text = {
						"Mutations: A group of Mutators and Selectors",
						"Selectors: Defines what NPCs should be targeted for the Mutators - must run the Scanner in the Inspector tab for the Dry Run to work. Can have duplicate Selector types, but order matters - see Selectors page.",
						"Mutators: Defines how the NPC should be changed (mutated) if selected by the Selectors. Each Mutation can only have one of each type of Mutator. Order doesn't matter within the context of a Mutation",
					}
				}
			}
		},
		{
			Topic = "Mutations",
			SubTopic = "Profiles",
			content = {
				{
					type = "Heading",
					text = "Exporting Profiles and Everything Associated",
					centered = true
				},
				{
					type = "CallOut",
					prefix = "Highlights:",
					prefix_color = "Green",
					text = [[
- Loose Exports are for sharing with individuals, Mod Exports are for sharing with the Community (make sure to list Lab as a dependency on Nexus)
- Exported Mutations will record any and all mods that they depend on
- You can't export another mod's mutations/lists without copying it to your machine first - this breaks the link with that mod (otherwise, their mod will become a dependency)
- When updating your Mod Export, copy the Dependency Nodes over as well, to ensure the dependencies list the latest versions]]
				} --[[@as MazzleDocsCallOut]],
				{
					type = "SubHeading",
					text = "Loose Files",
					fontsize = "Large"
				},
				{
					type = "Content",
					text = [[
Choosing to export a Profile (not Export For Mod) will create a JSON file under `%localappdata%\Larian Studios\Baldur's Gate 3\Script Extender\Absolutes_Laboratory\ExportedProfiles\Mutations`, named using the profile name(s), which includes all mutations, mutators, selectors, and lists used in that profile.

This file can be reimported immediately by you if you want to check what was exported - Lab will prevent duplication of Mutations and Profile names where necessary by assigning new UUIDs to things that have them, and appending `- Imported` or the first 3 characters of the UUID to the Name of the artifact.

Lab will also record any mods used for resources/stats in the packaged mutations in the export itself, validating that these mods are present when the user imports the file. If any are missing, the user is presented with a warning, a detailed report, and the option to continue.

If they choose to continue without first loading the mod, Lab will scrub all references to that resource/stat in the relevant selectors/mutators, proactively removing any possible runtime errors - the file itself will be untouched, allowing it to be reimported later (though the original import will need to be deleted via the menu so it isn't renamed on top of the original renaming, causing an - Imported - Imported situation).]]
				},
				{
					type = "Image",
					image_index = 3
				} --[[@as MazzleDocsImage]],
				{
					type = "Image",
					image_index = 4
				} --[[@as MazzleDocsImage]],
				{
					type = "Content",
					text = [[
If any mutations from Mods are used (see below), those mutations will not be exported - instead, a dependency on the mod providing those mutations will be recorded, preserving the link to that mod.

If you want to package the mutation separately, copy it to your own folder first, use that in your profile, then export.]]
				},
				{
					type = "Separator"
				},
				{
					type = "SubHeading",
					text = "Packaging With A Mod",
					fontsize = "Large"
				},
				{
					type = "Content",
					text = [[
Choosing the Export For Mod option will instead create two files in the same location - `AbsolutesLaboratory_ProfilesAndMutations.json` and `ExportedModMetaLsxDependencies.lsx`

The .json file is named this way because that is what Lab looks for in every active mod to determine if there're profiles/mutations to load. Simply place this file next to your meta.lsx and you're good to go - see the Example Mod

Profiles/Mutations/Lists loaded by users this way won't be renamed - they're stored separately in-memory from the users ones, so there won't be any kind of conflict. You can use Mod-added mutations/lists in your own profiles, but same rules as above apply: You can't export another mod's mutations/lists without copying it to your machine first (which is usually desirable, in case the original author updates them to work better in relevant circumstances).

The contents of the second file, ExportedModMetaLsxDependencies.lsx, should be used in the meta.lsx to document your mod's dependency on the relevant mods (including Lab!), allowing those dependencies to show up in Mod Managers for user convenience.
Simply copy the contents into your meta.lsx under the Dependencies node, and you're good to go (see the Example Mod in Github again for a full file example).

I recommend repeating this process every time you update your mod's export file, as these blocks also contain the versions of the mods you were using when you exported, so copying it over again will update the versions even if the mod list itself hasn't changed.

What it'll look like in BG3MM, followed by an example meta.lsx with the ExportedModMetaLsxDependencies.lsx copied over:]]
				},
				{
					type = "Image",
					image_index = 5,

				} --[[@as MazzleDocsImage]],
				{
					type = "Code",
					text = [[
<?xml version="1.0" encoding="utf-8"?>
<save>
  <version major="4" minor="0" revision="9" build="328" />
  <region id="Config">
    <node id="root">
      <children>
        <node id="Dependencies">
          <children>
            <node id="ModuleShortDesc">
              <attribute id="Folder" type="LSWString" value="Absolutes_Laboratory" />
              <attribute id="MD5" type="LSString" value="" />
              <attribute id="Name" type="FixedString" value="Absolute's Laboratory" />
              <attribute id="UUID" type="FixedString" value="a17a3a3d-5c16-404a-910a-68ae9e47f247" />
              <attribute id="Version64" type="int64" value="36873221949095936" />
            </node>
            <node id="ModuleShortDesc">
              <attribute id="Folder" type="LSWString" value="Attunement" />
              <attribute id="MD5" type="LSString" value="" />
              <attribute id="Name" type="FixedString" value="Attunement" />
              <attribute id="UUID" type="FixedString" value="7a526492-f5f4-44a0-ab25-ddcc4c6c1e7e" />
              <attribute id="Version64" type="int64" value="36451020221448192" />
            </node>
            <node id="ModuleShortDesc">
              <attribute id="Folder" type="LSWString" value="Valkrana's Skeleton Crew Feat" />
              <attribute id="MD5" type="LSString" value="" />
              <attribute id="Name" type="FixedString" value="Valkrana's Skeleton Crew Feat" />
              <attribute id="UUID" type="FixedString" value="d76ff1e5-e09e-4565-a9d2-a035037f6134" />
              <attribute id="Version64" type="int64" value="38702811445198848" />
            </node>
          </children>
        </node>
        <node id="ModuleInfo">
          <attribute id="Author" type="LSString" value="osirisofinternet" />
          <attribute id="Description" type="LSString" value="Example of how to package a Mutation Export" />
          <attribute id="Folder" type="LSString" value="Export_Mod_Example" />
		  ...
        </node>
      </children>
    </node>
  </region>
</save>]],
					centered = true
				}
			}
		},
		{
			Topic = "Mutations",
			SubTopic = "Profiles",
			content = {
				{
					type = "Heading",
					text = "Modifying Mod-Sourced Profiles/Mutations"
				},
				{
					type = "SubHeading",
					text = "Profiles"
				},
				{
					type = "Content",
					text = [[
If you want to modify a mod-sourced profile to change up the loaded mutations, you can simply copy it from the profile menu. This will clone it to your config, assigning it a new UUID.
The mutations under that profile won't be cloned - they'll still reference the original mutations so you can safely change the profile and still get updates to the mutations from the author. This does mean that any changes the author makes to their profile won't automatically update your local clone.]]
				},
				{
					type = "SubHeading",
					text = "Mutations"
				},
				{
					type = "Content",
					text = [[
There are 3 ways to clone mod-sourced mutations depending on your use-case:

1. I want all mutations from a mod, but I want to preserve their UUIDs so I can overwrite them with an updated JSON later
		Use the `Import Profile(s)` button in the Profiles settings, giving it the path to your JSON file (which you should get by unpaking the mod containing the profile) - this will import all profiles, mutations, and lists to your local config, preserving their UUIDs (which will conflict with the mod itself, so if you do this, don't have the mod loaded).
		If you make changes to some mutations and don't want them overwritten later, copy them within your config so they have new UUIDs generated

2. I want all mutations from a mod, and I don't want them to share the same UUIDs
		Right-click the mod separator text and click the button that pops up - this will clone every folder, mutation, and list under that mod to your local config, assigning new UUIDS for all.

3. I want to copy specific folders/mutations from a mod, and i don't want them to share the same UUIDs
		Right-click the specific folders/mutations and copy them to your local configs. This will not clone the underlying lists. (Lists be cloned individually in the List Designer by right-clicking them - you have to change the mutation to reference the cloned list)
]]
				}
			}
		},
		{
			Topic = "Mutations",
			SubTopic = "Profiles",
			content = {
				{
					type = "Heading",
					text = "Preparation Phase"
				},
				{
					type = "Content",
					text =
					[[The Preparation phase has a unique purpose - it runs Prep Mutations (and only these mutations), which are Mutations that only support the Prep Phase Mutator and don't support the Prep Marker Selector, with the intent being to reduce duplication of common Selectors in Main Mutations.

For example, if you find yourself defining the same set of Selectors over and over again (i.e. all bosses) + some specific additions, you can create a Prep Phase Mutation to mark all entities that are common between those Selectors, change your Main selector to just look at that marker, and simply add whatever extra selectors you want on top - e.g. All Bosses that are Humanoids, or all Devils that aren't bosses.

Lab pre-packages a number of Markers that can be used by anyone - these can't be edited or deleted, as each Marker has a UUID assigned to them that is used by the Mutator, so recreating them will cause irreversible duplication for anyone importing your profile and renaming them will just be confusing.

Prep Mutations don't support Additive behavior like Main Mutations, since that would force these mutations to assign many markers at once, instead of each prep mutation assigning a dedicated marker per the Selector criteria]]
				},
				{
					type = "Image",
					image_index = 1,
					centered = false
				} --[[@as MazzleDocsImage]],
				{
					type = "Image",
					image_index = 2,
					centered = false
				} --[[@as MazzleDocsImage]]
			}
		}
	} --[[@as MazzleDocsDocumentation]]

	SelectorInterface:generateDocs(docs)
	MutatorInterface:generateDocs(docs)

	return docs
end

---@return {[string]: MazzleDocsContentItem}
function MutationProfileManager:generateChangelog()
	return {
		["1.13.5"] = {
			type = "Bullet",
			text = {
				"Server: Allow Party Followers to be eligible for mutations when they join the party, allowing the new IsPartyFollower selector to be used. Only mutations that use the IsPartyFollower selector to run on PartyFollowers will be executed on the entity",
			}
		},
		["1.13.4"] = {
			type = "Bullet",
			text = {
				"Server: Fix undo logic not running when an active profile isn't found",
			}
		},
		["1.13.3"] = {
			type = "Bullet",
			text = {
				"Client: Fix spell list UUID's not being replaced with new UUIDs when copying all artifacts from a mod (this caused Lab to load your copied spell list when viewing the mod-sourced list that was copied, so it would appear to be out of date. You'll need to delete existing lists and recopy if you want to fix this)",
			}
		},
		["1.13.2"] = {
			type = "Bullet",
			text = {
				"Server: Remove logic to sort entities by distance from player during execution, given recent performance increases. Doesn't have that big of an impact, but on slower machines it might be preferable to save the cycles for the actual processing",
			}
		},
		["1.13.0"] = {
			type = "Bullet",
			text = {
				"Server: Change tick-latency measurement from measuring time between ticks to measuring execution time when permits are handed out - this is a more 'optimisitic' measurement, but results in massive performance improvement combined with the Selector optimizations and actually leverages the full power of the Permit system, instead of just throttling down to the minimum and staying near it. My execution times with Cahoot's profile & DIQ collection went from between 20-35 seconds to 7-9 seconds",
				"Client: Remove the Additive checkbox from Prep Marker Mutations, as they already weren't using additive behavior when processed - this is just ensuring the UI reflects the behavior"
			}
		},
		["1.12.2"] = {
			type = "Bullet",
			text = {
				"Server: Minor cleanup of transient resources used during Profile execution once execution is complete",
				"Server: Shifted execution event from LevelGameplayReady to LevelGameplayStarted, primarily for the benefit of Monster Lab, but did slightly improve execution time for Mutations as well",
				"Server: Introduced 2-tick delay for finalizing entity mutations",
			}
		},
		["1.12.0"] = {
			type = "Bullet",
			text = {
				"Client: Remove Profile Execution Status option from the General Tab",
				"Client: Add new 'Launch Profile Execution Hub' button in the Mutations tab to do what it says (accompanies the below)",
				"Server: Massive internal refactor of Profile Execution. The Profile Execution Hub window will popup automatically the first time you run a profile on this version to explain the changes and new options.",
				"Server: Removes !Lab_DupePassiveReport and !Lab_ClearEntityClasses console commands"
			}
		},
		["1.11.1"] = {
			type = "Bullet",
			text = {
				"Client: Add confirmation dialogue when deleting a profile",
				"Client: Add options to Folder context menus to expand/collapse all folders in the group"
			}
		},
		["1.10.10"] = {
			type = "Bullet",
			text = {
				"Server: Add a variety of eligibility checks to Mutation Profile execution, catching entities that aren't flagged as being able to fight but are actually, such as Bosses and NPCs lying in ambush"
			}
		},
		["1.10.8"] = {
			type = "Bullet",
			text = {
				"Server: Remove `Ext.System.ServerBoost.ReloadStatusBoosts` execution because it would remove statuses given by the game, like HARDCORE health boosts. Swapped to `Ext.System.ServerBoost.ReloadBaseBoost` and `Ext.System.ServerStatusRequest.ApplyDefault` to refresh the entity properly (hopefully)",
				"Server: Have dialogue blocker only check for the HostCharacter - improve the checks to prevent executing a profile multiple times in some instances, like the very first load of TUT_AVERNUS which loads the level twice, once pre-cutscene and once post-cutscene",
			}
		},
		["1.10.7"] = {
			type = "Bullet",
			text = {
				"Server: Directly undo mutations on chars that join the party instead of going through the whole Profile execution process (also force transient mutators to undo themselves, i.e. Abilities)",
			}
		},
		["1.10.6"] = {
			type = "Bullet",
			text = {
				"Server: Execute `Ext.System.ServerBoost.ReloadStatusBoosts` after each undo to force status boosts to reload, fixing compounding health issues even after the status is removed (have I mention I hate the health mutator? :) )"
			}
		},
		["1.10.5"] = {
			type = "Bullet",
			text = {
				"Server: Moves the application of the ABSOLUTES_LAB_UNDO_MUTATION_MARKER status _after_ the undo stage is complete for an entity"
			}
		},
		["1.10.4"] = {
			type = "Bullet",
			text = {
				"Server: Fix perma-lock caused by dialogue checks"
			}
		},
		["1.10.3"] = {
			type = "Bullet",
			text = {
				"Server: Adjust finalization stage for the Execution Status popup so it reports the right numbers",
				"Server: Applies ABSOLUTES_LAB_UNDO_MUTATION_MARKER for 1 round to each entity in the UNDO stage so other mod authors can manually remove their convoluted stats via stats"
			}
		},
		["1.10.2"] = {
			type = "Bullet",
			text = {
				"Client: Adds Finalize stage to the Profile Execution Status to give a better indication of when things are really done"
			}
		},
		["1.10.0"] = {
			type = "Bullet",
			text = {
				"Server: Excludes summons from the characters joining party event, preventing spam for things like minor illusion",
				"Client: Adds new method of cloning mutations with associated docs - see 'Modifying Mod-Sourced Profiles/Mutations'"
			}
		},
		["1.9.6"] = {
			type = "Bullet",
			text = {
				"Server: Prevents dead entities from having their mutations undone, preventing them from getting resurrected",
				"Server: Proactively removes mutations from characters when they join the party"
			}
		},
		["1.9.5"] = {
			type = "Bullet",
			text = {
				"Server: Adjust logic deferring execution during dialogue so it fires when the amount of party members < than the amount in dialogue (e.g. when you transition from ship to beach, Lae'Zal enters dialogue but leaves the party before she leaves dialogue, making it stick to +1 than it actually is)",
				"Server: Excludes entities that can't fight, are unconcious, or aren't in the party/in camp from mutations - should stop undesirable mutations",
				"Server: Swaps out liveness checks once again because this is apparently the pinnacle issue of Larian's time. Just checks if the entity's current health is > 0 this time."
			}
		},
		["1.9.4"] = {
			type = "Bullet",
			text = {
				"Server: I made the mistake of trusting Larian's function to do what it says. Using Norbyte's function instead. Dead entities will no longer be processed, preventing them from being revived",
				"Server: Defer profile execution if any party member is in dialogue to prevent the game going all spaghetti"
			}
		},
		["1.9.3"] = {
			type = "Bullet",
			text = {
				"Server: Reworks the Finalize aspect of mutators a bit, deferring their execution until all entities have finished processing their mutations to give the game time to figure out what's going on",
				"Server: No longer processes enemies that start dead - just lets them be caught by the enteringCombat logic",
				"Client: Adds text on ProfileExecutionStatus banner advising players not to perform actions in case of soft-locks on large profiles",
				"Adds missing documentation on existing console commands and on the new command, !Lab_DupePassiveReport"
			}
		},
		["1.9.2"] = {
			type = "Bullet",
			text = {
				"Fix copying from Mod-sourced profiles not copying correctly after the profile has been viewed",
			}
		},
		["1.9.0"] = {
			type = "Bullet",
			text = {
				"Execute a Ext.System.ServerStats.ReloadStats system call when all undo operations are complete for an entity, ensuring _all_ base values are reset to their intended Vanilla values",
				"Profile UI: Refactor the Folder portion of the UI, making it more convenient and space-efficient, especially when mods that provide mutations are loaded",
				"Profile UI: Remove Swapping behavior when drag/dropping rules into a Profile - will just move existing rules up/down as appropriate",
				"Profile UI: Fully fix reordering rules by specifying the rule number in the input",
				"Profile UI: Fix popup menu not appearing when right-clicking buttons in the active profile list",
			}
		},
		["1.8.4"] = {
			type = "Bullet",
			text = {
				"Fix mutations that somehow had internal proxy-specific fields in them from exporting/importing those fields, which caused undesirable behavior",
				"Adds Priority information to the Mutators in the generated Mermaid Diagram",
				"Fixes Diagram Generation Popup in the Mutations tab in the Inspector not having the correct height, giving the impression no diagram was generated"
			}
		},
		["1.8.2"] = {
			type = "Bullet",
			text = {
				"Fixed some runtime errors when exporting a profile that has non-existent mutators",
				"Server: Swaps from bulk indexing to lazy-loading the Progression indexing for Spell + Passive List Mutators, resulting in a meaningful performance increase especially for profiles with limited lists"
			}
		},
		["1.8.1"] = {
			type = "Bullet",
			text = {
				"Some minor performance/QOL cleanup in the Profile Executor",
				"Add confirmation behavior when deleting a folder"
			}
		},
		["1.8.0"] = {
			type = "Bullet",
			text = {
				"Exports now save to the Mutations folder, under the same ExportedProfiles folder as before",
				"Reworks the Profile Executor a bit to be more robust, have more logs, and account for Monster Lab profile",
				"Fixes the OnCombatEntered logic so loading a save that's mid-combat doesn't double/triple mutate entities"
			}
		},
		["1.7.2"] = {
			type = "Bullet",
			text = {
				"Server: Actually fix ProfileExecutor reprocessing all entities when a unprocessed entity enters combat q_q",
			}
		},
		["1.7.1"] = {
			type = "Bullet",
			text = {
				"Server: Fix ProfileExecutor duplicating it's completion checks",
				"Server: Fix ProfileExecutor reprocessing all entities when a unprocessed entity enters combat",
				"Restructures the Profile Manager column to be more user-friendly and properly adjust to mutation widths",
				"Fixed export utility not accounting for skipped indexes",
				"Add robust fallbacks in case a mutation that once existed and is present in a profile was removed outside of Lab (i.e. relying on a mod-sourced mutation)",
				"Adds unrecoverable error reporting to the Profile Execution Status Window",
				"Massively improve the accuracy of the Execution Status report on profiles with a large amount of mutations, and misc improvements to the window",
				"Adds two new incremental collapse/expand buttons for the Profile Manager column to help people on stupidly huge monitors with odd scaling behavior + with stupidly long mutation names"
			}
		},
		["1.7.0"] = {
			type = "Bullet",
			text = {
				"Rename 'Additive' to 'Composable' in the Docs to avoid the obvious, but unfortunately incorrect, assumption",
				"Increased static width of the profile rule manager column",
				"Fixes columns expanding to a smaller width than they should",
				"Fix profile section not scrolling like Folder view",
				"Doesn't execute the Mutation Profile against enemies that aren't on the same Game Level as the host character",
				"Creates a 5 rotating backup config.json whenever the real one gets written to (with a buffer of 60 seconds between each backup update)",
				"Adds a visual Profile Execution Status report while profile is executing - modes are configured in the General MCM tab",
				"Changes up the Profile Rules buttons to swap with each other or shunt existing buttons down when dragged and dropped, depending on where the button was dragged from",
				"Adds a new popup menu for Mutations to remove the mutation from the active Profile, if it's not a mod-added profile",
				"Maintains the currently selected Mutator in the Sidebar view mode when changing Mutation or Mutator view mode",
				"Adds new server-only console command !Lab_ClearEntityClasses to reset all entities (run this, disable your profile, save, reload, enable profile, save, reload)",
				"Adds the !Lab_GenerateMutationDiagram <entityId> server-only console command and a button in the Mutation tab of the Inspector to generate a Mermaid Diagram representing the mutation state flow of the specified entity against the currently active (or default) profile",
				"Adds client only console command Lab_MetaBlock <UUID LIST> to allow creating dependency nodes from any loaded mod(s)",
			}
		},
		["1.6.0"] = {
			type = "Bullet",
			text = {
				"Make Folders + Mutations sort alphabetically",
				"Introduces a 50ms delay on mutator application to allow the game enough time to finish processing the undo mutators",
				"Adds ability to save/load presets for selectors and mutators (needs dependency checks)",
				"Introduces PrepPhase Mutators + Selectors, greatly simplifying complex mutations in a two-phase approach",
				"Add Status and Passive lists to export/import functionality and adds mod integration to their mutators",
				"Adds show/hide to prep phase and main phase mutation sections",
				"Documents the Mod that a folder is sourced from in the json export for validation purposes",
				"Allows saving selectors and mutators into loadable presets",
			}
		}
	} --[[@as {[string]: MazzleDocsContentItem}]]
end
