--[[
    Cursive mouseover support.
    Hooks into Cursive's bar OnEnter/OnLeave to track mouseover unit by GUID.
    Enables [@mouseover] macros when hovering over Cursive DoT timer bars.
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

CleveRoids.Hooks = CleveRoids.Hooks or {}

local Extension = CleveRoids.RegisterExtension("CursiveMouseover")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")

local hooked = false

function Extension.OnEnter(guid)
    if guid and guid ~= 0 then
        -- SuperWoW's SetMouseoverUnit supports GUIDs directly
        CleveRoids.SetMouseoverFrom("cursive", guid)
    end
end

function Extension.OnLeave()
    CleveRoids.ClearMouseoverFrom("cursive")
end

local function HookCursiveUI()
    -- Check if Cursive and its UI module exist
    if not Cursive or not Cursive.ui then
        return false
    end

    -- Already hooked
    if hooked then
        return true
    end

    local ui = Cursive.ui

    -- Hook BarEnter if it exists
    if ui.BarEnter then
        CleveRoids.Hooks.CursiveBarEnter = ui.BarEnter
        ui.BarEnter = function()
            -- Call original
            CleveRoids.Hooks.CursiveBarEnter()
            -- Set mouseover from the bar's parent guid
            if this and this.parent and this.parent.guid then
                Extension.OnEnter(this.parent.guid)
            end
        end
    end

    -- Hook BarLeave if it exists
    if ui.BarLeave then
        CleveRoids.Hooks.CursiveBarLeave = ui.BarLeave
        ui.BarLeave = function()
            -- Clear mouseover first
            Extension.OnLeave()
            -- Call original
            CleveRoids.Hooks.CursiveBarLeave()
        end
    end

    hooked = true
    return true
end

function Extension.OnLoad()
    -- Try to hook when Cursive loads
    if arg1 == "Cursive" then
        -- Delay slightly to ensure Cursive.ui is initialized
        local frame = CreateFrame("Frame")
        frame:SetScript("OnUpdate", function()
            if HookCursiveUI() then
                this:Hide()
            end
        end)
    end
end

-- Also try to hook immediately in case Cursive is already loaded
if Cursive and Cursive.ui then
    HookCursiveUI()
end

_G["CleveRoids"] = CleveRoids
