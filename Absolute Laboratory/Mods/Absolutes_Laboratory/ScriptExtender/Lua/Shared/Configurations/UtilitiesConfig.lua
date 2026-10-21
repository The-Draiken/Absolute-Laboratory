---@class UtilitiesConfig
ConfigurationStructure.config.utilities = {}

---@class PassiveDuplicateRemoverConfig
ConfigurationStructure.config.utilities.passiveDupeRemover = {
    enabled = true,
    whitelistMode = true,
    ---@type string[]
    whitelist = {
        "MAG_ArcaneEnchantment_Lesser_Passive",
        "MAG_ArcaneEnchantment_Passive",
        "MAG_SpellSaveDC_Enchantment_Lesser_Passive",
        "MAG_SpellSaveDC_Enchantment_Passive"
    },
    ---@type string[]
    blacklist = {}
}
