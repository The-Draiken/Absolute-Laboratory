---@class MutationProfileExecutionHub
MutationProfileExecutionHub = {
	config = ConfigurationStructure.config.mutations.settings.profileExecution,
	---@type ExtuiWindow
	window = nil,
	---@type ExtuiWindow
	tutorialWindow = nil,
}

Channels.LaunchTutorial:SetHandler(function(data, user)
	MutationProfileExecutionHub:launchHubWindow(true)
end)

---@param fromEvent boolean?
function MutationProfileExecutionHub:launchHubWindow(fromEvent)
	if fromEvent and self.config.viewedTutorial then
		return
	end

	if not self.window then
		self.window = Ext.IMGUI.NewWindow("Mutation Profile Execution Hub")
		self.window.Closeable = true
		self.window.Scaling = "Scaled"
		self.window:SetStyle("WindowMinSize", 400, 400)
		self.window:SetSize({ 1300, 700 }, "FirstUseEver")
		self.window:SetColor("WindowBg", Styler:ConvertRGBAToIMGUI({ 0, 0, 0, 1 }))
	else
		self.window.Open = true
		self.window:SetFocus()
	end

	Helpers:KillChildren(self.window)

	local mainLayout = Styler:TwoColumnTable(self.window)

	local layoutRow = mainLayout:AddRow()

	local settingsColumn = layoutRow:AddCell()

	local docsView = layoutRow:AddCell():AddChildWindow("Tutorial Docs")

	self:renderSettingsView(settingsColumn)

	self:renderTutorialWindow(docsView, fromEvent)
end

