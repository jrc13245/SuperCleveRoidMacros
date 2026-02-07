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

-- Spells with physical damage + resistable CC effect (weapon-dependent)
-- These spells deal physical damage that ALWAYS lands (unless dodged/parried/blocked),
-- but apply a CC effect that can be resisted independently.
-- When the CC is resisted, we should NOT record physical immunity.
--
-- Master Strike (Warrior): 35% weapon damage + weapon-dependent CC
--   Mace: Disorient (3s)    Sword: Disarm (3s)      Axe: Immobilize (4s)
--   Polearm: Dismount       Fist: Knockdown (2s)    Dagger: Silence (3s)
--   Staff: Self-buff (parry, no CC)
local SPLIT_CC_SPELLS = {
    [54016] = true,  -- Master Strike (Mace) - Disorient
    [54017] = true,  -- Master Strike (Sword) - Disarm
    [54018] = true,  -- Master Strike (Axe) - Immobilize
    [54019] = true,  -- Master Strike (Polearm) - Dismount
    [54020] = true,  -- Master Strike (Fist) - Knockdown
    [54021] = true,  -- Master Strike (Staff) - Parry buff
    [54022] = true,  -- Master Strike (Dagger) - Silence
    [54023] = true,  -- Master Strike (Base)
    [54024] = true,  -- Master Strike (Level 0 variant)
}

-- Name-based lookup for split CC spells (for combat log parsing where only name is available)
-- All weapon variants share the same display name, so we need to check by name too
local SPLIT_CC_SPELL_NAMES = {
    ["Master Strike"] = true,
}

-- GUID normalization: ensure all GUIDs are strings for consistent table key lookups
-- In Lua, table["123"] is different from table[123], so we must normalize
function CleveRoids.NormalizeGUID(guid)
    if not guid then return nil end
    return tostring(guid)
end

-- Hidden tooltip for scanning spell info
local SpellScanTooltip = nil

-- Create hidden tooltip for scanning (once)
local function GetSpellScanTooltip()
    if not SpellScanTooltip then
        SpellScanTooltip = CreateFrame("GameTooltip", "CleveRoidsSpellScanTooltip", nil, "GameTooltipTemplate")
        SpellScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return SpellScanTooltip
end

-- Cache for spell durations from tooltip
local cachedSpellDurations = {}
local spellDurationCacheTime = {}
local SPELL_CACHE_DURATION = 0.5  -- Re-scan every 0.5 seconds (haste can change mid-fight)

-- Get a spell's slot in the spellbook by spell ID
local function GetSpellSlotByID(targetSpellID)
    local i = 1
    while true do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        -- Get spell ID for this slot using SpellInfo if available
        if SpellInfo then
            local _, _, spellID = GetSpellName(i, BOOKTYPE_SPELL)
            -- Try to get ID from the spell slot
            local slot, book = i, BOOKTYPE_SPELL
            -- SpellInfo needs the spell name to get ID, but we can check via GetSpellTexture match
        end
        i = i + 1
    end
    return nil, nil
end

-- Get a spell's slot in the spellbook by name (finds highest rank by default)
-- If targetRank is specified (e.g., "Rank 5"), finds that specific rank
local function GetSpellSlotByName(targetSpellName, targetRank)
    local foundSlot = nil
    local foundRank = nil
    local i = 1
    while true do
        local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        if spellName == targetSpellName then
            if targetRank then
                -- Looking for specific rank
                if spellRank == targetRank then
                    return i, BOOKTYPE_SPELL
                end
            else
                -- Looking for highest rank - keep scanning to find the last one
                foundSlot = i
                foundRank = spellRank
            end
        end
        i = i + 1
    end
    -- Return highest rank found (last match in spellbook order)
    return foundSlot, BOOKTYPE_SPELL
end

-- Parse channel duration from tooltip text
-- Matches patterns like "for 5 sec" or "over 8 sec" at the end of descriptions
local function ParseChannelDurationFromText(text)
    if not text then return nil end
    -- Match "for X sec" pattern (channels like Arcane Missiles, Drain Life)
    local duration = string.match(text, "for (%d+%.?%d*) sec")
    if duration then
        return tonumber(duration)
    end
    -- Match "over X sec" pattern (some DoT/HoT tooltips)
    duration = string.match(text, "over (%d+%.?%d*) sec")
    if duration then
        return tonumber(duration)
    end
    return nil
end

-- Scan spell tooltip for channel/cast duration
-- Returns duration in seconds, or nil if not found
function CleveRoids.GetSpellDurationFromTooltip(spellName)
    if not spellName then return nil end

    -- Check cache
    local now = GetTime()
    if cachedSpellDurations[spellName] and spellDurationCacheTime[spellName] then
        if now - spellDurationCacheTime[spellName] < SPELL_CACHE_DURATION then
            return cachedSpellDurations[spellName]
        end
    end

    local slot, bookType = GetSpellSlotByName(spellName)
    if not slot then return nil end

    local tooltip = GetSpellScanTooltip()
    tooltip:ClearLines()
    tooltip:SetSpell(slot, bookType)

    -- Scan tooltip lines for duration
    for i = 1, tooltip:NumLines() do
        local leftText = getglobal("CleveRoidsSpellScanTooltipTextLeft" .. i)
        if leftText then
            local text = leftText:GetText()
            local duration = ParseChannelDurationFromText(text)
            if duration then
                -- Cache the result
                cachedSpellDurations[spellName] = duration
                spellDurationCacheTime[spellName] = now
                return duration
            end
        end
    end

    return nil
end

-- Get channel duration for a spell by ID (looks up name first)
function CleveRoids.GetChannelDurationFromTooltipByID(spellID)
    if not spellID or not SpellInfo then return nil end
    local spellName = SpellInfo(spellID)
    if not spellName then return nil end
    return CleveRoids.GetSpellDurationFromTooltip(spellName)
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

-- PERFORMANCE: Trim cache to avoid repeated gsub pattern matching
local _trimCache = {}
local _trimCacheSize = 0
local _TRIM_CACHE_MAX = 512

function CleveRoids.Trim(str)
    if not str then
        return nil
    end

    -- PERFORMANCE: Check cache first
    local cached = _trimCache[str]
    if cached ~= nil then
        return cached
    end

    local result = string.gsub(str, "^%s*(.-)%s*$", "%1")

    -- Cache the result (limit cache size)
    if _trimCacheSize < _TRIM_CACHE_MAX then
        _trimCache[str] = result
        _trimCacheSize = _trimCacheSize + 1
    end

    return result
end

do
  local _G = _G or getfenv(0)
  local CleveRoids = _G.CleveRoids or {}
  _G.CleveRoids = CleveRoids

  CleveRoids.__mo = CleveRoids.__mo or { sources = {}, current = nil, selfTriggered = false }

  -- Priority levels for mouseover sources (higher = takes precedence)
  -- All unit frame addons get priority 3, native event gets 2, tooltip fallback gets 1
  local PRIORITY = {
    -- Unit frame addons (priority 3)
    pfui    = 3,
    blizz   = 3,
    aguf    = 3,  -- ag_UnitFrames
    ctra    = 3,  -- CT_RaidAssist
    ctuf    = 3,  -- CT_UnitFrames
    cursive = 3,  -- Cursive DoT tracker bars
    duf     = 3,  -- DiscordUnitFrames
    focus   = 3,  -- FocusFrame
    grid    = 3,  -- Grid
    ngrid   = 3,  -- NotGrid
    praid   = 3,  -- PerfectRaid
    sraid   = 3,  -- sRaidFrames
    xperl   = 3,  -- X-Perl UnitFrames
    luna    = 3,  -- LunaUnitFrames
    dfr     = 3,  -- DragonflightReloaded
    df3     = 3,  -- Dragonflight3
    -- Fallbacks (lower priority)
    native  = 2,
    tooltip = 1,
  }

  -- Get priority for a source, handling prefixed keys like "pfui:player"
  local function getPriority(source)
    if PRIORITY[source] then
      return PRIORITY[source]
    end
    -- Check for prefixed sources (e.g., "pfui:player" -> "pfui")
    -- Using string.find with captures for Lua 5.0 compatibility
    local _, _, prefix = string.find(source, "^(%w+):")
    if prefix and PRIORITY[prefix] then
      return PRIORITY[prefix]
    end
    return 0
  end

  local function getBest()
    local bestSource, bestUnit, bestP = nil, nil, -1
    for source, unit in pairs(CleveRoids.__mo.sources) do
      if unit and unit ~= "" then
        local p = getPriority(source)
        if p > bestP then
          bestP, bestSource, bestUnit = p, source, unit
        end
      end
    end
    return bestSource, bestUnit
  end

  -- Re-entrancy guard to prevent stack overflow from UI update cascades
  local isUpdatingMouseover = false

  local function apply(unit)
    if CleveRoids.hasSuperwow and _G.SetMouseoverUnit then
      -- Set flag so UPDATE_MOUSEOVER_UNIT handler knows we triggered this
      CleveRoids.__mo.selfTriggered = true
      -- Use empty string instead of nil to properly clear mouseover.
      -- SetMouseoverUnit(nil) doesn't properly clear the game's internal state,
      -- causing UnitIsPlayer("mouseover") to return stale data (TurtleRP bug).
      _G.SetMouseoverUnit(unit or "")
    else
      CleveRoids.mouseoverUnit = unit
    end
    if CleveRoids.QueueActionUpdate then CleveRoids.QueueActionUpdate() end
  end

  function CleveRoids.SetMouseoverFrom(source, unit)
    if not source or isUpdatingMouseover then return end
    CleveRoids.__mo.sources[source] = unit
    local _, bestUnit = getBest()
    if bestUnit ~= CleveRoids.__mo.current then
      CleveRoids.__mo.current = bestUnit
      isUpdatingMouseover = true
      apply(bestUnit)
      isUpdatingMouseover = false
    end
  end

  function CleveRoids.ClearMouseoverFrom(source, unitIfMatch)
    if not source or isUpdatingMouseover then return end
    if unitIfMatch and CleveRoids.__mo.sources[source] ~= unitIfMatch then
      return
    end
    CleveRoids.__mo.sources[source] = nil
    local _, bestUnit = getBest()
    if bestUnit ~= CleveRoids.__mo.current then
      CleveRoids.__mo.current = bestUnit
      isUpdatingMouseover = true
      apply(bestUnit)
      isUpdatingMouseover = false
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

-- PERFORMANCE: Cache for splitStringIgnoringQuotes results
-- Key: str .. "|" .. separator_key, Value: result table
local _splitCache = {}
local _splitCacheSize = 0
local _SPLIT_CACHE_MAX = 256  -- Limit cache size to prevent unbounded growth

-- PERFORMANCE: Pre-built separator tables for common cases
local _defaultSeparator = { [";"] = ";" }
local _commaSeparator = { [","] = ",", [" "] = " " }
local _colonSeparator = { [":"] = ":" }

-- PERFORMANCE: Reusable result table pool
local _splitResultPool = {}
local _splitResultPoolSize = 0

local function getSplitResult()
    if _splitResultPoolSize > 0 then
        local r = _splitResultPool[_splitResultPoolSize]
        _splitResultPool[_splitResultPoolSize] = nil
        _splitResultPoolSize = _splitResultPoolSize - 1
        -- Clear the table for reuse
        for k in pairs(r) do r[k] = nil end
        return r
    end
    return {}
end

-- Return a result to the pool (call when done iterating)
function CleveRoids.ReleaseSplitResult(result)
    if result and _splitResultPoolSize < 16 then
        _splitResultPoolSize = _splitResultPoolSize + 1
        _splitResultPool[_splitResultPoolSize] = result
    end
end

function CleveRoids.splitStringIgnoringQuotes(str, separator)
    if not str then return {""} end

    -- PERFORMANCE: Build cache key and check cache
    local sepKey
    if separator == nil then
        sepKey = ";"
    elseif type(separator) == "table" then
        -- For table separators, use a simple identifier
        if separator[1] == "," and separator[2] == " " then
            sepKey = ",_"
        else
            sepKey = "t"
        end
    else
        sepKey = separator
    end

    local cacheKey = str .. "|" .. sepKey
    local cached = _splitCache[cacheKey]
    if cached then
        -- PERFORMANCE: Return cached result directly - callers should only iterate, not mutate
        -- This avoids table allocation on every cache hit
        return cached
    end

    local result = getSplitResult()
    local temp = ""
    local insideQuotes = false
    local separators

    -- PERFORMANCE: Use pre-built separator tables when possible
    if separator == nil then
        separators = _defaultSeparator
    elseif type(separator) == "table" then
        if separator[1] == "," and separator[2] == " " then
            separators = _commaSeparator
        elseif separator[1] == ":" then
            separators = _colonSeparator
        else
            separators = {}
            for _, s in separator do
                separators[s] = s
            end
        end
    else
        if separator == ";" then
            separators = _defaultSeparator
        elseif separator == ":" then
            separators = _colonSeparator
        else
            separators = { [separator] = separator }
        end
    end

    -- PERFORMANCE: Use local references and avoid repeated function calls
    local strlen = string.len(str)
    local strsub = string.sub
    local Trim = CleveRoids.Trim
    local tinsert = table.insert

    for i = 1, strlen do
        local char = strsub(str, i, i)

        if char == "\"" then
            insideQuotes = not insideQuotes
            temp = temp .. char
        elseif separators[char] and not insideQuotes then
            temp = Trim(temp)
            if temp ~= "" then tinsert(result, temp) end
            temp = ""
        else
            temp = temp .. char
        end
    end

    if temp ~= "" then
        temp = Trim(temp)
        tinsert(result, temp)
    end

    if not next(result) then
        result[1] = ""
    end

    -- PERFORMANCE: Cache the result (store a copy)
    if _splitCacheSize < _SPLIT_CACHE_MAX then
        local cacheCopy = {}
        for i = 1, table.getn(result) do
            cacheCopy[i] = result[i]
        end
        _splitCache[cacheKey] = cacheCopy
        _splitCacheSize = _splitCacheSize + 1
    end

    return result
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

-- PFUI v7.4.3+ NAMPOWER-BASED DEBUFF TRACKING INTEGRATION
-- When pfUI v7.4.3+ with Nampower v2.26+ is available, we leverage pfUI's
-- comprehensive debuff tracking tables instead of duplicating the event handlers.
-- This provides accurate caster GUID tracking, rank checking, combo point
-- duration calculation, and miss/dodge/parry/resist/immune detection.

-- Enhanced tables (populated by pfUI or standalone Nampower handlers)
lib.ownDebuffs = lib.ownDebuffs or {}       -- [targetGUID][spellName] = {startTime, duration, texture, rank, slot}
lib.ownSlots = lib.ownSlots or {}           -- [targetGUID][slot] = spellName (LEGACY - empty when pfUI 7.6+ is active)
lib.allSlots = lib.allSlots or {}           -- [targetGUID][slot] = {spellName, casterGuid, isOurs} (LEGACY - empty when pfUI 7.6+ is active)
lib.slotOwnership = lib.slotOwnership or {} -- [targetGUID][auraSlot] = {casterGuid, spellName, spellId, isOurs} (pfUI 7.6+ GetUnitField edition)
lib.allAuraCasts = lib.allAuraCasts or {}   -- [targetGUID][spellName][casterGuid] = {startTime, duration, rank}
lib.pendingCasts = lib.pendingCasts or {}   -- [targetGUID][spellName] = {casterGuid, rank, time, comboPoints}
lib.recentMisses = lib.recentMisses or {}   -- [targetGUID][spellName] = {time, spellId, targetName, reason} for miss/dodge/parry detection
lib.iconCache = lib.iconCache or {}          -- [spellId] = texture (shared with pfUI 7.6 or standalone)

-- Flag indicating whether enhanced pfUI tracking is available
lib.hasPfUIEnhanced = false
lib.hasStandaloneNampower = false
lib.hasPfUI76 = false

-- Check if pfUI v7.4.3+ with enhanced libdebuff is available
function lib:HasEnhancedPfUILibdebuff()
  -- Check pfUI exists
  if not pfUI then return false end

  -- Check version from TOC (stored in pfUI.version after ADDON_LOADED)
  -- Minimum required: 7.4.3
  local v = pfUI.version
  if not v or not v.major then return false end

  -- Version comparison: 7.4.3+
  if v.major > 7 then
    -- Continue to Nampower check
  elseif v.major < 7 then
    return false
  else
    -- major == 7
    if v.minor > 4 then
      -- Continue to Nampower check
    elseif v.minor < 4 then
      return false
    else
      -- minor == 4
      if (v.fix or 0) < 3 then
        return false
      end
    end
  end

  -- Verify Nampower version based on pfUI version:
  -- - pfUI 7.6+ (GetUnitField edition): requires Nampower v2.27.2+
  -- - pfUI 7.4.3 to 7.5.x (legacy): requires Nampower v2.26+
  if not GetNampowerVersion then return false end
  local npMajor, npMinor, npPatch = GetNampowerVersion()
  npPatch = npPatch or 0

  -- Check if this is pfUI 7.6+ (GetUnitField edition) by looking for the new table
  local isPfUI76 = pfUI.libdebuff_slot_ownership ~= nil

  if isPfUI76 then
    -- pfUI 7.6+ requires Nampower v2.27.2+
    if npMajor < 2 then return false end
    if npMajor == 2 and npMinor < 27 then return false end
    if npMajor == 2 and npMinor == 27 and npPatch < 2 then return false end
  else
    -- Legacy pfUI 7.4.3-7.5.x requires Nampower v2.26+
    if npMajor < 2 or (npMajor == 2 and npMinor < 26) then return false end
  end

  -- Finally verify the exposed tables exist
  -- NOTE: libdebuff_own_slots and libdebuff_all_slots are LEGACY stubs (empty) in pfUI 7.6+
  -- The new GetUnitField-based libdebuff uses libdebuff_slot_ownership instead
  if not pfUI.libdebuff_own then return false end
  if not pfUI.libdebuff_pending then return false end
  -- Check for either legacy tables (pre-7.6) or new slotOwnership table (7.6+)
  if not pfUI.libdebuff_all_slots and not pfUI.libdebuff_slot_ownership then return false end

  return true
end

-- Check if pfUI v7.6+ with enhanced cast tracking is available
-- pfUI 7.6 requires Nampower v2.27.2+ and exposes additional tables
function lib:HasPfUI76()
  if not pfUI then return false end

  local v = pfUI.version
  if not v or not v.major then return false end

  -- Version comparison: 7.6+
  if v.major < 7 then return false end
  if v.major == 7 and (v.minor or 0) < 6 then return false end

  -- Verify Nampower v2.27.2+ (pfUI 7.6 hard requirement)
  if not GetNampowerVersion then return false end
  local npMajor, npMinor, npPatch = GetNampowerVersion()
  npPatch = npPatch or 0
  if npMajor < 2 then return false end
  if npMajor == 2 and npMinor < 27 then return false end
  if npMajor == 2 and npMinor == 27 and npPatch < 2 then return false end

  -- Verify the new tables exist
  if not pfUI.libdebuff_casts then return false end
  if not pfUI.libdebuff_objects_guid then return false end

  return true
end

-- Icon caching helper: DBC lookup (fast) → SpellInfo fallback (slow)
function lib:GetCachedIcon(spellId)
  if not spellId then return nil end
  if lib.iconCache[spellId] then return lib.iconCache[spellId] end

  local texture = nil

  -- Try Nampower DBC lookup first (fast)
  if GetSpellRecField and GetSpellIconTexture then
    local iconId = GetSpellRecField(spellId, "spellIconID")
    if iconId and type(iconId) == "number" and iconId > 0 then
      texture = GetSpellIconTexture(iconId)
    end
  end

  -- Fallback to SpellInfo (slower but works without Nampower v2.27)
  if not texture and SpellInfo then
    local _, _, spellTex = SpellInfo(spellId)
    texture = spellTex
  end

  -- Final fallback
  if not texture then
    texture = "Interface\\Icons\\INV_Misc_QuestionMark"
  end

  lib.iconCache[spellId] = texture
  return texture
end

-- Initialize pfUI integration (call after ADDON_LOADED for pfUI)
function lib:InitPfUIIntegration()
  if lib:HasEnhancedPfUILibdebuff() then
    -- Link to pfUI's tables directly
    lib.ownDebuffs = pfUI.libdebuff_own
    lib.allAuraCasts = pfUI.libdebuff_all_auras
    lib.pendingCasts = pfUI.libdebuff_pending

    -- LEGACY slot tables (empty in pfUI 7.6+ GetUnitField edition, but kept for backwards compat)
    lib.ownSlots = pfUI.libdebuff_own_slots or lib.ownSlots
    lib.allSlots = pfUI.libdebuff_all_slots or lib.allSlots

    -- NEW: GetUnitField-based slot ownership (pfUI 7.6+)
    -- This replaces the legacy ownSlots/allSlots with stable aura slot tracking
    if pfUI.libdebuff_slot_ownership then
      lib.slotOwnership = pfUI.libdebuff_slot_ownership
    end

    lib.hasPfUIEnhanced = true
    lib.hasStandaloneNampower = false

    -- Check for pfUI 7.6+ additional tables (cast tracking, GUID objects, icon cache)
    if lib:HasPfUI76() then
      CleveRoids.hasPfUI76 = true
      lib.hasPfUI76 = true
      CleveRoids.castTracking = pfUI.libdebuff_casts
      lib.iconCache = pfUI.libdebuff_icon_cache or lib.iconCache
      -- lib.objects is already set by pfUI's CleveRoids.libdebuff = libdebuff override
      -- but explicitly sync if pfUI.libdebuff_objects_guid is available
      if pfUI.libdebuff_objects_guid then
        lib.objects = pfUI.libdebuff_objects_guid
      end
    end

    -- Unregister chat log events since SPELL_GO provides miss detection
    if CleveRoidsLibDebuffLearnFrame then
      CleveRoidsLibDebuffLearnFrame:UnregisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
    end

    if CleveRoids.debug then
      local v = pfUI.version
      local tierMsg = lib.hasPfUI76 and " (7.6+ cast tracking)" or ""
      DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cff33ff99[libdebuff]|r pfUI v%d.%d.%d enhanced tracking enabled%s",
          v.major, v.minor, v.fix or 0, tierMsg)
      )
    end

    return true
  end

  -- Check for standalone Nampower v2.26+ (when pfUI is not available or outdated)
  -- Standalone mode uses SPELL_GO and AURA_CAST events which are available in v2.26+
  if GetNampowerVersion then
    local npMajor, npMinor, npPatch = GetNampowerVersion()
    npPatch = npPatch or 0
    local hasMinVersion = npMajor > 2 or (npMajor == 2 and npMinor >= 26)
    if hasMinVersion then
      lib.hasStandaloneNampower = true
      lib.hasPfUIEnhanced = false

      -- Unregister chat log events since SPELL_GO provides miss detection
      if CleveRoidsLibDebuffLearnFrame then
        CleveRoidsLibDebuffLearnFrame:UnregisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
      end

      if CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
          string.format("|cff33ff99[libdebuff]|r Standalone Nampower v%d.%d.%d tracking enabled",
            npMajor, npMinor, npPatch)
        )
      end

      return true
    end
  end

  return false
end

-- Unique debuffs: Same spell overwrites itself when cast by different player
-- Only one instance can exist on a target (regardless of caster)
lib.uniqueDebuffs = lib.uniqueDebuffs or {
  ["Hunter's Mark"] = true,
  ["Scorpid Sting"] = true,
  ["Curse of Weakness"] = true,
  ["Curse of Recklessness"] = true,
  ["Curse of the Elements"] = true,
  ["Curse of Shadow"] = true,
  ["Curse of Tongues"] = true,
  ["Curse of Idiocy"] = true,
  ["Curse of Agony"] = true,
  ["Curse of Doom"] = true,
  ["Curse of Exhaustion"] = true,
  ["Judgement of Light"] = true,
  ["Judgement of Wisdom"] = true,
  ["Judgement of Justice"] = true,
  ["Judgement of the Crusader"] = true,
  ["Shadow Vulnerability"] = true,
  ["Shadow Weaving"] = true,
  ["Stormstrike"] = true,
  ["Sunder Armor"] = true,
  ["Expose Armor"] = true,
  ["Nightfall"] = true,
  ["Improved Scorch"] = true,
  ["Winter's Chill"] = true,
}

-- Debuff pairs that can overwrite each other (e.g., Faerie Fire variants)
lib.debuffOverwritePairs = lib.debuffOverwritePairs or {
  -- Faerie Fire variants
  ["Faerie Fire"] = "Faerie Fire (Feral)",
  ["Faerie Fire (Feral)"] = "Faerie Fire",

  -- Demo variants
  ["Demoralizing Shout"] = "Demoralizing Roar",
  ["Demoralizing Roar"] = "Demoralizing Shout",
}

-- Combo point abilities: Duration depends on combo points used
lib.combopointAbilities = lib.combopointAbilities or {
  ["Rip"] = true,
  ["Rupture"] = true,
  ["Kidney Shot"] = true,
  ["Slice and Dice"] = true,
  ["Expose Armor"] = true,
}

-- Check if a spell recently failed (miss/dodge/parry/resist/immune/evade)
-- @param spellName: The spell to check
-- @param targetGuid: (optional) If provided, check only for this target; otherwise check all targets
function lib:DidSpellFail(spellName, targetGuid)
  if not spellName then return false end
  local now = GetTime()

  if targetGuid then
    -- Check specific target
    if lib.recentMisses[targetGuid] and lib.recentMisses[targetGuid][spellName] then
      local data = lib.recentMisses[targetGuid][spellName]
      if data and data.time and (now - data.time) < 1 then
        return true
      end
    end
  else
    -- Check all targets (backwards compatibility)
    for _, spells in pairs(lib.recentMisses) do
      if spells[spellName] then
        local data = spells[spellName]
        if data and data.time and (now - data.time) < 1 then
          return true
        end
      end
    end
  end
  return false
end

-- Recent combat log miss reasons (immune/reflect/evade)
-- Structure: [targetName][spellName] = { time = X, reason = "immune"|"reflect"|"evade" }
lib.recentCombatLogReasons = lib.recentCombatLogReasons or {}

