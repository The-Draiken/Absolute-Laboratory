---@class MonsterLabEntityCreationForm
MonsterLabEntityCreationForm = {
    ---@type ExtuiGroup
    inputFormParent = nil,
    ---@type ExtuiTabBar
    resourceBrowserTabs = nil,
    ---@type fun()
    callback = nil,
    ---@type MonsterLabEntity?
    existingEntity = nil,
    ---@type MonsterLabEncounter
    encounter = nil,
    ---@type {[string]: string}
    inputErrors = {},
    ---@type ExtuiGroup
    errorGroup = nil,
    inputCallbacks = {
        ---@type fun(val: string)
        template = nil,
        ---@type fun(val: string)
        stats = nil,
    },
    tempHoldingStorage = {
        ---@type string?
        name = nil,
        ---@type string?
        title = nil,
        ---@type Guid?
        templateId = nil,
        ---@type string?
        stat = nil,
        ---@type string?
        anubisConfigName = nil,
        ---@type Guid?
        characterVisId = nil,
        ---@type string?
        icon = nil
    },

}

---@param parent ExtuiTreeParent
---@param encounter MonsterLabEncounter
---@param completedCallback fun()
---@param existingEntity MonsterLabEntity?
function MonsterLabEntityCreationForm:create(parent, encounter, completedCallback, existingEntity)
    ---@type MonsterLabEntityCreationForm
    local instance = {}
    setmetatable(instance, self)
    self.__index = self

    Helpers:KillChildren(parent)
    instance.inputFormParent = parent:AddGroup("EntityFormParent")
    instance.inputFormParent.ItemReadOnly = encounter.modId ~= nil
    instance.resourceBrowserTabs = parent:AddTabBar("resourceBrowser")
    instance.resourceBrowserTabs.Visible = encounter.modId == nil

    instance.tempHoldingStorage = {}
    instance.inputErrors = {}
    instance.inputCallbacks = {}

    instance.encounter = encounter
    instance.callback = completedCallback
    instance.existingEntity = existingEntity

    if existingEntity then
        instance.tempHoldingStorage.name = existingEntity.displayName
        instance.tempHoldingStorage.title = existingEntity.title
        instance.tempHoldingStorage.templateId = existingEntity.template
        instance.tempHoldingStorage.stat = existingEntity.stat
        instance.tempHoldingStorage.characterVisId = existingEntity.characterVisualResourceID
        instance.tempHoldingStorage.icon = existingEntity.icon
        instance.tempHoldingStorage.anubisConfigName = existingEntity.anubisConfigName
    end

    instance:buildFormInputSection()
    instance:buildTemplateBrowser()
    instance:buildStatBrowser()
end

function MonsterLabEntityCreationForm:renderErrors()
    Helpers:KillChildren(self.errorGroup)

    if next(self.inputErrors) then
        Styler:Color(self.errorGroup:AddText("Validation Errors:"), "ErrorText")

        for _, errorText in TableUtils:OrderedPairs(self.inputErrors, function(key, value)
            return value
        end) do
            self.errorGroup:AddBulletText(errorText)
        end
    end
end

