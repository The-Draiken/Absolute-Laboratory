Debugger = {
    logger = Logger:new("DebuggerArchive.txt", "Debugger"),
    ---@type ExtuiWindow
    window = nil,
    ---@type ExtuiTabBar
    tabs = nil
}

---@class Debug_BoostEntry
---@field type BoostType
---@field cause BoostSource

---@class Debug_Boost
---@field type BoostType
---@field boosts Debug_BoostEntry[]

---@class Debug_Status
---@field statusId string
---@field type StatusType
---@field handle string
---@field boosts Debug_BoostEntry[]

---@class Debug_Passive
---@field passiveId string
---@field type StatusType
---@field boosts Debug_BoostEntry[]

---@class Debug_EntitySummary
---@field health number
---@field boosts Debug_Boost[]
---@field statuses Debug_Status[]
---@field passives Debug_Passive[]

---@class Debug_EntityRecord
---@field summary Debug_EntitySummary
---@field changedComponents string[]

---@class DebugReport
---@field timestamp string
---@field entityRecordsByFrame Debug_EntityRecord[]

---@param entityId Guid?
function Debugger:launch(entityId)
    if not self.window then
        self.window = Ext.IMGUI.NewWindow("Absolute's Debugger")
        self.window.Scaling = "Scaled"
        self.window:SetStyle("WindowMinSize", 300, 400)
        self.window.Closeable = true
        self.window.Font = MCM.Get("font_size", "755a8a72-407f-4f0d-9a33-274ac0f0b53d")
    else
        self.window.Open = true
        self.window:SetFocus()
    end

    Helpers:KillChildren(self.window)

    self:buildProfileActionButtons(self.window:AddGroup("profile actions"))

    self.tabs = self.window:AddTabBar("debugger_tabs")

    local entityTab = self.tabs:AddTabItem("Entity Change Tracker")
    ---@param tab ExtuiTabItem
    entityTab.OnActivate = function(tab)
        if Ext.Debug.IsDeveloperMode() then
            self:buildChangeTable(tab, entityId)
        else
            Helpers:KillChildren(tab)
            Styler:ScaledFont(tab:AddText("This functionality requires Developer mode to be enabled - enable it in the SE Settings (or through BG3MM)"), "Large")
        end
    end

    -- local functorTab = self.tabs:AddTabItem("Functor Execution Tracer")

    -- ---@param tab ExtuiTabItem
    -- functorTab.OnActivate = function(tab)

    -- end

    entityTab:Activate()
end

