--[[
    Multi-Target Debuff Tracker Extension (Cursive-style rewrite)
    Tracks player's debuffs across multiple enemy targets
    Based on Cursive addon architecture by Pepopo

    Features:
    - Per-class spell tables (only tracks spells you can cast)
    - UNIT_CASTEVENT based tracking with debuff scan verification
    - Resist/immune detection via chat parsing
    - Display priority: raid marks -> highest HP -> rest
]]

local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("MultiTargetTracker")

-- ============================================================================
-- Configuration
-- ============================================================================

local MAX_TRACKED_TARGETS = 15
local MAX_DEBUFFS_PER_ROW = 8
local UPDATE_INTERVAL = 0.1  -- 10 Hz

local CONFIG = {
    barHeight = 20,
    barSpacing = 2,
    targetIndicatorSize = 8,
    raidIconSize = 16,
    healthBarWidth = 140,
    debuffIconSize = 20,
    debuffIconSpacing = 2,
    padding = 2,
    titleHeight = 16,
    textSize = 10,
}

local BACKDROP_BORDER = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

local BACKDROP_BACKGROUND = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true, tileSize = 16,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
}

local COLORS = {
    borderNormal = { 0.2, 0.2, 0.2, 1 },
    borderHover = { 1, 1, 1, 1 },
    borderCombat = { 0.8, 0.2, 0.2, 1 },
    healthDefault = { 1, 0.8, 0.2, 1 },
    timerNormal = { 1, 1, 1 },
    timerExpiring = { 1, 0.2, 0.2 },
    titleText = { 1, 0.82, 0, 1 },
}

-- ============================================================================
-- Per-Class Spell Tables (Cursive format)
-- ============================================================================

local playerClassName = nil  -- Set in LoadClassSpells()

-- Combo point tracking for finisher duration calculation
local previousComboPoints = 0
local currentComboPoints = 0

local function GetComboPointsUsed()
    if currentComboPoints == 0 then
        return previousComboPoints
    end
    return currentComboPoints
end

-- Duration calculators for combo point scaling
local function getRipDuration()
    return 8 + GetComboPointsUsed() * 2
end

local function getRuptureDuration()
    local duration = 6 + GetComboPointsUsed() * 2
    -- Check for Improved Rupture talent (Assassination tree, tier 10)
    local _, _, _, _, count = GetTalentInfo(1, 10)
    if count and count > 0 then
        duration = duration + (count * 2)
    end
    return duration
end

local function getKidneyShotDuration()
    return 1 + GetComboPointsUsed()
end

local function getGougeDuration()
    -- Improved Gouge talent (Combat tree, tier 1)
    local _, _, _, _, count = GetTalentInfo(2, 1)
    if count and count > 0 then
        return 4 + (count * 0.5)
    end
    return 4
end

-- Class spell tables
local function getDruidSpells()
    return {
        -- Entangling Roots
        [339] = { name = "entangling roots", rank = 1, duration = 12 },
        [1062] = { name = "entangling roots", rank = 2, duration = 15 },
        [5195] = { name = "entangling roots", rank = 3, duration = 18 },
        [5196] = { name = "entangling roots", rank = 4, duration = 21 },
        [9852] = { name = "entangling roots", rank = 5, duration = 24 },
        [9853] = { name = "entangling roots", rank = 6, duration = 27 },
        -- Hibernate
        [2637] = { name = "hibernate", rank = 1, duration = 20 },
        [18657] = { name = "hibernate", rank = 2, duration = 30 },
        [18658] = { name = "hibernate", rank = 3, duration = 40 },
        -- Faerie Fire (all versions use same name for blocking)
        [770] = { name = "faerie fire", rank = 1, duration = 40 },
        [778] = { name = "faerie fire", rank = 2, duration = 40 },
        [9749] = { name = "faerie fire", rank = 3, duration = 40 },
        [9907] = { name = "faerie fire", rank = 4, duration = 40 },
        [16855] = { name = "faerie fire", rank = 1, duration = 40 },
        [17387] = { name = "faerie fire", rank = 2, duration = 40 },
        [17388] = { name = "faerie fire", rank = 3, duration = 40 },
        [17389] = { name = "faerie fire", rank = 4, duration = 40 },
        [16857] = { name = "faerie fire", rank = 1, duration = 40 },
        [17390] = { name = "faerie fire", rank = 2, duration = 40 },
        [17391] = { name = "faerie fire", rank = 3, duration = 40 },
        [17392] = { name = "faerie fire", rank = 4, duration = 40 },
        -- Insect Swarm
        [5570] = { name = "insect swarm", rank = 1, duration = 18 },
        [24974] = { name = "insect swarm", rank = 2, duration = 18 },
        [24975] = { name = "insect swarm", rank = 3, duration = 18 },
        [24976] = { name = "insect swarm", rank = 4, duration = 18 },
        [24977] = { name = "insect swarm", rank = 5, duration = 18 },
        -- Moonfire
        [8921] = { name = "moonfire", rank = 1, duration = 9 },
        [8924] = { name = "moonfire", rank = 2, duration = 12 },
        [8925] = { name = "moonfire", rank = 3, duration = 12 },
        [8926] = { name = "moonfire", rank = 4, duration = 12 },
        [8927] = { name = "moonfire", rank = 5, duration = 12 },
        [8928] = { name = "moonfire", rank = 6, duration = 12 },
        [8929] = { name = "moonfire", rank = 7, duration = 12 },
        [9833] = { name = "moonfire", rank = 8, duration = 12 },
        [9834] = { name = "moonfire", rank = 9, duration = 12 },
        [9835] = { name = "moonfire", rank = 10, duration = 12 },
        -- Rake
        [1822] = { name = "rake", rank = 1, duration = 9 },
        [1823] = { name = "rake", rank = 2, duration = 9 },
        [1824] = { name = "rake", rank = 3, duration = 9 },
        [9904] = { name = "rake", rank = 4, duration = 9 },
        -- Rip (combo point scaling)
        [1079] = { name = "rip", rank = 1, duration = 8, calculateDuration = getRipDuration },
        [9492] = { name = "rip", rank = 2, duration = 8, calculateDuration = getRipDuration },
        [9493] = { name = "rip", rank = 3, duration = 8, calculateDuration = getRipDuration },
        [9752] = { name = "rip", rank = 4, duration = 8, calculateDuration = getRipDuration },
        [9894] = { name = "rip", rank = 5, duration = 8, calculateDuration = getRipDuration },
        [9896] = { name = "rip", rank = 6, duration = 8, calculateDuration = getRipDuration },
        -- Bash
        [5211] = { name = "bash", rank = 1, duration = 2 },
        [6798] = { name = "bash", rank = 2, duration = 3 },
        [8983] = { name = "bash", rank = 3, duration = 4 },
        -- Demoralizing Roar
        [99] = { name = "demoralizing roar", rank = 1, duration = 30 },
        [1735] = { name = "demoralizing roar", rank = 2, duration = 30 },
        [9490] = { name = "demoralizing roar", rank = 3, duration = 30 },
        [9747] = { name = "demoralizing roar", rank = 4, duration = 30 },
        [9898] = { name = "demoralizing roar", rank = 5, duration = 30 },
        -- Pounce Bleed
        [9005] = { name = "pounce bleed", rank = 1, duration = 18 },
        [9823] = { name = "pounce bleed", rank = 2, duration = 18 },
        [9827] = { name = "pounce bleed", rank = 3, duration = 18 },
    }
