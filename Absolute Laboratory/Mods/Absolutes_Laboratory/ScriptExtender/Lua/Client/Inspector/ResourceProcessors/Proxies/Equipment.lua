EquipmentProxy = ResourceProxy:new()

ResourceProxy:RegisterResourceProxy("Equipment", EquipmentProxy)

function EquipmentProxy:RenderDisplayableValue(parent, equipmentName)
	if equipmentName then
		local equipment = Ext.Stats.EquipmentSet.Get(equipmentName)
		if equipment then
			local tbl = Styler:TwoColumnTable(parent, "EquipmentSet")

			for key, value in TableUtils:OrderedPairs(equipment) do
				local row = tbl:AddRow()
				row:AddCell():AddText(key)

				local valueCell = row:AddCell()
				if key == "EquipmentGroups" then
					value = Ext.Types.Serialize(value)
					---@cast value StatsEquipmentGroup[]

					for _, group in ipairs(value) do
						if group.Name and group.Name ~= "" then
							valueCell:AddText("Name:")
							Styler:SelectableText(valueCell, group.Name, group.Name).SameLine = true
						end

						for _, item in TableUtils:OrderedPairs(group.Equipment, function(key, value)
							return value
						end) do
							Styler:HyperlinkText(valueCell, item, function (parent)
								ResourceManager:RenderDisplayWindow(Ext.Stats.Get(item), parent)
							end)
						end
					end
				else
					Styler:SelectableText(valueCell, key, value)
				end
			end
		end
	end
end
