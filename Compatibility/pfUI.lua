local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("Compatibility_pfUI")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")
Extension.Debug = false

function Extension.RunMacro(name)
    CleveRoids.ExecuteMacroByName(name)
end

function Extension.DLOG(msg)
    if Extension.Debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffcccc33[R]: |cffffff55" .. ( msg ))
    end
end

function Extension.FocusNameHook()
    local hook = Extension.internal.memberHooks[CleveRoids]["GetFocusName"]
    local target = hook.original()

    if pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.unitname then
        target = pfUI.uf.focus.unitname
    end

    --Extension.DLOG(target)

    return target
end

function Extension.OnLoad()
    Extension.DLOG("Extension pfUI Loaded.")
    Extension.HookMethod(CleveRoids, "GetFocusName", "FocusNameHook", true)
    Extension.UnregisterEvent("ADDON_LOADED", "Onload")
end

_G["CleveRoids"] = CleveRoids
