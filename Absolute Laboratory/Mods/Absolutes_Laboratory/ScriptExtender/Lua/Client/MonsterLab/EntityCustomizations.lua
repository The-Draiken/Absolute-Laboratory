EntityCustomizations = {
    ---@type ExtuiPopup
    popup = nil,
    ---@type MonsterLab_RulesetRule
    entityRulesetCustomizations = nil,
    ---@type MonsterLabEntity
    mlEntity = nil,
    ---@type CharacterTemplate?
    charTemplate = nil,
}

---@param parent ExtuiTreeParent
---@param mlEntity MonsterLabEntity
---@param entityRulesetCustomizations MonsterLab_RulesetRule
---@param modSourced boolean?
function EntityCustomizations:buildCustomizationsMenu(parent, mlEntity, entityRulesetCustomizations, modSourced)
    Helpers:KillChildren(parent)

    self.entityRulesetCustomizations = entityRulesetCustomizations
    self.mlEntity = mlEntity
    self.charTemplate = Ext.Template.GetTemplate(self.mlEntity.template)
    self.modSourced = modSourced

    self.popup = parent:AddPopup("CustomizationsPopup")

    parent:AddSeparator()

    local tabBar = parent:AddTabBar("tabs")

    self:buildMutatorTab(tabBar:AddTabItem("Mutators"))

    self:buildStatsTab(tabBar:AddTabItem("Character Stat"))

    self:buildTemplateTab(tabBar:AddTabItem("Character Template"))
end

---@param tab ExtuiTreeParent
function EntityCustomizations:buildMutatorTab(tab)
    tab.UserData = "EnableForMods"
    Styler:EnableToggleButton(tab,
        "Composable",
        false,
        [[If enabled, these mutators will be _composable_, meaning they will be combined with any mutators of the same type that are applicable for this entity per the active Mutation Profile. See the documentation for each mutator to see when and how this applies.
	If unchecked, composable mutators of the same type from earlier mutations will be replaced with these - these mutators will always be processed last, so they are guaranteed to overwrite any conflicts from the Mutation Profile]],
        function(swap)
            if swap then
                self.entityRulesetCustomizations.composable = not self.entityRulesetCustomizations.composable
            end
            return self.entityRulesetCustomizations.composable
        end).UserData = "keep"

    self.entityRulesetCustomizations.mutators = self.entityRulesetCustomizations.mutators or {}

    MutationDesigner:RenderMutatorsSidebarStyle(tab, self.entityRulesetCustomizations.mutators, nil, nil, self.popup, self.modSourced)
end

---@param tab ExtuiTreeParent
function EntityCustomizations:buildStatsTab(tab)
    tab.UserData = "EnableForMods"

    self.entityRulesetCustomizations.stats = self.entityRulesetCustomizations.stats
        or TableUtils:DeeplyCopyTable(ConfigurationStructure.DynamicClassDefinitions.monsterLab.rulesetModifiers.stats)

    local statsConfig = self.entityRulesetCustomizations.stats

    ---@type Character?
    local existingStat
    if self.mlEntity.stat then
        existingStat = Ext.Stats.Get(self.mlEntity.stat)
    elseif self.charTemplate then
        existingStat = Ext.Stats.Get(self.charTemplate.Stats)
    end

    if not existingStat then
        Styler:Color(tab:AddText(([[
The Character Stat [%s] could not be loaded - you're probably missing a mod.
Overwrite the stat with a valid one in the edit entity form (right-click the entity name in the left sidebar), or load the missing mod.]]):format(self.mlEntity.stat or
                self.charTemplate.Stats)),
            "ErrorText")
    else
        tab:AddText("Stat: ")
        Styler:HyperlinkText(tab, existingStat.Name, function(parent)
            ResourceManager:RenderDisplayWindow(existingStat, parent)
        end).SameLine = true
    end

    local tbl = tab:AddTable("", 2)
    tbl.SizingFixedSame = true

    --#region Vitality
    local healthRow = tbl:AddRow()
    healthRow:AddCell():AddText("Vitality (?)"):Tooltip():AddText("\t Base Health of the entity, pre-calculation/modifiers")

    local healthInput = healthRow:AddCell():AddInputInt("", statsConfig.vitality or -1)
    healthInput:Tooltip():AddText(("\t Set to -1 to use base value. Base Value from [%s]: %s"):format(existingStat and existingStat.Name or "Invalid Stat",
        existingStat and existingStat.Vitality or "N/A"))
    healthInput.OnDeactivate = function()
        if healthInput.Value[1] == 0 or healthInput.Value[1] < -1 then
            healthInput.Value = { statsConfig.vitality, statsConfig.vitality, statsConfig.vitality, statsConfig.vitality }
        end

        statsConfig.vitality = healthInput.Value[1]
    end
    --#endregion Vitality

    --#region Ability Scores
    for i = 1, 6 do
        local abilityIdLabel = tostring(Ext.Enums.AbilityId[i])
        local abilityRow = tbl:AddRow()

        abilityRow:AddCell():AddText(abilityIdLabel)
        local input = abilityRow:AddCell():AddInputInt("", statsConfig.abilityScores[abilityIdLabel] or -1)
        input:Tooltip():AddText(("\t Set to -1 to use base value. Base Value from [%s]: %s"):format(existingStat and existingStat.Name or "Invalid Stat",
            existingStat and existingStat[abilityIdLabel] or "N/A"))

        input.OnDeactivate = function()
            if input.Value[1] == 0 or input.Value[1] < -1 then
                local val = statsConfig.abilityScores[abilityIdLabel] or -1
                input.Value = { val, val, val, val }
            end

            if input.Value[1] == -1 then
                statsConfig.abilityScores[abilityIdLabel] = nil
            else
                statsConfig.abilityScores[abilityIdLabel] = input.Value[1]
            end
        end
    end
    --#endregion Ability Scores
