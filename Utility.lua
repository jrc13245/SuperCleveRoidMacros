--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
local _G = getfenv(0)
local strfind = string.find
local find = string.find  -- Add this line
local gsub = string.gsub
local lower = string.lower
local floor = math.floor
local pairs = pairs
local ipairs = ipairs
local type = type
local tonumber = tonumber
local tostring = tostring
local GetTime = GetTime

-- GUID normalization: ensure all GUIDs are strings for consistent table key lookups
-- In Lua, table["123"] is different from table[123], so we must normalize
function CleveRoids.NormalizeGUID(guid)
    if not guid then return nil end
    return tostring(guid)
end

if type(hooksecurefunc) ~= "function" then
  function hooksecurefunc(arg1, arg2, arg3)
    local tgt, fname, post

    if type(arg1) == "string" and type(arg2) == "function" and arg3 == nil then
      fname, post = arg1, arg2
      local orig = _G[fname]
      if type(orig) ~= "function" then return end
      _G[fname] = function(...)
        local args = arg or {}
        local n = (type(args) == "table" and args.n) or 0
        local r = { orig(unpack(args, 1, n)) }
        post(unpack(args, 1, n))
        return unpack(r, 1, table.getn(r))
      end
      return
    end

    if type(arg1) == "table" and type(arg2) == "string" and type(arg3) == "function" then
      tgt, fname, post = arg1, arg2, arg3
      local orig = tgt[fname]
      if type(orig) ~= "function" then return end
      tgt[fname] = function(...)
        local args = arg or {}
        local n = (type(args) == "table" and args.n) or 0
        local r = { orig(unpack(args, 1, n)) }
        post(unpack(args, 1, n))
        return unpack(r, 1, table.getn(r))
      end
      return
    end
  end
end

if type(string.match) ~= "function" then
  function string.match(s, pattern, init)
    if s == nil or pattern == nil then return nil end
    local i, j, c1, c2, c3, c4, c5 = string.find(s, pattern, init)
    if not i then return nil end
    if c1 ~= nil then return c1, c2, c3, c4, c5 end
    return string.sub(s, i, j)
  end
end

if type(string.gmatch) ~= "function" then
  function string.gmatch(s, pattern)
    local pos = 1
    return function()
      if s == nil or pattern == nil then return nil end
      local i, j, c1, c2, c3, c4, c5 = string.find(s, pattern, pos)
      if not i then return nil end
      pos = j + 1
      if c1 ~= nil then return c1, c2, c3, c4, c5 end
      return string.sub(s, i, j)
    end
  end
end

function CleveRoids.Seq(_, i)
    return (i or 0) + 1
end

function CleveRoids.Trim(str)
    if not str then
        return nil
    end
    return string.gsub(str,"^%s*(.-)%s*$", "%1")
end

do
  local _G = _G or getfenv(0)
  local CleveRoids = _G.CleveRoids or {}
  _G.CleveRoids = CleveRoids

  CleveRoids.__mo = CleveRoids.__mo or { sources = {}, current = nil }

  local PRIORITY = {
    pfui    = 3,
    blizz   = 3,
    tooltip = 1,
  }

  local function getBest()
    local bestSource, bestUnit, bestP = nil, nil, -1
    for source, unit in CleveRoids.__mo.sources do
      if unit and unit ~= "" then
        local p = PRIORITY[source] or 0
        if p > bestP then
          bestP, bestSource, bestUnit = p, source, unit
        end
      end
    end
    return bestSource, bestUnit
  end

  local function apply(unit)
    if CleveRoids.hasSuperwow and _G.SetMouseoverUnit then
      _G.SetMouseoverUnit(unit)
    else
      CleveRoids.mouseoverUnit = unit
    end
    if CleveRoids.QueueActionUpdate then CleveRoids.QueueActionUpdate() end
  end

  function CleveRoids.SetMouseoverFrom(source, unit)
    if not source then return end
    CleveRoids.__mo.sources[source] = unit
    local _, bestUnit = getBest()
    if bestUnit ~= CleveRoids.__mo.current then
      CleveRoids.__mo.current = bestUnit
      apply(bestUnit)
    end
  end

  function CleveRoids.ClearMouseoverFrom(source, unitIfMatch)
    if not source then return end
    if unitIfMatch and CleveRoids.__mo.sources[source] ~= unitIfMatch then
      return
    end
    CleveRoids.__mo.sources[source] = nil
    local _, bestUnit = getBest()
    if bestUnit ~= CleveRoids.__mo.current then
      CleveRoids.__mo.current = bestUnit
      apply(bestUnit)
    end
  end
end

-- TODO: Get rid of one Split function.  CleveRoids.splitString is ~10% slower
function CleveRoids.Split(s, p, trim)
    local r, o = {}, 1

    if not p or p == "" then
        if trim then
            s = CleveRoids.Trim(s)
        end
        for i = 1, string.len(s) do
            table.insert(r, string.sub(s, i, 1))
        end
        return r
    end

    repeat
        local b, e = string.find(s, p, o)
        if b == nil then
            local sub = string.sub(s, o)
            table.insert(r, trim and CleveRoids.Trim(sub) or sub)
            return r
        end
        if b > 1 then
            local sub = string.sub(s, o, b - 1)
            table.insert(r, trim and CleveRoids.Trim(sub) or sub)
        else
            table.insert(r, "")
        end
        o = e + 1
    until false
end

function CleveRoids.splitString(str, seperatorPattern)
    local tbl = {}
    if not str then
        return tbl
    end
    local pattern = "(.-)" .. seperatorPattern
    local lastEnd = 1
    local s, e, cap = string.find(str, pattern, 1)

    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(tbl,cap)
        end
        lastEnd = e + 1
        s, e, cap = string.find(str, pattern, lastEnd)
    end

    if lastEnd <= string.len(str) then
        cap = string.sub(str, lastEnd)
        table.insert(tbl, cap)
    end

    return tbl
end

function CleveRoids.splitStringIgnoringQuotes(str, separator)
    local result = {}
    local temp = ""
    local insideQuotes = false
    local separators = {}

    if type(separator) == "table" then
        for _, s in separator do
            separators[s] = s
        end
    else
        separators[separator or ";"] = separator or ";"
    end

    for i = 1, string.len(str) do
        local char = string.sub(str, i, i)

        if char == "\"" then
            insideQuotes = not insideQuotes
            temp = temp .. char
        elseif char == separators[char] and not insideQuotes then
            temp = CleveRoids.Trim(temp)
            if temp ~= "" then table.insert(result, temp) end
            temp = ""
        else
            temp = temp .. char
        end
    end

    if temp ~= "" then
        temp = CleveRoids.Trim(temp)
        table.insert(result, temp)
    end

    return (next(result) and result or {""})
end

function CleveRoids.Print(...)
    local c = "|cFF4477FFCleveR|r|cFFFFFFFFoid :: |r"
    local out = ""

    for i=1, arg.n, 1 do
        out = out..tostring(arg[i]).."  "
    end
    if WowLuaFrameOutput then
        WowLuaFrameOutput:AddMessage(out)
    else
        if not DEFAULT_CHAT_FRAME:IsVisible() then
            FCF_SelectDockFrame(DEFAULT_CHAT_FRAME)
        end
        DEFAULT_CHAT_FRAME:AddMessage(c..out)
    end
end

function CleveRoids.PrintI(msg, depth)
    depth = depth or 0
    msg = string.rep("    ", depth) .. tostring(msg)
    CleveRoids.Print(msg)
end

function CleveRoids.PrintT(t, depth)
    depth = depth or 0
    local cs = "|cffc8c864"
    local ce = "|r"

    if t == nil or type(t) ~= "table" then
        CleveRoids.PrintI(t, depth)
    else
        for k, v in pairs(t) do
            if type(v) == "table" then
                CleveRoids.PrintI(cs..tostring(k)..":"..ce.." <TABLE>", depth)
                CleveRoids.PrintT(v, depth + 1)
            else
                CleveRoids.PrintI(cs..tostring(k)..ce..": "..tostring(v), depth)
            end
        end
    end
end

CleveRoids.kmods = {
    ctrl  = IsControlKeyDown,
    alt   = IsAltKeyDown,
    shift = IsShiftKeyDown,
    mod   = function() return (IsControlKeyDown() or IsAltKeyDown() or IsShiftKeyDown()) end,
    nomod = function() return (not IsControlKeyDown() and not IsAltKeyDown() and not IsShiftKeyDown()) end,
}

CleveRoids.operators = {
    ["<"] = "lt",
    ["lt"] = "<",
    [">"] = "gt",
    ["gt"] = ">",
    ["="] = "eq",
    ["eq"] = "=",
    ["<="] = "lte",
    ["lte"] = "<=",
    [">="] = "gte",
    ["gte"] = ">=",
    ["~="] = "ne",
    ["ne"] = "~=",
}

CleveRoids.comparators = {
    lt  = function(a, b) return (a <  b) end,
    gt  = function(a, b) return (a >  b) end,
    eq  = function(a, b) return (a == b) end,
    lte = function(a, b) return (a <= b) end,
    gte = function(a, b) return (a >= b) end,
    ne  = function(a, b) return (a ~= b) end,
}
CleveRoids.comparators["<"]  = CleveRoids.comparators.lt
CleveRoids.comparators[">"]  = CleveRoids.comparators.gt
CleveRoids.comparators["="]  = CleveRoids.comparators.eq
CleveRoids.comparators["<="] = CleveRoids.comparators.lte
CleveRoids.comparators[">="] = CleveRoids.comparators.gte
CleveRoids.comparators["~="] = CleveRoids.comparators.ne


_G["CleveRoids"] = CleveRoids

local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids

CleveRoids.libdebuff = CleveRoids.libdebuff or {}
local lib = CleveRoids.libdebuff

lib.objects = lib.objects or {}
lib.guidToName = lib.guidToName or {}