function MonsterLabEntityCreationForm:buildFormInputSection()
    Helpers:KillChildren(self.inputFormParent)

    local inputTable = self.inputFormParent:AddTable("", 3)
    inputTable:AddColumn("", "WidthFixed")
    inputTable:AddColumn("", "WidthFixed")
    inputTable:AddColumn("", "WidthFixed")
    inputTable.NoSavedSettings = true

    local sizingGuid = FormBuilder:generateGUID()

    self.errorGroup = self.inputFormParent:AddGroup("errors")

    local nameInputRow = inputTable:AddRow()
    nameInputRow:AddCell():AddText("Name")
    local nameInput = nameInputRow:AddCell():AddInputText("", self.tempHoldingStorage.name)
    nameInput.SizeHint = { Styler:calculateTextDimensions(sizingGuid) }
    nameInput.Hint = "Required"

    nameInput.OnChange = function()
        self.inputErrors["Name"] = nil
        if #nameInput.Text == 0 then
            self.inputErrors["Name"] = "Name Field Is Required"
        else
            self.tempHoldingStorage.name = nameInput.Text
        end

        self:renderErrors()
    end

    local titleInputRow = inputTable:AddRow()
    titleInputRow:AddCell():AddText("Title")
    local titleInput = titleInputRow:AddCell():AddInputText("", self.tempHoldingStorage.title)
    titleInput.SizeHint = { Styler:calculateTextDimensions(sizingGuid) }
    titleInput.Hint = "Optional"

    titleInput.OnChange = function()
        self.tempHoldingStorage.title = titleInput.Text
    end

    -- anchor so i can call the below rows from the template callback but still have this first
    local templateRow = inputTable:AddRow()

    local statRow = inputTable:AddRow()
    statRow:AddCell():AddText("Stat")
    local statCell = statRow:AddCell()
    local statButtonCell = statRow:AddCell()

    local useTemplateButton = statButtonCell:AddImageButton("ResetStat", "ico_randomize_d", { 28, 28 })
    useTemplateButton.Visible = self.tempHoldingStorage.stat ~= nil
    useTemplateButton:SetStyle("FramePadding", 2, 2)
    useTemplateButton:SetStyle("FrameRounding", 0)
    useTemplateButton:Tooltip():AddText(("\t Use the Character Stat from the currently chosen template (%s)"):format(
        Ext.Template.GetTemplate(self.tempHoldingStorage.templateId) and Ext.Template.GetTemplate(self.tempHoldingStorage.templateId).Stats or "UNKNOWN")
    )
    useTemplateButton.OnClick = function()
        self.inputCallbacks.stats()
    end

    self.inputCallbacks.stats = function(val)
        Helpers:KillChildren(statCell)

        self.tempHoldingStorage.stat = nil
        self.inputErrors["Stat"] = nil

        local tmpl = not val and Ext.Template.GetTemplate(self.tempHoldingStorage.templateId)
        local chosenStat = val or (tmpl and tmpl.Stats)
        if chosenStat then
            ---@type Character?
            local characterStat = Ext.Stats.Get(chosenStat)

            if not characterStat then
                if val then
                    self.inputErrors["Stat"] = ("Character Stat [%s] does not exist - choose a different stat or load the missing mod!"):format(val)
                end
            else
                Styler:HyperlinkText(statCell, characterStat.Name, function(parent)
                    ResourceManager:RenderDisplayWindow(characterStat, parent)
                end)

                if val then
                    self.tempHoldingStorage.stat = val
                end
            end
        end

        useTemplateButton.Visible = self.tempHoldingStorage.stat ~= nil

        self:renderErrors()
    end

    self.inputCallbacks.stats(self.tempHoldingStorage.stat)

    local anubisConfigRow = inputTable:AddRow()
    anubisConfigRow:AddCell():AddText("Anubis Script Name")
    local anubisConfigInput = anubisConfigRow:AddCell():AddInputText("", self.tempHoldingStorage.anubisConfigName)
    anubisConfigInput.SizeHint = { Styler:calculateTextDimensions(sizingGuid) }
    anubisConfigInput.CharsNoBlank = true
    anubisConfigInput.Hint = self.tempHoldingStorage.templateId
        and Ext.Template.GetTemplate(self.tempHoldingStorage.templateId)
        and Ext.Template.GetTemplate(self.tempHoldingStorage.templateId).AnubisConfigName
        or "Optional"

    anubisConfigInput.OnChange = function()
        self.tempHoldingStorage.anubisConfigName = anubisConfigInput.Text
        if #anubisConfigInput.Text == 0 then
            anubisConfigInput.Hint = self.tempHoldingStorage.templateId
                and Ext.Template.GetTemplate(self.tempHoldingStorage.templateId)
                and Ext.Template.GetTemplate(self.tempHoldingStorage.templateId).AnubisConfigName
                or "Optional"
        end
    end

    local charVisRow = inputTable:AddRow()
    charVisRow:AddCell():AddText("Visual Resource")

    local charVisInput = charVisRow:AddCell():AddInputText("", self.tempHoldingStorage.characterVisId)
    charVisInput.CharsNoBlank = true
    charVisInput.SizeHint = { Styler:calculateTextDimensions(sizingGuid) }
    charVisInput.Hint = "Optional"

    charVisInput.OnChange = function()
        self.inputErrors["CharVis"] = nil
        self.tempHoldingStorage.characterVisId = nil

        local charVisValue
        if #charVisInput.Text >= 1 then
            charVisValue = charVisInput.Text
            self.tempHoldingStorage.characterVisId = charVisInput.Text
            charVisInput.Hint = "Optional"
        elseif self.tempHoldingStorage.templateId then
            ---@type CharacterTemplate?
            local tmpl = Ext.Template.GetTemplate(self.tempHoldingStorage.templateId)

            charVisValue = tmpl and tmpl.CharacterVisualResourceID
            charVisInput.Hint = charVisValue or "Optional"
        end

        if charVisValue then
            ---@type ResourceCharacterVisualResource?
            local resource = Ext.Resource.Get(charVisValue, "CharacterVisual")

            if not resource and #charVisInput.Text >= 1 then
                self.tempHoldingStorage.characterVisId = nil
                self.inputErrors["CharVis"] = ("Character Visual Resource [%s] could not be found - overwrite with a valid resource or load the missing mod!"):format(charVisValue)
            end
        end

        self:renderErrors()
    end

    if self.tempHoldingStorage.characterVisId then
        charVisInput:OnChange()
    end

    local iconInputRow = inputTable:AddRow()
    iconInputRow:AddCell():AddText("Icon")

    local iconCell = iconInputRow:AddCell()
    local iconInput = iconCell:AddInputText("", self.tempHoldingStorage.icon)
    iconInput.CharsNoBlank = true
    iconInput.SizeHint = { Styler:calculateTextDimensions(sizingGuid) }
    iconInput.Hint = "Optional"
    iconInput.UserData = "keep"

    iconInput.OnChange = function()
        self.inputErrors["Icon"] = nil
        self.tempHoldingStorage.icon = nil

        local iconValue
        if #iconInput.Text >= 1 then
            iconValue = iconInput.Text
            self.tempHoldingStorage.icon = iconInput.Text
            iconInput.Hint = "Optional"
        elseif self.tempHoldingStorage.templateId then
            ---@type CharacterTemplate?
            local tmpl = Ext.Template.GetTemplate(self.tempHoldingStorage.templateId)

            iconValue = tmpl and tmpl.Icon
            iconInput.Hint = iconValue or "Optional"
        end

        Helpers:KillChildren(iconCell)
        if iconValue then
            local image = iconCell:AddImage(iconValue, { 48, 48 })
            if image.ImageData.Icon == "" then
                image:Destroy()
                iconCell:AddImage("Item_Unknown", { 32, 32 })

                if #iconInput.Text >= 1 then
                    self.inputErrors["Icon"] = ("Icon [%s] could not be found - this is potentially an error, but you'll be allowed to continue in case it's not"):format(iconValue)
                end
            end
        end

        self:renderErrors()
    end

    if self.tempHoldingStorage.icon then
        iconInput:OnChange()
    end

    templateRow:AddCell():AddText("Template")
    local templateCell = templateRow:AddCell()

    self.inputCallbacks.template = function(val)
        Helpers:KillChildren(templateCell)

        self.inputErrors["Template"] = nil
        self.tempHoldingStorage.templateId = nil

        if not val or val == "" then
            self.inputErrors["Template"] = "TemplateId is required!"
        elseif not Ext.Template.GetTemplate(val) then
            self.inputErrors["Template"] = ("Template [%s] does not exist - choose a different template or load the missing mod!"):format(val)
        else
            ---@type CharacterTemplate
            local templateResource = Ext.Template.GetTemplate(val)

            Styler:HyperlinkText(templateCell, templateResource.DisplayName:Get() or templateResource.Name, function(parent)
                ResourceManager:RenderDisplayWindow(templateResource, parent)
            end)

            self.tempHoldingStorage.templateId = val

            if not self.tempHoldingStorage.icon then
                iconInput:OnChange()
            end

            if not self.tempHoldingStorage.stat then
                self.inputCallbacks.stats()
            end

            if not self.tempHoldingStorage.characterVisId then
                charVisInput:OnChange()
            end
        end

        self:renderErrors()
    end

    if self.tempHoldingStorage.templateId then
        self.inputCallbacks.template(self.tempHoldingStorage.templateId)
    end

    if not self.encounter.modId then
        local submitButton = self.inputFormParent:AddButton("Submit")
        submitButton.OnClick = function()
            if not next(self.inputErrors) or (TableUtils:CountElements(self.inputErrors) == 1 and self.inputErrors["Icon"]) then
                local entity
                if not self.existingEntity then
                    self.encounter.entities = self.encounter.entities or {}

                    entity = TableUtils:DeeplyCopyTable(ConfigurationStructure.DynamicClassDefinitions.monsterLab.entity)
                    entity.mlEntityId = FormBuilder:generateGUID()
                    entity.coordinates = TableUtils:DeeplyCopyTable(self.encounter.baseCoords)

                    self.encounter.entities[entity.mlEntityId] = entity
                else
                    entity = self.existingEntity
                end

                entity.displayName = self.tempHoldingStorage.name
                entity.title = self.tempHoldingStorage.title
                entity.icon = self.tempHoldingStorage.icon
                entity.characterVisualResourceID = self.tempHoldingStorage.characterVisId
                entity.template = self.tempHoldingStorage.templateId
                entity.stat = self.tempHoldingStorage.stat
                entity.anubisConfigName = self.tempHoldingStorage.anubisConfigName

                self.callback()
            end
        end
    end
