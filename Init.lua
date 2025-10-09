local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids

CleveRoids.ready = false

CleveRoids.Hooks             = CleveRoids.Hooks      or {}
CleveRoids.Hooks.GameTooltip = {}

CleveRoids.Extensions          = CleveRoids.Extensions or {}
CleveRoids.actionEventHandlers = {}
CleveRoids.mouseOverResolvers  = {}

CleveRoids.mouseoverUnit = CleveRoids.mouseoverUnit or nil
CleveRoids.mouseOverUnit = nil

-- Environment flags
CleveRoids.hasSuperwow = SetAutoloot and true or false
CleveRoids.hasTurtle   = (type(_G.TURTLE_WOW_VERSION) ~= "nil")
CleveRoids.supported   = (CleveRoids.hasSuperwow or CleveRoids.hasTurtle)

CleveRoids.ParsedMsg = {}
CleveRoids.Items     = {}
CleveRoids.Spells    = {}
CleveRoids.PetSpells = {}
CleveRoids.Talents   = {}
CleveRoids.Cooldowns = {}
CleveRoids.Macros    = {}
CleveRoids.Actions   = {}
CleveRoids.Sequences = {}

CleveRoids.lastUpdate = 0
CleveRoids.lastGetItem = nil
CleveRoids.currentSequence = nil

CleveRoids.bookTypes = {BOOKTYPE_SPELL, BOOKTYPE_PET}
CleveRoids.unknownTexture = "Interface\\Icons\\INV_Misc_QuestionMark"

CleveRoids.spell_tracking = {}

-- Holds information about the currently cast spell
CleveRoids.CurrentSpell = {
    -- "channeled" or "cast"
    type = "",
    -- the name of the spell
    spellName = "",
    -- is the Attack ability enabled
    autoAttack = false,
    -- is the Auto Shot ability enabled
    autoShot = false,
    -- is the Shoot ability (wands) enabled
    wand = false,
}

CleveRoids.dynamicCmds = {
    ["/cast"]         = true,
    ["/castpet"]      = true,
    ["/castsequence"] = true,
    ["/use"]          = true,
    ["/equip"]        = true,
    ["/equipmh"]      = true,
    ["/equipoh"]      = true,
}

CleveRoids.ignoreKeywords = {
    action        = true,
    ignoretooltip = true,
    cancelaura    = true,
}

-- TODO: Localize?
CleveRoids.countedItemTypes = {
    ["Consumable"]  = true,
    ["Reagent"]     = true,
    ["Projectile"]  = true,
    ["Trade Goods"] = true,
}


-- TODO: Localize?
CleveRoids.actionSlots    = {}
CleveRoids.reactiveSlots  = {}
CleveRoids.reactiveSpells = {
    ["Revenge"]         = true,
    ["Overpower"]       = true,
    ["Riposte"]         = true,
    ["Surprise Attack"] = true,
    ["Lacerate"]        = true,
    ["Baited Shot"]     = true,
    ["Counterattack"]   = true,
    ["Arcane Surge"]    = true,
}

CleveRoids.spamConditions = {
    [CleveRoids.Localized.Attack]   = "checkchanneled",
    [CleveRoids.Localized.AutoShot] = "checkchanneled",
    [CleveRoids.Localized.Shoot]    = "checkchanneled",
}

CleveRoids.auraTextures = {
    [CleveRoids.Localized.Spells["Stealth"]]    = "Interface\\Icons\\Ability_Stealth",
    [CleveRoids.Localized.Spells["Prowl"]]      = "Interface\\Icons\\Ability_Ambush",
    [CleveRoids.Localized.Spells["Shadowform"]] = "Interface\\Icons\\Spell_Shadow_Shadowform",
    ["Seal of Wisdom"] = "Interface\\Icons\\Spell_Holy_RighteousnessAura",
    ["Seal of the Crusader"] = "Interface\\Icons\\Spell_Holy_HolySmite",
    ["Seal of Light"] = "Interface\\Icons\\Spell_Holy_HealingAura",
    ["Seal of the Justice"] = "Interface\\Icons\\Spell_Holy_SealOfWrath",
    ["Seal of Righteousness"] = "Interface\\Icons\\Ability_ThunderBolt",
    ["Seal of Command"] = "Interface\\Icons\\Ability_Warrior_InnerRage",
}


-- I need to make a 2h modifier
-- Maps easy to use weapon type names (e.g. Axes, Shields) to their inventory slot name and their localized tooltip name
CleveRoids.WeaponTypeNames = {
    Daggers   = { slot = "MainHandSlot", name = CleveRoids.Localized.Dagger },
    Fists     = { slot = "MainHandSlot", name = CleveRoids.Localized.FistWeapon },
    Axes      = { slot = "MainHandSlot", name = CleveRoids.Localized.Axe },
    Swords    = { slot = "MainHandSlot", name = CleveRoids.Localized.Sword },
    Staves    = { slot = "MainHandSlot", name = CleveRoids.Localized.Staff },
    Maces     = { slot = "MainHandSlot", name = CleveRoids.Localized.Mace },
    Polearms  = { slot = "MainHandSlot", name = CleveRoids.Localized.Polearm },
    -- OH
    Daggers2  = { slot = "SecondaryHandSlot", name = CleveRoids.Localized.Dagger },
    Fists2    = { slot = "SecondaryHandSlot", name = CleveRoids.Localized.FistWeapon },
    Axes2     = { slot = "SecondaryHandSlot", name = CleveRoids.Localized.Axe },
    Swords2   = { slot = "SecondaryHandSlot", name = CleveRoids.Localized.Sword },
    Maces2    = { slot = "SecondaryHandSlot", name = CleveRoids.Localized.Mace },
    Shields   = { slot = "SecondaryHandSlot", name = CleveRoids.Localized.Shield },
    -- ranged
    Guns      = { slot = "RangedSlot", name = CleveRoids.Localized.Gun },
    Crossbows = { slot = "RangedSlot", name = CleveRoids.Localized.Crossbow },
    Bows      = { slot = "RangedSlot", name = CleveRoids.Localized.Bow },
    Thrown    = { slot = "RangedSlot", name = CleveRoids.Localized.Thrown },
    Wands     = { slot = "RangedSlot", name = CleveRoids.Localized.Wand },
}

_G["CleveRoids"] = CleveRoids