-- Process miss reason from combat log correlation
-- Called 300ms after SPELL_GO with miss to allow combat log to arrive
-- Parameters:
--   verifyData: { spellName, spellId, targetGuid, targetName, checkTime }
function lib:ProcessMissReason(verifyData)
  if not verifyData or not verifyData.spellName or not verifyData.targetName then
    return
  end

  local spellName = verifyData.spellName
  local targetName = verifyData.targetName
  local targetGuid = verifyData.targetGuid
  local spellId = verifyData.spellId
  local now = GetTime()

  -- Look up reason from combat log correlation table
  local reason = nil
  if lib.recentCombatLogReasons[targetName] and lib.recentCombatLogReasons[targetName][spellName] then
    local reasonData = lib.recentCombatLogReasons[targetName][spellName]
    -- Only use if within 1 second of the miss
    if (now - reasonData.time) < 1.5 then
      reason = reasonData.reason
    end
    -- Clean up
    lib.recentCombatLogReasons[targetName][spellName] = nil
  end

  -- Also check for generic target entries (e.g., "Target is immune" without spell)
  if not reason and lib.recentCombatLogReasons[targetName] and lib.recentCombatLogReasons[targetName]["_generic"] then
    local reasonData = lib.recentCombatLogReasons[targetName]["_generic"]
    if (now - reasonData.time) < 1.5 then
      reason = reasonData.reason
    end
    lib.recentCombatLogReasons[targetName]["_generic"] = nil
  end

  -- Update recentMisses with the reason
  if lib.recentMisses[targetGuid] and lib.recentMisses[targetGuid][spellName] then
    lib.recentMisses[targetGuid][spellName].reason = reason
  end

  if CleveRoids.debug then
    local reasonStr = reason or "unknown (no combat log match)"
    DEFAULT_CHAT_FRAME:AddMessage(
      string.format("|cffff9900[ProcessMissReason]|r %s on %s: %s",
        spellName, targetName, reasonStr)
    )
  end

  -- Handle based on reason
  if reason == "immune" then
    -- Immunity already recorded by ParseImmunityCombatLog, no additional action needed
    -- But we can verify CC immunity detection here for CC spells
    if CleveRoids.debug then
      DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cff00ff00[Immunity Verified]|r %s is immune to %s", targetName, spellName)
      )
    end

  elseif reason == "reflect" then
    -- Reflect is a temporary state (buff-based), don't record as permanent immunity
    -- Store in a temporary reflect tracking table for awareness
    lib.recentReflects = lib.recentReflects or {}
    lib.recentReflects[targetName] = lib.recentReflects[targetName] or {}
    lib.recentReflects[targetName][spellName] = {
      time = now,
      spellId = spellId,
    }

    if CleveRoids.debug then
      DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cffff00ff[Spell Reflected]|r %s reflected %s", targetName, spellName)
      )
    end

  elseif reason == "evade" then
    -- Evade is a temporary mob state (out of range, pathing issue, etc.)
    -- Don't record as immunity - this is NOT a permanent trait
    lib.recentEvades = lib.recentEvades or {}
    lib.recentEvades[targetName] = lib.recentEvades[targetName] or {}
    lib.recentEvades[targetName][spellName] = {
      time = now,
      spellId = spellId,
    }

    if CleveRoids.debug then
      DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cffaaaaaa[Evade]|r %s evaded %s (temporary state, not immunity)",
          targetName, spellName)
      )
    end
  end

  -- Clean up recentMisses entry for this target/spell after processing
  if lib.recentMisses and lib.recentMisses[targetGuid] then
    lib.recentMisses[targetGuid][spellName] = nil
    -- Clean up empty target tables
    local isEmpty = true
    for _ in pairs(lib.recentMisses[targetGuid]) do
      isEmpty = false
      break
    end
    if isEmpty then
      lib.recentMisses[targetGuid] = nil
    end
  end
end

-- Check if a spell was recently reflected by a target
-- Returns: true if reflected within last 3 seconds
function lib:WasSpellReflected(targetName, spellName)
  if not targetName then return false end

  local now = GetTime()
  if lib.recentReflects and lib.recentReflects[targetName] then
    if spellName then
      -- Check specific spell
      local data = lib.recentReflects[targetName][spellName]
      if data and (now - data.time) < 3 then
        return true
      end
    else
      -- Check any spell on target
      for _, data in pairs(lib.recentReflects[targetName]) do
        if (now - data.time) < 3 then
          return true
        end
      end
    end
  end
  return false
end

-- Check if target recently evaded
-- Returns: true if evaded within last 3 seconds
function lib:DidTargetEvade(targetName)
  if not targetName then return false end

  local now = GetTime()
  if lib.recentEvades and lib.recentEvades[targetName] then
    for _, data in pairs(lib.recentEvades[targetName]) do
      if (now - data.time) < 3 then
        return true
      end
    end
  end
  return false
end

-- Periodic cleanup of stale tracking tables
-- Call this periodically (e.g., every 30 seconds) to prevent memory leaks
local lastCleanupTime = 0
function lib:CleanupStaleTrackingData()
  local now = GetTime()

  -- Only run every 30 seconds
  if (now - lastCleanupTime) < 30 then
    return
  end
  lastCleanupTime = now

  local staleTime = 10  -- Entries older than 10 seconds are cleaned up

  -- Clean recentCombatLogReasons
  if lib.recentCombatLogReasons then
    for targetName, spells in pairs(lib.recentCombatLogReasons) do
      for spellName, data in pairs(spells) do
        if (now - data.time) > staleTime then
          spells[spellName] = nil
        end
      end
      -- Remove empty target tables
      if not next(spells) then
        lib.recentCombatLogReasons[targetName] = nil
      end
    end
  end

  -- Clean recentMisses
  if lib.recentMisses then
    for guid, spells in pairs(lib.recentMisses) do
      for spellName, data in pairs(spells) do
        if (now - data.time) > staleTime then
          spells[spellName] = nil
        end
      end
      if not next(spells) then
        lib.recentMisses[guid] = nil
      end
    end
  end

  -- Clean recentReflects
  if lib.recentReflects then
    for targetName, spells in pairs(lib.recentReflects) do
      for spellName, data in pairs(spells) do
        if (now - data.time) > staleTime then
          spells[spellName] = nil
        end
      end
      if not next(spells) then
        lib.recentReflects[targetName] = nil
      end
    end
  end

  -- Clean recentEvades
  if lib.recentEvades then
    for targetName, spells in pairs(lib.recentEvades) do
      for spellName, data in pairs(spells) do
        if (now - data.time) > staleTime then
          spells[spellName] = nil
        end
      end
      if not next(spells) then
        lib.recentEvades[targetName] = nil
      end
    end
  end

  -- Clean pendingCasts (including combo point data from SPELL_GO)
  if lib.pendingCasts then
    for guid, spells in pairs(lib.pendingCasts) do
      for spellName, data in pairs(spells) do
        local capturedAt = data.capturedAt or data.time or 0
        if (now - capturedAt) > staleTime then
          spells[spellName] = nil
        end
      end
      if not next(spells) then
        lib.pendingCasts[guid] = nil
      end
    end
  end
end

-- Get the caster GUID for a debuff on a target
-- Returns: casterGuid or nil
function lib:GetDebuffCaster(unit, spellName)
  if not spellName then return nil end

  local _, guid = UnitExists(unit)
  if not guid then return nil end
  guid = CleveRoids.NormalizeGUID(guid)

  -- Check own debuffs first
  if lib.ownDebuffs[guid] and lib.ownDebuffs[guid][spellName] then
    local playerGuid = nil
    if UnitExists then
      local _, pg = UnitExists("player")
      playerGuid = pg
    end
    return playerGuid
  end

  -- Check slotOwnership (pfUI 7.6+ GetUnitField edition) for caster info
  if lib.slotOwnership[guid] then
    for auraSlot, slotData in pairs(lib.slotOwnership[guid]) do
      if slotData.spellName == spellName then
        return slotData.casterGuid
      end
    end
  end

  -- LEGACY: Check allSlots for caster info (pre-pfUI 7.6)
  if lib.allSlots[guid] then
    for slot, slotData in pairs(lib.allSlots[guid]) do
      if slotData.spellName == spellName then
        return slotData.casterGuid
      end
    end
  end

  -- Check allAuraCasts
  if lib.allAuraCasts[guid] and lib.allAuraCasts[guid][spellName] then
    -- Return first caster found (there should typically be only one for unique debuffs)
    for casterGuid, _ in pairs(lib.allAuraCasts[guid][spellName]) do
      return casterGuid
    end
  end

  return nil
end

-- Check if a debuff on a target is from the player
-- Returns: true if player's debuff, false otherwise
function lib:IsOurDebuff(unit, spellName)
  if not spellName then return false end

  local _, guid = UnitExists(unit)
  if not guid then return false end
  guid = CleveRoids.NormalizeGUID(guid)

  -- Check own debuffs
  if lib.ownDebuffs[guid] and lib.ownDebuffs[guid][spellName] then
    return true
  end

  -- Check slotOwnership (pfUI 7.6+ GetUnitField edition) for isOurs flag
  if lib.slotOwnership[guid] then
    for auraSlot, slotData in pairs(lib.slotOwnership[guid]) do
      if slotData.spellName == spellName then
        return slotData.isOurs == true
      end
    end
  end

  -- LEGACY: Check allSlots for isOurs flag (pre-pfUI 7.6)
  if lib.allSlots[guid] then
    for slot, slotData in pairs(lib.allSlots[guid]) do
      if slotData.spellName == spellName then
        return slotData.isOurs == true
      end
    end
  end

  return false
end

-- Get all tracked debuffs on a target
-- Returns: table of {spellName = {duration, timeleft, casterGuid, isOurs, stacks}}
function lib:GetAllDebuffsOnTarget(guid)
  if not guid then return {} end
  guid = CleveRoids.NormalizeGUID(guid)

  local result = {}
  local now = GetTime()

  -- Gather from ownDebuffs
  if lib.ownDebuffs[guid] then
    for spellName, data in pairs(lib.ownDebuffs[guid]) do
      if data.startTime and data.duration then
        local timeleft = (data.startTime + data.duration) - now
        if timeleft > 0 then
          result[spellName] = {
            duration = data.duration,
            timeleft = timeleft,
            casterGuid = nil, -- Player's own, get from UnitExists("player")
            isOurs = true,
            stacks = 1,
            rank = data.rank,
            slot = data.slot,
          }
        end
      end
    end
  end

  -- Gather from allAuraCasts (other players' debuffs)
  if lib.allAuraCasts[guid] then
    for spellName, casterTable in pairs(lib.allAuraCasts[guid]) do
      if not result[spellName] then
        for casterGuid, data in pairs(casterTable) do
          if data.startTime and data.duration then
            local timeleft = (data.startTime + data.duration) - now
            if timeleft > 0 then
              result[spellName] = {
                duration = data.duration,
                timeleft = timeleft,
                casterGuid = casterGuid,
                isOurs = false,
                stacks = 1,
                rank = data.rank,
              }
              break  -- Only store first active caster's data
            end
          end
        end
      end
    end
  end

  return result
end

-- Check if a pending cast exists for a spell on a target
function lib:HasPendingCast(targetGuid, spellName)
  if not targetGuid or not spellName then return false end
  targetGuid = CleveRoids.NormalizeGUID(targetGuid)

  if lib.pendingCasts[targetGuid] and lib.pendingCasts[targetGuid][spellName] then
    local data = lib.pendingCasts[targetGuid][spellName]
    -- Pending casts expire after 1 second
    if data.time and (GetTime() - data.time) < 1 then
      return true
    end
  end

  return false
end

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

  [9007] = 18,    -- Pounce Bleed (Rank 1) - triggered by Pounce 9005
  [9824] = 18,    -- Pounce Bleed (Rank 2) - triggered by Pounce 9823
  [9826] = 18,    -- Pounce Bleed (Rank 3) - triggered by Pounce 9827

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

  -- NOTE: Judgements moved to sharedDebuffs for proper target scanning
  -- NOTE: 51750 is the CAST spell for Turtle WoW, not a debuff (debuff is 51752)

  -- SHAMAN
  -- NOTE: Flame Shock is 15s in Turtle WoW (was 12s in vanilla)
  [8050] = 15,    -- Flame Shock (Rank 1)
  [8052] = 15,    -- Flame Shock (Rank 2)
  [8053] = 15,    -- Flame Shock (Rank 3)
  [10447] = 15,   -- Flame Shock (Rank 4)
  [10448] = 15,   -- Flame Shock (Rank 5)
  [29228] = 15,   -- Flame Shock (Rank 6)

  -- Frost Shock
  [8056] = 8,     -- Frost Shock (Rank 1)
  [8058] = 8,     -- Frost Shock (Rank 2)
  [10472] = 8,    -- Frost Shock (Rank 3)
  [10473] = 8,    -- Frost Shock (Rank 4)
}

-- SHARED DEBUFFS: Only one instance exists on a target, shared/refreshed by all players
-- These are armor reductions, attack power reductions, and marks
lib.sharedDebuffs = lib.sharedDebuffs or {
  -- PALADIN JUDGEMENTS (tracked as shared so SeedUnit picks them up from target scanning)
  [20184] = 10,   -- Judgement of Justice
  [20185] = 10,   -- Judgement of Light (Rank 1)
  [20267] = 10,   -- Judgement of Light (Rank 2)
  [20268] = 10,   -- Judgement of Light (Rank 3)
  [20271] = 10,   -- Judgement of Light (Rank 4)
  [20186] = 10,   -- Judgement of Wisdom (Rank 1)
  [20354] = 10,   -- Judgement of Wisdom (Rank 2)
  [20355] = 10,   -- Judgement of Wisdom (Rank 3)
  [51751] = 10,   -- Judgement of Wisdom (Rank 4) - Turtle WoW
  [51752] = 10,   -- Judgement of Wisdom (Rank 5) - Turtle WoW
  [21183] = 10,   -- Judgement of the Crusader (Rank 1)
  [20183] = 10,   -- Judgement of the Crusader (Rank 2)
  [20300] = 10,   -- Judgement of the Crusader (Rank 3)
  [20301] = 10,   -- Judgement of the Crusader (Rank 4)
  [20302] = 10,   -- Judgement of the Crusader (Rank 5)
  [20303] = 10,   -- Judgement of the Crusader (Rank 6)
  [51752] = 10,   -- Turtle WoW: Judgement of Wisdom debuff

  -- WARRIOR
  [7386] = 30,    -- Sunder Armor (Rank 1)
  [7405] = 30,    -- Sunder Armor (Rank 2)
  [8380] = 30,    -- Sunder Armor (Rank 3)
  [8647] = 30,    -- Sunder Armor (Rank 4)
  [11597] = 30,   -- Sunder Armor (Rank 5)

  [6343] = 10,    -- Thunder Clap (Rank 1)
  [8198] = 14,    -- Thunder Clap (Rank 2)
  [8205] = 18,    -- Thunder Clap (Rank 3)
  [11580] = 22,   -- Thunder Clap (Rank 4)
  [11581] = 26,   -- Thunder Clap (Rank 5)
  [13532] = 30,   -- Thunder Clap (Rank 6)

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

-- JUDGEMENT SPELLS: These are refreshed by the paladin's melee attacks
-- Track them by spell ID for refresh detection
lib.judgementSpells = lib.judgementSpells or {
  -- Vanilla IDs
  [20184] = true,   -- Judgement of Justice
  [20185] = true,   -- Judgement of Light (Rank 1)
  [20267] = true,   -- Judgement of Light (Rank 2)
  [20268] = true,   -- Judgement of Light (Rank 3)
  [20271] = true,   -- Judgement of Light (Rank 4)
  [20186] = true,   -- Judgement of Wisdom (Rank 1)
  [20354] = true,   -- Judgement of Wisdom (Rank 2)
  [20355] = true,   -- Judgement of Wisdom (Rank 3)
  [21183] = true,   -- Judgement of the Crusader (Rank 1)
  [20183] = true,   -- Judgement of the Crusader (Rank 2)
  [20300] = true,   -- Judgement of the Crusader (Rank 3)
  [20301] = true,   -- Judgement of the Crusader (Rank 4)
  [20302] = true,   -- Judgement of the Crusader (Rank 5)
  [20303] = true,   -- Judgement of the Crusader (Rank 6)

  -- Turtle WoW custom judgement IDs (debuff IDs only, not cast spells)
  [51751] = true,   -- Judgement of Wisdom (Rank 4) - Turtle WoW
  [51752] = true,   -- Judgement of Wisdom (Rank 5) - Turtle WoW
  -- Auto-detection will discover other Turtle WoW judgement debuffs at runtime
}

-- Pending judgement casts: Map cast spell ID to target for debuff ID detection
-- When paladin casts Judgement, we need to find what debuff actually appears
lib.pendingJudgements = lib.pendingJudgements or {}

-- Detected judgement debuff IDs: Maps debuff name patterns to spell IDs
-- This gets populated as we discover what debuffs actually appear after casting
lib.detectedJudgementDebuffIDs = lib.detectedJudgementDebuffIDs or {}

-- NOTE: Judgement refresh on melee hits is handled by evJudgement (below)
-- It only uses chat-based detection when SuperWoW is unavailable;
-- otherwise Core.lua handles it via UNIT_CASTEVENT (MAINHAND/OFFHAND)

-- Combined table for backwards compatibility (will be deprecated)
lib.durations = lib.durations or {}
for k, v in pairs(lib.personalDebuffs) do
  lib.durations[k] = v
end
for k, v in pairs(lib.sharedDebuffs) do
  lib.durations[k] = v
end

-- MUTUALLY EXCLUSIVE DEBUFFS: Only one per caster can exist on a target
-- When a new curse is applied, remove any other curses from the same caster
lib.curseSpellIDs = lib.curseSpellIDs or {
  -- Curse of Agony
  [980] = true, [1014] = true, [6217] = true, [11711] = true, [11712] = true, [11713] = true,
  -- Curse of Doom
  [603] = true,
  -- Curse of Recklessness
  [704] = true, [7658] = true, [7659] = true, [11717] = true,
  -- Curse of Shadow
  [17862] = true, [17937] = true,
  -- Curse of Elements
  [1490] = true, [11721] = true, [11722] = true,
  -- Curse of Tongues
  [1714] = true, [11719] = true,
  -- Curse of Weakness
  [702] = true, [1108] = true, [6205] = true, [7646] = true, [11707] = true, [11708] = true,
  -- Curse of Exhaustion
  [18223] = true,
}

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

-- Helper function to extract numeric rank from spell ID
-- Returns rank number (1, 2, 3, etc.) or 0 if no rank found
function lib:GetSpellRank(spellID)
  if not spellID then return 0 end
  local name, rankStr = SpellInfo(spellID)
  if not rankStr or rankStr == "" then return 0 end

  -- Handle different rank formats
  -- Could be: "Rank 9", "9", or number 9
  local rankType = type(rankStr)

  if rankType == "number" then
    return rankStr
  elseif rankType == "string" then
    -- Try to extract number from "Rank X" format or just "X"
    local rank = string.match(rankStr, "(%d+)")
    return tonumber(rank) or 0
  end

  return 0
end

-- Helper function to get spell base name (without rank)
function lib:GetSpellBaseName(spellID)
  if not spellID then return nil end
  local name = SpellInfo(spellID)
  if not name then return nil end

  -- Remove rank suffix
  return string.gsub(name, "%s*%(Rank %d+%)", "")
end

-- Track rank refreshes for pfUI integration
lib.rankRefreshOverrides = lib.rankRefreshOverrides or {}

-- Helper function to check if we should apply a debuff based on rank comparison
-- Returns: true (apply), false (skip), or {refresh=spellID, duration=X} (refresh higher rank)
-- Also removes lower/equal rank versions when applying a higher rank
function lib:ShouldApplyDebuffRank(targetGUID, newSpellID)
  if not targetGUID or not newSpellID then return true end

  -- Get base name and rank of new spell
  local newBaseName = lib:GetSpellBaseName(newSpellID)
  local newRank = lib:GetSpellRank(newSpellID)

  if not newBaseName then return true end

  -- Track highest existing rank and spell IDs to remove
  local highestExistingRank = 0
  local highestExistingSpellID = nil
  local highestExistingDuration = nil
  local spellIDsToRemove = {}

  -- Check all active debuffs on target for same base name
  if lib.objects[targetGUID] then
    for existingSpellID, rec in pairs(lib.objects[targetGUID]) do
      if rec and rec.start and rec.duration and existingSpellID ~= newSpellID then
        -- Check if debuff is still active
        local remaining = rec.duration + rec.start - GetTime()
        if remaining > 0 then
          -- Check if same spell (same base name)
          local existingBaseName = lib:GetSpellBaseName(existingSpellID)
          if existingBaseName == newBaseName then
            -- Same spell - track for potential removal
            local existingRank = lib:GetSpellRank(existingSpellID)

            if existingRank > highestExistingRank then
              highestExistingRank = existingRank
              highestExistingSpellID = existingSpellID
              highestExistingDuration = rec.duration
            end

            -- Mark all same-name spells for potential removal
            table.insert(spellIDsToRemove, existingSpellID)
          end
        end
      end
    end
  end

  -- If a higher rank exists, preserve its remaining time instead of blocking
  if newRank > 0 and highestExistingRank > 0 and newRank < highestExistingRank then
    -- Calculate remaining time on the higher rank
    local rec = lib.objects[targetGUID][highestExistingSpellID]
    local timeRemaining = rec.duration + rec.start - GetTime()

    -- Store refresh override for pfUI integration
    lib.rankRefreshOverrides[newBaseName] = {
      timestamp = GetTime(),
      targetGUID = targetGUID,
      lowerRankCast = newRank,
      higherRankActive = highestExistingRank,
      refreshSpellID = highestExistingSpellID,
      preservedTimeRemaining = timeRemaining
    }

    if CleveRoids.debug then
      DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cff00aaff[Rank Preserve]|r Cast %s Rank %d, preserving Rank %d timer (%.1fs remaining)",
          newBaseName, newRank, highestExistingRank, timeRemaining)
      )
    end

    -- Return special value indicating we should preserve the higher rank's timer
    return {
      preserve = highestExistingSpellID,
      timeRemaining = timeRemaining,
      targetGUID = targetGUID
    }
  end

  -- Remove all other ranks (lower or equal) before applying new rank
  if table.getn(spellIDsToRemove) > 0 then
    -- Get target name for pfUI cleanup
    local targetName = lib.guidToName[targetGUID]

    for _, removeID in ipairs(spellIDsToRemove) do
      if lib.objects[targetGUID][removeID] then
        local removeRank = lib:GetSpellRank(removeID)
        lib.objects[targetGUID][removeID] = nil

        if CleveRoids.debug then
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cff00ff00[Rank Check]|r Removed %s (Rank %d) before applying Rank %d",
              newBaseName, removeRank, newRank)
          )
        end
      end
    end

    -- Also clean up pfUI's tracking to prevent it from showing old ranks
    if pfUI and pfUI.api and pfUI.api.libdebuff and targetName then
      local pflib = pfUI.api.libdebuff

      if pflib.objects and pflib.objects[targetName] then
        for level, effects in pairs(pflib.objects[targetName]) do
          if type(effects) == "table" and effects[newBaseName] then
            -- Remove the old rank entry from pfUI
            effects[newBaseName] = nil

            if CleveRoids.debug then
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cff00ff00[Rank Check]|r Removed %s from pfUI tracking before applying new rank",
                  newBaseName)
              )
            end
            break
          end
        end
      end
    end
  end

  -- Apply the new rank
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

  -- CURSE REPLACEMENT: Only one curse per caster can exist on a target
  -- When casting a new curse, remove all other curses from tracking for this target
  if lib.curseSpellIDs[spellID] then
    for trackedID, rec in pairs(lib.objects[guid]) do
      if lib.curseSpellIDs[trackedID] and trackedID ~= spellID then
        if CleveRoids.debug then
          local oldName = SpellInfo(trackedID) or "Unknown"
          local newName = SpellInfo(spellID) or "Unknown"
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff8800[Curse Replace]|r %s replaced by %s on %s",
              oldName, newName, unitName or "target"))
        end
        lib.objects[guid][trackedID] = nil
      end
    end
  end

  local rec = lib.objects[guid][spellID] or {}
  rec.spellID = spellID
  rec.start = GetTime()
  rec.duration = duration
  rec.stacks = stacks or 0
  rec.caster = caster

  lib.objects[guid][spellID] = rec

  -- PFUI INTEGRATION: Inject all tracked debuffs into pfUI's libdebuff
  -- This allows pfUI to show accurate timers for ALL tracked debuffs (player + other casters)
  -- For shared debuffs like Sunder Armor, we want pfUI to show timers regardless of who cast it
  if pfUI and pfUI.api and pfUI.api.libdebuff and unitName then
    local pflib = pfUI.api.libdebuff
    local spellName = SpellInfo(spellID)

    if spellName and pflib.AddEffect then
      -- Get target level for pfUI's tracking structure
      local targetLevel = UnitLevel(guid) or UnitLevel("target") or 1

      -- Strip rank from spell name for pfUI (it uses base names)
      local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")

      -- Also register the duration in pfUI's duration table
      if pflib.debuffs then
        pflib.debuffs[baseName] = duration
      end

      -- Add the effect to pfUI's tracking
      -- Use "player" as caster for pfUI compatibility (it expects this format)
      pflib:AddEffect(unitName, targetLevel, baseName, duration, "player")

      if CleveRoids.debug then
        local casterStr = (caster == "player") and "player" or "other"
        DEFAULT_CHAT_FRAME:AddMessage(
          string.format("|cff00ff00[pfUI Inject]|r %s (%ds) on %s (level %d) [caster: %s]",
            baseName, duration, unitName, targetLevel, casterStr)
        )
      end
    end
  end

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

  local texture, stacks, dtype, spellID = nil, nil, nil, nil

  -- SuperWoW debuff slots: 1-16 are regular debuffs, 17-48 overflow to buff slots 1-32
  -- See: https://forum.turtle-wow.org/viewtopic.php?t=13281
  if id <= 16 then
    -- Regular debuff slot
    texture, stacks, dtype, spellID = UnitDebuff(unit, id)
  else
    -- Overflow debuff in buff slot: debuff index 17 = buff index 1, etc.
    local buffIndex = id - 16
    if buffIndex <= 32 then
      texture, stacks, spellID = UnitBuff(unit, buffIndex)
      -- Only accept buffs that are known debuffs (either static or learned durations, including combo durations)
      if texture and spellID and lib:GetDuration(spellID) <= 0 then
        return nil
      end
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
          -- SHARED DEBUFFS: Check if already tracked and handle refresh detection
          -- Player's casts are tracked via UNIT_CASTEVENT, but OTHER players' casts
          -- only trigger UNIT_AURA events. Detect refreshes via stack count changes.
          local existing = lib.objects[guid] and lib.objects[guid][spellID]

          if existing and existing.start and existing.duration then
            -- Already tracked - check if debuff was refreshed (by player or others)
            if existing.stacks ~= stacks then
              local oldStacks = existing.stacks or 0
              existing.stacks = stacks

              -- If stacks INCREASED, debuff was refreshed - reset timer to full duration
              -- This catches refreshes from other players (we can't detect via UNIT_CASTEVENT)
              if (stacks or 0) > oldStacks then
                existing.start = GetTime()
                existing.duration = duration

                -- PFUI INTEGRATION: Inject refreshed timer into pfUI
                if pfUI and pfUI.api and pfUI.api.libdebuff and unitName then
                  local pflib = pfUI.api.libdebuff
                  local spellName = SpellInfo(spellID)
                  if spellName and pflib.AddEffect then
                    local targetLevel = UnitLevel(unit) or 1
                    local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                    if pflib.debuffs then
                      pflib.debuffs[baseName] = duration
                    end
                    pflib:AddEffect(unitName, targetLevel, baseName, duration, "player")
                  end
                end

                if CleveRoids.debug then
                  local spellName = SpellInfo(spellID) or "Unknown"
                  DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffaaff00[DEBUG SeedUnit Debuff]|r %s (ID:%d) stack increased %d->%d, timer RESET to %ds (refresh detected)",
                      spellName, spellID, oldStacks, stacks or 0, duration)
                  )
                end
              else
                -- Stacks decreased (shouldn't happen normally) - just update stacks, preserve timer
                if CleveRoids.debug then
                  local spellName = SpellInfo(spellID) or "Unknown"
                  DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffaaff00[DEBUG SeedUnit Debuff]|r %s (ID:%d) updated stacks to %d (timer preserved)",
                      spellName, spellID, stacks or 0)
                  )
                end
              end
            end
            -- NOTE: When stacks stay the same (e.g., already at 5/5 Sunder), we can't detect
            -- refreshes from other players. This is a fundamental limitation without server-side
            -- duration data. The timer continues from the last known refresh.
          else
            -- First time seeing this debuff - add with full duration
            -- Check for combo spell duration
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
            lib:AddEffect(guid, unitName, spellID, duration, stacks, nil)
          end
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
          -- SHARED DEBUFFS (overflow): Check if already tracked and handle refresh detection
          -- Same logic as regular debuff slots - detect refreshes via stack count changes.
          local existing = lib.objects[guid] and lib.objects[guid][spellID]

          if existing and existing.start and existing.duration then
            -- Already tracked - check if debuff was refreshed (by player or others)
            if existing.stacks ~= stacks then
              local oldStacks = existing.stacks or 0
              existing.stacks = stacks

              -- If stacks INCREASED, debuff was refreshed - reset timer to full duration
              if (stacks or 0) > oldStacks then
                existing.start = GetTime()
                existing.duration = duration

                -- PFUI INTEGRATION: Inject refreshed timer into pfUI
                if pfUI and pfUI.api and pfUI.api.libdebuff and unitName then
                  local pflib = pfUI.api.libdebuff
                  local spellName = SpellInfo(spellID)
                  if spellName and pflib.AddEffect then
                    local targetLevel = UnitLevel(unit) or 1
                    local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                    if pflib.debuffs then
                      pflib.debuffs[baseName] = duration
                    end
                    pflib:AddEffect(unitName, targetLevel, baseName, duration, "player")
                  end
                end

                if CleveRoids.debug then
                  local spellName = SpellInfo(spellID) or "Unknown"
                  DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffaaff00[DEBUG SeedUnit Buff]|r %s (ID:%d) stack increased %d->%d, timer RESET to %ds (refresh detected)",
                      spellName, spellID, oldStacks, stacks or 0, duration)
                  )
                end
              else
                -- Stacks decreased (shouldn't happen normally) - just update stacks, preserve timer
                if CleveRoids.debug then
                  local spellName = SpellInfo(spellID) or "Unknown"
                  DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffaaff00[DEBUG SeedUnit Buff]|r %s (ID:%d) updated stacks to %d (timer preserved)",
                      spellName, spellID, stacks or 0)
                  )
                end
              end
            end
          else
            -- First time seeing this debuff - add with full duration
            -- Check for combo spell duration
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
            lib:AddEffect(guid, unitName, spellID, duration, stacks, nil)
          end
        end
      end
    end
  end