end

function MonsterLabEntityCreationForm:buildTemplateBrowser()
    TemplateSelector:init()
    RaceSelector:initialize()

    local browser = self.resourceBrowserTabs:AddTabItem("Template")

    local helpText = browser:AddText("Click outside of the input box, then hold Alt + hover over an entry to see its popup. Alt-left click to popout the popup")
    helpText.Font = "Tiny"
    helpText:SetColor("Text", Styler:ConvertRGBAToIMGUI({ 1, 1, 1, 0.5 }))


    local filterGroup = browser:AddGroup("filters")

    filterGroup:AddText("From Mod: ")
    local modSources = {}
    local modCombo = filterGroup:AddCombo("")
    modCombo.SameLine = true
    modCombo.WidthFitPreview = true

    filterGroup:AddText("Race: ").SameLine = true
    local raceCombo = filterGroup:AddCombo("")
    local raceOpts = TableUtils:DeeplyCopyTable(RaceSelector.raceOpts)
    table.insert(raceOpts, 1, "All")
    raceCombo.Options = raceOpts
    raceCombo.SelectedIndex = 0
    raceCombo.SameLine = true
    raceCombo.WidthFitPreview = true

    filterGroup:AddText("Subrace: ").SameLine = true
    local subRaceCombo = filterGroup:AddCombo("")
    subRaceCombo.SameLine = true
    subRaceCombo.WidthFitPreview = true
    subRaceCombo.Options = { "All" }
    subRaceCombo.SelectedIndex = 0

    local resultsView = browser:AddChildWindow("results")
    resultsView:SetStyle("WindowMinSize", 200, 500)
    resultsView.NoSavedSettings = true

    local templatesTable = resultsView:AddTable("", 3)

    local searchBox = filterGroup:AddInputText("")
    searchBox.Hint = "Search by Template Name or UUID"
    searchBox.SizeHint = { Styler:calculateTextDimensions(FormBuilder:generateGUID()) }

    local function buildResults()
        Helpers:KillChildren(templatesTable)
        local row = templatesTable:AddRow()

        local counter = 0
        local buildSources = not next(modSources)

        local searchText = Helpers:SanitizeStringForFind(searchBox.Text:upper())

        local chosenRace = raceCombo.SelectedIndex > 0 and RaceSelector.translationMap[raceCombo.Options[raceCombo.SelectedIndex + 1]]
        local chosenSubRace = subRaceCombo.SelectedIndex > 0 and RaceSelector.translationMap[subRaceCombo.Options[subRaceCombo.SelectedIndex + 1]]

        ---@type ExtuiSelectable?
        local lastSelect
        for _, templateId in ipairs(TemplateSelector.templates) do
            ---@type CharacterTemplate
            local characterTemplate = Ext.ClientTemplate.GetTemplate(templateId)
            local source = characterTemplate.FileName:gsub("^.*[\\/]Mods[\\/]", ""):gsub("^.*[\\/]Public[\\/]", ""):match("([^/\\]+)")

            if buildSources then
                if not TableUtils:IndexOf(modSources, source) then
                    table.insert(modSources, source)
                end
            end

            if (modCombo.SelectedIndex <= 0 or source == modCombo.Options[modCombo.SelectedIndex + 1])
                and (not chosenRace
                    or (not chosenSubRace
                        and (characterTemplate.Race == chosenRace
                            or TableUtils:IndexOf(RaceSelector.racesWithSubraces[chosenRace], characterTemplate.Race))
                        or (chosenSubRace and characterTemplate.Race == chosenSubRace)
                    )
                )
                and (searchBox.Text == ""
                    or TemplateSelector.translationMap[templateId]:upper():find(searchText)
                    or templateId:upper():find(searchText))
            then
                counter = counter + 1

                local cell = row:AddCell()
                local icon = cell:AddImage(characterTemplate.Icon, { 32, 32 })
                if icon.ImageData.Icon == "" then
                    icon:Destroy()
                    icon = cell:AddImage("Item_Unknown", { 32, 32 })
                end

                ---@type ExtuiSelectable
                local templateSelect = cell:AddSelectable(characterTemplate.Name == "" and (characterTemplate.DisplayName:Get() or source)
                    or characterTemplate.Name)
                templateSelect.SameLine = true

                local openWindow = Styler:HyperlinkRenderable(templateSelect,
                    templateId,
                    "Alt",
                    true,
                    nil,
                    function(parent)
                        CharacterWindow:BuildWindow(parent, templateId)
                    end)

                templateSelect.OnClick = function()
                    if not openWindow() then
                        if lastSelect and lastSelect.Handle ~= templateSelect.Handle then
                            lastSelect.Selected = false
                        end
                        lastSelect = templateSelect

                        self.inputCallbacks.template(templateId)
                    else
                        templateSelect.Selected = false
                    end
                end
                if self.tempHoldingStorage.templateId and self.tempHoldingStorage.templateId == templateId then
                    templateSelect:OnClick()
                end
            end
        end

        if buildSources then
            table.sort(modSources)
            table.insert(modSources, 1, "All")
            modCombo.Options = modSources
            modCombo.SelectedIndex = 0
        end
    end

    local timer
    searchBox.OnChange = function()
        if timer then
            Ext.Timer.Cancel(timer)
        end
        timer = Ext.Timer.WaitFor(300, buildResults)
    end
    modCombo.OnChange = buildResults
    raceCombo.OnChange = function()
        if raceCombo.SelectedIndex > 0 then
            local subRaces = TableUtils:DeeplyCopyTable(RaceSelector.racesWithSubraces[RaceSelector.translationMap[raceCombo.Options[raceCombo.SelectedIndex + 1]]])

            local opts = {}
            for _, subrace in ipairs(subRaces) do
                table.insert(opts, RaceSelector.translationMap[subrace])
            end

            table.sort(opts)
            table.insert(opts, 1, "All")

            subRaceCombo.Options = opts
        else
            subRaceCombo.Options = { "All" }
        end

        subRaceCombo.SelectedIndex = 0
        buildResults()
    end
    subRaceCombo.OnChange = buildResults

    buildResults()