end

local function getRogueSpells()
    return {
        -- Blind
        [2094] = { name = "blind", rank = 1, duration = 10 },
        [21060] = { name = "blind", rank = 1, duration = 10 },
        -- Sap
        [6770] = { name = "sap", rank = 1, duration = 25 },
        [2070] = { name = "sap", rank = 2, duration = 35 },
        [11297] = { name = "sap", rank = 3, duration = 45 },
        -- Gouge (talent scaling)
        [1776] = { name = "gouge", rank = 1, duration = 4, calculateDuration = getGougeDuration },
        [1777] = { name = "gouge", rank = 2, duration = 4, calculateDuration = getGougeDuration },
        [8629] = { name = "gouge", rank = 3, duration = 4, calculateDuration = getGougeDuration },
        [11285] = { name = "gouge", rank = 4, duration = 4, calculateDuration = getGougeDuration },
        [11286] = { name = "gouge", rank = 5, duration = 4, calculateDuration = getGougeDuration },
        -- Rupture (combo point + talent scaling)
        [1943] = { name = "rupture", rank = 1, duration = 6, calculateDuration = getRuptureDuration },
        [8639] = { name = "rupture", rank = 2, duration = 6, calculateDuration = getRuptureDuration },
        [8640] = { name = "rupture", rank = 3, duration = 6, calculateDuration = getRuptureDuration },
        [11273] = { name = "rupture", rank = 4, duration = 6, calculateDuration = getRuptureDuration },
        [11274] = { name = "rupture", rank = 5, duration = 6, calculateDuration = getRuptureDuration },
        [11275] = { name = "rupture", rank = 6, duration = 6, calculateDuration = getRuptureDuration },
        -- Kidney Shot (combo point scaling)
        [408] = { name = "kidney shot", rank = 1, duration = 1, calculateDuration = getKidneyShotDuration },
        [8643] = { name = "kidney shot", rank = 2, duration = 1, calculateDuration = getKidneyShotDuration },
        -- Expose Armor
        [8647] = { name = "expose armor", rank = 1, duration = 30 },
        [8649] = { name = "expose armor", rank = 2, duration = 30 },
        [8650] = { name = "expose armor", rank = 3, duration = 30 },
        [11197] = { name = "expose armor", rank = 4, duration = 30 },
        [11198] = { name = "expose armor", rank = 5, duration = 30 },
        -- Garrote
        [703] = { name = "garrote", rank = 1, duration = 18 },
        [8631] = { name = "garrote", rank = 2, duration = 18 },
        [8632] = { name = "garrote", rank = 3, duration = 18 },
        [8633] = { name = "garrote", rank = 4, duration = 18 },
        [11289] = { name = "garrote", rank = 5, duration = 18 },
        [11290] = { name = "garrote", rank = 6, duration = 18 },
        -- Deadly Poison
        [2818] = { name = "deadly poison", rank = 1, duration = 12 },
        [2819] = { name = "deadly poison ii", rank = 2, duration = 12 },
        [11353] = { name = "deadly poison iii", rank = 3, duration = 12 },
        [11354] = { name = "deadly poison iv", rank = 4, duration = 12 },
        [25349] = { name = "deadly poison v", rank = 5, duration = 12 },
        -- Hemorrhage
        [16511] = { name = "hemorrhage", rank = 1, duration = 15 },
        -- Cheap Shot
        [1833] = { name = "cheap shot", rank = 1, duration = 4 },
        [14902] = { name = "cheap shot", rank = 1, duration = 4 },
    }
end

local function getWarriorSpells()
    return {
        -- Rend
        [772] = { name = "rend", rank = 1, duration = 9 },
        [6546] = { name = "rend", rank = 2, duration = 12 },
        [6547] = { name = "rend", rank = 3, duration = 15 },
        [6548] = { name = "rend", rank = 4, duration = 18 },
        [11572] = { name = "rend", rank = 5, duration = 21 },
        [11573] = { name = "rend", rank = 6, duration = 21 },
        [11574] = { name = "rend", rank = 7, duration = 21 },
        -- Hamstring
        [1715] = { name = "hamstring", rank = 1, duration = 15 },
        [7372] = { name = "hamstring", rank = 2, duration = 15 },
        [7373] = { name = "hamstring", rank = 3, duration = 15 },
        -- Thunder Clap
        [6343] = { name = "thunder clap", rank = 1, duration = 10 },
        [8198] = { name = "thunder clap", rank = 2, duration = 14 },
        [8205] = { name = "thunder clap", rank = 3, duration = 18 },
        [11580] = { name = "thunder clap", rank = 4, duration = 22 },
        [11581] = { name = "thunder clap", rank = 5, duration = 26 },
        -- Demoralizing Shout
        [1160] = { name = "demoralizing shout", rank = 1, duration = 30 },
        [6190] = { name = "demoralizing shout", rank = 2, duration = 30 },
        [11554] = { name = "demoralizing shout", rank = 3, duration = 30 },
        [11555] = { name = "demoralizing shout", rank = 4, duration = 30 },
        [11556] = { name = "demoralizing shout", rank = 5, duration = 30 },
        -- Sunder Armor
        [7386] = { name = "sunder armor", rank = 1, duration = 30 },
        [7405] = { name = "sunder armor", rank = 2, duration = 30 },
        [8380] = { name = "sunder armor", rank = 3, duration = 30 },
        [11596] = { name = "sunder armor", rank = 4, duration = 30 },
        [11597] = { name = "sunder armor", rank = 5, duration = 30 },
    }
end