-- PERSONAL DEBUFFS: Each player can have their own instance of these debuffs on the same target
-- These are DoTs, poisons, stings, and most CC effects
lib.personalDebuffs = lib.personalDebuffs or {
  -- WARRIOR
  [772] = 9,      -- Rend (Rank 1)
  [6546] = 12,    -- Rend (Rank 2)
  [6547] = 15,    -- Rend (Rank 3)
  [6548] = 18,    -- Rend (Rank 4)
  [11572] = 21,   -- Rend (Rank 5)
  [11573] = 21,   -- Rend (Rank 6)
  [11574] = 21,   -- Rend (Rank 7)

  [7372] = 15,    -- Hamstring (Rank 1)
  [7373] = 15,    -- Hamstring (Rank 2)
  [1715] = 15,    -- Hamstring (Rank 3)

  [12323] = 6,    -- Piercing Howl

  -- ROGUE
  [2094] = 10,    -- Blind
  [21060] = 10,   -- Blind (alternate?)

  [6770] = 25,    -- Sap (Rank 1)
  [2070] = 35,    -- Sap (Rank 2)
  [11297] = 45,   -- Sap (Rank 3)

  [1776] = 4,     -- Gouge (Rank 1) - Scales with talent
  [1777] = 4,     -- Gouge (Rank 2)
  [8629] = 4,     -- Gouge (Rank 3)
  [11285] = 4,    -- Gouge (Rank 4)
  [11286] = 4,    -- Gouge (Rank 5)

  -- NOTE: Rupture removed - handled by ComboPointTracker (base 8s + 2s per CP)
  -- NOTE: Kidney Shot removed - handled by ComboPointTracker (base 1s/2s + 1s per CP)

  [703] = 18,     -- Garrote (Rank 1)
  [8631] = 18,    -- Garrote (Rank 2)
  [8632] = 18,    -- Garrote (Rank 3)
  [8633] = 18,    -- Garrote (Rank 4)
  [11289] = 18,   -- Garrote (Rank 5)
  [11290] = 18,   -- Garrote (Rank 6)

  [2818] = 12,    -- Deadly Poison (Rank 1)
  [2819] = 12,    -- Deadly Poison II (Rank 2)
  [11353] = 12,   -- Deadly Poison III (Rank 3)
  [11354] = 12,   -- Deadly Poison IV (Rank 4)
  [25349] = 12,   -- Deadly Poison V (Rank 5)

  [16511] = 15,   -- Hemorrhage

  [1833] = 4,     -- Cheap Shot
  [14902] = 4,    -- Cheap Shot (alternate?)

  -- Rogue poisons (not in Cursive, estimates):
  [3409] = 12,    -- Crippling Poison
  [5760] = 16,    -- Mind-numbing Poison (Rank 1)
  [8694] = 16,    -- Mind-numbing Poison (Rank 2)
  [11399] = 16,   -- Mind-numbing Poison (Rank 3)
  [13218] = 15,   -- Wound Poison (Rank 1)
  [13222] = 15,   -- Wound Poison (Rank 2)
  [13223] = 15,   -- Wound Poison (Rank 3)
  [13224] = 15,   -- Wound Poison (Rank 4)

  -- HUNTER
  [3043] = 20,    -- Scorpid Sting (Rank 1)
  [14275] = 20,   -- Scorpid Sting (Rank 2)
  [14276] = 20,   -- Scorpid Sting (Rank 3)
  [14277] = 20,   -- Scorpid Sting (Rank 4)

  [1978] = 15,    -- Serpent Sting (Rank 1)
  [13549] = 15,   -- Serpent Sting (Rank 2)
  [13550] = 15,   -- Serpent Sting (Rank 3)
  [13551] = 15,   -- Serpent Sting (Rank 4)
  [13552] = 15,   -- Serpent Sting (Rank 5)
  [13553] = 15,   -- Serpent Sting (Rank 6)
  [13554] = 15,   -- Serpent Sting (Rank 7)
  [13555] = 15,   -- Serpent Sting (Rank 8)
  [25295] = 15,   -- Serpent Sting (Rank 9)

  [3034] = 8,     -- Viper Sting (Rank 1)
  [14279] = 8,    -- Viper Sting (Rank 2)
  [14280] = 8,    -- Viper Sting (Rank 3)

  [2974] = 10,    -- Wing Clip (Rank 1)
  [14267] = 10,   -- Wing Clip (Rank 2)
  [14268] = 10,   -- Wing Clip (Rank 3)

  [5116] = 4,     -- Concussive Shot

  [19386] = 12,   -- Wyvern Sting (Rank 1)
  [24132] = 12,   -- Wyvern Sting (Rank 2)
  [24133] = 12,   -- Wyvern Sting (Rank 3)

  [19306] = 5,    -- Counterattack (Rank 1)
  [20909] = 5,    -- Counterattack (Rank 2)
  [20910] = 5,    -- Counterattack (Rank 3)

  [1130] = 120,   -- Hunter's Mark (Rank 1)
  [14323] = 120,  -- Hunter's Mark (Rank 2)
  [14324] = 120,  -- Hunter's Mark (Rank 3)
  [14325] = 120,  -- Hunter's Mark (Rank 4)

  -- DRUID
  [339] = 12,     -- Entangling Roots (Rank 1)
  [1062] = 15,    -- Entangling Roots (Rank 2)
  [5195] = 18,    -- Entangling Roots (Rank 3)
  [5196] = 21,    -- Entangling Roots (Rank 4)
  [9852] = 24,    -- Entangling Roots (Rank 5)
  [9853] = 27,    -- Entangling Roots (Rank 6)

  [700] = 20,     -- Sleep (Rank 1)
  [1090] = 30,    -- Sleep (Rank 2)
  [2937] = 40,    -- Sleep (Rank 3)

  [770] = 40,     -- Faerie Fire (Rank 1)
  [778] = 40,     -- Faerie Fire (Rank 2)
  [9749] = 40,    -- Faerie Fire (Rank 3)
  [9907] = 40,    -- Faerie Fire (Rank 4)

  [16855] = 40,   -- Faerie Fire (Bear) (Rank 1)
  [17387] = 40,   -- Faerie Fire (Bear) (Rank 2)
  [17388] = 40,   -- Faerie Fire (Bear) (Rank 3)
  [17389] = 40,   -- Faerie Fire (Bear) (Rank 4)

  [16857] = 40,   -- Faerie Fire (Feral) (Rank 1)
  [17390] = 40,   -- Faerie Fire (Feral) (Rank 2)
  [17391] = 40,   -- Faerie Fire (Feral) (Rank 3)
  [17392] = 40,   -- Faerie Fire (Feral) (Rank 4)

  [2637] = 20,    -- Hibernate (Rank 1)
  [18657] = 30,   -- Hibernate (Rank 2)
  [18658] = 40,   -- Hibernate (Rank 3)

  [5570] = 18,    -- Insect Swarm (Rank 1)
  [24974] = 18,   -- Insect Swarm (Rank 2)
  [24975] = 18,   -- Insect Swarm (Rank 3)
  [24976] = 18,   -- Insect Swarm (Rank 4)
  [24977] = 18,   -- Insect Swarm (Rank 5)

  [8921] = 9,     -- Moonfire (Rank 1)
  [8924] = 18,    -- Moonfire (Rank 2)
  [8925] = 18,    -- Moonfire (Rank 3)
  [8926] = 18,    -- Moonfire (Rank 4)
  [8927] = 18,    -- Moonfire (Rank 5)
  [8928] = 18,    -- Moonfire (Rank 6)
  [8929] = 18,    -- Moonfire (Rank 7)
  [9833] = 18,    -- Moonfire (Rank 8)
  [9834] = 18,    -- Moonfire (Rank 9)
  [9835] = 18,    -- Moonfire (Rank 10)

  [1822] = 9,     -- Rake (Rank 1)
  [1823] = 9,     -- Rake (Rank 2)
  [1824] = 9,     -- Rake (Rank 3)
  [9904] = 9,     -- Rake (Rank 4)

  -- NOTE: Rip is a combo-scaling personal debuff (base 10s + 2s per CP)
  [1079] = 10,    -- Rip (Rank 1)
  [9492] = 10,    -- Rip (Rank 2)
  [9493] = 10,    -- Rip (Rank 3)
  [9752] = 10,    -- Rip (Rank 4)
  [9894] = 10,    -- Rip (Rank 5)
  [9896] = 10,    -- Rip (Rank 6)

  [2908] = 15,    -- Soothe Animal (Rank 1)
  [8955] = 15,    -- Soothe Animal (Rank 2)
  [9901] = 15,    -- Soothe Animal (Rank 3)

  [5211] = 2,     -- Bash (Rank 1)
  [6798] = 3,     -- Bash (Rank 2)
  [8983] = 4,     -- Bash (Rank 3)

  [9005] = 18,    -- Pounce Bleed (Rank 1)
  [9823] = 18,    -- Pounce Bleed (Rank 2)
  [9827] = 18,    -- Pounce Bleed (Rank 3)

  -- WARLOCK
  [172] = 12,     -- Corruption (Rank 1)
  [6222] = 15,    -- Corruption (Rank 2)
  [6223] = 18,    -- Corruption (Rank 3)
  [7648] = 18,    -- Corruption (Rank 4)
  [11671] = 18,   -- Corruption (Rank 5)
  [11672] = 18,   -- Corruption (Rank 6)
  [25311] = 18,   -- Corruption (Rank 7)

  [980] = 24,     -- Curse of Agony (Rank 1)
  [1014] = 24,    -- Curse of Agony (Rank 2)
  [6217] = 24,    -- Curse of Agony (Rank 3)
  [11711] = 24,   -- Curse of Agony (Rank 4)
  [11712] = 24,   -- Curse of Agony (Rank 5)
  [11713] = 24,   -- Curse of Agony (Rank 6)

  [18265] = 30,   -- Siphon Life (Rank 1)
  [18879] = 30,   -- Siphon Life (Rank 2)
  [18880] = 30,   -- Siphon Life (Rank 3)
  [18881] = 30,   -- Siphon Life (Rank 4)

  [52550] = 8,    -- Dark Harvest (Rank 1)
  [52551] = 8,    -- Dark Harvest (Rank 2)
  [52552] = 8,    -- Dark Harvest (Rank 3)

  [603] = 60,     -- Curse of Doom

  [704] = 120,    -- Curse of Recklessness (Rank 1)
  [7658] = 120,   -- Curse of Recklessness (Rank 2)
  [7659] = 120,   -- Curse of Recklessness (Rank 3)
  [11717] = 120,  -- Curse of Recklessness (Rank 4)

  [17862] = 300,  -- Curse of Shadow (Rank 1)
  [17937] = 300,  -- Curse of Shadow (Rank 2)

  [1490] = 300,   -- Curse of Elements (Rank 1)
  [11721] = 300,  -- Curse of Elements (Rank 2)
  [11722] = 300,  -- Curse of Elements (Rank 3)

  [1714] = 30,    -- Curse of Tongues (Rank 1)
  [11719] = 30,   -- Curse of Tongues (Rank 2)

  [702] = 120,    -- Curse of Weakness (Rank 1)
  [1108] = 120,   -- Curse of Weakness (Rank 2)
  [6205] = 120,   -- Curse of Weakness (Rank 3)
  [7646] = 120,   -- Curse of Weakness (Rank 4)
  [11707] = 120,  -- Curse of Weakness (Rank 5)
  [11708] = 120,  -- Curse of Weakness (Rank 6)

  [18223] = 12,   -- Curse of Exhaustion

  [348] = 15,     -- Immolate (Rank 1)
  [707] = 15,     -- Immolate (Rank 2)
  [1094] = 15,    -- Immolate (Rank 3)
  [2941] = 15,    -- Immolate (Rank 4)
  [11665] = 15,   -- Immolate (Rank 5)
  [11667] = 15,   -- Immolate (Rank 6)
  [11668] = 15,   -- Immolate (Rank 7)
  [25309] = 15,   -- Immolate (Rank 8)

  [6789] = 3,     -- Death Coil (Rank 1)
  [17925] = 3,    -- Death Coil (Rank 2)
  [17926] = 3,    -- Death Coil (Rank 3)

  [710] = 20,     -- Banish (Rank 1)
  [18647] = 30,   -- Banish (Rank 2)

  [5782] = 10,    -- Fear (Rank 1)
  [6213] = 15,    -- Fear (Rank 2)
  [6215] = 20,    -- Fear (Rank 3)

  -- MAGE
  [118] = 20,     -- Polymorph (Rank 1)
  [12824] = 30,   -- Polymorph (Rank 2)
  [12825] = 40,   -- Polymorph (Rank 3)
  [12826] = 50,   -- Polymorph (Rank 4)

  [28270] = 50,   -- Polymorph: Cow
  [28271] = 50,   -- Polymorph: Turtle
  [28272] = 50,   -- Polymorph: Pig

  [116] = 5,      -- Frostbolt slow
  [120] = 5,      -- Cone of Cold slow
  [6136] = 15,    -- Chilled
  [12484] = 15,   -- Improved Blizzard slow
  [12486] = 15,   -- Blizzard slow

  -- PRIEST
  [1425] = 30,    -- Shackle Undead (Rank 1)
  [9486] = 40,    -- Shackle Undead (Rank 2)
  [10956] = 50,   -- Shackle Undead (Rank 3)

  [453] = 15,     -- Mind Soothe (Rank 1)
  [8192] = 15,    -- Mind Soothe (Rank 2)
  [10953] = 15,   -- Mind Soothe (Rank 3)

  [605] = 60,     -- Mind Control (Rank 1)
  [10911] = 30,   -- Mind Control (Rank 2)
  [10912] = 30,   -- Mind Control (Rank 3)

  [2944] = 24,    -- Devouring Plague (Rank 1)
  [19276] = 24,   -- Devouring Plague (Rank 2)
  [19277] = 24,   -- Devouring Plague (Rank 3)
  [19278] = 24,   -- Devouring Plague (Rank 4)
  [19279] = 24,   -- Devouring Plague (Rank 5)
  [19280] = 24,   -- Devouring Plague (Rank 6)

  [9035] = 120,   -- Hex of Weakness (Rank 1)
  [19281] = 120,  -- Hex of Weakness (Rank 2)
  [19282] = 120,  -- Hex of Weakness (Rank 3)
  [19283] = 120,  -- Hex of Weakness (Rank 4)
  [19284] = 120,  -- Hex of Weakness (Rank 5)
  [19285] = 120,  -- Hex of Weakness (Rank 6)

  [589] = 18,     -- Shadow Word: Pain (Rank 1)
  [594] = 18,     -- Shadow Word: Pain (Rank 2)
  [970] = 18,     -- Shadow Word: Pain (Rank 3)
  [992] = 18,     -- Shadow Word: Pain (Rank 4)
  [2767] = 18,    -- Shadow Word: Pain (Rank 5)
  [10892] = 18,   -- Shadow Word: Pain (Rank 6)
  [10893] = 18,   -- Shadow Word: Pain (Rank 7)
  [10894] = 18,   -- Shadow Word: Pain (Rank 8)

  [15286] = 60,   -- Vampiric Embrace

  [14914] = 10,   -- Holy Fire (Rank 1)
  [15262] = 10,   -- Holy Fire (Rank 2)
  [15263] = 10,   -- Holy Fire (Rank 3)
  [15264] = 10,   -- Holy Fire (Rank 4)
  [15265] = 10,   -- Holy Fire (Rank 5)
  [15266] = 10,   -- Holy Fire (Rank 6)
  [15267] = 10,   -- Holy Fire (Rank 7)
  [15261] = 10,   -- Holy Fire (Rank 8)

  -- Mind Flay
  [15407] = 3,    -- Mind Flay (Rank 1)
  [17311] = 3,    -- Mind Flay (Rank 2)
  [17312] = 3,    -- Mind Flay (Rank 3)
  [17313] = 3,    -- Mind Flay (Rank 4)
  [17314] = 3,    -- Mind Flay (Rank 5)
  [18807] = 3,    -- Mind Flay (Rank 6)

  -- PALADIN
  [853] = 6,      -- Hammer of Justice (Rank 1)
  [5588] = 6,     -- Hammer of Justice (Rank 2)
  [5589] = 6,     -- Hammer of Justice (Rank 3)
  [10308] = 6,    -- Hammer of Justice (Rank 4)

  [20184] = 10,   -- Judgement of Justice
  [20185] = 10,   -- Judgement of Light (Rank 1)
  [20267] = 10,   -- Judgement of Light (Rank 2)
  [20268] = 10,   -- Judgement of Light (Rank 3)
  [20271] = 10,   -- Judgement of Light (Rank 4)
  [20186] = 10,   -- Judgement of Wisdom (Rank 1)
  [20354] = 10,   -- Judgement of Wisdom (Rank 2)
  [20355] = 10,   -- Judgement of Wisdom (Rank 3)
  [21183] = 10,   -- Judgement of the Crusader (Rank 1)
  [20183] = 10,   -- Judgement of the Crusader (Rank 2)
  [20300] = 10,   -- Judgement of the Crusader (Rank 3)
  [20301] = 10,   -- Judgement of the Crusader (Rank 4)
  [20302] = 10,   -- Judgement of the Crusader (Rank 5)
  [20303] = 10,   -- Judgement of the Crusader (Rank 6)

  -- SHAMAN
  [8050] = 12,    -- Flame Shock (Rank 1)
  [8052] = 12,    -- Flame Shock (Rank 2)
  [8053] = 12,    -- Flame Shock (Rank 3)
  [10447] = 12,   -- Flame Shock (Rank 4)
  [10448] = 12,   -- Flame Shock (Rank 5)
  [29228] = 12,   -- Flame Shock (Rank 6)

  -- Frost Shock
  [8056] = 8,     -- Frost Shock (Rank 1)
  [8058] = 8,     -- Frost Shock (Rank 2)
  [10472] = 8,    -- Frost Shock (Rank 3)
  [10473] = 8,    -- Frost Shock (Rank 4)
}

-- SHARED DEBUFFS: Only one instance exists on a target, shared/refreshed by all players
-- These are armor reductions, attack power reductions, and marks
lib.sharedDebuffs = lib.sharedDebuffs or {
  -- WARRIOR
  [7386] = 30,    -- Sunder Armor (Rank 1)
  [7405] = 30,    -- Sunder Armor (Rank 2)
  [8380] = 30,    -- Sunder Armor (Rank 3)
  [8647] = 30,    -- Sunder Armor (Rank 4)
  [11597] = 30,   -- Sunder Armor (Rank 5)

  [6343] = 10,    -- Thunder Clap (Rank 1)
  [8198] = 10,    -- Thunder Clap (Rank 2)
  [8205] = 10,    -- Thunder Clap (Rank 3)
  [11580] = 10,   -- Thunder Clap (Rank 4)
  [11581] = 10,   -- Thunder Clap (Rank 5)

  [1160] = 30,    -- Demoralizing Shout (Rank 1)
  [6190] = 30,    -- Demoralizing Shout (Rank 2)
  [11554] = 30,   -- Demoralizing Shout (Rank 3)
  [11555] = 30,   -- Demoralizing Shout (Rank 4)
  [11556] = 30,   -- Demoralizing Shout (Rank 5)

  -- ROGUE
  [8647] = 30,    -- Expose Armor (Rank 1)
  [8649] = 30,    -- Expose Armor (Rank 2)
  [8650] = 30,    -- Expose Armor (Rank 3)
  [11197] = 30,   -- Expose Armor (Rank 4)
  [11198] = 30,   -- Expose Armor (Rank 5)

  -- HUNTER
  [1130] = 120,   -- Hunter's Mark (Rank 1)
  [14323] = 120,  -- Hunter's Mark (Rank 2)
  [14324] = 120,  -- Hunter's Mark (Rank 3)
  [14325] = 120,  -- Hunter's Mark (Rank 4)

  -- DRUID
  [770] = 40,     -- Faerie Fire (Rank 1)
  [778] = 40,     -- Faerie Fire (Rank 2)
  [9749] = 40,    -- Faerie Fire (Rank 3)
  [9907] = 40,    -- Faerie Fire (Rank 4)

  [16855] = 40,   -- Faerie Fire (Bear) (Rank 1)
  [17387] = 40,   -- Faerie Fire (Bear) (Rank 2)
  [17388] = 40,   -- Faerie Fire (Bear) (Rank 3)
  [17389] = 40,   -- Faerie Fire (Bear) (Rank 4)

  [16857] = 40,   -- Faerie Fire (Feral) (Rank 1)
  [17390] = 40,   -- Faerie Fire (Feral) (Rank 2)
  [17391] = 40,   -- Faerie Fire (Feral) (Rank 3)
  [17392] = 40,   -- Faerie Fire (Feral) (Rank 4)

  [99] = 30,      -- Demoralizing Roar (Rank 1)
  [1735] = 30,    -- Demoralizing Roar (Rank 2)
  [9490] = 30,    -- Demoralizing Roar (Rank 3)
  [9747] = 30,    -- Demoralizing Roar (Rank 4)
  [9898] = 30,    -- Demoralizing Roar (Rank 5)

  [5209] = 6,     -- Challenging Roar
}

-- Combined table for backwards compatibility (will be deprecated)
lib.durations = lib.durations or {}
for k, v in pairs(lib.personalDebuffs) do
  lib.durations[k] = v
end
for k, v in pairs(lib.sharedDebuffs) do
  lib.durations[k] = v
end

-- Helper function to check if a debuff is personal (returns true) or shared (returns false)
function lib:IsPersonalDebuff(spellID)
  if lib.personalDebuffs[spellID] then
    return true
  elseif lib.sharedDebuffs[spellID] then
    return false
  end
  -- Unknown debuffs are treated as personal by default (safer for multi-player scenarios)
  return true
end

lib.learnCastTimers = lib.learnCastTimers or {}

CleveRoids_LearnedDurations = CleveRoids_LearnedDurations or {}

function lib:GetDuration(spellID, casterGUID, comboPoints)
  -- Check combo-specific learned durations first if this is a combo spell
  if comboPoints and CleveRoids_ComboDurations and CleveRoids_ComboDurations[spellID] then
    local comboDuration = CleveRoids_ComboDurations[spellID][comboPoints]
    if comboDuration and comboDuration > 0 then
      if CleveRoids.debug then
        local spellName = SpellInfo(spellID) or "Unknown"
        DEFAULT_CHAT_FRAME:AddMessage(
          string.format("|cffccccff[DEBUG GetDuration]|r %s (ID:%d) CP:%d -> %ds (from learned combo)",
            spellName, spellID, comboPoints, comboDuration)
        )
      end
      return comboDuration
    end
  end

  -- Check caster-specific learned durations
  if casterGUID and CleveRoids_LearnedDurations[spellID] then
    local learned = CleveRoids_LearnedDurations[spellID][casterGUID]
    if learned and learned > 0 then
      if CleveRoids.debug then
        local spellName = SpellInfo(spellID) or "Unknown"
        DEFAULT_CHAT_FRAME:AddMessage(
          string.format("|cffccccff[DEBUG GetDuration]|r %s (ID:%d) -> %ds (from learned caster)",
            spellName, spellID, learned)
        )
      end
      return learned
    end
  end

  -- Fall back to static database
  local staticDur = self.durations[spellID] or 0
  if CleveRoids.debug and staticDur > 0 then
    local spellName = SpellInfo(spellID) or "Unknown"
    DEFAULT_CHAT_FRAME:AddMessage(
      string.format("|cffccccff[DEBUG GetDuration]|r %s (ID:%d) -> %ds (from static DB)",
        spellName, spellID, staticDur)
    )
  end
  return staticDur
end

function lib:AddEffect(guid, unitName, spellID, duration, stacks, caster)
  if not guid or not spellID then return end

  -- Normalize GUID to string for consistent table key lookups
  guid = CleveRoids.NormalizeGUID(guid)
  if not guid then return end

  duration = duration or lib:GetDuration(spellID, caster)
  if duration <= 0 then return end

  lib.objects[guid] = lib.objects[guid] or {}
  lib.guidToName[guid] = unitName

  local rec = lib.objects[guid][spellID] or {}
  rec.spellID = spellID
  rec.start = GetTime()
  rec.duration = duration
  rec.stacks = stacks or 0
  rec.caster = caster

  lib.objects[guid][spellID] = rec

  -- DEBUG: Show what we stored
  if CleveRoids.debug then
    local spellName = SpellInfo(spellID) or "Unknown"
    local casterStr = caster or "nil"
    DEFAULT_CHAT_FRAME:AddMessage(
      string.format("|cff00ffff[DEBUG AddEffect]|r %s (ID:%d) stored duration:%ds on %s, caster:%s, GUID:%s",
        spellName, spellID, duration, unitName or "Unknown", casterStr, tostring(guid))
    )
  end
end

