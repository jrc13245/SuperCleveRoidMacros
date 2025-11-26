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

  -- NOTE: Rip removed - handled by ComboPointTracker (base 10s + 2s per CP)

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
    DEFAULT_CHAT_FRAME:AddMessage(
      string.format("|cff00ffff[DEBUG AddEffect]|r %s (ID:%d) stored duration:%ds on %s",
        spellName, spellID, duration, unitName or "Unknown")
    )
  end
end

function lib:UnitDebuff(unit, id, filterCaster)
  local _, guid = UnitExists(unit)
  if not guid then return nil end

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
      if filterCaster and caster ~= filterCaster then
        return nil
      end
    else
      lib.objects[guid][spellID] = nil
    end
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
      local duration = lib:GetDuration(spellID)
      if duration > 0 then
        if not (lib.objects[guid] and lib.objects[guid][spellID]) then
          -- For combo spells, try to use the highest learned duration as a fallback
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
          lib:AddEffect(guid, unitName, spellID, duration, stacks)
        end
      end
    end
  end

  for i=1, 32 do
    local tex, stacks, spellID = UnitBuff(unit, i)
    if not tex then break end

    if spellID then
      local duration = lib:GetDuration(spellID)
      if duration > 0 then
        if not (lib.objects[guid] and lib.objects[guid][spellID]) then
          -- For combo spells, try to use the highest learned duration as a fallback
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
          lib:AddEffect(guid, unitName, spellID, duration, stacks)
        end
      end
    end
  end
