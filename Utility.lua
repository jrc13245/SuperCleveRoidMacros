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

lib.durations = lib.durations or {
  -- WARRIOR
  [772] = 9,      -- Rend (Rank 1)
  [6546] = 12,    -- Rend (Rank 2)
  [6547] = 15,    -- Rend (Rank 3)
  [6548] = 18,    -- Rend (Rank 4)
  [11572] = 21,   -- Rend (Rank 5)
  [11573] = 21,   -- Rend (Rank 6)
  [11574] = 21,   -- Rend (Rank 7)

  [7386] = 30,    -- Sunder Armor (Rank 1)
  [7405] = 30,    -- Sunder Armor (Rank 2)
  [8380] = 30,    -- Sunder Armor (Rank 3)
  [8647] = 30,    -- Sunder Armor (Rank 4)
  [11597] = 30,   -- Sunder Armor (Rank 5)

  [7372] = 15,    -- Hamstring (Rank 1)
  [7373] = 15,    -- Hamstring (Rank 2)
  [1715] = 15,    -- Hamstring (Rank 3)

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

  [12323] = 6,    -- Piercing Howl

  -- ROGUE
  [2094] = 10,    -- Blind
  [21060] = 10,   -- Blind (alternate?)

  [6770] = 25,    -- Sap (Rank 1)
  [2070] = 35,    -- Sap (Rank 2)
  [11297] = 45,   -- Sap (Rank 3)

  [1776] = 4,     -- Gouge (Rank 1) - base duration
  [1777] = 4,     -- Gouge (Rank 2)
  [8629] = 4,     -- Gouge (Rank 3)
  [11285] = 4,    -- Gouge (Rank 4)
  [11286] = 4,    -- Gouge (Rank 5)

  [1943] = 6,     -- Rupture (Rank 1) - base duration (scales with combo points)
  [8639] = 6,     -- Rupture (Rank 2)
  [8640] = 6,     -- Rupture (Rank 3)
  [11273] = 6,    -- Rupture (Rank 4)
  [11274] = 6,    -- Rupture (Rank 5)
  [11275] = 6,    -- Rupture (Rank 6)

  [408] = 1,      -- Kidney Shot (Rank 1) - base duration (scales with combo points)
  [8643] = 1,     -- Kidney Shot (Rank 2)

  [8647] = 30,    -- Expose Armor (Rank 1)
  [8649] = 30,    -- Expose Armor (Rank 2)
  [8650] = 30,    -- Expose Armor (Rank 3)
  [11197] = 30,   -- Expose Armor (Rank 4)
  [11198] = 30,   -- Expose Armor (Rank 5)

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

  [5570] = 18,    -- Insect Swarm (Rank 1) - 12s with talent
  [24974] = 18,   -- Insect Swarm (Rank 2)
  [24975] = 18,   -- Insect Swarm (Rank 3)
  [24976] = 18,   -- Insect Swarm (Rank 4)
  [24977] = 18,   -- Insect Swarm (Rank 5)

  [8921] = 9,     -- Moonfire (Rank 1) - 12s with talent
  [8924] = 18,    -- Moonfire (Rank 2) - 12s with talent
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

  [1079] = 10,     -- Rip (Rank 1) - base duration (scales with combo points)
  [9492] = 10,     -- Rip (Rank 2)
  [9493] = 10,     -- Rip (Rank 3)
  [9752] = 10,     -- Rip (Rank 4)
  [9894] = 10,     -- Rip (Rank 5)
  [9896] = 10,     -- Rip (Rank 6)

  [2908] = 15,    -- Soothe Animal (Rank 1)
  [8955] = 15,    -- Soothe Animal (Rank 2)
  [9901] = 15,    -- Soothe Animal (Rank 3)

  [5211] = 2,     -- Bash (Rank 1)
  [6798] = 3,     -- Bash (Rank 2)
  [8983] = 4,     -- Bash (Rank 3)

  [99] = 30,      -- Demoralizing Roar (Rank 1)
  [1735] = 30,    -- Demoralizing Roar (Rank 2)
  [9490] = 30,    -- Demoralizing Roar (Rank 3)
  [9747] = 30,    -- Demoralizing Roar (Rank 4)
  [9898] = 30,    -- Demoralizing Roar (Rank 5)

  [5209] = 6,     -- Challenging Roar

  [9005] = 18,    -- Pounce Bleed (Rank 1)
  [9823] = 18,    -- Pounce Bleed (Rank 2)
  [9827] = 18,    -- Pounce Bleed (Rank 3)

  -- WARLOCK
  [172] = 12,     -- Corruption (Rank 1) - 18s with talent
  [6222] = 15,    -- Corruption (Rank 2) - 18s with talent
  [6223] = 18,    -- Corruption (Rank 3) - 18s with talent
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

  [589] = 24,     -- Shadow Word: Pain (Rank 1) - 18s base, 24s with talent
  [594] = 24,     -- Shadow Word: Pain (Rank 2)
  [970] = 24,     -- Shadow Word: Pain (Rank 3)
  [992] = 24,     -- Shadow Word: Pain (Rank 4)
  [2767] = 24,    -- Shadow Word: Pain (Rank 5)
  [10892] = 24,   -- Shadow Word: Pain (Rank 6)
  [10893] = 24,   -- Shadow Word: Pain (Rank 7)
  [10894] = 24,   -- Shadow Word: Pain (Rank 8)

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

lib.learnCastTimers = lib.learnCastTimers or {}

CleveRoids_LearnedDurations = CleveRoids_LearnedDurations or {}

function lib:GetDuration(spellID, casterGUID)
  if casterGUID and CleveRoids_LearnedDurations[spellID] then
    local learned = CleveRoids_LearnedDurations[spellID][casterGUID]
    if learned and learned > 0 then
      return learned
    end
  end

  return self.durations[spellID] or 0
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
end

function lib:UnitDebuff(unit, id)
  local _, guid = UnitExists(unit)
  if not guid then return nil end

  local texture, stacks, dtype, spellID = UnitDebuff(unit, id)

  if not texture or not spellID then
    texture, stacks, _, spellID = UnitBuff(unit, id)
    if texture and spellID and not lib.durations[spellID] then
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
    else
      lib.objects[guid][spellID] = nil
    end
  end

  return name, nil, texture, stacks, dtype, duration, timeleft, caster
end

local function SeedUnit(unit)
  local _, guid = UnitExists(unit)
  if not guid then return end
  local unitName = UnitName(unit)

  for i=1, 16 do
    local tex, stacks, dtype, spellID = UnitDebuff(unit, i)
    if not tex then break end

    if spellID and lib.durations[spellID] then
      if not (lib.objects[guid] and lib.objects[guid][spellID]) then
        lib:AddEffect(guid, unitName, spellID, lib:GetDuration(spellID), stacks)
      end
    end
  end

  for i=1, 32 do
    local tex, stacks, _, spellID = UnitBuff(unit, i)
    if not tex then break end

    if spellID and lib.durations[spellID] then
      if not (lib.objects[guid] and lib.objects[guid][spellID]) then
        lib:AddEffect(guid, unitName, spellID, lib:GetDuration(spellID), stacks)
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

    if eventType == "CAST" and spellID then
      local _, playerGUID = UnitExists("player")
      if casterGUID == playerGUID and targetGUID then

        local duration = lib:GetDuration(spellID, casterGUID)

        if duration > 0 then
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
          lib:AddEffect(targetGUID, targetName, spellID, duration, 0, "player")

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

            CleveRoids_LearnedDurations[spellID] = CleveRoids_LearnedDurations[spellID] or {}
            CleveRoids_LearnedDurations[spellID][casterGUID] = floor(actualDuration + 0.5)

            if CleveRoids.debug then
              DEFAULT_CHAT_FRAME:AddMessage(
                "|cff4b7dccCleveRoids:|r Learned " .. spellName ..
                " (ID:" .. spellID .. ") = " .. floor(actualDuration + 0.5) .. "s"
              )
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
                end
            end
        end
    end
end)

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