function lib:UnitDebuff(unit, id, filterCaster)
  local _, guid = UnitExists(unit)
  if not guid then return nil end

  -- Normalize GUID to string for consistent table key lookups
  guid = CleveRoids.NormalizeGUID(guid)

  local texture, stacks, dtype, spellID = UnitDebuff(unit, id)

  if not texture or not spellID then
    texture, stacks, spellID = UnitBuff(unit, id)
    -- Only accept buffs that are known debuffs (either static or learned durations, including combo durations)
    if texture and spellID and lib:GetDuration(spellID) <= 0 then
      return nil
    end
  end

  if not texture or not spellID then return nil end

  local name = SpellInfo(spellID)
  local duration, timeleft, caster = nil, -1, nil

  local rec = lib.objects[guid] and lib.objects[guid][spellID]

  if rec and rec.duration and rec.start then
    local remaining = rec.duration + rec.start - GetTime()
    if remaining > 0 then
      duration = rec.duration
      timeleft = remaining
      caster = rec.caster
      stacks = rec.stacks or stacks

      -- Filter by caster if requested
      -- Since personal debuffs are only tracked via UNIT_CASTEVENT (player only),
      -- this filter only applies to shared debuffs where multiple casters can apply
      if filterCaster and caster ~= filterCaster then
        return nil
      end
    else
      lib.objects[guid][spellID] = nil
    end
  elseif filterCaster then
    -- No tracking record exists. This means either:
    -- 1. Personal debuff from another player (wasn't tracked via UNIT_CASTEVENT)
    -- 2. Shared debuff that expired from tracking
    -- In both cases, if filtering by caster, we should reject it
    return nil
  end

  return name, nil, texture, stacks, dtype, duration, timeleft, caster
end

-- Query buff data with duration and caster tracking (buff slots only)
function lib:UnitBuff(unit, id, filterCaster)
  local _, guid = UnitExists(unit)
  if not guid then return nil end

  -- Only check buff slots
  local texture, stacks, spellID = UnitBuff(unit, id)

  if not texture or not spellID then return nil end

  local name = SpellInfo(spellID)
  local duration, timeleft, caster = nil, -1, nil

  local rec = lib.objects[guid] and lib.objects[guid][spellID]

  if rec and rec.duration and rec.start then
    local remaining = rec.duration + rec.start - GetTime()
    if remaining > 0 then
      duration = rec.duration
      timeleft = remaining
      caster = rec.caster
      stacks = rec.stacks or stacks

      -- Filter by caster if requested
      if filterCaster and caster ~= filterCaster then
        return nil
      end
    else
      lib.objects[guid][spellID] = nil
    end
  elseif filterCaster then
    -- No tracking record exists - reject when filtering by caster
    return nil
  end

  return name, nil, texture, stacks, nil, duration, timeleft, caster
end

-- Find a player-cast debuff by spell ID (searches all slots including buff slots)
function lib:FindPlayerDebuff(unit, spellID)
  local _, guid = UnitExists(unit)
  if not guid then return nil end

  -- Check if we're tracking this spell for this unit
  local rec = lib.objects[guid] and lib.objects[guid][spellID]
  if not rec then return nil end

  -- Only return if it was cast by player
  if rec.caster ~= "player" then return nil end

  -- Check if it's still active
  local remaining = rec.duration + rec.start - GetTime()
  if remaining <= 0 then
    lib.objects[guid][spellID] = nil
    return nil
  end

  -- Find the texture by searching debuff and buff slots
  local texture, stacks = nil, rec.stacks

  -- Search debuff slots first
  for i = 1, 16 do
    local tex, st, dtype, sid = UnitDebuff(unit, i)
    if not tex then break end
    if sid == spellID then
      texture = tex
      stacks = st or stacks
      break
    end
  end

  -- If not found in debuffs, search buff slots
  if not texture then
    for i = 1, 32 do
      local tex, st, sid = UnitBuff(unit, i)
      if not tex then break end
      if sid == spellID then
        texture = tex
        stacks = st or stacks
        break
      end
    end
  end

  if not texture then return nil end

  local name = SpellInfo(spellID)
  return name, nil, texture, stacks, nil, rec.duration, remaining, rec.caster
end

-- Find a player-cast buff by spell ID (searches buff slots only)
function lib:FindPlayerBuff(unit, spellID)
  local _, guid = UnitExists(unit)
  if not guid then return nil end

  -- Check if we're tracking this spell for this unit
  local rec = lib.objects[guid] and lib.objects[guid][spellID]
  if not rec then return nil end

  -- Only return if it was cast by player
  if rec.caster ~= "player" then return nil end

  -- Check if it's still active
  local remaining = rec.duration + rec.start - GetTime()
  if remaining <= 0 then
    lib.objects[guid][spellID] = nil
    return nil
  end

  -- Find the texture by searching buff slots only
  local texture, stacks = nil, rec.stacks

  for i = 1, 32 do
    local tex, st, sid = UnitBuff(unit, i)
    if not tex then break end
    if sid == spellID then
      texture = tex
      stacks = st or stacks
      break
    end
  end

  if not texture then return nil end

  local name = SpellInfo(spellID)
  return name, nil, texture, stacks, nil, rec.duration, remaining, rec.caster
end

local function SeedUnit(unit)
  local _, guid = UnitExists(unit)
  if not guid then return end
  local unitName = UnitName(unit)

  for i=1, 16 do
    local tex, stacks, dtype, spellID = UnitDebuff(unit, i)
    if not tex then break end

    if spellID then
      -- CURSIVE ARCHITECTURE: Skip personal debuffs - they should only be tracked via UNIT_CASTEVENT
      -- Only track shared debuffs in SeedUnit (e.g., Sunder Armor, Thunder Clap)
      if lib:IsPersonalDebuff(spellID) then
        -- Skip this debuff - it should only come from UNIT_CASTEVENT
      else
        local duration = lib:GetDuration(spellID)
        if duration > 0 then
          -- SHARED DEBUFFS: Always update to refresh stacks and duration
          -- Check if already exists - if so, preserve caster info
          local existingCaster = nil
          if lib.objects[guid] and lib.objects[guid][spellID] then
            existingCaster = lib.objects[guid][spellID].caster
          end

          if not (lib.objects[guid] and lib.objects[guid][spellID]) then
            -- First time seeing this debuff - check for combo spell duration
            if CleveRoids.IsComboScalingSpellID and CleveRoids.IsComboScalingSpellID(spellID) and
               CleveRoids_ComboDurations and CleveRoids_ComboDurations[spellID] then
              -- Use the longest learned duration (assume 5 CP)
              for cp = 5, 1, -1 do
                if CleveRoids_ComboDurations[spellID][cp] then
                  duration = CleveRoids_ComboDurations[spellID][cp]
                  if CleveRoids.debug then
                    local spellName = SpellInfo(spellID) or "Unknown"
                    DEFAULT_CHAT_FRAME:AddMessage(
                      string.format("|cffaaff00[DEBUG SeedUnit Debuff]|r %s (ID:%d) using learned %dCP duration:%ds",
                        spellName, spellID, cp, duration)
                    )
                  end
                  break
                end
              end
            end
            duration = duration or lib:GetDuration(spellID)
          end

          -- Always update shared debuffs to keep stacks current
          lib:AddEffect(guid, unitName, spellID, duration, stacks, existingCaster)
        end
      end
    end
  end

  for i=1, 32 do
    local tex, stacks, spellID = UnitBuff(unit, i)
    if not tex then break end

    if spellID then
      -- CURSIVE ARCHITECTURE: Skip personal debuffs in overflow buff slots
      -- Only track shared debuffs in SeedUnit
      if lib:IsPersonalDebuff(spellID) then
        -- Skip this debuff - it should only come from UNIT_CASTEVENT
      else
        local duration = lib:GetDuration(spellID)
        if duration > 0 then
          -- SHARED DEBUFFS: Always update to refresh stacks and duration
          -- Check if already exists - if so, preserve caster info
          local existingCaster = nil
          if lib.objects[guid] and lib.objects[guid][spellID] then
            existingCaster = lib.objects[guid][spellID].caster
          end

          if not (lib.objects[guid] and lib.objects[guid][spellID]) then
            -- First time seeing this debuff - check for combo spell duration
            if CleveRoids.IsComboScalingSpellID and CleveRoids.IsComboScalingSpellID(spellID) and
               CleveRoids_ComboDurations and CleveRoids_ComboDurations[spellID] then
              -- Use the longest learned duration (assume 5 CP)
              for cp = 5, 1, -1 do
                if CleveRoids_ComboDurations[spellID][cp] then
                  duration = CleveRoids_ComboDurations[spellID][cp]
                  if CleveRoids.debug then
                    local spellName = SpellInfo(spellID) or "Unknown"
                    DEFAULT_CHAT_FRAME:AddMessage(
                      string.format("|cffaaff00[DEBUG SeedUnit Buff]|r %s (ID:%d) using learned %dCP duration:%ds",
                        spellName, spellID, cp, duration)
                    )
                  end
                  break
                end
              end
            end
            duration = duration or lib:GetDuration(spellID)
          end

          -- Always update shared debuffs to keep stacks current
          lib:AddEffect(guid, unitName, spellID, duration, stacks, existingCaster)
        end
      end
    end
  end
end

-- Carnage pending refresh system
-- Stores pending Carnage refreshes to be applied after verifying the Ferocious Bite hit
-- Format: { timestamp = GetTime(), targetGUID = guid, targetName = name, biteSpellID = id }
lib.pendingCarnageRefresh = nil

-- Personal debuff pending tracking system
-- Stores personal debuffs to be added after 0.5s delay (to verify they weren't dodged/parried/blocked)
-- Format: { [index] = { timestamp = GetTime(), targetGUID = guid, targetName = name, spellID = id, duration = X, comboPoints = CP } }
lib.pendingPersonalDebuffs = lib.pendingPersonalDebuffs or {}

-- Function to apply Carnage refresh (extracted for delayed execution)
local function ApplyCarnageRefresh(targetGUID, targetName, biteSpellID)
  if CleveRoids.debug then
    DEFAULT_CHAT_FRAME:AddMessage(
      string.format("|cffff00ff[Carnage]|r ApplyCarnageRefresh called for %s", targetName or "Unknown")
    )
  end

  -- Only refresh debuffs if they're currently active on the target
  if not lib.objects[targetGUID] then return end

  -- Try to refresh Rip
  if CleveRoids.lastRipCast and CleveRoids.lastRipCast.duration and
     CleveRoids.lastRipCast.targetGUID == targetGUID then
    -- Find which Rip rank is currently active
    for ripSpellID, _ in pairs(CleveRoids.RipSpellIDs) do
      if lib.objects[targetGUID][ripSpellID] then
        -- Found an active Rip, refresh it with the saved duration
        local ripDuration = CleveRoids.lastRipCast.duration
        local ripComboPoints = CleveRoids.lastRipCast.comboPoints or 5

        if CleveRoids.debug then
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff00ff[Carnage]|r About to refresh Rip: %ds on %s (spellID:%d)",
              ripDuration, targetName or "Unknown", ripSpellID)
          )
        end

        -- Store duration override for pfUI hooks (BEFORE updating tracking)
        if not CleveRoids.carnageDurationOverrides then
          CleveRoids.carnageDurationOverrides = {}
        end
        CleveRoids.carnageDurationOverrides[ripSpellID] = {
          duration = ripDuration,
          timestamp = GetTime(),
          targetGUID = targetGUID
        }

        -- Update CleveRoids internal tracking
        if lib.objects[targetGUID][ripSpellID] then
          lib.objects[targetGUID][ripSpellID].duration = ripDuration
          lib.objects[targetGUID][ripSpellID].start = GetTime()
          lib.objects[targetGUID][ripSpellID].expiry = GetTime() + ripDuration

          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cffff00ff[Carnage]|r Updated CleveRoids tracking for Rip")
            )
          end
        end

        -- DON'T call pfUI's AddEffect - just update the existing entry directly
        -- pfUI will pick up the new duration through our GetDuration/UnitDebuff hooks
        if pfUI and pfUI.api and pfUI.api.libdebuff then
          local pflib = pfUI.api.libdebuff
          local ripSpellName = SpellInfo(ripSpellID)
          local baseName = ripSpellName and string.gsub(ripSpellName, "%s*%(Rank %d+%)", "") or "Rip"

          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cffff00ff[Carnage]|r Updating existing pfUI entry for Rip directly")
            )
          end

          -- Find and update the existing pfUI entry (don't create new ones)
          if pflib.objects and pflib.objects[targetName] then
            local updated = false
            for level, effects in pairs(pflib.objects[targetName]) do
              if type(effects) == "table" and effects[baseName] then
                -- Update the existing entry
                effects[baseName].start = GetTime()
                effects[baseName].duration = ripDuration
                effects[baseName].caster = "player"
                updated = true

                if CleveRoids.debug then
                  DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffff00ff[Carnage]|r Updated pfUI Rip at level %s", tostring(level))
                  )
                end
                -- Only update the FIRST occurrence to avoid duplicates
                break
              end
            end

            if updated and pflib.UpdateUnits then
              pflib:UpdateUnits()
            end
          end
        end

        if CleveRoids.debug then
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff00ff[Carnage]|r Finished refreshing Rip: %ds on %s",
              ripDuration, targetName or "Unknown")
          )
        end
        break
      end
    end
  end

  -- Try to refresh Rake
  if CleveRoids.lastRakeCast and CleveRoids.lastRakeCast.duration and
     CleveRoids.lastRakeCast.targetGUID == targetGUID then
    -- Find which Rake rank is currently active
    for rakeSpellID, _ in pairs(CleveRoids.RakeSpellIDs) do
      if lib.objects[targetGUID][rakeSpellID] then
        -- Found an active Rake, refresh it with the saved duration
        local rakeDuration = CleveRoids.lastRakeCast.duration
        local rakeComboPoints = CleveRoids.lastRakeCast.comboPoints or 5

        -- Store duration override for pfUI hooks (BEFORE updating tracking)
        if not CleveRoids.carnageDurationOverrides then
          CleveRoids.carnageDurationOverrides = {}
        end
        CleveRoids.carnageDurationOverrides[rakeSpellID] = {
          duration = rakeDuration,
          timestamp = GetTime(),
          targetGUID = targetGUID
        }

        -- Update CleveRoids internal tracking
        if lib.objects[targetGUID][rakeSpellID] then
          lib.objects[targetGUID][rakeSpellID].duration = rakeDuration
          lib.objects[targetGUID][rakeSpellID].start = GetTime()
          lib.objects[targetGUID][rakeSpellID].expiry = GetTime() + rakeDuration
        end

        -- DON'T call pfUI's AddEffect - just update the existing entry directly
        -- pfUI will pick up the new duration through our GetDuration/UnitDebuff hooks
        if pfUI and pfUI.api and pfUI.api.libdebuff then
          local pflib = pfUI.api.libdebuff
          local rakeSpellName = SpellInfo(rakeSpellID)
          local baseName = rakeSpellName and string.gsub(rakeSpellName, "%s*%(Rank %d+%)", "") or "Rake"

          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cffff00ff[Carnage]|r Updating existing pfUI entry for Rake directly")
            )
          end

          -- Find and update the existing pfUI entry (don't create new ones)
          if pflib.objects and pflib.objects[targetName] then
            local updated = false
            for level, effects in pairs(pflib.objects[targetName]) do
              if type(effects) == "table" and effects[baseName] then
                -- Update the existing entry
                effects[baseName].start = GetTime()
                effects[baseName].duration = rakeDuration
                effects[baseName].caster = "player"
                updated = true

                if CleveRoids.debug then
                  DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffff00ff[Carnage]|r Updated pfUI Rake at level %s", tostring(level))
                  )
                end
                -- Only update the FIRST occurrence to avoid duplicates
                break
              end
            end

            if updated and pflib.UpdateUnits then
              pflib:UpdateUnits()
            end
          end
        end

        if CleveRoids.debug then
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff00ff[Carnage]|r Refreshed Rake: %ds on %s",
              rakeDuration, targetName or "Unknown")
          )
        end
        break
      end
    end
  end
end

-- Frame for delayed Carnage refresh and personal debuff tracking
local delayedTrackingFrame = CreateFrame("Frame", "CleveRoidsDelayedTrackingFrame", UIParent)
delayedTrackingFrame:SetScript("OnUpdate", function()
  -- Process pending Carnage refresh
  if lib.pendingCarnageRefresh then
    local pending = lib.pendingCarnageRefresh
    local elapsed = GetTime() - pending.timestamp

    -- Apply refresh after 0.3 second delay (enough time for dodge/parry/block messages)
    if elapsed >= 0.3 then
      -- Apply the Carnage refresh
      ApplyCarnageRefresh(pending.targetGUID, pending.targetName, pending.biteSpellID)

      if CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
          string.format("|cffff00ff[Carnage]|r Applied delayed refresh for Ferocious Bite on %s",
            pending.targetName or "Unknown")
        )
      end

      -- Clear the pending refresh
      lib.pendingCarnageRefresh = nil
    end
  end

  -- Process pending personal debuffs
  if lib.pendingPersonalDebuffs then
    local toRemove = {}
    for i, pending in ipairs(lib.pendingPersonalDebuffs) do
      local elapsed = GetTime() - pending.timestamp

      -- Add debuff after 0.3 second delay (enough time for dodge/parry/block messages)
      if elapsed >= 0.3 then
        -- Apply the personal debuff to tracking
        lib:AddEffect(pending.targetGUID, pending.targetName, pending.spellID, pending.duration, 0, "player")

        if CleveRoids.debug then
          local spellName = SpellInfo(pending.spellID) or "Unknown"
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cff00ff00[Delayed Track]|r Applied %s (ID:%d) to tracking on %s",
              spellName, pending.spellID, pending.targetName or "Unknown")
          )
        end

        -- Mark for removal
        table.insert(toRemove, i)
      end
    end

    -- Remove processed debuffs (iterate backwards to avoid index shifting)
    for i = table.getn(toRemove), 1, -1 do
      table.remove(lib.pendingPersonalDebuffs, toRemove[i])
    end
  end
end)

local ev = CreateFrame("Frame", "CleveRoidsLibDebuffFrame", UIParent)
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("UNIT_AURA")

if CleveRoids.hasSuperwow then
  ev:RegisterEvent("UNIT_CASTEVENT")
end