end

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
        -- If so, refresh the last Rip and Rake durations (only if debuffs are active)
        if CleveRoids.FerociousBiteSpellIDs and CleveRoids.FerociousBiteSpellIDs[spellID] then
          -- Get combo points used (capture before consumption)
          local biteComboPoints = CleveRoids.lastComboPoints or 0

          -- Check if player has Carnage talent at rank 2
          -- Carnage: Tab 2 (Feral Combat), Talent 17
          local carnageRank = 0
          local _, _, _, _, rank = GetTalentInfo(2, 17)
          carnageRank = tonumber(rank) or 0

          -- Carnage 2/2+: Ferocious Bite at 5 CP refreshes Rip and Rake back to their original duration
          if carnageRank >= 2 and biteComboPoints == 5 then
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

            -- Only refresh debuffs if they're currently active on the target
            if lib.objects[targetGUID] then
              -- Try to refresh Rip
              if CleveRoids.lastRipCast and CleveRoids.lastRipCast.duration and
                 CleveRoids.lastRipCast.targetGUID == targetGUID then
                -- Find which Rip rank is currently active
                for ripSpellID, _ in pairs(CleveRoids.RipSpellIDs) do
                  if lib.objects[targetGUID][ripSpellID] then
                    -- Found an active Rip, refresh it with the saved duration
                    local ripDuration = CleveRoids.lastRipCast.duration
                    local ripComboPoints = CleveRoids.lastRipCast.comboPoints or 5

                    -- Get spell name for pfUI
                    local ripSpellName = SpellInfo(ripSpellID)
                    local baseName = ripSpellName and string.gsub(ripSpellName, "%s*%(Rank %d+%)", "") or "Rip"

                    -- Update tracking tables for pfUI hooks
                    if CleveRoids.ComboPointTracking then
                      CleveRoids.ComboPointTracking[baseName] = {
                        combo_points = ripComboPoints,
                        duration = ripDuration,
                        cast_time = GetTime(),
                        target = targetName,
                        confirmed = true
                      }
                    end

                    -- Store duration override for pfUI hooks
                    if not CleveRoids.carnageDurationOverrides then
                      CleveRoids.carnageDurationOverrides = {}
                    end
                    CleveRoids.carnageDurationOverrides[ripSpellID] = {
                      duration = ripDuration,
                      timestamp = GetTime(),
                      targetGUID = targetGUID
                    }

                    -- Update pfUI's debuff timer directly
                    if pfUI and pfUI.api and pfUI.api.libdebuff then
                      local pflib = pfUI.api.libdebuff
                      if pflib.objects and pflib.objects[targetName] then
                        local updated = false
                        local currentLevel = UnitLevel("target") or 0

                        -- Update at all levels where the debuff exists
                        for level, effects in pairs(pflib.objects[targetName]) do
                          if type(effects) == "table" and effects[baseName] then
                            local entry = effects[baseName]
                            entry.duration = ripDuration
                            entry.start = GetTime()
                            entry.caster = "player"
                            if entry.tick then entry.tick = GetTime() end
                            updated = true
                          end
                        end

                        -- Ensure entry exists at current UnitLevel
                        if updated then
                          if not pflib.objects[targetName][currentLevel] then
                            pflib.objects[targetName][currentLevel] = {}
                          end
                          if not pflib.objects[targetName][currentLevel][baseName] then
                            pflib.objects[targetName][currentLevel][baseName] = {
                              effect = baseName,
                              duration = ripDuration,
                              start = GetTime(),
                              caster = "player"
                            }
                          end
                          if pflib.UpdateUnits then pflib:UpdateUnits() end
                        elseif pflib.AddEffect then
                          pflib:AddEffect(targetName, currentLevel, baseName, ripDuration, "player")
                        end
                      end
                    end

                    -- Update internal tracker
                    if lib.objects[targetGUID] and lib.objects[targetGUID][ripSpellID] then
                      lib.objects[targetGUID][ripSpellID].duration = ripDuration
                      lib.objects[targetGUID][ripSpellID].start = GetTime()
                      lib.objects[targetGUID][ripSpellID].expiry = GetTime() + ripDuration
                    end

                    if CleveRoids.debug then
                      DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cffff00ff[Carnage]|r Refreshed Rip: %ds on %s",
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

                    -- Get spell name for pfUI
                    local rakeSpellName = SpellInfo(rakeSpellID)
                    local baseName = rakeSpellName and string.gsub(rakeSpellName, "%s*%(Rank %d+%)", "") or "Rake"

                    -- Update tracking tables for pfUI hooks
                    if CleveRoids.ComboPointTracking then
                      CleveRoids.ComboPointTracking[baseName] = {
                        combo_points = rakeComboPoints,
                        duration = rakeDuration,
                        cast_time = GetTime(),
                        target = targetName,
                        confirmed = true
                      }
                    end

                    -- Store duration override for pfUI hooks
                    if not CleveRoids.carnageDurationOverrides then
                      CleveRoids.carnageDurationOverrides = {}
                    end
                    CleveRoids.carnageDurationOverrides[rakeSpellID] = {
                      duration = rakeDuration,
                      timestamp = GetTime(),
                      targetGUID = targetGUID
                    }

                    -- Update pfUI's debuff timer directly
                    if pfUI and pfUI.api and pfUI.api.libdebuff then
                      local pflib = pfUI.api.libdebuff
                      if pflib.objects and pflib.objects[targetName] then
                        local updated = false
                        local currentLevel = UnitLevel("target") or 0

                        -- Update at all levels where the debuff exists
                        for level, effects in pairs(pflib.objects[targetName]) do
                          if type(effects) == "table" and effects[baseName] then
                            local entry = effects[baseName]
                            entry.duration = rakeDuration
                            entry.start = GetTime()
                            entry.caster = "player"
                            if entry.tick then entry.tick = GetTime() end
                            updated = true
                          end
                        end

                        -- Ensure entry exists at current UnitLevel
                        if updated then
                          if not pflib.objects[targetName][currentLevel] then
                            pflib.objects[targetName][currentLevel] = {}
                          end
                          if not pflib.objects[targetName][currentLevel][baseName] then
                            pflib.objects[targetName][currentLevel][baseName] = {
                              effect = baseName,
                              duration = rakeDuration,
                              start = GetTime(),
                              caster = "player"
                            }
                          end
                          if pflib.UpdateUnits then pflib:UpdateUnits() end
                        elseif pflib.AddEffect then
                          pflib:AddEffect(targetName, currentLevel, baseName, rakeDuration, "player")
                        end
                      end
                    end

                    -- Update internal tracker
                    if lib.objects[targetGUID] and lib.objects[targetGUID][rakeSpellID] then
                      lib.objects[targetGUID][rakeSpellID].duration = rakeDuration
                      lib.objects[targetGUID][rakeSpellID].start = GetTime()
                      lib.objects[targetGUID][rakeSpellID].expiry = GetTime() + rakeDuration
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

          lib:AddEffect(targetGUID, targetName, spellID, duration, 0, "player")

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