---@param parent ExtuiTreeParent
function Debugger:buildProfileActionButtons(parent)
    Styler:MiddleAlignedColumnLayout(parent, function(ele)
        local activeProfileId = Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile

        ele:AddText("Active Profile: ")
        local profileCombo = ele:AddCombo("")
        profileCombo.SameLine = true
        profileCombo.WidthFitPreview = true

        local sIndex = -1
        local opt = {}
        if activeProfileId then
            table.insert(opt, "Disabled")
        end

        for profileId, profile in TableUtils:OrderedPairs(MutationConfigurationProxy.profiles, function(_, value)
            return value.name
        end) do
            table.insert(opt, profile.name .. (profile.modId and "(M)" or ""))
            if activeProfileId == profileId then
                sIndex = #opt
            end
        end

        profileCombo.Options = opt
        profileCombo.SelectedIndex = sIndex - 1
        profileCombo.OnChange = function()
            local selectedName = profileCombo.Options[profileCombo.SelectedIndex + 1]

            if selectedName == "Disabled" then
                activeProfileId = nil
                Ext.Vars.GetModVariables(ModuleUUID).HasDisabledProfiles = true
                Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = nil
            else
                local isModProfile = selectedName:sub(#selectedName - 2) == "(M)"

                activeProfileId = TableUtils:IndexOf(MutationConfigurationProxy.profiles, function(value)
                    if isModProfile then
                        if value.modId then
                            return value.name == selectedName:sub(1, #selectedName - 3)
                        else
                            return false
                        end
                    elseif not value.modId then
                        return value.name == selectedName
                    end
                    return false
                end)

                Ext.Vars.GetModVariables(ModuleUUID).HasDisabledProfiles = false
                Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = activeProfileId
            end
        end

        -- local buttonTable = ele:AddGroup("buttons")

        -- local unloadProfile = buttonTable:AddButton("Unload Active Profile")

        -- local loadProfile = buttonTable:AddButton("Load Profile")
        -- loadProfile.SameLine = true

        -- local saveGame = buttonTable:AddButton("Save Game")
        -- saveGame.SameLine = true
    end)
end

---@param tab ExtuiTabItem
---@param entityId Guid?
function Debugger:buildChangeTable(tab, entityId)
    Helpers:KillChildren(tab)

    local chosenEntity

    local chooseEntityGroup = tab:AddGroup("Choose Entity")

    local chosenEntityDisplay = tab:AddGroup("Chosen Entity")

    local buttonTable = tab:AddGroup("buttons")

    local entityTraceResults = tab:AddGroup("Entity Tracing")

    local unloadProfile = buttonTable:AddButton("Unload Active Profile & Trace Entity")
    unloadProfile.Disabled = chosenEntity ~= nil
    unloadProfile.OnClick = function()
        self:runTracing(entityTraceResults, chosenEntity.entityId, nil, "Unload")
    end

    local loadProfile = buttonTable:AddButton("Load Profile & Trace Entity")
    loadProfile.Disabled = chosenEntity ~= nil
    loadProfile.SameLine = true
    loadProfile.OnClick = function()
        self:runTracing(entityTraceResults, chosenEntity.entityId, nil, "Load")
    end

    local generalTrace = buttonTable:AddButton("General Trace - 10k Frames")
    generalTrace.SameLine = true
    generalTrace.OnClick = function()
        self:runTracing(entityTraceResults, chosenEntity and chosenEntity.entityId, nil, "General Trace")
    end

    local saveTracker = buttonTable:AddButton("Save Result To File")
    saveTracker.SameLine = true

    local loadTracker = buttonTable:AddButton("Load Result From File")
    loadTracker.SameLine = true

    ---@type Debugger_EntityRecord[]
    local entities = {}

    chooseEntityGroup:AddText("Entity To Trace: ")
    local chooseEntityCombo = chooseEntityGroup:AddCombo("")
    chooseEntityCombo.SameLine = true
    chooseEntityCombo.WidthFitPreview = true
    chooseEntityCombo.OnChange = function()
        Helpers:KillChildren(chosenEntityDisplay)
        if chooseEntityCombo.SelectedIndex > 0 then
            local entityEntry = chooseEntityCombo.Options[chooseEntityCombo.SelectedIndex + 1]
            local selectedEntityId = entityEntry:sub(#entityEntry - 36, #entityEntry - 1)

            chosenEntity = entities[TableUtils:IndexOf(entities, function(value)
                return value.entityId == selectedEntityId
            end)]

            unloadProfile.Disabled = false
            loadProfile.Disabled = false

            local icon = chosenEntityDisplay:AddImage(chosenEntity.icon, { 82, 82 })
            if icon.ImageData.Icon == "" then
                icon:Destroy()
                icon = chosenEntityDisplay:AddImage("Item_Unknown", { 82, 82 })
            end
            local displayGroup = chosenEntityDisplay:AddGroup("displ")
            displayGroup.SameLine = true
            Styler:SelectableText(displayGroup, chosenEntity.name, "Name: " .. chosenEntity.name)
            Styler:SelectableText(displayGroup, chosenEntity.entityId, "ID: " .. chosenEntity.entityId)
            Styler:SelectableText(displayGroup, "dead", "Dead: " .. tostring(chosenEntity.isDead))
        else
            unloadProfile.Disabled = true
            loadProfile.Disabled = true

            chosenEntityDisplay:AddImage("Item_Unknown", { 64, 64 })
        end
    end

    Channels.Debugger_GetEntitiesOnServer:RequestToServer(nil,
        ---@param data Debugger_EntityRecord[]
        function(data)
            entities = data

            local opts = {}

            local sIndex = 1
            for _, entity in TableUtils:OrderedPairs(entities, function(key, value)
                return value.name
            end) do
                table.insert(opts, ("%s (%s)"):format(entity.name, entity.entityId))
                if entityId and entityId == entity.entityId then
                    sIndex = #opts
                end
            end

            chooseEntityCombo.Options = opts
            chooseEntityCombo.SelectedIndex = sIndex - 1

            chooseEntityCombo:OnChange()
        end)
end

---@param parent ExtuiTreeParent
---@param entityId Guid
---@param existingArchive DebugReport?
---@param action "Load"|"Unload"|"General Trace"?
function Debugger:runTracing(parent, entityId, existingArchive, action)
    Helpers:KillChildren(parent)

    local tracingStatus = parent:AddText("")
    tracingStatus.Font = "Big"

    local traceTable = parent:AddTable("tracing", 3)
    traceTable:AddColumn("frame", "WidthFixed")
    traceTable.Borders = true
    -- traceTable.Resizable = true

    local headers = traceTable:AddRow()
    headers.Headers = true
    headers:AddCell():AddText("#")
    headers:AddCell():AddText("ECS Changes")
    headers:AddCell():AddText("Detailed Changes")

    ---@type Debug_EntityRecord[]
    local archive = {}

    if action then
        Channels.Debugger_ProfileAction_TraceEntity:SendToServer({
            action = action,
            entityId = entityId
        } --[[@as ProfileActionRequest]])

        tracingStatus.Label = "TRACING: " .. action

        Channels.Debugger_ProfileAction_TraceEntity:SetHandler(
        ---@param data Debug_EntityRecord[]
            function(data, _)
                if not data then
                    Channels.Debugger_ProfileAction_TraceEntity:SetHandler(function(_, _)
                        -- NOOP
                    end)

                    tracingStatus.Label = "Trace Complete: " .. action

                    FileUtils:SaveTableToFile("Debugger_Results.json", archive)
                else
                    for frame, entry in TableUtils:OrderedPairs(data, function(key, _)
                        return tonumber(key)
                    end) do
                        archive[frame] = entry

                        traceTable.ColumnDefs[1].Width = Styler:calculateTextDimensions(tostring(frame), 0)

                        local row = traceTable:AddRow()

                        row:AddCell():AddText(tostring(frame))

                        local ecsCell = row:AddCell()
                        if entry.changedComponents then
                            for _, message in ipairs(entry.changedComponents) do
                                ecsCell:AddText(message)
                            end
                        end
                    end
                end
            end)
    end
end

Channels.Debugger_ProfileAction_TraceEntity:SetHandler(function(data, user)
    -- NOOP
end)

function Debugger:buildExecutorTracerTab(parent)
    Helpers:KillChildren(parent)

    
end
