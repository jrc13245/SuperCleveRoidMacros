--[[
  SuperMacro compatibility shim for CleveRoidMacros (1.12.1-safe)
  - Installs only when BOTH SuperMacro and SuperCleveRoidMacros/CleveRoidMacros are loaded
  - Hooks SuperMacro's RunLine order-agnostically (ADDON_LOADED + PLAYER_LOGIN)
  - Intercepts CRM-owned slashcommands (including {…}, […], !, ?, ~)
  - Forwards to CRM's SlashCmdList handlers; preserves /castsequence
  - Leaves SuperMacro unmodified; safe fallback to original RunLine
  - Redirects global RunMacro to SuperMacro_RunMacro so RunLine hook can intercept
]]

do
  local _G  = _G or getfenv(0)
  local CRM = _G.CleveRoids or {}
  _G.CleveRoids = CRM
  CRM.Hooks = CRM.Hooks or {}

  -- Commands owned by CRM (keep in sync with Console.lua registrations)
  -- NOTE: /runmacro is NOT intercepted here - we let SuperMacro's RunLine handle it
  -- naturally via SuperMacro_RunMacro. This avoids conflicts with SuperMacro's keybinding system.
  local INTERCEPT = {
    cast=true, castsequence=true, use=true,
    startattack=true, stopattack=true, stopcasting=true, stopmacro=true,
    skipmacro=true, firstaction=true, nofirstaction=true,
    target=true, retarget=true, cancelaura=true, unbuff=true,
    unqueue=true, unshift=true, equip=true, equipmh=true, equipoh=true,
    -- runmacro intentionally NOT included - see note above
    -- pet
    petattack=true, petfollow=true, petpassive=true,
    petaggressive=true, petdefensive=true, petwait=true,
    -- healing (requires QuickHeal addon)
    quickheal=true, qh=true,
  }

  -- alias map (if CRM only registers /cancelaura, but /unbuff appears)
  local ALIASES = { unbuff = "cancelaura" }

  local function normalize_cmd(cmd)
    if not cmd or cmd == "" then return nil end
    local _, _, s = string.find(cmd, "^(.*)$")
    s = s and string.lower(s) or nil
    if s and ALIASES[s] then s = ALIASES[s] end
    return s
  end

  local function has_handler(cmd)
    local list = _G.SlashCmdList
    return cmd and list and type(list[string.upper(cmd)]) == "function"
  end

  local function parse_slash(text)
    if type(text) ~= "string" then return nil, nil end
    text = (string.gsub(text, "^[%s]+", ""))
    if not string.find(text, "^/") then return nil, nil end
    local _, _, cmd, rest = string.find(text, "^/(%S+)%s*(.*)$")
    return cmd, rest
  end

  local function install_supermacro_hook()
    if CRM.SM_RunLineHooked then return end
    if type(_G.RunLine) ~= "function" then return end

    local orig_RunLine = _G.RunLine
    CRM.Hooks.RunLine = CRM.Hooks.RunLine or orig_RunLine

    _G.RunLine = function(...)
      -- Check macro stop flags before processing any line
      if CRM.stopMacroFlag or CRM.skipMacroFlag then
        return true  -- Skip this line, tell SM we handled it
      end

      -- SuperMacro calls RunLine(line) one line at a time; handle first arg.
      local text = arg and arg[1]

      if type(text) == "string" then
        -- 1) special-case /castsequence → call CRM directly and RETURN TRUE
        local b, e, rest = string.find(text, "^%s*/castsequence%s*(.*)")
        if b then
          if type(CleveRoids) == "table" and type(CleveRoids.DoCastSequence) == "function" then
            pcall(CleveRoids.DoCastSequence, rest or "")
            return true
          end
          -- fallback: slash handler if defined
          local fn = _G.SlashCmdList and _G.SlashCmdList["CASTSEQUENCE"]
          if type(fn) == "function" then
            pcall(fn, rest or "")
            return true
          end
          -- nothing to do; pass through to SM
        else
          -- 2) generic /cmd forwarding (lets CRM handlers parse [])
          local _, _, raw, msg = string.find(text, "^/(%S+)%s*(.*)$")
          if raw then
            local cmd = string.lower(raw)
            -- alias map: /unbuff → /cancelaura
            if cmd == "unbuff" then cmd = "cancelaura" end
            if INTERCEPT[cmd] and has_handler(cmd) then
              pcall(_G.SlashCmdList[string.upper(cmd)], msg or "")
              return true  -- IMPORTANT: tell SM we handled it
            end
          end

          -- 3) fast-path for extended/bracket tokens (/cast {…} [/…] ! ? ~)
          local hooks = { cast = CRM.DoCast, target = CRM.DoTarget, use = CRM.DoUse }
          for k, fn in pairs(hooks) do
            if type(fn) == "function" then
              local b2, e2 = string.find(text, "^%s*/" .. k .. "%s+[!%[%{%?~]")
              if b2 then
                local msg2 = string.gsub(string.sub(text, e2), "^%s+", "")
                pcall(fn, msg2)
                return true  -- IMPORTANT
              end
            end
          end
        end
      end

      -- Not handled by CRM: let SuperMacro do its normal processing
      return orig_RunLine(text)
    end

    CRM.SM_RunLineHooked = true

    -- Hook SuperMacro_RunMacro to clear stopmacro flag at macro start
    -- and redirect global RunMacro so all macro execution goes through RunLine
    if type(_G.SuperMacro_RunMacro) == "function" then
      local orig_SuperMacro_RunMacro = _G.SuperMacro_RunMacro
      CRM.Hooks.SuperMacro_RunMacro = orig_SuperMacro_RunMacro

      local function hooked_RunMacro(index)
        -- Clear macro stop flags at macro start
        CRM.stopMacroFlag = false
        CRM.skipMacroFlag = false
        return orig_SuperMacro_RunMacro(index)
      end

      _G.SuperMacro_RunMacro = hooked_RunMacro
      _G.RunMacro = hooked_RunMacro
      _G.Macro = hooked_RunMacro
    end

    -- Hook RunSuperMacro (for "Super" extended text macros) to clear stopmacro flag
    -- This is a separate function from SuperMacro_RunMacro and uses RunLine directly
    if type(_G.RunSuperMacro) == "function" then
      local orig_RunSuperMacro = _G.RunSuperMacro
      CRM.Hooks.RunSuperMacro = orig_RunSuperMacro

      _G.RunSuperMacro = function(index)
        -- Clear macro stop flags at macro start
        CRM.stopMacroFlag = false
        CRM.skipMacroFlag = false
        return orig_RunSuperMacro(index)
      end
    end
  end

  -- ===== Order-agnostic loader: install only when BOTH addons are present =====
  local SM_LOADED, CRM_LOADED = false, false
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:RegisterEvent("PLAYER_LOGIN")

  local function note_loaded(name)
    if name == "SuperMacro" then
      SM_LOADED = true
    elseif name == "SuperCleveRoidMacros" or name == "CleveRoidMacros" then
      CRM_LOADED = true
    end
  end

  local function both_loaded()
    if SM_LOADED and CRM_LOADED then return true end
    -- heuristic fallback in case this file loads late:
    -- Check for SuperMacro's namespaced internal function (preferred) or RunLine
    local sm_ok  = type(_G.SuperMacro_RunMacro) == "function" or type(_G.RunLine) == "function"
    local crm_ok = _G.CleveRoids and _G.SlashCmdList and type(_G.SlashCmdList.CAST) == "function"
    return sm_ok and crm_ok
  end

  local function try_install()
    if both_loaded() then install_supermacro_hook() end
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
