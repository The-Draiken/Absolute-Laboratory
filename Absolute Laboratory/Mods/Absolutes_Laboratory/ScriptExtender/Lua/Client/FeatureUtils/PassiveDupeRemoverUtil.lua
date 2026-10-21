PassiveDupeRemoverUtility = {
    ---@type ExtuiTabItem
    tabParent = nil,
    config = ConfigurationStructure.config.utilities.passiveDupeRemover,
    ---@type ExtuiPopup
    popup = nil
}

MainUtilityTab:registerTab(function(parent)
    PassiveDupeRemoverUtility.tabParent = parent:AddTabItem("Passive Duplicate Remover")

    PassiveDupeRemoverUtility:render()

    PassiveDupeRemoverUtility.tabParent.OnActivate = function()
        PassiveDupeRemoverUtility:render()
    end
end)

function PassiveDupeRemoverUtility:render()
    Helpers:KillChildren(self.tabParent)
    self.popup = Styler:Popup(self.tabParent)

    Styler:ScaledFont(
        self.tabParent:AddText([[
Detects changes to the passiveContainer of all entities that have had their passives mutated by Lab, checking for duplicates of passives as dictated by the below settings, and removing them if possible.
If whitelist mode is enabled, all duplicate passives except those in the whitelist column will be removed.
If blacklist mode is enabled, then only duplicate passives in the blacklist column will be removed.

This utility exists because for some users, for unknown reasons, certain passives may duplicate themselves on NPCs over time, i.e. Tough. It isn't directly caused by Lab, but since Lab is the reason those NPCs
have those passives, it was decided to bake this utility into Lab. This is different from the Passive Boost Deduplicator mod, which has more generic functionality for wider use-cases
    ]]),
        "Default")

    Styler:EnableToggleButton(self.tabParent, "Enabled", false, "Whether this utility should run", function(swap)
        if swap then
            self.config.enabled = not self.config.enabled
        end

        return self.config.enabled
    end)

    Styler:DualToggleButton(self.tabParent, "Whitelist Mode", "Blacklist Mode", false, function(swap)
        if swap then
            self.config.whitelistMode = not self.config.whitelistMode
        end

        return self.config.whitelistMode
    end)

    local listTable = self.tabParent:AddTable("whitelistBlacklist", 2)

    local headers = listTable:AddRow()
    headers.Headers = true
    headers:AddCell():AddText("Whitelist")
    headers:AddCell():AddText("Blacklist")

    local columns = listTable:AddRow()

    ---@param config string[]
    local function buildColumn(config)
        local col = columns:AddCell()

        local input = col:AddButton("Add Passives")
        local passiveList = col:AddChildWindow("whitelist")

        local function renderList()
            Helpers:KillChildren(passiveList)

            for index, passive in TableUtils:OrderedPairs(config) do
                local deleteButton = Styler:ImageButton(passiveList:AddImageButton("delete" .. passive, "ico_red_x", Styler:ScaleFactor({ 16, 16 })))
                deleteButton.OnClick = function()
                    config[index] = nil
                    TableUtils:ReindexNumericTable(config)
                    renderList()
                end
                local dummyGroup = passiveList:AddGroup(passive)
                dummyGroup.SameLine = true
                PassivesProxy:RenderDisplayableValue(dummyGroup, passive)
            end
        end

        renderList()

        input.OnClick = function()
            Helpers:KillChildren(self.popup)
            self.popup:Open()

            StatBrowser:Render("PassiveData", self.popup, function(parent, results)
                    Styler:MiddleAlignedColumnLayout(parent, function(ele)
                        ele:AddButton("Add All").OnClick = function()
                            for _, passiveId in TableUtils:OrderedPairs(results, nil, function(key, value)
                                return TableUtils:IndexOf(config, value) == nil
                            end) do
                                table.insert(config, passiveId)
                            end
                            renderList()
                        end
                    end)
                end,
                function(pos)
                    return pos % (math.floor(self.popup.LastSize[1] / (58 * Styler:ScaleFactor()))) ~= 0
                end,
                function(passiveName)
                    return TableUtils:IndexOf(config, passiveName) ~= nil
                end,
                nil,
                function(_, passiveId)
                    local index = TableUtils:IndexOf(config, passiveId)
                    if index then
                        config[index] = nil
                        TableUtils:ReindexNumericTable(config)
                    else
                        table.insert(config, passiveId)
                    end
                    renderList()
                end
            )
        end
    end

    buildColumn(self.config.whitelist)
    buildColumn(self.config.blacklist)
end