---@param parent ExtuiTreeParent
function MutationProfileExecutionHub:renderSettingsView(parent)
	Helpers:KillChildren(parent
	)
	local titleSep = parent:AddSeparatorText("Execution Settings")
	titleSep:SetStyle("SeparatorTextAlign", 0.5)

	Styler:ScaledFont(parent:AddText("1 permit == 1 entity that can be processed\nThe goal is playable, not lag-free"), Styler.FontSize.Small):SetStyle("Alpha", 0.7)

	if self.config.targetLatency < 33 then
		self.config.targetLatency = 33
	end

	if self.config.minimumPermits >= self.config.initialPermits then
		self.config.minimumPermits = math.max(1, self.config.initialPermits - 1)
	end

	local settingTable = Styler:TwoColumnTable(parent, "Settings")

	---@param label string
	---@param tooltip string?
	---@param configKey string
	---@param minimumValue (fun(): number)?
	local function buildRow(configKey, label, tooltip, minimumValue)
		minimumValue = minimumValue or function() return 1 end

		local row = settingTable:AddRow()
		local labelText = row:AddCell():AddText(label)
		if tooltip then
			labelText.Label = labelText.Label .. " (?)"
			labelText:Tooltip():AddText("\t " .. tooltip)
		end

		local input = row:AddCell():AddInputInt("", self.config[configKey])
		input.ItemWidth = 80
		input.OnChange =
		---@param input ExtuiInputInt
			function(input)
				if input.Value[1] < minimumValue() then
					input.Value = { self.config[configKey], self.config[configKey], self.config[configKey], self.config[configKey] }
				end

				self.config[configKey] = input.Value[1]
			end

		input.OnDeactivate = function()
			self:renderSettingsView(parent)
		end
	end

	buildRow("targetLatency",
		"Target Latency (ms)",
		[[How long a tick is allowed to take to be considered 'Healthy', in milliseconds (ms). Minimum is 33ms.
If this value is exceeded, the number of permits will be reduced, otherwise it will be increased.
I don't recommend increasing this, but if you're on a machine with a weak CPU it may help with the permits aggressively throttling down to the minimum]],
		function() return 33 end)

	buildRow("initialPermits",
		"Initial Permits",
		"How many permits are available at the start of execution. This will increase (unbounded) or decrease (down to minimum permits), depending on execution time per tick")

	buildRow("minimumPermits",
		"Minimum Permits",
		"The lower limit of permits - it won't decrease below this even if you keep experiencing unhealthy tick times. Must be <= Initial Permits")

	local executionModeRow = settingTable:AddRow()
	local executionModeLabel = executionModeRow:AddCell():AddText("Execution Method")
	executionModeLabel.Label = executionModeLabel.Label .. " (?)"
	executionModeLabel:Tooltip():AddText([[
Tick-Based (Default): spreads processing across multiple game ticks using the permit settings above - keeps the game responsive, but takes longer overall.
Instant (Legacy): processes every eligible entity in one uninterrupted burst, closer to how Lab worked before 1.12. Faster overall, but the game may hitch or feel briefly unresponsive while it runs - don't move or take actions until the status window says it's done.
This applies both to automatic executions (combat start, level load) and to the "Apply Mutations Now" / "Undo Mutations Now" buttons in the Mutations tab.]])

	local executionModeCombo = executionModeRow:AddCell():AddCombo("")
	executionModeCombo.WidthFitPreview = true
	executionModeCombo.Options = { "Tick-Based (Default)", "Instant (Legacy)" }
	executionModeCombo.SelectedIndex = self.config.executionMode == "Instant" and 1 or 0
	executionModeCombo.OnChange = function()
		self.config.executionMode = executionModeCombo.SelectedIndex == 1 and "Instant" or "TickBased"
	end

	local statusViewRow = settingTable:AddRow()
	local statusViewLabel = statusViewRow:AddCell():AddText("Status Window")
	statusViewLabel.Label = statusViewLabel.Label .. " (?)"
	statusViewLabel:Tooltip():AddText(
		"Controls whether/how a small window pops up in the corner of your screen to let you know Mutations are currently being Applied or Undone - whether that was triggered automatically or via the buttons in the Mutations tab. Set to Off to go back to no indication at all.")

	local statusViewCombo = statusViewRow:AddCell():AddCombo("")
	statusViewCombo.WidthFitPreview = true
	statusViewCombo.Options = { "Detailed", "Simple", "Off" }
	statusViewCombo.SelectedIndex = self.config.statusView == "Detailed" and 0 or (self.config.statusView == "Off" and 2 or 1)
	statusViewCombo.OnChange = function()
		self.config.statusView = statusViewCombo.Options[statusViewCombo.SelectedIndex + 1]
	end

	local applyTriggerRow = settingTable:AddRow()
	local applyTriggerLabel = applyTriggerRow:AddCell():AddText("Apply Trigger")
	applyTriggerLabel.Label = applyTriggerLabel.Label .. " (?)"
	applyTriggerLabel:Tooltip():AddText([[
Always (Default): applies your active Profile to every eligible entity on the level as soon as it loads, same as always. Entities that get missed (spawn late, etc.) are still caught individually the moment they enter combat.
Combat Only: skips the level-load sweep entirely - nobody gets mutated just for existing on the level. Instead, each entity is mutated the moment it actually enters combat, batched with anyone else joining the same fight in that instant. Enemies that never fight you are never touched at all, which is the whole point - far less CPU spent per level, at the cost of a very brief pause/status window pop right as a fight starts instead of at load.
Off: Lab does nothing automatically at all - not even its usual safety-net Undo pass when no Profile is active. Use this once you have confirmed everything is already clean (e.g. via the Undo button or Force Clean) and just want Lab to sit completely idle from now on. This is different from simply having no Profile active/selected - with an active Profile of "Always" or "Combat Only", Lab still automatically re-scans and undoes anything left over on every level load and combat entry, even if that scan usually finds nothing; Off skips that scan entirely too.
None of these affect the "Apply Mutations Now"/"Undo Mutations Now" buttons, which always run a full level sweep regardless of this setting - they are meant as manual overrides either way, including while Off is selected.]])

	local applyTriggerCombo = applyTriggerRow:AddCell():AddCombo("")
	applyTriggerCombo.WidthFitPreview = true
	applyTriggerCombo.Options = { "Always (Default)", "Combat Only", "Off" }
	applyTriggerCombo.SelectedIndex = self.config.applyTrigger == "CombatOnly" and 1 or (self.config.applyTrigger == "Off" and 2 or 0)
	applyTriggerCombo.OnChange = function()
		self.config.applyTrigger = applyTriggerCombo.Options[applyTriggerCombo.SelectedIndex + 1] == "Combat Only" and "CombatOnly"
			or applyTriggerCombo.Options[applyTriggerCombo.SelectedIndex + 1] == "Off" and "Off"
			or "Always"
	end

	local pauseCombatRow = settingTable:AddRow()
	local pauseCombatLabel = pauseCombatRow:AddCell():AddText("Pause Combat While Mutating")
	pauseCombatLabel.Label = pauseCombatLabel.Label .. " (?)"
	pauseCombatLabel:Tooltip():AddText([[
When entities are mutated because they just entered a fight (always the case under Combat Only, and for stragglers under Always), the combat is paused until their Mutations - and the engine's replication of them - have finished, then resumed automatically.
Without this, turns (including enemy AI planning) run against enemies whose classes, level and spellbook are still being rebuilt, which can cause lag spikes, softlocks, or crashes right as a fight starts.
Combats paused by something else (dialogue, cinematics) are never touched. A failsafe resumes the fight after 20 seconds no matter what.]])

	local pauseCombatCheckbox = pauseCombatRow:AddCell():AddCheckbox("", self.config.pauseCombatWhileMutating ~= false)
	pauseCombatCheckbox.OnChange = function()
		self.config.pauseCombatWhileMutating = pauseCombatCheckbox.Checked
	end
