local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("Compatibility_SuperMacro")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")

function Extension.RunMacro(name)
    CleveRoids.ExecuteMacroByName(name)
end

function Extension.OnLoad()
    if not SuperMacroFrame then
        return
    end

    Extension.Hook("RunMacro", "RunMacro", true)
    Extension.UnregisterEvent("ADDON_LOADED", "Onload")
end


_G["CleveRoids"] = CleveRoids