ev:SetScript("OnEvent", function()
  if event == "PLAYER_TARGET_CHANGED" then
    SeedUnit("target")

  elseif event == "UNIT_AURA" and arg1 == "target" then
    SeedUnit("target")

  elseif event == "UNIT_CASTEVENT" then
    local casterGUID = arg1
    local targetGUID = arg2
    local eventType = arg3
    local spellID = arg4

    -- Normalize targetGUID to string for consistent table key lookups
    targetGUID = CleveRoids.NormalizeGUID(targetGUID)

    -- Capture combo points when cast STARTS (before they're consumed)
    if (eventType == "START" or eventType == "CHANNEL") and spellID then
      local _, playerGUID = UnitExists("player")
      if casterGUID == playerGUID and targetGUID then
        -- If this is a combo scaling spell OR Ferocious Bite, capture combo points NOW (before consumption)
        local isComboSpell = CleveRoids.IsComboScalingSpellID and CleveRoids.IsComboScalingSpellID(spellID)
        local isFerociousBite = CleveRoids.FerociousBiteSpellIDs and CleveRoids.FerociousBiteSpellIDs[spellID]

        if isComboSpell or isFerociousBite then
          local currentCP = CleveRoids.GetComboPoints()
          if currentCP and currentCP > 0 then
            CleveRoids.lastComboPoints = currentCP
            if CleveRoids.debug then
              local spellName = SpellInfo(spellID) or "Unknown"
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffaaaaff[UNIT_CASTEVENT START]|r Captured %d CP before casting %s (ID:%d)",
                  currentCP, spellName, spellID)
              )
            end
          end
        end
      end
    end

    if eventType == "CAST" and spellID then
      local _, playerGUID = UnitExists("player")
      if casterGUID == playerGUID and targetGUID then

        -- DRUID CARNAGE TALENT: Check if this is Ferocious Bite with 5 CP
        -- Schedule a delayed refresh to allow dodge/parry/block detection
        if CleveRoids.FerociousBiteSpellIDs and CleveRoids.FerociousBiteSpellIDs[spellID] then
          -- Get combo points used (captured before consumption)
          local biteComboPoints = CleveRoids.lastComboPoints or 0

          -- Check if player has Carnage talent at rank 2
          -- Carnage: Tab 2 (Feral Combat), Talent 17
          local carnageRank = 0
          local _, _, _, _, rank = GetTalentInfo(2, 17)
          carnageRank = tonumber(rank) or 0

          -- Carnage 2/2+: Ferocious Bite at 5 CP schedules a refresh (applied only if spell hits)
          if carnageRank >= 2 and biteComboPoints == 5 then
            local targetName = lib.guidToName[targetGUID]
            if not targetName then
              local _, currentTargetGUID = UnitExists("target")
              currentTargetGUID = CleveRoids.NormalizeGUID(currentTargetGUID)
              if currentTargetGUID == targetGUID then
                targetName = UnitName("target")
                lib.guidToName[targetGUID] = targetName
              else
                targetName = "Unknown"
              end
            end

            -- Schedule the Carnage refresh (will be applied after 0.5s if not cancelled)
            lib.pendingCarnageRefresh = {
              timestamp = GetTime(),
              targetGUID = targetGUID,
              targetName = targetName,
              biteSpellID = spellID
            }

            if CleveRoids.debug then
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff00ff[Carnage]|r Scheduled refresh for Ferocious Bite on %s (will apply if hit)",
                  targetName or "Unknown")
              )
            end
          end
        end

        -- Check if this is a combo point scaling spell first
        local duration = nil
        local comboPoints = nil
        if CleveRoids.TrackComboPointCastByID then
          duration = CleveRoids.TrackComboPointCastByID(spellID, targetGUID)
          -- Get combo points used from tracking
          if CleveRoids.ComboPointTracking and CleveRoids.ComboPointTracking.byID and
             CleveRoids.ComboPointTracking.byID[spellID] then
            comboPoints = CleveRoids.ComboPointTracking.byID[spellID].combo_points
          end
        end

        -- If not a combo scaling spell, use normal duration lookup
        if not duration then
          duration = lib:GetDuration(spellID, casterGUID)

          -- Apply talent modifiers for non-combo spells
          -- (combo spells already have talent modifiers applied in CalculateComboScaledDurationByID)
          if duration and CleveRoids.ApplyTalentModifier then
            duration = CleveRoids.ApplyTalentModifier(spellID, duration)
          end

          -- Apply equipment modifiers for non-combo spells
          -- (combo spells already have equipment modifiers applied in CalculateComboScaledDurationByID)
          if duration and CleveRoids.ApplyEquipmentModifier then
            duration = CleveRoids.ApplyEquipmentModifier(spellID, duration)
          end

          -- Apply set bonus modifiers for non-combo spells
          if duration and CleveRoids.ApplySetBonusModifier then
            duration = CleveRoids.ApplySetBonusModifier(spellID, duration)
          end
        end

        -- DEBUG: Show what duration we calculated
        if CleveRoids.debug and duration then
          local spellName = SpellInfo(spellID) or "Unknown"
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff00ff[DEBUG CAST]|r %s (ID:%d) CP:%s duration:%ds",
              spellName, spellID, tostring(comboPoints or "nil"), duration)
          )
        end

        if duration and duration > 0 then
          local targetName = lib.guidToName[targetGUID]
          if not targetName then
            local _, currentTargetGUID = UnitExists("target")
            if currentTargetGUID == targetGUID then
              targetName = UnitName("target")
              lib.guidToName[targetGUID] = targetName
            else
              targetName = "Unknown"
            end
          end

          -- For combo spells, populate name-based tracking for pfUI compatibility
          if comboPoints and comboPoints > 0 then
            local spellName = SpellInfo(spellID)
            if spellName and CleveRoids.ComboPointTracking then
              -- Remove rank from spell name to match pfUI's format
              local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
              CleveRoids.ComboPointTracking[baseName] = {
                combo_points = comboPoints,
                duration = duration,
                cast_time = GetTime(),
                target = targetName,
                confirmed = true  -- This is from actual UNIT_CASTEVENT, always confirmed
              }
              if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cff00ffff[Name-based tracking]|r Set %s: %d CP, %ds duration (for pfUI)",
                    baseName, comboPoints, duration)
                )
              end

              -- CRITICAL: Update pfUI's duration database directly
              if pfUI and pfUI.api and pfUI.api.libdebuff and pfUI.api.libdebuff.debuffs then
                -- pfUI stores durations by spell name in its debuffs table
                pfUI.api.libdebuff.debuffs[baseName] = duration
                if CleveRoids.debug then
                  DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffff00ff[pfUI Duration Inject]|r Set pfUI.api.libdebuff.debuffs['%s'] = %ds",
                      baseName, duration)
                  )
                end
              end
            end
          end

          -- Check if this is a personal debuff - if so, delay tracking to verify it lands
          local isPersonal = lib:IsPersonalDebuff(spellID)

          if isPersonal then
            -- Schedule personal debuff for delayed tracking (after 0.5s)
            table.insert(lib.pendingPersonalDebuffs, {
              timestamp = GetTime(),
              targetGUID = targetGUID,
              targetName = targetName,
              spellID = spellID,
              duration = duration,
              comboPoints = comboPoints
            })

            if CleveRoids.debug then
              local spellName = SpellInfo(spellID) or "Unknown"
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffaaff00[Pending Track]|r Scheduled %s (ID:%d) for tracking on %s (will apply if hit)",
                  spellName, spellID, targetName or "Unknown")
              )
            end
          else
            -- Shared debuff - add immediately with predicted stack count
            -- For stacking debuffs (Sunder, Faerie Fire), predict new stack count
            local newStacks = 0

            -- Check current stacks on target
            local _, currentTargetGUID = UnitExists("target")
            currentTargetGUID = CleveRoids.NormalizeGUID(currentTargetGUID)
            if currentTargetGUID == targetGUID and CleveRoids.hasSuperwow then
              -- Scan debuff slots to find current stacks
              for i = 1, 16 do
                local _, existingStacks, _, existingSpellID = UnitDebuff("target", i)
                if existingSpellID == spellID then
                  newStacks = (existingStacks or 0) + 1
                  break
                end
              end

              -- If not found in debuff slots, check buff slots (overflow)
              if newStacks == 0 then
                for i = 1, 32 do
                  local _, existingStacks, existingSpellID = UnitBuff("target", i)
                  if existingSpellID == spellID then
                    newStacks = (existingStacks or 0) + 1
                    break
                  end
                end
              end

              -- If still not found, this is the first stack
              if newStacks == 0 then
                newStacks = 1
              end

              -- Cap at maximum stacks (5 for Sunder Armor, most debuffs)
              -- TODO: Make this configurable per spell if needed
              if newStacks > 5 then
                newStacks = 5
              end

              if CleveRoids.debug then
                local spellName = SpellInfo(spellID) or "Unknown"
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cff00ff00[Shared Debuff]|r %s (ID:%d) predicted stacks:%d",
                    spellName, spellID, newStacks)
                )
              end
            else
              -- Target changed or not available, default to 1 stack
              newStacks = 1
            end

            lib:AddEffect(targetGUID, targetName, spellID, duration, newStacks, "player")
          end

          -- Track this cast for miss/dodge/parry removal
          lib.lastPlayerCast = {
            spellID = spellID,
            targetGUID = targetGUID,
            timestamp = GetTime()
          }

          -- DRUID CARNAGE TALENT: Save Rip cast duration for later refresh by Ferocious Bite
          if CleveRoids.RipSpellIDs and CleveRoids.RipSpellIDs[spellID] then
            if CleveRoids.lastRipCast then
              CleveRoids.lastRipCast.duration = duration
              CleveRoids.lastRipCast.targetGUID = targetGUID
              CleveRoids.lastRipCast.comboPoints = comboPoints or 0
              CleveRoids.lastRipCast.timestamp = GetTime()
              if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cff00ff00[Carnage]|r Saved Rip cast: %ds duration (%d CP) on target %s",
                    duration, comboPoints or 0, targetName or "Unknown")
                )
              end
            end
          end

          -- DRUID CARNAGE TALENT: Save Rake cast duration for later refresh by Ferocious Bite
          if CleveRoids.RakeSpellIDs and CleveRoids.RakeSpellIDs[spellID] then
            if CleveRoids.lastRakeCast then
              CleveRoids.lastRakeCast.duration = duration
              CleveRoids.lastRakeCast.targetGUID = targetGUID
              CleveRoids.lastRakeCast.comboPoints = comboPoints or 0
              CleveRoids.lastRakeCast.timestamp = GetTime()
              if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cff00ff00[Carnage]|r Saved Rake cast: %ds duration (%d CP) on target %s",
                    duration, comboPoints or 0, targetName or "Unknown")
                )
              end
            end
          end

          -- Sync combo duration to pfUI if it's loaded
          if comboPoints and CleveRoids.Compatibility_pfUI and
             CleveRoids.Compatibility_pfUI.SyncComboDurationToPfUI then
            CleveRoids.Compatibility_pfUI.SyncComboDurationToPfUI(targetGUID, spellID, duration)
          end

          -- ALWAYS set up learning for combo spells (even if we have calculated duration)
          if comboPoints then
            lib.learnCastTimers[targetGUID] = lib.learnCastTimers[targetGUID] or {}
            lib.learnCastTimers[targetGUID][spellID] = {
              start = GetTime(),
              caster = casterGUID,
              comboPoints = comboPoints  -- Store CP count for learning
            }
          end

        else
          lib.learnCastTimers[targetGUID] = lib.learnCastTimers[targetGUID] or {}
          lib.learnCastTimers[targetGUID][spellID] = {
            start = GetTime(),
            caster = casterGUID
          }

          lib.objects[targetGUID] = lib.objects[targetGUID] or {}
          lib.objects[targetGUID][spellID] = {
            spellID = spellID,
            start = GetTime(),
            duration = 999,  -- Placeholder
            stacks = 0,
            caster = casterGUID
          }
        end
      end
    end
  end
end)

-- Track the last cast spell and target for miss/dodge/parry removal
-- Format: { spellID = id, targetGUID = guid, timestamp = GetTime() }
lib.lastPlayerCast = lib.lastPlayerCast or nil

local evLearn = CreateFrame("Frame", "CleveRoidsLibDebuffLearnFrame", UIParent)
evLearn:RegisterEvent("RAW_COMBATLOG")
evLearn:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")  -- For miss/dodge/parry detection

evLearn:SetScript("OnEvent", function()
  -- Handle spell misses, dodges, parries, resists, blocks, and immunities
  if event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    local message = arg1
    if not message then return end

    -- Cursive-style pattern matching (more reliable than substring search)
    -- Patterns match "Your [Spell] was/is [result] by [Target]" format
    local spell_failed_tests = {
      "Your (.+) was resisted by (.+)",      -- resist
      "Your (.+) missed (.+)",                -- miss
      "Your (.+) is parried by (.+)",        -- parry (is, not was)
      "Your (.+) was dodged by (.+)",        -- dodge
      "Your (.+) was blocked by (.+)",       -- full block
      "Your (.+) fail.+%. (.+) is immune",   -- immune
    }

    local spellName, targetName
    for _, pattern in ipairs(spell_failed_tests) do
      local _, _, foundSpell, foundTarget = find(message, pattern)
      if foundSpell and foundTarget then
        spellName = foundSpell
        targetName = foundTarget
        break
      end
    end

    if spellName and targetName then
      -- CARNAGE: Cancel pending refresh if Ferocious Bite was dodged/parried/blocked
      if lib.pendingCarnageRefresh then
        -- Check if the failed spell is Ferocious Bite
        local isFerociousBite = false
        if CleveRoids.FerociousBiteSpellIDs then
          for biteSpellID, _ in pairs(CleveRoids.FerociousBiteSpellIDs) do
            local biteName = SpellInfo(biteSpellID)
            if biteName then
              biteName = string.gsub(biteName, "%s*%(%s*Rank%s+%d+%s*%)", "")
              local messageSpellName = string.gsub(spellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
              if lower(biteName) == lower(messageSpellName) then
                isFerociousBite = true
                break
              end
            end
          end
        end

        if isFerociousBite then
          -- Cancel the pending Carnage refresh
          if CleveRoids.debug and lib.pendingCarnageRefresh then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cffff00ff[Carnage]|r Cancelling pending refresh (time since cast: %.2fs)",
                GetTime() - lib.pendingCarnageRefresh.timestamp)
            )
          end

          lib.pendingCarnageRefresh = nil

          -- Clear any stale Carnage duration overrides to prevent pfUI from using old data
          if CleveRoids.carnageDurationOverrides then
            CleveRoids.carnageDurationOverrides = {}
          end

          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cffff00ff[Carnage]|r Cancelled refresh - Ferocious Bite was avoided by %s",
                targetName or "Unknown")
            )
          end
        end
      end

      -- PERSONAL DEBUFFS: Cancel pending tracking if spell was dodged/parried/blocked
      if lib.pendingPersonalDebuffs then
        local messageSpellName = string.gsub(spellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
        local toRemove = {}

        for i, pending in ipairs(lib.pendingPersonalDebuffs) do
          local pendingSpellName = SpellInfo(pending.spellID)
          if pendingSpellName then
            pendingSpellName = string.gsub(pendingSpellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
            if lower(pendingSpellName) == lower(messageSpellName) then
              -- Found the pending debuff that was avoided - cancel it
              if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cffff0000[Pending Track]|r Cancelled %s (ID:%d) - avoided by %s",
                    pendingSpellName, pending.spellID, targetName or "Unknown")
                )
              end
              table.insert(toRemove, i)
            end
          end
        end

        -- Remove cancelled debuffs (iterate backwards to avoid index shifting)
        for i = table.getn(toRemove), 1, -1 do
          table.remove(lib.pendingPersonalDebuffs, toRemove[i])
        end
      end

      -- Use the last player cast info if available and recent (within 1 second)
      if lib.lastPlayerCast and lib.lastPlayerCast.timestamp and
         (GetTime() - lib.lastPlayerCast.timestamp) < 1.0 then

        local targetGUID = lib.lastPlayerCast.targetGUID
        local castSpellID = lib.lastPlayerCast.spellID

        -- Get the spell name from the cast (strip rank)
        local castSpellName = SpellInfo(castSpellID)
        if castSpellName then
          castSpellName = string.gsub(castSpellName, "%s*%(%s*Rank%s+%d+%s*%)", "")

          -- Strip rank from the message spell name for comparison
          local messageSpellName = string.gsub(spellName, "%s*%(%s*Rank%s+%d+%s*%)", "")

          -- Only remove if the spell names match (case-insensitive)
          if lower(castSpellName) == lower(messageSpellName) then
            -- Verify the target name matches the stored GUID
            local expectedTargetName = lib.guidToName[targetGUID]
            if expectedTargetName and lower(expectedTargetName) ~= lower(targetName) then
              -- Wrong target - this failure is for a different cast, not the one in lastPlayerCast
              if CleveRoids.debugVerbose then
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cffff9900[Spell Failed]|r Ignoring %s failure - target mismatch (expected:%s, got:%s)",
                    castSpellName, expectedTargetName, targetName)
                )
              end
              return
            end

            -- Find all spell IDs matching this name (all ranks)
            local matchingSpellIDs = {}
            if lib.personalDebuffs then
              for sid, _ in pairs(lib.personalDebuffs) do
                local name = SpellInfo(sid)
                if name then
                  name = string.gsub(name, "%s*%(%s*Rank%s+%d+%s*%)", "")
                  if name == castSpellName then
                    table.insert(matchingSpellIDs, sid)
                  end
                end
              end
            end
            if lib.sharedDebuffs then
              for sid, _ in pairs(lib.sharedDebuffs) do
                local name = SpellInfo(sid)
                if name then
                  name = string.gsub(name, "%s*%(%s*Rank%s+%d+%s*%)", "")
                  if name == castSpellName then
                    table.insert(matchingSpellIDs, sid)
                  end
                end
              end
            end

            -- Remove ALL ranks from tracking (the cast failed)
            if targetGUID and lib.objects[targetGUID] then
              for _, sid in ipairs(matchingSpellIDs) do
                if lib.objects[targetGUID][sid] then
                  local rec = lib.objects[targetGUID][sid]
                  -- Only remove if very recently added (within 1 second)
                  if rec.start and (GetTime() - rec.start) < 1.0 then
                    lib.objects[targetGUID][sid] = nil
                    if CleveRoids.debug then
                      local failType = find(message, "resist") and "resisted" or
                                       find(message, "miss") and "missed" or
                                       find(message, "dodge") and "dodged" or
                                       find(message, "parry") and "parried" or
                                       find(message, "block") and "blocked" or
                                       find(message, "immune") and "immune" or "failed"

                      DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cffff6600[Spell Failed]|r Removed %s (ID:%d) from %s - %s",
                          castSpellName, sid, targetName or "target", failType)
                      )

                      -- If unknown fail type, show the actual message for debugging
                      if failType == "failed" and CleveRoids.debugVerbose then
                        DEFAULT_CHAT_FRAME:AddMessage(
                          string.format("|cffaaaaaa[Debug Message]|r %s", message)
                        )
                      end
                    end
                  end
                end
              end
            end

            -- Clear the last cast so we don't remove it again
            lib.lastPlayerCast = nil
          end
        end
      end
    end

  elseif event == "RAW_COMBATLOG" then
    local raw = arg2
    -- PERFORMANCE: Quick length check before string search
    if not raw or string.len(raw) < 12 then return end  -- "X fades from Y" minimum length
    if not find(raw, "fades from") then return end

    local _, _, spellName = find(raw, "^(.-) fades from ")
    local _, _, targetGUID = find(raw, "from (.-).$")

    if lower(targetGUID or "") == "you" then
      _, targetGUID = UnitExists("player")
    end
    targetGUID = gsub(targetGUID or "", "^0x", "")

    if not spellName or targetGUID == "" then return end
    if not lib.objects[targetGUID] then return end

    local timestamp = GetTime()

    for spellID in pairs(lib.objects[targetGUID]) do
      local name = SpellInfo(spellID)
      if name then
        name = gsub(name, "%s*%(%s*Rank%s+%d+%s*%)", "")
        if name == spellName then
          if lib.learnCastTimers[targetGUID] and
             lib.learnCastTimers[targetGUID][spellID] then

            local castTime = lib.learnCastTimers[targetGUID][spellID].start
            local casterGUID = lib.learnCastTimers[targetGUID][spellID].caster
            local actualDuration = timestamp - castTime

            -- Check if this is a combo point spell - if so, learn it with combo point context
            local comboPoints = lib.learnCastTimers[targetGUID][spellID].comboPoints
            if comboPoints and CleveRoids.IsComboScalingSpellID and CleveRoids.IsComboScalingSpellID(spellID) then
              -- Learn combo spell duration
              CleveRoids_ComboDurations = CleveRoids_ComboDurations or {}
              CleveRoids_ComboDurations[spellID] = CleveRoids_ComboDurations[spellID] or {}
              CleveRoids_ComboDurations[spellID][comboPoints] = floor(actualDuration + 0.5)

              if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  "|cff4b7dccCleveRoids:|r Learned combo spell " .. spellName ..
                  " (ID:" .. spellID .. ") at " .. comboPoints .. " CP = " .. floor(actualDuration + 0.5) .. "s"
                )
              end
            else
              -- Learn normal spell duration
              CleveRoids_LearnedDurations[spellID] = CleveRoids_LearnedDurations[spellID] or {}
              CleveRoids_LearnedDurations[spellID][casterGUID] = floor(actualDuration + 0.5)

              if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  "|cff4b7dccCleveRoids:|r Learned " .. spellName ..
                  " (ID:" .. spellID .. ") = " .. floor(actualDuration + 0.5) .. "s"
                )
              end
            end

            lib.learnCastTimers[targetGUID][spellID] = nil
            if not next(lib.learnCastTimers[targetGUID]) then
              lib.learnCastTimers[targetGUID] = nil
            end
          end

          -- For personal debuffs, only remove if it was cast by the player
          -- For shared debuffs, remove if expired OR not found in scan
          local rec = lib.objects[targetGUID][spellID]
          local isPersonal = lib:IsPersonalDebuff(spellID)
          local shouldRemove = false

          if isPersonal then
            -- Personal debuff: only remove if cast by player
            if rec.caster == "player" then
              -- Check if duration expired (with 1s safety margin for latency)
              local hasExpired = (rec.start + rec.duration + 1) <= timestamp

              -- As a fallback, scan to see if the debuff is completely gone
              -- (this helps catch edge cases where duration tracking is off)
              local stillExists = false
              local _, checkGUID = UnitExists("target")
              if checkGUID == targetGUID then
                for i = 1, 16 do
                  local _, _, _, checkSpellID = UnitDebuff("target", i)
                  if checkSpellID == spellID then
                    stillExists = true
                    break
                  end
                end
              end

              -- Remove if EITHER:
              -- 1. Duration expired AND debuff not found in scan (definitely gone)
              -- 2. Duration significantly expired (> 1s past expected expiry)
              if (hasExpired and not stillExists) or ((rec.start + rec.duration + 2) <= timestamp) then
                shouldRemove = true
                if CleveRoids.debug then
                  DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffff8800[Fade Handler]|r Removed player's %s (ID:%d) - expired:%.1fs scan:%s",
                      spellName, spellID, rec.start + rec.duration, tostring(not stillExists))
                  )
                end
              elseif CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cffff8800[Fade Handler]|r Keeping player's %s (ID:%d) - not expired or still exists (expires:%.1fs now:%.1fs exists:%s)",
                    spellName, spellID, rec.start + rec.duration, timestamp, tostring(stillExists))
                )
              end
            elseif CleveRoids.debug and rec.caster ~= "player" then
              -- Ignore fade events for other players' personal debuffs
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff8800[Fade Handler]|r Ignored %s (ID:%d) fade - caster is '%s', not player",
                  spellName, spellID, tostring(rec.caster or "nil"))
              )
            end
          else
            -- Shared debuff: use Cursive's approach - scan to verify it's gone
            local stillExists = false
            local _, checkGUID = UnitExists("target")
            if checkGUID == targetGUID then
              for i = 1, 16 do
                local _, _, _, checkSpellID = UnitDebuff("target", i)
                if checkSpellID == spellID then
                  stillExists = true
                  break
                end
              end
            end

            -- Remove if not found in scan OR if duration well past expiry
            if not stillExists or ((rec.start + rec.duration + 2) <= timestamp) then
              shouldRemove = true
              if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cffff8800[Fade Handler]|r Removed shared %s (ID:%d) - scan:%s expired:%s",
                    spellName, spellID, tostring(not stillExists), tostring((rec.start + rec.duration) <= timestamp))
                )
              end
            end
          end

          if shouldRemove then
            lib.objects[targetGUID][spellID] = nil
          end

          if not next(lib.objects[targetGUID]) then
            lib.objects[targetGUID] = nil
          end
          break
        end
      end
    end
  end
