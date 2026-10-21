-- UI for ForceCleanUtility (Server/Mutations/ForceCleanUtility.lua) - a recovery tool for when the normal
-- per-entity Undo has nothing to undo because its tracking variable was lost (most commonly: Absolute's
-- Laboratory itself was fully uninstalled while a mod's Mutations were still applied, then the game was
-- saved/reloaded in that state, wiping the record of what to revert). See ForceCleanUtility.lua's header
-- comment for exactly what this can and can't recover.

---@class ForceCleanWindow
ForceCleanWindow = {
	---@type ExtuiWindow?
	window = nil,
}

function ForceCleanWindow:Launch()
	if not self.window then
		self.window = Ext.IMGUI.NewWindow("Force Clean By Mutation Folder")
		self.window.Closeable = true
		self.window.Scaling = "Scaled"
		self.window:SetStyle("WindowMinSize", 500, 300)
		self.window:SetSize({ 700, 500 }, "FirstUseEver")
	else
		self.window.Open = true
		self.window:SetFocus()
	end

	self:renderPicker()
end

function ForceCleanWindow:renderPicker()
	Helpers:KillChildren(self.window)

	self.window:AddText(
		"This is a recovery tool for when the normal Undo button has nothing to undo - most commonly because Absolute's Laboratory itself was fully uninstalled while a mod's Mutations were still applied, then the save was reloaded in that state, wiping the record of what to put back."
	).TextWrapPos = 0

	self.window:AddText(
		"It does NOT rely on that per-entity record. Instead, for every character currently loaded on your CURRENT level, it checks directly for any Passive, Status, or Spell that the folder you pick below COULD have granted (loose entries plus anything hand-authored in the Lists it references, including linked Lists) and strips whatever's actually present."
	).TextWrapPos = 0

	self.window:AddSeparator()

	local warningHeader = self.window:AddText("This will NOT catch:")
	Styler:Color(warningHeader, "ErrorText")

	self.window:AddBulletText("Ability score / Health / Level / Class-and-subclass / Equipment / Boost / Action Resource / Progression changes - there's no safe way to detect or revert these without the lost record")
	self.window:AddBulletText("Spells a config REMOVED from a character - there's no record left of what those were")
	self.window:AddBulletText("Passives/Spells/Statuses that only came from this game's own vanilla class-progression auto-population, rather than being hand-picked in a List")
	self.window:AddBulletText("Characters on a different level than the one you're currently on - revisit each affected level and run this again")

	self.window:AddSeparator()
	self.window:AddText("Pick the Mutation Folder to clean up after:")

	local folderGroup = self.window:AddChildWindow("forceCleanFolders")
	folderGroup.Size = { 0, 220 * Styler:ScaleFactor() }
	folderGroup.NoSavedSettings = true

	local hasFolders = false
	for folderId, folder in TableUtils:OrderedPairs(MutationConfigurationProxy.folders, function(key, value)
		return value.name
	end) do
		hasFolders = true

		local modName
		if folder.modId then
			local mod = Ext.Mod.GetMod(folder.modId)
			modName = mod and mod.Info.Name or "an uninstalled mod"
		end

		local select = folderGroup:AddSelectable(folder.name .. (modName and (" (from " .. modName .. ")") or " (your own)"))
		select.OnClick = function()
			self:renderConfirmation(folderId, folder.name)
		end
	end

	if not hasFolders then
		local emptyText = folderGroup:AddText(
			"No Mutation Folders found. If the folder you want belongs to a config mod (like Cahoot's), that mod needs to be enabled in your mod list and your save reloaded for its data to show up here - Force Clean reads a config mod's folder definition straight from that mod's own files, so the mod has to actually be loaded this session, the same as any other mod's content. You do NOT need to select it as your active Profile in the Execution Hub, just have it present in your load order."
		)
		emptyText.TextWrapPos = 0
	end
end

---@param folderId Guid
---@param folderName string
function ForceCleanWindow:renderConfirmation(folderId, folderName)
	Helpers:KillChildren(self.window)

	self.window:AddText(("Clean up everything Passive/Status/Spell the folder \"%s\" could have granted, on every character currently loaded on your current level?"):format(folderName))
		.TextWrapPos = 0

	local warning = self.window:AddText(
		"This isn't reversible through the normal Undo button - if it removes something by mistake (e.g. a vanilla passive that happens to share a GUID with one in this folder), you'll need to add it back manually.")
	warning.TextWrapPos = 0
	Styler:Color(warning, "ErrorText")

	local confirmButton = self.window:AddButton("Confirm and Clean")
	confirmButton.OnClick = function()
		Helpers:KillChildren(self.window)
		self.window:AddText(
			"Cleaning current level - watch the status box in the corner of your screen for live progress. This runs a few characters at a time so it won't freeze the game; feel free to close this window, it'll keep going in the background and this window will show the result when it's done."
		).TextWrapPos = 0

		Channels.ForceCleanByFolder:SendToServer(folderId)
	end

	local cancelButton = self.window:AddButton("Cancel")
	cancelButton.SameLine = true
	cancelButton.OnClick = function()
		self:renderPicker()
	end
end

-- Force Clean's actual clean-up pass runs asynchronously across several game ticks (see
-- ForceCleanUtility.lua's CleanCurrentLevelAsync), so its result can't come back as a direct reply to the
-- request that kicked it off - it arrives later on this separate channel instead. Progress in the meantime
-- is shown by the normal Mutation status window (Channels.MutationExecutionStatus), same as Apply/Undo
-- Mutations Now.
---@param data {entitiesCleaned: integer, passivesRemoved: integer, statusesRemoved: integer, spellsRemoved: integer}|{error: string}
Channels.ForceCleanResult:SetHandler(function(data, user)
	if not ForceCleanWindow.window then
		return
	end

	Helpers:KillChildren(ForceCleanWindow.window)

	if data.error then
		Styler:Color(ForceCleanWindow.window:AddText(data.error), "ErrorText")
	else
		ForceCleanWindow.window:AddText(("Done. Touched %d character(s) on this level: removed %d passive(s), %d status(es), %d spell(s)."):format(
			data.entitiesCleaned, data.passivesRemoved, data.statusesRemoved, data.spellsRemoved)).TextWrapPos = 0

		if data.entitiesCleaned == 0 then
			ForceCleanWindow.window:AddText(
				"Nothing was found on this level - if you expected changes here, double check you're on the right level, or the changes may be in a category this tool can't catch (see the list on the previous screen)."
			).TextWrapPos = 0
		end
	end

	local backButton = ForceCleanWindow.window:AddButton("Back")
	backButton.OnClick = function()
		ForceCleanWindow:renderPicker()
	end
end)
