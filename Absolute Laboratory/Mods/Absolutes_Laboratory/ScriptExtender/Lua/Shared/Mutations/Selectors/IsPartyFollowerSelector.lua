IS_PARTY_FOLLOWER_VAR_NAME = "AbsolutesLaboratory_IsPartyFollowerSelectorRan"

Ext.Vars.RegisterUserVariable(IS_PARTY_FOLLOWER_VAR_NAME, {
    Server = true,
    WriteableOnServer = true
})

IsPartyFollowerSelector = SelectorInterface:new("Is Party Follower")

function IsPartyFollowerSelector:handleDependencies()
    -- NOOP
end

---@class InPartySelector : Selector
---@field criteriaValue boolean

---@param existingSelector InPartySelector
function IsPartyFollowerSelector:renderSelector(parent, existingSelector)
    existingSelector.criteriaValue = existingSelector.criteriaValue == nil and true or existingSelector.criteriaValue

    parent:AddText([[
    This selector exists for specific scenarios where you want a NPC to have one set of mutations while they're an enemy, and another while they're an ally (i.e. the Emperor).
    Only mutations that have this selector set to Inclusive (checkbox is checked) will be run against PartyFollowers, to ensure no undesired mutations are leftover.
    Use the inclusive checkbox to set true/false.
]]).TextWrapPos = 0
end

---@param selector InPartySelector
---@return fun(entity: EntityHandle|EntityRecord):boolean
function IsPartyFollowerSelector:predicate(selector)
    return function(entity)
        if type(entity) == "userdata" then
            ---@cast entity EntityHandle

            entity.Vars[IS_PARTY_FOLLOWER_VAR_NAME] = true

            return Osi.IsPartyFollower(entity.Uuid.EntityUuid) == 1
        else
            return true
        end
    end
end

function IsPartyFollowerSelector:cleanup()
    -- NOOP
end

function IsPartyFollowerSelector:generateDocs()
end
