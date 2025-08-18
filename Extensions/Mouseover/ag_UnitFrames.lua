local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

CleveRoids.Hooks = CleveRoids.Hooks or {}
CleveRoids.mouseoverUnit = CleveRoids.mouseoverUnit or nil

local Extension = CleveRoids.RegisterExtension("ag_UnitFrames")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")

function Extension.OnEnter(unit)
    CleveRoids.mouseoverUnit = unit
end

function Extension.OnLeave()
    CleveRoids.mouseoverUnit = nil
end

-- Because AddOns are loaded in alphabetical order, this callback will never see the aUF loaded message, had to do a workaround...
function Extension.OnLoad()
    if not aUF then
        return
    end
    CleveRoids.Hooks.ag_UnitFrames = { OnEnter = aUF.classes.aUFunit.prototype.OnEnter, OnLeave = aUF.classes.aUFunit.prototype.OnLeave}
    aUF.classes.aUFunit.prototype.OnEnter = CleveRoids.aUFOnEnter
    aUF.classes.aUFunit.prototype.OnLeave = CleveRoids.aUFOnLeave
    Extension.UnregisterEvent("ADDON_LOADED", "Onload")
end

-- Taken from ag_UnitClass.lua
function CleveRoids:aUFOnEnter()
    Extension.OnEnter(self.unit)
    self.frame.unit = self.unit
    self:UpdateHighlight(true)
    UnitFrame_OnEnter()
end

function CleveRoids:aUFOnLeave()
    Extension.OnLeave()
    self:UpdateHighlight()
    UnitFrame_OnLeave()
end


_G["CleveRoids"] = CleveRoids
