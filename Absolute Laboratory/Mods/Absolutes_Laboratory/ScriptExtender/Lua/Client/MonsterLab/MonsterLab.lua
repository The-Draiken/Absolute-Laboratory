Ext.Vars.RegisterModVariable(ModuleUUID, "ActiveMonsterLabProfile", {
	Server = true,
	Client = true,
	WriteableOnServer = true,
	WriteableOnClient = true,
	SyncToClient = true,
	SyncToServer = true,
	SyncOnWrite = true
})

Ext.Vars.RegisterModVariable(ModuleUUID, "HasDisabledMonsterLabProfiles", {
	Server = true,
	Client = true,
	WriteableOnServer = true,
	WriteableOnClient = true,
	SyncToClient = true,
	SyncToServer = true,
	SyncOnWrite = true
})


Ext.Require("Client/MonsterLab/EncounterDesigner.lua")
Ext.Require("Client/MonsterLab/EntityCustomizations.lua")
Ext.Require("Client/MonsterLab/ServerHelpers.lua")
Ext.Require("Client/MonsterLab/MonsterLabEntityCreationForm.lua")

MonsterLab = {
	config = MonsterLabConfigurationProxy,
	activeRuleset = "Base",
	---@param newProfile (string|boolean)?
	---@return string?
	activeProfile = function(newProfile)
		if newProfile or newProfile == false then
			Ext.Vars.GetModVariables(ModuleUUID).ActiveMonsterLabProfile = (type(newProfile) == "string" and newProfile or nil)
			Ext.Vars.GetModVariables(ModuleUUID).HasDisabledMonsterLabProfiles = not type(newProfile) == "string"
		end

		return Ext.Vars.GetModVariables(ModuleUUID).ActiveMonsterLabProfile
	end
}

local hasInitialized

if Ext.Mod.IsModLoaded("755a8a72-407f-4f0d-9a33-274ac0f0b53d") then
	Mods.BG3MCM.IMGUIAPI:InsertModMenuTab(ModuleUUID, "Monster Lab",
		--- @param tabHeader ExtuiTabItem
		function(tabHeader)
			if not hasInitialized then
				MonsterLab:init(tabHeader)
				hasInitialized = true
			end
		end)
end

---@param parent ExtuiTreeParent
function MonsterLab:init(parent)
	self.popup = Styler:Popup(parent)

	local layoutTable = Styler:TwoColumnTable(parent, "MonsterLab")
	layoutTable.Resizable = false
	layoutTable.Borders = false

	local layoutRow = layoutTable:AddRow()

	self.encounterFoldersSidebar = layoutRow:AddCell():AddChildWindow("folders")
	self.designerSection = layoutRow:AddCell()

	self:buildFolderView()
end