end)

-- Cleanup dead/invalid targets
local evCleanup = CreateFrame("Frame", "CleveRoidsLibDebuffCleanupFrame", UIParent)
evCleanup:RegisterEvent("PLAYER_TARGET_CHANGED")
evCleanup:RegisterEvent("PLAYER_DEAD")
evCleanup:RegisterEvent("PLAYER_ENTERING_WORLD")

local lastCleanup = 0
local CLEANUP_THROTTLE = 2  -- Only run cleanup every 2 seconds max

evCleanup:SetScript("OnEvent", function()
    local timestamp = GetTime()

    -- Cleanup on zone change / login / death
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        -- Keep only current target's data
        local _, currentGUID = UnitExists("target")
        if currentGUID then
            local temp = lib.objects[currentGUID]
            lib.objects = {}
            if temp then
                lib.objects[currentGUID] = temp
            end
        else
            lib.objects = {}  -- Clear everything
        end
        lastCleanup = timestamp
        return
    end

    -- Throttle cleanup on target change
    if event == "PLAYER_TARGET_CHANGED" then
        if (timestamp - lastCleanup) < CLEANUP_THROTTLE then
            return  -- Don't cleanup too frequently
        end
        lastCleanup = timestamp

        -- Remove expired effects from all GUIDs
        for guid, effects in pairs(lib.objects) do
            local _, targetGUID = UnitExists("target")
            local isCurrentTarget = (targetGUID == guid)

            -- Check if current target is dead
            if isCurrentTarget and UnitIsDead("target") then
                lib.objects[guid] = nil
                lib.guidToName[guid] = nil  -- MEMORY: Clean up name mapping
            else
                -- Remove expired effects
                for spellID, effect in pairs(effects) do
                    if effect.start + effect.duration < timestamp then
                        effects[spellID] = nil
                    end
                end

                -- Remove GUID if no effects remain (but keep current target)
                if not next(effects) and not isCurrentTarget then
                    lib.objects[guid] = nil
                    lib.guidToName[guid] = nil  -- MEMORY: Clean up name mapping
                end
            end
        end

        -- MEMORY: Clean up orphaned guidToName entries (GUIDs not in lib.objects)
        for guid in pairs(lib.guidToName) do
            if not lib.objects[guid] then
                lib.guidToName[guid] = nil
            end
        end
    end
end)

-- ============================================================================
-- TALENT MODIFIER SYSTEM
-- ============================================================================

-- Database of talent modifiers for debuff durations
-- Structure: [spellID] = {
--   talent = "Talent Name" (optional, for name-based lookup),
--   tab = talentTab (preferred, for direct position lookup),
--   id = talentID (preferred, for direct position lookup),
--   modifier = function(baseDuration, talentRank)
-- }
CleveRoids.talentModifiers = CleveRoids.talentModifiers or {}

-- ROGUE talent modifiers
-- Taste for Blood: Increases Rupture duration by 2 seconds per rank (3 ranks max)
-- Talent Position: Tab 1, Talent 10 (Assassination tree)
-- Talent Spell IDs: 14174 (Rank 1), 14175 (Rank 2), 14176 (Rank 3)
CleveRoids.talentModifiers[1943] = { tab = 1, id = 10, talent = "Taste for Blood", modifier = function(base, rank) return base + (rank * 2) end }  -- Rupture Rank 1
CleveRoids.talentModifiers[8639] = { tab = 1, id = 10, talent = "Taste for Blood", modifier = function(base, rank) return base + (rank * 2) end }  -- Rupture Rank 2
CleveRoids.talentModifiers[8640] = { tab = 1, id = 10, talent = "Taste for Blood", modifier = function(base, rank) return base + (rank * 2) end }  -- Rupture Rank 3
CleveRoids.talentModifiers[11273] = { tab = 1, id = 10, talent = "Taste for Blood", modifier = function(base, rank) return base + (rank * 2) end } -- Rupture Rank 4
CleveRoids.talentModifiers[11274] = { tab = 1, id = 10, talent = "Taste for Blood", modifier = function(base, rank) return base + (rank * 2) end } -- Rupture Rank 5
CleveRoids.talentModifiers[11275] = { tab = 1, id = 10, talent = "Taste for Blood", modifier = function(base, rank) return base + (rank * 2) end } -- Rupture Rank 6

-- Improved Gouge: Increases Gouge duration by 0.5 seconds per rank (3 ranks max)
-- Talent Position: Tab 3, Talent 3 (Subtlety tree)
-- Talent Spell IDs: 13741 (Rank 1), 13793 (Rank 2), 13792 (Rank 3)
CleveRoids.talentModifiers[1776] = { tab = 3, id = 3, talent = "Improved Gouge", modifier = function(base, rank) return base + (rank * 0.5) end }  -- Gouge Rank 1
CleveRoids.talentModifiers[1777] = { tab = 3, id = 3, talent = "Improved Gouge", modifier = function(base, rank) return base + (rank * 0.5) end }  -- Gouge Rank 2
CleveRoids.talentModifiers[8629] = { tab = 3, id = 3, talent = "Improved Gouge", modifier = function(base, rank) return base + (rank * 0.5) end }  -- Gouge Rank 3
CleveRoids.talentModifiers[11285] = { tab = 3, id = 3, talent = "Improved Gouge", modifier = function(base, rank) return base + (rank * 0.5) end } -- Gouge Rank 4
CleveRoids.talentModifiers[11286] = { tab = 3, id = 3, talent = "Improved Gouge", modifier = function(base, rank) return base + (rank * 0.5) end } -- Gouge Rank 5

-- PRIEST talent modifiers
-- Improved Shadow Word: Pain: Increases SW:P duration by 3 seconds per rank (2 ranks max)
-- Talent Position: Tab 3 (Shadow), Talent 4
-- Talent Spell IDs: 15275 (Rank 1), 15317 (Rank 2)
CleveRoids.talentModifiers[589] = { tab = 3, id = 4, talent = "Improved Shadow Word: Pain", modifier = function(base, rank) return base + (rank * 3) end }    -- SW:P Rank 1
CleveRoids.talentModifiers[594] = { tab = 3, id = 4, talent = "Improved Shadow Word: Pain", modifier = function(base, rank) return base + (rank * 3) end }    -- SW:P Rank 2
CleveRoids.talentModifiers[970] = { tab = 3, id = 4, talent = "Improved Shadow Word: Pain", modifier = function(base, rank) return base + (rank * 3) end }    -- SW:P Rank 3
CleveRoids.talentModifiers[992] = { tab = 3, id = 4, talent = "Improved Shadow Word: Pain", modifier = function(base, rank) return base + (rank * 3) end }    -- SW:P Rank 4
CleveRoids.talentModifiers[2767] = { tab = 3, id = 4, talent = "Improved Shadow Word: Pain", modifier = function(base, rank) return base + (rank * 3) end }   -- SW:P Rank 5
CleveRoids.talentModifiers[10892] = { tab = 3, id = 4, talent = "Improved Shadow Word: Pain", modifier = function(base, rank) return base + (rank * 3) end }  -- SW:P Rank 6
CleveRoids.talentModifiers[10893] = { tab = 3, id = 4, talent = "Improved Shadow Word: Pain", modifier = function(base, rank) return base + (rank * 3) end }  -- SW:P Rank 7
CleveRoids.talentModifiers[10894] = { tab = 3, id = 4, talent = "Improved Shadow Word: Pain", modifier = function(base, rank) return base + (rank * 3) end }  -- SW:P Rank 8

-- DRUID talent modifiers
-- Brutal Impact: Increases Bash and Pounce stun duration by 0.5 seconds per rank (2 ranks max)
-- Talent Position: Tab 2 (Feral Combat), Talent 4
-- Talent Spell IDs: 16940 (Rank 1), 16941 (Rank 2)
CleveRoids.talentModifiers[5211] = { tab = 2, id = 4, talent = "Brutal Impact", modifier = function(base, rank) return base + (rank * 0.5) end }  -- Bash Rank 1
CleveRoids.talentModifiers[6798] = { tab = 2, id = 4, talent = "Brutal Impact", modifier = function(base, rank) return base + (rank * 0.5) end }  -- Bash Rank 2
CleveRoids.talentModifiers[8983] = { tab = 2, id = 4, talent = "Brutal Impact", modifier = function(base, rank) return base + (rank * 0.5) end }  -- Bash Rank 3

CleveRoids.talentModifiers[9005] = { tab = 2, id = 4, talent = "Brutal Impact", modifier = function(base, rank) return base + (rank * 0.5) end }  -- Pounce Rank 1
CleveRoids.talentModifiers[9823] = { tab = 2, id = 4, talent = "Brutal Impact", modifier = function(base, rank) return base + (rank * 0.5) end }  -- Pounce Rank 2
CleveRoids.talentModifiers[9827] = { tab = 2, id = 4, talent = "Brutal Impact", modifier = function(base, rank) return base + (rank * 0.5) end }  -- Pounce Rank 3

-- NOTE: Carnage talent (Tab 2, ID 17) is NOT a duration modifier!
-- Carnage is a refresh mechanic: Ferocious Bite at 5 CP refreshes Rip/Rake to their original duration
-- This is handled separately in the Carnage refresh logic (lines 1125-1192)

-- WARRIOR talent modifiers
-- Booming Voice: Increases duration of Battle Shout and Demoralizing Shout by 12% per rank (5 ranks max)
-- Talent Position: Tab 2 (Fury), Talent 1
-- Talent Spell IDs: 12321 (Rank 1), 12835 (Rank 2), 12836 (Rank 3), 12837 (Rank 4), 12838 (Rank 5)
local boomingVoiceModifier = function(base, rank) return base * (1 + rank * 0.12) end  -- 12% per rank, 60% at rank 5
CleveRoids.talentModifiers[1160] = { tab = 2, id = 1, talent = "Booming Voice", modifier = boomingVoiceModifier }   -- Demoralizing Shout Rank 1
CleveRoids.talentModifiers[6190] = { tab = 2, id = 1, talent = "Booming Voice", modifier = boomingVoiceModifier }   -- Demoralizing Shout Rank 2
CleveRoids.talentModifiers[11554] = { tab = 2, id = 1, talent = "Booming Voice", modifier = boomingVoiceModifier }  -- Demoralizing Shout Rank 3
CleveRoids.talentModifiers[11555] = { tab = 2, id = 1, talent = "Booming Voice", modifier = boomingVoiceModifier }  -- Demoralizing Shout Rank 4
CleveRoids.talentModifiers[11556] = { tab = 2, id = 1, talent = "Booming Voice", modifier = boomingVoiceModifier }  -- Demoralizing Shout Rank 5

-- Function to get talent rank
-- Supports both position-based (tab, id) and name-based lookup
-- Position-based is preferred as it's more reliable and locale-independent (like Cursive addon)
-- Parameters: talentName OR (tab, id)
-- Returns: Talent rank (0 if not found or not learned)
function CleveRoids.GetTalentRank(talentName, tab, id)
    -- Method 1: Direct position lookup (preferred, like Cursive)
    if tab and id then
        local _, _, _, _, rank = GetTalentInfo(tab, id)
        return tonumber(rank) or 0
    end

    -- Method 2: Name-based lookup (fallback for backwards compatibility)
    if not talentName then return 0 end

    -- Ensure talents are indexed
    if not CleveRoids.Talents or table.getn(CleveRoids.Talents) == 0 then
        if CleveRoids.IndexTalents then
            CleveRoids.IndexTalents()
        end
    end

    local rank = CleveRoids.Talents[talentName]
    return (rank and tonumber(rank)) or 0
end

-- Apply talent modifiers to a debuff duration
-- Parameters:
--   spellID: The spell ID
--   baseDuration: The base duration (after combo points if applicable)
-- Returns: Modified duration, or baseDuration if no talent modifier applies
function CleveRoids.ApplyTalentModifier(spellID, baseDuration)
    if not spellID or not baseDuration then
        return baseDuration
    end

    local modifier = CleveRoids.talentModifiers[spellID]
    if not modifier then
        return baseDuration
    end

    local talentRank = 0
    local lookupMethod = "none"

    -- Method 1: Position-based lookup (preferred, locale-independent)
    if modifier.tab and modifier.id then
        local _, _, _, _, rank = GetTalentInfo(modifier.tab, modifier.id)
        talentRank = tonumber(rank) or 0
        if talentRank > 0 then
            lookupMethod = "position"
        end
    end

    -- Method 2: Name-based lookup (fallback for backwards compatibility)
    if talentRank == 0 and modifier.talent then
        talentRank = CleveRoids.GetTalentRank(modifier.talent)
        if talentRank > 0 then
            lookupMethod = "name"
        end
    end

    if talentRank == 0 then
        return baseDuration
    end

    local modifiedDuration = modifier.modifier(baseDuration, talentRank)

    if CleveRoids.debug then
        local talentName = modifier.talent or ("Tab " .. modifier.tab .. " ID " .. modifier.id)
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff00ff[Talent Modifier]|r %s (ID:%d): %ds -> %ds (talent: %s rank %d, %s)",
                SpellInfo(spellID) or "Unknown", spellID, baseDuration, modifiedDuration,
                talentName, talentRank, lookupMethod)
        )
    end

    return modifiedDuration
end

-- Helper function to register a talent modifier
-- Usage: CleveRoids.RegisterTalentModifier(spellID, talentName, modifierFunction)
function CleveRoids.RegisterTalentModifier(spellID, talentName, modifierFunc)
    if not spellID or not talentName or not modifierFunc then
        return false
    end

    CleveRoids.talentModifiers[spellID] = {
        talent = talentName,
        modifier = modifierFunc
    }

    return true
end