local function getWarlockSpells()
    return {
        -- Corruption
        [172] = { name = "corruption", rank = 1, duration = 12 },
        [6222] = { name = "corruption", rank = 2, duration = 15 },
        [6223] = { name = "corruption", rank = 3, duration = 18 },
        [7648] = { name = "corruption", rank = 4, duration = 18 },
        [11671] = { name = "corruption", rank = 5, duration = 18 },
        [11672] = { name = "corruption", rank = 6, duration = 18 },
        [25311] = { name = "corruption", rank = 7, duration = 18 },
        -- Curse of Agony
        [980] = { name = "curse of agony", rank = 1, duration = 24 },
        [1014] = { name = "curse of agony", rank = 2, duration = 24 },
        [6217] = { name = "curse of agony", rank = 3, duration = 24 },
        [11711] = { name = "curse of agony", rank = 4, duration = 24 },
        [11712] = { name = "curse of agony", rank = 5, duration = 24 },
        [11713] = { name = "curse of agony", rank = 6, duration = 24 },
        -- Siphon Life
        [18265] = { name = "siphon life", rank = 1, duration = 30 },
        [18879] = { name = "siphon life", rank = 2, duration = 30 },
        [18880] = { name = "siphon life", rank = 3, duration = 30 },
        [18881] = { name = "siphon life", rank = 4, duration = 30 },
        -- Curse of Doom
        [603] = { name = "curse of doom", rank = 1, duration = 60 },
        -- Curse of Recklessness
        [704] = { name = "curse of recklessness", rank = 1, duration = 120 },
        [7658] = { name = "curse of recklessness", rank = 2, duration = 120 },
        [7659] = { name = "curse of recklessness", rank = 3, duration = 120 },
        [11717] = { name = "curse of recklessness", rank = 4, duration = 120 },
        -- Curse of Shadow
        [17862] = { name = "curse of shadow", rank = 1, duration = 300 },
        [17937] = { name = "curse of shadow", rank = 2, duration = 300 },
        -- Curse of the Elements
        [1490] = { name = "curse of the elements", rank = 1, duration = 300 },
        [11721] = { name = "curse of the elements", rank = 2, duration = 300 },
        [11722] = { name = "curse of the elements", rank = 3, duration = 300 },
        -- Curse of Tongues
        [1714] = { name = "curse of tongues", rank = 1, duration = 30 },
        [11719] = { name = "curse of tongues", rank = 2, duration = 30 },
        -- Curse of Weakness
        [702] = { name = "curse of weakness", rank = 1, duration = 120 },
        [1108] = { name = "curse of weakness", rank = 2, duration = 120 },
        [6205] = { name = "curse of weakness", rank = 3, duration = 120 },
        [7646] = { name = "curse of weakness", rank = 4, duration = 120 },
        [11707] = { name = "curse of weakness", rank = 5, duration = 120 },
        [11708] = { name = "curse of weakness", rank = 6, duration = 120 },
        -- Curse of Exhaustion
        [18223] = { name = "curse of exhaustion", rank = 1, duration = 12 },
        -- Immolate
        [348] = { name = "immolate", rank = 1, duration = 15 },
        [707] = { name = "immolate", rank = 2, duration = 15 },
        [1094] = { name = "immolate", rank = 3, duration = 15 },
        [2941] = { name = "immolate", rank = 4, duration = 15 },
        [11665] = { name = "immolate", rank = 5, duration = 15 },
        [11667] = { name = "immolate", rank = 6, duration = 15 },
        [11668] = { name = "immolate", rank = 7, duration = 15 },
        [25309] = { name = "immolate", rank = 8, duration = 15 },
        -- Death Coil
        [6789] = { name = "death coil", rank = 1, duration = 3 },
        [17925] = { name = "death coil", rank = 2, duration = 3 },
        [17926] = { name = "death coil", rank = 3, duration = 3 },
        -- Banish
        [710] = { name = "banish", rank = 1, duration = 20 },
        [18647] = { name = "banish", rank = 2, duration = 30 },
        -- Fear
        [5782] = { name = "fear", rank = 1, duration = 10 },
        [6213] = { name = "fear", rank = 2, duration = 15 },
        [6215] = { name = "fear", rank = 3, duration = 20 },
    }
end

local function getHunterSpells()
    return {
        -- Scorpid Sting
        [3043] = { name = "scorpid sting", rank = 1, duration = 20 },
        [14275] = { name = "scorpid sting", rank = 2, duration = 20 },
        [14276] = { name = "scorpid sting", rank = 3, duration = 20 },
        [14277] = { name = "scorpid sting", rank = 4, duration = 20 },
        -- Serpent Sting
        [1978] = { name = "serpent sting", rank = 1, duration = 15 },
        [13549] = { name = "serpent sting", rank = 2, duration = 15 },
        [13550] = { name = "serpent sting", rank = 3, duration = 15 },
        [13551] = { name = "serpent sting", rank = 4, duration = 15 },
        [13552] = { name = "serpent sting", rank = 5, duration = 15 },
        [13553] = { name = "serpent sting", rank = 6, duration = 15 },
        [13554] = { name = "serpent sting", rank = 7, duration = 15 },
        [13555] = { name = "serpent sting", rank = 8, duration = 15 },
        [25295] = { name = "serpent sting", rank = 9, duration = 15 },
        -- Viper Sting
        [3034] = { name = "viper sting", rank = 1, duration = 8 },
        [14279] = { name = "viper sting", rank = 2, duration = 8 },
        [14280] = { name = "viper sting", rank = 3, duration = 8 },
        -- Wing Clip
        [2974] = { name = "wing clip", rank = 1, duration = 10 },
        [14267] = { name = "wing clip", rank = 2, duration = 10 },
        [14268] = { name = "wing clip", rank = 3, duration = 10 },
        -- Concussive Shot
        [5116] = { name = "concussive shot", rank = 1, duration = 4 },
        -- Wyvern Sting
        [19386] = { name = "wyvern sting", rank = 1, duration = 12 },
        [24132] = { name = "wyvern sting", rank = 2, duration = 12 },
        [24133] = { name = "wyvern sting", rank = 3, duration = 12 },
        -- Hunter's Mark
        [1130] = { name = "hunter's mark", rank = 1, duration = 120 },
        [14323] = { name = "hunter's mark", rank = 2, duration = 120 },
        [14324] = { name = "hunter's mark", rank = 3, duration = 120 },
        [14325] = { name = "hunter's mark", rank = 4, duration = 120 },
    }
end