end

---@param tab ExtuiTreeParent
function EntityCustomizations:buildTemplateTab(tab)
    tab.UserData = "EnableForMods"

    if self.charTemplate then
        tab:AddText("Template: ")
        Styler:HyperlinkText(tab, self.charTemplate.DisplayName:Get() or self.charTemplate.Name, function(parent)
            ResourceManager:RenderDisplayWindow(self.charTemplate, parent)
        end).SameLine = true
    else
        Styler:Color(
            tab:AddText(("Character template [%s] could not be loaded - you're probably missing a mod. This form will be broken until you either change it or load the missing mod.")
                :format(self.mlEntity.template)),
            "ErrorText")
    end

    self.entityRulesetCustomizations.template = self.entityRulesetCustomizations.template
        or TableUtils:DeeplyCopyTable(ConfigurationStructure.DynamicClassDefinitions.monsterLab.rulesetModifiers.template)

    local templateConfig = self.entityRulesetCustomizations.template

    local tbl = tab:AddTable("", 2)
    tbl.SizingFixedSame = true

    ---@param label string
    ---@param configKey string
    ---@param componentKey string
    ---@param typeHint string?
    local function renderStringInput(label, configKey, templateComponent, componentKey, typeHint)
        local row = tbl:AddRow()
        row:AddCell():AddText(label)
        local input = row:AddCell():AddInputText("", templateConfig[configKey])
        input.SizeHint = { Styler:calculateTextDimensions("RangerCompanion_ExceptionalTraining") }
        input.CharsNoBlank = true
        if typeHint then
            input:Tooltip():AddText("\t " .. typeHint)
        end
        input.Hint = templateComponent[componentKey]

        input.OnDeactivate = function()
            templateConfig[configKey] = input.Text ~= "" and input.Text or nil
        end
    end

    renderStringInput("AI Archetype", "archetype", self.charTemplate.CombatComponent, "Archetype", "type:ai on bg3.norbyte.dev")
    renderStringInput("Equipment", "equipment", self.charTemplate, "Equipment", "type:equipment on bg3.norbyte.dev")

    --#region LevelOverride
    local levelRow = tbl:AddRow()
    levelRow:AddCell():AddText("Level Override")
    local levelInput = levelRow:AddCell():AddInputInt("", templateConfig.level or -1)
    levelInput:Tooltip():AddText("\t Set to -1 to use the template's default value")
    levelInput.ItemWidth = 80

    levelInput.OnDeactivate = function()
        if levelInput.Value[1] == 0 or levelInput.Value[1] < -1 then
            levelInput.Value = { templateConfig.level, templateConfig.level, templateConfig.level, templateConfig.level }
        elseif levelInput.Value[1] == -1 then
            templateConfig.level = nil
        else
            templateConfig.level = levelInput.Value[1]
        end
    end
    --#endregion

    renderStringInput("Spell Set", "spellSet", self.charTemplate, "SpellSet", "'type:charactertemplate spellSet' on bg3.norbyte.dev (add '& -Common*' to filter out the common ones)")

    --#region Skill List
    local skillListRow = tbl:AddRow()
    skillListRow:AddCell():AddText("Clear Skill List?")
    local skillBox = skillListRow:AddCell():AddCheckbox("", templateConfig.skillList.clearBase or false)
    skillBox.OnChange = function()
        templateConfig.skillList.clearBase = skillBox.Checked
    end
    --#endregion

    --#region Statuses
    local statusesRow = tbl:AddRow()
    statusesRow:AddCell():AddText("Clear Status List?")
    local statusesBox = statusesRow:AddCell():AddCheckbox("", templateConfig.statuses.clearBase or false)
    statusesBox.OnChange = function()
        templateConfig.statuses.clearBase = statusesBox.Checked
    end
    --#endregion

    --#region Treasures
    local treasuresRow = tbl:AddRow()
    treasuresRow:AddCell():AddText("Clear Treasures?")
    local treasuresBox = treasuresRow:AddCell():AddCheckbox("", templateConfig.treasures.clearBase or false)
    treasuresBox.OnChange = function()
        templateConfig.treasures.clearBase = treasuresBox.Checked
    end
    --#endregion

    --#region Trade Treasures
    local tradeTreasuresRow = tbl:AddRow()
    tradeTreasuresRow:AddCell():AddText("Clear Trade Treasures?")
    local tradeTreasuresBox = tradeTreasuresRow:AddCell():AddCheckbox("", templateConfig.tradeTreasures.clearBase or false)
    tradeTreasuresBox.OnChange = function()
        templateConfig.tradeTreasures.clearBase = tradeTreasuresBox.Checked
    end
    --#endregion
end
