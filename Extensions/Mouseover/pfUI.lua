--[[
  Author: Dennis Werner Garske (DWG) / brian / Mewtiny
  License: MIT License

  Fixes pfUI mouseover issues by:
  - Using a unique source key per pfUI frame (e.g., "pfui:party3", "pfui:raid7")
  - Pairing Set/Clear with the same per-frame key
  - Resolving a real UnitID when .unit isn't set
  - Properly hooking party group[0] (your own party slot) with a safe closure and defaulting to "player"
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

CleveRoids.mouseoverUnit = CleveRoids.mouseoverUnit or nil

local Extension = CleveRoids.RegisterExtension("pfUI")
Extension.RegisterEvent("PLAYER_ENTERING_WORLD", "PLAYER_ENTERING_WORLD")

function Extension.OnLoad()
end

-- Resolve a pfUI unitframe (focus / focustarget and fallback for party/raid)
local function ResolvePfUnit(frame, fallbackName)
  if not frame then return nil end
  if frame.label and frame.id then
    return frame.label .. frame.id
  end

  local name = fallbackName or frame.unitname
  if not name or name == "" then return nil end
  name = strlower(name)

  local candidates = { "target", "targettarget", "player", "pet" }
  local i
  for i = 1, 4 do
    table.insert(candidates, "party"..i)
    table.insert(candidates, "partypet"..i)
  end
  for i = 1, 40 do
    table.insert(candidates, "raid"..i)
    table.insert(candidates, "raidpet"..i)
  end

  for _,u in ipairs(candidates) do
    if UnitExists(u) and strlower(UnitName(u) or "") == name then
      return u
    end
  end

  return nil
end

-- Unique key per pfUI frame so leave events can't clear another frame's hover
local function PfSourceKey(frame)
  if not frame then return "pfui:unknown" end
  if frame.label and frame.id then
    return "pfui:" .. frame.label .. frame.id
  end
  if frame.unit and frame.unit ~= "" then
    return "pfui:" .. frame.unit
  end
  return "pfui:" .. tostring(frame) -- stable per-frame string in 1.12
end

-- Resolve a *real* UnitID for a pfUI frame
local function PfResolveUnit(frame, defaultUnit)
  if frame and frame.unit and frame.unit ~= "" then
    return frame.unit
  end
  if frame and frame.label and frame.id then
    return frame.label .. frame.id
  end
  return ResolvePfUnit(frame) or defaultUnit
end

-- Helper to set with per-frame key
local function PfSet(frame, defaultUnit)
  local key  = PfSourceKey(frame)
  local unit = PfResolveUnit(frame, defaultUnit)
  if unit then
    frame.__cr_src = key
    CleveRoids.SetMouseoverFrom(key, unit)
  end
end

-- Helper to clear with the same per-frame key
local function PfClear(frame)
  if frame and frame.__cr_src then
    CleveRoids.ClearMouseoverFrom(frame.__cr_src)
    frame.__cr_src = nil
  end
end

-- PLAYER
function Extension.RegisterPlayerScripts()
  if not pfUI or not pfUI.uf or not pfUI.uf.player then return end
  local frame = pfUI.uf.player
  local onEnterFunc = frame:GetScript("OnEnter")
  local onLeaveFunc = frame:GetScript("OnLeave")

  frame:SetScript("OnEnter", function()
    PfSet(this, "player")
    if onEnterFunc then onEnterFunc(this) end
  end)

  frame:SetScript("OnLeave", function()
    PfClear(this)
    if onLeaveFunc then onLeaveFunc(this) end
  end)
end

-- TARGET
function Extension.RegisterTargetScripts()
  if not pfUI or not pfUI.uf or not pfUI.uf.target then return end
  local frame = pfUI.uf.target
  local onEnterFunc = frame:GetScript("OnEnter")
  local onLeaveFunc = frame:GetScript("OnLeave")

  frame:SetScript("OnEnter", function()
    PfSet(this, "target")
    if onEnterFunc then onEnterFunc(this) end
  end)

  frame:SetScript("OnLeave", function()
    PfClear(this)
    if onLeaveFunc then onLeaveFunc(this) end
  end)
end

-- TARGETTARGET
function Extension.RegisterTargetTargetScripts()
  if not pfUI or not pfUI.uf or not pfUI.uf.targettarget then return end
  local frame = pfUI.uf.targettarget
  local onEnterFunc = frame:GetScript("OnEnter")
  local onLeaveFunc = frame:GetScript("OnLeave")

  frame:SetScript("OnEnter", function()
    PfSet(this, "targettarget")
    if onEnterFunc then onEnterFunc(this) end
  end)

  frame:SetScript("OnLeave", function()
    PfClear(this)
    if onLeaveFunc then onLeaveFunc(this) end
  end)
end

-- PARTY (pfUI.uf.group[0..4])  -- include 0 to cover your own party slot
function Extension.RegisterPartyScripts()
  if not pfUI or not pfUI.uf or not pfUI.uf.group then return end

  local i
  for i = 0, 4 do
    local frame = pfUI.uf.group[i]
    if frame then
      -- bind loop index for closures (Vanilla-safe)
      local idx = i
      local onEnterFunc = frame:GetScript("OnEnter")
      local onLeaveFunc = frame:GetScript("OnLeave")

      frame:SetScript("OnEnter", function()
        -- For group[0] (your own party frame), default to "player"
        local defaultUnit = (idx == 0) and "player" or nil
        PfSet(this, defaultUnit)
        if onEnterFunc then onEnterFunc(this) end
      end)

      frame:SetScript("OnLeave", function()
        PfClear(this)
        if onLeaveFunc then onLeaveFunc(this) end
      end)
    end
  end
end

-- RAID (pfUI.uf.raid[1..40])
function Extension.RegisterRaidScripts()
  if not pfUI or not pfUI.uf or not pfUI.uf.raid then return end

  local i
  for i = 1, 40 do
    local frame = pfUI.uf.raid[i]
    if frame then
      local onEnterFunc = frame:GetScript("OnEnter")
      local onLeaveFunc = frame:GetScript("OnLeave")

      frame:SetScript("OnEnter", function()
        PfSet(this)
        if onEnterFunc then onEnterFunc(this) end
      end)

      frame:SetScript("OnLeave", function()
        PfClear(this)
        if onLeaveFunc then onLeaveFunc(this) end
      end)
    end
  end
end

-- FOCUS
function Extension.RegisterFocusScripts()
  if not pfUI or not pfUI.uf or not pfUI.uf.focus then return end
  local frame = pfUI.uf.focus
  local onEnterFunc = frame:GetScript("OnEnter")
  local onLeaveFunc = frame:GetScript("OnLeave")

  frame:SetScript("OnEnter", function()
    PfSet(this) -- ResolvePfUnit handles focus emulation
    if onEnterFunc then onEnterFunc(this) end
  end)

  frame:SetScript("OnLeave", function()
    PfClear(this)
    if onLeaveFunc then onLeaveFunc(this) end
  end)
end

-- FOCUSTARGET (if your pfUI build provides it)
function Extension.RegisterFocusTargetScripts()
  if not pfUI or not pfUI.uf or not pfUI.uf.focustarget then return end
  local frame = pfUI.uf.focustarget
  local onEnterFunc = frame:GetScript("OnEnter")
  local onLeaveFunc = frame:GetScript("OnLeave")

  frame:SetScript("OnEnter", function()
    PfSet(this)
    if onEnterFunc then onEnterFunc(this) end
  end)

  frame:SetScript("OnLeave", function()
    PfClear(this)
    if onLeaveFunc then onLeaveFunc(this) end
  end)
end

-- PARTYTARGET (party1target..party4target, plus player's target)
function Extension.RegisterPartyTargetScripts()
  if not pfUI or not pfUI.uf then return end

  -- This helper function is used to hook any given frame.
  local function hookFrame(frame, defaultUnit)
    if not frame then return end
    local onEnterFunc = frame:GetScript("OnEnter")
    local onLeaveFunc = frame:GetScript("OnLeave")

    frame:SetScript("OnEnter", function()
      PfSet(this, defaultUnit)
      -- We remove the call to the original onEnterFunc to prevent overwritten tooltips.
    end)

    frame:SetScript("OnLeave", function()
      PfClear(this)
      if onLeaveFunc then onLeaveFunc(this) end
    end)
  end

  -- This helper function is specifically for party member targets (1-4)
  local function hookPartyMemberTarget(i, frame)
    if not frame then return end
    local defaultUnit = "party" .. i .. "target"
    hookFrame(frame, defaultUnit)
  end

  -- Case A: Hook dedicated arrays for party members 1-4
  if pfUI.uf.grouptarget then
    for i = 1, 4 do hookPartyMemberTarget(i, pfUI.uf.grouptarget[i]) end
  end
  if pfUI.uf.partytarget then
    for i = 1, 4 do hookPartyMemberTarget(i, pfUI.uf.partytarget[i]) end
  end

  -- Case B: Hook child target frames for party members 1-4
  if pfUI.uf.group then
    for i = 1, 4 do
      local g = pfUI.uf.group[i]
      if g and g.target then hookPartyMemberTarget(i, g.target) end
    end
  end

  --- START OF FIX to include party0target ---
  -- Case C: Specifically find and hook the player's own target frame (group[0].target)
  if pfUI.uf.group and pfUI.uf.group[0] and pfUI.uf.group[0].target then
    -- The player's target UnitID is always "target", not "party0target".
    hookFrame(pfUI.uf.group[0].target, "target")
  end
  --- END OF FIX ---
end

function Extension.PLAYER_ENTERING_WORLD()
  if not pfUI or not pfUI.uf then return end
  Extension.RegisterPlayerScripts()
  Extension.RegisterTargetScripts()
  Extension.RegisterTargetTargetScripts()
  Extension.RegisterPartyScripts()
  Extension.RegisterPartyTargetScripts()
  Extension.RegisterRaidScripts()
  Extension.RegisterFocusScripts()
  Extension.RegisterFocusTargetScripts()
end