local function getMageSpells()
    return {
        -- Polymorph
        [118] = { name = "polymorph", rank = 1, duration = 20 },
        [12824] = { name = "polymorph", rank = 2, duration = 30 },
        [12825] = { name = "polymorph", rank = 3, duration = 40 },
        [12826] = { name = "polymorph", rank = 4, duration = 50 },
        [28270] = { name = "polymorph: cow", rank = 1, duration = 50 },
        [28271] = { name = "polymorph: turtle", rank = 1, duration = 50 },
        [28272] = { name = "polymorph: pig", rank = 1, duration = 50 },
        -- Frostbolt (snare component)
        [116] = { name = "frostbolt", rank = 1, duration = 5 },
        [205] = { name = "frostbolt", rank = 2, duration = 6 },
        [837] = { name = "frostbolt", rank = 3, duration = 6 },
        [7322] = { name = "frostbolt", rank = 4, duration = 7 },
        [8406] = { name = "frostbolt", rank = 5, duration = 7 },
        [8407] = { name = "frostbolt", rank = 6, duration = 8 },
        [8408] = { name = "frostbolt", rank = 7, duration = 8 },
        [10179] = { name = "frostbolt", rank = 8, duration = 9 },
        [10180] = { name = "frostbolt", rank = 9, duration = 9 },
        [10181] = { name = "frostbolt", rank = 10, duration = 9 },
        [25304] = { name = "frostbolt", rank = 11, duration = 9 },
    }
end

local function getPriestSpells()
    return {
        -- Shackle Undead
        [9485] = { name = "shackle undead", rank = 1, duration = 30 },
        [9486] = { name = "shackle undead", rank = 2, duration = 40 },
        [10955] = { name = "shackle undead", rank = 3, duration = 50 },
        -- Mind Control
        [605] = { name = "mind control", rank = 1, duration = 60 },
        [10911] = { name = "mind control", rank = 2, duration = 30 },
        [10912] = { name = "mind control", rank = 3, duration = 30 },
        -- Devouring Plague
        [2944] = { name = "devouring plague", rank = 1, duration = 24 },
        [19276] = { name = "devouring plague", rank = 2, duration = 24 },
        [19277] = { name = "devouring plague", rank = 3, duration = 24 },
        [19278] = { name = "devouring plague", rank = 4, duration = 24 },
        [19279] = { name = "devouring plague", rank = 5, duration = 24 },
        [19280] = { name = "devouring plague", rank = 6, duration = 24 },
        -- Shadow Word: Pain
        [589] = { name = "shadow word: pain", rank = 1, duration = 18 },
        [594] = { name = "shadow word: pain", rank = 2, duration = 18 },
        [970] = { name = "shadow word: pain", rank = 3, duration = 18 },
        [992] = { name = "shadow word: pain", rank = 4, duration = 18 },
        [2767] = { name = "shadow word: pain", rank = 5, duration = 18 },
        [10892] = { name = "shadow word: pain", rank = 6, duration = 18 },
        [10893] = { name = "shadow word: pain", rank = 7, duration = 18 },
        [10894] = { name = "shadow word: pain", rank = 8, duration = 18 },
        -- Vampiric Embrace
        [15286] = { name = "vampiric embrace", rank = 1, duration = 60 },
        -- Holy Fire (DoT component)
        [14914] = { name = "holy fire", rank = 1, duration = 10 },
        [15262] = { name = "holy fire", rank = 2, duration = 10 },
        [15263] = { name = "holy fire", rank = 3, duration = 10 },
        [15264] = { name = "holy fire", rank = 4, duration = 10 },
        [15265] = { name = "holy fire", rank = 5, duration = 10 },
        [15266] = { name = "holy fire", rank = 6, duration = 10 },
        [15267] = { name = "holy fire", rank = 7, duration = 10 },
        [15261] = { name = "holy fire", rank = 8, duration = 10 },
    }
end

local function getShamanSpells()
    return {
        -- Flame Shock
        [8050] = { name = "flame shock", rank = 1, duration = 12 },
        [8052] = { name = "flame shock", rank = 2, duration = 12 },
        [8053] = { name = "flame shock", rank = 3, duration = 12 },
        [10447] = { name = "flame shock", rank = 4, duration = 12 },
        [10448] = { name = "flame shock", rank = 5, duration = 12 },
        [29228] = { name = "flame shock", rank = 6, duration = 12 },
        -- Frost Shock (snare)
        [8056] = { name = "frost shock", rank = 1, duration = 8 },
        [8058] = { name = "frost shock", rank = 2, duration = 8 },
        [10472] = { name = "frost shock", rank = 3, duration = 8 },
        [10473] = { name = "frost shock", rank = 4, duration = 8 },
    }
end

local function getPaladinSpells()
    return {
        -- Judgement of the Crusader
        [21183] = { name = "judgement of the crusader", rank = 1, duration = 10 },
        [20188] = { name = "judgement of the crusader", rank = 2, duration = 10 },
        [20300] = { name = "judgement of the crusader", rank = 3, duration = 10 },
        [20301] = { name = "judgement of the crusader", rank = 4, duration = 10 },
        [20302] = { name = "judgement of the crusader", rank = 5, duration = 10 },
        [20303] = { name = "judgement of the crusader", rank = 6, duration = 10 },
        -- Judgement of Light
        [20185] = { name = "judgement of light", rank = 1, duration = 10 },
        [20267] = { name = "judgement of light", rank = 2, duration = 10 },
        [20268] = { name = "judgement of light", rank = 3, duration = 10 },
        [20271] = { name = "judgement of light", rank = 4, duration = 10 },
        -- Judgement of Wisdom
        [20186] = { name = "judgement of wisdom", rank = 1, duration = 10 },
        [20354] = { name = "judgement of wisdom", rank = 2, duration = 10 },
        [20355] = { name = "judgement of wisdom", rank = 3, duration = 10 },
        -- Judgement of Justice
        [20184] = { name = "judgement of justice", rank = 1, duration = 10 },
        -- Hammer of Justice
        [853] = { name = "hammer of justice", rank = 1, duration = 3 },
        [5588] = { name = "hammer of justice", rank = 2, duration = 4 },
        [5589] = { name = "hammer of justice", rank = 3, duration = 5 },
        [10308] = { name = "hammer of justice", rank = 4, duration = 6 },
    }
end

-- ============================================================================
-- State Variables
-- ============================================================================

local trackedSpellIds = {}           -- spellID -> { name, rank, duration, texture, ... }
local trackedSpellNamesToTextures = {} -- "rake" -> texture path
local discoveredGuids = {}           -- guid -> timestamp (when discovered)
local trackedDebuffs = {}            -- guid -> { [spellName] = { spellID, rank, duration, start, texture } }
local pendingCast = {}               -- Current pending cast { spellID, targetGuid, time }
local lastTargetGuid = nil           -- Last target GUID for resist detection

local mainFrame = nil
local unitFrames = {}                -- [row] -> frame
local isFrameVisible = false
local isDisabled = false
local isUnlocked = false

-- ============================================================================
-- Spell Loading
-- ============================================================================