end

---@param parent ExtuiTreeParent
---@param fromEvent boolean?
function MutationProfileExecutionHub:renderTutorialWindow(parent, fromEvent)
	Helpers:KillChildren(parent)

	---@type MazzleDocsContentItem[]
	local docsContent = {}

	if fromEvent and not self.config.viewedTutorial then
		docsContent = {
			{
				type = "CallOut",
				prefix = "Note:",
				color = "Green",
				text =
				[[Do not skip this if you've used Lab pre-1.12 - there's been a major change in underlying behavior that you need to know]]
			} --[[@as MazzleDocsCallOut]],
			{
				type = "Content",
				text = [[
You're seeing this window because you're executing a Mutation Profile on Absolute's Laboratory 1.12.0+ for the first time.
You'll notice that your game is a bit laggy right now - this is due to your active Mutation Profile executing in the background with the settings to the left. This tutorial is a short, one-time, INTENTIONALLY in-your-face walkthrough of those options while the profile runs.
This will be the only the only time you're forced to see a window like this. You can get back to this window by going in Lab's MCM section -> Mutation Tab -> "Launch Profile Execution Hub" button in the top left of the tab]]
			}
		}
	end

	self.config.viewedTutorial = true

	for _, slides in ipairs(self:generateDocs()) do
		for i, content in ipairs(slides.content) do
			if i > 2 then
				table.insert(docsContent, content)
			end
		end
	end

	MazzleDocs.RenderContent(parent, docsContent)

	return true
end