end

-- Carnage refresh system
-- NOTE: Carnage proc detection is now handled in ComboPointTracker.lua via PLAYER_COMBO_POINTS event
-- When Carnage procs, combo points don't drop to 0 after Ferocious Bite (they stay at 1)
-- The ApplyCarnageRefresh function below is called from ComboPointTracker when a proc is detected

-- WARLOCK DARK HARVEST: Duration Acceleration System (TWoW Custom)
-- Credits: Avitasia / Cursive addon
-- Dark Harvest is a channeled spell that accelerates DoT tick rate by 30%
-- While channeling, DoTs on the target expire 30% faster

-- Calculate Dark Harvest reduction for a debuff record
-- Returns the amount of time to subtract from remaining duration
function lib.GetDarkHarvestReduction(rec)
  if not rec or not rec.dhStartTime then
    return 0
  end

  local endTime = rec.dhEndTime or GetTime()
  local dhActiveTime = endTime - rec.dhStartTime
  if dhActiveTime > 0 then
    return dhActiveTime * 0.3  -- 30% acceleration
  end
  return 0
end

-- Track Dark Harvest start for all DoTs on target
function lib.ApplyDarkHarvestStart(targetGUID)
  if not lib.objects[targetGUID] then return end

  local now = GetTime()
  for spellID, rec in pairs(lib.objects[targetGUID]) do
    if type(rec) == "table" and rec.duration and rec.start then
      -- Only affect DoTs (debuffs with duration > 0 that tick)
      -- Skip if already has dhStartTime (avoid double-tracking)
      if not rec.dhStartTime then
        rec.dhStartTime = now
        rec.dhEndTime = nil  -- Clear any previous end time
      end
    end
  end

  if CleveRoids.debug then
    DEFAULT_CHAT_FRAME:AddMessage(
      string.format("|cff9482c9[Dark Harvest]|r Started accelerating DoTs on %s",
        lib.guidToName[targetGUID] or "Unknown")
    )
  end
end

-- Track Dark Harvest end for all DoTs on target
function lib.ApplyDarkHarvestEnd(targetGUID)
  if not lib.objects[targetGUID] then return end

  local now = GetTime()
  for spellID, rec in pairs(lib.objects[targetGUID]) do
    if type(rec) == "table" and rec.dhStartTime and not rec.dhEndTime then
      rec.dhEndTime = now
    end
  end
end

-- Get time remaining for a debuff, accounting for Dark Harvest acceleration
function lib.GetTimeRemainingWithDarkHarvest(rec)
  if not rec or not rec.duration or not rec.start then
    return 0
  end

  local baseRemaining = rec.duration + rec.start - GetTime()
  local dhReduction = lib.GetDarkHarvestReduction(rec)

  return baseRemaining - dhReduction
end

-- Personal debuff pending tracking system
-- Stores personal debuffs to be added after 0.5s delay (to verify they weren't dodged/parried/blocked)
-- Format: { [index] = { timestamp = GetTime(), targetGUID = guid, targetName = name, spellID = id, duration = X, comboPoints = CP } }
lib.pendingPersonalDebuffs = lib.pendingPersonalDebuffs or {}

-- CC (Crowd Control) pending tracking system
-- Stores CC spells to verify they landed (for immunity detection)
-- Format: { [index] = { timestamp = GetTime(), targetGUID = guid, targetName = name, spellID = id, ccType = "stun" } }
lib.pendingCCDebuffs = lib.pendingCCDebuffs or {}

-- Shared debuff pending tracking system
-- Stores shared debuffs to verify they landed (for immunity detection by spell school)
-- Format: { [index] = { timestamp = GetTime(), targetGUID = guid, targetName = name, spellID = id, school = "arcane", duration = X, stacks = N } }
lib.pendingSharedDebuffs = lib.pendingSharedDebuffs or {}

-- Spells with HIDDEN CC debuffs - these apply CC effects but don't show visible debuffs
-- Pounce stun is hidden - the target is stunned but no debuff icon appears
-- These spells use extended verification (0.4s instead of 0.2s) to allow time for:
--   1. "afflicted by" combat log messages to arrive and confirm success
--   2. Mechanic-based ValidateUnitCC check (if the stun is internally tracked)
-- If neither confirms the CC landed, immunity is recorded
lib.hiddenCCSpells = {
  [9005] = true,   -- Pounce (Rank 1)
  [9823] = true,   -- Pounce (Rank 2)
  [9827] = true,   -- Pounce (Rank 3)
}

-- Reverse lookup: spell NAME -> immunity type for combat log tracking
-- Used by ParseAfflictedCombatLog to confirm spells landed via "afflicted by" messages
-- Format: { ["SpellName"] = { type = "cc" or "school", value = "stun" or "bleed" } }
lib.trackedAfflictions = {
  -- Hidden CC effects (no visible debuff, must use combat log)
  ["Pounce"] = { type = "cc", value = "stun" },

  -- Bleed effects (visible debuff, but combat log is more reliable)
  ["Pounce Bleed"] = { type = "school", value = "bleed" },
  ["Rake"] = { type = "school", value = "bleed" },
  ["Rip"] = { type = "school", value = "bleed" },
  ["Lacerate"] = { type = "school", value = "bleed" },
  ["Garrote"] = { type = "school", value = "bleed" },
  ["Rupture"] = { type = "school", value = "bleed" },
  ["Deep Wound"] = { type = "school", value = "bleed" },
  ["Deep Wounds"] = { type = "school", value = "bleed" },
  ["Rend"] = { type = "school", value = "bleed" },
}

-- Function to apply Carnage refresh (exposed for ComboPointTracker to call on proc detection)
function lib.ApplyCarnageRefresh(targetGUID, targetName, biteSpellID)
  if CleveRoids.debug then
    -- Compare Carnage GUID with current target GUID
    local _, currentTargetGUID = UnitExists("target")
    currentTargetGUID = CleveRoids.NormalizeGUID(currentTargetGUID)
    local guidMatch = (targetGUID == currentTargetGUID) and "MATCH" or "MISMATCH"
    DEFAULT_CHAT_FRAME:AddMessage(
      string.format("|cffff00ff[Carnage]|r ApplyCarnageRefresh called for %s (GUID:%s, current:%s, %s)",
        targetName or "Unknown", tostring(targetGUID), tostring(currentTargetGUID), guidMatch)
    )
  end

  -- Only refresh debuffs if they're currently active on the target
  if not lib.objects[targetGUID] then
    if CleveRoids.debug then
      DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cffff6600[Carnage]|r No tracking data for GUID %s", tostring(targetGUID))
      )
    end
    return
  end

  -- Try to refresh Rip
  if CleveRoids.lastRipCast and CleveRoids.lastRipCast.duration and CleveRoids.lastRipCast.spellID and
     CleveRoids.lastRipCast.targetGUID == targetGUID then
    -- Only refresh if the SAME rank that was cast is still active
    local ripSpellID = CleveRoids.lastRipCast.spellID
    local rec = lib.objects[targetGUID] and lib.objects[targetGUID][ripSpellID]
    if rec and rec.duration and rec.start then
      -- Check if Rip is still active (not expired)
      local remaining = rec.duration + rec.start - GetTime()
      if remaining > 0 then
        -- Found the exact same rank active, refresh it with the saved duration
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
        if lib.objects[targetGUID] and lib.objects[targetGUID][ripSpellID] then
          local oldCaster = lib.objects[targetGUID][ripSpellID].caster
          lib.objects[targetGUID][ripSpellID].duration = ripDuration
          lib.objects[targetGUID][ripSpellID].start = GetTime()
          lib.objects[targetGUID][ripSpellID].expiry = GetTime() + ripDuration
          -- Ensure caster is preserved (required for personal debuff tracking)
          if not lib.objects[targetGUID][ripSpellID].caster then
            lib.objects[targetGUID][ripSpellID].caster = "player"
          end

          if CleveRoids.debug then
            -- Verify the record was actually saved
            local verifyRec = lib.objects[targetGUID] and lib.objects[targetGUID][ripSpellID]
            if verifyRec then
              local verifyRemaining = verifyRec.duration + verifyRec.start - GetTime()
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff00ff[Carnage]|r Updated CleveRoids tracking for Rip (GUID:%s, caster:%s->%s)",
                  tostring(targetGUID), tostring(oldCaster), tostring(verifyRec.caster))
              )
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff00ff[Carnage VERIFY]|r Rip record: dur=%s, start=%s, remaining=%.1fs",
                  tostring(verifyRec.duration), tostring(verifyRec.start), verifyRemaining)
              )
            else
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff0000[Carnage ERROR]|r Rip record MISSING immediately after update!")
              )
            end
          end
        else
          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cffff6600[Carnage]|r WARNING: Rip record not found! GUID:%s, objects[GUID]:%s",
                tostring(targetGUID), tostring(lib.objects[targetGUID]))
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
      end
    end
  end

  -- Try to refresh Rake
  if CleveRoids.lastRakeCast and CleveRoids.lastRakeCast.duration and CleveRoids.lastRakeCast.spellID and
     CleveRoids.lastRakeCast.targetGUID == targetGUID then
    -- Only refresh if the SAME rank that was cast is still active
    local rakeSpellID = CleveRoids.lastRakeCast.spellID
    local rec = lib.objects[targetGUID] and lib.objects[targetGUID][rakeSpellID]
    if rec and rec.duration and rec.start then
      -- Check if Rake is still active (not expired)
      local remaining = rec.duration + rec.start - GetTime()
      if remaining > 0 then
        -- Found the exact same rank active, refresh it with the saved duration
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
        if lib.objects[targetGUID] and lib.objects[targetGUID][rakeSpellID] then
          local oldCaster = lib.objects[targetGUID][rakeSpellID].caster
          lib.objects[targetGUID][rakeSpellID].duration = rakeDuration
          lib.objects[targetGUID][rakeSpellID].start = GetTime()
          lib.objects[targetGUID][rakeSpellID].expiry = GetTime() + rakeDuration
          -- Ensure caster is preserved (required for personal debuff tracking)
          if not lib.objects[targetGUID][rakeSpellID].caster then
            lib.objects[targetGUID][rakeSpellID].caster = "player"
          end

          if CleveRoids.debug then
            -- Verify the record was actually saved
            local verifyRec = lib.objects[targetGUID] and lib.objects[targetGUID][rakeSpellID]
            if verifyRec then
              local verifyRemaining = verifyRec.duration + verifyRec.start - GetTime()
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff00ff[Carnage]|r Updated CleveRoids tracking for Rake (GUID:%s, caster:%s->%s)",
                  tostring(targetGUID), tostring(oldCaster), tostring(verifyRec.caster))
              )
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff00ff[Carnage VERIFY]|r Rake record: dur=%s, remaining=%.1fs",
                  tostring(verifyRec.duration), verifyRemaining)
              )
            else
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff0000[Carnage ERROR]|r Rake record MISSING immediately after update!")
              )
            end
          end
        else
          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cffff6600[Carnage]|r WARNING: Rake record not found! GUID:%s",
                tostring(targetGUID))
            )
          end
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
      end
    end
  end
end

-- Frame for delayed personal debuff tracking and judgement scanning
-- NOTE: Carnage refresh is now handled via PLAYER_COMBO_POINTS event in ComboPointTracker.lua

-- PERFORMANCE: Upvalues for frequently called functions
local _GetTime = GetTime
local _UnitExists = UnitExists
local _UnitDebuff = UnitDebuff
local _UnitIsDead = UnitIsDead
local _UnitName = UnitName
local _SpellInfo = SpellInfo
local _string_find = string.find
local _string_format = string.format
local _string_sub = string.sub
local _tostring = tostring
local _next = next
local _pairs = pairs
local _getn = table.getn  -- Lua 5.0 compatible table length
local _table_insert = table.insert  -- Lua 5.0 compatible

-- PERFORMANCE: Static buffers for removal tracking - reused every frame
-- Using mark-and-sweep pattern instead of table.remove() for O(1) removal
local _pendingJudgementsBuffer = {}
local _pendingPersonalBuffer = {}
local _pendingCCBuffer = {}
local _pendingSharedBuffer = {}

-- PERFORMANCE: Throttling - run at 20Hz max instead of every frame (60+Hz)
-- Minimum delay is 0.2s, so 20Hz (50ms) gives us 4 checks per minimum delay
local _lastDelayedTrackingUpdate = 0
local _DELAYED_TRACKING_INTERVAL = 0.05  -- 50ms = 20Hz