local function LoadClassSpells()
    trackedSpellIds = {}
    trackedSpellNamesToTextures = {}

    -- Get player class at load time (not file parse time)
    local _, className = UnitClass("player")
    playerClassName = className

    if not playerClassName then
        CleveRoids.Print("MultiTargetTracker: Could not determine player class")
        return false
    end

    local spells = nil
    if playerClassName == "DRUID" then
        spells = getDruidSpells()
    elseif playerClassName == "ROGUE" then
        spells = getRogueSpells()
    elseif playerClassName == "WARRIOR" then
        spells = getWarriorSpells()
    elseif playerClassName == "WARLOCK" then
        spells = getWarlockSpells()
    elseif playerClassName == "HUNTER" then
        spells = getHunterSpells()
    elseif playerClassName == "MAGE" then
        spells = getMageSpells()
    elseif playerClassName == "PRIEST" then
        spells = getPriestSpells()
    elseif playerClassName == "SHAMAN" then
        spells = getShamanSpells()
    elseif playerClassName == "PALADIN" then
        spells = getPaladinSpells()
    end

    if not spells then
        CleveRoids.Print("MultiTargetTracker: No spells defined for class " .. tostring(playerClassName))
        return false
    end

    local spellCount = 0
    for spellID, data in pairs(spells) do
        -- Get texture via SpellInfo
        local name, rank, texture = SpellInfo(spellID)
        data.texture = texture
        trackedSpellIds[spellID] = data
        trackedSpellNamesToTextures[data.name] = texture
        spellCount = spellCount + 1
    end

    return true, spellCount
end

-- ============================================================================
-- GUID Discovery (Cursive core.lua style)
-- ============================================================================

local function AddGuid(guid)
    if not guid or guid == "" or guid == "0x0" or guid == "0x000000000" then
        return
    end
    if string.sub(guid, 1, 2) ~= "0x" then
        return
    end
    if UnitExists(guid) and not UnitIsDead(guid) then
        discoveredGuids[guid] = GetTime()
    end
end

local function AddUnit(unit)
    local _, guid = UnitExists(unit)
    if guid and not UnitIsDead(unit) then
        discoveredGuids[guid] = GetTime()
    end
end

local function RemoveGuid(guid)
    discoveredGuids[guid] = nil
    trackedDebuffs[guid] = nil
end

-- ============================================================================
-- Debuff Scanning
-- ============================================================================

local function ScanGuidForDebuff(guid, spellID)
    if not CleveRoids.hasSuperwow then return false end

    -- Scan debuff slots 1-16
    for slot = 1, 16 do
        local _, _, _, id = UnitDebuff(guid, slot)
        if not id then break end
        if id == spellID then return true end
    end

    -- Scan buff slots (for overflow debuffs) 1-32
    for slot = 1, 32 do
        local _, _, id = UnitBuff(guid, slot)
        if not id then break end
        if id == spellID then return true end
    end

    return false
end

local function ScanGuidForAllDebuffs(guid)
    if not CleveRoids.hasSuperwow then return end
    if not trackedDebuffs[guid] then return end

    for spellName, debuffData in pairs(trackedDebuffs[guid]) do
        if not ScanGuidForDebuff(guid, debuffData.spellID) then
            -- Debuff no longer on target, remove it
            trackedDebuffs[guid][spellName] = nil
        end
    end
end

-- ============================================================================
-- Debuff Application
-- ============================================================================

local function GetDebuffDuration(spellID)
    local spellData = trackedSpellIds[spellID]
    if not spellData then return 0 end

    if spellData.calculateDuration then
        return spellData.calculateDuration()
    end

    return spellData.duration or 0
end

local function ApplyDebuff(spellID, targetGuid, startTime, duration)
    local spellData = trackedSpellIds[spellID]
    if not spellData then return end

    -- Verify debuff is actually on target
    if not ScanGuidForDebuff(targetGuid, spellID) then
        return
    end

    if not trackedDebuffs[targetGuid] then
        trackedDebuffs[targetGuid] = {}
    end

    trackedDebuffs[targetGuid][spellData.name] = {
        spellID = spellID,
        rank = spellData.rank,
        duration = duration,
        start = startTime,
        texture = spellData.texture,
    }

    -- Ensure GUID is in discovery list
    discoveredGuids[targetGuid] = GetTime()
end

local function RemoveDebuff(guid, spellName)
    if trackedDebuffs[guid] and trackedDebuffs[guid][spellName] then
        trackedDebuffs[guid][spellName] = nil
    end
end

local function TimeRemaining(debuffData)
    local remaining = debuffData.duration - (GetTime() - debuffData.start)
    return remaining > 0 and remaining or 0
end

local function HasAnyDebuff(guid)
    if trackedDebuffs[guid] and next(trackedDebuffs[guid]) then
        return true
    end
    return false
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

local eventFrame = CreateFrame("Frame", "CleveRoidsMTTEventFrame", UIParent)

-- GUID Discovery events
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UNIT_COMBAT")
eventFrame:RegisterEvent("UNIT_MODEL_CHANGED")

-- Cast tracking
eventFrame:RegisterEvent("UNIT_CASTEVENT")

-- Resist/immune detection
eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")

-- Fade detection
eventFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")

-- Combo points for finisher tracking
eventFrame:RegisterEvent("PLAYER_COMBO_POINTS")

-- Resist patterns
local resist_pattern = "Your (.+) was resisted by (.+)"
local immune_pattern = "Your (.+) fail.+%. (.+) is immune"
local missed_pattern = "Your (.+) missed (.+)"
local parried_pattern = "Your (.+) is parried by (.+)"
local blocked_pattern = "Your (.+) was blocked by (.+)"
local dodged_pattern = "Your (.+) was dodged by (.+)"

-- Fade pattern
local fades_pattern = "(.+) fades from (.+)"

eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_TARGET_CHANGED" then
        AddUnit("target")

    elseif event == "UNIT_COMBAT" or event == "UNIT_MODEL_CHANGED" then
        -- arg1 is GUID in SuperWoW
        if arg1 then
            AddGuid(arg1)
        end

    elseif event == "UNIT_CASTEVENT" then
        -- UNIT_CASTEVENT args:
        -- arg1 = casterGUID
        -- arg2 = targetGUID
        -- arg3 = event type ("START", "CAST", "FAIL", "CHANNEL")
        -- arg4 = spell ID
        -- arg5 = cast duration

        local casterGuid = arg1
        local targetGuid = arg2
        local eventType = arg3
        local spellID = arg4

        -- Check if caster is player
        local _, playerGuid = UnitExists("player")
        if not playerGuid or casterGuid ~= playerGuid then
            return
        end

        if eventType == "CAST" then
            if trackedSpellIds[spellID] and targetGuid then
                lastTargetGuid = targetGuid

                -- Calculate duration
                local duration = GetDebuffDuration(spellID)

                -- Apply debuff after a short delay to account for travel time
                local delay = 0.2
                local _, _, ping = GetNetStats()
                if ping and ping > 0 and ping < 500 then
                    delay = 0.05 + (ping / 1000)
                end

                -- Store pending cast
                pendingCast = {
                    spellID = spellID,
                    targetGuid = targetGuid,
                    time = GetTime(),
                    duration = duration - delay,
                }

                -- Schedule application
                local applyFrame = CreateFrame("Frame")
                applyFrame.elapsed = 0
                applyFrame:SetScript("OnUpdate", function()
                    this.elapsed = this.elapsed + arg1
                    if this.elapsed >= delay then
                        if pendingCast.spellID == spellID and pendingCast.targetGuid == targetGuid then
                            ApplyDebuff(spellID, targetGuid, GetTime(), pendingCast.duration)
                            pendingCast = {}
                        end
                        this:SetScript("OnUpdate", nil)
                    end
                end)
            end

        elseif eventType == "START" then
            if trackedSpellIds[spellID] and targetGuid then
                pendingCast = {
                    spellID = spellID,
                    targetGuid = targetGuid,
                    time = GetTime(),
                }
            end

        elseif eventType == "FAIL" then
            pendingCast = {}
        end

    elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        local message = arg1

        local patterns = { resist_pattern, immune_pattern }
        -- Add melee patterns for melee classes
        if playerClassName == "DRUID" or playerClassName == "ROGUE" or playerClassName == "WARRIOR" then
            table.insert(patterns, missed_pattern)
            table.insert(patterns, parried_pattern)
            table.insert(patterns, blocked_pattern)
            table.insert(patterns, dodged_pattern)
        end

        for _, pattern in pairs(patterns) do
            local _, _, spellName, target = string.find(message, pattern)
            if spellName and target then
                -- Cancel pending cast
                pendingCast = {}
                return
            end
        end

    elseif event == "CHAT_MSG_SPELL_AURA_GONE_OTHER" then
        local message = arg1
        local _, _, spellName, target = string.find(message, fades_pattern)

        if spellName and target then
            local lowerSpellName = string.lower(spellName)

            -- Check if this is a spell we track
            if trackedSpellNamesToTextures[lowerSpellName] then
                -- Find the GUID for this target and verify
                for guid, debuffs in pairs(trackedDebuffs) do
                    if debuffs[lowerSpellName] then
                        if not ScanGuidForDebuff(guid, debuffs[lowerSpellName].spellID) then
                            RemoveDebuff(guid, lowerSpellName)
                        end
                    end
                end
            end
        end

    elseif event == "PLAYER_COMBO_POINTS" then
        previousComboPoints = currentComboPoints
        currentComboPoints = GetComboPoints()
    end
end)

-- ============================================================================
-- UI Creation
-- ============================================================================

local function GetBarWidth()
    return CONFIG.targetIndicatorSize + CONFIG.raidIconSize + CONFIG.padding +
           CONFIG.healthBarWidth + CONFIG.padding +
           (MAX_DEBUFFS_PER_ROW * (CONFIG.debuffIconSize + CONFIG.debuffIconSpacing))
end

local function FormatHealth(hp)
    if not hp then return "" end
    if hp >= 1000000 then
        return string.format("%.1fm", hp / 1000000)
    elseif hp >= 1000 then
        return string.format("%.1fk", hp / 1000)
    end
    return tostring(hp)
end

local function CreateUnitFrame(parent, index)
    local frame = CreateFrame("Frame", "CleveRoidsMTTRow" .. index, parent)
    frame:SetWidth(GetBarWidth())
    frame:SetHeight(CONFIG.barHeight)
    frame.guid = nil
    frame.hover = false

    -- First section: target indicator + raid icon
    local firstSection = CreateFrame("Frame", nil, frame)
    firstSection:SetPoint("LEFT", frame, "LEFT", 0, 0)
    firstSection:SetWidth(CONFIG.targetIndicatorSize + CONFIG.raidIconSize + CONFIG.padding)
    firstSection:SetHeight(CONFIG.barHeight)
    frame.firstSection = firstSection

    -- Target indicator
    local targetIndicator = firstSection:CreateTexture(nil, "OVERLAY")
    targetIndicator:SetWidth(CONFIG.targetIndicatorSize)
    targetIndicator:SetHeight(8)
    targetIndicator:SetPoint("LEFT", firstSection, "LEFT", 0, 0)
    targetIndicator:SetTexture("Interface\\AddOns\\Cursive\\img\\target-left")
    targetIndicator:Hide()
    frame.targetIndicator = targetIndicator

    -- Raid icon
    local raidIcon = firstSection:CreateTexture(nil, "OVERLAY")
    raidIcon:SetWidth(CONFIG.raidIconSize)
    raidIcon:SetHeight(CONFIG.raidIconSize)
    raidIcon:SetPoint("RIGHT", firstSection, "RIGHT", 0, 0)
    raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidIcon:Hide()
    frame.raidIcon = raidIcon

    -- Second section: health bar (clickable)
    local secondSection = CreateFrame("Button", nil, frame)
    secondSection:SetPoint("LEFT", firstSection, "RIGHT", 0, 0)
    secondSection:SetWidth(CONFIG.healthBarWidth + CONFIG.padding)
    secondSection:SetHeight(CONFIG.barHeight)
    secondSection.parent = frame
    frame.secondSection = secondSection

    -- Click to target
    secondSection:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    secondSection:SetScript("OnClick", function()
        if this.parent.guid then
            if arg1 == "LeftButton" then
                TargetUnit(this.parent.guid)
            elseif arg1 == "RightButton" then
                TargetUnit(this.parent.guid)
                if not PlayerFrame.inCombat then
                    AttackTarget()
                end
            end
        end
    end)

    secondSection:SetScript("OnEnter", function()
        this.parent.hover = true
        if this.parent.healthBar and this.parent.healthBar.border then
            this.parent.healthBar.border:SetBackdropBorderColor(1, 1, 1, 1)
        end
        if this.parent.guid then
            GameTooltip_SetDefaultAnchor(GameTooltip, this)
            GameTooltip:SetUnit(this.parent.guid)
            GameTooltip:Show()
        end
    end)

    secondSection:SetScript("OnLeave", function()
        this.parent.hover = false
        GameTooltip:Hide()
    end)

    -- Health bar
    local healthBar = CreateFrame("StatusBar", nil, secondSection)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetStatusBarColor(COLORS.healthDefault[1], COLORS.healthDefault[2], COLORS.healthDefault[3], 1)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthBar:SetPoint("LEFT", secondSection, "LEFT", CONFIG.padding, 0)
    healthBar:SetWidth(CONFIG.healthBarWidth)
    healthBar:SetHeight(CONFIG.barHeight)
    frame.healthBar = healthBar

    -- Health bar backdrop
    healthBar:SetBackdrop(BACKDROP_BACKGROUND)
    healthBar:SetBackdropColor(0, 0, 0, 1)

    -- Health bar border
    local border = CreateFrame("Frame", nil, healthBar)
    border:SetBackdrop(BACKDROP_BORDER)
    border:SetBackdropBorderColor(COLORS.borderNormal[1], COLORS.borderNormal[2], COLORS.borderNormal[3], 1)
    border:SetPoint("TOPLEFT", healthBar, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 2, -2)
    healthBar.border = border

    -- HP text
    local hpText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    hpText:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", -2, -2)
    hpText:SetFont(STANDARD_TEXT_FONT, CONFIG.textSize, "OUTLINE")
    hpText:SetJustifyH("RIGHT")
    frame.hpText = hpText

    -- Name text
    local nameText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    nameText:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 2, -2)
    nameText:SetPoint("BOTTOMRIGHT", hpText, "BOTTOMLEFT", -2, 0)
    nameText:SetFont(STANDARD_TEXT_FONT, CONFIG.textSize, "OUTLINE")
    nameText:SetJustifyH("LEFT")
    frame.nameText = nameText

    -- Third section: debuff icons
    local thirdSection = CreateFrame("Frame", nil, frame)
    thirdSection:SetPoint("LEFT", secondSection, "RIGHT", 0, 0)
    thirdSection:SetWidth(MAX_DEBUFFS_PER_ROW * (CONFIG.debuffIconSize + CONFIG.debuffIconSpacing))
    thirdSection:SetHeight(CONFIG.barHeight)
    frame.thirdSection = thirdSection

    -- Debuff icons
    frame.debuffIcons = {}
    for i = 1, MAX_DEBUFFS_PER_ROW do
        local icon = thirdSection:CreateTexture(nil, "OVERLAY")
        icon:SetWidth(CONFIG.debuffIconSize)
        icon:SetHeight(CONFIG.debuffIconSize)
        icon:SetPoint("LEFT", thirdSection, "LEFT", (i - 1) * (CONFIG.debuffIconSize + CONFIG.debuffIconSpacing) + CONFIG.padding, 0)
        icon:Hide()

        local timer = thirdSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        timer:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        timer:SetTextColor(1, 1, 1)
        timer:SetAllPoints(icon)
        timer:Hide()
        icon.timer = timer

        frame.debuffIcons[i] = icon
    end

    frame:Hide()
    return frame