-- Diagnostic function to check talent modifier system
-- Usage: CleveRoids.DiagnoseTalentModifier(spellID, baseDuration)
function CleveRoids.DiagnoseTalentModifier(spellID, baseDuration)
    baseDuration = baseDuration or 10 -- Default test duration

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== Talent Modifier Diagnostic ===|r")

    -- Check if spellID is valid
    local spellName = SpellInfo(spellID)
    if not spellName then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ERROR: Invalid spell ID " .. tostring(spellID) .. "|r")
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("Spell: " .. spellName .. " (ID: " .. spellID .. ")")

    -- Check if talents are indexed
    if not CleveRoids.Talents then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ERROR: Talents table doesn't exist!|r")
        DEFAULT_CHAT_FRAME:AddMessage("Attempting to index talents...")
        if CleveRoids.IndexTalents then
            CleveRoids.IndexTalents()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Talents indexed.|r")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ERROR: IndexTalents function not found!|r")
            return
        end
    end

    local talentCount = 0
    for k, v in pairs(CleveRoids.Talents) do
        if type(k) == "string" and type(v) == "number" and v > 0 then
            talentCount = talentCount + 1
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("Talents indexed: " .. talentCount .. " talents found")

    -- Check if modifier is registered
    local modifier = CleveRoids.talentModifiers[spellID]
    if not modifier then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000No talent modifier registered for this spell|r")
        return
    end

    local talentDesc = modifier.talent or ("Tab " .. tostring(modifier.tab) .. " ID " .. tostring(modifier.id))
    DEFAULT_CHAT_FRAME:AddMessage("Modifier registered: " .. talentDesc)

    -- Check talent rank using BOTH methods
    local talentRank = 0
    local lookupMethod = "none"

    if modifier.tab and modifier.id then
        -- Position-based lookup (preferred)
        local _, name, _, _, rank = GetTalentInfo(modifier.tab, modifier.id)
        talentRank = tonumber(rank) or 0
        lookupMethod = "position"
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Position lookup (Tab " .. modifier.tab .. ", ID " .. modifier.id .. "):|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Talent name: " .. tostring(name))
        DEFAULT_CHAT_FRAME:AddMessage("  Rank: " .. talentRank)
    end

    if modifier.talent then
        -- Name-based lookup (fallback)
        local nameRank = CleveRoids.GetTalentRank(modifier.talent)
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaa00Name lookup (" .. modifier.talent .. "):|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Rank: " .. nameRank)

        -- Use name rank if position didn't work
        if talentRank == 0 and nameRank > 0 then
            talentRank = nameRank
            lookupMethod = "name"
        end

        -- Check if talent exists in table
        local directLookup = CleveRoids.Talents[modifier.talent]
        DEFAULT_CHAT_FRAME:AddMessage("  Direct table lookup: " .. tostring(directLookup))
    end

    DEFAULT_CHAT_FRAME:AddMessage("Final rank: " .. talentRank .. " (via " .. lookupMethod .. ")")

    if talentRank == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000You don't have " .. talentDesc .. "!|r")
        -- Show available talents for debugging
        DEFAULT_CHAT_FRAME:AddMessage("Available talents with ranks:")
        local shown = 0
        for name, rank in pairs(CleveRoids.Talents) do
            if type(name) == "string" and type(rank) == "number" and rank > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("  - " .. name .. ": " .. rank)
                shown = shown + 1
                if shown >= 10 then
                    DEFAULT_CHAT_FRAME:AddMessage("  ... (showing first 10)")
                    break
                end
            end
        end
    else
        -- Test the modifier
        local modifiedDuration = modifier.modifier(baseDuration, talentRank)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Test calculation:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Base: " .. baseDuration .. "s")
        DEFAULT_CHAT_FRAME:AddMessage("  Modified: " .. modifiedDuration .. "s")
        DEFAULT_CHAT_FRAME:AddMessage("  Bonus: +" .. (modifiedDuration - baseDuration) .. "s")

        -- Test actual application
        local applied = CleveRoids.ApplyTalentModifier(spellID, baseDuration)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Via ApplyTalentModifier:|r " .. applied .. "s")
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== End Diagnostic ===|r")
end

-- ============================================================================
-- EQUIPMENT MODIFIER SYSTEM
-- ============================================================================

-- Database of equipment modifiers for debuff durations
-- Structure: [spellID] = { slot = invSlotID, items = { [itemID] = modifierFunction } }
CleveRoids.equipmentModifiers = CleveRoids.equipmentModifiers or {}

-- DRUID equipment modifiers
-- Idol of Savagery (Black Morass Idol): Reduces Rip and Rake duration by 10% (multiplicative)
-- Item ID: 61699, Slot: 18 (Ranged/Relic)
local ripRakeIdolModifier = function(duration, itemID)
    if itemID == 61699 then
        -- Idol of Savagery: 10% reduction (multiply by 0.9)
        return duration * 0.9
    end
    return duration
end

-- Rip (all ranks)
CleveRoids.equipmentModifiers[1079] = { slot = 18, modifier = ripRakeIdolModifier }   -- Rip Rank 1
CleveRoids.equipmentModifiers[9492] = { slot = 18, modifier = ripRakeIdolModifier }   -- Rip Rank 2
CleveRoids.equipmentModifiers[9493] = { slot = 18, modifier = ripRakeIdolModifier }   -- Rip Rank 3
CleveRoids.equipmentModifiers[9752] = { slot = 18, modifier = ripRakeIdolModifier }   -- Rip Rank 4
CleveRoids.equipmentModifiers[9894] = { slot = 18, modifier = ripRakeIdolModifier }   -- Rip Rank 5
CleveRoids.equipmentModifiers[9896] = { slot = 18, modifier = ripRakeIdolModifier }   -- Rip Rank 6

-- Rake (all ranks)
CleveRoids.equipmentModifiers[1822] = { slot = 18, modifier = ripRakeIdolModifier }   -- Rake Rank 1
CleveRoids.equipmentModifiers[1823] = { slot = 18, modifier = ripRakeIdolModifier }   -- Rake Rank 2
CleveRoids.equipmentModifiers[1824] = { slot = 18, modifier = ripRakeIdolModifier }   -- Rake Rank 3
CleveRoids.equipmentModifiers[9904] = { slot = 18, modifier = ripRakeIdolModifier }   -- Rake Rank 4

-- Function to get equipped item ID in a specific slot
function CleveRoids.GetEquippedItemID(slotID)
    local itemLink = GetInventoryItemLink("player", slotID)
    if not itemLink then return nil end

    local _, _, itemID = string.find(itemLink, "item:(%d+)")
    return tonumber(itemID)
end

-- Apply equipment modifiers to a debuff duration
-- Parameters:
--   spellID: The spell ID
--   baseDuration: The base duration (after combo points and talents)
-- Returns: Modified duration, or baseDuration if no equipment modifier applies
function CleveRoids.ApplyEquipmentModifier(spellID, baseDuration)
    if not spellID or not baseDuration then
        return baseDuration
    end

    local modifier = CleveRoids.equipmentModifiers[spellID]
    if not modifier then
        return baseDuration
    end

    local itemID = CleveRoids.GetEquippedItemID(modifier.slot)
    if not itemID then
        return baseDuration
    end

    local modifiedDuration = modifier.modifier(baseDuration, itemID)

    if modifiedDuration ~= baseDuration and CleveRoids.debug then
        local itemName = "Unknown"
        local itemLink = GetInventoryItemLink("player", modifier.slot)
        if itemLink then
            itemName = string.match(itemLink, "%[(.-)%]") or "Unknown"
        end

        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff00ff[Equipment Modifier]|r %s (ID:%d): %ds -> %ds (item: %s [%d])",
                SpellInfo(spellID) or "Unknown", spellID, baseDuration, modifiedDuration,
                itemName, itemID)
        )
    end

    return modifiedDuration
end

-- Helper function to register an equipment modifier
-- Usage: CleveRoids.RegisterEquipmentModifier(spellID, slotID, modifierFunction)
function CleveRoids.RegisterEquipmentModifier(spellID, slotID, modifierFunc)
    if not spellID or not slotID or not modifierFunc then
        return false
    end

    CleveRoids.equipmentModifiers[spellID] = {
        slot = slotID,
        modifier = modifierFunc
    }

    return true
end

-- ============================================================================
-- SET BONUS MODIFIER SYSTEM
-- ============================================================================

-- Database of set bonus modifiers for debuff durations
-- Structure: [spellID] = { items = {itemID1, itemID2, ...}, threshold = X, modifier = function(baseDuration) }
CleveRoids.setbonusModifiers = CleveRoids.setbonusModifiers or {}

-- Function to count how many items from a set are currently equipped
function CleveRoids.CountEquippedSetItems(items)
    if not items or type(items) ~= "table" then return 0 end

    local count = 0
    -- Check all equipment slots (1-19)
    for slot = 1, 19 do
        local itemLink = GetInventoryItemLink("player", slot)
        if itemLink then
            local _, _, itemID = string.find(itemLink, "item:(%d+)")
            if itemID then
                itemID = tonumber(itemID)
                -- Check if this item is in the set
                for _, setItemID in ipairs(items) do
                    if itemID == setItemID then
                        count = count + 1
                        break
                    end
                end
            end
        end
    end

    return count
end

-- Apply set bonus modifiers to a debuff duration
-- Parameters:
--   spellID: The spell ID
--   baseDuration: The base duration (after combo points, talents, and equipment)
-- Returns: Modified duration, or baseDuration if no set bonus modifier applies
function CleveRoids.ApplySetBonusModifier(spellID, baseDuration)
    if not spellID or not baseDuration then
        return baseDuration
    end

    local modifier = CleveRoids.setbonusModifiers[spellID]
    if not modifier then
        return baseDuration
    end

    -- Check if player has enough set pieces equipped
    local equippedCount = CleveRoids.CountEquippedSetItems(modifier.items)
    if equippedCount < modifier.threshold then
        return baseDuration
    end

    local modifiedDuration = modifier.modifier(baseDuration)

    if modifiedDuration ~= baseDuration and CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cff00ffff[Set Bonus Modifier]|r %s (ID:%d): %.1fs -> %.1fs (%d/%d pieces)",
                SpellInfo(spellID) or "Unknown", spellID, baseDuration, modifiedDuration,
                equippedCount, modifier.threshold)
        )
    end

    return modifiedDuration
end

-- Helper function to register a set bonus modifier
-- Usage: CleveRoids.RegisterSetBonusModifier(spellID, itemsTable, threshold, modifierFunction)
function CleveRoids.RegisterSetBonusModifier(spellID, items, threshold, modifierFunc)
    if not spellID or not items or not threshold or not modifierFunc then
        return false
    end

    CleveRoids.setbonusModifiers[spellID] = {
        items = items,
        threshold = threshold,
        modifier = modifierFunc
    }

    return true
end

-- DRUID set bonus modifiers
-- Dreamwalker Regalia (4/9): Increases Moonfire duration by 3 seconds and Insect Swarm by 2 seconds
-- Item IDs: 47372, 47373, 47374, 47375, 47376, 47377, 47378, 47379, 47380
local dreamwalkerItems = { 47372, 47373, 47374, 47375, 47376, 47377, 47378, 47379, 47380 }
local dreamwalkerMoonfireModifier = function(base) return base + 3 end
local dreamwalkerInsectSwarmModifier = function(base) return base + 2 end

-- Moonfire (all ranks)
CleveRoids.setbonusModifiers[8921] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerMoonfireModifier }   -- Moonfire Rank 1
CleveRoids.setbonusModifiers[8924] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerMoonfireModifier }   -- Moonfire Rank 2
CleveRoids.setbonusModifiers[8925] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerMoonfireModifier }   -- Moonfire Rank 3
CleveRoids.setbonusModifiers[8926] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerMoonfireModifier }   -- Moonfire Rank 4
CleveRoids.setbonusModifiers[8927] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerMoonfireModifier }   -- Moonfire Rank 5
CleveRoids.setbonusModifiers[8928] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerMoonfireModifier }   -- Moonfire Rank 6
CleveRoids.setbonusModifiers[8929] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerMoonfireModifier }   -- Moonfire Rank 7
CleveRoids.setbonusModifiers[9833] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerMoonfireModifier }   -- Moonfire Rank 8
CleveRoids.setbonusModifiers[9834] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerMoonfireModifier }   -- Moonfire Rank 9
CleveRoids.setbonusModifiers[9835] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerMoonfireModifier }   -- Moonfire Rank 10

-- Insect Swarm (all ranks)
CleveRoids.setbonusModifiers[5570] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerInsectSwarmModifier }   -- Insect Swarm Rank 1
CleveRoids.setbonusModifiers[24974] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerInsectSwarmModifier }  -- Insect Swarm Rank 2
CleveRoids.setbonusModifiers[24975] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerInsectSwarmModifier }  -- Insect Swarm Rank 3
CleveRoids.setbonusModifiers[24976] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerInsectSwarmModifier }  -- Insect Swarm Rank 4
CleveRoids.setbonusModifiers[24977] = { items = dreamwalkerItems, threshold = 4, modifier = dreamwalkerInsectSwarmModifier }  -- Insect Swarm Rank 5

-- Haruspex's Garb (3/5): Increases Faerie Fire duration by 5 seconds
-- Item IDs: 19613, 19955, 19840, 19839, 19838
local haruspexItems = { 19613, 19955, 19840, 19839, 19838 }
local haruspexFaerieFireModifier = function(base) return base + 5 end

-- Faerie Fire (non-feral, all ranks)
CleveRoids.setbonusModifiers[770] = { items = haruspexItems, threshold = 3, modifier = haruspexFaerieFireModifier }    -- Faerie Fire Rank 1
CleveRoids.setbonusModifiers[778] = { items = haruspexItems, threshold = 3, modifier = haruspexFaerieFireModifier }    -- Faerie Fire Rank 2
CleveRoids.setbonusModifiers[9749] = { items = haruspexItems, threshold = 3, modifier = haruspexFaerieFireModifier }   -- Faerie Fire Rank 3
CleveRoids.setbonusModifiers[9907] = { items = haruspexItems, threshold = 3, modifier = haruspexFaerieFireModifier }   -- Faerie Fire Rank 4

-- ============================================================================
-- IMMUNITY TRACKING SYSTEM
-- ============================================================================

-- Initialize SavedVariables for immunity tracking
CleveRoids_ImmunityData = CleveRoids_ImmunityData or {}

-- Spell school constants
local IMMUNITY_SCHOOLS = {
    physical = 1,
    holy = 2,
    fire = 3,
    nature = 4,
    frost = 5,
    shadow = 6,
    arcane = 7,
    bleed = 8,
    unknown = 9,  -- For spells where we can't determine the school
}

-- Spells with split damage types (initial hit vs DoT/debuff)
-- GetSpellSchool() returns the debuff school by default for these spells
-- Users can explicitly check the initial damage school with [noimmune:physical]
local SPLIT_DAMAGE_SPELLS = {
    ["Rake"] = { initial = "physical", debuff = "bleed" },
    ["Pounce"] = { initial = "physical", debuff = "bleed" },
    ["Garrote"] = { initial = "physical", debuff = "bleed" },
}

-- Known non-damaging spells that won't be learned via SPELL_DAMAGE_EVENT
-- These need explicit school mapping to avoid pattern matching errors
-- (e.g., "Faerie Fire" contains "fire" but is actually arcane)
--
-- Add spells here if:
--   1. They don't deal damage (so won't trigger SPELL_DAMAGE_EVENT)
--   2. Their name causes false positives in pattern matching
--   3. You need accurate school detection for immunity checking
--
-- Format: ["Spell Name"] = "school" (without rank)
local KNOWN_NON_DAMAGING_SPELLS = {
    -- Druid
    ["Faerie Fire"] = "arcane",
    ["Moonfire"] = "arcane",  -- Initial hit deals damage, but debuff is arcane
    ["Insect Swarm"] = "nature",
    ["Abolish Poison"] = "nature",
    ["Remove Curse"] = "arcane",

    -- Mage
    ["Amplify Magic"] = "arcane",
    ["Dampen Magic"] = "arcane",
    ["Remove Lesser Curse"] = "arcane",
    ["Slow Fall"] = "arcane",
    ["Detect Magic"] = "arcane",

    -- Priest
    ["Dispel Magic"] = "holy",
    ["Cure Disease"] = "holy",
    ["Abolish Disease"] = "holy",
    ["Power Word: Fortitude"] = "holy",
    ["Power Word: Shield"] = "holy",
    ["Divine Spirit"] = "holy",
    ["Fear Ward"] = "holy",
    ["Resurrection"] = "holy",

    -- Paladin
    ["Cleanse"] = "holy",
    ["Purify"] = "holy",
    ["Divine Protection"] = "holy",
    ["Divine Shield"] = "holy",
    ["Blessing of Protection"] = "holy",
    ["Blessing of Freedom"] = "holy",
    ["Blessing of Sacrifice"] = "holy",
    ["Redemption"] = "holy",

    -- Warlock
    ["Banish"] = "shadow",
    ["Curse of Weakness"] = "shadow",
    ["Curse of Recklessness"] = "shadow",
    ["Curse of Tongues"] = "shadow",
    ["Amplify Curse"] = "shadow",
    ["Death Coil"] = "shadow",  -- Has damage component but often used for CC

    -- Shaman
    ["Cure Poison"] = "nature",
    ["Cure Disease"] = "nature",
    ["Purge"] = "nature",
    ["Ancestral Spirit"] = "nature",

    -- Hunter
    ["Aspect of the Hawk"] = "nature",
    ["Aspect of the Monkey"] = "nature",
    ["Aspect of the Cheetah"] = "nature",
    ["Aspect of the Pack"] = "nature",
    ["Aspect of the Wild"] = "nature",
}

-- Spell school mapping learned from Nampower damage events
-- This table maps spell IDs to their damage school (fire, frost, nature, shadow, arcane, holy, physical, bleed)
-- Persisted via SavedVariable (CleveRoids_SpellSchools) for accuracy across sessions
CleveRoids_SpellSchools = CleveRoids_SpellSchools or {}
CleveRoids.spellSchoolMapping = CleveRoids_SpellSchools  -- Alias for easier access

-- School ID to name mapping (from Nampower SPELL_DAMAGE_EVENT documentation)
-- Based on WoW 1.12.1 SpellSchools enum values (NOT bitmasks)
local SCHOOL_NAMES = {
    [0] = "physical",  -- SPELL_SCHOOL_NORMAL (Physical/Armor)
    [1] = "holy",      -- SPELL_SCHOOL_HOLY
    [2] = "fire",      -- SPELL_SCHOOL_FIRE
    [3] = "nature",    -- SPELL_SCHOOL_NATURE
    [4] = "frost",     -- SPELL_SCHOOL_FROST
    [5] = "shadow",    -- SPELL_SCHOOL_SHADOW
    [6] = "arcane"     -- SPELL_SCHOOL_ARCANE
}

-- Convert Nampower spell school ID to school name
-- Note: In vanilla WoW 1.12.1, schools are enum values (0-6), not bitmasks
-- Multi-school spells (like Frostfire Bolt) don't exist in vanilla
local function GetSchoolNameFromID(spellSchool)
    if not spellSchool then
        return "physical"
    end

    -- Direct lookup from enum
    local schoolName = SCHOOL_NAMES[spellSchool]
    if schoolName then
        return schoolName
    end

    -- Fallback for unknown school IDs
    return "physical"
