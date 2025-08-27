-- CleveRoidMacros/Compatibility/SuperMacro.lua
-- Make SuperMacro’s RunLine play nicely with CleveRoidMacros (incl. /castsequence)

local _G  = _G or getfenv(0)
local CRM = _G.CleveRoids or {}
_G.CleveRoids = CRM

local function install_supermacro_hook()
  if CRM.SM_RunLineHooked then return end
  if type(_G.RunLine) ~= "function" then return end

  -- Commands we only intercept when they use bracket/extended syntax
  local bracketHooks = {
    cast   = CRM.DoCast,
    target = CRM.DoTarget,
    use    = CRM.DoUse,
  }

  CRM.Hooks = CRM.Hooks or {}
  CRM.Hooks.RunLine = CRM.Hooks.RunLine or _G.RunLine

  _G.RunLine = function(...)
    for i = 1, arg.n do
      local text = arg[i]
      if CRM.stopmacro then
        CRM.stopmacro = false
        return true
      end

      local handled = false
      if type(text) == "string" then
        -- 1) Always handle /castsequence (with or without conditionals)
        local b1, e1, rest = string.find(text, "^%s*/castsequence%s*(.*)")
        if b1 then
          local msg = CRM.Trim(rest or "")
          local seq = CRM.GetSequence(msg)
          if seq then pcall(CRM.DoCastSequence, seq) end
          handled = true
        else
          -- 2) Bracketed/advanced forms for /cast, /target, /use
          for cmd, action in bracketHooks do
            local b2, e2 = string.find(text, "^%s*/" .. cmd .. "%s+[!%[]")
            if b2 then
              local msg = string.sub(text, e2)
              msg = string.gsub(msg, "^%s+", "")
              pcall(action, msg)
              handled = true
              break
            end
          end
        end
      end

      if not handled then
        CRM.Hooks.RunLine(text) -- fall back to SuperMacro’s original logic
      end
    end
  end

  CRM.SM_RunLineHooked = true
end

-- Install after either addon is ready (order-agnostic)
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, addon)
  if event == "ADDON_LOADED" then
    if addon == "SuperMacro" or addon == "CleveRoidMacros" then
      install_supermacro_hook()
    end
  else
    install_supermacro_hook()
  end
end)