end

local function CreateMainFrame()
    local frame = CreateFrame("Frame", "CleveRoidsMultiTargetFrame", UIParent)
    frame:SetWidth(GetBarWidth() + 10)
    frame:SetHeight(CONFIG.titleHeight + (MAX_TRACKED_TARGETS * (CONFIG.barHeight + CONFIG.barSpacing)) + 10)
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, 100)
    frame:SetBackdrop(BACKDROP_BACKGROUND)
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function()
        if isUnlocked then
            this:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        SaveFramePosition()
    end)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -2)
    title:SetFont(STANDARD_TEXT_FONT, CONFIG.textSize, "OUTLINE")
    title:SetText("Debuff Tracker")
    title:SetTextColor(COLORS.titleText[1], COLORS.titleText[2], COLORS.titleText[3], 1)
    frame.titleText = title

    -- Create unit frames
    for i = 1, MAX_TRACKED_TARGETS do
        local unitFrame = CreateUnitFrame(frame, i)
        unitFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -(CONFIG.titleHeight + (i - 1) * (CONFIG.barHeight + CONFIG.barSpacing)))
        unitFrames[i] = unitFrame
    end

    frame:Hide()
    return frame
end

-- ============================================================================
-- Frame Position Saving
-- ============================================================================

local function SaveFramePosition()
    if not mainFrame then return end

    local point, relativeTo, relativePoint, xOfs, yOfs = mainFrame:GetPoint()

    CleveRoidMacros = CleveRoidMacros or {}
    CleveRoidMacros.multiTargetPos = {
        point = point,
        relativePoint = relativePoint,
        x = xOfs,
        y = yOfs,
    }
end

local function RestoreFramePosition()
    if not mainFrame then return end

    CleveRoidMacros = CleveRoidMacros or {}
    local pos = CleveRoidMacros.multiTargetPos

    if pos and pos.point then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    end
end

-- ============================================================================
-- Display Logic (Cursive-style priority)
-- ============================================================================

local function ShouldDisplayGuid(guid)
    if not UnitExists(guid) then return false end
    if UnitIsDead(guid) then return false end
    if not HasAnyDebuff(guid) then return false end
    return true
end

local function GetSortedDebuffs(guidDebuffs)
    local debuffList = {}
    for name, data in pairs(guidDebuffs) do
        table.insert(debuffList, { name = name, data = data })
    end

    -- Sort by time remaining (soonest first)
    table.sort(debuffList, function(a, b)
        return TimeRemaining(a.data) < TimeRemaining(b.data)
    end)

    return debuffList
end

local function UpdateUnitFrame(frame, guid)
    frame.guid = guid

    -- Update health bar
    if frame.healthBar then
        frame.healthBar:SetMinMaxValues(0, UnitHealthMax(guid) or 100)
        frame.healthBar:SetValue(UnitHealth(guid) or 0)
    end

    -- Update name
    local name = UnitName(guid)
    if name and frame.nameText then
        frame.nameText:SetText(name)
    end

    -- Update HP text
    if frame.hpText then
        local hp = UnitHealth(guid)
        frame.hpText:SetText(FormatHealth(hp))
    end

    -- Update border color
    if frame.healthBar and frame.healthBar.border then
        if frame.hover then
            frame.healthBar.border:SetBackdropBorderColor(1, 1, 1, 1)
        elseif UnitAffectingCombat(guid) then
            frame.healthBar.border:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
        else
            frame.healthBar.border:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        end
    end

    -- Update target indicator
    if frame.targetIndicator then
        if UnitIsUnit("target", guid) then
            frame.targetIndicator:Show()
        else
            frame.targetIndicator:Hide()
        end
    end

    -- Update raid icon
    if frame.raidIcon then
        local raidIndex = GetRaidTargetIndex(guid)
        if raidIndex then
            SetRaidTargetIconTexture(frame.raidIcon, raidIndex)
            frame.raidIcon:Show()
        else
            frame.raidIcon:Hide()
        end
    end

    -- Update debuff icons
    for i = 1, MAX_DEBUFFS_PER_ROW do
        frame.debuffIcons[i]:Hide()
        frame.debuffIcons[i].timer:Hide()
    end

    local guidDebuffs = trackedDebuffs[guid]
    if guidDebuffs then
        local sortedDebuffs = GetSortedDebuffs(guidDebuffs)
        for i, debuff in ipairs(sortedDebuffs) do
            if i > MAX_DEBUFFS_PER_ROW then break end

            local icon = frame.debuffIcons[i]
            local remaining = TimeRemaining(debuff.data)

            if remaining > 0 then
                icon:SetTexture(debuff.data.texture)
                icon:Show()

                -- Timer text
                local timerText
                if remaining < 10 then
                    timerText = string.format("%.1f", remaining)
                else
                    timerText = string.format("%d", math.ceil(remaining))
                end
                icon.timer:SetText(timerText)

                -- Timer color
                if remaining < 3 then
                    icon.timer:SetTextColor(1, 0.2, 0.2)
                else
                    icon.timer:SetTextColor(1, 1, 1)
                end
                icon.timer:Show()
            end
        end
    end

    frame:Show()