function MonsterLab:buildProfileView()
	---@type fun()
	local renderProfile

	local profileTable = Styler:MiddleAlignedColumnLayout(self.encounterFoldersSidebar, function(ele)
		Styler:CheapTextAlign("Profiles", ele, "Big").SamePosition = true

		local sIndex = 1
		local opt = { "Disabled" }

		for profileId, profile in TableUtils:OrderedPairs(self.config.profiles, function(_, value)
			return value.name
		end) do
			table.insert(opt, profile.name .. (profile.modId and "(M)" or ""))
			if self.activeProfile() == profileId then
				sIndex = #opt
			end
		end

		local viewProfileButton = Styler:ImageButton(ele:AddImageButton("seeProfile", "ico_concentration", Styler:ScaleFactor({ 32, 32 })))

		local profileCombo = ele:AddCombo("##profiles")
		profileCombo.SameLine = true
		profileCombo.Options = opt
		profileCombo.WidthFitPreview = true
		profileCombo.SelectedIndex = sIndex - 1

		local manageProfileButton = Styler:ImageButton(ele:AddImageButton("Manage", "ico_edit_d", Styler:ScaleFactor({ 32, 32 })))
		manageProfileButton.SameLine = true

		viewProfileButton.OnClick = function()
			renderProfile()
		end

		profileCombo.OnChange = function()
			local selectedName = profileCombo.Options[profileCombo.SelectedIndex + 1]

			if selectedName == "Disabled" then
				self.activeProfile(false)
				Helpers:KillChildren(self.designerSection)
			else
				local isModProfile = selectedName:sub(#selectedName - 2) == "(M)"

				local activeProfile = self.activeProfile()

				self.activeProfile(TableUtils:IndexOf(self.config.profiles, function(value)
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
				end))

				if self.activeProfile() ~= activeProfile then
					renderProfile()
				end
			end
		end

		manageProfileButton.OnClick = function()
			Helpers:KillChildren(self.popup)
			self.popup:Open()

			FormBuilder:CreateForm(self.popup:AddMenu("Create New Profile"), function(formResults)
					---@type MonsterLabProfile
					local profile = {
						name = formResults.Name,
						description = formResults.Description,
						encounters = {}
					}

					self.config.profiles[FormBuilder:generateGUID()] = profile
					self:buildFolderView()
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
				})

			---@type ExtuiMenu
			local importMenu = self.popup:AddMenu("Import Profile(s)")

			local importGroup = importMenu:AddGroup("Import")
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
				local importFunc, mods, failedDependencies, showDepWindowFunc = MonsterLabExportImport:importProfile(FileUtils:LoadTableFile(fileNameInput.Text))
				if not importFunc then
					self:buildFolderView()
					Styler:CheapTextAlign("Imported!", importGroup)
				else
					errorGroup.Visible = true
					Helpers:KillChildren(errorGroup)

					errorGroup:AddSeparatorText("Missing Dependencies!"):SetColor("Separator", { 1, 0, 0, 0.4 })
					Styler:MiddleAlignedColumnLayout(errorGroup, function(ele)
						local continueButton = ele:AddButton("Continue")
						continueButton:Tooltip():AddText("\t This will remove all items that depend on a missing mod while importing - it will not affect the file")
						continueButton.OnClick = function()
							importFunc()
							self:buildFolderView()
							Styler:CheapTextAlign("Imported!", importGroup)
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

			if ConfigurationStructure.config.monsterLab.profiles() then
				---@type ExtuiMenu
				local exportMenu = self.popup:AddMenu("Export")
				local checkboxGroup = exportMenu:AddGroup("")
				for profileId, profile in TableUtils:OrderedPairs(ConfigurationStructure.config.monsterLab.profiles, function(key, value)
					return value.name
				end) do
					checkboxGroup:AddCheckbox(profile.name).UserData = profileId
				end

				exportMenu:AddSelectable("Export").OnClick = function()
					local profiles = {}
					for _, child in pairs(checkboxGroup.Children) do
						if child.Checked then
							table.insert(profiles, child.UserData)
						end
					end
					MonsterLabExportImport:exportProfile(false, table.unpack(profiles))
				end

				exportMenu:AddSelectable("Export For Mod").OnClick = function()
					local profiles = {}
					for _, child in pairs(checkboxGroup.Children) do
						if child.Checked then
							table.insert(profiles, child.UserData)
						end
					end
					MonsterLabExportImport:exportProfile(true, table.unpack(profiles))
				end
			end

			local modGroups = {
				["user"] = self.popup:AddGroup("")
			}
			modGroups["user"]:AddSeparatorText("Your Profile(s)"):SetStyle("SeparatorTextAlign", 0.5)

			for profileId, profile in TableUtils:OrderedPairs(self.config.profiles, function(key, value)
				return (value.modId and Ext.Mod.GetMod(value.modId).Info.Name or "") .. value.name
			end) do
				if profile.modId and not modGroups[profile.modId] then
					modGroups[profile.modId] = self.popup:AddGroup(profile.modId)
					modGroups[profile.modId]:AddSeparatorText(Ext.Mod.GetMod(profile.modId).Info.Name):SetStyle("SeparatorTextAlign", 0.5)
				end

				---@type ExtuiMenu
				local profileMenu = modGroups[profile.modId or "user"]:AddMenu(("%s%s"):format(profile.name, self.config.settings.defaultActiveProfile == profileId and " (D)" or ""))
				-- If groups only contain a menu, they resize indefinitely. They need some non-parent element inside em with a concrete size
				-- Putting it once above wasn't working for some reason
				modGroups[profile.modId or "user"]:AddDummy(0, 0)

				profileMenu:AddSelectable(("%s As Default"):format(self.config.settings.defaultActiveProfile == profileId and "Unset" or "Set")).OnClick = function()
					if self.config.settings.defaultActiveProfile == profileId then
						self.config.settings.defaultActiveProfile = nil
					else
						self.config.settings.defaultActiveProfile = profileId
					end
				end
				profileMenu:AddSelectable("Clone").OnClick = function()
					local profileCopy = TableUtils:DeeplyCopyTable(profile._real or profile)
					if TableUtils:IndexOf(self.config.profiles, function(value)
							return value.name == profile.name and not value.modId
						end)
					then
						profileCopy.name = profileCopy.name .. " (Copy)"
					end

					self.config.profiles[FormBuilder:generateGUID()] = profileCopy
					self:buildFolderView()
				end

				if not profile.modId then
					FormBuilder:CreateForm(profileMenu:AddMenu("Edit"), function(formResults)
							profile.name = formResults.Name
							profile.description = formResults.Description

							self:buildFolderView()
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
							}
						})

					profileMenu:AddSelectable("Export").OnClick = function()
						MonsterLabExportImport:exportProfile(false, profileId)
					end

					profileMenu:AddSelectable("Export For Mod").OnClick = function()
						MonsterLabExportImport:exportProfile(true, profileId)
					end

					---@param select ExtuiSelectable
					profileMenu:AddSelectable("Delete", "DontClosePopups").OnClick = function(select)
						if select.Label ~= "Delete" then
							profile.delete = true
							if self.activeProfile() == profileId then
								self.activeProfile(false)
							end

							self:buildFolderView()
						else
							select.Label = "Are You Sure?"
							select.DontClosePopups = false
							Styler:Color(select, "ErrorText")
						end
					end
				end
			end
		end
	end)
	MazzleDocs:addDocButton(profileTable.Children[1].Children[1])
	self.encounterFoldersSidebar:AddNewLine()

	renderProfile = function()
		Helpers:KillChildren(self.designerSection)

		if self.activeProfile() and self.config.profiles[self.activeProfile()] then
			---@type MonsterLabProfile
			local profile = self.config.profiles[self.activeProfile()]

			Styler:CheapTextAlign("Active Profile: " .. profile.name, self.designerSection, "Large")

			if profile.description and profile.description ~= "" then
				Styler:CheapTextAlign(profile.description, self.designerSection)
			end

			if profile.modId then
				local mod = Ext.Mod.GetMod(profile.modId).Info
				Styler:Color(Styler:CheapTextAlign("MOD-SOURCED PROFILE - You can view, but not edit", self.designerSection, "Large"), "ErrorText")
				Styler:CheapTextAlign(("Mod: %s (v%s) by %s"):format(mod.Name, table.concat(mod.ModVersion, "."), mod.Author), self.designerSection)
			end

			local levelTable = self.designerSection:AddTable("levels", 1)
			levelTable.NoSavedSettings = true
			levelTable.RowBg = true
			levelTable.Resizable = false
			levelTable:SetColor("TableRowBg", Styler:ConvertRGBAToIMGUI({ 34, 34, 34, 0.6 }))
			levelTable:SetColor("TableRowBgAlt", Styler:ConvertRGBAToIMGUI({ 22, 22, 22, 0.96 }))

			-- Only using this to determine the width of the container, as it keeps scaling the vertical dimension infinitely
			local cardsWindow = self.designerSection:AddChildWindow("Combat Group Cards")
			cardsWindow.AlwaysAutoResize = true
			cardsWindow.Size = { 0, 1 }

			local cardColours = {
				{ 255, 0,   0,   0.5 },
				{ 0,   255, 0,   0.5 },
				{ 0,   0,   255, 0.5 },
				{ 255, 0,   255, 0.5 },
				{ 255, 255, 0,   0.5 },
				{ 0,   255, 255, 0.5 },
			}

			-- Giving the cardsWindow time to resize itself
			Ext.Timer.WaitFor(50, function()
				for l, level in ipairs(EntityRecorder.Levels) do
					local row = levelTable:AddRow():AddCell()

					row:AddDummy(Styler:ScaleFactor() * 50, 0)
					local title = Styler:ScaledFont(row:AddText(level), "Large")
					title.SameLine = true

					---@class ML_CombatGroup
					---@field profileEncounter MonsterLabProfileEncounterEntry
					---@field encounter MonsterLabEncounter

					---@type ML_CombatGroup[]
					local combatGroups = {}

					for k, profileEncounter in pairs(profile.encounters) do
						local encounter = self.config.folders[profileEncounter.folderId]
							and self.config.folders[profileEncounter.folderId].encounters[profileEncounter.encounterId]

						if encounter then
							if encounter.gameLevel == level then
								table.insert(combatGroups, {
									profileEncounter = profileEncounter,
									encounter = encounter
								})
							end
						else
							profileEncounter.delete = true
							profile.encounters[k] = nil
						end
					end
					TableUtils:ReindexNumericTable(profile.encounters)

					local maxRowSize = math.floor(cardsWindow.LastSize[1] / (Styler:ScaleFactor() * 300))
					local entriesPerColumn = math.floor(TableUtils:CountElements(combatGroups) / maxRowSize)
					entriesPerColumn = entriesPerColumn > 0 and entriesPerColumn or 1
					local layoutTable = row:AddTable("cards", maxRowSize)

					local encounterManagerGroup = row:AddGroup("encounterManager")
					encounterManagerGroup.Visible = false

					local cardRow = layoutTable:AddRow()

					for _ = 1, maxRowSize do
						cardRow:AddCell()
					end

					local counter = 0

					for index, combatGroup in TableUtils:OrderedPairs(combatGroups, function(key, value)
						return TableUtils:CountElements(value)
					end) do
						counter = counter + 1

						---@type ExtuiChildWindow
						local combatGroupCard = cardRow.Children[(counter % maxRowSize) > 0 and (counter % maxRowSize) or maxRowSize]:AddChildWindow(index)
						combatGroupCard.Size = Styler:ScaleFactor({ 300, (TableUtils:CountElements(combatGroup.encounter.entities) + 1.5) * 40 })

						local groupTable = combatGroupCard:AddTable("chlidTable", 1)
						groupTable.Borders = true
						groupTable:SetColor("TableBorderStrong", Styler:ConvertRGBAToIMGUI(cardColours[(counter % (#cardColours - (maxRowSize % 2 == 0 and 1 or 0))) + 1]))

						local headerCell = groupTable:AddRow():AddCell()

						if not profile.modId then
							local removeEncounterButton = Styler:ImageButton(headerCell:AddImageButton("delete" .. index, "ico_close_d", Styler:ScaleFactor({ 24, 24 })))
							removeEncounterButton:Tooltip():AddText("\t  Removes this encounter from this Profile - will not delete the encounter itself")
							removeEncounterButton.OnClick = function()
								local encounterProfileIndex = TableUtils:IndexOf(profile.encounters, function(value)
									return value.encounterId == combatGroup.profileEncounter.encounterId and value.folderId == combatGroup.profileEncounter.folderId
								end)
								profile.encounters[encounterProfileIndex].delete = true
								TableUtils:ReindexNumericTable(profile.encounters)
								renderProfile()
							end
						end

						local modName = combatGroup.encounter.modId and Ext.Mod.GetMod(combatGroup.encounter.modId).Info.Name
						local titleText = headerCell:AddTextLink(("%s (%s)%s"):format(
							combatGroup.encounter.name,
							self.config.folders[combatGroup.profileEncounter.folderId].name,
							modName and ("\nMod: " .. modName:sub(0, 10)) or ""))
						titleText.SameLine = true
						titleText.UserData = "EnableForMods"

						titleText:SetColor("TextLink", { 0.86, 0.79, 0.68, 0.78 })
						titleText.OnClick = function()
							if encounterManagerGroup.Visible == false then
								encounterManagerGroup.Visible = true
								self:buildEncounterView(combatGroup.encounter, encounterManagerGroup, combatGroup.profileEncounter)
							else
								Helpers:KillChildren(encounterManagerGroup)
								encounterManagerGroup.Visible = false
							end
						end

						for entityId, entityRecord in TableUtils:OrderedPairs(combatGroup.encounter.entities, function(key, value)
							return value.displayName
						end) do
							local entityRow = groupTable:AddRow():AddCell()

							---@type CharacterTemplate
							local template = Ext.ClientTemplate.GetTemplate(entityRecord.template)

							local image = entityRow:AddImage(entityRecord.icon or (template and template.Icon) or "Item_Unknown", { 32, 32 })
							if image.ImageData.Icon == "" then
								image:Destroy()
								entityRow:AddImage("Item_Unknown", Styler:ScaleFactor({ 32, 32 }))
							end

							entityRow:AddText(entityRecord.displayName).SameLine = true
						end
					end

					counter = counter + 1

					if not profile.modId then
						---@type ExtuiChildWindow
						local addGroupCard = cardRow.Children[(counter % maxRowSize) > 0 and (counter % maxRowSize) or maxRowSize]:AddGroup("Add Group")

						local groupTable = addGroupCard:AddTable("chlidTable", 1)
						groupTable.Borders = true
						groupTable:SetColor("TableBorderStrong", Styler:ConvertRGBAToIMGUI(cardColours[(counter % (#cardColours - (maxRowSize % 2 == 0 and 1 or 0))) + 1]))

						---@type ExtuiSelectable
						local addEncounterSelect = groupTable:AddRow():AddCell():AddSelectable("Add Encounter")
						addEncounterSelect:SetStyle("SelectableTextAlign", 0.5)
						addEncounterSelect.Selected = true
						addEncounterSelect.OnClick = function()
							addEncounterSelect.Selected = true
							Helpers:KillChildren(self.popup)
							self.popup:Open()

							for folderId, folder in TableUtils:OrderedPairs(self.config.folders,
								function(key, value)
									return value.name
								end,
								function(key, value)
									return TableUtils:IndexOf(value.encounters, function(value)
										return value.gameLevel == level
									end) ~= nil
								end)
							do
								local folderWindow = self.popup:AddChildWindow(folderId)
								folderWindow.NoSavedSettings = true

								Styler:CheapTextAlign(folder.name, folderWindow)

								local width, height = Styler:calculateTextDimensions(folder.name)
								height = height * 2

								for encounterId, encounter in TableUtils:OrderedPairs(folder.encounters,
									function(key, value)
										return value.name
									end,
									function(key, value)
										return value.gameLevel == level and not TableUtils:IndexOf(profile.encounters, function(value)
											return value.folderId == folderId and value.encounterId == key
										end)
									end)
								do
									local encounterName = string.format("%s%s", encounter.name,
										encounter.modId and " (" .. Ext.Mod.GetMod(encounter.modId).Info.Name .. ")"
										or "")

									local optWidth, optHeight = Styler:calculateTextDimensions(encounterName)

									if optWidth > width then
										width = optWidth
									end
									height = height + optHeight

									folderWindow:AddSelectable(encounterName, "DontClosePopups").OnClick = function()
										table.insert(profile.encounters, {
											encounterId = encounterId,
											folderId = folderId
										} --[[@as MonsterLabProfileEncounterEntry]])

										renderProfile()
									end
								end

								if #folderWindow.Children == 1 then
									folderWindow:Destroy()
								else
									folderWindow.Size = { width, height }
								end
							end

							if #self.popup.Children == 0 then
								Styler:Color(self.popup:AddText("No Encounters Available For Level " .. level), "ErrorText")
							end
						end
					end
				end

				if profile.modId then
					Styler:disableNonNavigatableElements(self.designerSection)
				end
			end)
		end
	end
end

local waitedOnce = false
local folderState = {}

function MonsterLab:buildFolderView()
	if not waitedOnce and not self.activeProfile() then
		waitedOnce = true
		Ext.Timer.WaitFor(200, function()
			self:buildFolderView()
		end)
	end

	Helpers:KillChildren(self.encounterFoldersSidebar)

	self:buildProfileView()

	local groups = { ["User"] = self.encounterFoldersSidebar:AddGroup("user") }

	local userSep = groups["User"]:AddSeparatorText("Your Encounters (?)")
	userSep:SetStyle("SeparatorTextAlign", 0.5)
	userSep:Tooltip():AddText(
		"\t Right-click on folders or mutations under any user or mod section to manage them. Drag and Drop mutations into the profile section to add them to a profile")

	local longestText = 0

	for folderId, folder in TableUtils:OrderedPairs(self.config.folders, function(key, value)
		return not value.modId and ("1" .. value.name) or ("2" .. Ext.Mod.GetMod(value.modId).Info.Name .. value.name)
	end) do
		local parent = groups[folder.modId or "User"]
		if not parent then
			groups[folder.modId] = self.encounterFoldersSidebar:AddGroup(folder.modId)
			parent = groups[folder.modId]
			local sep = parent:AddSeparatorText(Ext.Mod.GetMod(folder.modId).Info.Name .. " ( ? )")
			sep:Tooltip():AddText("\t  Right-Click this if you want to copy all profiles, encounters, and rulesets from this mod")
			sep.OnRightClick = function()
				self.popup:Open()
				Helpers:KillChildren(self.popup)

				---@type ExtuiSelectable
				local folderSelect = self.popup:AddSelectable("Clone All Profiles, Encounters, and Rulesets?", "DontClosePopups")
				folderSelect:Tooltip():AddText([[
	Clones all profiles, encounters, and rulesets to your local config, generating new UUIDs for them. If folders already exist with the same name, '(COPY)' will be appended to them.
If you want to preserve the original UUIDs so you can overwrite them with a new version of the JSON file, use the Import Profile option in the Profiles settings.]])

				folderSelect.OnClick = function()
					if folderSelect.Label ~= "Clone All Profiles, Encounters, and Rulesets?" then
						---@type MonsterLabConfig
						local modConfig = TableUtils:DeeplyCopyTable(MonsterLabModProxy:importMonsterLab(folder.modId))

						local serialized = Ext.Json.Stringify(modConfig, {
							Beautify = false,
							MaxDepth = 1000,
							AvoidRecursion = false,
						})

						for folderId in pairs(modConfig.folders) do
							serialized = serialized:gsub(Helpers:SanitizeStringForFind(folderId), Ext.Utils.GenerateGuid())
						end

						for profileId in pairs(modConfig.profiles) do
							serialized = serialized:gsub(Helpers:SanitizeStringForFind(profileId), Ext.Utils.GenerateGuid())
						end

						for rulesetId in pairs(modConfig.rulesets) do
							serialized = serialized:gsub(Helpers:SanitizeStringForFind(rulesetId), Ext.Utils.GenerateGuid())
						end

						modConfig = { ["monsterLab"] = Ext.Json.Parse(serialized) }
						TableUtils:ConvertStringifiedNumberIndexes(modConfig)

						local depFunc = MonsterLabExportImport:importProfile(modConfig)
						if depFunc then
							depFunc()
						end
						self:buildFolderView()
					else
						folderSelect.Label = "Are You Sure?"
						folderSelect.DontClosePopups = false
					end
				end
			end
			sep:SetStyle("SeparatorTextAlign", 0.5)
		end

		local folderSelect = parent:AddTree(folder.name)
		folderSelect.IDContext = folderId
		folderSelect:SetOpen(folderState[folderId] == true, "Always")
		folderSelect.Selected = folderState[folderId] == true
		folderSelect.SpanFullWidth = true
		Styler:ScaledFont(folderSelect, "Big")

		parent:AddDummy(50, 0)
		local header = parent:AddGroup("encounters")
		header.IDContext = folderId
		header.SameLine = true
		header.Visible = folderSelect.Selected

		folderSelect.OnClick = function()
			header.Visible = not header.Visible
			folderState[folderId] = header.Visible
		end

		folderSelect.OnRightClick = function()
			Helpers:KillChildren(self.popup)
			self.popup:Open()

			self.popup:AddSelectable("Copy Folder").OnClick = function()
				local folderCopy = {
					name = TableUtils:IndexOf(ConfigurationStructure.config.monsterLab.folders, function(value)
							return value.name == folder.name
						end)
						and (folder.name .. " (COPY)")
						or folder.name,
					description = folder.description,
					encounters = TableUtils:DeeplyCopyTable(folder.encounters)
				} --[[@as MonsterLabFolder]]

				for _, encounter in pairs(folderCopy.encounters) do
					encounter.modId = nil
				end

				ConfigurationStructure.config.monsterLab.folders[Ext.Utils.GenerateGuid()] = folderCopy
				self:buildFolderView()
			end

			if not folder.modId then
				FormBuilder:CreateForm(self.popup:AddMenu("Create Encounter"), function(formResults)
					local encounter = TableUtils:DeeplyCopyTable(ConfigurationStructure.DynamicClassDefinitions.monsterLab.encounter)
					encounter.name = formResults.Name
					encounter.description = formResults.Description
					encounter.combatGroupId = FormBuilder:generateGUID()
					encounter.faction = "64321d50-d516-b1b2-cfac-2eb773de1ff6"
					folder.encounters[FormBuilder:generateGUID()] = encounter
					self:buildFolderView()
				end, {
					{
						label = "Name",
						type = "Text",
						errorMessageIfEmpty = "Required Field"
					},
					{
						label = "Description",
						type = "Multiline"
					}
				})

				FormBuilder:CreateForm(self.popup:AddMenu("Edit"), function(formResults)
						folder.name = formResults.Name
						folder.description = formResults.Description

						self:buildFolderView()
					end,
					{
						{
							label = "Name",
							type = "Text",
							errorMessageIfEmpty = "Name is required",
							defaultValue = folder.name
						},
						{
							label = "Description",
							type = "Multiline",
							defaultValue = folder.description
						}
					})

				---@param select ExtuiSelectable
				self.popup:AddSelectable("Delete", "DontClosePopups").OnClick = function(select)
					if select.Label ~= "Delete" then
						folder.delete = true
						self:buildFolderView()
					else
						select.DontClosePopups = false
						select.Label = "Are You Sure?"
						Styler:Color(select, "ErrorText")
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

		local width = Styler:calculateTextDimensions(folder.name)
		longestText = width > longestText and width or longestText

		for encounterId, encounter in TableUtils:OrderedPairs(folder.encounters, function(key, value)
			return value.name
		end) do
			local width = Styler:calculateTextDimensions(folder.name)
			longestText = width > longestText and width or longestText

			---@type ExtuiSelectable
			local encounterSelect = header:AddSelectable(encounter.name .. "##" .. encounterId)
			encounterSelect.IDContext = encounterId
			encounterSelect.OnClick = function()
				encounterSelect.Selected = false
				self:buildEncounterView(encounter, nil, {
					folderId = folderId,
					encounterId = encounterId
				})
			end

			if not folder.modId then
				encounterSelect.OnRightClick = function()
					Helpers:KillChildren(self.popup)
					self.popup:Open()

					---@type ExtuiMenu
					local editMenu = self.popup:AddMenu("Edit")

					FormBuilder:CreateForm(editMenu, function(formResults)
							encounter.name = formResults.Name
							encounter.description = formResults.Description

							self:buildFolderView()
						end,
						{
							{
								label = "Name",
								type = "Text",
								errorMessageIfEmpty = "Name is required",
								defaultValue = encounter.name
							},
							{
								label = "Description",
								type = "Multiline",
								defaultValue = encounter.description
							}
						})

					self.popup:AddSelectable("Copy").OnClick = function()
						---@type MonsterLabEncounter
						local encounterCopy = TableUtils:DeeplyCopyTable(encounter._real)
						encounterCopy.name = encounterCopy.name .. " (Copy)"

						folder.encounters[FormBuilder:generateGUID()] = encounterCopy
						self:buildFolderView()
					end

					if TableUtils:CountElements(self.config.folders) > 1 then
						---@type ExtuiMenu
						local moveMenu = self.popup:AddMenu("Move To Folder")
						for _, otherFolder in TableUtils:OrderedPairs(self.config.folders, function(key, value)
								return value.name
							end,
							function(key, value)
								return key ~= folderId and not value.modId
							end) do
							moveMenu:AddSelectable(otherFolder.name).OnClick = function()
								---@type MonsterLabEncounter
								local encounterCopy = TableUtils:DeeplyCopyTable(encounter._real)

								if TableUtils:IndexOf(otherFolder.encounters, function(value)
										return value.name == encounterCopy.name
									end) then
									encounterCopy.name = encounterCopy.name .. " (Copy)"
								end

								otherFolder.encounters[encounterId] = encounterCopy
								encounter.delete = true

								self:buildFolderView()
							end
						end
					end

					self.popup:AddSelectable("Delete", "DontClosePopups").OnClick =
					---@param select ExtuiSelectable
						function(select)
							if select.Label ~= "Delete" then
								encounter.delete = true
								self:buildFolderView()
							else
								select.Label = "Are You Sure?"
								Styler:Color(select, "ErrorText")
								select.DontClosePopups = false
							end
						end
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
				self.config.folders[FormBuilder:generateGUID()] = {
					name = formResults.Name,
					description = formResults.Description,
					encounters = {}
				} --[[@as MonsterLabFolder]]

				self:buildFolderView()
			end,
			{
				{
					label = "Name",
					type = "Text",
					errorMessageIfEmpty = "Name is required"
				},
				{
					label = "Description",
					type = "Multiline"
				}
			})
	end

	self.encounterFoldersSidebar.Size = { math.max(300 * Styler:ScaleFactor(), longestText), 0 }
end

---@param encounter MonsterLabEncounter
---@param parent ExtuiTreeParent?
---@param encounterMeta MonsterLabProfileEncounterEntry
function MonsterLab:buildEncounterView(encounter, parent, encounterMeta)
	local parent = parent or self.designerSection
	Helpers:KillChildren(parent)

	Styler:MiddleAlignedColumnLayout(parent, function(ele)
		Styler:CheapTextAlign(encounter.name, ele).Font = "Big"

		if encounter.description then
			Styler:CheapTextAlign(encounter.description, parent)
		end

		if encounter.modId then
			Styler:Color(Styler:CheapTextAlign("MOD-SOURCED ENCOUNTER", parent, "Large"), "ErrorText")
			Styler:Color(Styler:CheapTextAlign("You can view, but not edit", parent, "Large"), "ErrorText")

			Styler:disableNonNavigatableElements(parent)
		end
	end)

	---@type fun()
	local buildEncounter

	Styler:MiddleAlignedColumnLayout(parent, function(ele)
		self:ManageRulesets(ele:AddGroup("Rulesets"), function(...)
			buildEncounter(...)
		end)
	end)

	local encounterGroup = parent:AddGroup("Encounter")

	local lastSelectedEntity
	---@type ExtuiImage?
	local activeSelectedIcon

	---@param rulesetToCopyTo string?
	---@param rulesetToCopyFrom string?
	buildEncounter = function(rulesetToCopyTo, rulesetToCopyFrom)
		activeSelectedIcon = nil

		Helpers:KillChildren(encounterGroup)
		local layoutTable = Styler:TwoColumnTable(encounterGroup, "layout")
		layoutTable.Resizable = false
		local layoutRow = layoutTable:AddRow()

		local entitySidebar = layoutRow:AddCell()
		local designerModeButton = entitySidebar:AddButton("Launch Designer Mode")
		designerModeButton.UserData = "EnableForMods"
		designerModeButton.OnClick = function()
			EncounterDesigner:buildDesigner(encounter, encounterMeta._real or encounterMeta)
		end
		local designerSection = layoutRow:AddCell()

		for id, entity in TableUtils:OrderedPairs(encounter.entities, function(key, value)
			return value.displayName
		end) do
			if rulesetToCopyTo and rulesetToCopyFrom then
				if entity.rulesetModifiers[rulesetToCopyFrom] then
					---@type MonsterLab_RulesetRule
					local rulesetCopy = TableUtils:DeeplyCopyTable(entity.rulesetModifiers[rulesetToCopyFrom]._real)

					if entity.rulesetModifiers[rulesetToCopyTo] then
						entity.rulesetModifiers[rulesetToCopyTo].delete = true
						entity.rulesetModifiers[rulesetToCopyTo] = nil
					end

					entity.rulesetModifiers[rulesetToCopyTo] = rulesetCopy
				end
			end

			if not entity.rulesetModifiers[self.activeRuleset] then
				entity.rulesetModifiers[self.activeRuleset] = TableUtils:DeeplyCopyTable(ConfigurationStructure.DynamicClassDefinitions.monsterLab.rulesetModifiers)
			end

			local entityGroup = entitySidebar:AddGroup(id)
			if not encounter.modId then
				local deleteButton = Styler:ImageButton(entityGroup:AddImageButton("delete" .. id, "ico_red_x", Styler:ScaleFactor({ 16, 16 })))
				deleteButton.OnClick = function()
					encounter.entities[id].delete = true
					Helpers:KillChildren(designerSection)
					buildEncounter()
				end
			end

			---@type CharacterTemplate
			local characterTemplate = Ext.ClientTemplate.GetTemplate(entity.template)

			if not characterTemplate then
				entityGroup:AddImage("Item_Unknown", { 48, 48 }).SameLine = not encounter.modId
			else
				local icon = entityGroup:AddImage(entity.icon or characterTemplate.Icon, { 48, 48 })
				if icon.ImageData.Icon == "" then
					icon:Destroy()
					icon = entityGroup:AddImage("Item_Unknown", { 48, 48 })
				end
				icon.SameLine = not encounter.modId
			end

			local nameGroup = entityGroup:AddGroup(id)
			nameGroup.SameLine = true

			local selectedIcon = entityGroup:AddImage("ico_concentration", Styler:ScaleFactor({ 36, 36 }))
			selectedIcon.Visible = false
			selectedIcon.SameLine = true

			---@type ExtuiTextLink
			local name = Styler:Color(nameGroup:AddTextLink(("%s (%s)"):format(entity.displayName, id:sub(#id - 5))), "PlainLink")
			name.UserData = "EnableForMods"
			name.IDContext = id
			name.OnRightClick = function()
				Helpers:KillChildren(self.popup)
				self.popup:Open()

				self.popup:AddSelectable(string.format("%s Entity Details", encounter.modId and "View" or "Edit")).OnClick = function()
					MonsterLabEntityCreationForm:create(designerSection, encounter, buildEncounter, entity)
				end

				if encounter.modId then
					return
				end

				---@type ExtuiMenu
				local copyEntityMutations = self.popup:AddMenu("Copy Entity Mutations From:")
				for rulesetId, ruleset in TableUtils:OrderedPairs(self.config.rulesets, function(key, value)
					return key == "Base" and 1 or value.name
				end) do
					---@type ExtuiMenu
					local rulesetMenu = copyEntityMutations:AddMenu(ruleset.name)
					rulesetMenu.IDContext = rulesetId

					for entityId, otherEntity in TableUtils:OrderedPairs(encounter.entities, function(key, value)
							return value.displayName
						end,
						function(key, value)
							return key ~= id and value.rulesetModifiers[rulesetId] and next(value.rulesetModifiers[rulesetId]._real)
						end)
					do
						rulesetMenu:AddSelectable(("%s (%s)"):format(otherEntity.displayName, entityId:sub(#entityId - 5))).OnClick = function()
							---@type MonsterLab_RulesetRule
							local copy = TableUtils:DeeplyCopyTable(otherEntity.rulesetModifiers[rulesetId]._real)

							if entity.rulesetModifiers[rulesetId] then
								entity.rulesetModifiers[rulesetId].delete = true
								entity.rulesetModifiers[rulesetId] = nil
							end
							entity.rulesetModifiers[rulesetId] = copy
							buildEncounter()
						end
					end

					if #rulesetMenu.Children == 0 then
						rulesetMenu:Destroy()
					end
				end

				self.popup:AddSelectable("Clone").OnClick = function()
					encounter.entities[FormBuilder:generateGUID()] = TableUtils:DeeplyCopyTable(entity._real)
					buildEncounter()
				end
			end

			local openPopupFunc = Styler:HyperlinkRenderable(name, entity.template, "Alt", true, nil, function(parent)
				CharacterWindow:BuildWindow(parent, entity.template)
			end)

			name.OnClick = function()
				if not openPopupFunc() then
					selectedIcon.Visible = true
					if activeSelectedIcon and activeSelectedIcon.Handle ~= selectedIcon.Handle then
						activeSelectedIcon.Visible = false
					end
					activeSelectedIcon = selectedIcon

					lastSelectedEntity = id
					Helpers:KillChildren(designerSection)

					entity.rulesetModifiers[self.activeRuleset] = entity.rulesetModifiers[self.activeRuleset]
						or TableUtils:DeeplyCopyTable(ConfigurationStructure.DynamicClassDefinitions.monsterLab.rulesetModifiers)

					local activeRuleset = entity.rulesetModifiers[self.activeRuleset]

					local mutatorGroup

					Styler:EnableToggleButton(designerSection, "Spawn", false, nil, function(swap)
						if swap then
							activeRuleset.shouldSpawn = not activeRuleset.shouldSpawn
							mutatorGroup.Visible = activeRuleset.shouldSpawn
						end
						return activeRuleset.shouldSpawn
					end)

					mutatorGroup = designerSection:AddGroup("DesignIt")

					EntityCustomizations:buildCustomizationsMenu(mutatorGroup, entity, activeRuleset, encounter.modId ~= nil)

					if encounter.modId then
						Styler:disableNonNavigatableElements(mutatorGroup)
					end
				end
			end

			if lastSelectedEntity == id then
				name:OnClick()
			end

			if encounter.modId then
				Styler:disableNonNavigatableElements(entityGroup)
			end
		end

		if not encounter.modId then
			---@type ExtuiSelectable
			local createEntityButton = entitySidebar:AddSelectable("Create New Entity")
			createEntityButton:SetStyle("SelectableTextAlign", 0.5)
			createEntityButton.OnClick = function()
				createEntityButton.Selected = false

				MonsterLabEntityCreationForm:create(designerSection, encounter, function()
					buildEncounter()
				end)
			end
		end
	end
	buildEncounter()
end

---@param parent ExtuiTreeParent
---@param rulesetSelectCallback fun()
function MonsterLab:ManageRulesets(parent, rulesetSelectCallback)
	Helpers:KillChildren(parent)
	if not self.config.rulesets["Base"] then
		self.config.rulesets["Base"] = { negate = true, name = "Base", description = "Base Ruleset that will be activated if no other rulesets are eligible. Can't be modified.", activeModifiers = {} }
	end

	parent:AddSeparatorText("Rulesets ( ? )"):Tooltip():AddText([[
	These rulesets can be used to customize encounters without having to replicate them - left-click the button to customize the encounter according to that ruleset's criteria,
right-click to modify or delete that ruleset. The Base ruleset can't be modified or deleted - this is the default if there are no other eligible rulesets.]])

	---@type ExtuiButton
	local lastActiveButton

	local createdOne = false
	for rulesetId, ruleset in TableUtils:OrderedPairs(MonsterLabConfigurationProxy.rulesets, function(key, value)
		return key == "Base" and 1 or value.name
	end) do
		local rulesetButton = parent:AddButton(("%s%s"):format(ruleset.name, ruleset.modId and " (M)" or ""))
		rulesetButton.SameLine = createdOne
		createdOne = true

		rulesetButton.IDContext = rulesetId
		local tooltip = ""
		if ruleset.description ~= "" then
			tooltip = ("\t" .. ruleset.description)
		end

		if ruleset.modId then
			if #tooltip > 0 then
				tooltip = tooltip .. "\n"
			end
			tooltip = tooltip .. ("\t From Mod %s - Can't Be Modified"):format(Ext.Mod.GetMod(ruleset.modId).Info.Name)
		end

		if tooltip ~= "" then
			rulesetButton:Tooltip():AddText(tooltip)
		end

		if rulesetId == self.activeRuleset then
			Styler:Color(rulesetButton, "ActiveButton")
			lastActiveButton = rulesetButton
		else
			Styler:Color(rulesetButton, "DisabledButton")
		end

		rulesetButton.OnClick = function()
			if rulesetButton.Handle ~= lastActiveButton.Handle then
				Styler:Color(lastActiveButton, "DisabledButton")
				Styler:Color(rulesetButton, "ActiveButton")

				lastActiveButton = rulesetButton

				self.activeRuleset = rulesetId

				rulesetSelectCallback()
			end
		end

		rulesetButton.OnRightClick = function()
			Helpers:KillChildren(self.popup)
			self.popup:Open()

			if rulesetId ~= "Base" then
				---@type ExtuiMenu
				local editRulesetMetaMenu = self.popup:AddMenu("Edit Ruleset Name/Description")
				FormBuilder:CreateForm(editRulesetMetaMenu, function(formResults)
					ruleset.name = formResults.Name
					ruleset.description = formResults.Description
					self:ManageRulesets(parent, rulesetSelectCallback)
				end, {
					{
						label = "Name",
						type = "Text",
						defaultValue = ruleset.name,
						errorMessageIfEmpty = "A name is required"
					},
					{
						label = "Description",
						type = "Multiline",
						defaultValue = ruleset.description
					}
				})

				---@type ExtuiMenu
				local customizeModifiersMenu = self.popup:AddMenu("Customize Ruleset Modifiers")
				customizeModifiersMenu.IDContext = rulesetId

				---@type ExtuiMenu
				local selectModifiersMenu
				if not ruleset.modId then
					selectModifiersMenu = customizeModifiersMenu:AddMenu("Select Modifiers")
				end

				local modGroup = customizeModifiersMenu:AddGroup("mods")

				local function buildCustomizer()
					modGroup.Visible = TableUtils:CountElements(ruleset.activeModifiers) ~= 0
					Helpers:KillChildren(modGroup)
					for modifierId in TableUtils:OrderedPairs(ruleset.activeModifiers, function(key)
						---@type ResourceRulesetModifier
						local modifierResource = Ext.StaticData.Get(key, "RulesetModifier")
						return tostring(modifierResource.RulesetModifierType) .. (modifierResource.DisplayName:Get() or modifierResource.Name)
					end) do
						---@type ResourceRulesetModifier
						local modifierResource = Ext.StaticData.Get(modifierId, "RulesetModifier")

						modGroup:AddSeparatorText(modifierResource.DisplayName:Get() or modifierResource.Name)

						local modifierGroup = modGroup:AddGroup(modifierId)
						modifierGroup.IDContext = modifierId

						if modifierResource.RulesetModifierType == 4 then
							Styler:DualToggleButton(modifierGroup, "Enabled", "Disabled", false, function(swap)
								if swap then
									ruleset.activeModifiers[modifierId] = not ruleset.activeModifiers[modifierId]
								end
								return ruleset.activeModifiers[modifierId]
							end)
						elseif modifierResource.RulesetModifierType == 3 then
							---@type ResourceRulesetModifierOption[]
							local resourceModifierValues = {}
							for _, modifierValueId in pairs(Ext.StaticData.GetAll("RulesetModifierOption")) do
								---@type ResourceRulesetModifierOption
								local rulesetModifierValue = Ext.StaticData.Get(modifierValueId, "RulesetModifierOption")
								if rulesetModifierValue.Modifier == modifierId then
									table.insert(resourceModifierValues, rulesetModifierValue)
								end
							end
							table.sort(resourceModifierValues, function(a, b)
								return (a.DisplayName:Get() or a.Name) < (b.DisplayName:Get() or b.Name)
							end)

							---@type string[]
							local selectedModifiers = ruleset.activeModifiers[modifierId]

							for i, modifierOption in ipairs(resourceModifierValues) do
								local box = modifierGroup:AddCheckbox(modifierOption.DisplayName:Get() or modifierOption.Name,
									TableUtils:IndexOf(selectedModifiers, modifierOption.Name) ~= nil)

								box.IDContext = modifierOption.Name
								box.SameLine = i > 1
								box.OnChange = function()
									if box.Checked then
										table.insert(selectedModifiers, box.IDContext)
									else
										selectedModifiers[TableUtils:IndexOf(selectedModifiers, box.IDContext)] = nil
										TableUtils:ReindexNumericTable(selectedModifiers)
									end
								end
							end
						end
					end
				end
				buildCustomizer()

				if not ruleset.modId then
					for modifierName, modifierId in TableUtils:OrderedPairs(Lab_RulesetModifiers, function(_, value)
							---@type ResourceRulesetModifier
							local modifierResource = Ext.StaticData.Get(value, "RulesetModifier")
							return tostring(modifierResource.RulesetModifierType) .. (modifierResource.DisplayName:Get() or modifierResource.Name)
						end,
						function(key, value)
							return #value == 36
						end) do
						---@type ResourceRulesetModifier
						local modifierResource = Ext.StaticData.Get(modifierId, "RulesetModifier")

						---@type ExtuiSelectable
						local modSelect = selectModifiersMenu:AddSelectable(modifierResource.DisplayName:Get() or modifierResource.Name, "DontClosePopups")
						modSelect.Selected = ruleset.activeModifiers[modifierId] ~= nil
						modSelect.OnClick = function()
							if ruleset.activeModifiers[modifierId] ~= nil then
								if type(ruleset.activeModifiers[modifierId]) == "table" then
									ruleset.activeModifiers[modifierId].delete = true
								end
								ruleset.activeModifiers[modifierId] = nil
							else
								ruleset.activeModifiers[modifierId] = modifierResource.RulesetModifierType == 3 and {} or false
							end

							buildCustomizer()
						end
					end
				end

				---@param select ExtuiSelectable
				self.popup:AddSelectable("Delete Ruleset", "DontClosePopups").OnClick = function(select)
					if select.Label ~= "Delete Ruleset" then
						self.config.rulesets[rulesetId].delete = true
						for _, folder in pairs(self.config.folders) do
							if not folder.modId then
								for _, encounter in pairs(folder.encounters) do
									for _, entity in pairs(encounter.entities) do
										if entity.rulesetModifiers[rulesetId] then
											entity.rulesetModifiers[rulesetId].delete = true
										end
									end
								end
							end
						end
						self:ManageRulesets(parent, rulesetSelectCallback)
					else
						select.Label = "Are You Sure?"
						Styler:Color(select, "ErrorText")
						select.DontClosePopups = false
					end
				end
			end


			---@type ExtuiMenu
			local copyMenu = self.popup:AddMenu("Copy Encounter Configs From: ")
			copyMenu:Tooltip():AddText("\t This will completely override the configs in this ruleset")

			for otherRulesetId, otherRuleset in TableUtils:OrderedPairs(self.config.rulesets, function(key, value)
					return key == "Base" and 1 or value.name
				end,
				function(key, value)
					return key ~= rulesetId
				end)
			do
				copyMenu:AddSelectable(otherRuleset.name).OnClick = function()
					rulesetSelectCallback(rulesetId, otherRulesetId)
				end
			end
		end
	end

	local makeNewButton = parent:AddButton("+")
	makeNewButton:Tooltip():AddText("\t Create a new Ruleset")
	makeNewButton.SameLine = true
	makeNewButton.OnClick = function()
		self.popup:Open()
		FormBuilder:CreateForm(self.popup, function(formResults)
			local ruleset = TableUtils:DeeplyCopyTable(ConfigurationStructure.DynamicClassDefinitions.monsterLab.ruleset)
			ruleset.name = formResults.Name
			ruleset.description = formResults.Description

			self.config.rulesets[FormBuilder:generateGUID()] = ruleset
			self:ManageRulesets(parent, rulesetSelectCallback)
		end, {
			{
				label = "Name",
				type = "Text",
				errorMessageIfEmpty = "A name is required"
			},
			{
				label = "Description",
				type = "Multiline",
			}
		})
	end
end

---@return MazzleDocsDocumentation
function MonsterLab:generateDocs()
	return {
		{
			Topic = "Monster Lab (ML)",
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
					text = "Server Only"
				},
				{
					type = "Content",
					text =
					[[!Lab_FindDBEntries entity UUIDs separated by a space - returns all DB entries for each passed-in entity]]
				},
				{
					type = "Code",
					text = [[server
!Lab_FindDBEntries 002_e7fc87a2-2320-43fc-83b3-5c9bc2076efe 223eba2a-fa66-36d3-edb6-23a7ec8bb323]]
				},
				{
					type = "Content",
					text =
					[[!Lab_ParseDBs - Generates %localappdata%\Larian Studios\Baldur's Gate 3\Script Extender\Absolutes_Laboratory\CharacterIndexedDB.json - in case you want a copy for whatever reason. This is what ML uses internally to determine what DBs to check.]]
				},
				{
					type = "Code",
					text = [[server
!Lab_ParseDBs]]
				},
				{
					type = "Content",
					text =
					[[!Lab_MonsterLab_DatabaseParityCheck (ALL or ML-spawned entity ids separated by a space) - Checks the cached DB entries on each ML entity against their live DB entries, reporting any differences. If ALL is passed, then checks all ML entities that are currently on the server]]
				},
				{
					type = "Code",
					text = [[server
!Lab_MonsterLab_DatabaseParityCheck ALL
!Lab_MonsterLab_DatabaseParityCheck 002_e7fc87a2-2320-43fc-83b3-5c9bc2076efe 223eba2a-fa66-36d3-edb6-23a7ec8bb323]]
				},
				{
					type = "Content",
					text =
					[[!Lab_ResetMonsterLabDatabases (ALL or ML-spawned entity ids separated by a space) - Completely wipes out all DB entries for the given entities, so they can be freshly set by ML after a save + reload. If ALL is passed, then processes all ML entities that are currently on the server]]
				},
				{
					type = "Code",
					text = [[server
!Lab_ResetMonsterLabDatabases ALL
!Lab_ResetMonsterLabDatabases 002_e7fc87a2-2320-43fc-83b3-5c9bc2076efe 223eba2a-fa66-36d3-edb6-23a7ec8bb323]]
				},
			}
		},
		{
			Topic = "Monster Lab (ML)",
			content = {
				{
					type = "Heading",
					text = "Encounters"
				},
				{
					type = "CallOut",
					prefix = "Tips",
					text = "Always right click on a discrete component, like a folder, encounter, ruleset, or entity, to manage their properties (i.e. edit/delete them)",
					prefix_color = "Green"
				} --[[@as MazzleDocsCallOut]],
				{
					type = "Content",
					text = [[
Encounters are exactly what you'd expect - groups of entities that are linked together to form one combat group, or encounter.

You can have as many entities in an encounter as you'd like - just keep basic engine limitations in mind.

You create encounters under a dedicated folder in the Monster Lab tab in MCM - folders are just superficial organizational tools, same as with Mutations.

Within an encounter, you create an entity by giving it a dedicated Template, Name, and Title; each entity is given an unique ID by Lab, so you can give the same properties to as many entities as you'd like (i.e. 36 cranium rats :D).

You can also set some properties and assign Mutators to them according to different rulesets, but that's covered in the "Rulesets" section.

As of this writing, only statically-placed encounters are supported, the process of which is documented in the "Encounter Designer" section - in the future, you'll be able to create encounters that:
- Are trigger based (with custom triggers)
- Ambush the player's party anywhere in a map based on specified rules
and maybe more, depending on what I think of/what feedback I get.]]
				}
			}
		},
		{
			Topic = "Monster Lab (ML)",
			content = {
				{
					type = "Heading",
					text = "Static Encounter Designer"
				},
				{
					type = "CallOut",
					prefix = "Tips",
					prefix_color = "Green",
					text = "When using a in-world picker, middle-click to save the value, left/right-click to cancel and use the existing value"
				} --[[@as MazzleDocsCallOut]],
				{
					type = "Section",
					text = "The Designer, in context of an encounter, will:"
				},
				{
					type = "Bullet",
					text = {
						"close MCM when opened and reopen it upon being closed, closing all windows related to the Designer at the same time",
						"spawn all entities that haven't already been spawned by an active Monster Lab profile on launch and despawn on close - if an entity was already spawned by a profile, their properties will be updated the same way as if it had been spawned by the designer. It will not resurrect dead entities.",
						"update the properties of the spawned entities whenever a change is made",
						"block entities ability to enter combat until closed, allowing you to set conflicting factions without watching them die",
						"default to blocking the player's (and party's) ability to enter combat and dialogue, controlled by the toggles in the top-left. Note that blocking dialogue doesn't prevent you from triggering Triggers placed in the game world, which will often start cutscenes or force dialogue. Teleporting directly to an entity will usually bypass these, deending on the trigger.",
						"not execute ruleset behavior during the designer phase (but it also won't clear any mutators applied by an active ML + Mutation profile)"
					}
				} --[[@as MazzleDoctsBullet]],
				{
					type = "SubHeading",
					text = "Encounter-Level Settings"
				},
				{
					type = "Section",
					text = "Game Level and Base Coordinates"
				},
				{
					type = "Content",
					text = [[
These two settings are core to your encounter: What Game Level is it active in, and where in that map is it placed?

An encounter can only be statically placed in one spot - if you want the same encounter in multiple places, you'll have to clone it and place them seperately (do this after you've configured the Ruleset properties, covered in the "Rulesets" section).

If you select a level you aren't currently in, most of the buttons will be hidden, and a new Teleport button will appear next to the Level Dropdown to teleport you to that level - once you're in the correct level, you can use the coordinate picker to choose the base coordinate.

The base coordinates serve as the default coordinates for your entities, spawning them in a tightly-clustered group, and as the destination for the Teleport button that appears below the dropdown if you're in the correct level. When choosing your coordinates, an orb and moonbeam effect will trigger to help show you that location (thanks to Mazzle_Lib!)

If you want to attach your encounter to an existing one, click on the Twin Daggers icon in the same row as the Teleport Button - if you've run the Entity Recorder (button in the Inspector) as of Lab Version 1.8.0 (Monster Lab release), you'll see every recorded entity grouped by their shared CombatGroupId if applicable, along with a teleport button that will take you to that encounter (you can also copy entities from any level in the game to your encounter via this combat group window)

Once you've chosen your level and base coordinates, you can move on to the next section.]]
				},
				{
					type = "Section",
					text = "Extra Settings: Combat Group ID, Faction, and Databases"
				},
				{
					type = "Content",
					text = [[
These two settings are available under the Comment looking button in the row under the Dropdown.

CombatGroupId is a random identifier set in the entity's CombatParticipant.CombatGroupID component, ensuring that when one entity enters combat, every entity with that same ID enters combat at the same time, regardless of how far away they are.
Lab will enforce the presence of a UUID for an encounter and set it for all entities under that encounter, as individual sight/hearing-based engagement is incredibly unreliable.

Factions are set in the Faction component of each entity, and control who they're friendly, neutral, and hostile towards. There are 971 factions in the base game, with various hierarchal depths, so there isn't search/selector functionality for this - by default, Lab will use (and force, if the value is cleared) the "Evil NPC" faction, making your entities always hostile to the player.
Keep in mind that factions can swap to being hostile/friendly towards the player just based on triggers - for example, the captured civilians on the Nautaloid will only become hostile when the correct button is pressed, but they all share the same faction and CombatGroupId.

You can search for factions via https://bg3.norbyte.dev/search?q=type%3Afactions or use Lab's Inspector to see what faction a given entity belongs to, but if you're looking to integrate your encounter with an existing one, there's an easier way - click on the True Strike icon above the input boxes and you can copy both CombatGroupId and Faction from an entity in the game world just by middle clicking them.

You may see entities within the same encounter have different Factions - these are usually hierarchal, which Larian went really, really in-depth with for some reason, but they should all bubble up to the same parent faction, so don't be concerned about that

Databases are a complex topic, and thus have their own section in the left sidebar. All you need to know here is that you can copy the current database entries an entity in the game world has via the same picker as combatGroupId/faction - these will be inherited by each ML entity in the encounter.]]
				},
				{
					type = "SubHeading",
					text = "Entity-Level Settings"
				},
				{
					type = "Content",
					text = [[Most of the settings here are self-explanatory, or behave similarily to above, so here're the highlights:]]
				},
				{
					type = "Section",
					text = "Animations"
				},
				{
					type = "Content",
					text = [[
Basic Animations are set on the entity via `Osi.PlayAnimation({entityId}, {provided UUID})` and looping ones are set via
Osi.PlayLoopingAnimation({entityId},
						{startAnimation},
						{loopAnimation},
						{endAnimation},
						{loopVariation1},
						{loopVariation2},
						{loopVariation3},
						{loopVariation4})

I genuinely don't know anything about how, when, why, and what values work - I just exposed the option for those who do. There's no validation around this, and Osi doesn't throw errors if the command doesn't work (as long as it's syntatically valid), so either know what you're doing or be prepared for a _lot_ of experimenting and research.
]]
				},
				{
					type = "Section",
					text = "Rotation"
				},
				{
					type = "Content",
					text =
					[[Rotation in this game is weird - I offload the computations and implementation of that to Mazzle_Lib, which has to spawn an invisible object and use Osi to force the entity to look at it; because of this, there really isn't sensible math around rotation - just play around with it and see what works.]]
				}
			}
		},
		{
			Topic = "Monster Lab (ML)",
			SubTopic = "Osiris Databases (DB)",
			content = {
				{
					type = "Heading",
					text = "What Is A Database?"
				},
				{
					type = "Content",
					text = [[
Osiris Databases are two-dimensional systems of records, which is to say that there are two components: Columns and Rows. (If you know what a relational database is, don't think about it. These are not relational DBs.)

Each database has a set of Columns which define what kind of data is expected in what position of a row - these columns have different data types, but all columns support null values (in the form of NULL_00000000-0000-0000-0000-000000000000).
Each row in a database represents a unique combination of column values that can then be queried by the game later.

For example, using the database "DB_SpotPlayers"]]
				},
				{
					type = "Code",
					text = [[
// NOTE: You can copy-paste the contents of any blocks like this

Full Definition:
DB_SpotPlayers(CHARACTER, STRING, FLAG, FLAG)

Columns:
1 - CHARACTER
2 - STRING
3 - FLAG
4 - FLAG

Example Row:

1 - CHARACTER = "S_GLO_Orin_bf24e0ec-a3a6-4905-bd2d-45dc8edf8101",
2 - STRING    = "WYR_OrinsImpersonation_OrinJournalistSpotting",
3 - FLAG      = "NULL_00000000-0000-0000-0000-000000000000",
4 - FLAG      = "NULL_00000000-0000-0000-0000-000000000000"

or, to represent it more traditionally (values truncated for readability):

| | CHARACTER  | STRING    | FLAG | FLAG |
|1| S_GLO_Orin | WYR_Orins | NULL | NULL |]]
				},
				{
					type = "Content",
					text = [[
Databases can have thousands of rows, but each one must contain a unique permutation of values - there are no duplicate rows in a Database.

Column Types Cheatsheet:]]
				},
				{
					type = "Code",
					text = [[
// NOTE: You can copy-paste the contents of any blocks like this
// NOTE - To reduce repetition, "UUID" is used to represent two mostly equivalent values:
// 1. Just the UUID of the subject - i.e. 88f2b674-5e09-4819-8ac7-04b1be422dec
// 2. The joining of <NAME OF RESOURCE> and <UUID> separated by "_" - i.e. LOW_SharGrotto_GrottoSentry_223eba2a-fa66-36d3-edb6-23a7ec8bb323
// Larian's scripts always use the second form, but the DBs accept either value
//		- as far as I can tell, the second is the standard for readability when inspecting a DB entry, so that's what ML uses
// Choosing to deviate from this pattern may break Script Extender mods inspecting the rows retrieved from the DB for whatever reason,
// 		as it's less flexible than Osiris in this specific instance (but straight queries should still work either way)
// For Character + Item entries, the <NAME OF RESOURCE> refers to the <Name> node on the character/item template, NOT the <TemplateName> node
// You can find example usages of all these types by going to https://bg3.norbyte.dev and searching "type:script TYPE"
//		- i.e. type:script LEVELTEMPLATE

ANIMATION: UUID of Animation Set - https://bg3.norbyte.dev/search?q=type%3Aanimationset
ARMOURSET: Either "Normal" or "Vanity"
CHARACTER: UUID of a spawned Character Entity - https://bg3.norbyte.dev/search?q=type%3Acharacter
CHARACTERROOT: UUID of a Character Template - https://bg3.norbyte.dev/search?q=type%3Acharactertemplate
DEATHTYPE: One of the human-readable values from https://bg3.norbyte.dev/search?q=type%3Aenumeration+death#result-d3d25740d18876c47227d4c541f9985710ba6600
DIALOGRESOURCE: UUID - https://bg3.norbyte.dev/search?q=type%3Adialog
DLC: No master list - you can find examples via https://bg3.norbyte.dev/search?q=type%3Ascript+DLC
FACTION: UUID - https://bg3.norbyte.dev/search?q=type%3Afactions
FLAG: UUID - https://bg3.norbyte.dev/search?q=type%3Aflag
GUIDSTRING: Unknown - seems like a generic type for any UUID that may be used by a script - https://bg3.norbyte.dev/search?q=type%3Ascript+GUIDSTRING
INTEGER: Whole numbers - i.e. 1
ITEM - UUID of a spawned Item - https://bg3.norbyte.dev/search?q=type%3Aitem
ITEMROOT - UUID of a item template - https://bg3.norbyte.dev/search?q=type%3Aitemtemplate
LEVELTEMPLATE - UUID - https://bg3.norbyte.dev/search?q=type%3Aleveltemplate
				(NOTE: The values used are extremely inconsistent in some OSI scripts, not sure why)
REAL - Decimal numbers - i.e. 1.4
ROOT - Unsure, seems to be a generic type to hold any template? - https://bg3.norbyte.dev/search?q=type%3Aosiris+ROOT
SPLINE - These are _weird_. I don't understand them well, but it's not just https://bg3.norbyte.dev/search?q=type%3Aspline
			- there's a whole waterfall that Larian does to determine a specific spline to use
STRING - Arbitrary human-readable value
TAG - UUID - https://bg3.norbyte.dev/search?q=type%3Atag
TRIGGER - UUID - https://bg3.norbyte.dev/search?q=type%3Atrigger
VOICEBARKRESOURCE - UUID - https://bg3.norbyte.dev/search?q=type%3AVOICEBARK]]
				}
			}
		},
		{
			Topic = "Monster Lab (ML)",
			SubTopic = "Osiris Databases (DB)",
			content = {
				{
					type = "Heading",
					text = "How Does The Game Use Databases?"
				},
				{
					type = "Content",
					text = [[
Databases are used for a variety of reasons, such as tracking state (i.e. can character X see character Y via DB_Sees), coupling dialogue triggers to entities, and registering entities for use in scripted events.

That last example, use in scripted events, is what drove this feature for Monster Lab. If you look at an Osiris Script via bg3.norbyte.dev, such as Act3_WYR_MerchantsHouse, you'll see they are GENERALLY broken down into two phases:

1. Setup - adding NPCs to Databases
2. Execution - listening for things like PROCs/Triggers/DB updates and executing more Osiris commands

The Execution phase generally pulls records out the databases used in the setup phase to determine what entities should be processed in response to an event - for example, if the player decides to pay off the Thugs' leader, all entities in the "DB_WYR_MerchantsHouse_Thugs" Database will be sent away peacefully via a block like:]]
				},
				{
					type = "Code",
					text = [[
// Script Link: https://bg3.norbyte.dev/search?iid=Script.GustavDev.Act3_WYR_MerchantsHouse

PROC
PROC_GlobalFlagReactionAfterDialog((FLAG)WYR_MerchantsHouse_Event_ThugsLeave_d518e87e-3514-1f96-a96a-3ce6b1d0be64)
AND
NOT DB_GlobalFlag((FLAG)WYR_MerchantsHouse_State_ThugsChasedOutRefuges_caec5b7a-b2a9-3cc6-595d-fc1bcf74521f)
AND
DB_WYR_MerchantsHouse_Thugs(_Thug)
THEN
PROC_PeacefulResolve(_Thug);]]
				},
				{
					type = "Content",
					text = [[
Therefore, if we want to add more thugs to the scene and want to make sure they leave when the other thugs do, we need to add our ML entities to "DB_WYR_MerchantsHouse_Thugs" (and potentially other DBs)]]
				},
			},
		},
		{
			Topic = "Monster Lab (ML)",
			SubTopic = "Osiris Databases (DB)",
			content = {
				{
					type = "Heading",
					text = "Using DBs In ML - What To Know Before You Start"
				},
				{
					type = "SubHeading",
					text = "Filtered Databases"
				},
				{
					type = "Content",
					text = [[
You can view the database entries for a character entity in two places: The Entity Tab in the Inspector and the "Extra Options" in ML's Encounter Designer by using the Picker.

The inspector view does not filter out any databases - it will show you every DB that accepts a "CHARACTER" type that the inspected entity currently has an entry in.

ML however does filter the DBs down to what I think is relevant to entities spawned by ML. The following DBs are currently filtered:

1. DB_Sees - holds all entities that can see each other. Constantly updated, handled by the game, we have no reason to directly interact with it

2. DB_Dead - holds all dead entities. _May_ add support for this in future to support "playing dead" enemies, like the Scribes in Wither's tomb, but for now it's just not necessary and is a huge table

3. Any table that starts with DB_InternPlayer - from what I was seeing, this covers a _lot_ of tables that are specifically focused on player interactions, like SpeakWithDead dialogue, normal dialogue, and scene triggers.
These scenarios will not be supported by ML since they require a lot of supporting resources to be created anyway, so you're better off just creating your custom entities the same way Larian does and not through ML]]
				},
				{
					type = "SubHeading",
					text = "Cascading and Scripted DB entries"
				},
				{
					type = "Content",
					text = [[
When adding ML entities to DBs for use in Scripted Events, the entity will likely be added to more tables than configured over the course of the event, or even simply because they were added to a specific table.

For example, referring back to the Act3_WYR_MerchantsHouse script again, if you allow the Thugs to chase out the refugees then all entities in the DB_WYR_MerchantsHouse_Thugs DB will added to the DB_WYR_MerchantsHouse_ThugNonLethal DB due to:

----
...
THEN
DB_WYR_MerchantsHouse_ThugNonLethal(_Thug);
AddPassive(_Thug, "WYR_MerchantsHouse_ThugsNonLethal_Passive");
----

Additionally, there are DBs that are managed by the game but aren't tied to any specific scripted events - DB_Sees is a good example of this, as ML entities will be added to that table whenever they're in another entity's line of sight, and that's not something we can control.

This is normal, expected behavior, but is important to note for 3 reasons:
1. If you copy an existing entity's DB entries for use in ML after triggering a scripted event, you'll likely add the ML entities to DBs they shouldn't actually be in when the player first loads an area. Ensure you're working on a clean save as much as possible.
2. If you remove a DB from a ML entity/encounter after a player has already used your profile and triggered that event, they'll be left with a mix of configured and non-configured DB entries (more on this later)
3. If you're debugging a ML entity by viewing them in the Inspector, or trying to copy a different encounter's DB entries for an encounter, you may see more DB entries than you configured]]
				}
			}
		},
		{
			Topic = "Monster Lab (ML)",
			SubTopic = "Osiris Databases (DB)",
			content = {
				{
					type = "Heading",
					text = "Using DBs In ML - Configuring Encounters/Entities"
				},
				{
					type = "SubHeading",
					text = "Adding Entries"
				},
				{
					type = "Content",
					text = [[
You can add Database entries for your ML entities at both the Encounter and Entity level, both within the Encounter Designer (Launch Designer Mode button).

To add them at the encounter level, click on the Comment icon to show extra encounter-level settings, where the Faction and CombatGroupId buttons are. You can use the picker to copy the entries from an existing entity the same way you can with Faction/CombatGroupId,
but unlike those fields, existing DB entries will _not_ be overwritten when you copy from a second+ entity (meaning, you can copy from one entity, then another, and the result will be a combination of both their entries).
You can also add custom entries by clicking the "Add New Entry" button - see the tooltips for important information. You are responsible for filling in each column's value yourself.

This is considered the ideal way to manage DB entries for your entities, for the following reasons:
1. Each encounter should represent a discrete set of entities that share goals + behavior - meaning, you shouldn't create one encounter to add both Thugs and Refugees to the Act3_WYR_MerchantsHouse, you should create two encounters to ensure there's no inappropriate bleed between them
2. Since ML doesn't support adding Dialogue/Custom Scripts/etc to ML entities, they should only be added to the bare minimum set of DBs anyway, mimicking other NPCs of the same nature in the scripted event

However, if you identify a need to add a specific entity in your encounter to a separate DB, you can do so by expanding the "Databases" section within that entity's card. There is no picker for this section - you have to fill out the values yourself.]]
				},
				{
					type = "SubHeading",
					text = "Removing/Disabling Entries"
				},
				{
					type = "Content",
					text = [[
You can disable/remove entries from your encounter/entity at any point of time - however, this has potential implications due to Cascading/Scripted DB entries as mentioned in "Using DBs In ML - What To Know Before You Start".

For example, say you added your entities to "DB_AssaultFamilyIgnoreFor" as part of the setup for the Act3_WYR_MerchantsHouse event. You publish your config, other players use it, get to this event, start it, then save and exit the game.

At this stage, Lab has baked the currently configured DB entries in the ML Entity data - this serves as a cache so the next time the save has loaded, Lab can compare the cached entries against the currently configured entries and bring them into parity
by removing extra entries + add any missing ones. This means that Lab does NOT check the live Database entries, as doing so would mean that Lab could remove DB entries that the entity should have as part of the scripted event, e.g. the aforementioned "DB_WYR_MerchantsHouse_ThugNonLethal" DB.

Continuing the scenario, you then remove those DB entries "DB_AssaultFamilyIgnoreFor" for whatever reason, publish your config, players update, load into their save.
Lab will see those DBs are in the cached entries, but not in the config, so now it will remove them. This **could** have unintended consequences, perhaps causing the ML entities to start a fight on their own as soon as the player loads into their save (just an example, not a definite result in this situation).

Alternatively, you decide to move your thugs to a different spot in Rivington, and change up their DB entries so they become hostile to the player if the player attacked the other thugs, so the player gets ambushed down the road. When the player loads their save, the ML entities get moved to the new spot and removed
from the other DBs, but they're still in all the DBs that the scripted event added them to, which could mess up your intended flow.

So how do we work around this? The short answer is - you can't. Lab can't reasonably determine why a ML Entity is present in DBs that aren't in the config - it could be due to OSI scripts, engine events, or just the author removing those entries from the config, so it just sticks to comparing cached config vs current config.

What this means for you as an author:
1. If you publish major changes to DB entries, make sure you detail which encounters they are so players know whether or not they should wait to upgrade
2. If you run into a situation where players _need_ to completely reset the DB entries for a ML entity, have them do the following:
	1) Disable the Monster Lab Profile
	2) Save the game
	3) Reload
	-- ALL encounters in the profile will now be completely despawned, which cleans up ALL DB entries the ML entities are found it - this is a live DB check, not a cached one --
	4) Active the ML Profile
	5) Save the game
	6) Reload
	-- The encounter will now be spawned in fresh, adding each entity's DB entries from scratch --

You as the author have an alternative, via console commands - see the Monster Lab Console Commands section in these docs. You can direct users to use these as well if you want.
]]
				}
			}
		},
		{
			Topic = "Monster Lab (ML)",
			content = {
				{
					type = "Heading",
					text = "Rulesets"
				},
				{
					type = "Section",
					text = "Foreword"
				},
				{
					type = "Content",
					text = [[
Rulesets are an advanced bit of customization for each entity within an encounter, for those wanting their encounter difficulties to match the player's settings - you can create rulesets for any combination of BG3's difficulty settings, like enemy power and free first-strikes, and that ruleset will only activate when ALL of its specified criteria are met.

When processing a profile, only rulesets that have been configured for an entity will be considered - this generally always means that all entities in an encounter will share the same ruleset, as they'll be auto-configured with defaults for an existing ruleset, but this ultimately ensures the entity is processed in the context it was configured for.

If two rulesets have the same criteria, one is randomly chosen - if two rulesets have common criteria, the one with more matched criteria will be chosen.

There is always an immutable Base criteria present, allowing all mods creating encounters to have a guaranteed fallback. This ruleset has no criteria, and will always be chosen if no other ruleset qualifies for the campaign the profile is active within.

If a difficulty setting is changed by the player, they need only save and reload, and Lab will adjust the spawned encounter to meet the new ruleset, if applicable.

Keep in mind that only one ruleset is chosen for the whole encounter - so if you have one entity configured for the chosen custom ruleset, but another is only configured for the Base ruleset, that entity just won't have anything beyond the defaults applied to it.

You can copy ruleset properties between entities by right-clicking on the entity link in the main MCM window.

These rulesets are exported along with your profile, and made available to users if you packaged the export into a mod, but they won't be able to change/delete them, ensuring your customizations always apply in the intended scenarios.]]
				},
				{
					type = "SubHeading",
					text = "What's Controlled By A Ruleset"
				},
				{
					type = "Section",
					text = "Spawning"
				},
				{
					type = "Content",
					text = [[
This is a straightforward toggle - disabling it will hide all of the sections below, and the entity will be despawned next time the relevant profile is executed (or just skipped if not already spawned)]]
				},
				{
					type = "Section",
					text = "Mutators"
				},
				{
					type = "Content",
					text = [[
These mutators work exactly as in the Mutations tab - the ruleset is treated as a Mutation, selecting the relevant entity and only that entity for the configured mutators.

If there is an active Mutation profile and the entity is selected by mutations within that profile, the mutators specified in ML will be processed last - if you enable the Composable setting, this only means that the Mutation profile can't overwrite your mutator with a non-composable Mutation, but if you disable Composability, that means your mutators will automatically override the same types of mutators from the selected Mutations.
Regardless of whether you enable or disable Composability, any mutators specified in the applicable Mutation profile that aren't configured in your Entity's Ruleset (i.e. you have a Health mutator in your mutation profile but not your entity's ruleset), that mutator will always apply - you can't enforce that only your mutators should apply for the entity.]]
				},
				{
					type = "Section",
					text = "Character Stat"
				},
				{
					type = "Content",
					text = [[
These fields correspond to the fields on https://bg3.norbyte.dev/search?q=type%3Astatscharacter (type:statscharacter) - changes to these values will reflect on the spawned entity immediately, without necessitate a save/reload.
The "Stat" field is not editable here - instead, right-click the entity's name in the left sidebar and click "Edit Details" - you'll be able to change the dedicated stat there (which is agnostic of Ruleset).

Use -1 for any number fields to instead use the Stat's original value. Note that the original value is not persisted to the config, so if users running your profile have a mod that affect the relevant fields, they'll use those modded values, not the ones you see without the mod.]]
				},
				{
					type = "Section",
					text = "Character Template"
				},
				{
					type = "Content",
					text = [[
These fields correspond to the fields on https://bg3.norbyte.dev/search?q=type%3Acharactertemplate (type:charactertemplate) - changes to these values will NOT reflect on the spawned entity immediately - users must save + reload for them to be properly applied.
The "Template" field is not editable here - instead, right-click the entity's name in the left sidebar and click "Edit Details" - you'll be able to change the dedicated template there (which is agnostic of Ruleset).

Use -1 for any number fields to instead use the Templates's original value. Note that the original value is not persisted to the config, so if users running your profile have a mod that affect the relevant fields, they'll use those modded values, not the ones you see without the mod.]]
				}
			}
		},
		{
			Topic = "Monster Lab (ML)",
			content = {
				{
					type = "Heading",
					text = "Profiles"
				},
				{
					type = "Content",
					text = [[
Profiles are a simple set of Encounters that should be active in each Game Level - you can view/edit your active profile by clicking on the Eye icon to the left of the profile dropdown, or by selecting a different profile in that dropdown.

You can edit Encounters directly within the profile view by simply clicking on the encounter's name - click on it again to hide that section.

Profiles can be set as the default the same way Mutation Profiles can - just click the gear icon to the right of the dropdown, choose your Profile, and mark as default. Setting the dropdown to "Disabled" and saving will prevent the chosen default from activating within that campaign.

Monster Lab Profiles are always executed before Mutation profiles to ensure that the spawned entities are mutated by an active Mutation Profile, and are triggered after the `LevelGameplayReady` Osi event fires.

Exporting/Importing a profile works exactly the same as Mutations, so go read that section under "Mutations/Profiles/Exporting Profiles and Everything Associated" - the only difference to note is that ML exports for mods using a different name: AbsolutesLaboratory_MonsterLab_ProfilesAndMutations.json under the MonsterLab directory.

The reasoning for this is that while Mutations will affect MonsterLab entities, the two are conceptually and technically independent functions of Lab that can be mixed and matched at will, so there's actually nothing tying them together - this gives users the freedom to import and export any set of profiles independently of each other, crafting unique but cohesive experiences at will.]]
				}
			}
		}
	} --[[@as MazzleDocsDocumentation]]
end

---@return {[string]: MazzleDocsContentItem}
function MonsterLab:generateChangelog()
	return {
		["1.13.5"] = {
			type = "Bullet",
			text = {
				"Server: Remove logic that deletes spawned encounters when player is no longer on the same level, preventing duplicate spawns when leaving and re-entering the area. Won't delete spawns that already duplicated - run server console command !Lab_MonsterLab_DeleteDuplicates in the SE console while in the same area as the duplicates to delete them",
			}
		},
		["1.13.1"] = {
			type = "Bullet",
			text = {
				"Server: Fixes other entities in the encounter being deleted when managing a single entity in the Encounter Designer",
				"Server: Skip Template and Database updates while in Designer mode",
				"Client: Allow whitespace in the entity's Name + Title"
			}
		},
		["1.12.3"] = {
			type = "Bullet",
			text = {
				"Server: Support Global Templates by spawning in their Root Template, then copying the GlobalTemplate fields over to the CachedTemplate",
				"Server: Ensure proper cleanup of entities that were removed from encounters and encounters that were removed from the profile",
				"Client: Fix Mod-sourced profiles not loading sometimes",
				"Client: Properly separate mod-sourced and user-made encounters",
				"Client: Ensure mod-sourced folders, profiles, rulesets, and encounters can't be edited",
				"Client: Allow cloning mod-sourced profiles, rulesets, folders, and encounters",
				"Client: Move Stats creation logic to StatsLoaded and set a super low priority on the listener - this fixes the initial stats being deleted when loading into an honour save, and the low priority seems to reliably address the logic running before templates are available. If you see ML entities with 1 health, report it"
			}
		},
		["1.12.2"] = {
			type = "Bullet",
			text = {
				"Server: Fixed updating entity rotation during profile execution",
			}
		},
		["1.12.1"] = {
			type = "Bullet",
			text = {
				"Server: Fix error with log preventing rotation from being updated",
			}
		},
		["1.12.0"] = {
			type = "Bullet",
			text = {
				"Server: Fix ML Entities not having their mutation var attached when there's no active mutation profile, but they still have mutations defined in ML",
				"Client + Server: Add support for adding ML entities to Osiris Databases to allow them to participate in scripted events. See new docs.",
				"Client + Server: Allows overwriting the Character Stat, Icon, Visual Resource, and Anubis Config Name used for a ML entity, separate from the Template. Edit your ML by right-clicking their name in the main MCM tab to change existing entities",
				"Client + Server: Rulesets: Allows setting specific character stat and template fields, separate from the base entity definition.",
				"Client: Fallback logic when the template assigned to an entity does not exist in the game, allowing a new template to be chosen"
			}
		},
		["1.10.4"] = {
			type = "Bullet",
			text = {
				"Server: Add safeguards for when an entity somehow doesn't exist when ML runs"
			}
		},
		["1.8.1"] = {
			type = "Bullet",
			text = {
				"Fix NPE when there's never been an active ML profile executed"
			}
		},
		["1.8.0"] = {
			type = "Bullet",
			text = "Initial Release"
		}
	} --[[@as {[string]: MazzleDocsContentItem}]]
end
