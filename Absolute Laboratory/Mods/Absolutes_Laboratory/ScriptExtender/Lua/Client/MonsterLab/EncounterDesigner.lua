Ext.Vars.RegisterModVariable(ModuleUUID, "MonsterLab_SpawnedEntities", {
	Server = true,
	Client = true,
	WriteableOnServer = true,
	WriteableOnClient = true,
	SyncToClient = true,
	SyncToServer = true
})

Ext.Vars.RegisterUserVariable("AbsolutesLaboratory_MonsterLab_Entity", {
	Server = true,
	Client = true,
	WriteableOnServer = true,
	WriteableOnClient = true,
	SyncToClient = true,
	SyncToServer = true
})

Ext.Require("Client/MonsterLab/ExistingEncounters.lua")

EncounterDesigner = {
	---@type ExtuiWindow
	designerWindow = nil,
	---@type ExtuiWindow
	designerModeHeader = nil,
	---@type ExtuiWindow
	designerPickerInfo = nil,
	---@type ExtuiWindow
	existingEncountersWindow = nil,
	---@type ExtuiPopup
	popup = nil,
	mlDynamicClasses = ConfigurationStructure.DynamicClassDefinitions.monsterLab,
	---@type {[string]: string[]}
	dbIndex = FileUtils:LoadTableFile(string.format("Mods/%s/OsirisMetaData/CharacterIndexedDB.json", Ext.Mod.GetMod(ModuleUUID).Info.Directory), "data")
}

local saveButton = 2

