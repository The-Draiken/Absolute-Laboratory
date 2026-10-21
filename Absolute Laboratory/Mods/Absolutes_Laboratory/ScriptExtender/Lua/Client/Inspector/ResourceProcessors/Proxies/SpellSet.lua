SpellSetProxy = ResourceProxy:new()

ResourceProxy:RegisterResourceProxy("SpellSet", SpellSetProxy)

function SpellSetProxy:RenderDisplayableValue(parent, spellSetName)
	if spellSetName then
		---@type StatsSpellSet
		local spellSet = Ext.Stats.SpellSet.Get(spellSetName)

		if spellSet then
			Styler:SimpleRecursiveTwoColumnTable(parent, spellSet, spellSet.Name)
		end
	end
end