local evLearn = CreateFrame("Frame", "CleveRoidsLibDebuffLearnFrame", UIParent)
evLearn:RegisterEvent("RAW_COMBATLOG")

evLearn:SetScript("OnEvent", function()
  if event == "RAW_COMBATLOG" then
    local raw = arg2
    if not raw or not find(raw, "fades from") then return end

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

          if lib.objects[targetGUID][spellID].start +
             lib.objects[targetGUID][spellID].duration <= timestamp then
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
}

-- Cache for spell school lookups
local spellSchoolCache = {}

-- Get the damage school of a spell
local function GetSpellSchool(spellName)
    if not spellName then return nil end

    -- Remove rank information for cache consistency
    local baseName = string.gsub(spellName, "%s*%(.-%)%s*$", "")

    -- Check cache first
    if spellSchoolCache[baseName] then
        return spellSchoolCache[baseName]
    end

    -- Try to find spell in player's spellbook
    local spell = CleveRoids.GetSpell(baseName)
    if not spell then
        return nil
    end

    -- Create tooltip if needed
    if not CleveRoidsSchoolTooltip then
        CreateFrame("GameTooltip", "CleveRoidsSchoolTooltip", nil, "GameTooltipTemplate")
        CleveRoidsSchoolTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end

    CleveRoidsSchoolTooltip:ClearLines()
    CleveRoidsSchoolTooltip:SetSpell(spell.spellSlot, spell.bookType)

    -- Scan tooltip for school keywords
    local school = nil
    for i = 1, CleveRoidsSchoolTooltip:NumLines() do
        local line = _G["CleveRoidsSchoolTooltipTextLeft" .. i]
        if line then
            local text = string.lower(line:GetText() or "")

            if string.find(text, "fire") or string.find(text, "flame") then
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

    -- Fallback: Use spell name patterns for common spells
    if not school then
        local lower = string.lower(baseName)
        if string.find(lower, "fire") or string.find(lower, "flame") or string.find(lower, "immolat") or string.find(lower, "scorch") then
            school = "fire"
        elseif string.find(lower, "frost") or string.find(lower, "ice") or string.find(lower, "blizzard") then
            school = "frost"
        elseif string.find(lower, "nature") or string.find(lower, "poison") or string.find(lower, "sting") then
            school = "nature"
        elseif string.find(lower, "shadow") or string.find(lower, "curse") or string.find(lower, "corruption") then
            school = "shadow"
        elseif string.find(lower, "arcane") then
            school = "arcane"
        elseif string.find(lower, "holy") or string.find(lower, "smite") or string.find(lower, "exorcism") then
            school = "holy"
        else
            school = "physical"
        end
    end

    -- Cache the result
    spellSchoolCache[baseName] = school
    return school
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
local function RecordImmunity(npcName, spellName, conditionalBuff)
    if not npcName or not spellName or npcName == "" then
        return
    end

    local school = GetSpellSchool(spellName)
    if not school then
        return
    end

    -- Initialize school table
    if not CleveRoids_ImmunityData[school] then
        CleveRoids_ImmunityData[school] = {}
    end

    -- Record immunity
    if conditionalBuff then
        -- Buff-based immunity
        CleveRoids_ImmunityData[school][npcName] = {
            buff = conditionalBuff
        }
        if CleveRoids.debug then
            CleveRoids.Print("|cffff6600Immunity:|r " .. npcName .. " is immune to " .. school .. " when buffed with: " .. conditionalBuff)
        end
    else
        -- Permanent immunity
        if CleveRoids_ImmunityData[school][npcName] ~= true then
            CleveRoids_ImmunityData[school][npcName] = true
            if CleveRoids.debug then
                CleveRoids.Print("|cffff6600Immunity:|r " .. npcName .. " is permanently immune to " .. school)
            end
        end
    end
end

