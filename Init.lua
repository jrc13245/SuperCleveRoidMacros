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

-- GUID-based cast tracking (populated by pfUI 7.6 or standalone SPELL_START events)
-- Format: [casterGuid] = {spellID, spellName, icon, startTime, duration, endTime}
CleveRoids.castTracking = {}

-- pfUI 7.6+ with Nampower 2.31.0+ detected (GUID-based cast tracking available)
CleveRoids.hasPfUI76 = false

-- Combo point tracking (initialized early for /cast hook)
CleveRoids.lastComboPoints = 0
CleveRoids.lastComboPointsTime = 0

-- Resist tracking state
-- Structure: { resistType = "full"|"partial", targetGUID = guid }
CleveRoids.resistState = nil

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

-- Enhanced casting state tracking
CleveRoids.UpdateCastingState = function()
    if not GetCurrentCastingInfo then return false end

    local castId, visId, autoId, casting, channeling, onswing, autoattack = GetCurrentCastingInfo()

    -- Update CurrentSpell based on actual cast state
    -- NOTE: Channel state is EXCLUSIVELY managed by SPELLCAST_CHANNEL_START/STOP events
    -- This function NEVER touches channel state, only regular casts
    if casting == 1 then
        CleveRoids.CurrentSpell.type = "cast"
        CleveRoids.CurrentSpell.castingSpellId = castId
    elseif CleveRoids.CurrentSpell.type == "cast" then
        -- Only clear if we were in a regular cast (not channel)
        CleveRoids.CurrentSpell.type = ""
        CleveRoids.CurrentSpell.castingSpellId = nil
    end
    -- DO NOT touch channel state here - events handle it

    -- Always update metadata from GetCurrentCastingInfo (onswing/autoattack only here)
    CleveRoids.CurrentSpell.autoAttack = (autoattack == 1)
    CleveRoids.CurrentSpell.onSwingPending = (onswing == 1)
    CleveRoids.CurrentSpell.visualSpellId = visId
    CleveRoids.CurrentSpell.autoRepeatSpellId = autoId

    -- Enhanced timing data from GetCastInfo (Nampower 2.18+)
    if GetCastInfo then
        local ok, info = pcall(GetCastInfo)
        if ok and info then
            CleveRoids.CurrentSpell.castRemainingMs = info.castRemainingMs
            CleveRoids.CurrentSpell.castEndTime = info.castEndS
            CleveRoids.CurrentSpell.gcdRemainingMs = info.gcdRemainingMs
            CleveRoids.CurrentSpell.gcdEndTime = info.gcdEndS
        else
            CleveRoids.CurrentSpell.castRemainingMs = nil
            CleveRoids.CurrentSpell.castEndTime = nil
            CleveRoids.CurrentSpell.gcdRemainingMs = nil
            CleveRoids.CurrentSpell.gcdEndTime = nil
        end
    end

    return true
end

CleveRoids.dynamicCmds = {
    ["/cast"]         = true,
    ["/castpet"]      = true,
    ["/castsequence"] = true,
    ["/use"]          = true,
    ["/equip"]        = true,
    ["/equipmh"]      = true,
    ["/equipoh"]      = true,
    ["/equip11"]      = true,
    ["/equip12"]      = true,
    ["/equip13"]      = true,
    ["/equip14"]      = true,
    ["/applymain"]    = true,
    ["/applyoff"]     = true,
}

-- Equipment swap queue system
CleveRoids.equipmentQueue = {}
CleveRoids.equipmentQueueLen = 0  -- PERFORMANCE: Track length to avoid table.getn() every frame
CleveRoids.lastEquipTime = {}
CleveRoids.lastGlobalEquipTime = 0
CleveRoids.EQUIP_COOLDOWN = 1.5  -- Per-slot cooldown
CleveRoids.EQUIP_GLOBAL_COOLDOWN = 0.5  -- Global cooldown

-- PERFORMANCE: Table pool for queue entries to reduce garbage collection
CleveRoids.queueEntryPool = {}

-- PERFORMANCE: Static buffer for proc removal to avoid per-frame allocation
CleveRoids._procRemovalBuffer = {}

-- PERFORMANCE: Static buffer for action grouping to avoid per-call allocation
CleveRoids._actionsToSlotsBuffer = {}
CleveRoids._slotsBuffer = {}
CleveRoids._actionsListBuffer = {}

-- PERFORMANCE: Static buffer for arg backup in SendEventForAction
CleveRoids._originalArgsBuffer = {}

-- Spell queue state (Nampower)
CleveRoids.queuedSpell = nil
CleveRoids.lastCastSpell = nil

-- Macro execution control
CleveRoids.stopMacroFlag = false

-- PERFORMANCE: Event-driven cached state (updated on events, not polled)
CleveRoids._cachedPlayerInCombat = nil   -- Updated on PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED

CleveRoids.ignoreKeywords = {
    action        = true,
    ignoretooltip = true,
    cancelaura    = true,
    noSpam        = true,  -- ! prefix flag: prevent toggle-off at execution time
    _operators    = true,  -- Metadata for AND/OR operator tracking
    _groups       = true,  -- Grouped conditional values for AND/OR evaluation
    multiscan     = true,  -- Processed before Keywords loop (target resolution)
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
    ["Aquatic Form"]    = true,
}

