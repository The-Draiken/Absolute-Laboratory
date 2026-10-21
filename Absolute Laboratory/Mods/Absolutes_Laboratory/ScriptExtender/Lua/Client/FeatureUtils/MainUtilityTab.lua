MainUtilityTab = {
	---@type ExtuiTabBar
	tabBar = nil
}

---@type (fun(parent: ExtuiTabBar))[]
local tabsToRegister = {}

Mods.BG3MCM.IMGUIAPI:InsertModMenuTab(ModuleUUID, "Utilities",
	--- @param tabHeader ExtuiTreeParent
	function(tabHeader)
		MainUtilityTab.tabBar = tabHeader:AddTabBar("utilities")
		MainUtilityTab.tabBar.TextWrapPos = 0

		for _, func in ipairs(tabsToRegister) do
			func(MainUtilityTab.tabBar)
		end
	end
)

---@param registrationFunc fun(parent: ExtuiTabBar)
function MainUtilityTab:registerTab(registrationFunc)
	if self.tabBar then
		registrationFunc(self.tabBar)
	else
		table.insert(tabsToRegister, registrationFunc)
	end
end

Ext.Require("Client/FeatureUtils/PassiveDupeRemoverUtil.lua")