local delayedTrackingFrame = CreateFrame("Frame", "CleveRoidsDelayedTrackingFrame", UIParent)
delayedTrackingFrame:SetScript("OnUpdate", function()
  -- PERFORMANCE: Throttle updates - most pending items have 0.2-0.5s delays anyway
  local currentTime = _GetTime()
  if (currentTime - _lastDelayedTrackingUpdate) < _DELAYED_TRACKING_INTERVAL then
    return
  end
  _lastDelayedTrackingUpdate = currentTime

  -- PERFORMANCE: Early exit if all queues are empty
  -- NOTE: Use next() instead of [1] to handle array holes from table.remove()
  -- Array holes can occur when combat log handlers remove entries mid-iteration
  local hasJudgements = lib.pendingJudgements and _next(lib.pendingJudgements)
  local hasPersonal = lib.pendingPersonalDebuffs and _next(lib.pendingPersonalDebuffs)
  local hasCC = lib.pendingCCDebuffs and _next(lib.pendingCCDebuffs)
  local hasShared = lib.pendingSharedDebuffs and _next(lib.pendingSharedDebuffs)
  local hasOverrides = lib.rankRefreshOverrides and _next(lib.rankRefreshOverrides)

  -- DEBUG: Track pending queue state - check EVERY time to diagnose issue
  if CleveRoids.debug then
    local sharedCount = lib.pendingSharedDebuffs and _getn(lib.pendingSharedDebuffs) or 0
    local personalCount = lib.pendingPersonalDebuffs and _getn(lib.pendingPersonalDebuffs) or 0
    -- Log if any shared pending exists, regardless of hasShared check
    if sharedCount > 0 then
      -- Only log occasionally to avoid spam (every ~0.5s)
      if not lib._lastPendingQueueLog or (currentTime - lib._lastPendingQueueLog) > 0.5 then
        lib._lastPendingQueueLog = currentTime
        local firstItem = lib.pendingSharedDebuffs[1]
        DEFAULT_CHAT_FRAME:AddMessage(
          _string_format("|cffaaaaaa[Pending Queue]|r shared:%d (hasShared:%s, [1]:%s) personal:%d",
            sharedCount, hasShared and "TRUE" or "FALSE", firstItem and "exists" or "NIL", personalCount)
        )
      end
    end
    -- Log personal debuff queue state when items exist but hasPersonal might be false
    if personalCount > 0 then
      if not lib._lastPersonalQueueLog or (currentTime - lib._lastPersonalQueueLog) > 0.5 then
        lib._lastPersonalQueueLog = currentTime
        local firstItem = lib.pendingPersonalDebuffs[1]
        local firstItemInfo = "NIL"
        if firstItem then
          firstItemInfo = _string_format("spellID:%s,targetGUID:%s",
            _tostring(firstItem.spellID or "nil"), firstItem.targetGUID and "exists" or "nil")
        end
        DEFAULT_CHAT_FRAME:AddMessage(
          _string_format("|cffaaaaaa[Personal Queue]|r count:%d, hasPersonal:%s, [1]:%s",
            personalCount, hasPersonal and "TRUE" or "FALSE", firstItemInfo)
        )
      end
    end
  end

  if not (hasJudgements or hasPersonal or hasCC or hasShared or hasOverrides) then
    return
  end

  -- Cache frequently accessed values
  local hasSuperwow = CleveRoids.hasSuperwow
  local debug = CleveRoids.debug

  -- Process pending judgement scans to detect actual debuff IDs
  if hasJudgements then
    local writeIdx = 0
    local pendingList = lib.pendingJudgements

    for i = 1, _getn(pendingList) do
      local pending = pendingList[i]
      -- Guard against nil entries (can occur if combat log events remove items during iteration)
      if pending then
      local elapsed = currentTime - pending.timestamp

      -- Scan target after 0.5 seconds to find the actual judgement debuff
      if elapsed >= 0.5 then
        -- Check if this is still the current target
        local _, currentTargetGUID = _UnitExists("target")
        currentTargetGUID = CleveRoids.NormalizeGUID(currentTargetGUID)

        if currentTargetGUID == pending.targetGUID and hasSuperwow then
          -- Scan all debuffs on target to find judgement-type debuffs
          for slot = 1, 16 do
            local _, _, _, debuffSpellID = _UnitDebuff("target", slot)
            if not debuffSpellID then break end

            local debuffName = _SpellInfo(debuffSpellID)
            -- Check if this is a judgement debuff (name starts with "Judgement")
            if debuffName and _string_find(debuffName, "^Judgement") then
              -- Found a judgement debuff! Store it for refresh tracking
              if not lib.detectedJudgementDebuffIDs[debuffSpellID] then
                lib.detectedJudgementDebuffIDs[debuffSpellID] = true
                lib.judgementSpells[debuffSpellID] = true  -- Add to refresh list

                if debug then
                  DEFAULT_CHAT_FRAME:AddMessage(
                    _string_format("|cff00ffff[Judgement Detect]|r Found debuff %s (ID:%d) from cast (ID:%d) - added to refresh list",
                      debuffName, debuffSpellID, pending.castSpellID)
                  )
                end
              end
            end
          end
        end
        -- Item processed, don't copy to output
      else
        -- Item not ready, keep it
        writeIdx = writeIdx + 1
        if writeIdx ~= i then
          pendingList[writeIdx] = pending
        end
      end
      end -- if pending
    end

    -- PERFORMANCE: Clear remaining slots and update length
    for i = writeIdx + 1, _getn(pendingList) do
      pendingList[i] = nil
    end
  end

  -- Process pending personal debuffs
  if hasPersonal then
    -- Count entries properly using pairs (handles array holes)
    local pendingCount = 0
    for _ in _pairs(lib.pendingPersonalDebuffs) do
      pendingCount = pendingCount + 1
    end

    -- Debug: Show pending count every few seconds (avoid spam)
    if debug and pendingCount > 0 then
      if not lib._lastPendingDebugTime or (currentTime - lib._lastPendingDebugTime) > 2.0 then
        lib._lastPendingDebugTime = currentTime
        DEFAULT_CHAT_FRAME:AddMessage(
          _string_format("|cffaaaaaa[Pending Debug]|r %d personal debuffs waiting", pendingCount)
        )
      end
    end

    -- Use pairs() to iterate and rebuild without holes
    -- This handles array holes created by table.remove() in combat log handlers
    local newPendingList = {}

    for _, pending in _pairs(lib.pendingPersonalDebuffs) do
      -- Process each entry (pairs handles holes correctly)
      if pending then
      local elapsed = currentTime - pending.timestamp

      -- Add debuff after 0.2 second delay (enough time for server sync)
      if elapsed >= 0.2 then
        -- BLEED IMMUNITY VERIFICATION: Check if bleed debuff actually appeared
        -- This happens AFTER the delay, giving the server time to sync the debuff
        local isBleedSpell = CleveRoids.BleedSpellIDs and CleveRoids.BleedSpellIDs[pending.spellID]
        local bleedVerified = true

        -- DEBUG: Log verification attempt for bleed spells
        if debug and isBleedSpell then
          local spellNameDbg = _SpellInfo(pending.spellID) or "Unknown"
          DEFAULT_CHAT_FRAME:AddMessage(
            _string_format("|cff00aaff[Bleed Verify Start]|r %s (ID:%d) on %s - hasSuperwow:%s, targetGUID:%s",
              spellNameDbg, pending.spellID, pending.targetName or "Unknown",
              hasSuperwow and "yes" or "NO", pending.targetGUID and "exists" or "NIL")
          )
        end

        if isBleedSpell and hasSuperwow and pending.targetGUID then
          -- Check if mob is in bleed whitelist (skip verification for known bleeders)
          local isWhitelisted = CleveRoids.MobsThatBleed and CleveRoids.MobsThatBleed[pending.targetGUID]

          if not isWhitelisted then
            -- Check if target is dead - requires special handling
            -- Note: SuperWoW allows GUID-based queries for all unit functions
            if _UnitIsDead(pending.targetGUID) then
              -- Target died - check if we saw "afflicted by" message before death
              if pending.verifiedByAffliction then
                -- We confirmed bleed landed via combat log before target died
                if debug then
                  local spellNameDebug = _SpellInfo(pending.spellID) or "Bleed"
                  DEFAULT_CHAT_FRAME:AddMessage(
                    _string_format("|cff00ff00[Bleed Verified]|r %s on %s confirmed via 'afflicted by' (target now dead)",
                      spellNameDebug, pending.targetName or "Unknown")
                  )
                end
              else
                -- Target died WITHOUT "afflicted by" message
                -- BUT: Don't record immunity for one-shot kills!
                -- If target died within 0.5s of cast, the bleed didn't have time to apply
                -- even on a valid target. We can't determine immunity from instant kills.
                local timeSinceCast = currentTime - pending.timestamp
                local ONE_SHOT_THRESHOLD = 0.5  -- seconds

                if timeSinceCast < ONE_SHOT_THRESHOLD then
                  -- One-shot kill - can't determine immunity, skip recording
                  -- Set bleedVerified = false so we don't add to tracking or remove existing immunity
                  bleedVerified = false
                  if debug then
                    local spellNameDebug = _SpellInfo(pending.spellID) or "Bleed"
                    DEFAULT_CHAT_FRAME:AddMessage(
                      _string_format("|cffaaaaaa[Bleed Skip]|r %s on %s - target died too quickly (%.2fs), can't determine immunity",
                        spellNameDebug, pending.targetName or "Unknown", timeSinceCast)
                    )
                  end
                  -- Note: We set bleedVerified = false but DON'T record immunity
                  -- This is intentional - one-shots are inconclusive
                else
                  -- Target lived long enough but no "afflicted by" = immunity
                  bleedVerified = false
                  if pending.targetName and pending.targetName ~= "" then
                    local spellNameForImmunity = _SpellInfo(pending.spellID) or "Bleed"

                    if not CleveRoids_ImmunityData["bleed"] then
                      CleveRoids_ImmunityData["bleed"] = {}
                    end
                    CleveRoids_ImmunityData["bleed"][pending.targetName] = true

                    if debug then
                      DEFAULT_CHAT_FRAME:AddMessage(
                        _string_format("|cffff6600[Bleed Immunity]|r %s is immune to bleed (%s) - target died without 'afflicted by' message (%.2fs)",
                          pending.targetName, spellNameForImmunity, timeSinceCast)
                      )
                    end
                  end
                end
              end
            elseif not UnitExists(pending.targetGUID) then
              -- Target despawned or GUID is invalid - can't verify, skip without recording immunity
              -- This is similar to one-shot kills: inconclusive result, don't record immunity
              bleedVerified = false
              if debug then
                local spellNameDebug = _SpellInfo(pending.spellID) or "Bleed"
                DEFAULT_CHAT_FRAME:AddMessage(
                  _string_format("|cffaaaaaa[Bleed Skip]|r %s on %s - target no longer exists (despawned), can't determine immunity",
                    spellNameDebug, pending.targetName or "Unknown")
                )
              end
              -- Note: We set bleedVerified = false but DON'T record immunity
              -- This is intentional - despawned targets are inconclusive
            else
              -- Target is alive - check debuffs by GUID (SuperWoW supports GUID-based queries)
              bleedVerified = false
              local totalDebuffs = 0

              for slot = 1, 48 do
                local _, _, _, debuffSpellID = _UnitDebuff(pending.targetGUID, slot)
                if not debuffSpellID then
                  if slot <= 16 then break end  -- Regular debuffs are dense, overflow continues on nil
                else
                  totalDebuffs = totalDebuffs + 1
                  if debuffSpellID == pending.spellID then
                    bleedVerified = true
                    -- Don't break - continue counting total debuffs for immunity vs cap detection
                  end
                end
              end

              -- If bleed is missing and target has few debuffs, it's likely immunity (not debuff cap)
              if not bleedVerified then
                local DEBUFF_CAP_THRESHOLD = 47  -- Max is 48 (16 visible + 32 overflow)
                if totalDebuffs < DEBUFF_CAP_THRESHOLD then
                  -- Few debuffs = likely bleed immunity, not debuff cap
                  if pending.targetName and pending.targetName ~= "" then
                    -- Record as BLEED immunity directly (bypass split damage override in RecordImmunity)
                    -- RecordImmunity would record Rake/Pounce as "physical" (initial school),
                    -- but we specifically detected the BLEED debuff didn't land
                    local spellNameForImmunity = _SpellInfo(pending.spellID) or "Bleed"

                    if not CleveRoids_ImmunityData["bleed"] then
                      CleveRoids_ImmunityData["bleed"] = {}
                    end
                    CleveRoids_ImmunityData["bleed"][pending.targetName] = true

                    if debug then
                      DEFAULT_CHAT_FRAME:AddMessage(
                        _string_format("|cffff6600[Bleed Immunity]|r %s is immune to bleed (%s) - only %d debuffs on target",
                          pending.targetName, spellNameForImmunity, totalDebuffs)
                      )
                    end
                  end
                else
                  -- Many debuffs = likely pushed off at debuff cap
                  if debug then
                    local spellNameDebug = _SpellInfo(pending.spellID) or "Bleed"
                    DEFAULT_CHAT_FRAME:AddMessage(
                      _string_format("|cffff6600[Debuff Cap]|r %s not found on %s - likely pushed off (%d debuffs on target)",
                        spellNameDebug, pending.targetName or "Unknown", totalDebuffs)
                    )
                  end
                end
              end
            end
          end
        end

        -- Only apply the debuff to tracking if it was verified (or not a bleed/was whitelisted)
        if bleedVerified then
          -- Debug: Show what we're about to add to tracking
          if debug then
            local spellNameDebug = _SpellInfo(pending.spellID) or "Unknown"
            local guidStr = _string_sub(_tostring(pending.targetGUID or "nil"), 1, 20)
            DEFAULT_CHAT_FRAME:AddMessage(
              _string_format("|cff88ff88[Pending Process]|r Adding %s (ID:%d, %ds) GUID:%s",
                spellNameDebug, pending.spellID, pending.duration or 0, guidStr)
            )
          end

          lib:AddEffect(pending.targetGUID, pending.targetName, pending.spellID, pending.duration, 0, "player")

          -- Remove any existing bleed immunity record for this NPC ONLY if a bleed spell landed
          -- Previously this unconditionally removed bleed immunity for ANY personal debuff
          if isBleedSpell and pending.targetName and pending.targetName ~= "" then
            CleveRoids.RemoveSpellImmunity(pending.targetName, "bleed")
          end

          -- CARNAGE TALENT: Mark Rake as verified for Ferocious Bite refresh
          local isRakeSpell = CleveRoids.RakeSpellIDs and CleveRoids.RakeSpellIDs[pending.spellID]
          if isRakeSpell and CleveRoids.lastRakeCast and CleveRoids.lastRakeCast.pending then
            if CleveRoids.lastRakeCast.targetGUID == pending.targetGUID and
               CleveRoids.lastRakeCast.spellID == pending.spellID then
              CleveRoids.lastRakeCast.pending = nil  -- Mark as verified
              if debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  _string_format("|cff00ff00[Carnage]|r Rake verified on %s - ready for Ferocious Bite refresh",
                    pending.targetName or "Unknown")
                )
              end
            end
          end

          if debug then
            local spellName = _SpellInfo(pending.spellID) or "Unknown"
            DEFAULT_CHAT_FRAME:AddMessage(
              _string_format("|cff00ff00[Delayed Track]|r Applied %s (ID:%d) to tracking on %s",
                spellName, pending.spellID, pending.targetName or "Unknown")
            )
          end
        else
          -- Bleed didn't land - clear pending Rake data for Carnage if applicable
          local isRakeSpell = CleveRoids.RakeSpellIDs and CleveRoids.RakeSpellIDs[pending.spellID]
          if isRakeSpell and CleveRoids.lastRakeCast and CleveRoids.lastRakeCast.pending then
            if CleveRoids.lastRakeCast.targetGUID == pending.targetGUID and
               CleveRoids.lastRakeCast.spellID == pending.spellID then
              CleveRoids.lastRakeCast = nil  -- Clear invalid Rake data
              if debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  _string_format("|cffff6600[Carnage]|r Rake failed to apply on %s - clearing tracking data",
                    pending.targetName or "Unknown")
                )
              end
            end
          end
        end
        -- Item processed, don't add to new list
      else
        -- Item not ready, keep it in the new list
        _table_insert(newPendingList, pending)
      end
      end -- if pending
    end

    -- Replace old list with compacted new list (no holes)
    lib.pendingPersonalDebuffs = newPendingList
  end

  -- Process pending CC debuffs for immunity detection
  if hasCC then
    -- Use pairs() to iterate and rebuild without holes (same fix as personal debuffs)
    local newPendingList = {}

    for _, pending in _pairs(lib.pendingCCDebuffs) do
      -- Process each entry (pairs handles holes correctly)
      if pending then
      local elapsed = currentTime - pending.timestamp

      -- Check after delay: 0.4s for hidden CC (no visible debuff), 0.2s for normal CC
      -- Hidden CC (e.g., Pounce stun) needs longer delay to wait for "afflicted by" messages
      local verifyDelay = pending.isHiddenCC and 0.4 or 0.2

      -- Drop stale entries (>2s) without recording immunity - inconclusive due to severe lag
      if elapsed > 2.0 then
        if debug then
          DEFAULT_CHAT_FRAME:AddMessage(
            _string_format("|cffff6600[CC Stale]|r Dropping stale CC entry for %s on %s (%.1fs old)",
              pending.ccType or "CC", pending.targetName or "Unknown", elapsed)
          )
        end
        -- Don't add to newPendingList - silently discard
      elseif elapsed >= verifyDelay then
        local ccVerified = false
        local totalDebuffs = 0

        -- Check if already verified via "afflicted by" combat log message
        -- This happens for hidden CC spells like Pounce when the message arrives first
        if pending.verifiedByAffliction then
          ccVerified = true
        end

        -- SPELL_GO early-exit: Use definitive hit/miss data when available
        -- This is faster and more reliable than debuff scanning, and handles debuff cap correctly
        if not ccVerified and pending.spellGoHit then
          ccVerified = true
          if debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              _string_format("|cff00ff00[CC Verified via SPELL_GO]|r %s landed on %s - skipping debuff scan",
                pending.ccType or "CC", pending.targetName or "Unknown")
            )
          end
        end

        -- CC IMMUNITY VERIFICATION: Check if CC effect actually landed
        -- Uses hybrid approach: direct spell ID match OR mechanic-based validation
        -- (CC debuff IDs often differ from cast IDs, e.g., Pounce cast ≠ Pounce Stun debuff)
        -- Guard: skip debuff scanning if SPELL_GO already determined outcome
        if not ccVerified and not pending.spellGoHit and not pending.spellGoMissed
          and hasSuperwow and pending.targetGUID then
          -- Skip verification if target is dead (debuffs are removed on death)
          if _UnitIsDead(pending.targetGUID) then
            ccVerified = true  -- Assume CC landed, can't verify on dead target
            if debug then
              DEFAULT_CHAT_FRAME:AddMessage(
                _string_format("|cffff6600[CC Verify Skip]|r Target %s is dead - skipping immunity check for %s",
                  pending.targetName or "Unknown", pending.ccType or "CC")
              )
            end
          else
            -- Method 1: Direct spell ID matching (scan debuffs for exact spell ID)
            if pending.spellID then
              for slot = 1, 48 do
                local texture, _, _, debuffSpellID = _UnitDebuff(pending.targetGUID, slot)
                if not texture then
                  if slot <= 16 then break end  -- Regular debuffs are dense, overflow continues on nil
                else
                  totalDebuffs = totalDebuffs + 1
                  -- Debug: Show each debuff found during CC verification
                  if debug then
                    local debuffName = _SpellInfo(debuffSpellID) or "Unknown"
                    local mechanic = CleveRoids.GetSpellMechanic and CleveRoids.GetSpellMechanic(debuffSpellID) or 0
                    DEFAULT_CHAT_FRAME:AddMessage(
                      _string_format("|cffaaaaaa[CC Scan]|r Slot %d: %s (ID:%d, Mech:%d) - Looking for %s (ID:%d)",
                        slot, debuffName, debuffSpellID or 0, mechanic, pending.spellName or "CC", pending.spellID or 0)
                    )
                  end
                  if debuffSpellID == pending.spellID then
                    ccVerified = true
                    -- Don't break - continue counting total debuffs for immunity vs cap detection
                  end
                end
              end
            end

            -- Method 2: Mechanic-based validation (fallback if spell ID not found)
            -- CC debuff IDs often differ from cast IDs (e.g., Pounce stun uses different ID)
            -- Check if target has ANY debuff of the correct CC type (stun, fear, etc.)
            if not ccVerified and pending.ccType and CleveRoids.ValidateUnitCC then
              if debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  _string_format("|cffaaaa00[CC Verify]|r Direct ID match failed, trying mechanic check for %s...",
                    pending.ccType)
                )
              end
              ccVerified = CleveRoids.ValidateUnitCC(pending.targetGUID, pending.ccType)
              if debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  _string_format("|cff00aaff[CC Verify]|r Mechanic check result: %s",
                    ccVerified and "FOUND" or "NOT FOUND")
                )
              end
            end
          end
        end

        if not ccVerified and pending.spellGoMissed and debug then
          DEFAULT_CHAT_FRAME:AddMessage(
            _string_format("|cffff6600[CC Missed via SPELL_GO]|r %s missed on %s - checking immunity",
              pending.ccType or "CC", pending.targetName or "Unknown")
          )
        end

        -- If CC didn't land, check if it's immunity or debuff cap
        if not ccVerified and not _UnitIsDead(pending.targetGUID) then
          -- totalDebuffs already counted above, reuse it
          if totalDebuffs == 0 and hasSuperwow and pending.targetGUID then
            -- Count wasn't done (dead target check skipped counting), do it now
            for slot = 1, 48 do
              local texture, _, _, debuffSpellID = _UnitDebuff(pending.targetGUID, slot)
              if not texture then
                if slot <= 16 then break end
              else
                totalDebuffs = totalDebuffs + 1
              end
            end
          end

          -- Try to get target name if we don't have it (might have been a focus/mouseover cast)
          local resolvedTargetName = pending.targetName
          if (not resolvedTargetName or resolvedTargetName == "") and pending.targetGUID then
            -- Try to get from GUID cache
            resolvedTargetName = lib.guidToName[pending.targetGUID]
            -- Try to resolve from current target
            if not resolvedTargetName then
              local _, currentTargetGUID = _UnitExists("target")
              if currentTargetGUID and CleveRoids.NormalizeGUID(currentTargetGUID) == pending.targetGUID then
                resolvedTargetName = _UnitName("target")
                lib.guidToName[pending.targetGUID] = resolvedTargetName
              end
            end
            -- Try to resolve using SuperWoW GUID-based query
            if not resolvedTargetName and hasSuperwow then
              local name = _UnitName(pending.targetGUID)
              if name and name ~= "Unknown" then
                resolvedTargetName = name
                lib.guidToName[pending.targetGUID] = resolvedTargetName
              end
            end
          end

          local DEBUFF_CAP_THRESHOLD = 47  -- Max is 48 (16 visible + 32 overflow)

          -- SPLIT CC SPELLS: Skip immunity recording for spells with physical damage + resistable CC
          -- (e.g., Master Strike) - physical damage lands but CC can be resisted independently
          -- spellGoHit: SPELL_GO confirmed hit, so CC was resisted independently (not true immunity)
          local isSplitCCSpell = SPLIT_CC_SPELLS[pending.spellID] or pending.spellGoHit
          if isSplitCCSpell then
            if debug then
              local spellNameDebug = pending.spellName or (_SpellInfo(pending.spellID) or "Unknown")
              DEFAULT_CHAT_FRAME:AddMessage(
                _string_format("|cff00aaff[Split CC Skip]|r %s CC resisted on %s - skipping CC immunity recording",
                  spellNameDebug, resolvedTargetName or "Unknown")
              )
            end
            -- Skip immunity recording - damage landed, only CC was resisted
          elseif totalDebuffs < DEBUFF_CAP_THRESHOLD then
            -- Few debuffs = likely CC immunity
            if resolvedTargetName and resolvedTargetName ~= "" and pending.ccType then
              CleveRoids.RecordCCImmunity(resolvedTargetName, pending.ccType, nil, pending.spellName)

              if debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  _string_format("|cff00ff00[CC Immunity]|r %s is immune to %s (%s) - verified: debuff missing, only %d debuffs on target",
                    resolvedTargetName, pending.ccType, pending.spellName or "Unknown", totalDebuffs)
                )
              end
            elseif debug then
              DEFAULT_CHAT_FRAME:AddMessage(
                _string_format("|cffff6600[CC Immunity Skip]|r Could not resolve target name for GUID %s - cannot record %s immunity",
                  pending.targetGUID or "nil", pending.ccType or "Unknown")
              )
            end
          else
            -- Many debuffs = likely pushed off
            if debug then
              DEFAULT_CHAT_FRAME:AddMessage(
                _string_format("|cffff6600[CC Debuff Cap]|r %s not found on %s - likely pushed off (%d debuffs)",
                  pending.ccType, resolvedTargetName or "Unknown", totalDebuffs)
              )
            end
          end
        else
          -- CC landed successfully - remove any existing immunity record for this NPC/CC type
          local resolvedTargetName = pending.targetName
          if (not resolvedTargetName or resolvedTargetName == "") and pending.targetGUID then
            resolvedTargetName = lib.guidToName[pending.targetGUID]
          end
          if resolvedTargetName and pending.ccType then
            CleveRoids.RemoveCCImmunity(resolvedTargetName, pending.ccType)
          end
          if debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              _string_format("|cff00ff00[CC Verified]|r %s landed on %s",
                pending.ccType, resolvedTargetName or "Unknown")
            )
          end
        end
        -- Item processed, don't add to new list
      else
        -- Item not ready, keep it in the new list
        _table_insert(newPendingList, pending)
      end
      end -- if pending
    end

    -- Replace old list with compacted new list (no holes)
    lib.pendingCCDebuffs = newPendingList
  end

  -- Process pending shared debuffs for immunity detection
  if hasShared then
    -- Use pairs() to iterate and rebuild without holes (same fix as personal/CC debuffs)
    local newPendingList = {}

    -- Count for debug output
    local pendingCount = 0
    for _ in _pairs(lib.pendingSharedDebuffs) do
      pendingCount = pendingCount + 1
    end

    if debug then
      DEFAULT_CHAT_FRAME:AddMessage(
        _string_format("|cff00aaff[Shared Process]|r Processing %d pending shared debuffs", pendingCount)
      )
    end

    for _, pending in _pairs(lib.pendingSharedDebuffs) do
      -- Guard against nil entries (can occur if combat log events remove items during iteration)
      if pending then
      local elapsed = currentTime - pending.timestamp

      if debug then
        local spellName = pending.spellID and _SpellInfo(pending.spellID) or "Unknown"
        DEFAULT_CHAT_FRAME:AddMessage(
          _string_format("|cff00aaff[Shared Check]|r %s elapsed:%.2fs (need 0.2s)", spellName, elapsed)
        )
      end

      -- Drop stale entries (>2s) without recording immunity - inconclusive due to severe lag
      if elapsed > 2.0 then
        if debug then
          local spellNameDebug = pending.spellID and _SpellInfo(pending.spellID) or "Unknown"
          DEFAULT_CHAT_FRAME:AddMessage(
            _string_format("|cffff6600[Shared Stale]|r Dropping stale shared entry for %s on %s (%.1fs old)",
              spellNameDebug, pending.targetName or "Unknown", elapsed)
          )
        end
        -- Don't add to newPendingList - silently discard
      elseif elapsed >= 0.2 then
        local debuffVerified = false
        local totalDebuffs = 0

        -- SPELL_GO early-exit: Use definitive hit/miss data when available
        if pending.spellGoHit then
          debuffVerified = true
          if debug then
            local spellNameDebug = _SpellInfo(pending.spellID) or "Shared Debuff"
            DEFAULT_CHAT_FRAME:AddMessage(
              _string_format("|cff00ff00[Shared Verified via SPELL_GO]|r %s landed on %s - skipping debuff scan",
                spellNameDebug, pending.targetName or "Unknown")
            )
          end
        end

        -- Skip verification if target is dead (debuffs are removed on death)
        -- Guard: skip debuff scanning if SPELL_GO already determined outcome
        if not debuffVerified and not pending.spellGoHit and not pending.spellGoMissed
          and hasSuperwow and pending.targetGUID then
          if _UnitIsDead(pending.targetGUID) then
            -- Target died - can't verify immunity, assume debuff landed
            debuffVerified = true
            if debug then
              local spellNameDebug = _SpellInfo(pending.spellID) or "Shared Debuff"
              DEFAULT_CHAT_FRAME:AddMessage(
                _string_format("|cffff6600[Shared Verify Skip]|r Target %s is dead - skipping immunity check for %s",
                  pending.targetName or "Unknown", spellNameDebug)
              )
            end
          else
            -- Target is alive - check if debuff exists
            for slot = 1, 48 do
              local _, _, _, debuffSpellID = _UnitDebuff(pending.targetGUID, slot)
              if not debuffSpellID then
                if slot <= 16 then break end  -- Regular debuffs are dense, overflow continues on nil
              else
                totalDebuffs = totalDebuffs + 1
                if debuffSpellID == pending.spellID then
                  debuffVerified = true
                  -- Don't break - continue counting total debuffs for immunity vs cap detection
                end
              end
            end
          end
        else
          -- No SuperWoW or no GUID - assume debuff landed (can't verify)
          debuffVerified = true
        end

        -- Process result
        if debuffVerified then
          -- Debuff landed - add to tracking
          if debug then
            local spellNameDebug = _SpellInfo(pending.spellID) or "Unknown"
            DEFAULT_CHAT_FRAME:AddMessage(
              _string_format("|cff88ff88[Shared Verified]|r %s (ID:%d) verified on %s",
                spellNameDebug, pending.spellID, pending.targetName or "Unknown")
            )
          end

          lib:AddEffect(pending.targetGUID, pending.targetName, pending.spellID, pending.duration, pending.stacks or 0, "player")

          -- Remove any existing immunity record for this NPC for this spell's school
          if pending.school and pending.targetName and pending.targetName ~= "" then
            CleveRoids.RemoveSpellImmunity(pending.targetName, pending.school)
          end
        else
          -- Debuff didn't land - check if it's immunity or debuff cap
          local DEBUFF_CAP_THRESHOLD = 47  -- Max is 48 (16 visible + 32 overflow)

          -- SPLIT CC SPELLS: Skip immunity recording for spells with physical damage + resistable CC
          -- (e.g., Master Strike) - the physical damage lands but CC can be resisted independently
          -- spellGoHit: SPELL_GO confirmed hit, so debuff was resisted independently (not true immunity)
          local isSplitCCSpell = SPLIT_CC_SPELLS[pending.spellID] or SPLIT_CC_SPELLS[pending.castSpellID] or pending.spellGoHit
          if isSplitCCSpell then
            if debug then
              local spellNameDebug = _SpellInfo(pending.castSpellID or pending.spellID) or "Unknown"
              DEFAULT_CHAT_FRAME:AddMessage(
                _string_format("|cff00aaff[Split CC Skip]|r %s CC resisted on %s - skipping immunity recording (physical damage landed)",
                  spellNameDebug, pending.targetName or "Unknown")
              )
            end
            -- Skip immunity recording - damage landed, only CC was resisted
          elseif totalDebuffs < DEBUFF_CAP_THRESHOLD then
            -- Few debuffs = likely immunity
            if pending.targetName and pending.targetName ~= "" and pending.school then
              -- Record immunity for this spell's school
              if not CleveRoids_ImmunityData[pending.school] then
                CleveRoids_ImmunityData[pending.school] = {}
              end
              CleveRoids_ImmunityData[pending.school][pending.targetName] = true

              if debug then
                local spellNameDebug = _SpellInfo(pending.spellID) or "Unknown"
                DEFAULT_CHAT_FRAME:AddMessage(
                  _string_format("|cffff6600[Shared Immunity]|r %s is immune to %s (%s) - only %d debuffs on target",
                    pending.targetName, pending.school, spellNameDebug, totalDebuffs)
                )
              end
            end
          else
            -- Many debuffs = likely pushed off at debuff cap
            if debug then
              local spellNameDebug = _SpellInfo(pending.spellID) or "Unknown"
              DEFAULT_CHAT_FRAME:AddMessage(
                _string_format("|cffff6600[Shared Debuff Cap]|r %s not found on %s - likely pushed off (%d debuffs)",
                  spellNameDebug, pending.targetName or "Unknown", totalDebuffs)
              )
            end
          end
        end
        -- Item processed, don't add to new list
      else
        -- Item not ready, keep it in the new list
        _table_insert(newPendingList, pending)
      end
      end -- if pending
    end

    -- Replace old list with compacted new list (no holes)
    lib.pendingSharedDebuffs = newPendingList
  end

  -- Clean up old rank refresh overrides (older than 2 seconds)
  if hasOverrides then
    for spellName, override in pairs(lib.rankRefreshOverrides) do
      if currentTime - override.timestamp > 2.0 then
        lib.rankRefreshOverrides[spellName] = nil
      end
    end
  end

  -- Periodically clean up stale tracking data (immune/reflect/evade correlation tables)
  lib:CleanupStaleTrackingData()
end)

local ev = CreateFrame("Frame", "CleveRoidsLibDebuffFrame", UIParent)
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("ADDON_LOADED")  -- For pfUI integration initialization

if CleveRoids.hasSuperwow then
  ev:RegisterEvent("UNIT_CASTEVENT")
end

-- Register Nampower v2.26+ events for standalone mode (when pfUI is not available or outdated)
-- These provide accurate hit/miss detection and debuff application tracking
if CleveRoids.hasNampower then
  local npMajor, npMinor = GetNampowerVersion()
  if npMajor > 2 or (npMajor == 2 and npMinor >= 26) then
    ev:RegisterEvent("SPELL_GO_SELF")
    ev:RegisterEvent("SPELL_GO_OTHER")
    ev:RegisterEvent("AURA_CAST_ON_SELF")
    ev:RegisterEvent("AURA_CAST_ON_OTHER")
    ev:RegisterEvent("DEBUFF_ADDED_OTHER")
    ev:RegisterEvent("DEBUFF_REMOVED_OTHER")
    ev:RegisterEvent("UNIT_DIED")  -- Instant cleanup on target death

    if CleveRoids.debug then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Nampower]|r Registered UNIT_DIED for instant cleanup (v2.26+)")
    end
  end

  -- Register SPELL_START/SPELL_FAILED events for cast tracking (v2.25+)
  -- These events let us know when ANY unit starts or fails a cast-time spell
  -- pfUI 7.6 handles these itself, but we register anyway for standalone mode
  if npMajor > 2 or (npMajor == 2 and npMinor >= 25) then
    ev:RegisterEvent("SPELL_START_SELF")
    ev:RegisterEvent("SPELL_START_OTHER")
    ev:RegisterEvent("SPELL_FAILED_OTHER")

    if CleveRoids.debug then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Nampower]|r Registered SPELL_START/SPELL_FAILED for cast tracking (v2.25+)")
    end
  end
end

-- Track if UNIT_DIED is available for cleanup optimization
lib.hasUnitDiedEvent = CleveRoids.hasNampower and GetNampowerVersion and (function()
  local npMajor, npMinor = GetNampowerVersion()
  return npMajor > 2 or (npMajor == 2 and npMinor >= 26)
end)() or false