CleveRoids.spamConditions = {
    [CleveRoids.Localized.Attack]   = "checkchanneled",
    [CleveRoids.Localized.AutoShot] = "checkchanneled",
    [CleveRoids.Localized.Shoot]    = "checkchanneled",
}

-- PERFORMANCE: Static lookup for toggled buff abilities (built once, used per-frame)
CleveRoids._toggledBuffAbilities = {
    [CleveRoids.Localized.Spells["Prowl"]] = true,
    [CleveRoids.Localized.Spells["Shadowmeld"]] = true,
}

function CleveRoids.IsToggledBuffAbility(spellName)
    return CleveRoids._toggledBuffAbilities[spellName]
end

CleveRoids.auraTextures = {
    [CleveRoids.Localized.Spells["Stealth"]]    = "Interface\\Icons\\Ability_Stealth",
    [CleveRoids.Localized.Spells["Prowl"]]      = "Interface\\Icons\\Spell_Nature_Invisibilty",
    [CleveRoids.Localized.Spells["Shadowform"]] = "Interface\\Icons\\Spell_Shadow_Shadowform",
    [CleveRoids.Localized.Spells["Shadowmeld"]] = "Interface\\Icons\\Spell_Nature_WispSplode",
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

-- Detect available features
CleveRoids.hasNampower = (QueueSpellByName ~= nil)
CleveRoids.hasUnitXP = pcall(UnitXP, "nop", "nop")

-- Extended Nampower feature flags (populated by NampowerAPI.lua)
CleveRoids.nampowerVersion = { major = 0, minor = 0, patch = 0 }
CleveRoids.hasExtendedNampower = false  -- True if v2.12+ with new API functions

-- Feature detection messages
local function PrintFeatures()
    local features = {}
    if CleveRoids.hasSuperwow then table.insert(features, "SuperWoW") end
    if CleveRoids.hasNampower then
        local ver = CleveRoids.nampowerVersion
        if ver.major > 0 then
            table.insert(features, string.format("Nampower v%d.%d.%d", ver.major, ver.minor, ver.patch))
        else
            table.insert(features, "Nampower")
        end
    end
    if CleveRoids.hasUnitXP then table.insert(features, "UnitXP") end
    if CleveRoids.hasTurtle then table.insert(features, "Turtle") end

    if table.getn(features) > 0 then
        CleveRoids.Print("Enhanced features: " .. table.concat(features, ", "))
    end
end

-- Immunity data version - increment this when changing immunity data format
-- This will cause all immunity data to be reset on addon update
-- v3: Fixed Master Strike false physical immunity recording (split CC spell handling)
CleveRoids.IMMUNITY_DATA_VERSION = 3

-- Call on next frame to ensure everything is loaded
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function()
    this:UnregisterAllEvents()

    -- Check immunity data version and reset if outdated
    CleveRoidMacros = CleveRoidMacros or {}
    CleveRoids_ImmunityData = CleveRoids_ImmunityData or {}
    local savedVersion = CleveRoidMacros.immunityDataVersion or 0

    if savedVersion < CleveRoids.IMMUNITY_DATA_VERSION then
        -- Check if there was existing data to clear
        local hadData = next(CleveRoids_ImmunityData) ~= nil

        -- Version changed - reset all immunity data
        CleveRoids_ImmunityData = {}
        CleveRoidMacros.immunityDataVersion = CleveRoids.IMMUNITY_DATA_VERSION

        if hadData then
            -- Show message if we actually cleared existing data
            CleveRoids.Print("|cffff9900Immunity data reset|r - addon updated to data version " .. CleveRoids.IMMUNITY_DATA_VERSION)
        end
    end

    -- Initialize NampowerAPI if available
    if CleveRoids.NampowerAPI then
        local API = CleveRoids.NampowerAPI

        -- Get version info
        local major, minor, patch = API.GetVersion()
        CleveRoids.nampowerVersion = { major = major, minor = minor, patch = patch }

        -- Check for extended API (v2.12+)
        CleveRoids.hasExtendedNampower = API.HasMinimumVersion(2, 12, 0)

        -- Sync feature flags
        if API.features then
            CleveRoids.hasGetSpellRec = API.features.hasGetSpellRec
            CleveRoids.hasGetItemStats = API.features.hasGetItemStats
            CleveRoids.hasGetUnitData = API.features.hasGetUnitData
            CleveRoids.hasGetSpellModifiers = API.features.hasGetSpellModifiers
            CleveRoids.hasEnhancedSpellFunctions = API.features.hasEnhancedSpellFunctions
            -- v2.37+: CastSpellByName supports unit token strings as 2nd param
            CleveRoids.hasCastSpellByNameUnitToken = API.features.hasCastSpellByNameUnitToken
        end

        -- Initialize the API
        API.Initialize()
    end

    PrintFeatures()
end)

_G["CleveRoids"] = CleveRoids
