--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {} -- redundant since we're loading first but peace of mind if another file is added top of chain

-- Vanilla 1.12.1 compatibility: hooksecurefunc polyfill
if type(hooksecurefunc) ~= "function" then
  function hooksecurefunc(arg1, arg2, arg3)
    local tgt, fname, post

    -- Variant A: hooksecurefunc("GlobalFuncName", postHook)
    if type(arg1) == "string" and type(arg2) == "function" and arg3 == nil then
      fname, post = arg1, arg2
      local orig = _G[fname]
      if type(orig) ~= "function" then return end
      _G[fname] = function(...)
        local r = { orig(unpack(arg)) }  -- Lua 5.0 varargs
        post(unpack(arg))
        return unpack(r)
      end
      return
    end

    -- Variant B: hooksecurefunc(table, "MethodName", postHook)
    if type(arg1) == "table" and type(arg2) == "string" and type(arg3) == "function" then
      tgt, fname, post = arg1, arg2, arg3
      local orig = tgt[fname]
      if type(orig) ~= "function" then return end
      tgt[fname] = function(...)
        local r = { orig(unpack(arg)) }
        post(unpack(arg))
        return unpack(r)
      end
      return
    end
    -- If neither signature matches, do nothing (fail-safe)
  end
end

-- Lua 5.0 compatibility shims (WoW 1.12): string.match / string.gmatch
if type(string.match) ~= "function" then
  function string.match(s, pattern, init)
    if s == nil or pattern == nil then return nil end
    local i, j, c1, c2, c3, c4, c5 = string.find(s, pattern, init)
    if not i then return nil end
    -- If the pattern has captures, return them (first 5 for simplicity).
    if c1 ~= nil then return c1, c2, c3, c4, c5 end
    -- Otherwise return the matched substring (Lua 5.1+ behavior).
    return string.sub(s, i, j)
  end
end

if type(string.gmatch) ~= "function" then
  -- Simple gmatch built on repeated string.find
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

-- Trims any leading or trailing white space characters from the given string
-- str: The string to trim
-- returns: The trimmed string
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
    pfui    = 3,   -- unitframe hovers should win
    blizz   = 3,   -- same level as pfui
    tooltip = 1,   -- lowest; don’t stomp frames
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
    -- SuperWoW path if available; otherwise internal fallback
    if CleveRoids.hasSuperwow and _G.SetMouseoverUnit then
      _G.SetMouseoverUnit(unit) -- nil clears
    else
      CleveRoids.mouseoverUnit = unit
    end
    if CleveRoids.QueueActionUpdate then CleveRoids.QueueActionUpdate() end
  end

  function CleveRoids.SetMouseoverFrom(source, unit)
    -- set/refresh a source’s unit
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
      return -- don’t clear if it was replaced meanwhile
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

-- Splits the given string into a list of sub-strings
-- str: The string to split
-- seperatorPattern: The seperator between sub-string. May contain patterns
-- returns: A list of sub-strings
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

    -- Add the last segment if it exists
    if temp ~= "" then
        temp = CleveRoids.Trim(temp)
        table.insert(result, temp)
    end

    -- if nothing was found, return the empty string
    return (next(result) and result or {""})
end

-- Prints all the given arguments into WoW's default chat frame
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

-- === CleveRoids.libdebuff (Vanilla 1.12.1 / Lua 5.0) =======================
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids

-- create table
CleveRoids.libdebuff = CleveRoids.libdebuff or {}
local lib = CleveRoids.libdebuff

-- storage modeled after pfUI: objects[name][level][effect] = {start,duration,caster}
lib.objects = lib.objects or {}
lib.pending = lib.pending or {} -- {unit, level, effect, duration, caster}
local lastspell

-- configurable durations (extend as needed)
lib.durations = lib.durations or {
  ["Sunder Armor"] = 30,
  ["Expose Armor"] = 30,
  -- ["Faerie Fire"] = 40,
  -- ["Rend"] = 21,
}