ev:SetScript("OnEvent", function()
  -- Initialize pfUI integration when pfUI loads
  if event == "ADDON_LOADED" and arg1 == "pfUI" then
    -- Defer initialization slightly to ensure pfUI.version is populated
    local initFrame = CreateFrame("Frame")
    local initTimer = 0
    initFrame:SetScript("OnUpdate", function()
      initTimer = initTimer + arg1
      if initTimer >= 0.5 then
        lib:InitPfUIIntegration()
        this:SetScript("OnUpdate", nil)
      end
    end)
    return
  end

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

        -- WARLOCK DARK HARVEST: Track channeling for DoT acceleration (TWoW Custom)
        -- Credits: Avitasia / Cursive addon
        -- Dark Harvest accelerates DoT tick rate by 30% while channeling
        if eventType == "CHANNEL" and CleveRoids.DarkHarvestSpellIDs and CleveRoids.DarkHarvestSpellIDs[spellID] then
          -- Get channel duration from tooltip or use base duration (8 seconds)
          local channelDuration = 8  -- Base Dark Harvest duration

          CleveRoids.darkHarvestData = {
            targetGUID = targetGUID,
            spellID = spellID,
            startTime = GetTime(),
            channelDuration = channelDuration,
            isActive = true
          }

          -- Apply Dark Harvest acceleration to all existing DoTs on target
          lib.ApplyDarkHarvestStart(targetGUID)

          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cff9482c9[Dark Harvest]|r Started channeling on %s (DoTs will tick 30%% faster)",
                lib.guidToName[targetGUID] or "Unknown")
            )
          end
        end
      end
    end

    if eventType == "CAST" and spellID then
      local _, playerGUID = UnitExists("player")
      if casterGUID == playerGUID and targetGUID then

        -- DRUID CARNAGE TALENT: Track Ferocious Bite cast for proc detection
        -- Carnage proc is detected in ComboPointTracker via PLAYER_COMBO_POINTS event
        -- When Carnage procs, combo points don't decrease (or increase by 1)
        if CleveRoids.FerociousBiteSpellIDs and CleveRoids.FerociousBiteSpellIDs[spellID] then
          -- Check if player has Carnage talent (any rank)
          -- Carnage: Tab 2 (Feral Combat), Talent 17
          local _, _, _, _, rank = GetTalentInfo(2, 17)
          local carnageRank = tonumber(rank) or 0

          if carnageRank >= 1 then
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

            -- Track Ferocious Bite cast for Carnage proc detection (via PLAYER_COMBO_POINTS)
            -- Unlike the old system, we don't schedule a refresh here - we wait for the proc
            CleveRoids.lastFerociousBiteTime = GetTime()
            CleveRoids.lastFerociousBiteTargetGUID = targetGUID
            CleveRoids.lastFerociousBiteTargetName = targetName
            CleveRoids.lastFerociousBiteSpellID = spellID

            if CleveRoids.debug then
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff00ff[Carnage]|r Tracking Ferocious Bite on %s (waiting for proc detection)",
                  targetName or "Unknown")
              )
            end
          end
        end

        -- SHAMAN MOLTEN BLAST: Track for Flame Shock refresh detection (TWoW Custom)
        -- Credits: Avitasia / Cursive addon
        if CleveRoids.MoltenBlastSpellIDs and CleveRoids.MoltenBlastSpellIDs[spellID] then
          CleveRoids.lastMoltenBlastTime = GetTime()
          CleveRoids.lastMoltenBlastTargetGUID = targetGUID
          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cff0070dd[Molten Blast]|r Tracking cast on %s (waiting for hit confirmation)",
                lib.guidToName[targetGUID] or "Unknown")
            )
          end
        end

        -- WARLOCK CONFLAGRATE: Reduces Immolate duration by 3 seconds
        -- Credits: Avitasia / Cursive addon
        if CleveRoids.ConflagrateSpellIDs and CleveRoids.ConflagrateSpellIDs[spellID] then
          -- Find active Immolate on target and reduce its duration
          if lib.objects[targetGUID] then
            for immolateID, _ in pairs(CleveRoids.ImmolateSpellIDs or {}) do
              local rec = lib.objects[targetGUID][immolateID]
              if rec and rec.duration and rec.start then
                local remaining = rec.duration + rec.start - GetTime()
                if remaining > 0 then
                  -- Reduce duration by 3 seconds
                  rec.duration = rec.duration - 3
                  if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                      string.format("|cff9482c9[Conflagrate]|r Reduced Immolate duration by 3s (now %.1fs remaining)",
                        rec.duration + rec.start - GetTime())
                    )
                  end
                  break
                end
              end
            end
          end
        end

        -- POUNCE: Convert cast spell ID to triggered Pounce Bleed spell ID
        -- Pounce (cast) triggers a separate Pounce Bleed spell with a different ID
        -- We track the bleed, not the stun, for immunity detection
        local trackingSpellID = spellID
        if CleveRoids.PounceToBleedMapping and CleveRoids.PounceToBleedMapping[spellID] then
          trackingSpellID = CleveRoids.PounceToBleedMapping[spellID]
          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cff00aaff[Pounce→Bleed]|r Converted cast ID %d to bleed ID %d", spellID, trackingSpellID)
            )
          end
        end

        -- CC IMMUNITY TRACKING: Check if this spell is a CC spell and track for immunity verification
        -- Uses the original spellID (not trackingSpellID) to detect CC type
        local ccType = CleveRoids.GetSpellCCType and CleveRoids.GetSpellCCType(spellID)

        -- Debug: Show what GetSpellCCType returns for this spell
        if CleveRoids.debug then
          local spellNameDebug = SpellInfo(spellID) or "Unknown"
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffaaaaaa[CC Check]|r %s (ID:%d) → ccType: %s",
              spellNameDebug, spellID, ccType or "nil")
          )
        end

        if ccType then
          -- Track ALL CC spells for immunity verification, including hidden CC (e.g., Pounce stun)
          -- Hidden CC spells don't show visible debuffs, but:
          -- 1. They may still be detectable via mechanic-based ValidateUnitCC check
          -- 2. Combat log "afflicted by" messages confirm successful CC
          -- 3. If neither detection method finds the CC, we record immunity
          local isHiddenCC = lib.hiddenCCSpells and lib.hiddenCCSpells[spellID]
          local spellName = SpellInfo(spellID)
          -- Get target name from cache or current target
          local ccTargetName = lib.guidToName[targetGUID]
          if not ccTargetName then
            local _, currentTargetGUID = UnitExists("target")
            currentTargetGUID = CleveRoids.NormalizeGUID(currentTargetGUID)
            if currentTargetGUID == targetGUID then
              ccTargetName = UnitName("target")
              lib.guidToName[targetGUID] = ccTargetName
            end
          end
          table.insert(lib.pendingCCDebuffs, {
            timestamp = GetTime(),
            targetGUID = targetGUID,
            targetName = ccTargetName,
            spellID = spellID,
            spellName = spellName,
            ccType = ccType,
            isHiddenCC = isHiddenCC,  -- Flag for hidden CC spells
          })

          if CleveRoids.debug then
            local hiddenStr = isHiddenCC and " (hidden CC)" or ""
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cff00ff00[CC Track]|r Tracking %s (%s) on %s for immunity verification%s",
                spellName or "Unknown", ccType, ccTargetName or "Unknown", hiddenStr)
            )
          end
        end

        -- Check if this is a combo point scaling spell first
        local duration = nil
        local comboPoints = nil
        if CleveRoids.TrackComboPointCastByID then
          duration = CleveRoids.TrackComboPointCastByID(trackingSpellID, targetGUID)
          -- Get combo points used from tracking
          if CleveRoids.ComboPointTracking and CleveRoids.ComboPointTracking.byID and
             CleveRoids.ComboPointTracking.byID[trackingSpellID] then
            comboPoints = CleveRoids.ComboPointTracking.byID[trackingSpellID].combo_points
          end
        end

        -- If not a combo scaling spell, use normal duration lookup
        if not duration then
          duration = lib:GetDuration(trackingSpellID, casterGUID)

          -- Apply all duration modifiers (Nampower, talents, equipment, set bonuses)
          -- (combo spells already have modifiers applied in CalculateComboScaledDurationByID)
          if duration and CleveRoids.ApplyAllDurationModifiers then
            duration = CleveRoids.ApplyAllDurationModifiers(trackingSpellID, duration)
          end
        end

        -- DEBUG: Show what duration we calculated
        if CleveRoids.debug and duration then
          local spellName = SpellInfo(trackingSpellID) or "Unknown"
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff00ff[DEBUG CAST]|r %s (ID:%d) CP:%s duration:%ds",
              spellName, trackingSpellID, tostring(comboPoints or "nil"), duration)
          )
        end

        if duration and duration > 0 then
          local targetName = lib.guidToName[targetGUID]
          if not targetName then
            local _, currentTargetGUID = UnitExists("target")
            -- IMPORTANT: Normalize GUID before comparison to avoid type mismatch
            currentTargetGUID = CleveRoids.NormalizeGUID(currentTargetGUID)
            if currentTargetGUID == targetGUID then
              targetName = UnitName("target")
              lib.guidToName[targetGUID] = targetName
            end
            -- Try SuperWoW GUID-based name lookup if still not resolved
            if not targetName and CleveRoids.hasSuperwow then
              targetName = UnitName(targetGUID)
              if targetName and targetName ~= "Unknown" then
                lib.guidToName[targetGUID] = targetName
              end
            end
            -- Final fallback
            if not targetName then
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
          local isPersonal = lib:IsPersonalDebuff(trackingSpellID)

          if isPersonal then
            -- Check if we should apply based on rank comparison
            local rankCheck = lib:ShouldApplyDebuffRank(targetGUID, trackingSpellID)

            if rankCheck == true then
              -- Normal application - schedule personal debuff for delayed tracking
              table.insert(lib.pendingPersonalDebuffs, {
                timestamp = GetTime(),
                targetGUID = targetGUID,
                targetName = targetName,
                spellID = trackingSpellID,  -- Use tracking spell ID (e.g., Pounce Bleed, not Pounce)
                castSpellID = spellID,      -- Original cast spell ID (for dodge/parry matching)
                duration = duration,
                comboPoints = comboPoints
              })

              -- If this is a Judgement spell cast by a Paladin, schedule a scan to find the actual debuff ID
              if CleveRoids.playerClass == "PALADIN" and lib.judgementSpells[spellID] then
                table.insert(lib.pendingJudgements, {
                  timestamp = GetTime(),
                  castSpellID = spellID,
                  targetGUID = targetGUID,
                  targetName = targetName
                })
              end

              if CleveRoids.debug then
                local spellName = SpellInfo(trackingSpellID) or "Unknown"
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cffaaff00[Pending Track]|r Scheduled %s (ID:%d) for tracking on %s (will apply if hit)",
                    spellName, trackingSpellID, targetName or "Unknown")
                )
              end
            elseif type(rankCheck) == "table" and rankCheck.preserve then
              -- Preserve higher rank's timer - schedule with higher rank's spell ID and remaining time
              table.insert(lib.pendingPersonalDebuffs, {
                timestamp = GetTime(),
                targetGUID = targetGUID,
                targetName = targetName,
                spellID = rankCheck.preserve,  -- Use higher rank's spell ID
                duration = rankCheck.timeRemaining,  -- Use remaining time, not full duration
                comboPoints = comboPoints,
                isRankPreserve = true  -- Flag this as a rank preserve
              })

              if CleveRoids.debug then
                local spellName = SpellInfo(rankCheck.preserve) or "Unknown"
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cffaaff00[Pending Track]|r Scheduled rank preserve for %s (ID:%d, %.1fs remaining) on %s",
                    spellName, rankCheck.preserve, rankCheck.timeRemaining, targetName or "Unknown")
                )
              end
            end
            -- If rankCheck == false, skip entirely (shouldn't happen for personal debuffs with new logic)
          else
            -- Shared debuff - schedule for delayed verification (immunity detection)
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
            else
              -- Target changed or not available, default to 1 stack
              newStacks = 1
            end

            -- Determine spell school for immunity tracking
            -- GetSpellSchool is defined later in file, use CleveRoids wrapper if available
            local spellSchool = nil
            local spellNameForSchool = SpellInfo(spellID)
            if CleveRoids.GetSpellSchool then
              spellSchool = CleveRoids.GetSpellSchool(spellNameForSchool, spellID)
            end

            -- Check if we should apply based on rank comparison
            local rankCheck = lib:ShouldApplyDebuffRank(targetGUID, spellID)

            local trackingSpellID = spellID
            local trackingDuration = duration
            if type(rankCheck) == "table" and rankCheck.preserve then
              -- Preserve higher rank's timer
              trackingSpellID = rankCheck.preserve
              trackingDuration = rankCheck.timeRemaining
            elseif rankCheck == false then
              -- Skip entirely
              trackingSpellID = nil
            end

            if trackingSpellID then
              -- REFRESH DETECTION: If newStacks > 1, debuff already existed on target
              -- Skip pending queue for refreshes - directly reset the timer
              -- The pending queue is only for NEW applications where immunity detection matters
              local isRefresh = (newStacks > 1)

              if isRefresh then
                -- Direct timer reset for refreshes (debuff already verified to exist)
                lib:AddEffect(targetGUID, targetName, trackingSpellID, trackingDuration, newStacks, "player")

                if CleveRoids.debug then
                  local spellName = SpellInfo(trackingSpellID) or "Unknown"
                  DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cff00ff00[Shared Refresh]|r %s (ID:%d) on %s - timer reset to %ds (stacks:%d)",
                      spellName, trackingSpellID, targetName or "Unknown", trackingDuration, newStacks)
                  )
                end
              else
                -- NEW APPLICATION: Schedule for delayed verification (immunity detection)
                table.insert(lib.pendingSharedDebuffs, {
                  timestamp = GetTime(),
                  targetGUID = targetGUID,
                  targetName = targetName,
                  spellID = trackingSpellID,
                  castSpellID = spellID,  -- Original cast spell ID (for dodge/parry matching)
                  duration = trackingDuration,
                  stacks = newStacks,
                  school = spellSchool,
                  isRankPreserve = (trackingSpellID ~= spellID)
                })

                if CleveRoids.debug then
                  local spellName = SpellInfo(trackingSpellID) or "Unknown"
                  local queueLen = table.getn(lib.pendingSharedDebuffs)
                  local firstItem = lib.pendingSharedDebuffs[1]
                  DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffaaff00[Pending Shared]|r Scheduled %s (ID:%d, school:%s) for tracking on %s [queueLen:%d, [1]:%s]",
                      spellName, trackingSpellID, spellSchool or "unknown", targetName or "Unknown",
                      queueLen, firstItem and "exists" or "NIL")
                  )
                end
              end
            end
          end

          -- Track this cast for miss/dodge/parry removal
          lib.lastPlayerCast = {
            spellID = spellID,
            targetGUID = targetGUID,
            timestamp = GetTime()
          }

          -- DRUID CARNAGE TALENT: Save Rip cast duration for later refresh by Ferocious Bite
          if CleveRoids.RipSpellIDs and CleveRoids.RipSpellIDs[spellID] then
            -- Clear any stale Carnage duration override for this spell
            -- New cast should use its own duration, not old Carnage refresh duration
            if CleveRoids.carnageDurationOverrides and CleveRoids.carnageDurationOverrides[spellID] then
              CleveRoids.carnageDurationOverrides[spellID] = nil
              if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cff888888[Carnage]|r Cleared stale Rip override (new cast replaces)")
                )
              end
            end

            if CleveRoids.lastRipCast then
              CleveRoids.lastRipCast.spellID = spellID
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

          -- NOTE: Bleed immunity detection is now handled in the delayed pending debuff
          -- processing system (see pendingPersonalDebuffs OnUpdate handler above).
          -- This prevents false positives from checking UnitDebuff() immediately after
          -- UNIT_CASTEVENT, before the server has synced the debuff to the client.

          -- CARNAGE TALENT: Save Rake cast data for potential Ferocious Bite refresh
          -- Verification that the bleed landed happens in the delayed tracking system
          local isRakeSpell = CleveRoids.RakeSpellIDs and CleveRoids.RakeSpellIDs[spellID]
          if isRakeSpell then
            -- Clear any stale Carnage duration override for this spell
            -- New cast should use its own duration, not old Carnage refresh duration
            if CleveRoids.carnageDurationOverrides and CleveRoids.carnageDurationOverrides[spellID] then
              CleveRoids.carnageDurationOverrides[spellID] = nil
              if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cff888888[Carnage]|r Cleared stale Rake override (new cast replaces)")
                )
              end
            end

            if CleveRoids.lastRakeCast then
              CleveRoids.lastRakeCast.spellID = spellID
              CleveRoids.lastRakeCast.duration = duration
              CleveRoids.lastRakeCast.targetGUID = targetGUID
              CleveRoids.lastRakeCast.comboPoints = comboPoints or 0
              CleveRoids.lastRakeCast.timestamp = GetTime()
              CleveRoids.lastRakeCast.pending = true  -- Mark as pending verification
              if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cff00ff00[Carnage]|r Saved Rake cast (pending verification): %ds duration (%d CP) on target %s",
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

      -- SHARED DEBUFFS FROM OTHER PLAYERS: Track when other players cast shared debuffs
      -- This ensures Sunder Armor, Faerie Fire, etc. are tracked when ANY player casts them
      -- Personal debuffs are still only tracked from the player (we only care about our own)
      local _, playerGUID = UnitExists("player")
      if casterGUID ~= playerGUID and targetGUID then
        -- Check if this is a shared debuff we should track
        if lib.sharedDebuffs[spellID] then
          local duration = lib:GetDuration(spellID)
          if duration and duration > 0 then
            -- Get target name from cache or current target
            local targetName = lib.guidToName[targetGUID]
            if not targetName then
              local _, currentTargetGUID = UnitExists("target")
              currentTargetGUID = CleveRoids.NormalizeGUID(currentTargetGUID)
              if currentTargetGUID == targetGUID then
                targetName = UnitName("target")
                lib.guidToName[targetGUID] = targetName
              end
            end

            -- For stacking debuffs, predict new stack count
            local newStacks = 1
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
              if newStacks == 1 then
                for i = 1, 32 do
                  local _, existingStacks, existingSpellID = UnitBuff("target", i)
                  if existingSpellID == spellID then
                    newStacks = (existingStacks or 0) + 1
                    break
                  end
                end
              end

              -- Cap at maximum stacks
              if newStacks > 5 then
                newStacks = 5
              end
            end

            -- Directly add the effect (other players' casts don't need immunity verification)
            -- Reset timer to full duration since the debuff was just refreshed
            lib:AddEffect(targetGUID, targetName, spellID, duration, newStacks, casterGUID)

            if CleveRoids.debug then
              local spellName = SpellInfo(spellID) or "Unknown"
              local casterName = lib.guidToName[casterGUID] or "Other Player"
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cff00aaff[Other Cast]|r %s cast %s (ID:%d) on %s - timer reset to %ds",
                  casterName, spellName, spellID, targetName or "Unknown", duration)
              )
            end
          end
        end
      end
    end

  -- NAMPOWER v2.25+ CAST TRACKING HANDLERS (Standalone or pfUI < 7.6)
  -- Populates CleveRoids.castTracking for [casting] conditional support.
  -- When pfUI 7.6+ is active, castTracking points to pfUI.libdebuff_casts
  -- and these handlers return early (pfUI handles it).

  elseif event == "SPELL_START_SELF" or event == "SPELL_START_OTHER" then
    -- pfUI 7.6 manages castTracking via its own SPELL_START handler
    if lib.hasPfUI76 then return end

    local spellId = arg2
    local casterGuid = arg3
    local castTime = arg6  -- milliseconds

    if not casterGuid or not spellId then return end

    local spellName = SpellInfo and SpellInfo(spellId)
    local icon = lib:GetCachedIcon(spellId)
    local now = GetTime()
    local durationSec = castTime and (castTime / 1000) or 0

    CleveRoids.castTracking[casterGuid] = {
      spellID = spellId,
      spellName = spellName,
      icon = icon,
      startTime = now,
      duration = durationSec,
      endTime = durationSec > 0 and (now + durationSec) or nil,
    }

    if CleveRoids.debug then
      DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cff00ccff[SPELL_START]|r %s (ID:%d) cast by %s - %.1fs",
          spellName or "Unknown", spellId, casterGuid, durationSec)
      )
    end

  elseif event == "SPELL_FAILED_OTHER" then
    -- pfUI 7.6 manages castTracking cleanup itself
    if lib.hasPfUI76 then return end

    local casterGuid = arg1
    if casterGuid and CleveRoids.castTracking[casterGuid] then
      if CleveRoids.debug then
        local entry = CleveRoids.castTracking[casterGuid]
        DEFAULT_CHAT_FRAME:AddMessage(
          string.format("|cffff6600[SPELL_FAILED]|r %s cast by %s interrupted/failed",
            entry.spellName or "Unknown", casterGuid)
        )
      end
      CleveRoids.castTracking[casterGuid] = nil
    end

  -- NAMPOWER v2.26+ SPELL EVENT HANDLERS (Standalone Mode)
  -- These handlers are only used when pfUI v7.4.3+ is NOT available.
  -- When pfUI is available, we use its tables directly instead.

  elseif event == "SPELL_GO_SELF" or event == "SPELL_GO_OTHER" then
    -- Skip if pfUI enhanced tracking is active (it handles this)
    if lib.hasPfUIEnhanced then return end

    -- Clear cast tracking entry - cast completed/fired (standalone mode only)
    if not lib.hasPfUI76 and arg3 and CleveRoids.castTracking[arg3] then
      CleveRoids.castTracking[arg3] = nil
    end

    local spellId = arg2
    local casterGuid = arg3
    local targetGuid = arg4
    local numHit = arg6 or 0
    local numMissed = arg7 or 0

    if not spellId or not targetGuid then return end
    targetGuid = CleveRoids.NormalizeGUID(targetGuid)

    local spellName = SpellInfo and SpellInfo(spellId)
    if not spellName then return end

    local _, playerGUID = UnitExists("player")
    local isOurs = (casterGuid == playerGUID)

    -- Annotate pending CC/shared debuffs with SPELL_GO hit/miss outcome
    -- This data is consumed by the OnUpdate verification loop for early-exit paths
    if isOurs then
      -- Annotate pendingCCDebuffs
      for _, pending in ipairs(lib.pendingCCDebuffs) do
        if pending and pending.spellID == spellId and pending.targetGUID == targetGuid then
          if numHit > 0 then
            pending.spellGoHit = true
          elseif numMissed > 0 then
            pending.spellGoMissed = true
          end
          break
        end
      end
      -- Annotate pendingSharedDebuffs (match against both castSpellID and spellID)
      for _, pending in ipairs(lib.pendingSharedDebuffs) do
        if pending and pending.targetGUID == targetGuid
          and (pending.castSpellID == spellId or pending.spellID == spellId) then
          if numHit > 0 then
            pending.spellGoHit = true
          elseif numMissed > 0 then
            pending.spellGoMissed = true
          end
          break
        end
      end
    end

    -- Spell missed - clear pending, mark as failed, track for immunity detection
    if numHit == 0 and numMissed > 0 then
      if lib.pendingCasts[targetGuid] then
        lib.pendingCasts[targetGuid][spellName] = nil
      end

      -- Get target name for immunity tracking
      local targetName = lib.guidToName[targetGuid]
      if not targetName then
        local _, currentTargetGUID = UnitExists("target")
        if CleveRoids.NormalizeGUID(currentTargetGUID) == targetGuid then
          targetName = UnitName("target")
          lib.guidToName[targetGuid] = targetName
        end
      end

      -- Mark spell as recently failed for DidSpellFail() check
      -- Store details for immunity/reflect/evade detection via combat log correlation
      lib.recentMisses[targetGuid] = lib.recentMisses[targetGuid] or {}
      lib.recentMisses[targetGuid][spellName] = {
        time = GetTime(),
        spellId = spellId,
        targetGuid = targetGuid,
        targetName = targetName,
        casterGuid = casterGuid,
        isOurs = isOurs,
        reason = nil,  -- Will be set by combat log parser (immune/reflect/evade/resist/dodge/parry)
      }

      if CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
          string.format("|cffff6600[SPELL_GO MISS]|r %s missed on %s - pending immunity check",
            spellName, targetName or "Unknown")
        )
      end

      -- Schedule immunity verification after a short delay
      -- This gives combat log time to report the miss reason (immune/reflect/evade)
      -- Optimization: Use shorter delay with Nampower v2.26+ since AURA_CAST events are faster
      if isOurs and targetName then
        -- Delay: 150ms with Nampower v2.26+ (AURA_CAST confirms faster), 300ms fallback
        local verifyDelay = lib.hasUnitDiedEvent and 0.15 or 0.3

        local verifyFrame = CreateFrame("Frame")
        local verifyData = {
          spellName = spellName,
          spellId = spellId,
          targetGuid = targetGuid,
          targetName = targetName,
          checkTime = GetTime() + verifyDelay,
        }
        verifyFrame:SetScript("OnUpdate", function()
          if GetTime() >= verifyData.checkTime then
            this:SetScript("OnUpdate", nil)
            lib:ProcessMissReason(verifyData)
          end
        end)
      end

      return
    end

    -- Spell hit - do refresh logic for OWN debuffs
    if isOurs and lib.ownDebuffs[targetGuid] and lib.ownDebuffs[targetGuid][spellName] then
      local existingData = lib.ownDebuffs[targetGuid][spellName]
      if existingData.startTime and existingData.duration then
        local timeleft = (existingData.startTime + existingData.duration) - GetTime()
        if timeleft > 0 then
          -- Refresh the timer
          lib.ownDebuffs[targetGuid][spellName].startTime = GetTime()

          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cff00ff00[SPELL_GO REFRESH]|r %s refreshed on %s",
                spellName, lib.guidToName[targetGuid] or "Unknown")
            )
          end
        end
      end
    end

    -- Spell hit on target - clear any pending immunity checks
    -- (The spell landed, so target is definitely not immune to it)
    if isOurs and lib.recentMisses and lib.recentMisses[targetGuid] then
      lib.recentMisses[targetGuid][spellName] = nil
    end

    -- COMBO POINT INTEGRATION: Capture combo points on SPELL_GO hit
    -- SPELL_GO fires immediately when the spell lands - this is the best time
    -- to capture combo points because they might already be consumed by the
    -- time AURA_CAST fires. Store in pendingCasts for AURA_CAST to use.
    if isOurs and lib.combopointAbilities and lib.combopointAbilities[spellName] then
      -- Capture combo points from multiple sources
      -- Priority: SPELL_CAST_EVENT (client-side, pre-server) > GetComboPoints > lastComboPoints > ComboPointTracking
      local comboPoints = 0

      -- PRIMARY: Check SPELL_CAST_EVENT capture (most reliable - captured before server consumed CP)
      local pending = CleveRoids.pendingCasts and CleveRoids.pendingCasts[spellId]
      if pending and pending.comboPoints and pending.comboPoints > 0 then
        comboPoints = pending.comboPoints
      end

      -- Fallback: Try GetComboPoints (may still be available)
      if comboPoints == 0 then
        comboPoints = CleveRoids.GetComboPoints and CleveRoids.GetComboPoints() or 0
      end

      -- Fallback: lastComboPoints (from pre-cast hooks or UNIT_CASTEVENT START)
      if comboPoints == 0 and CleveRoids.lastComboPoints and CleveRoids.lastComboPoints > 0 then
        comboPoints = CleveRoids.lastComboPoints
      end

      -- Fallback: ComboPointTracking for recent data (from /cast hook pre-population)
      if comboPoints == 0 and CleveRoids.ComboPointTracking then
        local tracking = CleveRoids.ComboPointTracking[spellName]
        if tracking and tracking.combo_points and tracking.combo_points > 0 then
          local age = GetTime() - (tracking.cast_time or 0)
          if age < 1.0 then  -- Use if less than 1 second old
            comboPoints = tracking.combo_points
          end
        end
      end

      -- Store combo points in pendingCasts for AURA_CAST to retrieve
      if comboPoints > 0 then
        lib.pendingCasts[targetGuid] = lib.pendingCasts[targetGuid] or {}
        lib.pendingCasts[targetGuid][spellName] = lib.pendingCasts[targetGuid][spellName] or {}
        lib.pendingCasts[targetGuid][spellName].comboPoints = comboPoints
        lib.pendingCasts[targetGuid][spellName].capturedAt = GetTime()
        lib.pendingCasts[targetGuid][spellName].spellId = spellId

        if CleveRoids.debug then
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cff00ffaa[SPELL_GO COMBO]|r Captured %d CP for %s on %s",
              comboPoints, spellName, lib.guidToName[targetGuid] or "Unknown")
          )
        end
      end
    end

  elseif event == "AURA_CAST_ON_SELF" or event == "AURA_CAST_ON_OTHER" then
    -- Skip if pfUI enhanced tracking is active
    if lib.hasPfUIEnhanced then return end

    local spellId = arg1
    local casterGuid = arg2
    local targetGuid = arg3
    local durationMs = arg8

    if not spellId or not targetGuid then return end
    targetGuid = CleveRoids.NormalizeGUID(targetGuid)

    local spellName, spellRankStr, texture = SpellInfo and SpellInfo(spellId)
    if not spellName then return end

    -- Extract rank number
    local rankNum = 0
    if spellRankStr and spellRankStr ~= "" then
      rankNum = tonumber((string.gsub(spellRankStr, "Rank ", ""))) or 0
    end

    local duration = durationMs and (durationMs / 1000) or 0
    local now = GetTime()
    local _, playerGUID = UnitExists("player")
    local isOurs = (playerGUID and casterGuid == playerGUID)

    -- Check if this debuff recently failed (miss/dodge/parry) on this specific target
    if isOurs and lib:DidSpellFail(spellName, targetGuid) then
      return  -- Don't track - spell failed
    end

    -- Handle combo point abilities for our casts
    if isOurs and lib.combopointAbilities[spellName] then
      -- Priority order for combo points:
      -- 1. SPELL_CAST_EVENT capture (client-side, before server consumes CP)
      -- 2. pendingCasts from SPELL_GO (captured on spell landing)
      -- 3. CleveRoids.lastComboPoints (from pre-cast hooks)
      -- 4. GetComboPoints() (might be 0 if already consumed)
      local comboPoints = 0
      local comboSource = "none"

      -- PRIMARY: Check SPELL_CAST_EVENT capture (most reliable - client-side pre-server)
      local castPending = CleveRoids.pendingCasts and CleveRoids.pendingCasts[spellId]
      if castPending and castPending.comboPoints and castPending.comboPoints > 0 then
        comboPoints = castPending.comboPoints
        comboSource = "SPELL_CAST_EVENT"
      end

      -- Fallback: Check lib.pendingCasts (populated by SPELL_GO)
      if comboPoints == 0 and lib.pendingCasts[targetGuid] and lib.pendingCasts[targetGuid][spellName] then
        local pending = lib.pendingCasts[targetGuid][spellName]
        local age = GetTime() - (pending.capturedAt or 0)
        if pending.comboPoints and pending.comboPoints > 0 and age < 2.0 then
          comboPoints = pending.comboPoints
          comboSource = "SPELL_GO"
        end
      end

      -- Clean up lib.pendingCasts after reading (regardless of which source won)
      if lib.pendingCasts[targetGuid] and lib.pendingCasts[targetGuid][spellName] then
        lib.pendingCasts[targetGuid][spellName] = nil
      end

      -- Fallback to lastComboPoints
      if comboPoints == 0 and CleveRoids.lastComboPoints and CleveRoids.lastComboPoints > 0 then
        comboPoints = CleveRoids.lastComboPoints
        comboSource = "lastComboPoints"
      end

      -- Last resort: current GetComboPoints (might be 0)
      if comboPoints == 0 then
        comboPoints = CleveRoids.GetComboPoints and CleveRoids.GetComboPoints() or 0
        if comboPoints > 0 then
          comboSource = "GetComboPoints"
        end
      end

      -- Default to 1 CP if we couldn't find any data
      if comboPoints == 0 then
        comboPoints = 1
        comboSource = "default"
      end

      if CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
          string.format("|cff00aaff[AURA_CAST COMBO]|r %s using %d CP (source: %s)",
            spellName, comboPoints, comboSource)
        )
      end

      -- Use our GetDuration which handles combo points
      duration = lib:GetDuration(spellId, casterGuid, comboPoints)
    end

    -- Store in appropriate table
    if isOurs then
      lib.ownDebuffs[targetGuid] = lib.ownDebuffs[targetGuid] or {}

      -- Check existing for rank comparison
      local existing = lib.ownDebuffs[targetGuid][spellName]
      if existing and existing.startTime and existing.duration then
        local timeleft = (existing.startTime + existing.duration) - now
        if timeleft > 0 and rankNum > 0 and existing.rank and rankNum < existing.rank then
          -- Lower rank cannot overwrite higher rank
          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cffff6600[AURA_CAST RANK BLOCK]|r %s Rank %d cannot overwrite Rank %d",
                spellName, rankNum, existing.rank)
            )
          end
          return
        end
      end

      lib.ownDebuffs[targetGuid][spellName] = {
        startTime = now,
        duration = duration,
        texture = texture,
        rank = rankNum,
        slot = nil,  -- Will be set by DEBUFF_ADDED
      }

      if CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
          string.format("|cff00ffff[AURA_CAST OURS]|r %s duration=%.1fs target=%s",
            spellName, duration, lib.guidToName[targetGuid] or "Unknown")
        )
      end
    else
      -- Other player's debuff
      lib.allAuraCasts[targetGuid] = lib.allAuraCasts[targetGuid] or {}
      lib.allAuraCasts[targetGuid][spellName] = lib.allAuraCasts[targetGuid][spellName] or {}
      lib.allAuraCasts[targetGuid][spellName][casterGuid] = {
        startTime = now,
        duration = duration,
        rank = rankNum,
      }
    end

  elseif event == "DEBUFF_ADDED_OTHER" then
    -- Skip if pfUI enhanced tracking is active
    if lib.hasPfUIEnhanced then return end

    local guid = arg1
    local slot = arg2
    local spellId = arg3
    local stacks = arg4 or 1

    if not guid or not slot or not spellId then return end
    guid = CleveRoids.NormalizeGUID(guid)

    local spellName = SpellInfo and SpellInfo(spellId)
    if not spellName then return end

    local _, playerGUID = UnitExists("player")

    -- Update slot info in ownDebuffs if this is our debuff
    if lib.ownDebuffs[guid] and lib.ownDebuffs[guid][spellName] then
      lib.ownDebuffs[guid][spellName].slot = slot
    end

    -- Update allSlots for slot tracking
    lib.allSlots[guid] = lib.allSlots[guid] or {}
    lib.allSlots[guid][slot] = {
      spellName = spellName,
      casterGuid = playerGUID,  -- Default to player, updated if other caster known
      isOurs = lib.ownDebuffs[guid] and lib.ownDebuffs[guid][spellName] ~= nil,
    }

    -- Check allAuraCasts for caster info if not ours
    if lib.allAuraCasts[guid] and lib.allAuraCasts[guid][spellName] then
      for casterGuid, _ in pairs(lib.allAuraCasts[guid][spellName]) do
        lib.allSlots[guid][slot].casterGuid = casterGuid
        break
      end
    end

  elseif event == "DEBUFF_REMOVED_OTHER" then
    -- Skip if pfUI enhanced tracking is active
    if lib.hasPfUIEnhanced then return end

    local guid = arg1
    local slot = arg2
    local spellId = arg3

    if not guid or not slot then return end
    guid = CleveRoids.NormalizeGUID(guid)

    local spellName = spellId and SpellInfo and SpellInfo(spellId)

    -- Remove from ownDebuffs if present
    if spellName and lib.ownDebuffs[guid] and lib.ownDebuffs[guid][spellName] then
      lib.ownDebuffs[guid][spellName] = nil
    end

    -- Remove from ownSlots
    if lib.ownSlots[guid] and lib.ownSlots[guid][slot] then
      lib.ownSlots[guid][slot] = nil
    end

    -- Remove from allSlots and shift slots down
    if lib.allSlots[guid] and lib.allSlots[guid][slot] then
      lib.allSlots[guid][slot] = nil

      -- Shift slots down
      local maxSlot = 0
      for s in pairs(lib.allSlots[guid]) do
        if s > maxSlot then maxSlot = s end
      end

      for s = slot + 1, maxSlot + 1 do
        if lib.allSlots[guid][s] then
          lib.allSlots[guid][s - 1] = lib.allSlots[guid][s]
          lib.allSlots[guid][s] = nil
        end
      end
    end

  -- NAMPOWER v2.26+ UNIT_DIED - Instant cleanup on target death
  elseif event == "UNIT_DIED" then
    local guid = arg1
    if not guid then return end
    guid = CleveRoids.NormalizeGUID(guid)

    -- Get unit name before cleanup (for debug output)
    local unitName = lib.guidToName[guid]

    -- Clean up all tracking data for this GUID immediately
    if lib.ownDebuffs[guid] then
      lib.ownDebuffs[guid] = nil
    end
    if lib.ownSlots[guid] then
      lib.ownSlots[guid] = nil
    end
    if lib.allSlots[guid] then
      lib.allSlots[guid] = nil
    end
    if lib.allAuraCasts[guid] then
      lib.allAuraCasts[guid] = nil
    end
    if lib.pendingCasts[guid] then
      lib.pendingCasts[guid] = nil
    end
    if lib.recentMisses and lib.recentMisses[guid] then
      lib.recentMisses[guid] = nil
    end

    -- Clean up cast tracking for this unit (they can't be casting if dead)
    if not lib.hasPfUI76 and CleveRoids.castTracking[guid] then
      CleveRoids.castTracking[guid] = nil
    end

    -- Clean up GUID to name mapping (after 5 seconds to allow final lookups)
    -- Actually, keep it for a bit in case we need it for immunity detection
    -- lib.guidToName[guid] = nil

    if CleveRoids.debug and unitName then
      DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cffff6600[UNIT_DIED]|r Cleaned up tracking data for %s (%s)",
          unitName, guid)
      )
    end
  end