---@return MazzleDocsDocumentation
function MutationProfileExecutionHub:generateDocs()
	return {
		{
			Topic = "End User Docs",
			content = {
				{
					type = "Heading",
					text = "Profile Execution Hub"
				},
				{
					type = "Content",
					text = "Open the hub by clicking on the 'Launch Profile Execution Hub' button in the top-left of the Mutation Tab in MCM"
				},
				{
					type = "SubHeading",
					text = "Too Long; Didn't Read"
				},
				{
					type = "Bullet",
					text = {
						"More permits = more NPCs processed per tick = more lag but probably less overall time",
						"Fewer permits = fewer NPCs processed per tick = less lag but probably longer overall time",
						"Lag manifests as moonwalking NPCs, delayed spell casts, and delayed dialogue selections. Extremely high lag can result in soft locks if you attempt to perform any actions during it.",
						"LAB slowly increases permits (with no limit) by 20% when there is no lag, slowly decreases it to the Minimum when lag is low, and quickly decreases it to the Minimum when lag is high.",
						"Defaults should work fine, but you can tweak the numbers with a goal of finding a 'playable' middle ground - where the latency is low enough for you to not feel stuck/scared of soft-locking, but still allowing enough entities to be processed quickly enough to end the lag entirely",
						"You don't have to save your game after changing the values - just reload and it'll take effect",
						"There really aren't any consequences to an extremely slow profile - entities are processed closest -> farthest from the player, and it's extremely unlikely that there'd be any save corruption if you save while this is running - BG3 is very robust",
						"You won't see any feedback when the profile is done executing except in the logs + SE console"
					}
				} --[[@as MazzleDoctsBullet]],
				{
					type = "SubHeading",
					text = "Too Long; Still Read"
				},
				{
					type = "Content",
					text = [[
Before v1.12, Lab would process all entities together in stages: Selection, Undo, Mutate, Finalize. If there were 500 entities that met the basic criteria (alive, not a party member, etc), then 500 entities would be run sequentially in each stage.
This worked pretty well for the most part as the game is impressively robust, but experience varied pretty significantly between modlists and hardware, and essentially soft-locked the server for the duration of the run (usually for less than a minute, but for some users it would last several minutes). Ultimately, it just wasn't as efficient as it could be.

v1.12 changes this behavior in a big way - instead of processing every entity together and letting Script Extender + the game handle load distribution, each entity is assigned one permit out of a pool, and reserves that permit for the entire flow - from Selection to Finalization.
Permits are only assigned at the start of each tick (a slice of game time that functionality gets executed within - ideally happens every 33 milliseconds (ms) for BG3 server functionality) and are only checked back in once the entity that reserved it is completely done with processing, which often takes several ticks.

This means, given a pool of 20 permits, 20 entities will reserve permits at the start of a tick and go through all the stages of Mutation at their own pace. If 10 of the entities aren't eligible for Selection and don't have any existing mutations, they'll almost immediately (after a lot of Osi calls that determine their eligiblity) return their permits for more entities to be processed the next tick while the other 10 continue through the pipeline.
This makes processing a lot more efficient by not overtaxing the game each tick, reducing tick latency (preventing the server from soft-locking) and even overall increasing the speed each entity is processed. But just hardcoding the pool isn't enough - by using this approach, we can now apply Dynamic Rate-Limiting.]]
				},
				{
					type = "Section",
					text = "Dynamic Rate-Limiting"
				},
				{
					type = "Content",
					text = [[
Essentially, rate-limiting is just limiting the rate at which actions happen - in this case, the 'action' is the processing of an entity from Selection to Finalization. By measuring how much time passed from the start of one tick to the start of the next, we can determine if the game is performing well or suffering too much latency and adjust the permit pool size accordingly.

For example, say we start out with 20 permits again and hand all of them out, and 15 get returned within the same tick due to 15 entities failing the eligibility check. At the start of the new tick, we determine that the last tick took 80ms to complete, 59% longer than the target time of 33ms.
That's too long, so we reduce the maximum permit pool size by that same 59% - the permit pool size is now 11 permits (rounded down), so the new tick can only hand out 11 permits, despite having 15 checked back in the previous tick. This reduces the stress on the game, reducing latency on the server and therefore on the user's experience.

Now say that the 2nd tick takes 33ms - reducing the permit pool helped! But what if we reduced the permit pool too much - what if we could have achieved 33ms by only reducing the pool to 15 permits? We can't predict that, so instead we'll now increase the permit pool by a flat 20% - this increases the pool up to 13 permits, adding two free permits to the pool to be handed out in the third tick regardless of how many are returned by the end of the second tick.

These interactions will continue for the duration of the profile execution - some entities will require more processing, some less, so Lab constantly adjusts the permit pool to keep the processing time per tick as close to the target of 33ms as possible.]]
				},
				{
					type = "Section",
					text = "Controlling Your Experience"
				},
				{
					type = "Content",
					text = [[
This above has proven to work really well, but as mentioned at the start of this document, this is far from an "objective" result - what mods a user is running on what hardware will heavily affect the behavior here, in addition to normal gameplay factors such as the amount of NPCs killed.
Users with weak CPUs may aggressively throttle down to the minimum permit pool size because 33ms per tick just isn't what their machine is capable of - users with stronger CPUs will experience longer execution times than necessary because the the initial permit pool is too small and grows too slowly.

To accommodate these scenarios, you can adjust the various parameters in the Profile Execution Hub to what works for your machine + modlist (though keep in mind experience will change level to level). Keep in mind, the goal should be to find the numbers that make the game _feel_ acceptable/playable while you play, not to get a 0 lag experience, as that just may not be possible for you depending on a variety of factors.

If, and ONLY IF, you're technically minded, you can turn the log level up to TRACE in the General tab in MCM and look for `[RX` logs in `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\Absolutes_Laboratory\log.txt`. If you're not technically minded, then only do this if I ask you to - looking at the logs can do more harm than good if you misinterpret them.]]
				}
			}
		}
	} --[[@as MazzleDocsDocumentation]]
end
