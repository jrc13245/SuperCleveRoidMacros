--[[
  UltimaMacros compatibility shim for CleveRoidMacros (1.12.1-safe)
  - Installs only when BOTH UltimaMacros and SuperCleveRoidMacros are loaded
  - Hooks UltimaMacros' UM_RunLine to intercept CRM-owned slash commands
  - Clears CRM stop flags at macro start
  - Enables #showtooltip dynamic icon support for UltimaMacros
]]

do
  local _G = _G or getfenv(0)
  local CRM = _G.CleveRoids or {}
  _G.CleveRoids = CRM
  CRM.Hooks = CRM.Hooks or {}

  -- Commands owned by CRM (same as SuperMacro.lua)
  local INTERCEPT = {
    cast=true, castsequence=true, use=true,
    startattack=true, stopattack=true, stopcasting=true, stopmacro=true,
    skipmacro=true, firstaction=true, nofirstaction=true,
    target=true, retarget=true, cancelaura=true, unbuff=true,
    unqueue=true, unshift=true, equip=true, equipmh=true, equipoh=true,
    petattack=true, petfollow=true, petpassive=true,
    petaggressive=true, petdefensive=true, petwait=true,
    quickheal=true, qh=true,
    castpet=true, cleartarget=true,
    applymain=true, applyoff=true,
    ["equip11"]=true, ["equip12"]=true, ["equip13"]=true, ["equip14"]=true,
  }

  local ALIASES = { unbuff = "cancelaura" }

  local function has_handler(cmd)
    local list = _G.SlashCmdList
    return cmd and list and type(list[string.upper(cmd)]) == "function"
  end

  local function install_ultimamacros_hook()
    if CRM.UM_RunLineHooked then return end
    if type(_G.UM_RunLine) ~= "function" then return end

    local orig_RunLine = _G.UM_RunLine
    CRM.Hooks.UM_RunLine = orig_RunLine

    _G.UM_RunLine = function(line)
      if type(line) ~= "string" then
        return orig_RunLine(line)
      end

      -- Skip comment lines
      if string.find(line, "^%s*%-%-") then
        return orig_RunLine(line)
      end

      -- Skip #showtooltip lines (don't execute, just for icon)
      if string.find(line, "^%s*#") then
        return
      end

      -- Handle /nofirstaction BEFORE stop flag check
      local _, _, nofirstactionArgs = string.find(line, "^%s*/nofirstaction%s*(.*)")
      if nofirstactionArgs then
        local wasFirstActionActive = CRM.stopOnCastFlag
        if type(CleveRoids.DoNoFirstAction) == "function" then
          pcall(CleveRoids.DoNoFirstAction, nofirstactionArgs or "")
        end
        if wasFirstActionActive and CRM.stopMacroFlag then
          CRM.stopMacroFlag = false
        end
        return
      end

      -- Check macro stop flags
      if CRM.stopMacroFlag or CRM.skipMacroFlag then
        return
      end

      -- Handle /castsequence
      local _, _, csRest = string.find(line, "^%s*/castsequence%s*(.*)")
      if csRest then
        if type(CleveRoids.DoCastSequence) == "function" then
          pcall(CleveRoids.DoCastSequence, csRest or "")
          return
        end
        local fn = _G.SlashCmdList and _G.SlashCmdList["CASTSEQUENCE"]
        if type(fn) == "function" then
          pcall(fn, csRest or "")
          return
        end
      end

      -- Generic /cmd forwarding
      local _, _, raw, msg = string.find(line, "^%s*/(%S+)%s*(.*)$")
      if raw then
        local cmd = string.lower(raw)
        if cmd == "unbuff" then cmd = "cancelaura" end
        if INTERCEPT[cmd] and has_handler(cmd) then
          pcall(_G.SlashCmdList[string.upper(cmd)], msg or "")
          return
        end
      end

      -- Fast-path for extended/bracket tokens
      local hooks = { cast = CRM.DoCast, target = CRM.DoTarget, use = CRM.DoUse }
      for k, fn in pairs(hooks) do
        if type(fn) == "function" then
          local b2, e2 = string.find(line, "^%s*/" .. k .. "%s+[!%[%{%?~]")
          if b2 then
            local msg2 = string.gsub(string.sub(line, e2), "^%s+", "")
            pcall(fn, msg2)
            return
          end
        end
      end

      -- Not handled by CRM: let UltimaMacros do its normal processing
      return orig_RunLine(line)
    end

    CRM.UM_RunLineHooked = true

    -- Hook UM_Run to clear stop flags at macro start
    if type(_G.UM_Run) == "function" then
      local orig_UM_Run = _G.UM_Run
      CRM.Hooks.UM_Run = orig_UM_Run

      _G.UM_Run = function(name)
        -- Clear ALL macro stop flags at macro start
        CRM.stopMacroFlag = false
        CRM.skipMacroFlag = false
        CRM.stopOnCastFlag = false
        return orig_UM_Run(name)
      end
    end

    -- Register for dynamic icon updates (modifier keys, target changes, etc.)
    if CRM.RegisterActionEventHandler then
      CRM.RegisterActionEventHandler(function(slot, event)
        -- Trigger button update for UltimaMacros slots
        if _G.UM_GetMappedName and _G.UM_RefreshActionButtonsForSlot then
          local name = _G.UM_GetMappedName(slot)
          if name then
            _G.UM_RefreshActionButtonsForSlot(slot)
          end
        end
      end)
    end
  end

  -- Order-agnostic loader
  local UM_LOADED, CRM_LOADED = false, false
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:RegisterEvent("PLAYER_LOGIN")

  local function note_loaded(name)
    if name == "UltimaMacros" then
      UM_LOADED = true
    elseif name == "SuperCleveRoidMacros" or name == "CleveRoidMacros" then
      CRM_LOADED = true
    end
  end

  local function both_loaded()
    if UM_LOADED and CRM_LOADED then return true end
    -- Heuristic fallback
    local um_ok = type(_G.UM_Run) == "function" and type(_G.UM_RunLine) == "function"
    local crm_ok = _G.CleveRoids and _G.SlashCmdList and type(_G.SlashCmdList.CAST) == "function"
    return um_ok and crm_ok
  end

  local function try_install()
    if both_loaded() then install_ultimamacros_hook() end
  end

  f:SetScript("OnEvent", function()
    local evt = event
    local addon = arg1
    if evt == "ADDON_LOADED" then
      if type(addon) == "string" then note_loaded(addon) end
      try_install()
    elseif evt == "PLAYER_LOGIN" then
      try_install()
    end
  end)
end