end

local function UpdateDisplay()
    if isDisabled then return end

    -- Cleanup old/dead GUIDs
    for guid, time in pairs(discoveredGuids) do
        if not UnitExists(guid) or UnitIsDead(guid) then
            RemoveGuid(guid)
        elseif GetTime() - time > 900 and not UnitIsVisible(guid) then
            -- 15 minutes old and not visible
            RemoveGuid(guid)
        end
    end

    -- Collect displayable GUIDs
    local displayable = {}

    -- Priority 1: Raid marked targets
    for i = 8, 1, -1 do
        local _, guid = UnitExists("mark" .. i)
        if guid and ShouldDisplayGuid(guid) then
            table.insert(displayable, guid)
        end
    end

    -- Priority 2: Highest HP targets (top 3)
    local hpTargets = {}
    for guid, _ in pairs(discoveredGuids) do
        if ShouldDisplayGuid(guid) then
            local found = false
            for _, dg in ipairs(displayable) do
                if dg == guid then found = true break end
            end
            if not found then
                table.insert(hpTargets, { guid = guid, hp = UnitHealthMax(guid) or 0 })
            end
        end
    end

    table.sort(hpTargets, function(a, b) return a.hp > b.hp end)

    for i = 1, 3 do
        if hpTargets[i] then
            table.insert(displayable, hpTargets[i].guid)
        end
    end

    -- Priority 3: Remaining targets
    for guid, _ in pairs(discoveredGuids) do
        if table.getn(displayable) >= MAX_TRACKED_TARGETS then break end

        if ShouldDisplayGuid(guid) then
            local found = false
            for _, dg in ipairs(displayable) do
                if dg == guid then found = true break end
            end
            if not found then
                table.insert(displayable, guid)
            end
        end
    end

    -- Update unit frames
    local showFrame = false
    for i = 1, MAX_TRACKED_TARGETS do
        local frame = unitFrames[i]
        local guid = displayable[i]

        if guid then
            UpdateUnitFrame(frame, guid)
            showFrame = true
        else
            frame:Hide()
        end
    end

    -- Show/hide main frame
    if mainFrame then
        if showFrame and not isDisabled then
            if not isFrameVisible then
                mainFrame:Show()
                isFrameVisible = true
            end
        elseif not isUnlocked then
            if isFrameVisible then
                mainFrame:Hide()
                isFrameVisible = false
            end
        end
    end
end

-- ============================================================================
-- Update Loop
-- ============================================================================

local lastUpdate = 0

local function OnUpdate()
    local now = GetTime()
    if now - lastUpdate < UPDATE_INTERVAL then return end
    lastUpdate = now

    UpdateDisplay()
end

-- ============================================================================
-- Extension Load
-- ============================================================================

function Extension.OnLoad()
    if not CleveRoids.hasSuperwow then
        CleveRoids.Print("MultiTargetTracker: SuperWoW required, extension disabled")
        return
    end

    -- Load class spells
    local success, spellCount = LoadClassSpells()
    if not success then
        CleveRoids.Print("MultiTargetTracker: Failed to load spells, extension disabled")
        return
    end

    -- Create main frame
    mainFrame = CreateMainFrame()

    -- Restore position
    RestoreFramePosition()

    -- Restore hidden state
    CleveRoidMacros = CleveRoidMacros or {}
    if CleveRoidMacros.multiTargetHidden then
        isDisabled = true
        mainFrame:Hide()
        isFrameVisible = false
    end

    -- Start update loop
    mainFrame:SetScript("OnUpdate", function()
        OnUpdate()
    end)

    CleveRoids.Print("Multi-Target Tracker loaded for " .. playerClassName .. " (" .. spellCount .. " spells). Use /cleveroid mtt for commands.")
end

-- ============================================================================
-- API Export
-- ============================================================================

CleveRoids.MultiTargetTracker = {
    Show = function()
        if mainFrame then
            mainFrame:Show()
            isFrameVisible = true
            isDisabled = false
            CleveRoidMacros = CleveRoidMacros or {}
            CleveRoidMacros.multiTargetHidden = nil
        end
    end,

    Hide = function()
        if mainFrame then
            mainFrame:Hide()
            isFrameVisible = false
            isDisabled = true
            CleveRoidMacros = CleveRoidMacros or {}
            CleveRoidMacros.multiTargetHidden = true
        end
    end,

    Toggle = function()
        if mainFrame then
            if isDisabled then
                CleveRoids.MultiTargetTracker.Show()
            else
                CleveRoids.MultiTargetTracker.Hide()
            end
        end
    end,

    IsVisible = function()
        return isFrameVisible
    end,

    IsDisabled = function()
        return isDisabled
    end,

    Unlock = function()
        isUnlocked = true
        if mainFrame then
            mainFrame:Show()
            isFrameVisible = true
            if mainFrame.titleText then
                mainFrame.titleText:SetText("Debuff Tracker (UNLOCKED)")
                mainFrame.titleText:SetTextColor(0, 1, 0, 1)
            end
        end
        CleveRoids.Print("Multi-Target Tracker: Unlocked - drag to move")
    end,

    Lock = function()
        isUnlocked = false
        if mainFrame and mainFrame.titleText then
            mainFrame.titleText:SetText("Debuff Tracker")
            mainFrame.titleText:SetTextColor(COLORS.titleText[1], COLORS.titleText[2], COLORS.titleText[3], 1)
        end
        SaveFramePosition()
        CleveRoids.Print("Multi-Target Tracker: Locked")
    end,

    ResetPosition = function()
        CleveRoidMacros = CleveRoidMacros or {}
        CleveRoidMacros.multiTargetPos = nil
        if mainFrame then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 100)
        end
        CleveRoids.Print("Multi-Target Tracker: Position reset")
    end,

    ClearTargets = function()
        discoveredGuids = {}
        trackedDebuffs = {}
        CleveRoids.Print("Multi-Target Tracker: Cleared all targets")
    end,
}

_G["CleveRoids"] = CleveRoids