end)

-- Track the last cast spell and target for miss/dodge/parry removal
-- Format: { spellID = id, targetGUID = guid, timestamp = GetTime() }
lib.lastPlayerCast = lib.lastPlayerCast or nil

local evLearn = CreateFrame("Frame", "CleveRoidsLibDebuffLearnFrame", UIParent)
-- NOTE: RAW_COMBATLOG now handled by unified CleveRoidsUnifiedCombatLogFrame
evLearn:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")  -- For miss/dodge/parry detection

evLearn:SetScript("OnEvent", function()
  -- Handle spell misses, dodges, parries, resists, blocks, and immunities
  if event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    -- Skip chat log parsing when Nampower SPELL_GO events are available
    -- SPELL_GO provides real-time miss detection with GUID tracking
    if lib.hasStandaloneNampower or lib.hasPfUIEnhanced then return end

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
      -- CARNAGE: Clear Ferocious Bite tracking if it was dodged/parried/blocked
      -- This prevents false proc detection in edge cases
      if CleveRoids.lastFerociousBiteTime then
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
          if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
              string.format("|cffff00ff[Carnage]|r Ferocious Bite avoided by %s - clearing tracking",
                targetName or "Unknown")
            )
          end

          -- Clear Ferocious Bite tracking (no proc possible since it was avoided)
          CleveRoids.lastFerociousBiteTime = nil
          CleveRoids.lastFerociousBiteTargetGUID = nil
          CleveRoids.lastFerociousBiteTargetName = nil
          CleveRoids.lastFerociousBiteSpellID = nil
        end
      end

      -- PERSONAL DEBUFFS: Cancel pending tracking if spell was dodged/parried/blocked
      if lib.pendingPersonalDebuffs then
        local messageSpellName = string.gsub(spellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
        local toRemove = {}

        for i, pending in ipairs(lib.pendingPersonalDebuffs) do
          -- Check both the triggered spell name AND the original cast spell name
          -- (e.g., "Pounce Bleed" is triggered by "Pounce", but combat log says "Pounce was dodged")
          local pendingSpellName = SpellInfo(pending.spellID)
          local castSpellName = pending.castSpellID and SpellInfo(pending.castSpellID)

          local matchesTriggered = false
          local matchesCast = false

          if pendingSpellName then
            pendingSpellName = string.gsub(pendingSpellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
            matchesTriggered = lower(pendingSpellName) == lower(messageSpellName)
          end

          if castSpellName then
            castSpellName = string.gsub(castSpellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
            matchesCast = lower(castSpellName) == lower(messageSpellName)
          end

          if matchesTriggered or matchesCast then
            -- Found the pending debuff that was avoided - cancel it
            if CleveRoids.debug then
              local displayName = matchesCast and castSpellName or pendingSpellName
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff0000[Pending Track]|r Cancelled %s (ID:%d) - avoided by %s",
                  displayName or "Unknown", pending.spellID, targetName or "Unknown")
              )
            end
            table.insert(toRemove, i)
          end
        end

        -- Remove cancelled debuffs (iterate backwards to avoid index shifting)
        for i = table.getn(toRemove), 1, -1 do
          table.remove(lib.pendingPersonalDebuffs, toRemove[i])
        end
      end

      -- PENDING CC/SHARED DEBUFFS: Cancel pending tracking if spell was dodged/parried/blocked/missed/resisted/immune
      -- NOTE: We cancel on ALL failure types:
      -- - Physical avoidance (dodge/parry/block/miss): Combat mechanic
      -- - Resist: RNG-based spell resistance
      -- - Immune: TRUE immunity (ParseImmunityCombatLog also records for [immune] conditional)
      local isSpellFailure = find(message, "dodged") or find(message, "parried") or
                              find(message, "blocked") or find(message, "missed") or
                              find(message, "resist") or find(message, "immune")

      if isSpellFailure and lib.pendingCCDebuffs then
        local messageSpellName = string.gsub(spellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
        local toRemove = {}

        for i, pending in ipairs(lib.pendingCCDebuffs) do
          local pendingSpellName = SpellInfo(pending.spellID)
          if pendingSpellName then
            pendingSpellName = string.gsub(pendingSpellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
            if lower(pendingSpellName) == lower(messageSpellName) then
              -- Found the pending CC that was avoided/resisted - cancel it (don't record immunity)
              if CleveRoids.debug then
                local failType = find(message, "dodged") and "dodged" or
                                  find(message, "parried") and "parried" or
                                  find(message, "blocked") and "blocked" or
                                  find(message, "resist") and "resisted" or
                                  find(message, "immune") and "immune" or "missed"
                DEFAULT_CHAT_FRAME:AddMessage(
                  string.format("|cffff0000[CC Track]|r Cancelled %s (%s) - %s by %s",
                    pendingSpellName, pending.ccType or "CC", failType, targetName or "Unknown")
                )
              end
              table.insert(toRemove, i)
            end
          end
        end

        -- Remove cancelled CC tracking (iterate backwards to avoid index shifting)
        for i = table.getn(toRemove), 1, -1 do
          table.remove(lib.pendingCCDebuffs, toRemove[i])
        end
      end

      -- SHARED DEBUFFS: Cancel pending tracking if spell was dodged/parried/blocked/missed/resisted/immune
      if isSpellFailure and lib.pendingSharedDebuffs then
        local messageSpellName = string.gsub(spellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
        local toRemove = {}

        for i, pending in ipairs(lib.pendingSharedDebuffs) do
          -- Check both the tracking spell name AND the original cast spell name
          local pendingSpellName = SpellInfo(pending.spellID)
          local castSpellName = pending.castSpellID and SpellInfo(pending.castSpellID)

          local matchesTracking = false
          local matchesCast = false

          if pendingSpellName then
            pendingSpellName = string.gsub(pendingSpellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
            matchesTracking = lower(pendingSpellName) == lower(messageSpellName)
          end

          if castSpellName then
            castSpellName = string.gsub(castSpellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
            matchesCast = lower(castSpellName) == lower(messageSpellName)
          end

          if matchesTracking or matchesCast then
            -- Found the pending shared debuff that failed - cancel tracking
            if CleveRoids.debug then
              local displayName = matchesCast and castSpellName or pendingSpellName
              local failType = find(message, "dodged") and "dodged" or
                               find(message, "parried") and "parried" or
                               find(message, "blocked") and "blocked" or
                               find(message, "resist") and "resisted" or
                               find(message, "immune") and "immune" or "missed"
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff0000[Shared Track]|r Cancelled %s (school:%s) - %s by %s",
                  displayName or "Unknown", pending.school or "unknown", failType, targetName or "Unknown")
              )
            end
            table.insert(toRemove, i)
          end
        end

        -- Remove cancelled shared debuff tracking (iterate backwards to avoid index shifting)
        for i = table.getn(toRemove), 1, -1 do
          table.remove(lib.pendingSharedDebuffs, toRemove[i])
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

    -- SHAMAN MOLTEN BLAST: Check for damage hit to trigger Flame Shock refresh (TWoW Custom)
    -- Credits: Avitasia / Cursive addon
    -- Pattern: "Your Molten Blast hits/crits X for Y Fire damage"
    if CleveRoids.lastMoltenBlastTime and CleveRoids.lastMoltenBlastTargetGUID then
      local timeSinceCast = GetTime() - CleveRoids.lastMoltenBlastTime
      -- Check within 1 second of cast
      if timeSinceCast < 1.0 then
        -- Check if message mentions Molten Blast damage
        if find(message, "Molten Blast") and find(message, "Fire damage") then
          local targetGUID = CleveRoids.lastMoltenBlastTargetGUID

          -- Find active Flame Shock on target and refresh it
          if lib.objects[targetGUID] then
            for flameShockID, _ in pairs(CleveRoids.FlameShockSpellIDs or {}) do
              local rec = lib.objects[targetGUID][flameShockID]
              -- Only refresh player's own Flame Shock, not other shamans'
              if rec and rec.duration and rec.start and rec.caster == "player" then
                local remaining = rec.duration + rec.start - GetTime()
                if remaining > 0 then
                  -- Refresh: reset start time to now
                  rec.start = GetTime()

                  -- Sync refresh to pfUI
                  local targetName = lib.guidToName[targetGUID]
                  if pfUI and pfUI.api and pfUI.api.libdebuff and targetName then
                    local pflib = pfUI.api.libdebuff
                    local spellName = SpellInfo(flameShockID)
                    if spellName and pflib.AddEffect then
                      local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                      local targetLevel = UnitLevel(targetGUID) or UnitLevel("target") or 1
                      pflib:AddEffect(targetName, targetLevel, baseName, rec.duration, "player")
                    end
                  end

                  if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                      string.format("|cff0070dd[Molten Blast]|r Refreshed Flame Shock to %.1fs on %s",
                        rec.duration, lib.guidToName[targetGUID] or "Unknown")
                    )
                  end
                  break
                end
              end
            end
          end

          -- Clear tracking
          CleveRoids.lastMoltenBlastTime = nil
          CleveRoids.lastMoltenBlastTargetGUID = nil
        end
      else
        -- Time window expired
        CleveRoids.lastMoltenBlastTime = nil
        CleveRoids.lastMoltenBlastTargetGUID = nil
      end
    end
    -- NOTE: RAW_COMBATLOG fade handling now done by unified CleveRoidsUnifiedCombatLogFrame
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

-- Judgement refresh on melee hits
-- NOTE: Judgement refresh is now handled in Core.lua via UNIT_CASTEVENT (MAINHAND/OFFHAND)
-- This chat-based fallback is only used if SuperWoW is not available
local evJudgement = CreateFrame("Frame", "CleveRoidsLibDebuffJudgementRefreshFrame", UIParent)

-- Only use chat-based detection if SuperWoW is not available
if not CleveRoids.hasSuperwow then
  evJudgement:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
  evJudgement:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
end

evJudgement:SetScript("OnEvent", function()
  -- Skip if SuperWoW is available (handled by UNIT_CASTEVENT instead)
  if CleveRoids.hasSuperwow then return end
  -- Only process for paladins
  if CleveRoids.playerClass ~= "PALADIN" then return end

  if not arg1 then return end

  -- Debug: Show all combat hit events if debug is enabled
  if CleveRoids.debug and event == "CHAT_MSG_COMBAT_SELF_HITS" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[Combat Hit Event]|r " .. arg1)
  end

  -- Check if this is a melee hit (not a spell hit)
  -- CHAT_MSG_COMBAT_SELF_HITS contains both melee and spell hits
  -- Filter out spell hits by checking for spell names in parentheses or common patterns
  -- Melee hits look like: "You hit Target for X." or "You crit Target for X."
  local isSpellHit = string.find(arg1, "%(") -- Spell hits often have parentheses
  if isSpellHit then return end

  -- Must contain "hit" or "crit" to be a valid melee attack
  local lowerMsg = string.lower(arg1)
  local hasHit = string.find(lowerMsg, "hit") or string.find(lowerMsg, "crit")
  if not hasHit then return end

  -- Get current target
  local _, targetGUID = UnitExists("target")
  if not targetGUID then return end

  targetGUID = CleveRoids.NormalizeGUID(targetGUID)
  if not targetGUID or not lib.objects[targetGUID] then return end

  -- Refresh all active Judgements on the target
  for spellID, rec in pairs(lib.objects[targetGUID]) do
    if lib.judgementSpells[spellID] and rec.start and rec.duration then
      -- Only refresh if the Judgement is still active and was cast by player
      local remaining = rec.duration + rec.start - GetTime()
      if remaining > 0 and rec.caster == "player" then
        -- Refresh the Judgement by updating the start time
        rec.start = GetTime()

        if CleveRoids.debug then
          local spellName = SpellInfo(spellID) or "Unknown"
          DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cff00ffaa[Judgement Refresh]|r Refreshed %s (ID:%d) on melee hit - new duration: %ds",
              spellName, spellID, rec.duration)
          )
        end

        -- Also sync to pfUI if it's loaded
        if pfUI and pfUI.api and pfUI.api.libdebuff then
          local targetName = lib.guidToName[targetGUID] or UnitName("target")
          local targetLevel = UnitLevel("target") or 0
          local spellName = SpellInfo(spellID)

          if spellName and targetName then
            -- Remove rank from spell name to match pfUI's format
            local effectName = string.gsub(spellName, "%s*%(Rank %d+%)", "")

            -- Refresh in pfUI's tracking
            pfUI.api.libdebuff:AddEffect(targetName, targetLevel, effectName, rec.duration, "player")

            if CleveRoids.debug then
              DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cff00ffaa[pfUI Judgement Refresh]|r Synced %s refresh to pfUI",
                  effectName)
              )
            end
          end
        end
      end
    end
  end
end)

-- TALENT MODIFIER SYSTEM

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

-- NOTE: Brutal Impact affects the STUN portion of Pounce (cast spell IDs 9005, 9823, 9827)
-- The BLEED portion (triggered spell IDs 9007, 9824, 9826) is NOT affected by Brutal Impact
-- We track the bleed for immunity detection, not the stun, so no talent modifiers needed here

-- NOTE: Carnage talent (Tab 2, ID 17) is NOT a duration modifier!
-- Carnage is a refresh mechanic: When Ferocious Bite procs Carnage, it refreshes Rip/Rake to original duration
-- Proc detection: Combo points stay at 1 after FB instead of dropping to 0
-- This is handled in ComboPointTracker.lua via PLAYER_COMBO_POINTS event

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

-- EQUIPMENT MODIFIER SYSTEM

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

-- NAMPOWER SPELL MODIFIERS INTEGRATION (v2.18+)

-- Try to get duration modifiers from Nampower's GetSpellModifiers
-- This function supplements (not replaces) the talent/equipment modifier system
-- Returns: Modified duration, or nil if no Nampower modifier applies
-- Parameters:
--   spellID: The spell ID
--   baseDuration: The base duration before modifiers
function CleveRoids.ApplyNampowerDurationModifier(spellID, baseDuration)
    if not spellID or not baseDuration then
        return nil
    end

    -- Check if Nampower API is available with GetSpellModifiers
    local API = CleveRoids.NampowerAPI
    if not API or not GetSpellModifiers then
        return nil
    end

    -- MODIFIER_DURATION = 1
    local flat, percent, hasModifier = GetSpellModifiers(spellID, 1)

    if not hasModifier or (flat == 0 and percent == 0) then
        return nil
    end

    -- Apply flat modifier first, then percentage
    -- Nampower returns percent as final multiplier (90 = 90% of original, not -10% change)
    local modified = baseDuration + (flat or 0)
    if percent and percent ~= 0 then
        modified = modified * (percent / 100)
    end

    if CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff00ff[Nampower Duration Modifier]|r %s (ID:%d): %ds -> %ds (flat: %+d, percent: %d%%)",
                SpellInfo(spellID) or "Unknown", spellID, baseDuration, modified,
                flat or 0, percent or 0)
        )
    end

    return modified
end

-- Comprehensive duration modifier function that combines all sources
-- Logic:
--   1. If Nampower GetSpellModifiers available: use it exclusively (includes talents, buffs, equipment)
--   2. Otherwise fallback: apply manual talent modifiers, then equipment modifiers
--   3. Always apply set bonus modifiers last
-- Parameters:
--   spellID: The spell ID
--   baseDuration: The base duration (after combo points if applicable)
-- Returns: Fully modified duration
function CleveRoids.ApplyAllDurationModifiers(spellID, baseDuration)
    if not spellID or not baseDuration then
        return baseDuration
    end

    local duration = baseDuration

    -- Try Nampower's GetSpellModifiers first (includes dynamic modifiers from buffs/talents/equipment)
    local nampowerDuration = CleveRoids.ApplyNampowerDurationModifier(spellID, duration)
    if nampowerDuration then
        -- Nampower handled all modifiers (talents, buffs, equipment effects like Idol of Savagery)
        -- Do NOT apply equipment modifiers again - Nampower already includes them
        duration = nampowerDuration
    else
        -- Fallback: use manual talent and equipment modifiers when Nampower unavailable
        if CleveRoids.ApplyTalentModifier then
            duration = CleveRoids.ApplyTalentModifier(spellID, duration)
        end
        if CleveRoids.ApplyEquipmentModifier then
            duration = CleveRoids.ApplyEquipmentModifier(spellID, duration)
        end
    end

    -- Always apply set bonus modifiers last
    if CleveRoids.ApplySetBonusModifier then
        duration = CleveRoids.ApplySetBonusModifier(spellID, duration)
    end

    return duration
end

-- SET BONUS MODIFIER SYSTEM

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

-- IMMUNITY TRACKING SYSTEM
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

-- CC (Crowd Control) immunity types
-- These are stored with "cc_" prefix in CleveRoids_ImmunityData to avoid collision with damage schools
local CC_IMMUNITY_TYPES = {
    stun = true,       -- Cheap Shot, Kidney Shot, Bash, Gouge, Sap
    fear = true,       -- Fear, Psychic Scream, Howl of Terror
    root = true,       -- Entangling Roots, Frost Nova
    silence = true,    -- Silence, Counterspell
    sleep = true,      -- Hibernate, Wyvern Sting
    charm = true,      -- Mind Control, Seduction
    polymorph = true,  -- Polymorph (all variants)
    banish = true,     -- Banish
    horror = true,     -- Death Coil
    disorient = true,  -- Scatter Shot, Blind
    snare = true,      -- Hamstring, Wing Clip
}

