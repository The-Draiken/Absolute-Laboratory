---@class ModEventsManager
ModEventsManager = {}

local name = "Absolutes_Laboratory"

local ABSOLUTES_LABORATORY_MONSTER_LAB_ENTITY_VAR = "AbsolutesLaboratory_MonsterLab_Entity"

if Ext.IsServer() then
    ---@param state "Started"|"Completed"|"Errored"
    function ModEventsManager:MutationProfileExecuted(state)
        Ext.Timer.WaitFor(200, function()
            Ext.ModEvents[name]["MutationProfileExecuted"]:Throw({
                ["userVarKey"] = ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME,
                ["state"] = state
            })
        end)
    end

    ---@param state "Started"|"Completed"|"Errored"
    function ModEventsManager:MonsterLabProfileExecuted(state)
        Ext.Timer.WaitFor(200, function()
            Ext.ModEvents[name]["MonsterLabProfileExecuted"]:Throw({
                ["userVarKey"] = ABSOLUTES_LABORATORY_MONSTER_LAB_ENTITY_VAR,
                ["state"] = state
            })
        end)
    end
end

---@param existingSlides MazzleDocsSlide[]?
---@return MazzleDocsSlide[]?
function ModEventsManager:generateDocs(existingSlides)
    existingSlides = existingSlides or {}

    table.insert(existingSlides, {
        Topic = "Utilities for Other Authors",
        content = {
            {
                type = "Heading",
                text = "Mod Events"
            },
            {
                type = "Section",
                text = "Other mods can listen to the below events by implementing the following code on the server or client, depending on the event:"
            },
            {
                type = "Code",
                text = ("Ext.ModEvents[\"%s\"][\"<EVENT NAME HERE>\"]:Subscribe(function(payload)"):format(name)
            },
            {
                type = "SubHeading",
                text = "Mutation Profile Executed"
            },
            {
                type = "CallOut",
                text = "MutationProfileExecuted",
                prefix = "Event name"
            } --[[@as MazzleDocsCallOut]],
            {
                type = "CallOut",
                text = "Server Only",
                prefix = "Server/Client?"
            } --[[@as MazzleDocsCallOut]],
            {
                type = "Content",
                text =
                [[Sent when Lab has either successfully processed the active Mutation Profile or reverted all changes to entities due to there being no profile. Delayed by 200ms after the trigger to ensure all changes to entities are processed.
You can operate on every mutated entity by iterating on Ext.Vars.GetEntitiesWithVariable using the userVarKey in the event payload, as shown below.]]
            },
            {
                type = "Code",
                text = ([[
# Payload
{
   ["userVarKey"] = "%s",
   ["state"] = "Started"|"Completed"|"Errored" (one of the values, not all 3)
}

# Usage
for _, entity in pairs(Ext.Vars.GetEntitiesWithVariable(payload.userVarKey)) do ... end]]):format(ABSOLUTES_LABORATORY_MUTATIONS_VAR_NAME)
            },
            {
                type = "SubHeading",
                text = "Monster Lab Profile Executed"
            },
            {
                type = "CallOut",
                text = "MonsterLabProfileExecuted",
                prefix = "Event name"
            } --[[@as MazzleDocsCallOut]],
            {
                type = "CallOut",
                text = "Server Only",
                prefix = "Server/Client?"
            } --[[@as MazzleDocsCallOut]],
            {
                type = "Content",
                text =
                [[Sent when Lab has either successfully processed the active Monster Lab Profile or removed all spawned entities due to there being no active profile. Delayed by 200ms after the trigger to ensure all changes to entities are processed.
You can operate on every spawned in entity by iterating on Ext.Vars.GetEntitiesWithVariable using the userVarKey in the event payload, as shown below.]]
            },
            {
                type = "Code",
                text = ([[
# Payload
{
   ["userVarKey"] = "%s",
   ["state"] = "Started"|"Completed"|"Errored" (one of the values, not all 3)
}

# Usage
for _, entity in pairs(Ext.Vars.GetEntitiesWithVariable(payload.userVarKey)) do ... end]]):format(ABSOLUTES_LABORATORY_MONSTER_LAB_ENTITY_VAR)
            }
        }
    } --[[@as MazzleDocsSlide]])

    return existingSlides
end

---@return {[string]: MazzleDocsContentItem}
function ModEventsManager:generateChangelog()
    return {
        ["1.12.0"] = {
            type = "Bullet",
            text = "Added 'state' fields to existing payloads - can be one of \"Started\"|\"Completed\"|\"Errored\""
        },
        ["1.11.0"] = {
            type = "Bullet",
            text = "Initial Release"
        }
    } --[[@as {[string]: MazzleDocsContentItem}]]
end