---@param encounter MonsterLabEncounter
---@param encounterMeta MonsterLabProfileEncounterEntry
function EncounterDesigner:buildDesigner(encounter, encounterMeta)
	if not self.designerWindow then
		self.designerWindow = Ext.IMGUI.NewWindow(encounter.name)
		self.designerWindow.IDContext = "Monster Lab Designer Window"
		self.designerWindow.Closeable = true
		self.designerWindow.Scaling = "Scaled"
		self.designerWindow.Font = MCM.Get("font_size", "755a8a72-407f-4f0d-9a33-274ac0f0b53d")
		self.designerWindow:SetPos({ Ext.IMGUI.GetViewportSize()[1] / 2, Ext.IMGUI.GetViewportSize()[2] / 2 }, "FirstUseEver")
		self.designerWindow:SetSize({ 300, 300 }, "FirstUseEver")

		self.popup = self.designerWindow:AddPopup("encounter")
		self.popup.UserData = "keep"
		self.popup:SetColor("PopupBg", { 0, 0, 0, 1 })
		self.popup:SetColor("Border", { 1, 0, 0, 0.5 })

		self.designerModeHeader = Ext.IMGUI.NewWindow("ACTIVE DESIGNER MODE")
		self.designerModeHeader.Closeable = false
		self.designerModeHeader.Scaling = "Scaled"
		self.designerModeHeader.NoResize = true
		self.designerModeHeader.NoTitleBar = true
		self.designerModeHeader.NoMove = true
		self.designerModeHeader:SetBgAlpha(0)
		self.designerModeHeader:SetColor("FrameBg", { 1, 1, 1, 0 })
		self.designerModeHeader.Font = MCM.Get("font_size", "755a8a72-407f-4f0d-9a33-274ac0f0b53d")

		Styler:MiddleAlignedColumnLayout(self.designerModeHeader, function(ele)
			Styler:CheapTextAlign("DESIGNER MODE ACTIVE", ele, "Big")

			---@type ManageDesignerModeRequest
			local manageDesignerModeRequest = { playersCanDialogue = false, playersCanFight = false }

			Styler:CheapTextAlign("Players:", ele)
			Styler:EnableToggleButton(ele, "Can Enter Combat", false, nil, function(swap)
				if swap then
					manageDesignerModeRequest.playersCanFight = not manageDesignerModeRequest.playersCanFight
					Channels.ManageDesignerMode:SendToServer(manageDesignerModeRequest)
				end
				return manageDesignerModeRequest.playersCanFight
			end)

			ele:AddText(" | ").SameLine = true

			Styler:EnableToggleButton(ele, "Can Enter/Trigger Dialogue", true, nil, function(swap)
				if swap then
					manageDesignerModeRequest.playersCanDialogue = not manageDesignerModeRequest.playersCanDialogue
					Channels.ManageDesignerMode:SendToServer(manageDesignerModeRequest)
				end
				return manageDesignerModeRequest.playersCanDialogue
			end)
		end)

		self.designerPickerInfo = Ext.IMGUI.NewWindow("Picker Help")
		self.designerPickerInfo.Scaling = "Scaled"
		self.designerPickerInfo.Visible = false
		self.designerPickerInfo.Closeable = false
		self.designerPickerInfo.NoResize = true
		self.designerPickerInfo.NoTitleBar = true
		self.designerPickerInfo.NoMove = true
		self.designerPickerInfo.AlwaysAutoResize = true
		self.designerPickerInfo:SetColor("FrameBg", { 1, 1, 1, 0 })
		self.designerPickerInfo:SetBgAlpha(0)

		Styler:CheapTextAlign("Middle-Click to save current value, Left/Right-Click to cancel", self.designerPickerInfo).UserData = "keep"
		Styler:ScaledFont(self.designerPickerInfo, "Large")

		self.existingEncountersWindow = Ext.IMGUI.NewWindow("Existing Encounters")
		self.existingEncountersWindow.Font = MCM.Get("font_size", "755a8a72-407f-4f0d-9a33-274ac0f0b53d")
		self.existingEncountersWindow.Closeable = true
		self.existingEncountersWindow.Open = false
		self.existingEncountersWindow.Scaling = "Scaled"
		self.existingEncountersWindow:SetStyle("WindowMinSize", 500, 800)
	else
		self.designerModeHeader.Open = true

		self.designerWindow.Label = encounter.name
		self.designerWindow.Open = true
		self.designerWindow:SetFocus()
		Helpers:KillChildren(self.designerWindow)
	end

	MCM.CloseMCMWindow()

	Ext.Timer.WaitFor(50, function()
		self.designerModeHeader:SetPos({ 0, 0 }, "Always")
		self.designerPickerInfo:SetPos({ (Ext.IMGUI.GetViewportSize()[1] / 2) - (Ext.IMGUI.GetViewportSize()[1] * .1), 0 }, "Always")
	end)

	Channels.ManageDesignerMode:SendToServer({
		playersCanDialogue = false,
		playersCanFight = false
	} --[[@as ManageDesignerModeRequest]])

	local currentGameLevel

	Channels.GetCurrentHostLevel:RequestToServer(nil, function(levelName)
		if not encounter.gameLevel then
			encounter.gameLevel = levelName
		end
		currentGameLevel = levelName
		if levelName == encounter.gameLevel then
			Channels.ManageEncounterSpawns:SendToServer({
				folderId = encounterMeta.folderId,
				encounterId = encounterMeta.encounterId,
				encounter = (encounter._real or encounter)
			} --[[@as ManageEncounterRequest]])
		end
	end)

	if not TableUtils:TablesAreEqual(encounter.baseCoords, { 0, 0, 0 }) and next(encounter.entities._real or encounter.entities) then
		Channels.OrbAtPosition:SendToServer({
			encounterId = encounterMeta.encounterId,
			context = "BaseCoords",
			coords = encounter.baseCoords._real or encounter.baseCoords,
			moonbeam = 5
		} --[[@as VisualizationRequest]])
	end

	self.designerWindow.OnClose = function()
		Channels.OrbAtPosition:SendToServer({
			encounterId = encounterMeta.encounterId,
			cleanupEncounter = true
		} --[[@as VisualizationRequest]])

		self.designerModeHeader.Open = false
		self.existingEncountersWindow.Open = false
		Channels.ManageDesignerMode:SendToServer({
			playersCanDialogue = true,
			playersCanFight = true
		} --[[@as ManageDesignerModeRequest]])

		Channels.ManageEncounterSpawns:SendToServer({
			folderId = encounterMeta.folderId,
			encounterId = encounterMeta.encounterId,
			delete = true
		} --[[@as ManageEncounterRequest]])

		MCM.OpenMCMWindow()
	end

	if encounter.modId then
		Styler:Color(Styler:CheapTextAlign("MOD-SOURCED ENCOUNTER - You can view, but not edit", self.designerWindow, "Large"), "ErrorText")
	end

	local entityCardsGroup
	local encounterSettingsGroup

	Styler:MiddleAlignedColumnLayout(self.designerWindow, function(ele)
		local levelCombo
		local teleportToLevelButton
		Styler:MiddleAlignedColumnLayout(ele, function(ele)
			ele:AddText("Location:")
			local levels = {}
			for _, level in ipairs(EntityRecorder.Levels) do
				table.insert(levels, level)
			end
			levelCombo = ele:AddCombo("")
			levelCombo.WidthFitPreview = true
			levelCombo.SameLine = true
			levelCombo.Options = levels
			levelCombo.SelectedIndex = (TableUtils:IndexOf(levels, encounter.gameLevel) or 1) - 1

			teleportToLevelButton = Styler:ImageButton(ele:AddImageButton("Teleport_Level", "Spell_Conjuration_DimensionDoor", Styler:ScaleFactor({ 32, 32 })))
			teleportToLevelButton.Visible = false
			teleportToLevelButton.UserData = "EnableForMods"
			teleportToLevelButton.SameLine = true
		end)

		local coordsGroup = ele:AddGroup("coords")
		for i, coord in ipairs({ "X", "Y", "Z" }) do
			coordsGroup:AddText(coord .. ": ").SameLine = i > 1
			local input = coordsGroup:AddInputScalar("", encounter.baseCoords[i])
			input.SameLine = true
			input.ItemWidth = 100
			input.OnChange = function()
				encounter.baseCoords[i] = input.Value[1]
			end
		end

		local pickCoordsButton
		local teleportToCoordsButton

		Styler:MiddleAlignedColumnLayout(ele, function(ele)
			pickCoordsButton = Styler:ImageButton(ele:AddImageButton("PickBaseCoords", "Spell_Divination_TrueStrike", Styler:ScaleFactor({ 48, 48 })))
			pickCoordsButton:Tooltip():AddText(
				"\t Pick a location in the game world to set as the base coordinates for this encounter - has no impact on functionality,\nbut is used for the teleport button to the right and is useful for planning out your encounter")
			pickCoordsButton.UserData = false
			pickCoordsButton.OnClick = function()
				if not pickCoordsButton.UserData then
					pickCoordsButton.UserData = true
					self.designerPickerInfo.Visible = true

					local tickSub = Ext.Events.Tick:Subscribe(function(e)
						local coords = Ext.ClientUI.GetPickingHelper(1).Inner.Position
						for i = 1, 3 do
							coordsGroup.Children[i * 2].Value = { coords[i], coords[i], coords[i], coords[i] }
						end

						Channels.OrbAtPosition:SendToServer({
							encounterId = encounterMeta.encounterId,
							coords = coords,
							context = "BaseCoords"
						} --[[@as VisualizationRequest]])
					end)

					local mouseSub
					mouseSub = Ext.Events.MouseButtonInput:Subscribe(
					---@param e EclLuaMouseButtonEvent
						function(e)
							if e.Pressed then
								for i = 1, 3 do
									if e.Button == saveButton then
										coordsGroup.Children[i * 2]:OnChange()

										if encounter.entities then
											for _, entity in pairs(encounter.entities) do
												if not entity.coordinates or TableUtils:CompareLists(entity.coordinates, { 0, 0, 0 }) then
													entity.coordinates.delete = true
													entity.coordinates = nil
													entity.coordinates = TableUtils:DeeplyCopyTable(encounter.baseCoords)
												end
											end
										end
									else
										coordsGroup.Children[i * 2].Value = { encounter.baseCoords[i], encounter.baseCoords[i], encounter.baseCoords[i], encounter.baseCoords[i] }
									end
								end

								Ext.Events.Tick:Unsubscribe(tickSub)
								Ext.Events.MouseButtonInput:Unsubscribe(mouseSub)
								Channels.OrbAtPosition:SendToServer({
									encounterId = encounterMeta.encounterId,
									cleanupEncounter = true
								} --[[@as VisualizationRequest]])
								pickCoordsButton.UserData = false
								self.designerPickerInfo.Visible = false
							end
						end)
				end
			end
			pickCoordsButton.Visible = false

			teleportToCoordsButton = Styler:ImageButton(ele:AddImageButton("Teleport_Coords", "Spell_Conjuration_DimensionDoor", Styler:ScaleFactor({ 48, 48 })))
			teleportToCoordsButton.UserData = "EnableForMods"
			teleportToCoordsButton:Tooltip():AddText("\t Teleport to the Encounter's Base Coordinates")
			teleportToCoordsButton.OnClick = function()
				Channels.TeleportToCoords:SendToServer({
					x = encounter.baseCoords[1],
					y = encounter.baseCoords[2],
					z = encounter.baseCoords[3],
				})
			end

			local existingCombatGroups = Styler:ImageButton(ele:AddImageButton("SeeExistingGroups", "ico_mode_combat", { 48, 48 }))
			existingCombatGroups.SameLine = true
			existingCombatGroups.Visible = encounter.modId == nil
			existingCombatGroups:Tooltip():AddText("\t Show all existing enemies in their combat groups if applicable with helpful utilities")
			existingCombatGroups.OnClick = function()
				self.existingEncountersWindow.Open = true
				self.existingEncountersWindow:SetFocus()
				ExistingEncounters:renderEncounters(
					self.existingEncountersWindow,
					currentGameLevel,
					encounter,
					function()
						self:RenderCardForEntities(entityCardsGroup,
							encounter.entities,
							currentGameLevel == encounter.gameLevel,
							encounter,
							encounterMeta)

						Channels.ManageEncounterSpawns:SendToServer({
							folderId = encounterMeta.folderId,
							encounterId = encounterMeta.encounterId,
							encounter = (encounter._real or encounter)
						} --[[@as ManageEncounterRequest]])
					end)
			end

			local refreshEntitiesButton = Styler:ImageButton(ele:AddImageButton("RefreshView", "ico_reset_d", Styler:ScaleFactor({ 48, 48 })))
			refreshEntitiesButton.SameLine = true
			refreshEntitiesButton.UserData = "EnableForMods"
			refreshEntitiesButton:Tooltip():AddText("\t Refresh the Entity Card View to match the current window dimensions")
			refreshEntitiesButton.OnClick = function()
				self:RenderCardForEntities(entityCardsGroup,
					encounter.entities,
					currentGameLevel == encounter.gameLevel,
					encounter,
					encounterMeta)
			end

			MazzleDocs:addDocButton(ele, { 48, 48 }).SameLine = true
		end)

		teleportToCoordsButton.Visible = false
		teleportToCoordsButton.SameLine = true
		teleportToLevelButton.OnClick = function()
			Channels.TeleportToLevel:SendToServer({
				LevelName = encounter.gameLevel
			})
			currentGameLevel = encounter.gameLevel
			teleportToCoordsButton.Visible = true
			pickCoordsButton.Visible = true
			teleportToLevelButton.Visible = false
			self:RenderCardForEntities(entityCardsGroup,
				encounter.entities,
				currentGameLevel == encounter.gameLevel,
				encounter,
				encounterMeta)
		end

		local function checkCurrentLevel()
			Channels.GetCurrentHostLevel:RequestToServer(nil, function(levelName)
				currentGameLevel = levelName
				teleportToLevelButton.Visible = levelName ~= encounter.gameLevel
				teleportToCoordsButton.Visible = not teleportToLevelButton.Visible
				pickCoordsButton.Visible = teleportToCoordsButton.Visible

				self:RenderCardForEntities(entityCardsGroup,
					encounter.entities,
					currentGameLevel == encounter.gameLevel,
					encounter,
					encounterMeta)
			end)
		end
		checkCurrentLevel()

		levelCombo.OnChange = function()
			encounter.gameLevel = levelCombo.Options[levelCombo.SelectedIndex + 1]
			checkCurrentLevel()
		end

		Ext.Timer.WaitFor(10, function()
			Styler:DualToggleButton(ele, "Manage Encounter", "Manage Entities", false, function(swap)
				if swap then
					encounterSettingsGroup.Visible = entityCardsGroup.Visible
					entityCardsGroup.Visible = not entityCardsGroup.Visible
				end

				return encounterSettingsGroup.Visible
			end)
		end)
	end)

	entityCardsGroup = self.designerWindow:AddGroup("cards")
	encounterSettingsGroup = self.designerWindow:AddGroup("encounter")
	encounterSettingsGroup.Visible = false

	self:manageEncounterSettings(encounterSettingsGroup, encounter, encounterMeta)

	if encounter.modId then
		Styler:disableNonNavigatableElements(self.designerWindow)
	end