-- Maps DBC mechanic IDs back to CC type names for immunity recording
-- Inverse of CleveRoids.CCMechanics (defined in Conditionals.lua)
local MECHANIC_TO_CC_TYPE = {
    [1] = "charm",
    [2] = "disorient",
    [5] = "fear",
    [7] = "root",
    [9] = "silence",
    [10] = "sleep",
    [11] = "snare",
    [12] = "stun",
    [13] = "stun",     -- freeze → stun (similar effect)
    [14] = "stun",     -- knockout/gouge → stun
    [17] = "polymorph",
    [18] = "banish",
    [20] = "shackle",
    [24] = "horror",
    [27] = "disorient", -- daze → disorient
    [30] = "stun",     -- sap → stun
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
    ["Faerie Fire"] = "nature",
    ["Faerie Fire (Feral)"] = "nature",
    ["Faerie Fire (Bear)"] = "nature",
    ["Moonfire"] = "arcane",  -- Initial hit deals damage, but debuff is arcane
    ["Insect Swarm"] = "nature",
    ["Abolish Poison"] = "nature",
    ["Remove Curse"] = "arcane",
    ["Pounce Bleed"] = "bleed",  -- Triggered by Pounce (9005→9007, 9823→9824, 9827→9826)

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

    -- Get base name early for split damage spell check
    local baseName = nil
    if spellName then
        baseName = string.gsub(spellName, "%s*%(.-%)%s*$", "")
    elseif spellID and SpellInfo then
        local fullName = SpellInfo(spellID)
        if fullName then
            baseName = string.gsub(fullName, "%s*%(.-%)%s*$", "")
        end
    end

    -- PRIORITY 0 (HIGHEST): Split damage spells ALWAYS use their debuff school for immunity checks
    -- This prevents the initial physical hit from being learned and masking bleed immunity.
    -- Example: Rake's initial hit is physical, but the DoT is bleed. On bleed-immune targets,
    -- the DoT never ticks, so spellSchoolMapping stays "physical" - which would miss bleed immunity!
    if baseName and SPLIT_DAMAGE_SPELLS[baseName] then
        local school = SPLIT_DAMAGE_SPELLS[baseName].debuff
        return school
    end

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

    -- Remove rank information for cache consistency (may already be set from above)
    if not baseName then
        baseName = string.gsub(spellName, "%s*%(.-%)%s*$", "")
    end

    -- PRIORITY 3: Check cache
    if spellSchoolCache[baseName] then
        return spellSchoolCache[baseName]
    end

    -- PRIORITY 4: SPLIT_DAMAGE_SPELLS already checked at Priority 0

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

        -- Arcane
        elseif string.find(lower, "arcane") or string.find(lower, "polymorph") or
               string.find(lower, "mana burn") then
            school = "arcane"

        -- Nature: Faerie Fire (check before "fire" to avoid false positive)
        elseif string.find(lower, "faerie") then
            school = "nature"

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

-- Spells with INVULNERABILITY mechanic (mechanic 25) from BuffLib SpellData DBC
-- These grant temporary immunity and should not trigger permanent immunity recording
-- Source: BuffLib/SpellData.lua - extracted from DBC files
local INVULNERABILITY_SPELL_IDS = {
    -- Paladin
    [498] = true,    -- Divine Protection (Rank 1)
    [642] = true,    -- Divine Shield (Rank 1)
    [1020] = true,   -- Divine Shield (Rank 2)
    [1022] = true,   -- Blessing of Protection (Rank 1)
    [5573] = true,   -- Divine Protection (Rank 2)
    [5599] = true,   -- Blessing of Protection (Rank 2)
    [10278] = true,  -- Blessing of Protection (Rank 3)
    [25771] = true,  -- Forbearance (debuff after immunity)
    -- Old/Unused Paladin
    [1052] = true,   -- zzOLDBlessing of Righteousness
    [5601] = true,   -- zzOLDBlessing of Righteousness
    [5602] = true,   -- zzOLDBlessing of Righteousness
    [10280] = true,  -- zzOLDBlessing of Righteousness
    [10281] = true,  -- zzOLDBlessing of Righteousness
    -- Rogue
    [6770] = true,   -- Sap (invuln during effect)
    -- NPC/Misc
    [7992] = true,   -- Slowing Poison
    [11638] = true,  -- Radiation Poisoning
    [14897] = true,  -- Slowing Poison
    [16603] = true,  -- Demonfork
    [16791] = true,  -- Furious Anger
    [17407] = true,  -- Wound
    [18208] = true,  -- Poison
    [23230] = true,  -- Blood Fury
    [24005] = true,  -- Food
    [24707] = true,  -- Food
    [24865] = true,  -- Sanctified Orb
    [26263] = true,  -- Dim Sum
    [28522] = true,  -- Icebolt
    [29055] = true,  -- Refreshing Red Apple
    [29325] = true,  -- Acid Volley
    [29330] = true,  -- Sapphiron's Wing Buffet Despawn
    -- Spell Reflection (no DBC mechanic, but grants immunity to reflected schools)
    [9941] = true,   -- Spell Reflection
    [9943] = true,   -- Spell Reflection
    [10074] = true,  -- Spell Reflection
    [11818] = true,  -- Spell Reflection
    [21118] = true,  -- Spell Reflection
    -- School-specific Reflectors (Engineering items)
    [23097] = true,  -- Fire Reflector
    [23131] = true,  -- Frost Reflector
    [23132] = true,  -- Shadow Reflector
    [23178] = true,  -- Nature Reflector
    [23216] = true,  -- Arcane Reflector
    -- Multi-school Reflect (NPC abilities)
    [13022] = true,  -- Fire and Arcane Reflect
    [19595] = true,  -- Shadow and Frost Reflect
    -- Generic Reflection buffs
    [3651] = true,   -- Shield of Reflection
    [9906] = true,   -- Reflection
    [10831] = true,  -- Reflection Field
    [17106] = true,  -- Reflection
    [17107] = true,  -- Reflection
    [17108] = true,  -- Reflection
    [20223] = true,  -- Magic Reflection
    [20619] = true,  -- Magic Reflection
    [22067] = true,  -- Reflection
    [23920] = true,  -- Shield Reflection
    [23921] = true,  -- Shield Reflection
    [27564] = true,  -- Reflection
}

-- Check if a unit has any immunity-granting buff active
-- Uses only spell IDs from DBC mechanic 25 (INVULNERABILITY) for reliability
-- Returns the buff name if found, nil otherwise
local function HasImmunityGrantingBuff(unit)
    if not CleveRoids.hasSuperwow then return nil end
    if not UnitExists(unit) then return nil end

    for i = 1, 32 do
        local texture, stacks, spellID = UnitBuff(unit, i)
        if not texture then break end

        if spellID and INVULNERABILITY_SPELL_IDS[spellID] then
            local buffName = SpellInfo(spellID) or ("SpellID:" .. spellID)
            return buffName
        end
    end

    return nil
end

-- CC IMMUNITY TRACKING

-- Get CC type from a spell ID using the CCSpellMechanics table from Conditionals.lua
-- Returns: CC type name (e.g., "stun", "fear") or nil if not a CC spell
local function GetSpellCCType(spellID)
    if not spellID or spellID <= 0 then return nil end

    -- CCSpellMechanics is defined in Conditionals.lua and loaded before this
    local mechanic = CleveRoids.CCSpellMechanics and CleveRoids.CCSpellMechanics[spellID]
    if not mechanic then return nil end

    -- Map mechanic ID to CC type name
    return MECHANIC_TO_CC_TYPE[mechanic]
end

-- Expose publicly for use by other modules
CleveRoids.GetSpellCCType = GetSpellCCType

-- Record a CC immunity (permanent or buff-based)
-- Parameters:
--   npcName: Name of the NPC that is immune
--   ccType: CC type name (e.g., "stun", "fear", "root")
--   conditionalBuff: Optional buff name required for the immunity
--   spellName: Optional spell name for debug output
local function RecordCCImmunity(npcName, ccType, conditionalBuff, spellName)
    if not npcName or not ccType or npcName == "" then
        return
    end

    -- Validate CC type
    if not CC_IMMUNITY_TYPES[ccType] then
        if CleveRoids.debug then
            CleveRoids.Print("|cffff0000[CC Immunity]|r Unknown CC type: " .. tostring(ccType))
        end
        return
    end

    -- Store with "cc_" prefix to avoid collision with damage schools
    local key = "cc_" .. ccType

    -- Initialize CC type table
    if not CleveRoids_ImmunityData[key] then
        CleveRoids_ImmunityData[key] = {}
    end

    -- Don't overwrite existing immunity with same data
    local existing = CleveRoids_ImmunityData[key][npcName]

    -- Record immunity
    if conditionalBuff then
        -- Buff-based immunity
        local immunityData = { buff = conditionalBuff }
        if existing and type(existing) == "table" and existing.buff == conditionalBuff then
            return  -- Already recorded
        end
        CleveRoids_ImmunityData[key][npcName] = immunityData

        if CleveRoids.debug then
            local spellInfo = spellName and (" (" .. spellName .. ")") or ""
            CleveRoids.Print("|cff00ff00[CC Immunity]|r " .. npcName .. " is immune to " .. ccType .. spellInfo .. " when buffed with: " .. conditionalBuff)
        end
    else
        -- Permanent immunity
        if existing == true then
            return  -- Already recorded
        end
        CleveRoids_ImmunityData[key][npcName] = true

        if CleveRoids.debug then
            local spellInfo = spellName and (" (" .. spellName .. ")") or ""
            CleveRoids.Print("|cff00ff00[CC Immunity]|r " .. npcName .. " is permanently immune to " .. ccType .. spellInfo)
        end
    end
end

-- Expose publicly
CleveRoids.RecordCCImmunity = RecordCCImmunity

-- Remove a CC immunity record when a spell successfully lands
-- This is called when we verify that a CC effect actually landed on a previously-immune NPC
-- Parameters:
--   npcName: Name of the NPC
--   ccType: CC type name (e.g., "stun", "fear", "root")
local function RemoveCCImmunity(npcName, ccType)
    if not npcName or not ccType or npcName == "" then
        return
    end

    local key = "cc_" .. ccType

    if CleveRoids_ImmunityData[key] and CleveRoids_ImmunityData[key][npcName] then
        CleveRoids_ImmunityData[key][npcName] = nil

        if CleveRoids.debug then
            CleveRoids.Print("|cff00aaff[CC Immunity Removed]|r " .. npcName .. " is no longer immune to " .. ccType .. " (spell landed successfully)")
        end
    end
end

-- Expose publicly
CleveRoids.RemoveCCImmunity = RemoveCCImmunity

-- Check if a unit is immune to a specific CC type
-- Parameters:
--   unitId: WoW unit ID (e.g., "target", "focus")
--   ccType: CC type name (e.g., "stun", "fear")
-- Returns: true if immune, false otherwise
local function CheckCCImmunity(unitId, ccType)
    if not unitId or not UnitExists(unitId) then
        return false
    end

    -- CC immunity only tracked for NPCs
    if UnitIsPlayer(unitId) then
        return false
    end

    local targetName = UnitName(unitId)
    -- Fallback to GUID->name cache if UnitName fails
    -- This happens when multiscan passes a GUID that isn't the current target
    if not targetName or targetName == "" or targetName == "Unknown" then
        local normalizedGuid = CleveRoids.NormalizeGUID(unitId)
        if normalizedGuid and lib and lib.guidToName then
            targetName = lib.guidToName[normalizedGuid]
        end
    end
    if not targetName or targetName == "" then
        return false
    end

    -- Look up CC immunity with "cc_" prefix
    local key = "cc_" .. ccType
    local immunityData = CleveRoids_ImmunityData[key] and CleveRoids_ImmunityData[key][targetName]

    if not immunityData then
        return false
    end

    if immunityData == true then
        -- Permanent immunity
        return true
    elseif type(immunityData) == "table" and immunityData.buff then
        -- Buff-based immunity: check if the buff is currently active
        local buffs = GetUnitBuffs(unitId)
        return buffs[immunityData.buff] == true
    end

    return false
end

-- Expose publicly
CleveRoids.CheckCCImmunity = CheckCCImmunity

-- DAMAGE SCHOOL IMMUNITY RECORDING

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

    -- SPLIT DAMAGE SPELLS: Combat log immunity messages refer to the INITIAL hit failing,
    -- not the DoT/debuff. For spells like Pounce (stun + bleed), if a mob is stun-immune,
    -- the bleed might still apply. Use the initial school for immunity recording.
    if spellName then
        local baseName = string.gsub(spellName, "%s*%(.-%)%s*$", "")
        if SPLIT_DAMAGE_SPELLS[baseName] then
            school = SPLIT_DAMAGE_SPELLS[baseName].initial
            if CleveRoids.debug then
                CleveRoids.Print("|cff00aaff[Split Damage]|r " .. baseName .. " immunity recorded as '" .. school .. "' (initial), not '" .. SPLIT_DAMAGE_SPELLS[baseName].debuff .. "' (debuff)")
            end
        end
    end

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

-- Expose RecordImmunity globally for use by debuff verification (bleed immunity detection)
CleveRoids.RecordImmunity = RecordImmunity

-- Remove a spell/school immunity record when a spell successfully lands
-- This is called when we verify that a debuff actually landed on a previously-immune NPC
-- Parameters:
--   npcName: Name of the NPC
--   school: Damage school (e.g., "fire", "bleed") or spell name for unknown schools
local function RemoveSpellImmunity(npcName, school)
    if not npcName or not school or npcName == "" then
        return
    end

    if CleveRoids_ImmunityData[school] and CleveRoids_ImmunityData[school][npcName] then
        CleveRoids_ImmunityData[school][npcName] = nil

        if CleveRoids.debug then
            CleveRoids.Print("|cff00aaff[Immunity Removed]|r " .. npcName .. " is no longer immune to " .. school .. " (spell landed successfully)")
        end
    end
end

-- Expose publicly
CleveRoids.RemoveSpellImmunity = RemoveSpellImmunity

-- Cancel pending verification entries when immunity is confirmed from combat log
-- This prevents redundant 0.2s verification when combat log already told us about immunity
-- Parameters:
--   targetName: Name of the target (required)
--   spellName: Name of the spell (optional - if nil, cancels ALL pending entries for target)
local function CancelPendingVerification(targetName, spellName)
    if not targetName or targetName == "" then return end

    local debug = CleveRoids.debug
    local lowerTarget = string.lower(targetName)
    local lowerSpell = spellName and string.lower(string.gsub(spellName, "%s*%(.-%)%s*$", ""))

    -- Cancel pending CC debuff entries
    if lib.pendingCCDebuffs then
        local toRemove = {}
        for i, pending in ipairs(lib.pendingCCDebuffs) do
            local matches = false
            if pending.targetName and string.lower(pending.targetName) == lowerTarget then
                if lowerSpell then
                    -- Specific spell - only cancel if spell matches
                    local pendingSpellName = pending.spellName and string.lower(string.gsub(pending.spellName, "%s*%(.-%)%s*$", ""))
                    if pendingSpellName and pendingSpellName == lowerSpell then
                        matches = true
                    end
                else
                    -- No spell specified - cancel all for this target
                    matches = true
                end
            end
            if matches then
                if debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cff00aaff[Combat Log Immune]|r Cancelled pending CC verification for %s on %s - combat log confirmed immunity",
                            pending.ccType or "CC", targetName)
                    )
                end
                table.insert(toRemove, i)
            end
        end
        for i = table.getn(toRemove), 1, -1 do
            table.remove(lib.pendingCCDebuffs, toRemove[i])
        end
    end

    -- Cancel pending shared debuff entries
    if lib.pendingSharedDebuffs then
        local toRemove = {}
        for i, pending in ipairs(lib.pendingSharedDebuffs) do
            local matches = false
            if pending.targetName and string.lower(pending.targetName) == lowerTarget then
                if lowerSpell then
                    local pendingSpellName = pending.spellID and SpellInfo(pending.spellID)
                    pendingSpellName = pendingSpellName and string.lower(string.gsub(pendingSpellName, "%s*%(.-%)%s*$", ""))
                    if pendingSpellName and pendingSpellName == lowerSpell then
                        matches = true
                    end
                else
                    matches = true
                end
            end
            if matches then
                if debug then
                    local spellNameDebug = pending.spellID and SpellInfo(pending.spellID) or "Unknown"
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cff00aaff[Combat Log Immune]|r Cancelled pending shared debuff verification for %s on %s - combat log confirmed immunity",
                            spellNameDebug, targetName)
                    )
                end
                table.insert(toRemove, i)
            end
        end
        for i = table.getn(toRemove), 1, -1 do
            table.remove(lib.pendingSharedDebuffs, toRemove[i])
        end
    end

    -- Cancel pending personal debuff entries (bleeds)
    if lib.pendingPersonalDebuffs then
        local toRemove = {}
        for i, pending in ipairs(lib.pendingPersonalDebuffs) do
            local matches = false
            if pending.targetName and string.lower(pending.targetName) == lowerTarget then
                if lowerSpell then
                    local pendingSpellName = pending.spellID and SpellInfo(pending.spellID)
                    pendingSpellName = pendingSpellName and string.lower(string.gsub(pendingSpellName, "%s*%(.-%)%s*$", ""))
                    local castSpellName = pending.castSpellID and SpellInfo(pending.castSpellID)
                    castSpellName = castSpellName and string.lower(string.gsub(castSpellName, "%s*%(.-%)%s*$", ""))
                    if (pendingSpellName and pendingSpellName == lowerSpell) or
                       (castSpellName and castSpellName == lowerSpell) then
                        matches = true
                    end
                else
                    matches = true
                end
            end
            if matches then
                if debug then
                    local spellNameDebug = pending.spellID and SpellInfo(pending.spellID) or "Unknown"
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cff00aaff[Combat Log Immune]|r Cancelled pending personal debuff verification for %s on %s - combat log confirmed immunity",
                            spellNameDebug, targetName)
                    )
                end
                table.insert(toRemove, i)
            end
        end
        for i = table.getn(toRemove), 1, -1 do
            table.remove(lib.pendingPersonalDebuffs, toRemove[i])
        end
    end
end

-- Combat log parser for immunity, reflect, and evade detection
-- Handles both RAW_COMBATLOG (arg1=formatted, arg2=raw) and CHAT_MSG events (arg1=formatted only)
local function ParseImmunityCombatLog()
    local message = arg1      -- Formatted chat message text
    local rawMessage = arg2   -- Raw message (only present for RAW_COMBATLOG)

    if not message then return end

    -- PERFORMANCE: Quick length check
    if string.len(message) < 8 then return end

    -- Detect message type: immune, reflect, or evade
    local hasImmune = string.find(message, "immune")
    local hasReflect = string.find(message, "reflect")
    local hasEvade = string.find(message, "evade")

    -- ONLY process immune/reflect/evade messages - NOT resists!
    -- Resists are RNG-based and should NOT create immunity records
    if not hasImmune and not hasReflect and not hasEvade then
        return
    end

    -- Determine the miss reason type
    local missReason = nil
    if hasImmune then
        missReason = "immune"
    elseif hasReflect then
        missReason = "reflect"
    elseif hasEvade then
        missReason = "evade"
    end

    -- Debug: Show the message we're parsing
    if CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffaaaaaa[CombatLog Parse]|r [%s] %s", missReason, message))
    end

    local spellName = nil
    local targetName = nil
    local school = nil

    -- IMMUNE PATTERNS
    if hasImmune then
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
    end

    -- REFLECT PATTERNS
    if hasReflect and not targetName then
        -- Pattern 1: "Your [Spell] is reflected back by Y."
        local _, _, extractedSpell, extractedTarget = string.find(message, "Your%s+(.-)%s+is reflected back by%s+(.-)%.")
        if extractedSpell and extractedTarget then
            spellName = extractedSpell
            targetName = extractedTarget
        end

        -- Pattern 2: "Your [Spell] was reflected by Y."
        if not spellName or not targetName then
            _, _, extractedSpell, extractedTarget = string.find(message, "Your%s+(.-)%s+was reflected by%s+(.-)%.")
            if extractedSpell and extractedTarget then
                spellName = extractedSpell
                targetName = extractedTarget
            end
        end

        -- Pattern 3: "Y reflects your [Spell]."
        if not targetName then
            _, _, extractedTarget, extractedSpell = string.find(message, "^(.-)%s+reflects your%s+(.-)%.")
            if extractedTarget and extractedSpell then
                targetName = extractedTarget
                spellName = extractedSpell
            end
        end

        -- Pattern 4: "Y reflects [Spell] back at you."
        if not targetName then
            _, _, extractedTarget, extractedSpell = string.find(message, "^(.-)%s+reflects%s+(.-)%s+back")
            if extractedTarget and extractedSpell then
                targetName = extractedTarget
                spellName = extractedSpell
            end
        end
    end

    -- EVADE PATTERNS
    if hasEvade and not targetName then
        -- Pattern 1: "Your [Spell] fails. Y evades."
        local _, _, extractedSpell, extractedTarget = string.find(message, "Your%s+(.-)%s+fails%.%s+(.-)%s+evades")
        if extractedSpell and extractedTarget then
            spellName = extractedSpell
            targetName = extractedTarget
        end

        -- Pattern 2: "Your [Spell] failed. Y evades." (past tense)
        if not spellName or not targetName then
            _, _, extractedSpell, extractedTarget = string.find(message, "Your%s+(.-)%s+failed%.%s+(.-)%s+evades")
            if extractedSpell and extractedTarget then
                spellName = extractedSpell
                targetName = extractedTarget
            end
        end

        -- Pattern 3: "Y evades your [Spell]."
        if not targetName then
            _, _, extractedTarget, extractedSpell = string.find(message, "^(.-)%s+evades your%s+(.-)%.")
            if extractedTarget and extractedSpell then
                targetName = extractedTarget
                spellName = extractedSpell
            end
        end

        -- Pattern 4: "Y evades." (generic)
        if not targetName then
            _, _, extractedTarget = string.find(message, "^(.-)%s+evades")
            if extractedTarget then
                targetName = extractedTarget
            end
        end
    end

    -- STORE REASON FOR SPELL_GO CORRELATION
    -- Store the reason for ProcessMissReason to correlate with SPELL_GO events
    if targetName and lib and lib.recentCombatLogReasons then
        lib.recentCombatLogReasons[targetName] = lib.recentCombatLogReasons[targetName] or {}
        if spellName then
            lib.recentCombatLogReasons[targetName][spellName] = {
                time = GetTime(),
                reason = missReason,
            }
        else
            -- Store generic reason for target (no specific spell)
            lib.recentCombatLogReasons[targetName]["_generic"] = {
                time = GetTime(),
                reason = missReason,
            }
        end

        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cff00aaff[CombatLog Stored]|r %s -> %s (%s)",
                    spellName or "_generic", targetName, missReason)
            )
        end
    end

    -- For reflect and evade, we don't record as immunity - just return after storing reason
    if hasReflect or hasEvade then
        return
    end

    -- NOTE: Resist patterns removed - resists are RNG-based, not immunity
    -- Only "immune" messages should create immunity records

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
                -- Cancel pending verification - combat log confirmed immunity
                CancelPendingVerification(targetName, nil)
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
        -- Cancel pending verification - combat log confirmed immunity
        CancelPendingVerification(targetName, nil)
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

                -- SPLIT CC SPELLS: Skip immunity recording for spells with physical damage + resistable CC
                -- (e.g., Master Strike) - physical damage lands but CC can be resisted independently
                -- Check both spell ID and spell name (all weapon variants share the same display name)
                local baseName = string.gsub(spellName, "%s*%(.-%)%s*$", "")
                if (spellID and SPLIT_CC_SPELLS[spellID]) or SPLIT_CC_SPELL_NAMES[baseName] then
                    if CleveRoids.debug then
                        CleveRoids.Print("|cff00aaff[Split CC Skip]|r " .. spellName .. " CC immune on " .. targetName .. " - skipping immunity recording (physical damage landed)")
                    end
                    CancelPendingVerification(targetName, spellName)
                    return
                end

                -- Check if this is a CC spell - if so, record CC immunity instead
                local ccType = spellID and GetSpellCCType(spellID)
                if ccType then
                    RecordCCImmunity(targetName, ccType, singleBuff, spellName)
                else
                    RecordImmunity(targetName, spellName, singleBuff, spellID)
                end
                -- Cancel pending verification - combat log confirmed immunity
                CancelPendingVerification(targetName, spellName)
                return
            end
        end

        -- Check for immunity-granting buffs before recording permanent immunity
        -- If target has a known immunity buff (Divine Shield, Ice Block, etc.), skip recording
        local immunityBuff = nil
        if UnitExists("target") and UnitName("target") == targetName then
            immunityBuff = HasImmunityGrantingBuff("target")
        end

        if immunityBuff then
            if CleveRoids.debug then
                CleveRoids.Print("|cff00aaff[Temporary Immunity Skip]|r " .. targetName .. " has " .. immunityBuff .. " active - skipping permanent immunity recording for " .. spellName)
            end
            CancelPendingVerification(targetName, spellName)
            return
        end

        -- No immunity buff detected, record as permanent immunity
        local spellID = CleveRoids.GetSpellIdForName and CleveRoids.GetSpellIdForName(spellName)

        -- SPLIT CC SPELLS: Skip immunity recording for spells with physical damage + resistable CC
        -- (e.g., Master Strike) - physical damage lands but CC can be resisted independently
        -- Check both spell ID and spell name (all weapon variants share the same display name)
        local baseName = string.gsub(spellName, "%s*%(.-%)%s*$", "")
        if (spellID and SPLIT_CC_SPELLS[spellID]) or SPLIT_CC_SPELL_NAMES[baseName] then
            if CleveRoids.debug then
                CleveRoids.Print("|cff00aaff[Split CC Skip]|r " .. spellName .. " CC immune on " .. targetName .. " - skipping immunity recording (physical damage landed)")
            end
            CancelPendingVerification(targetName, spellName)
            return
        end

        -- Check if this is a CC spell - if so, record CC immunity instead
        local ccType = spellID and GetSpellCCType(spellID)
        if ccType then
            RecordCCImmunity(targetName, ccType, nil, spellName)
        else
            RecordImmunity(targetName, spellName, nil, spellID)
        end
        -- Cancel pending verification - combat log confirmed immunity
        CancelPendingVerification(targetName, spellName)
    end
end

-- Combat log parser for "afflicted by" messages
-- Tracks when CC effects (like Pounce stun) and bleeds successfully land
-- This confirms the effect worked and removes any false immunity records
local function ParseAfflictedCombatLog()
    local message = arg1
    if not message then return end

    -- Quick check: must contain "afflicted by"
    if not string.find(message, "afflicted by") then return end

    -- Pattern: "X is afflicted by Y" or "X is afflicted by Y (N)."
    -- Handle both with and without trailing period
    local _, _, targetName, spellName = string.find(message, "^(.-)%s+is afflicted by%s+(.+)")
    if not targetName or not spellName then return end

    -- Remove trailing period if present
    spellName = string.gsub(spellName, "%.$", "")
    -- Remove stack count like "(1)" from spell name
    spellName = string.gsub(spellName, "%s*%(%d+%)$", "")

    -- Check if this is a tracked spell (CC or bleed)
    local affliction = lib.trackedAfflictions and lib.trackedAfflictions[spellName]
    if not affliction then
        return  -- Not a tracked spell, ignore
    end

    if affliction.type == "cc" then
        -- CC effect landed - remove any false CC immunity
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cff00ff00[CC Landed]|r %s afflicted by %s (%s)",
                    targetName, spellName, affliction.value)
            )
        end
        RemoveCCImmunity(targetName, affliction.value)

        -- Mark any pending CC verification for this target/spell as verified
        -- This prevents false immunity recordings when "afflicted by" message arrives
        -- before the verification delay completes (especially for hidden CC spells)
        if lib.pendingCCDebuffs then
            for _, pending in ipairs(lib.pendingCCDebuffs) do
                if pending.targetName == targetName and
                   pending.ccType == affliction.value and
                   not pending.verifiedByAffliction then
                    pending.verifiedByAffliction = true
                    if CleveRoids.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(
                            string.format("|cff00aaff[CC Verified Early]|r %s on %s confirmed via 'afflicted by' message",
                                pending.ccType, targetName)
                        )
                    end
                    break  -- Only mark one pending entry
                end
            end
        end

    elseif affliction.type == "school" then
        -- School/bleed effect landed - remove any false school immunity
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cff00ff00[Bleed Landed]|r %s afflicted by %s (%s)",
                    targetName, spellName, affliction.value)
            )
        end
        RemoveSpellImmunity(targetName, affliction.value)

        -- Mark any pending bleed verification for this target/spell as verified
        -- This prevents false immunity recordings when target dies before verification
        -- (e.g., Rake lands, target dies at 0.1s, verification at 0.2s would miss it)
        if lib.pendingPersonalDebuffs then
            for _, pending in ipairs(lib.pendingPersonalDebuffs) do
                if pending.targetName == targetName and not pending.verifiedByAffliction then
                    -- Check if this pending entry matches the affliction spell
                    local pendingSpellName = pending.spellID and SpellInfo(pending.spellID)
                    if pendingSpellName then
                        -- Strip rank info for comparison
                        pendingSpellName = string.gsub(pendingSpellName, "%s*%(.-%)%s*$", "")
                        local afflictionSpellName = string.gsub(spellName, "%s*%(.-%)%s*$", "")
                        if string.lower(pendingSpellName) == string.lower(afflictionSpellName) then
                            pending.verifiedByAffliction = true
                            if CleveRoids.debug then
                                DEFAULT_CHAT_FRAME:AddMessage(
                                    string.format("|cff00aaff[Bleed Verified Early]|r %s on %s confirmed via 'afflicted by' message",
                                        pendingSpellName, targetName)
                                )
                            end
                            break  -- Only mark one pending entry
                        end
                    end
                end
            end
        end
    end
end

-- Check if a unit is immune to a spell, damage school, or CC type
-- Supports: CheckImmunity(unitId, "Flame Shock") or CheckImmunity(unitId, "fire") or CheckImmunity(unitId, "stun")
function CleveRoids.CheckImmunity(unitId, spellOrSchool)
    if not unitId or not UnitExists(unitId) then
        return false
    end

    if not spellOrSchool or spellOrSchool == "" then
        return false
    end

    -- Check if input is a CC type (stun, fear, root, etc.)
    local inputLower = string.lower(spellOrSchool)
    if CC_IMMUNITY_TYPES[inputLower] then
        return CheckCCImmunity(unitId, inputLower)
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
    -- Fallback to GUID->name cache if UnitName fails
    -- This happens when multiscan passes a GUID that isn't the current target
    if not targetName or targetName == "" or targetName == "Unknown" then
        local normalizedGuid = CleveRoids.NormalizeGUID(unitId)
        if normalizedGuid and lib and lib.guidToName then
            targetName = lib.guidToName[normalizedGuid]
        end
    end
    if not targetName or targetName == "" then
        return false
    end

    -- Check if input is a spell school name directly
    -- (inputLower already defined above for CC type check)
    local school = nil
    local checkSpellName = nil  -- For unknown school, we need to match spell name too

    if IMMUNITY_SCHOOLS[inputLower] then
        -- Input is a damage school name (fire, frost, nature, etc.)
        school = inputLower
    else
        -- Input is a spell name, need to determine its school
        checkSpellName = spellOrSchool  -- Save the spell name for unknown school check

        -- Get base name for split damage spell check
        local baseName = string.gsub(spellOrSchool, "%s*%(.-%)%s*$", "")

        -- SPLIT DAMAGE SPELLS: Check BOTH initial and debuff schools
        -- If target is immune to EITHER component, skip the spell
        if SPLIT_DAMAGE_SPELLS[baseName] then
            local splitData = SPLIT_DAMAGE_SPELLS[baseName]
            local initialSchool = splitData.initial
            local debuffSchool = splitData.debuff

            -- Check initial school immunity (e.g., physical for Rake's initial hit)
            local initialImmune = false
            if initialSchool and CleveRoids_ImmunityData[initialSchool] then
                local initialImmunityData = CleveRoids_ImmunityData[initialSchool][targetName]
                if initialImmunityData == true then
                    initialImmune = true
                elseif type(initialImmunityData) == "table" and not initialImmunityData.buff then
                    initialImmune = true
                elseif type(initialImmunityData) == "table" and initialImmunityData.buff then
                    -- Check if target has the immunity-granting buff
                    if CleveRoids.hasSuperwow then
                        for i = 1, 32 do
                            local texture, stacks, spellID = UnitBuff(unitId, i)
                            if not texture then break end
                            if spellID then
                                local buffName = SpellInfo(spellID)
                                if buffName and buffName == initialImmunityData.buff then
                                    initialImmune = true
                                    break
                                end
                            end
                        end
                    end
                end
            end

            -- Check debuff school immunity (e.g., bleed for Rake's DoT)
            local debuffImmune = false
            if debuffSchool and CleveRoids_ImmunityData[debuffSchool] then
                local debuffImmunityData = CleveRoids_ImmunityData[debuffSchool][targetName]
                if debuffImmunityData == true then
                    debuffImmune = true
                elseif type(debuffImmunityData) == "table" and not debuffImmunityData.buff then
                    debuffImmune = true
                elseif type(debuffImmunityData) == "table" and debuffImmunityData.buff then
                    -- Check if target has the immunity-granting buff
                    if CleveRoids.hasSuperwow then
                        for i = 1, 32 do
                            local texture, stacks, spellID = UnitBuff(unitId, i)
                            if not texture then break end
                            if spellID then
                                local buffName = SpellInfo(spellID)
                                if buffName and buffName == debuffImmunityData.buff then
                                    debuffImmune = true
                                    break
                                end
                            end
                        end
                    end
                end
            end

            -- Return true if immune to EITHER component
            if initialImmune or debuffImmune then
                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cffff6600[Immunity Check]|r %s on %s: initial(%s)=%s, debuff(%s)=%s",
                            baseName, targetName,
                            initialSchool, initialImmune and "IMMUNE" or "ok",
                            debuffSchool, debuffImmune and "IMMUNE" or "ok")
                    )
                end
                return true
            end
            return false
        end

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

