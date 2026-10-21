Debugger = {}

---@class Debugger_EntityRecord
---@field entityId Guid
---@field icon string
---@field name string
---@field isDead boolean


Channels.Debugger_GetEntitiesOnServer:SetRequestHandler(function(data, user)
    ---@type Debugger_EntityRecord[]
    local entities = {}

    ---@type EntityHandle
    local hostChar = Ext.Entity.Get(Osi.GetHostCharacter())
    local currentLevel = hostChar.ServerCharacter.Level

    for _, entity in pairs(Ext.Entity.GetAllEntitiesWithComponent("ServerCharacter")) do
        if entity.ServerCharacter.Level == currentLevel then
            table.insert(entities, {
                entityId = entity.Uuid.EntityUuid,
                name = EntityRecorder:GetEntityName(entity),
                icon = entity.Icon and entity.Icon.Icon or "Item_Unknown",
                isDead = entity.Health.Hp <= 0
            } --[[@as Debugger_EntityRecord]])
        end
    end

    return entities
end)

local changePrinter = ChangePrinter:New()

---@type ECSPrinter_Listener
local changeTrackerListener = TableUtils:DeeplyCopyTable(ChangePrinter.listener)
changePrinter.listener = changeTrackerListener

local traceTimer
local traceLock

local userThatInitiated

---@type Debug_EntityRecord[]
local traceResults = {}

function changeTrackerListener:message(message, frame, updateEntitySummary)
    traceResults[frame] = traceResults[frame] or {}
    traceResults[frame].changedComponents = traceResults[frame].changedComponents or {}
    table.insert(traceResults[frame].changedComponents, message)
end

local lastTickSent = 0
function changeTrackerListener:onTick(entity, frame)
    if frame % 10 == 0 or (frame - lastTickSent) >= 10 then
        Channels.Debugger_ProfileAction_TraceEntity:SendToClient(traceResults, userThatInitiated)
        traceResults = {}
        lastTickSent = frame
    end
end

function changeTrackerListener:onStop()
    Channels.Debugger_ProfileAction_TraceEntity:SendToClient(traceResults, userThatInitiated)
    Channels.Debugger_ProfileAction_TraceEntity:SendToClient(nil, userThatInitiated)
    traceResults = {}
    traceLock = false
end

---@class ProfileActionRequest
---@field action "Load"|"Unload"|"General Trace"
---@field entityId Guid

Channels.Debugger_ProfileAction_TraceEntity:SetHandler(
---@param data ProfileActionRequest
    function(data, user)
        if not traceLock then
            traceLock = true
            traceResults = {}

            userThatInitiated = user

            if data.action ~= "General Trace" then
                local profileId
                local disabled
                if data.action == "Unload" then
                    profileId = Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile
                    Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = nil

                    disabled = Ext.Vars.GetModVariables(ModuleUUID).HasDisabledProfiles
                    Ext.Vars.GetModVariables(ModuleUUID).HasDisabledProfiles = true
                end

                changePrinter:Start(nil, data.entityId)

                MutationProfileExecutor:ExecuteProfile(true, function()
                    if profileId then
                        Ext.Vars.GetModVariables(ModuleUUID).ActiveMutationProfile = profileId
                        Ext.Vars.GetModVariables(ModuleUUID).HasDisabledProfiles = disabled
                    end

                    Ext.Timer.WaitFor(5000, function()
                        traceLock = false
                        changePrinter:Stop()
                    end)
                end, data.entityId)
            else
                changePrinter:Start(10000, data.entityId)
            end
        end
    end)

local functorExecutionSub

---@class Debugger_TraceFunctorExecutionRequest
---@field action 'Start'|'Stop'
---@field filter table

Channels.Debugger_TraceFunctorExecution:SetHandler(
---@param data Debugger_TraceFunctorExecutionRequest
    function(data, user)

    end)