-- Combat log parser for immunity detection
local function ParseImmunityCombatLog()
    local message = arg1  -- Formatted message
    local rawMessage = arg2  -- Raw message

    if not rawMessage then return end

    -- Pattern: "X's SpellName fails. Y is immune."
    local spellName = nil
    local targetName = nil

    -- Extract spell name from raw message
    local _, _, extractedSpell = string.find(rawMessage, "'s%s+(.-)%s+fails%.")
    if not extractedSpell then
        _, _, extractedSpell = string.find(rawMessage, "Your%s+(.-)%s+fails%.")
    end

    -- Extract target name from formatted message (more reliable)
    if message then
        local _, _, extractedTarget = string.find(message, "fails%.%s+(.-)%s+is immune")
        if extractedTarget then
            targetName = extractedTarget
        end
    end

    -- Fallback: Try to get target from current target
    if not targetName and UnitExists("target") then
        local _, targetGUID = UnitExists("target")
        if targetGUID and rawMessage and string.find(rawMessage, targetGUID) then
            targetName = UnitName("target")
        end
    end

    if extractedSpell and targetName then
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
                RecordImmunity(targetName, extractedSpell, singleBuff)
                return
            end
        end

        -- No single buff detected, record as permanent immunity
        RecordImmunity(targetName, extractedSpell, nil)
    end
end

-- Check if a unit is immune to a spell or damage school
-- Supports: CheckImmunity(unitId, "Flame Shock") or CheckImmunity(unitId, "fire")
function CleveRoids.CheckImmunity(unitId, spellOrSchool)
    if not unitId or not UnitExists(unitId) then
        return false
    end

    -- Only works on NPCs
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

    if IMMUNITY_SCHOOLS[inputLower] then
        -- Input is a damage school name (fire, frost, nature, etc.)
        school = inputLower
    else
        -- Input is a spell name, need to determine its school
        school = GetSpellSchool(spellOrSchool)
        if not school then
            return false
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

    -- Buff-based immunity (check if NPC has the required buff)
    if type(immunityData) == "table" and immunityData.buff then
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
            elseif type(data) == "table" and data.buff then
                CleveRoids.Print("  - " .. npc .. " (when buffed: " .. data.buff .. ")")
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
        CleveRoids.Print("Schools: fire, frost, nature, shadow, arcane, holy, physical")
        return
    end

    school = string.lower(school)
    if not IMMUNITY_SCHOOLS[school] then
        CleveRoids.Print("Invalid school. Use: fire, frost, nature, shadow, arcane, holy, physical")
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

-- Register combat log event for immunity tracking
local immunityFrame = CreateFrame("Frame", "CleveRoidsImmunityFrame")
immunityFrame:RegisterEvent("RAW_COMBATLOG")
immunityFrame:SetScript("OnEvent", function()
    if event == "RAW_COMBATLOG" then
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
        duration = 4.0  -- 4 second proc window
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
        duration = 5.0  -- 5 second proc window (estimated, may be 4s)
    },
    Revenge = {
        -- Procs when YOU block, dodge, or parry an enemy attack (any stance)
        patterns = {
            "You block",           -- English: "You block X's Y"
            "You dodge",           -- English: "You dodge X's Y"
            "You parry",           -- English: "You parry X's Y"
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
        requiresTargetGUID = true,  -- Track which enemy triggered it
        duration = 4.0  -- 4 second proc window
    }
}

-- Set a reactive proc state with optional target GUID
function CleveRoids.SetReactiveProc(spellName, duration, targetGUID)
    duration = duration or REACTIVE_PROC_DURATION
    CleveRoids.reactiveProcs[spellName] = {
        expiry = GetTime() + duration,
        targetGUID = targetGUID
    }
end

-- Check if a reactive proc is active (with optional GUID check)
function CleveRoids.HasReactiveProc(spellName)
    local procData = CleveRoids.reactiveProcs[spellName]
    if not procData or not procData.expiry then return false end

    local now = GetTime()
    if now >= procData.expiry then
        -- Expired, clear it
        CleveRoids.reactiveProcs[spellName] = nil
        -- Queue action update to refresh icon state
        CleveRoids.QueueActionUpdate()
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
local reactiveFrame = CreateFrame("Frame", "CleveRoidsReactiveFrame")
reactiveFrame:RegisterEvent("RAW_COMBATLOG")
reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
reactiveFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
reactiveFrame:SetScript("OnEvent", function()
    if event == "RAW_COMBATLOG" or
       event == "CHAT_MSG_COMBAT_SELF_HITS" or
       event == "CHAT_MSG_COMBAT_SELF_MISSES" or
       event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" or
       event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        CleveRoids.ParseReactiveCombatLog()
    end
end)