-- Utility: effect duration lookup (can be expanded with rank/talent logic later)
function lib:GetDuration(effect, rank)
  return self.durations[effect] or 0
end

-- Basic add/refresh of a debuff record
function lib:AddEffect(unitName, unitLevel, effect, duration, caster)
  if not unitName or not effect then return end
  unitLevel = unitLevel or 0
  duration = duration or lib:GetDuration(effect)
  if duration <= 0 then return end

  lib.objects[unitName] = lib.objects[unitName] or {}
  lib.objects[unitName][unitLevel] = lib.objects[unitName][unitLevel] or {}
  lib.objects[unitName][unitLevel][effect] = lib.objects[unitName][unitLevel][effect] or {}

  local rec = lib.objects[unitName][unitLevel][effect]
  lastspell = rec

  rec.effect = effect
  rec.start_old = rec.start
  rec.start = GetTime()
  rec.duration = duration
  rec.caster = caster

  -- no UI refresh hook needed; your UI reads via conditionals
end

function lib:RevertLastAction()
  if lastspell and lastspell.start_old then
    lastspell.start = lastspell.start_old
    lastspell.start_old = nil
  end
end

function lib:AddPending(unitName, unitLevel, effect, duration, caster)
  if not unitName or not effect then return end
  if (duration or 0) <= 0 then duration = lib:GetDuration(effect) end
  if duration <= 0 then return end

  lib.pending[1] = unitName
  lib.pending[2] = unitLevel or 0
  lib.pending[3] = effect
  lib.pending[4] = duration
  lib.pending[5] = caster
end

function lib:RemovePending()
  lib.pending[1] = nil
  lib.pending[2] = nil
  lib.pending[3] = nil
  lib.pending[4] = nil
  lib.pending[5] = nil
end

function lib:PersistPending(effect)
  -- if effect matches the pending one (or nil meaning “persist whatever is pending”)
  if lib.pending[3] and (effect == nil or effect == lib.pending[3]) then
    lib:AddEffect(lib.pending[1], lib.pending[2], lib.pending[3], lib.pending[4], lib.pending[5])
  end
  lib:RemovePending()
end

-- Read API similar to pfUI: returns effect, rank(nil), texture, stacks, dtype, duration, timeleft, caster
function lib:UnitDebuff(unit, id)
  local unitName = UnitName(unit)
  local unitLevel = UnitLevel(unit) or 0
  local texture, stacks, dtype = UnitDebuff(unit, id)
  local duration, timeleft, caster = nil, -1, nil
  local effect

  if texture then
    -- Try to resolve a stable effect name using SuperWoW SpellInfo when available
    local _, _, spellID
    if CleveRoids.hasSuperwow then
      -- Use tooltip scan alternative via UnitDebuff’s texture->name mapping if you have it,
      -- or rely on GameTooltip scanning if desired (omitted for performance).
      -- The most stable way here: read the name off the debuff button tooltip:
      -- (Left out to keep it lightweight; we fetch name by scanning by index below)
    end

    -- Prefer reading name by setting the tooltip on this debuff index (cheap enough on access)
    -- We avoid a full scanner dependency to keep this self-contained:
    -- Build a temporary tooltip to fetch line 1 as the effect name.
    if not lib._tt then
      lib._tt = CreateFrame("GameTooltip", "CleveRoidsLibDebuffTT", UIParent, "GameTooltipTemplate")
      lib._tt:SetOwner(UIParent, "ANCHOR_NONE")
    end
    local tt = lib._tt
    tt:ClearLines()
    tt:SetUnitDebuff(unit, id)
    effect = (getglobal("CleveRoidsLibDebuffTTTextLeft1") and getglobal("CleveRoidsLibDebuffTTTextLeft1"):GetText()) or ""
  end

  -- read level-scoped storage, try exact level then 0 fallback (pfUI pattern)
  local data = lib.objects[unitName] and (lib.objects[unitName][unitLevel] or lib.objects[unitName][0])
  local rec = data and effect and data[effect]

  if rec and rec.duration and rec.start and (rec.duration + rec.start > GetTime()) then
    duration = rec.duration
    timeleft = rec.duration + rec.start - GetTime()
    caster = rec.caster
  elseif rec then
    -- cleanup expired
    data[effect] = nil
  end

  return effect, nil, texture, stacks, dtype, duration, timeleft, caster