end

---@param parent ExtuiTreeParent
---@param entities {[Guid]: MonsterLabEntity}
---@param renderCoordPickers boolean
---@param encounter MonsterLabEncounter
---@param encounterMeta MonsterLabProfileEncounterEntry
function EncounterDesigner:RenderCardForEntities(parent, entities, renderCoordPickers, encounter, encounterMeta)
	Helpers:KillChildren(parent)

	-- Only using this to determine the width of the container, as it keeps scaling the vertical dimension infinitely
	local cardsWindow = parent:AddChildWindow("Combat Group Cards")
	cardsWindow.AlwaysAutoResize = true
	cardsWindow.Size = { 0, 1 }

	local cardGroup = parent:AddGroup("cards")

	local cardColours = {
		{ 255, 0,   0,   0.5 },
		{ 0,   255, 0,   0.5 },
		{ 0,   0,   255, 0.5 },
		{ 255, 0,   255, 0.5 },
		{ 255, 255, 0,   0.5 },
		{ 0,   255, 255, 0.5 },
	}

	local function renderGroupCards()
		if not entities or (entities.__real and not entities() or not next(entities)) then
			return
		end

		if cardsWindow.LastSize[1] < 1 then
			Ext.Timer.WaitFor(50, function()
				renderGroupCards()
			end)
			return
		end

		Helpers:KillChildren(cardGroup)

		local maxRowSize = math.max(2, math.floor(cardsWindow.LastSize[1] / 400))
		local entriesPerColumn = math.floor(TableUtils:CountElements(entities) / maxRowSize)
		entriesPerColumn = entriesPerColumn > 0 and entriesPerColumn or 1
		local layoutTable = cardGroup:AddTable("cards", math.min(TableUtils:CountElements(entities), maxRowSize))

		local row = layoutTable:AddRow()

		for _ = 1, maxRowSize do
			row:AddCell()
		end

		local counter = 0

		for mlEntityId, mlEntity in TableUtils:OrderedPairs(entities, function(key, value)
			return value.displayName
		end) do
			counter = counter + 1

			---@type CharacterTemplate
			local template = Ext.ClientTemplate.GetTemplate(mlEntity.template)

			---@type ExtuiGroup
			local card = row.Children[(counter % maxRowSize) > 0 and (counter % maxRowSize) or maxRowSize]:AddGroup(mlEntityId)

			local groupTable = card:AddTable("chlidTable", 1)
			groupTable.Borders = true
			groupTable:SetColor("TableBorderStrong", Styler:ConvertRGBAToIMGUI(cardColours[(counter % (#cardColours - (maxRowSize % 2 == 0 and 1 or 0))) + 1]))

			local entityRow = groupTable:AddRow():AddCell()

			Styler:MiddleAlignedColumnLayout(entityRow, function(ele)
				Styler:MiddleAlignedColumnLayout(ele, function(ele)
					local image = ele:AddImage(mlEntity.icon or template.Icon, { 48, 48 })
					if image.ImageData.Icon == "" then
						image:Destroy()
						ele:AddImage("Item_Unknown", { 48, 48 })
					end
					ele:AddDummy(32, 32).SameLine = true
				end)

				local nameLink = Styler:HyperlinkText(ele, mlEntity.displayName, function(parent)
					ResourceManager:RenderDisplayWindow(template, parent)
				end)
				nameLink:SetColor("TextLink", { 0.86, 0.79, 0.68, 0.78 })

				local editEntityButton = Styler:ImageButton(ele:AddImageButton("editEntity", "ico_edit_d", Styler:ScaleFactor({ 24, 24 })))
				editEntityButton.SameLine = true
				editEntityButton.OnClick = function()
					Helpers:KillChildren(self.popup)
					self.popup:Open()

					self.popup:AddSelectable("Edit", "DontClosePopups").OnClick = function()
						MonsterLabEntityCreationForm:create(self.popup, encounter, function()
							Channels.ManageEncounterSpawns:SendToServer({
								folderId = encounterMeta.folderId,
								encounterId = encounterMeta.encounterId,
								encounter = encounter._real
							} --[[@as ManageEncounterRequest]])

							self.popup:SetCollapsed(true)
							self:RenderCardForEntities(parent, entities, renderCoordPickers, encounter, encounterMeta)
						end, mlEntity)
					end

					self.popup:AddSelectable("Copy").OnClick = function()
						entities[FormBuilder:generateGUID()] = TableUtils:DeeplyCopyTable(mlEntity._real)
						Channels.ManageEncounterSpawns:SendToServer({
							folderId = encounterMeta.folderId,
							encounterId = encounterMeta.encounterId,
							encounter = encounter._real
						} --[[@as ManageEncounterRequest]])

						self:RenderCardForEntities(parent, entities, renderCoordPickers, encounter, encounterMeta)
					end

					---@param selectable ExtuiSelectable
					self.popup:AddSelectable("Delete", "DontClosePopups").OnClick = function(selectable)
						if selectable.Label ~= "Delete" then
							entities[mlEntityId].delete = true

							-- Clean up, then respawn
							Channels.ManageEncounterSpawns:SendToServer({
								folderId = encounterMeta.folderId,
								encounterId = encounterMeta.encounterId,
								delete = true
							} --[[@as ManageEncounterRequest]])

							Channels.ManageEncounterSpawns:SendToServer({
								folderId = encounterMeta.folderId,
								encounterId = encounterMeta.encounterId,
								encounter = encounter._real
							} --[[@as ManageEncounterRequest]])

							self.popup:SetCollapsed(true)
							self:RenderCardForEntities(parent, entities, renderCoordPickers, encounter, encounterMeta)
						else
							selectable.Label = "Are You Sure?"
							Styler:Color(selectable, "ErrorText")
							selectable.DontClosePopups = false
						end
					end
				end
			end)


			local pickerPlaceholder = entityRow:AddGroup("pickerButton")
			pickerPlaceholder.Visible = renderCoordPickers

			local coordsGroup = entityRow:AddGroup("coords")
			coordsGroup.SameLine = renderCoordPickers

			---@diagnostic disable-next-line: missing-fields
			local pickCoordsButton = Styler:ImageButton(pickerPlaceholder:AddImageButton("PickCoords", "Spell_Divination_TrueStrike", Styler:ScaleFactor({ 26, 26 })))

			for i, coord in ipairs({ "X", "Y", "Z" }) do
				coordsGroup:AddText(coord .. ": ").SameLine = i > 1
				local input = coordsGroup:AddInputScalar("", mlEntity.coordinates[i])
				input.SameLine = true
				input.ItemWidth = Styler:ScaleFactor() * 85
				input.OnChange = function()
					mlEntity.coordinates[i] = input.Value[1]
				end
			end

			--#region Rotation
			entityRow:AddText("Rotation: ")
			local rotationGroup = entityRow:AddGroup("Rotatations")
			rotationGroup.SameLine = true

			local rotateButton = rotationGroup:AddButton("+.25")
			local rotationValue = rotationGroup:AddInputScalar("", mlEntity.rotation)
			rotationValue.ItemWidth = 85 * Styler:ScaleFactor()
			rotateButton.OnClick = function()
				local newVal = rotationValue.Value[1] + .25
				rotationValue.Value = { newVal, newVal, newVal, newVal }
				rotationValue:OnChange()
			end
			rotationValue.SameLine = true
			rotationValue.OnChange = function()
				mlEntity.rotation = rotationValue.Value[1]

				Channels.ManageEncounterSpawns:SendToServer({
					folderId = encounterMeta.folderId,
					encounterId = encounterMeta.encounterId,
					encounter = {
						entities = {
							[mlEntityId] = mlEntity._real
						}
					}
				} --[[@as ManageEncounterRequest]])
			end

			pickCoordsButton.OnClick = function()
				if not pickCoordsButton.UserData then
					pickCoordsButton.UserData = true
					self.designerPickerInfo.Visible = true
					local entityCopy = TableUtils:DeeplyCopyTable((mlEntity._real or mlEntity))

					local mouseSub
					local buttonSub
					local tickSub

					tickSub = Ext.Events.Tick:Subscribe(function(e)
						local groupExists = pcall(function()
							return coordsGroup.Handle
						end)

						if not groupExists then
							Logger:BasicWarning(
								"Had to cancel picking coordinates due to IMGUI lifetimes expiring somehow, probably due to you using the UI before cancelling out of this process")

							Ext.Events.KeyInput:Unsubscribe(buttonSub)
							Ext.Events.Tick:Unsubscribe(tickSub)
							Ext.Events.MouseButtonInput:Unsubscribe(mouseSub)
							self.designerPickerInfo.Visible = false
						end

						local coords = Ext.ClientUI.GetPickingHelper(1).Inner.Position
						for i = 1, 3 do
							coordsGroup.Children[i * 2].Value = { coords[i], coords[i], coords[i], coords[i] }
						end

						entityCopy.coordinates = coords
						entityCopy.rotation = rotationValue.Value[1]

						local encounterCopy = TableUtils:DeeplyCopyTable(encounter)
						encounterCopy.entities = {
							[mlEntityId] = entityCopy
						}

						Channels.ManageEncounterSpawns:SendToServer({
							folderId = encounterMeta.folderId,
							encounterId = encounterMeta.encounterId,
							encounter = encounterCopy
						} --[[@as ManageEncounterRequest]])
					end)

					buttonSub = Ext.Events.KeyInput:Subscribe(
					---@param e EclLuaKeyInputEvent
						function(e)
							if e.Pressed then
								if e.Key == "F" then
									entityCopy.rotation = rotationValue.Value[1] - .25
								elseif e.Key == "G" then
									entityCopy.rotation = rotationValue.Value[1] + .25
								end
								rotationValue.Value = { entityCopy.rotation, entityCopy.rotation, entityCopy.rotation, entityCopy.rotation }
							end
						end)


					mouseSub = Ext.Events.MouseButtonInput:Subscribe(
					---@param e EclLuaMouseButtonEvent
						function(e)
							if e.Pressed then
								for i = 1, 3 do
									if e.Button == saveButton then
										coordsGroup.Children[i * 2]:OnChange()
										rotationValue:OnChange()
									else
										coordsGroup.Children[i * 2].Value = { mlEntity.coordinates[i], mlEntity.coordinates[i], mlEntity.coordinates[i], mlEntity.coordinates[i] }
										rotationValue.Value = { mlEntity.rotation, mlEntity.rotation, mlEntity.rotation, mlEntity.rotation }
									end
								end
								pickCoordsButton.UserData = false
								Ext.Events.KeyInput:Unsubscribe(buttonSub)
								Ext.Events.Tick:Unsubscribe(tickSub)
								Ext.Events.MouseButtonInput:Unsubscribe(mouseSub)
								self.designerPickerInfo.Visible = false
							end
						end)
				end
			end
			--#endregion

			--#region Animation
			local animationHeader = entityRow:AddCollapsingHeader("Animation")
			animationHeader.UserData = "EnableForMods"
			animationHeader:SetColor("Header", { 0, 0, 0, 0 })
			animationHeader.DefaultOpen = false

			local refreshAnimFunc

			Styler:MiddleAlignedColumnLayout(animationHeader, function(ele)
				Styler:DualToggleButton(ele, "Basic", "Looping", false, function(swap)
					if swap then
						mlEntity.animation.simple = not mlEntity.animation.simple and "" or nil
						refreshAnimFunc()
					end
					return mlEntity.animation.simple ~= nil
				end)
			end)

			local animationGroup = animationHeader:AddGroup("Animations")
			refreshAnimFunc = function()
				Helpers:KillChildren(animationGroup)
				local animationConfig = mlEntity.animation
				if animationConfig.simple then
					---@type ResourceAnimationResource?
					local existingAnimation = Ext.Resource.Get(animationConfig.simple, "Animation")
					local animationInput = animationGroup:AddInputText("", existingAnimation and existingAnimation.SourceFile:match("([^/\\]+)$") or "")
					animationInput.Hint = "Enter UUID"
					animationInput.OnChange = function()
						---@type ResourceAnimationResource
						local animation = Ext.Resource.Get(animationInput.Text, "Animation")
						if animation then
							animationConfig.simple = animation.Guid
							animationInput.Text = animation.SourceFile:match("([^/\\]+)$")
							animationInput:SetColor("Text", { 0.86, 0.79, 0.68, 0.78 })
							Channels.ManageEncounterSpawns:SendToServer({
								folderId = encounterMeta.folderId,
								encounterId = encounterMeta.encounterId,
								encounter = {
									entities = {
										[mlEntityId] = mlEntity._real
									}
								}
							} --[[@as ManageEncounterRequest]])
						else
							animationInput:SetColor("Text", { 1, 0, 0, 0.75 })
						end
					end
				else
					for animationKey, animationId in TableUtils:OrderedPairs(animationConfig.looping) do
						animationGroup:AddText(animationKey)

						---@type ResourceAnimationResource?
						local existingAnimation = Ext.Resource.Get(animationId, "Animation")
						local animationInput = animationGroup:AddInputText("", existingAnimation and existingAnimation.SourceFile:match("([^/\\]+)$") or "")
						animationInput.ItemWidth = 500
						animationInput.Hint = "Enter UUID"
						animationInput.OnChange = function()
							---@type ResourceAnimationResource
							local animation = Ext.Resource.Get(animationInput.Text, "Animation")
							if animation then
								animationConfig.looping[animationKey] = animation.Guid
								animationInput.Text = animation.SourceFile:match("([^/\\]+)$")
								animationInput:SetColor("Text", { 0.86, 0.79, 0.68, 0.78 })

								Channels.ManageEncounterSpawns:SendToServer({
									folderId = encounterMeta.folderId,
									encounterId = encounterMeta.encounterId,
									encounter = {
										entities = {
											[mlEntityId] = mlEntity._real
										}
									}
								} --[[@as ManageEncounterRequest]])
							else
								animationInput:SetColor("Text", { 1, 0, 0, 0.75 })
							end
						end
					end
				end

				animationGroup.ItemReadOnly = encounter.modId ~= nil
			end
			refreshAnimFunc()
			--#endregion

			mlEntity.databaseCalls = mlEntity.databaseCalls or {}
			local databaseHeader = entityRow:AddCollapsingHeader("Databases")
			databaseHeader:SetColor("Header", { 0, 0, 0, 0 })
			databaseHeader.DefaultOpen = false

			self:renderDatabaseSection(databaseHeader, mlEntity.databaseCalls)
		end

		--#region Adding New Entity
		if not encounter.modId then
			---@type ExtuiGroup
			local card = cardGroup:AddGroup("Add New Entity")

			local groupTable = card:AddTable("chlidTable", 1)
			groupTable.Borders = true
			groupTable:SetColor("TableBorderStrong", Styler:ConvertRGBAToIMGUI(cardColours[((counter + 1) % (#cardColours - (maxRowSize % 2 == 0 and 1 or 0))) + 1]))

			local addNewEntityRow = groupTable:AddRow():AddCell()

			---@type ExtuiGroup
			local formGroup
			Styler:MiddleAlignedColumnLayout(addNewEntityRow, function(ele)
				Styler:CheapTextAlign("Add New Entity", ele, "Big")
				ele:AddButton("Launch Form").OnClick = function(button)
					if #formGroup.Children == 0 then
						button.Label = "Close Form"
						MonsterLabEntityCreationForm:create(formGroup, encounter, function()
							Channels.ManageEncounterSpawns:SendToServer({
								folderId = encounterMeta.folderId,
								encounterId = encounterMeta.encounterId,
								encounter = encounter._real
							} --[[@as ManageEncounterRequest]])
							self:RenderCardForEntities(parent, entities, renderCoordPickers, encounter, encounterMeta)
						end)
					else
						button.Label = "Launch Form"
						Helpers:KillChildren(formGroup)
					end
				end
			end)
			formGroup = addNewEntityRow:AddGroup("New Entity")
		end
		--#endregion

		if encounter.modId then
			Styler:disableNonNavigatableElements(cardGroup)
		end
	end

	renderGroupCards()
end

---@param parent ExtuiTreeParent
---@param encounter MonsterLabEncounter
function EncounterDesigner:manageEncounterSettings(parent, encounter, encounterMeta)
	Helpers:KillChildren(parent)

	parent:AddText("Copy Values By Selecting Entity: ")
	local pickEntityButton = Styler:ImageButton(parent:AddImageButton("PickEntityButton", "Spell_Divination_TrueStrike", Styler:ScaleFactor({ 36, 36 })))
	pickEntityButton.SameLine = true
	pickEntityButton.UserData = false

	parent:AddText("CombatGroupId: ")
	local combatGroupId = parent:AddInputText("", encounter.combatGroupId)
	combatGroupId.OnChange = function()
		if #combatGroupId.Text == 36 then
			combatGroupId:SetColor("Text", { 0.86, 0.79, 0.68, 0.78 })
			encounter.combatGroupId = combatGroupId.Text
			Channels.ManageEncounterSpawns:SendToServer({
				folderId = encounterMeta.folderId,
				encounterId = encounterMeta.encounterId,
				encounter = encounter._real
			} --[[@as ManageEncounterRequest]])
		else
			Styler:Color(combatGroupId, "ErrorText")
		end
	end

	combatGroupId.OnDeactivate = function()
		if combatGroupId.Text == "" or #combatGroupId.Text ~= 36 then
			combatGroupId.Text = FormBuilder:generateGUID()
			combatGroupId:OnChange()
		end
	end

	parent:AddText("Faction: ")
	local factionDisplayName
	factionDisplayName = Styler:HyperlinkText(parent, "", function(parent)
		if factionDisplayName.UserData then
			ResourceManager:RenderDisplayWindow(Ext.StaticData.Get(factionDisplayName.UserData, "Faction"), parent)
		end
	end)
	factionDisplayName.SameLine = true

	local factionInput = parent:AddInputText("", encounter.faction)

	local function setFactionDisplayName()
		factionDisplayName.UserData = nil

		if #factionInput.Text == 36 then
			pcall(function(...)
				---@type ResourceFaction?
				local faction = Ext.StaticData.Get(factionInput.Text, "Faction")
				if faction then
					factionDisplayName.Label = faction.Faction
					factionDisplayName.UserData = faction.ResourceUUID
				else
					factionDisplayName.Label = ""
				end
			end)
		else
			factionDisplayName.Label = ""
		end
	end
	setFactionDisplayName()
	factionInput.OnChange = function()
		setFactionDisplayName()
		if #factionDisplayName.Label > 0 then
			factionInput:SetColor("Text", { 0.86, 0.79, 0.68, 0.78 })
			encounter.faction = factionInput.Text
			Channels.ManageEncounterSpawns:SendToServer({
				folderId = encounterMeta.folderId,
				encounterId = encounterMeta.encounterId,
				encounter = encounter._real
			} --[[@as ManageEncounterRequest]])
		else
			Styler:Color(factionInput, "ErrorText")
		end
	end

	factionInput.OnDeactivate = function()
		if #factionInput.Text ~= 36 then
			factionInput.Text = "64321d50-d516-b1b2-cfac-2eb773de1ff6"
			factionInput:OnChange()
		end
	end

	local databaseGroup = parent:AddGroup("Databases")
	databaseGroup:AddText("Databases (?): "):Tooltip():AddText(
		"\t List of Databases this entity is currently added to, which each entity in the encounter will also be added to unless disabled")
	local databaseList = databaseGroup:AddGroup("databaseList")

	encounter.databaseCalls = encounter.databaseCalls or {}
	self:renderDatabaseSection(databaseList, encounter.databaseCalls)

	pickEntityButton.OnClick = function()
		if not pickEntityButton.UserData then
			combatGroupId.Disabled = true
			factionInput.Disabled = true

			pickEntityButton.UserData = true
			self.designerPickerInfo.Visible = true
			local mouseSub
			local tickSub
			local hoveringOverChar
			local dbCallback

			tickSub = Ext.Events.Tick:Subscribe(function(e)
				local picking = Ext.ClientUI.GetPickingHelper(1)

				local isAlive = pcall(function(...)
					return combatGroupId.Handle
				end)

				if not isAlive then
					self.designerPickerInfo.Visible = false
					Ext.Events.Tick:Unsubscribe(tickSub)
					Ext.Events.MouseButtonInput:Unsubscribe(mouseSub)
				end

				if picking and picking.Inner.Inner[1] then
					local entity = picking.Inner.Inner[1].GameObject
					if entity and entity.ClientCharacter and not entity.Vars.AbsolutesLaboratory_MonsterLab_Entity then
						if entity.Uuid.EntityUuid ~= hoveringOverChar then
							hoveringOverChar = entity.Uuid.EntityUuid
							if entity.CombatParticipant and entity.CombatParticipant.CombatGroupId then
								combatGroupId.Text = entity.CombatParticipant.CombatGroupId
							end

							if entity.Faction and entity.Faction.field_8 then
								factionInput.Text = entity.Faction.field_8
								setFactionDisplayName()
							end

							Channels.GetDBEntries_ForEntity:RequestToServer({
									entityId = entity.Uuid.EntityUuid
								} --[[@as GetDBEntriesRequest]],

								---@param data GetDBEntriesResponse
								function(data)
									if hoveringOverChar and next(data.list) then
										dbCallback = self:renderDatabaseSection(databaseList, encounter.databaseCalls, data, hoveringOverChar)
									end
								end)
						end
					elseif hoveringOverChar then
						hoveringOverChar = nil
						pcall(function(...)
							combatGroupId.Text = encounter.combatGroupId
							factionInput.Text = encounter.faction
							setFactionDisplayName()
							self:renderDatabaseSection(databaseList, encounter.databaseCalls)
							dbCallback = nil
						end)
					end
				end
			end)

			mouseSub = Ext.Events.MouseButtonInput:Subscribe(
			---@param e EclLuaMouseButtonEvent
				function(e)
					if e.Pressed then
						if e.Button == saveButton then
							combatGroupId:OnChange()
							factionInput:OnChange()
							combatGroupId:OnDeactivate()
							factionInput:OnDeactivate()

							if dbCallback then
								dbCallback()
							end
						else
							combatGroupId.Text = encounter.combatGroupId
							factionInput.Text = encounter.faction
							self:renderDatabaseSection(databaseList, encounter.databaseCalls)
						end
						self.designerPickerInfo.Visible = false
						factionInput.Disabled = false
						combatGroupId.Disabled = false
						Ext.Events.Tick:Unsubscribe(tickSub)
						Ext.Events.MouseButtonInput:Unsubscribe(mouseSub)

						pickEntityButton.UserData = false
					end
				end)
		end
	end
end

---@param parent ExtuiTreeParent
---@param existingConfig {[string]: MonsterLab_DatabaseEntry}
---@param serverResponse GetDBEntriesResponse?
---@param inspectedEntity Guid?
---@return fun()?
function EncounterDesigner:renderDatabaseSection(parent, existingConfig, serverResponse, inspectedEntity)
	Helpers:KillChildren(parent)

	local deferChangesForCallback = inspectedEntity ~= nil

	if not deferChangesForCallback then
		---@param button ExtuiButton
		parent:AddButton("Delete All Entries").OnClick = function(button)
			if button.Label ~= "Delete All Entries" then
				for k, entry in TableUtils:OrderedPairs(existingConfig) do
					entry.delete = true
					existingConfig[k] = nil
				end

				self:renderDatabaseSection(parent, existingConfig)
			else
				button.Label = "Are You Sure?"
				Styler:Color(button, "ErrorText")
			end
		end

		local addEntryButton = parent:AddButton("Add New Entry")
		addEntryButton:Tooltip():AddText("Define a custom DB entry - you will be responsible for filling out all required parameters")
		addEntryButton.SameLine = true
		addEntryButton.OnClick = function()
			existingConfig["NEW ENTRY"] = {
				enabled = true,
				parameters = {}
			}

			self:renderDatabaseSection(parent, existingConfig)
		end
	end

	---@type ExtuiTable
	local entryTable

	local function buildTable(name, entries)
		entryTable = parent:AddTable(name, deferChangesForCallback and 2 or 3)
		entryTable.UserData = entries

		if not deferChangesForCallback then
			entryTable:AddColumn("buttons", "WidthFixed", 110)
		end
		entryTable:AddColumn("name" .. name)
		entryTable:AddColumn("params" .. name)

		entryTable.Borders = false
		entryTable.BordersH = true
		entryTable.BordersOuterV = true
		entryTable.SizingFixedFit = true
		entryTable.RowBg = true
		entryTable:SetStyle("CellPadding", 1, 10)

		entryTable:SetColor("TableRowBg", Styler:ConvertRGBAToIMGUI({ 24, 24, 24, 1 }))
		entryTable:SetColor("TableRowBgAlt", Styler:ConvertRGBAToIMGUI({ 40, 40, 40, 0.96 }))
	end

	---@type {[string]: MonsterLab_DatabaseEntry}
	local queuedChanges = {}

	---@param key string
	---@param entry MonsterLab_DatabaseEntry
	---@param tableRef ExtuiTable
	local function renderCalls(key, entry, tableRef)
		local entryRow = tableRef:AddRow()
		local lastKnownKey = key

		local nameCol, paramCol

		if not deferChangesForCallback then
			local buttonCol = entryRow:AddCell()
			buttonCol.Disabled = false

			local deleteButton = Styler:ImageButton(buttonCol:AddImageButton("delete", "ico_red_x", { 24, 24 }))
			deleteButton:Tooltip():AddText("Remove this entry from the config")
			deleteButton.Disabled = false
			deleteButton.OnClick = function()
				tableRef.UserData[lastKnownKey].delete = true
				tableRef.UserData[lastKnownKey] = nil
				self:renderDatabaseSection(parent, existingConfig)
			end

			local disableButton = Styler:ImageButton(buttonCol:AddImageButton("disable", entry.enabled and "ico_concentration" or "Spell_Necromancy_Blindness", { 24, 24 }))
			disableButton.SameLine = true
			disableButton.Disabled = false
			disableButton:Tooltip():AddText(entry.enabled
				and
				"Disable this entry - you won't be able to edit it unless re-enabled, but this entry will be removed from the DB next time this encounter is processed and won't be re-inserted until enabled"
				or "Enable this entry - this database entry will be inserted next time this encounter is processed")

			disableButton.OnClick = function()
				entry.enabled = not entry.enabled
				Helpers:KillChildren(tableRef)
				for key, entry in TableUtils:OrderedPairs(tableRef.UserData) do
					renderCalls(key, entry, tableRef)
				end
			end

			if self.dbIndex[entry.name] then
				local seeExistingEntriesButton = Styler:ImageButton(buttonCol:AddImageButton("seeExisting", "campFollowers_btn_ico_h", { 24, 24 }))
				seeExistingEntriesButton.SameLine = true
				seeExistingEntriesButton:Tooltip():AddText("See all entries that are currently in this database. You can copy any value from the rendered table")

				seeExistingEntriesButton.OnClick = function()
					Helpers:KillChildren(self.popup)

					Channels.GetDBEntries_ForDatabase:RequestToServer(entry.name,
						---@param data string[][]
						function(data)
							local fullDatabaseString = entry.name .. "("
							for i, param in ipairs(self.dbIndex[entry.name]) do
								fullDatabaseString = fullDatabaseString .. param
								if i < #self.dbIndex[entry.name] then
									fullDatabaseString = fullDatabaseString .. ", "
								end
							end
							fullDatabaseString = fullDatabaseString .. ")"
							self.popup:AddText(fullDatabaseString).Font = "Big"

							if not data or not next(data) then
								self.popup:AddText("No Results Found").Font = "Large"
							else
								local scrollingWindow = self.popup:AddChildWindow("results")
								scrollingWindow.NoSavedSettings = true
								scrollingWindow:SetSizeConstraints({ 0, 0 }, { 10000, 600 })
								scrollingWindow.AlwaysAutoResize = true

								local tbl = scrollingWindow:AddTable("existing", #self.dbIndex[entry.name])
								tbl.RowBg = true
								tbl:SetColor("TableRowBg", Styler:ConvertRGBAToIMGUI({ 24, 24, 24, 1 }))
								tbl:SetColor("TableRowBgAlt", Styler:ConvertRGBAToIMGUI({ 40, 40, 40, 0.96 }))
								tbl.Borders = true
								tbl.SizingFixedFit = true

								local headerRow = tbl:AddRow()
								headerRow.Headers = true

								for _, param in ipairs(self.dbIndex[entry.name]) do
									headerRow:AddCell():AddText(param)
								end

								for _, columns in TableUtils:OrderedPairs(data, function(_, value)
									return tostring(value[1])
								end) do
									local row = tbl:AddRow()
									for _, column in ipairs(columns) do
										local cell = row:AddCell()
										Styler:SelectableText(cell, column, column)
									end
								end
							end

							self.popup:Open()
						end)
				end
			end
		end

		nameCol = entryRow:AddCell()
		nameCol.Disabled = deferChangesForCallback or not entry.enabled
		local databaseName = nameCol:AddInputText("", entry.name)
		databaseName.ItemReadOnly = false
		databaseName.Hint = "Database Name - Min 3 Chars"
		databaseName.SizeHint = { Styler:calculateTextDimensions(entry.name or "Database Name - Min 3 Chars", 150) }
		databaseName.AutoSelectAll = true

		local databaseSearchResult = nameCol:AddChildWindow("results")
		databaseSearchResult.Size = { 0, 300 }
		databaseSearchResult.Visible = false

		paramCol = entryRow:AddCell()
		paramCol.Disabled = deferChangesForCallback or not entry.enabled

		---@param params MonsterLab_DatabaseParam[]
		local function renderParams(params)
			Helpers:KillChildren(paramCol)

			for i, param in TableUtils:OrderedPairs(params) do
				paramCol:AddText(("%s%d: "):format(i < 10 and "  " or "", i))
				local input = paramCol:AddInputText("",
					param.value
					or (param.type == "CHARACTER" and self.mlDynamicClasses.constants.entityParamPlaceholder)
					or param.type)

				input.SizeHint = { Styler:calculateTextDimensions(input.Text) }
				input.Hint = param.type
				input.SameLine = true
				input.AutoSelectAll = true

				local tooltip = input:Tooltip()

				tooltip:AddText("Type: " .. param.type).UserData = "keep"

				if param.type == "CHARACTER" then
					tooltip:AddText(("Write %s to use the Monster Lab entity being processed as the value.\nOtherwise, value must be in <NAME OF TEMPLATE>_<ENTITY_UUID> format (NOT TemplateName, just the Name node on the template).\nExample: S_WYR_MerchantsHouse_Thug_002_e7fc87a2-2320-43fc-83b3-5c9bc2076efe")
						:format(self.mlDynamicClasses.constants.entityParamPlaceholder)).UserData = "keep"
				end

				tooltip:AddText("\nTab out or click on another element to save your changes (Table will re-sort all rows after)").UserData = "keep"

				if input.Text == param.type then
					Styler:Color(input, "ErrorText")
					Styler:Color(tooltip:AddText("Value is needed"), "ErrorText")
				end

				input.OnDeactivate = function()
					Helpers:KillChildren(tooltip)

					if #input.Text > 0 then
						input.SizeHint = { Styler:calculateTextDimensions(input.Text) }

						Styler:Color(input, "DefaultText")

						local newEntry = TableUtils:DeeplyCopyTable(entry)
						newEntry.parameters[i].value = input.Text

						local newKey = self:constructDatabaseKey(newEntry)

						if newKey ~= lastKnownKey then
							if queuedChanges[newKey] or existingConfig[newKey] then
								Styler:Color(input, "ErrorText")
								Styler:Color(tooltip:AddText(
										"An entry with this Database name and these parameter values already exists (includes disabled entries).\nChanges won't be saved until a different permutation is provided (can also delete the other entry, then come back and make an arbitrary change to this input)"),
									"ErrorText")
							else
								local configToCheck = deferChangesForCallback and queuedChanges or existingConfig

								if lastKnownKey then
									configToCheck[lastKnownKey].delete = true
									configToCheck[lastKnownKey] = nil
								end
								lastKnownKey = newKey

								configToCheck[newKey] = newEntry
								Helpers:KillChildren(tableRef)
								for key, entry in TableUtils:OrderedPairs(tableRef.UserData) do
									renderCalls(key, entry, tableRef)
								end
							end
						else
							if input.Text == param.type then
								Styler:Color(input, "ErrorText")
								Styler:Color(tooltip:AddText("Value is needed"), "ErrorText")
							end
						end
					else
						Styler:Color(input, "ErrorText")
						Styler:Color(tooltip:AddText("Must provide a value. Changes won't save until one is provided"), "ErrorText")
					end
				end
			end
		end

		renderParams(entry.parameters)

		local nameChangeTimer
		databaseName.OnChange = function()
			if nameChangeTimer then
				Ext.Timer.Cancel(nameChangeTimer)
			end

			nameChangeTimer = Ext.Timer.WaitFor(300, function()
				if #databaseName.Text >= 3 then
					local searchName = Helpers:SanitizeStringForFind(databaseName.Text:upper())

					Helpers:KillChildren(databaseSearchResult)
					databaseSearchResult.Visible = true

					for name, params in TableUtils:OrderedPairs(self.dbIndex, nil, function(key, value)
						return key:upper():find(searchName) ~= nil
					end) do
						local fullDatabaseString = name .. "("
						for i, param in ipairs(params) do
							fullDatabaseString = fullDatabaseString .. param
							if i < #params then
								fullDatabaseString = fullDatabaseString .. ", "
							end
						end
						fullDatabaseString = fullDatabaseString .. ")"

						databaseSearchResult.Size = { math.max(databaseSearchResult.Size[1], Styler:calculateTextDimensions(fullDatabaseString)), 300 }

						---@type MonsterLab_DatabaseEntry
						local newEntry = {
							enabled = entry.enabled,
							name = name,
							parameters = {}
						}

						for _, param in ipairs(params) do
							table.insert(newEntry.parameters, {
								type = param,
								value = param == "CHARACTER" and self.mlDynamicClasses.constants.entityParamPlaceholder or param
							} --[[@as MonsterLab_DatabaseParam]])
						end

						local newKey = self:constructDatabaseKey(newEntry)

						local nameSelect = databaseSearchResult:AddSelectable(fullDatabaseString)

						if queuedChanges[newKey] or existingConfig[newKey] then
							nameSelect.Disabled = true
							Styler:Color(
								nameSelect:Tooltip():AddText("A blank entry for this database already exists - you can't select this until that one is filled out or deleted"),
								"ErrorText")
						end

						nameSelect.OnClick = function()
							local configToCheck = deferChangesForCallback and queuedChanges or existingConfig
							if lastKnownKey then
								configToCheck[lastKnownKey].delete = true
								configToCheck[lastKnownKey] = nil
							end

							lastKnownKey = newKey

							configToCheck[newKey] = newEntry

							Helpers:KillChildren(tableRef)
							for key, entry in TableUtils:OrderedPairs(tableRef.UserData) do
								renderCalls(key, entry, tableRef)
							end
						end
					end
				end

				nameChangeTimer = nil
			end)
		end
	end

	if serverResponse and next(serverResponse) then
		parent:AddSeparatorText("From Hovered Entity (Deduped against current config)"):SetStyle("SeparatorTextAlign", 0.5)

		buildTable("entries", serverResponse.list)

		for databaseName, paramList in TableUtils:OrderedPairs(serverResponse.list) do
			for _, params in TableUtils:OrderedPairs(paramList, function(key, value)
				return value[1]
			end) do
				---@type MonsterLab_DatabaseEntry
				local entry = {
					name = databaseName,
					parameters = {},
					enabled = true
				}

				for i, param in ipairs(params) do
					table.insert(entry.parameters, {
						type = self.dbIndex[databaseName][i],
						value = (type(param) == "string" and param:sub(-36) == inspectedEntity and self.mlDynamicClasses.constants.entityParamPlaceholder) or param
					} --[[@as MonsterLab_DatabaseParam]])
				end

				local key = self:constructDatabaseKey(entry)
				if not existingConfig[key] then
					queuedChanges[key] = entry
					renderCalls(key, entry, entryTable)
				end
			end
		end
	end

	if next(existingConfig) then
		if serverResponse and next(serverResponse) then
			parent:AddSeparatorText("From Current Config"):SetStyle("SeparatorTextAlign", 0.5)
		end

		buildTable("existingEntries", existingConfig)

		for key, entry in TableUtils:OrderedPairs(existingConfig) do
			renderCalls(key, entry, entryTable)
		end
	end

	return function()
		for key, entry in pairs(queuedChanges) do
			existingConfig[key] = entry
		end

		self:renderDatabaseSection(parent, existingConfig)
	end
end

---@param entry MonsterLab_DatabaseEntry
---@return string
function EncounterDesigner:constructDatabaseKey(entry)
	if not entry.name then
		return ""
	end

	local str = entry.name .. "("

	if entry.parameters and next(entry.parameters) then
		for i, param in ipairs(entry.parameters) do
			str = str .. (param.value or param.type)
			if i < #entry.parameters then
				str = str .. ", "
			end
		end
	end

	str = str .. ")"
	return str
end

---@param parent ExtuiTreeParent
---@param encounter MonsterLabEncounter
function EncounterDesigner:renderTriggersSection(parent, encounter)
	local sep = parent:AddSeparatorText("Trigger-Based Spawning (?)")
	sep:SetStyle("SeparatorTextAlign", 0.5, 0.5)
	sep:Tooltip():AddText("\t TODO")

	encounter.spawnTrigger = encounter.spawnTrigger or {
		enabled = false
	}

	Styler:EnableToggleButton(parent, "Enable", false, nil, function(swap)
		if swap then
			encounter.spawnTrigger.enabled = not encounter.spawnTrigger.enabled
		end

		return encounter.spawnTrigger.enabled
	end)

	parent:AddText("Trigger Type: ")
	local triggerType = parent:AddCombo("")
	triggerType:Tooltip():AddText("\t Changing this value will wipe the current settings")

	triggerType.Options = { "GlobalTrigger", "NPC" }
end

---@return {[string]: MazzleDocsContentItem}
function EncounterDesigner:generateChangelog()
	return {
		["1.13.1"] = {
			type = "Bullet",
			text = {
				"Introduce a toggle to swap between managing encounter-level and entity-level settings",
			}
		},
		["1.12.3"] = {
			type = "Bullet",
			text = {
				"Prevent editing of mod-sourced encounters",
				"Add fallback logic to coordinate picker when the user exits out of the view without cancelling the picker"
			}
		},
		["1.11.1"] = {
			type = "Bullet",
			text = {
				"Fix a couple of UI bugs due to improper cleanup and Cahoot being a nonce",
				"Increase font size of the banner at the top of the screen when using the world picker",
				"Set windows to use SE-based scaling math instead of manual calculations",
				"Set minimum sizing on the Existing Encounter window",
				"Fix miscellaneous UI bugs",
				"When the base coordinate for the encounter is set, update all entities with coords [0,0,0] to be the encounter's coords"
			}
		},
		["1.10.5"] = {
			type = "Bullet",
			text = "Make row calculation logic more robust"
		},
		["1.10.4"] = {
			type = "Bullet",
			text = "Fix error when clearing an encounter that hasn't spawned in every entity"
		},
		["1.8.0"] = {
			type = "Bullet",
			text = "Initial Release"
		}
	} --[[@as {[string]: MazzleDocsContentItem}]]
end
