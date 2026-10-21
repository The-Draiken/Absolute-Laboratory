-- Revives the "here's a box telling you Mutations are running" behavior from pre-1.12 (previously
-- Client/Mutations/ProfileExecutionStatus.lua, driven by Channels.ProfileExecutionStatus + the MCM
-- "profile_execution_view" setting), which got dropped when the Profile Execution Hub replaced it.
-- Driven by Channels.MutationExecutionStatus (see Server/Mutations/MutationProfileExecutor.lua) and the
-- "Status Window" setting in the Profile Execution Hub (ConfigurationStructure.config.mutations.settings.profileExecution.statusView).

---@class MutationExecutionStatusWindow
MutationExecutionStatusWindow = {
	---@type ExtuiWindow?
	window = nil,
	config = ConfigurationStructure.config.mutations.settings.profileExecution,
}

---@class MutationExecutionStatusPayload
---@field action "Apply"|"Undo"
---@field stage "Starting"|"Running"|"Complete"|"Error"
---@field profile string?
---@field processed number
---@field total number
---@field timeElapsed number

Channels.MutationExecutionStatus:SetHandler(
---@param data MutationExecutionStatusPayload
	function(data, _)
		MutationExecutionStatusWindow:Render(data)
	end)

---@param data MutationExecutionStatusPayload
function MutationExecutionStatusWindow:Render(data)
	if self.config.statusView == "Off" then
		if self.window then
			self.window:Destroy()
			self.window = nil
		end
		return
	end

	if not self.window then
		self.window = Ext.IMGUI.NewWindow("MutationExecutionStatusWindow")
		self.window.NoSavedSettings = true
		self.window.NoTitleBar = true
		self.window.NoMove = true
		self.window.Closeable = false
		self.window.NoResize = true
		self.window.Scaling = "Scaled"
		self.window.NoNav = true
		self.window.AlwaysAutoResize = true
		self.window:SetColor("WindowBg", { 0, 0, 0, 0.7 })
		self.window:SetColor("Text", { 1, 1, 1, 1 })

		local window = self.window
		Ext.OnNextTick(function()
			if window and window == self.window then
				window:SetPos(Styler:ScaleFactor({ 20, -20 }), "Always")
			end
		end)
	end

	Helpers:KillChildren(self.window)

	local title = ("Absolute's Laboratory: %s Mutations"):format(data.action == "Undo" and "Undoing" or "Applying")
	Styler:CheapTextAlign(title, self.window, "Big")

	if data.stage ~= "Complete" and data.stage ~= "Error" then
		Styler:CheapTextAlign("Do not attempt to perform any actions", self.window)
		Styler:CheapTextAlign("while this is running - you may softlock your game", self.window)

		if self.config.statusView == "Detailed" then
			if data.profile then
				Styler:CheapTextAlign("Profile: " .. data.profile, self.window)
			end

			Styler:CheapTextAlign(
				("%s: %d (considered so far: %d) | Time Elapsed: %dms"):format(
					data.action == "Undo" and "Entities Undone" or "Entities Mutated",
					data.processed or 0,
					data.total or 0,
					data.timeElapsed or 0),
				self.window)

			Styler:CheapTextAlign(
				self.config.executionMode == "Instant"
				and "Execution Method: Instant - this should finish quickly, but may hitch the game while it does"
				or "Execution Method: Tick-Based - this can take a while on a large level, but shouldn't hitch the game",
				self.window,
				"Tiny")
		end

		if MCM and MCM.Get and MCM.Get("log_level") and MCM.Get("log_level") >= Logger.PrintTypes.DEBUG then
			Styler:Color(Styler:CheapTextAlign("Debug Logs Are Currently Enabled - This Will Slow Things Down!", self.window), "ErrorText")
		end
	else
		Styler:CheapTextAlign(data.stage == "Complete" and "Completed!" or "An Error Occurred - See log.txt and report on Nexus", self.window)

		self.window.AlwaysAutoResize = false

		local window = self.window
		Ext.Timer.WaitFor(2000, function()
			if window and window == self.window then
				window:Destroy()
				self.window = nil
			end
		end)
	end
end