end

-- Track damage events to learn spell schools automatically
-- This provides the most accurate school detection without relying on tooltip parsing
--
-- Nampower SPELL_DAMAGE_EVENT parameters:
--   arg1: targetGuid (string)
--   arg2: casterGuid (string)
--   arg3: spellId (int)
--   arg4: amount (int) - damage dealt
--   arg5: mitigationStr (string) - "absorb,block,resist"
--   arg6: hitInfo (int) - bitmask flags (0x02 = crit, 0x08 = split damage, etc.)
--   arg7: spellSchool (int) - enum 0-6 (0=physical, 1=holy, 2=fire, 3=nature, 4=frost, 5=shadow, 6=arcane)
--   arg8: effectAuraStr (string) - "effect1,effect2,effect3,auraType"
local function OnSpellDamageEvent()
    if not CleveRoids.hasNampower then return end

    local spellId = arg3
    local spellSchool = arg7

    if not spellId or not spellSchool then return end

    -- PERFORMANCE: Skip if already learned and finalized
    local currentSchool = CleveRoids.spellSchoolMapping[spellId]
    if currentSchool then
        -- If already learned as anything other than physical, we're done (can't be upgraded)
        if currentSchool ~= "physical" then
            return
        end
        -- If learned as physical, continue processing - might upgrade to bleed
    end

    -- Convert school enum (0-6) to name
    local schoolName = GetSchoolNameFromID(spellSchool)

    -- Special handling for bleeds:
    -- SPELL_AURA_PERIODIC_DAMAGE_PERCENT (89) indicates percentage-based DoT (bleeds)
    -- These show as "physical" school but are actually bleeds (ignore armor)
    local effectAuraStr = arg8
    if effectAuraStr then
        local _, _, _, auraType = string.find(effectAuraStr, "([^,]+),([^,]+),([^,]+),([^,]+)")
        if auraType and tonumber(auraType) == 89 then
            schoolName = "bleed"
        end
    end

    -- Check if this is a known bleed spell by name (fallback) - only if physical
    if schoolName == "physical" then
        local spellName = SpellInfo and SpellInfo(spellId)
        if spellName then
            local baseName = string.gsub(spellName, "%s*%(.-%)%s*$", "")
            local lower = string.lower(baseName)
            if string.find(lower, "rip") or string.find(lower, "rake") or string.find(lower, "rupture") or
               string.find(lower, "garrote") or string.find(lower, "rend") or string.find(lower, "deep wound") or
               string.find(lower, "hemorrhage") or string.find(lower, "pounce") then
                schoolName = "bleed"
            end
        end
    end

    -- PERFORMANCE: Skip if the detected school matches what we already know
    if currentSchool == schoolName then
        return  -- No change needed
    end

    -- Only update if not already known or if upgrading from physical to bleed
    if not currentSchool or (currentSchool == "physical" and schoolName == "bleed") then
        CleveRoids.spellSchoolMapping[spellId] = schoolName

        if CleveRoids.debug then
            local spellName = SpellInfo and SpellInfo(spellId) or "Unknown"
            CleveRoids.Print(string.format("|cff88ff88[School Learned]|r %s (ID:%d) = %s (raw:%d)",
                spellName, spellId, schoolName, spellSchool))
        end
    end
end

-- Register Nampower damage events for spell school tracking
if CleveRoids.hasNampower then
    local schoolTracker = CreateFrame("Frame", "CleveRoidsSchoolTracker")
    schoolTracker:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")
    schoolTracker:RegisterEvent("SPELL_DAMAGE_EVENT_OTHER")
    schoolTracker:SetScript("OnEvent", OnSpellDamageEvent)
end

-- Cache for spell school lookups
local spellSchoolCache = {}

-- Get the damage school of a spell
-- Parameters:
--   spellName: The name of the spell (with or without rank)
--   spellID: Optional spell ID for more accurate lookups
-- Returns: School name (fire, frost, nature, shadow, arcane, holy, physical, bleed) or nil
-- Priority:
--   1. Learned from Nampower damage events (most accurate)
--   2. Cached lookups
--   3. Split damage spell table (e.g., Rake = bleed debuff)
--   4. Known non-damaging spells table (e.g., Faerie Fire = arcane)
--   5. Tooltip scanning (player's spellbook only)
--   6. Name pattern matching (fallback, least accurate)
local function GetSpellSchool(spellName, spellID)
    if not spellName and not spellID then return nil end

    -- PRIORITY 1: Use learned school from Nampower damage events (most accurate)
    if spellID and CleveRoids.spellSchoolMapping[spellID] then
        return CleveRoids.spellSchoolMapping[spellID]
    end

    -- PRIORITY 2: If we have name but no ID, try to find ID and check mapping
    if spellName and not spellID then
        if CleveRoids.GetSpellIdForName then
            spellID = CleveRoids.GetSpellIdForName(spellName)
            if spellID and CleveRoids.spellSchoolMapping[spellID] then
                return CleveRoids.spellSchoolMapping[spellID]
            end
        end
    end

    -- If we only have spellID but no name, try to get name from SpellInfo
    if spellID and not spellName and SpellInfo then
        spellName = SpellInfo(spellID)
    end

    if not spellName then return nil end

    -- Remove rank information for cache consistency
    local baseName = string.gsub(spellName, "%s*%(.-%)%s*$", "")

    -- PRIORITY 3: Check cache
    if spellSchoolCache[baseName] then
        return spellSchoolCache[baseName]
    end

    -- PRIORITY 4: Check if this is a split damage spell (return debuff school by default)
    if SPLIT_DAMAGE_SPELLS[baseName] then
        local school = SPLIT_DAMAGE_SPELLS[baseName].debuff
        spellSchoolCache[baseName] = school
        return school
    end

    -- PRIORITY 5: Check known non-damaging spells
    -- These won't be learned via damage events and need explicit mapping
    if KNOWN_NON_DAMAGING_SPELLS[baseName] then
        local school = KNOWN_NON_DAMAGING_SPELLS[baseName]
        spellSchoolCache[baseName] = school
        return school
    end

    -- PRIORITY 6: Try to find spell in player's spellbook and scan tooltip
    local school = nil
    local spell = CleveRoids.GetSpell(baseName)

    if spell then
        -- Create tooltip if needed
        if not CleveRoidsSchoolTooltip then
            CreateFrame("GameTooltip", "CleveRoidsSchoolTooltip", nil, "GameTooltipTemplate")
            CleveRoidsSchoolTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
        end

        CleveRoidsSchoolTooltip:ClearLines()
        CleveRoidsSchoolTooltip:SetSpell(spell.spellSlot, spell.bookType)

        -- Scan tooltip for school keywords
        for i = 1, CleveRoidsSchoolTooltip:NumLines() do
            local line = _G["CleveRoidsSchoolTooltipTextLeft" .. i]
            if line then
                local text = string.lower(line:GetText() or "")

                if string.find(text, "bleed") then
                    school = "bleed"
                    break
                elseif string.find(text, "fire") or string.find(text, "flame") then
                    school = "fire"
                    break
                elseif string.find(text, "frost") or string.find(text, "ice") then
                    school = "frost"
                    break
                elseif string.find(text, "nature") or string.find(text, "poison") then
                    school = "nature"
                    break
                elseif string.find(text, "shadow") or string.find(text, "dark") then
                    school = "shadow"
                    break
                elseif string.find(text, "arcane") then
                    school = "arcane"
                    break
                elseif string.find(text, "holy") or string.find(text, "divine") then
                    school = "holy"
                    break
                end
            end
        end
    end

    -- PRIORITY 7: Fallback pattern matching for common spell name patterns
    -- NOTE: This is the lowest priority fallback - be specific to avoid false positives
    -- (e.g., "Faerie Fire" should not match as "fire" school)
    if not school then
        local lower = string.lower(baseName)

        -- Bleed effects (DoTs that ignore armor)
        if string.find(lower, "rip") or string.find(lower, "rake") or string.find(lower, "rupture") or
           string.find(lower, "garrote") or string.find(lower, "rend") or string.find(lower, "deep wound") or
           string.find(lower, "hemorrhage") or string.find(lower, "pounce") then
            school = "bleed"

        -- Arcane (check before "fire" to catch "Faerie Fire" and similar)
        elseif string.find(lower, "arcane") or string.find(lower, "polymorph") or
               string.find(lower, "faerie") or string.find(lower, "mana burn") then
            school = "arcane"

        -- Fire (specific patterns to avoid false positives)
        elseif string.find(lower, "^fire") or string.find(lower, " fire") or  -- Starts with or contains " fire"
               string.find(lower, "flame") or string.find(lower, "immolat") or
               string.find(lower, "scorch") or string.find(lower, "pyroblast") or
               string.find(lower, "ignite") or string.find(lower, "combustion") then
            school = "fire"

        -- Frost
        elseif string.find(lower, "frost") or string.find(lower, "ice") or
               string.find(lower, "blizzard") or string.find(lower, "freeze") or
               string.find(lower, "chill") then
            school = "frost"

        -- Nature
        elseif string.find(lower, "nature") or string.find(lower, "poison") or
               string.find(lower, "sting") or string.find(lower, "wrath") or
               string.find(lower, "starfire") or string.find(lower, "thorns") then
            school = "nature"

        -- Shadow
        elseif string.find(lower, "shadow") or string.find(lower, "curse") or
               string.find(lower, "corruption") or string.find(lower, "drain") or
               string.find(lower, "vampir") or string.find(lower, "affliction") then
            school = "shadow"

        -- Holy
        elseif string.find(lower, "holy") or string.find(lower, "smite") or
               string.find(lower, "exorcism") or string.find(lower, "consecrat") or
               string.find(lower, "judgment") or string.find(lower, "hammer of wrath") then
            school = "holy"

        -- Default to physical for melee attacks and unknown spells
        else
            school = "physical"
        end
    end

    -- Cache the result
    spellSchoolCache[baseName] = school
    return school
end

-- Public API: Get spell school by name and/or ID
-- Usage: CleveRoids.GetSpellSchool("Fireball") or CleveRoids.GetSpellSchool(nil, 133)
CleveRoids.GetSpellSchool = GetSpellSchool

-- Public API: Get spell school by ID only (convenience wrapper)
-- Usage: CleveRoids.GetSpellSchoolByID(133)
function CleveRoids.GetSpellSchoolByID(spellID)
    return GetSpellSchool(nil, spellID)
end

-- Get current buffs on a unit
local function GetUnitBuffs(unit)
    local buffs = {}
    if not CleveRoids.hasSuperwow then return buffs end

    for i = 1, 32 do
        local texture, stacks, spellID = UnitBuff(unit, i)
        if not texture then break end

        if spellID then
            local buffName = SpellInfo(spellID)
            if buffName then
                buffs[buffName] = true
            end
        end
    end

    return buffs
end

-- Record an immunity (permanent or buff-based)
-- Parameters:
--   npcName: Name of the NPC that is immune
--   spellName: Name of the spell that was resisted/immune
--   conditionalBuff: Optional buff name required for the immunity
--   spellID: Optional spell ID for more accurate school detection
local function RecordImmunity(npcName, spellName, conditionalBuff, spellID)
    if not npcName or (not spellName and not spellID) or npcName == "" then
        return
    end

    -- Try to get school using spell ID if available (most accurate)
    local school = GetSpellSchool(spellName, spellID)

    -- If we can't determine the school, use "unknown" and store the spell name
    if not school then
        school = "unknown"
        if CleveRoids.debug then
            CleveRoids.Print("|cffff9900[Unknown School]|r Could not determine school for: " .. spellName)
        end
    end

    -- Initialize school table
    if not CleveRoids_ImmunityData[school] then
        CleveRoids_ImmunityData[school] = {}
    end

    -- Record immunity
    if conditionalBuff then
        -- Buff-based immunity
        local immunityData = { buff = conditionalBuff }
        if school == "unknown" then
            immunityData.spell = spellName
        end
        CleveRoids_ImmunityData[school][npcName] = immunityData

        if CleveRoids.debug then
            if school == "unknown" then
                CleveRoids.Print("|cffff6600Immunity:|r " .. npcName .. " is immune to '" .. spellName .. "' (unknown school) when buffed with: " .. conditionalBuff)
            else
                CleveRoids.Print("|cffff6600Immunity:|r " .. npcName .. " is immune to " .. school .. " when buffed with: " .. conditionalBuff)
            end
        end
    else
        -- Permanent immunity
        local immunityData
        if school == "unknown" then
            -- Store spell name for unknown school immunities
            immunityData = { spell = spellName }
        else
            immunityData = true
        end

        if CleveRoids_ImmunityData[school][npcName] ~= immunityData then
            CleveRoids_ImmunityData[school][npcName] = immunityData
            if CleveRoids.debug then
                if school == "unknown" then
                    CleveRoids.Print("|cffff6600Immunity:|r " .. npcName .. " is permanently immune to '" .. spellName .. "' (unknown school)")
                else
                    CleveRoids.Print("|cffff6600Immunity:|r " .. npcName .. " is permanently immune to " .. school)
                end
            end
        end
    end
end

-- Combat log parser for immunity detection
-- Handles both RAW_COMBATLOG (arg1=formatted, arg2=raw) and CHAT_MSG events (arg1=formatted only)
local function ParseImmunityCombatLog()
    local message = arg1      -- Formatted chat message text
    local rawMessage = arg2   -- Raw message (only present for RAW_COMBATLOG)

    if not message then return end

    -- PERFORMANCE: Quick length and content checks
    -- Minimum immunity message: "X is immune" = ~11 chars
    if string.len(message) < 11 then return end

    -- Only process immunity-related messages
    -- IMPORTANT: Exclude partial resists (messages containing "resisted)" with a closing parenthesis)
    -- Example partial resist: "Your Fireball hit Enemy for 500. (250 resisted)"
    local hasImmune = string.find(message, "immune")
    local hasResisted = string.find(message, "resisted")

    if not (hasImmune or hasResisted) then
        return
    end

    -- Skip partial resist messages (they contain "resisted)" not "resisted by" or "resists")
    if hasResisted and string.find(message, "resisted%)") then
        return
    end

    -- Debug: Show the message we're parsing
    if CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[Immunity Parse]|r " .. message)
    end

    local spellName = nil
    local targetName = nil
    local school = nil

    -- Pattern 1: "Your [Spell] fails. Y is immune."
    local _, _, extractedSpell, extractedTarget = string.find(message, "Your%s+(.-)%s+fails%.%s+(.-)%s+is immune")
    if extractedSpell and extractedTarget then
        spellName = extractedSpell
        targetName = extractedTarget
    end

    -- Pattern 2: "Your [Spell] failed. Y is immune." (past tense)
    if not spellName or not targetName then
        _, _, extractedSpell, extractedTarget = string.find(message, "Your%s+(.-)%s+failed%.%s+(.-)%s+is immune")
        if extractedSpell and extractedTarget then
            spellName = extractedSpell
            targetName = extractedTarget
        end
    end

    -- Pattern 3: "Y is immune to [School] damage"
    if not targetName then
        _, _, extractedTarget = string.find(message, "^(.-)%s+is immune to")
        if extractedTarget then
            targetName = extractedTarget
        end
    end

    -- Pattern 4: "Y is immune" (generic)
    if not targetName then
        _, _, extractedTarget = string.find(message, "^(.-)%s+is immune")
        if extractedTarget then
            targetName = extractedTarget
        end
    end

    -- Pattern 5: "Your [Spell] was resisted by Y"
    if not spellName or not targetName then
        _, _, extractedSpell, extractedTarget = string.find(message, "Your%s+(.-)%s+was resisted by (.-)%.")
        if extractedSpell and extractedTarget then
            spellName = extractedSpell
            targetName = extractedTarget
        end
    end

    -- Pattern 6: "Y resists your [Spell]"
    if not spellName or not targetName then
        _, _, extractedTarget, extractedSpell = string.find(message, "^(.-)%s+resists your (.-)%.")
        if extractedSpell and extractedTarget then
            spellName = extractedSpell
            targetName = extractedTarget
        end
    end

    -- Extract damage school if explicitly mentioned in message
    if string.find(message, "is immune to") then
        local lowerMsg = string.lower(message)
        if string.find(lowerMsg, "fire") then
            school = "fire"
        elseif string.find(lowerMsg, "frost") then
            school = "frost"
        elseif string.find(lowerMsg, "nature") then
            school = "nature"
        elseif string.find(lowerMsg, "shadow") then
            school = "shadow"
        elseif string.find(lowerMsg, "arcane") then
            school = "arcane"
        elseif string.find(lowerMsg, "holy") then
            school = "holy"
        elseif string.find(lowerMsg, "physical") then
            school = "physical"
        elseif string.find(lowerMsg, "bleed") then
            school = "bleed"
        end
    end

    -- Fallback: Try to get target from current target if message mentions them
    if not targetName and UnitExists("target") then
        local currentTargetName = UnitName("target")
        if currentTargetName and string.find(message, currentTargetName) then
            targetName = currentTargetName
        end
    end

    -- If we have a school but no spell, use the school directly
    if school and targetName and not spellName then
        -- Record immunity by school
        if not CleveRoids_ImmunityData[school] then
            CleveRoids_ImmunityData[school] = {}
        end

        -- Check for conditional buff
        local buffs = nil
        if UnitExists("target") and UnitName("target") == targetName then
            buffs = GetUnitBuffs("target")
        end

        if buffs and next(buffs) then
            local buffCount = 0
            local singleBuff = nil
            for buff, _ in pairs(buffs) do
                buffCount = buffCount + 1
                singleBuff = buff
                if buffCount > 1 then
                    singleBuff = nil
                    break
                end
            end

            if singleBuff then
                CleveRoids_ImmunityData[school][targetName] = { buff = singleBuff }
                if CleveRoids.debug then
                    CleveRoids.Print("|cffff6600Immunity:|r " .. targetName .. " is immune to " .. school .. " when buffed with: " .. singleBuff)
                end
                return
            end
        end

        -- Permanent immunity
        if CleveRoids_ImmunityData[school][targetName] ~= true then
            CleveRoids_ImmunityData[school][targetName] = true
            if CleveRoids.debug then
                CleveRoids.Print("|cffff6600Immunity:|r " .. targetName .. " is permanently immune to " .. school)
            end
        end
        return
    end

    -- If we have a spell and target, record immunity
    if spellName and targetName then
        -- Debug: Show what we extracted
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff9900[Immunity Detected]|r Spell: %s | Target: %s | School: %s",
                    spellName, targetName, school or "auto-detect")
            )
        end

        -- Check if target has any buffs (for conditional immunity)
        local buffs = nil
        if UnitExists("target") and UnitName("target") == targetName then
            buffs = GetUnitBuffs("target")
        end

        -- If target has exactly one buff, assume it's causing the immunity
        if buffs and next(buffs) then
            local buffCount = 0
            local singleBuff = nil
            for buff, _ in pairs(buffs) do
                buffCount = buffCount + 1
                singleBuff = buff
                if buffCount > 1 then
                    singleBuff = nil
                    break
                end
            end

            if singleBuff then
                -- Try to get spell ID for more accurate school detection
                local spellID = CleveRoids.GetSpellIdForName and CleveRoids.GetSpellIdForName(spellName)
                RecordImmunity(targetName, spellName, singleBuff, spellID)
                return
            end
        end

        -- No single buff detected, record as permanent immunity
        local spellID = CleveRoids.GetSpellIdForName and CleveRoids.GetSpellIdForName(spellName)
        RecordImmunity(targetName, spellName, nil, spellID)
    end