end

-- Seed timers by scanning the current target/player auras (to avoid relying only on casts)
local function SeedUnit(unit)
  if not UnitExists(unit) then return end
  local unitName = UnitName(unit)
  if not unitName or unitName == "" then return end
  local unitLevel = UnitLevel(unit) or 0

  for i=1, 16 do
    local tex = (UnitDebuff(unit, i))
    if not tex then break end

    -- resolve effect name via tooltip line 1
    if not lib._tt then
      lib._tt = CreateFrame("GameTooltip", "CleveRoidsLibDebuffTT", UIParent, "GameTooltipTemplate")
      lib._tt:SetOwner(UIParent, "ANCHOR_NONE")
    end
    local tt = lib._tt
    tt:ClearLines()
    tt:SetUnitDebuff(unit, i)
    local effect = (getglobal("CleveRoidsLibDebuffTTTextLeft1") and getglobal("CleveRoidsLibDebuffTTTextLeft1"):GetText()) or ""

    if effect ~= "" and lib.durations[effect] then
      -- don’t overwrite a valid running timer
      local data = lib.objects[unitName] and (lib.objects[unitName][unitLevel] or lib.objects[unitName][0])
      if not (data and data[effect]) then
        lib:AddEffect(unitName, unitLevel, effect, lib:GetDuration(effect))
      end
    end
  end
end

-- Events & hooks (modeled after pfUI, simplified to avoid extra libs)
local ev = CreateFrame("Frame", "CleveRoidsLibDebuffFrame", UIParent)
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("SPELLCAST_STOP")
ev:RegisterEvent("CHAT_MSG_SPELL_FAILED_LOCALPLAYER")
ev:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")

-- (Optional) add more combat log events if you later want to detect “aura applied” via text

ev:SetScript("OnEvent", function()
  if event == "PLAYER_TARGET_CHANGED" then
    SeedUnit("target")

  elseif event == "UNIT_AURA" and arg1 == "target" then
    SeedUnit("target")

  elseif event == "SPELLCAST_STOP" then
    lib:PersistPending() -- accept any pending on cast stop

  elseif event == "CHAT_MSG_SPELL_FAILED_LOCALPLAYER" or event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    -- best-effort pending cleanup/revert patterns can be added here if you parse failure strings
    -- for now, we just drop the pending on generic failure patterns being detected elsewhere
  end
end)

-- Hooks to capture “pending” when you cast
hooksecurefunc("CastSpell", function(id, bookType)
  -- try to resolve spell name via SuperWoW or vanilla
  local name, rank
  if type(SpellInfo) == "function" then
    name, rank = SpellInfo(id)
  elseif type(GetSpellName) == "function" then
    name, rank = GetSpellName(id, bookType)
  end
  if name then
    local dur = lib:GetDuration(name)
    lib:AddPending(UnitName("target"), UnitLevel("target"), name, dur, "player")
  end
end)

hooksecurefunc("CastSpellByName", function(spell)
  local name = spell
  -- accept “Name(Rank X)” format; trim rank for table match
  local base = string.match(spell, "^(.-)%s*%(") or spell
  local dur = lib:GetDuration(base)
  lib:AddPending(UnitName("target"), UnitLevel("target"), base, dur, "player")
end)

-- Simple action use hook (optional; safe no-op if Action API differs)
hooksecurefunc("UseAction", function(slot)
  if GetActionText(slot) or not IsCurrentAction(slot) then return end
  -- we can’t reliably get the effect name without a tooltip scanner; skip to keep it lightweight
end)
-- === end CleveRoids.libdebuff ==============================================