-- CC IMMUNITY MANAGEMENT COMMANDS

-- List CC immunities
function CleveRoids.ListCCImmunities(ccType)
    if ccType then
        ccType = string.lower(ccType)
        local key = "cc_" .. ccType

        if not CC_IMMUNITY_TYPES[ccType] then
            CleveRoids.Print("Invalid CC type. Use: stun, fear, root, silence, sleep, charm, polymorph, banish, horror, disorient, snare")
            return
        end

        if not CleveRoids_ImmunityData[key] then
            CleveRoids.Print("No " .. ccType .. " immunity data recorded")
            return
        end

        CleveRoids.Print("|cff00ff00" .. ccType .. " immunities:|r")
        local count = 0
        for npc, data in pairs(CleveRoids_ImmunityData[key]) do
            if data == true then
                CleveRoids.Print("  - " .. npc .. " (permanent)")
            elseif type(data) == "table" and data.buff then
                CleveRoids.Print("  - " .. npc .. " (when buffed: " .. data.buff .. ")")
            end
            count = count + 1
        end
        CleveRoids.Print("Total: " .. count)
    else
        -- List all CC types
        CleveRoids.Print("|cff00ff00CC Immunity Data by Type:|r")
        local found = false
        for key, npcs in pairs(CleveRoids_ImmunityData) do
            -- Only show CC immunity keys (prefixed with "cc_")
            if string.sub(key, 1, 3) == "cc_" then
                local count = 0
                for _ in pairs(npcs) do
                    count = count + 1
                end
                if count > 0 then
                    local ccName = string.sub(key, 4)  -- Remove "cc_" prefix
                    CleveRoids.Print("  " .. ccName .. ": " .. count .. " NPCs")
                    found = true
                end
            end
        end
        if not found then
            CleveRoids.Print("  No CC immunity data recorded")
        end
    end
end

-- Clear CC immunities
function CleveRoids.ClearCCImmunities(ccType)
    if ccType then
        ccType = string.lower(ccType)
        local key = "cc_" .. ccType

        if not CC_IMMUNITY_TYPES[ccType] then
            CleveRoids.Print("Invalid CC type. Use: stun, fear, root, silence, sleep, charm, polymorph, banish, horror, disorient, snare")
            return
        end

        CleveRoids_ImmunityData[key] = {}
        CleveRoids.Print("Cleared " .. ccType .. " immunity data")
    else
        -- Clear all CC immunities (only cc_ prefixed keys)
        local cleared = 0
        for key, _ in pairs(CleveRoids_ImmunityData) do
            if string.sub(key, 1, 3) == "cc_" then
                CleveRoids_ImmunityData[key] = nil
                cleared = cleared + 1
            end
        end
        CleveRoids.Print("Cleared all CC immunity data (" .. cleared .. " types)")
    end
end

-- Manually add CC immunity
function CleveRoids.AddCCImmunity(npcName, ccType, buffName)
    if not npcName or not ccType then
        CleveRoids.Print("Usage: /cleveroid addccimmune <npc name> <cctype> [buff name]")
        CleveRoids.Print("CC Types: stun, fear, root, silence, sleep, charm, polymorph, banish, horror, disorient, snare")
        return
    end

    ccType = string.lower(ccType)
    if not CC_IMMUNITY_TYPES[ccType] then
        CleveRoids.Print("Invalid CC type. Use: stun, fear, root, silence, sleep, charm, polymorph, banish, horror, disorient, snare")
        return
    end

    local key = "cc_" .. ccType
    if not CleveRoids_ImmunityData[key] then
        CleveRoids_ImmunityData[key] = {}
    end

    if buffName and buffName ~= "" then
        CleveRoids_ImmunityData[key][npcName] = { buff = buffName }
        CleveRoids.Print("Added: " .. npcName .. " is immune to " .. ccType .. " when buffed with: " .. buffName)
    else
        CleveRoids_ImmunityData[key][npcName] = true
        CleveRoids.Print("Added: " .. npcName .. " is permanently immune to " .. ccType)
    end
end

-- Remove a CC immunity (command handler with user feedback)
-- NOTE: Do not use for automatic removal - use CleveRoids.RemoveCCImmunity instead
function CleveRoids.RemoveCCImmunityCommand(npcName, ccType)
    if not npcName or not ccType then
        CleveRoids.Print("Usage: /cleveroid removeccimmune <npc name> <cctype>")
        return
    end

    ccType = string.lower(ccType)
    local key = "cc_" .. ccType
    if CleveRoids_ImmunityData[key] and CleveRoids_ImmunityData[key][npcName] then
        CleveRoids_ImmunityData[key][npcName] = nil
        CleveRoids.Print("Removed: " .. npcName .. " from " .. ccType .. " immunities")
    else
        CleveRoids.Print("Not found: " .. npcName .. " in " .. ccType .. " immunities")
    end
end

-- Register combat log events for immunity tracking
-- PERFORMANCE: Only use RAW_COMBATLOG and SPELL_FAILURE to avoid spam from damage events
-- CHAT_MSG_SPELL_*_DAMAGE fires on EVERY hit/resist (100+ times/second in combat)
-- EXCEPTION: CHAT_MSG_SPELL_SELF_DAMAGE is needed for immunity detection (includes "is immune" messages)
-- EXCEPTION: CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE is needed for "afflicted by" detection (hidden CC spells)
local immunityFrame = CreateFrame("Frame", "CleveRoidsImmunityFrame")
immunityFrame:RegisterEvent("RAW_COMBATLOG")
immunityFrame:RegisterEvent("CHAT_MSG_SPELL_FAILURE")
immunityFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
immunityFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
immunityFrame:SetScript("OnEvent", function()
    if event == "RAW_COMBATLOG" or event == "CHAT_MSG_SPELL_FAILURE" or event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        ParseImmunityCombatLog()
    end
    -- Check for "afflicted by" messages for hidden CC spells (e.g., Pounce stun)
    -- These come through RAW_COMBATLOG and PERIODIC_CREATURE_DAMAGE
    if event == "RAW_COMBATLOG" or event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" then
        ParseAfflictedCombatLog()
    end
end)

-- REACTIVE ABILITY PROC TRACKING SYSTEM
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

-- VictimState constant for dodge detection (used by ParseReactiveCombatLog)
local VICTIMSTATE_DODGE_REACTIVE = 2

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
        -- Skip outgoing dodge patterns when SPELL_GO_SELF handles yellow attack miss detection
        if CleveRoids.usingSpellGoEvents and config.type == "enemy_dodge" then
            -- Overpower handled by SPELL_GO_SELF (hit/miss binary, no text parsing needed)
        elseif CleveRoids.reactiveSpells and CleveRoids.reactiveSpells[spellName] then
            for _, pattern in ipairs(config.patterns) do
                if strfind(message, pattern) then
                    -- Found a trigger event (works in any stance)
                    local guid = config.requiresTargetGUID and targetGUID or nil
                    local duration = config.duration or REACTIVE_PROC_DURATION
                    CleveRoids.SetReactiveProc(spellName, duration, guid)

                    -- For Overpower (enemy dodge), also update LastSwing so [lastswing:dodge] works
                    -- (Only reached when SPELL_GO is NOT available - combat log fallback)
                    if config.type == "enemy_dodge" and CleveRoids.LastSwing then
                        CleveRoids.LastSwing.timestamp = GetTime()
                        CleveRoids.LastSwing.victimState = VICTIMSTATE_DODGE_REACTIVE
                        CleveRoids.LastSwing.targetGuid = guid
                    end

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

        -- Clear reactive proc and resist state on spell cast start
        if arg1 == "player" and arg2 == "START" and arg4 then
            CleveRoids.ClearReactiveProcOnCast(arg4)
            CleveRoids.ClearResistState()
        end
    end
end

-- NAMPOWER v2.24+ AUTO_ATTACK EVENT HANDLER FOR REACTIVE ABILITIES
-- Uses native events for dodge/parry/block detection when available.
-- Falls back to combat log parsing for older Nampower versions.

-- VictimState constants (from AUTO_ATTACK / SPELL_GO events)
local VICTIMSTATE_UNAFFECTED = 0  -- Generic miss (seen with HITINFO_MISS)
local VICTIMSTATE_NORMAL = 1      -- Hit landed
local VICTIMSTATE_DODGE = 2
local VICTIMSTATE_PARRY = 3
local VICTIMSTATE_INTERRUPT = 4
local VICTIMSTATE_BLOCKS = 5
local VICTIMSTATE_EVADES = 6
local VICTIMSTATE_IS_IMMUNE = 7
local VICTIMSTATE_DEFLECTS = 8

-- HitInfo constant for SPELL_GO miss tracking
local HITINFO_MISS = 16  -- 0x10

-- Track if we're using Nampower events (set during initialization)
CleveRoids.usingNampowerAutoAttack = false

-- Process AUTO_ATTACK events for reactive ability procs
-- Parameters: attackerGuid, targetGuid, totalDamage, hitInfo, victimState, ...
function CleveRoids.ProcessAutoAttackEvent(isPlayerAttacker, attackerGuid, targetGuid, totalDamage, hitInfo, victimState)
    -- Get player GUID for comparison
    local _, playerGUID = UnitExists("player")
    if not playerGUID then return end

    -- Determine current target GUID
    local _, currentTargetGUID = UnitExists("target")

    -- ========================================================================
    -- OVERPOWER: Enemy dodges YOUR attack
    -- ========================================================================
    if isPlayerAttacker and victimState == VICTIMSTATE_DODGE then
        -- Enemy dodged our attack - Overpower proc
        -- Note: We skip the hasSpell check since CleveRoids.GetSpell requires spellbook to be indexed,
        -- which may not happen immediately on load. If player uses [reactive:Overpower], they have the spell.
        if CleveRoids.reactiveSpells and CleveRoids.reactiveSpells["Overpower"] then
            -- Overpower requires targeting the mob that dodged
            CleveRoids.SetReactiveProc("Overpower", 4.0, targetGuid)
            CleveRoids.QueueActionUpdate()

            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cff00ff00[AUTO_ATTACK]|r Overpower proc - enemy dodged (victimState=%d)",
                        victimState)
                )
            end
        end
    end

    -- ========================================================================
    -- RIPOSTE: YOU parry an enemy attack
    -- ========================================================================
    if not isPlayerAttacker and targetGuid == playerGUID and victimState == VICTIMSTATE_PARRY then
        -- We parried an enemy attack - Riposte proc
        if CleveRoids.reactiveSpells and CleveRoids.reactiveSpells["Riposte"] then
            -- Riposte requires targeting the mob we parried
            CleveRoids.SetReactiveProc("Riposte", 4.0, attackerGuid)
            CleveRoids.QueueActionUpdate()

            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cff00ff00[AUTO_ATTACK]|r Riposte proc - player parried (victimState=%d)",
                        victimState)
                )
            end
        end
    end

    -- ========================================================================
    -- REVENGE: YOU block, dodge, or parry an enemy attack
    -- ========================================================================
    if not isPlayerAttacker and targetGuid == playerGUID then
        local isAvoidance = (victimState == VICTIMSTATE_DODGE or
                            victimState == VICTIMSTATE_PARRY or
                            victimState == VICTIMSTATE_BLOCKS)
        if isAvoidance then
            if CleveRoids.reactiveSpells and CleveRoids.reactiveSpells["Revenge"] then
                -- Revenge can be used on any target once procced
                CleveRoids.SetReactiveProc("Revenge", 4.0, nil)
                CleveRoids.QueueActionUpdate()

                if CleveRoids.debug then
                    local avoidType = victimState == VICTIMSTATE_DODGE and "dodge" or
                                     (victimState == VICTIMSTATE_PARRY and "parry" or "block")
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cff00ff00[AUTO_ATTACK]|r Revenge proc - player %s (victimState=%d)",
                            avoidType, victimState)
                    )
                end
            end
        end
    end
end

-- Register combat log event for reactive proc tracking (FALLBACK)
-- CHAT_MSG_SPELL_SELF_DAMAGE is needed for yellow ability dodge/parry/block detection
-- (e.g., "Your Mortal Strike was dodged by Target.") - only auto-attack dodges come through COMBAT_SELF_MISSES
-- CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS is needed for partial block detection (Revenge)
local reactiveFrame = CreateFrame("Frame", "CleveRoidsReactiveFrame")

-- Check for Nampower v2.24+ AUTO_ATTACK events
local hasAutoAttackEvents = false
if GetNampowerVersion then
    local npMajor, npMinor = GetNampowerVersion()
    if npMajor > 2 or (npMajor == 2 and npMinor >= 24) then
        hasAutoAttackEvents = true
        CleveRoids.usingNampowerAutoAttack = true

        -- Auto-enable the CVar required for AUTO_ATTACK events
        -- This is persistent, so only set if not already enabled
        if GetCVar and SetCVar then
            local currentValue = GetCVar("NP_EnableAutoAttackEvents")
            if currentValue ~= "1" then
                SetCVar("NP_EnableAutoAttackEvents", "1")
                -- Note: CVar takes effect on next login/reload, but we register anyway
            end
        end

        reactiveFrame:RegisterEvent("AUTO_ATTACK_SELF")
        reactiveFrame:RegisterEvent("AUTO_ATTACK_OTHER")

        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Nampower]|r Using AUTO_ATTACK events for reactive abilities (v2.24+)")
        end
    end
end

-- Check for Nampower v2.25+ SPELL_GO events (replaces combat log for yellow attack miss detection)
local hasSpellGoEvents = false
if GetNampowerVersion then
    local npMajor, npMinor = GetNampowerVersion()
    if npMajor > 2 or (npMajor == 2 and npMinor >= 25) then
        hasSpellGoEvents = true
        CleveRoids.usingSpellGoEvents = true

        reactiveFrame:RegisterEvent("SPELL_GO_SELF")

        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Nampower]|r Using SPELL_GO events for yellow attack miss detection (v2.25+)")
        end
    end
end

-- Register combat log events for reactive abilities
-- When SPELL_GO + AUTO_ATTACK are both available, outgoing dodges are handled natively;
-- combat log only needed for incoming avoidance (Riposte/Revenge from enemy abilities)
if hasAutoAttackEvents and hasSpellGoEvents then
    reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
    reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
else
    -- Full combat log fallback
    reactiveFrame:RegisterEvent("RAW_COMBATLOG")
    reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
    reactiveFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
    reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
    reactiveFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
end

reactiveFrame:SetScript("OnEvent", function()
    -- ========================================================================
    -- NAMPOWER v2.24+ AUTO_ATTACK EVENTS (preferred when available)
    -- ========================================================================
    if event == "AUTO_ATTACK_SELF" then
        -- Player is the TARGET of an attack
        -- Parameters: attackerGuid, targetGuid, totalDamage, hitInfo, victimState, ...
        local attackerGuid = arg1
        local targetGuid = arg2
        local totalDamage = arg3
        local hitInfo = arg4
        local victimState = arg5

        CleveRoids.ProcessAutoAttackEvent(false, attackerGuid, targetGuid, totalDamage, hitInfo, victimState)
        return  -- Handled by Nampower, skip combat log parsing
    end

    if event == "AUTO_ATTACK_OTHER" then
        -- Player is the ATTACKER (or watching other units)
        local attackerGuid = arg1
        local targetGuid = arg2
        local totalDamage = arg3
        local hitInfo = arg4
        local victimState = arg5

        -- Check if player is the attacker
        local _, playerGUID = UnitExists("player")
        local isPlayerAttacker = (attackerGuid == playerGUID)

        CleveRoids.ProcessAutoAttackEvent(isPlayerAttacker, attackerGuid, targetGuid, totalDamage, hitInfo, victimState)
        return  -- Handled by Nampower, skip combat log parsing
    end

    -- ========================================================================
    -- NAMPOWER v2.25+ SPELL_GO EVENTS (yellow attack hit/miss detection)
    -- ========================================================================
    -- Two-step: SPELL_CAST_EVENT (success=1) → SPELL_GO_SELF (hit/miss outcome)
    -- Replaces combat log text parsing for outgoing yellow ability misses.
    -- SPELL_GO_SELF params: itemId, spellId, casterGuid, targetGuid, castFlags, numTargetsHit, numTargetsMissed
    if event == "SPELL_GO_SELF" then
        local spellId = arg2
        local targetGuid = arg4
        local numHit = arg6 or 0
        local numMissed = arg7 or 0

        -- Step 1: Validate against SPELL_CAST_EVENT (confirms player-initiated, successful cast)
        local pending = CleveRoids.pendingCasts and CleveRoids.pendingCasts[spellId]
        if not pending then
            return  -- No matching SPELL_CAST_EVENT with success=1, skip
        end

        -- Clear the pending cast (consumed)
        CleveRoids.pendingCasts[spellId] = nil

        -- Skip channels and targeting spells (not melee/ranged attacks)
        -- CastType: NORMAL=1, NON_GCD=2, ON_SWING=3, CHANNEL=4, TARGETING=5, TARGETING_NON_GCD=6
        if pending.castType and pending.castType >= 4 then
            return
        end

        -- Step 2: Check hit/miss outcome - binary check covers dodge, parry, resist, etc.
        if numMissed >= 1 and numHit == 0 then
            -- Use current target GUID if SPELL_GO targetGuid is empty
            local procTarget = targetGuid
            if not procTarget or procTarget == "0x0000000000000000" then
                procTarget = pending.targetGuid
                if not procTarget or procTarget == "0x0000000000000000" then
                    local _, currentTargetGUID = UnitExists("target")
                    procTarget = currentTargetGUID
                end
            end

            -- Overpower: enemy avoided our yellow attack
            if CleveRoids.reactiveSpells and CleveRoids.reactiveSpells["Overpower"] then
                CleveRoids.SetReactiveProc("Overpower", 4.0, procTarget)
                CleveRoids.QueueActionUpdate()

                if CleveRoids.debug then
                    local spellName = SpellInfo and SpellInfo(spellId) or tostring(spellId)
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cff00ff00[SPELL_GO]|r Overpower proc - %s missed (hit=%d, miss=%d, castType=%s)",
                            spellName, numHit, numMissed, tostring(pending.castType))
                    )
                end
            end

            -- Update LastSwing for yellow miss (victimState unknown from SPELL_GO, use UNAFFECTED)
            -- Don't overwrite AUTO_ATTACK data from the same frame (on-swing abilities fire both)
            if CleveRoids.LastSwing and CleveRoids.LastSwing.timestamp ~= GetTime() then
                CleveRoids.LastSwing.timestamp = GetTime()
                CleveRoids.LastSwing.hitInfo = HITINFO_MISS
                CleveRoids.LastSwing.victimState = VICTIMSTATE_UNAFFECTED
                CleveRoids.LastSwing.damage = 0
                CleveRoids.LastSwing.blockedAmount = 0
                CleveRoids.LastSwing.absorbAmount = 0
                CleveRoids.LastSwing.resistAmount = 0
                CleveRoids.LastSwing.targetGuid = procTarget
            end
        end

        return
    end

    -- ========================================================================
    -- COMBAT LOG FALLBACK FOR REACTIVE ABILITIES
    -- ========================================================================
    -- Only used for incoming avoidance (Riposte/Revenge) from enemy abilities.
    -- Outgoing dodges handled by SPELL_GO_SELF (v2.25+) or AUTO_ATTACK (white swings).
    if event == "RAW_COMBATLOG" or
       event == "CHAT_MSG_COMBAT_SELF_MISSES" or
       event == "CHAT_MSG_SPELL_SELF_DAMAGE" or
       event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" or
       event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS" then
        CleveRoids.ParseReactiveCombatLog()
    end
end)

-- RESIST TRACKING SYSTEM
-- Tracks full and partial spell resists for [resisted] and [noresisted] conditionals

-- Set resist state with target GUID matching
function CleveRoids.SetResistState(resistType, targetGUID)
    CleveRoids.resistState = {
        resistType = resistType,
        targetGUID = targetGUID
    }
    CleveRoids.QueueActionUpdate()

    if CleveRoids.debug then
        local targetName = UnitName("target") or "Unknown"
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff6600[Resist Track]|r %s resist on %s",
                string.upper(resistType), targetName)
        )
    end
end

-- Clear resist state
function CleveRoids.ClearResistState()
    if CleveRoids.resistState then
        CleveRoids.resistState = nil
        CleveRoids.QueueActionUpdate()
    end
end

-- Check resist state (used by conditionals)
-- Returns true if resist matches the type AND current target matches the GUID
function CleveRoids.CheckResistState(resistType)
    local state = CleveRoids.resistState
    if not state then return false end

    -- Must have current target that matches the GUID from resist event
    local _, currentTargetGUID = UnitExists("target")
    if not currentTargetGUID or currentTargetGUID ~= state.targetGUID then
        return false
    end

    -- If no specific type requested, any resist matches
    if not resistType or resistType == "" then
        return true
    end

    -- Check specific resist type
    return state.resistType == string.lower(resistType)
end

-- Parse combat log for resist messages
local function ParseResistCombatLog()
    local message = arg1      -- Formatted message (localized)

    if not message then return end

    -- PERFORMANCE: Quick length check (minimum resist message ~15 chars)
    if string.len(message) < 15 then return end

    -- PERFORMANCE: Quick keyword check before expensive pattern matching
    local lowerMsg = string.lower(message)
    if not string.find(lowerMsg, "resist") then return end

    -- Get current target info for matching
    local _, targetGUID = UnitExists("target")
    if not targetGUID then return end

    local targetName = UnitName("target")
    if not targetName then return end

    -- Verify the resist was against current target by checking if target name appears in message
    if not string.find(message, targetName, 1, true) then
        -- Target name not found in message - resist was against different mob
        return
    end

    -- Detect partial resist: "Your X hit Y for Z. (N resisted)"
    -- Key pattern: "resisted)" with closing parenthesis indicates damage was dealt
    local isPartial = string.find(message, "resisted%)")

    -- Detect full resist patterns:
    -- Pattern 1: "Your X was resisted by Y."
    -- Pattern 2: "Y resists your X."
    local isFull = false
    if not isPartial then
        if string.find(message, "was resisted by") or string.find(message, "resists your") then
            isFull = true
        end
    end

    -- Set resist state based on type detected
    if isPartial then
        CleveRoids.SetResistState("partial", targetGUID)
    elseif isFull then
        CleveRoids.SetResistState("full", targetGUID)
    end
end

-- UNIFIED COMBAT LOG DISPATCHER
-- Consolidates all RAW_COMBATLOG handling into a single frame for performance.
-- Previously, 4 separate frames were each parsing the same combat log events.
-- This single dispatcher calls all parsing functions once per event.
--
-- Functions called:
--   1. HandleDebuffFade() - Learn debuff durations when they fade
--   2. ParseImmunityCombatLog() - Immune/reflect/evade detection
--   3. ParseAfflictedCombatLog() - "afflicted by" detection for hidden CC
--   4. ParseReactiveCombatLog() - Reactive ability procs (fallback when no Nampower)
--   5. ParseResistCombatLog() - Resist tracking

-- Helper function for debuff fade learning and cleanup (extracted from evLearn)
-- Handles "X fades from Y" messages in RAW_COMBATLOG
local function HandleDebuffFade()
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
          -- Learn duration if we have timing data
          if lib.learnCastTimers[targetGUID] and
             lib.learnCastTimers[targetGUID][spellID] then

            local castTime = lib.learnCastTimers[targetGUID][spellID].start
            local casterGUID = lib.learnCastTimers[targetGUID][spellID].caster
            local actualDuration = timestamp - castTime

            -- Check if this is a combo point spell
            local comboPoints = lib.learnCastTimers[targetGUID][spellID].comboPoints
            if comboPoints and CleveRoids.IsComboScalingSpellID and CleveRoids.IsComboScalingSpellID(spellID) then
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
            if lib.learnCastTimers[targetGUID] and not next(lib.learnCastTimers[targetGUID]) then
              lib.learnCastTimers[targetGUID] = nil
            end
          end

          -- Cleanup logic for personal vs shared debuffs
          local rec = lib.objects[targetGUID][spellID]
          local isPersonal = lib:IsPersonalDebuff(spellID)
          local shouldRemove = false

          if isPersonal then
            -- Personal debuff: only remove if cast by player
            if rec.caster == "player" then
              local hasExpired = (rec.start + rec.duration + 1) <= timestamp
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
              if (hasExpired and not stillExists) or ((rec.start + rec.duration + 2) <= timestamp) then
                shouldRemove = true
              end
            end
          else
            -- Shared debuff: scan to verify it's gone
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
            if not stillExists or ((rec.start + rec.duration + 2) <= timestamp) then
              shouldRemove = true
            end
          end

          if shouldRemove then
            lib.objects[targetGUID][spellID] = nil
          end

          if not next(lib.objects[targetGUID]) then
            lib.objects[targetGUID] = nil
          end
          return
        end
      end
    end
end

-- Unified combat log frame - processes RAW_COMBATLOG ONCE and dispatches to all handlers
local unifiedCombatLogFrame = CreateFrame("Frame", "CleveRoidsUnifiedCombatLogFrame")
unifiedCombatLogFrame:RegisterEvent("RAW_COMBATLOG")
unifiedCombatLogFrame:SetScript("OnEvent", function()
    if event ~= "RAW_COMBATLOG" then return end

    -- 1. Debuff fade learning (for duration auto-learning)
    HandleDebuffFade()

    -- 2. Immunity detection (immune/reflect/evade from combat log)
    ParseImmunityCombatLog()

    -- 3. "Afflicted by" detection for hidden CC (e.g., Pounce stun)
    ParseAfflictedCombatLog()

    -- 4. Reactive ability procs (always run - AUTO_ATTACK events only cover white swings,
    --    yellow ability dodges like Mortal Strike/Heroic Strike come through combat log)
    CleveRoids.ParseReactiveCombatLog()

    -- 5. Resist tracking
    ParseResistCombatLog()
end)