end

function MonsterLabEntityCreationForm:buildStatBrowser()
    local browser = self.resourceBrowserTabs:AddTabItem("Stats")
    local helpText = browser:AddText("Click outside of the input box, then hold Alt + hover over an entry to see its popup. Alt-left click to popout the popup")
    helpText.Font = "Tiny"
    helpText:SetColor("Text", Styler:ConvertRGBAToIMGUI({ 1, 1, 1, 0.5 }))

    local filterGroup = browser:AddGroup("filters")

    filterGroup:AddText("From Mod: ")

    ---@type string[]
    local modSources = {}
    ---@type {[Guid|string]: (string|Guid)}
    local modTranslationMap = {}

    local modCombo = filterGroup:AddCombo("")
    modCombo.SameLine = true
    modCombo.WidthFitPreview = true

    local resultsView = browser:AddChildWindow("results")
    resultsView:SetStyle("WindowMinSize", 200, 500)
    resultsView.NoSavedSettings = true

    local statsTable = resultsView:AddTable("", 3)

    local searchBox = filterGroup:AddInputText("")
    searchBox.Hint = "Search by Stat Name"
    searchBox.SizeHint = { Styler:calculateTextDimensions(FormBuilder:generateGUID()) }

    local function buildResults()
        Helpers:KillChildren(statsTable)
        local row = statsTable:AddRow()

        local counter = 0
        local buildSources = not next(modSources)

        local searchText = Helpers:SanitizeStringForFind(searchBox.Text:upper())
        local chosenMod = modCombo.SelectedIndex > 0 and modTranslationMap[modCombo.Options[modCombo.SelectedIndex + 1]]

        ---@type ExtuiSelectable?
        local lastSelect
        for _, statId in TableUtils:OrderedPairs(Ext.Stats.GetStats("Character"), function(key, value)
            return Ext.Stats.Get(value).Name
        end)
        do
            ---@type Character
            local characterStat = Ext.Stats.Get(statId)

            if buildSources then
                local modInfo = Ext.Mod.GetMod(characterStat.ModId)
                if not modTranslationMap[characterStat.ModId] and modInfo then
                    modTranslationMap[characterStat.ModId] = modInfo.Info.Name
                    modTranslationMap[modInfo.Info.Name] = characterStat.ModId

                    table.insert(modSources, modTranslationMap[characterStat.ModId])
                end

                modInfo = Ext.Mod.GetMod(characterStat.OriginalModId)
                if not modTranslationMap[characterStat.OriginalModId] and modInfo then
                    modTranslationMap[characterStat.OriginalModId] = modInfo.Info.Name
                    modTranslationMap[modInfo.Info.Name] = characterStat.OriginalModId

                    table.insert(modSources, modTranslationMap[characterStat.OriginalModId])
                end
            end

            if (not chosenMod or (characterStat.ModId == chosenMod or characterStat.OriginalModId == chosenMod))
                and (searchBox.Text == ""
                    or characterStat.Name:upper():find(searchText)
                    or statId:upper():find(searchText))
            then
                counter = counter + 1

                local cell = row:AddCell()

                ---@type ExtuiSelectable
                local statSelect = cell:AddSelectable(characterStat.Name or statId)

                local openWindow = Styler:HyperlinkRenderable(statSelect,
                    statId,
                    "Alt",
                    true,
                    nil,
                    function(parent)
                        ResourceManager:RenderDisplayWindow(characterStat, parent)
                    end)

                statSelect.OnClick = function()
                    if not openWindow() then
                        if lastSelect and lastSelect.Handle ~= statSelect.Handle then
                            lastSelect.Selected = false
                        end
                        lastSelect = statSelect

                        self.inputCallbacks.stats(statId)
                    else
                        statSelect.Selected = false
                    end
                end

                if self.tempHoldingStorage.stat and self.tempHoldingStorage.stat == statId then
                    statSelect:OnClick()
                end
            end
        end

        if buildSources then
            table.sort(modSources)
            table.insert(modSources, 1, "All")
            modCombo.Options = modSources
            modCombo.SelectedIndex = 0
        end
    end

    local timer
    searchBox.OnChange = function()
        if timer then
            Ext.Timer.Cancel(timer)
        end
        timer = Ext.Timer.WaitFor(300, buildResults)
    end
    modCombo.OnChange = buildResults

    buildResults()
end