end

-- Check if a unit is immune to a spell or damage school
-- Supports: CheckImmunity(unitId, "Flame Shock") or CheckImmunity(unitId, "fire")
function CleveRoids.CheckImmunity(unitId, spellOrSchool)
    if not unitId or not UnitExists(unitId) then
        return false
    end

    -- Universal debuff-based immunities (Banish, etc.)
    -- Banish makes target immune to most damage schools (not all spells)
    if CleveRoids.hasSuperwow then
        local hasBanish = false

        -- Check debuffs first (Banish: 710 = Rank 1, 18647 = Rank 2)
        for i = 1, 16 do
            local texture, stacks, dtype, spellID = UnitDebuff(unitId, i)
            if not texture then break end

            if spellID == 710 or spellID == 18647 then
                hasBanish = true
                break
            end
        end

        -- Overflow handling: debuffs can overflow into buffs on NPCs
        if not hasBanish and not UnitIsPlayer(unitId) then
            for i = 1, 32 do
                local texture, stacks, spellID = UnitBuff(unitId, i)
                if not texture then break end

                if spellID == 710 or spellID == 18647 then
                    hasBanish = true
                    break
                end
            end
        end

        -- If Banished, check what's being tested for immunity
        if hasBanish then
            -- Check if input is a damage school or spell
            local inputLower = string.lower(spellOrSchool)

            -- Banished targets are immune to all damage schools
            -- (but Banish itself can be recast immediately)
            local banishImmuneSchools = {
                fire = true,
                frost = true,
                nature = true,
                shadow = true,
                arcane = true,
                holy = true,
                physical = true,
                bleed = true
            }

            if banishImmuneSchools[inputLower] then
                return true
            end

            -- For specific spells, determine their school and check
            if not IMMUNITY_SCHOOLS[inputLower] then
                local spellSchool = GetSpellSchool(spellOrSchool)
                if spellSchool and banishImmuneSchools[spellSchool] then
                    return true
                end
            end
        end
    end

    -- Only works on NPCs for NPC-specific immunities
    if UnitIsPlayer(unitId) then
        return false
    end

    local targetName = UnitName(unitId)
    if not targetName or targetName == "" then
        return false
    end

    if not spellOrSchool or spellOrSchool == "" then
        return false
    end

    -- Check if input is a spell school name directly
    local inputLower = string.lower(spellOrSchool)
    local school = nil
    local checkSpellName = nil  -- For unknown school, we need to match spell name too

    if IMMUNITY_SCHOOLS[inputLower] then
        -- Input is a damage school name (fire, frost, nature, etc.)
        school = inputLower
    else
        -- Input is a spell name, need to determine its school
        checkSpellName = spellOrSchool  -- Save the spell name for unknown school check
        school = GetSpellSchool(spellOrSchool)
        if not school then
            school = "unknown"  -- If we can't determine school, check unknown category
        end
    end

    -- Check immunity data for this school
    if not CleveRoids_ImmunityData[school] then
        return false
    end

    local immunityData = CleveRoids_ImmunityData[school][targetName]

    -- No immunity data for this NPC
    if not immunityData then
        return false
    end

    -- Permanent immunity
    if immunityData == true then
        return true
    end

    -- Table-based immunity data (buff-based or unknown school with spell name)
    if type(immunityData) == "table" then
        -- For unknown school, check if spell name matches
        if school == "unknown" and immunityData.spell and checkSpellName then
            if immunityData.spell ~= checkSpellName then
                return false  -- NPC is immune to a different spell, not this one
            end
        end

        -- Check buff-based immunity (if NPC has the required buff)
        if immunityData.buff then
            local requiredBuff = immunityData.buff

            -- Check target's buffs
            if CleveRoids.hasSuperwow then
                for i = 1, 32 do
                    local texture, stacks, spellID = UnitBuff(unitId, i)
                    if not texture then break end

                    if spellID then
                        local buffName = SpellInfo(spellID)
                        if buffName and buffName == requiredBuff then
                            return true
                        end
                    end
                end
            end

            -- Buff not found, not currently immune
            return false
        end

        -- Unknown school permanent immunity (has spell name, no buff requirement)
        if immunityData.spell and not immunityData.buff then
            return true  -- Permanent immunity to this specific spell
        end
    end

    return false
end

-- Management functions for immunity data
function CleveRoids.ListImmunities(school)
    if school then
        school = string.lower(school)
        if not CleveRoids_ImmunityData[school] then
            CleveRoids.Print("No immunity data for school: " .. school)
            return
        end

        CleveRoids.Print("|cff00ff00" .. school .. " immunities:|r")
        local count = 0
        for npc, data in pairs(CleveRoids_ImmunityData[school]) do
            if data == true then
                CleveRoids.Print("  - " .. npc .. " (permanent)")
            elseif type(data) == "table" then
                if data.buff and data.spell then
                    -- Unknown school with conditional buff
                    CleveRoids.Print("  - " .. npc .. " immune to '" .. data.spell .. "' (when buffed: " .. data.buff .. ")")
                elseif data.buff then
                    -- Known school with conditional buff
                    CleveRoids.Print("  - " .. npc .. " (when buffed: " .. data.buff .. ")")
                elseif data.spell then
                    -- Unknown school, permanent
                    CleveRoids.Print("  - " .. npc .. " immune to '" .. data.spell .. "' (permanent)")
                end
            end
            count = count + 1
        end
        CleveRoids.Print("Total: " .. count)
    else
        -- List all schools
        CleveRoids.Print("|cff00ff00Immunity Data by School:|r")
        for schoolName, npcs in pairs(CleveRoids_ImmunityData) do
            local count = 0
            for _ in pairs(npcs) do
                count = count + 1
            end
            if count > 0 then
                CleveRoids.Print("  " .. schoolName .. ": " .. count .. " NPCs")
            end
        end
    end
end

function CleveRoids.ClearImmunities(school)
    if school then
        school = string.lower(school)
        CleveRoids_ImmunityData[school] = {}
        CleveRoids.Print("Cleared " .. school .. " immunity data")
    else
        CleveRoids_ImmunityData = {}
        CleveRoids.Print("Cleared all immunity data")
    end
end

function CleveRoids.AddImmunity(npcName, school, buffName)
    if not npcName or not school then
        CleveRoids.Print("Usage: /cleveroid addimmune <npc name> <school> [buff name]")
        CleveRoids.Print("Schools: fire, frost, nature, shadow, arcane, holy, physical, bleed, unknown")
        return
    end

    school = string.lower(school)
    if not IMMUNITY_SCHOOLS[school] then
        CleveRoids.Print("Invalid school. Use: fire, frost, nature, shadow, arcane, holy, physical, bleed, unknown")
        return
    end

    if not CleveRoids_ImmunityData[school] then
        CleveRoids_ImmunityData[school] = {}
    end

    if buffName and buffName ~= "" then
        CleveRoids_ImmunityData[school][npcName] = { buff = buffName }
        CleveRoids.Print("Added: " .. npcName .. " is immune to " .. school .. " when buffed with: " .. buffName)
    else
        CleveRoids_ImmunityData[school][npcName] = true
        CleveRoids.Print("Added: " .. npcName .. " is permanently immune to " .. school)
    end
end

function CleveRoids.RemoveImmunity(npcName, school)
    if not npcName or not school then
        CleveRoids.Print("Usage: /cleveroid removeimmune <npc name> <school>")
        return
    end

    school = string.lower(school)
    if CleveRoids_ImmunityData[school] and CleveRoids_ImmunityData[school][npcName] then
        CleveRoids_ImmunityData[school][npcName] = nil
        CleveRoids.Print("Removed: " .. npcName .. " from " .. school .. " immunities")
    else
        CleveRoids.Print("Not found: " .. npcName .. " in " .. school .. " immunities")
    end
end

-- Register combat log events for immunity tracking
-- PERFORMANCE: Only use RAW_COMBATLOG and SPELL_FAILURE to avoid spam from damage events
-- CHAT_MSG_SPELL_*_DAMAGE fires on EVERY hit/resist (100+ times/second in combat)
local immunityFrame = CreateFrame("Frame", "CleveRoidsImmunityFrame")
immunityFrame:RegisterEvent("RAW_COMBATLOG")
immunityFrame:RegisterEvent("CHAT_MSG_SPELL_FAILURE")
immunityFrame:SetScript("OnEvent", function()
    if event == "RAW_COMBATLOG" or event == "CHAT_MSG_SPELL_FAILURE" then
        ParseImmunityCombatLog()
    end
end)

-- ============================================================================
-- REACTIVE ABILITY PROC TRACKING SYSTEM
-- ============================================================================
-- Tracks reactive ability procs independently of stance/usability
-- Allows detection of Overpower/Revenge/Riposte procs even when not in correct stance

-- Table to store reactive proc states with expiry times and target GUIDs
-- Structure: { spellName = { expiry = time, targetGUID = guid } }
CleveRoids.reactiveProcs = CleveRoids.reactiveProcs or {}

-- Table to track which reactive spells we've seen proc at least once
-- This helps us decide whether to use combat log tracking vs fallback methods
CleveRoids.reactiveProcsEverSeen = CleveRoids.reactiveProcsEverSeen or {}

-- Proc durations (in seconds)
-- Overpower and Revenge: 4 seconds
-- Riposte: 5 seconds (keeping at 5 for safety, can be adjusted)
local REACTIVE_PROC_DURATION = 4.0

-- Reactive ability trigger patterns for combat log
local reactivePatterns = {
    Overpower = {
        -- Procs when ENEMY dodges YOUR attack (auto or ability)
        patterns = {
            -- Auto attack dodges
            "(.+) dodges",                  -- English: "Target dodges"
            "(.+) weicht aus",              -- German
            "(.+) esquive",                 -- French
            "(.+)이%(가%) 회피",            -- Korean
            "躲闪了(.+)",                   -- Chinese Simplified
            "躲閃了(.+)",                   -- Chinese Traditional

            -- Ability dodges
            "was dodged by",                -- English: "Your Mortal Strike was dodged by Target"
            "wurde von (.+) ausgewichen",   -- German
            "a été esquivé par",            -- French
            "을%(를%) (.+)이%(가%) 회피",   -- Korean
            "被(.+)躲闪",                   -- Chinese Simplified
            "被(.+)躲閃",                   -- Chinese Traditional
        },
        type = "enemy_dodge",
        requiresTargetGUID = true,
        duration = 4.0
    },
    Riposte = {
        -- Procs when YOU parry an enemy attack
        patterns = {
            "You parry",           -- English: "You parry X's Y"
            "Ihr pariert",         -- German
            "Vous parez",          -- French
            "막아냈습니다",        -- Korean
            "你招架了",            -- Chinese Simplified
            "你招架了",            -- Chinese Traditional
        },
        type = "player_parry",
        requiresTargetGUID = true,  -- Track which enemy you parried
        duration = 4.0  -- 5 second proc window (estimated, may be 4s)
    },
    Revenge = {
        -- Procs when YOU block, dodge, or parry an enemy attack (any stance)
        -- Does NOT require targeting the triggering mob - can use on any target
        patterns = {
            "You block",           -- English: "You block X's Y"
            "You dodge",           -- English: "You dodge X's Y"
            "You parry",           -- English: "You parry X's Y"
            "hits you.*%(%d+ blocked%)",  -- English: "X hits you for Y (Z blocked)" - more specific
            "Ihr blockt",          -- German block
            "Ihr weicht aus",      -- German dodge
            "Ihr pariert",         -- German parry
            "Vous bloquez",        -- French block
            "Vous esquivez",       -- French dodge
            "Vous parez",          -- French parry
            "막았습니다",          -- Korean block
            "회피했습니다",        -- Korean dodge
            "막아냈습니다",        -- Korean parry
            "你格挡了",            -- Chinese Simplified block
            "你躲闪了",            -- Chinese Simplified dodge
            "你招架了",            -- Chinese Simplified parry
            "你格擋了",            -- Chinese Traditional block
            "你躲閃了",            -- Chinese Traditional dodge
            "你招架了",            -- Chinese Traditional parry
        },
        type = "player_avoid",
        requiresTargetGUID = false,  -- Revenge usable on any target once procced
        duration = 4.0
    }
}

-- Set a reactive proc state with optional target GUID
function CleveRoids.SetReactiveProc(spellName, duration, targetGUID)
    duration = duration or REACTIVE_PROC_DURATION
    CleveRoids.reactiveProcs[spellName] = {
        expiry = GetTime() + duration,
        targetGUID = targetGUID
    }
    -- Mark that we've seen this reactive spell proc at least once
    CleveRoids.reactiveProcsEverSeen[spellName] = true
end

-- Check if a reactive proc is active (with optional GUID check)
function CleveRoids.HasReactiveProc(spellName)
    local procData = CleveRoids.reactiveProcs[spellName]
    if not procData or not procData.expiry then
        return false
    end

    local now = GetTime()
    if now >= procData.expiry then
        -- Expired, clear it
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff9900[HasReactiveProc]|r %s: EXPIRED - clearing and queuing update", spellName)
            )
        end
        CleveRoids.reactiveProcs[spellName] = nil
        -- Queue action update to refresh icon state
        CleveRoids.QueueActionUpdate()
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff9900[HasReactiveProc]|r Action update queued, isActionUpdateQueued = %s", tostring(CleveRoids.isActionUpdateQueued))
            )
        end
        return false
    end

    -- If proc has a target GUID requirement, check if current target matches
    if procData.targetGUID then
        local _, targetGUID = UnitExists("target")
        if not targetGUID or targetGUID ~= procData.targetGUID then
            return false
        end
    end

    return true
end

-- Clear a reactive proc
function CleveRoids.ClearReactiveProc(spellName)
    CleveRoids.reactiveProcs[spellName] = nil
end

-- Parse combat log for reactive ability triggers
function CleveRoids.ParseReactiveCombatLog()
    if not arg1 then return end

    local message = arg1

    -- PERFORMANCE: Early return if no reactive spells configured
    if not CleveRoids.reactiveSpells or not next(CleveRoids.reactiveSpells) then
        return
    end

    -- PERFORMANCE: Quick keyword check - most messages won't match
    local lowerMsg = lower(message)
    if not (strfind(lowerMsg, "dodge") or strfind(lowerMsg, "parry") or strfind(lowerMsg, "block")) then
        return
    end

    local _, targetGUID = UnitExists("target")

    -- Check each reactive ability's trigger patterns
    for spellName, config in pairs(reactivePatterns) do
        -- Check if this is a known reactive spell and player has it
        local hasSpell = false
        if CleveRoids.reactiveSpells and CleveRoids.reactiveSpells[spellName] then
            -- Check if player knows this spell (any rank)
            hasSpell = (CleveRoids.GetSpell and CleveRoids.GetSpell(spellName)) or
                       (CleveRoids.Spells and CleveRoids.Spells[spellName]) or
                       false
        end

        if hasSpell then
            for _, pattern in ipairs(config.patterns) do
                if strfind(message, pattern) then
                    -- Found a trigger event (works in any stance)
                    local guid = config.requiresTargetGUID and targetGUID or nil
                    local duration = config.duration or REACTIVE_PROC_DURATION
                    CleveRoids.SetReactiveProc(spellName, duration, guid)

                    -- DEBUG: Show what triggered the proc
                    if CleveRoids.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(
                            string.format("|cffff9900[REACTIVE PROC]|r %s triggered by: |cffffffff%s|r (pattern: |cffcccccc%s|r)",
                                spellName, message, pattern)
                        )
                    end

                    -- Update action buttons to reflect new state
                    CleveRoids.QueueActionUpdate()
                    break
                end
            end
        end
    end
end

-- Clear reactive proc when spell is cast
function CleveRoids.ClearReactiveProcOnCast(spellName)
    if not spellName then return end

    -- Check if this is a reactive spell
    if CleveRoids.reactiveSpells and CleveRoids.reactiveSpells[spellName] then
        CleveRoids.ClearReactiveProc(spellName)
        CleveRoids.QueueActionUpdate()
    end
end

-- Hook UNIT_CASTEVENT to clear reactive procs
local originalUnitCastEvent = CleveRoids.Frame and CleveRoids.Frame.UNIT_CASTEVENT
if originalUnitCastEvent then
    CleveRoids.Frame.UNIT_CASTEVENT = function(...)
        -- Call original handler first
        if type(originalUnitCastEvent) == "function" then
            originalUnitCastEvent(unpack(arg))
        end

        -- Clear reactive proc on spell cast start
        if arg1 == "player" and arg2 == "START" and arg4 then
            CleveRoids.ClearReactiveProcOnCast(arg4)
        end
    end
end

-- Register combat log event for reactive proc tracking
-- PERFORMANCE: Removed CHAT_MSG_SPELL_SELF_DAMAGE (fires on every spell hit - not needed for dodge/parry/block)
-- CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS is needed for partial block detection (Revenge)
local reactiveFrame = CreateFrame("Frame", "CleveRoidsReactiveFrame")
reactiveFrame:RegisterEvent("RAW_COMBATLOG")
reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
reactiveFrame:SetScript("OnEvent", function()
    if event == "RAW_COMBATLOG" or
       event == "CHAT_MSG_COMBAT_SELF_MISSES" or
       event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" or
       event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS" then
        CleveRoids.ParseReactiveCombatLog()
    end
end)
