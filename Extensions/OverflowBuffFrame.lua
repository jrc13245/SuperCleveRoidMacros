--[[
    OverflowBuffFrame Extension
    Two frames displaying server-side overflow buffs (no client aura slot) for
    the player and the current target (if a group/party member).
    Player data: CleveRoids.OverflowBuffs (AURA_CAST_ON_SELF when buff-capped).
    Target data: CleveRoids.AllCasterAuraTracking filtered by UnitBuff visibility.
    Each frame shows 2 rows of 8 icons = 16 slots.

    Author: Mewtiny
    License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

-- ============================================================================
-- Constants
-- ============================================================================
local ICON_SIZE = 24
local ICON_SPACING = 2
local ICONS_PER_ROW = 8
local NUM_ROWS = 2
local ICONS_PER_FRAME = ICONS_PER_ROW * NUM_ROWS  -- 16
local ROW_SPACING = 16  -- vertical gap between rows (icon + duration text)
local DURATION_FONT_SIZE = 10
local DURATION_OFFSET_Y = -3
local UPDATE_INTERVAL = 0.2
local LABEL_HEIGHT = 12

-- ============================================================================
-- State
-- ============================================================================
local playerFrame = nil
local targetFrame = nil
local playerIcons = {}   -- [1..16]
local targetIcons = {}   -- [1..16]
local playerLabelFs = nil
local targetLabelFs = nil
local updateFrame = nil
local updateElapsed = 0
local testMode = false
local dirty = false  -- Flag for deferred rebuild (avoids event ordering race)
local lastPlayerCount = 0
local lastTargetCount = 0

-- ============================================================================
-- Duration Formatting (matches pfUI api.lua:1324 style)
-- ============================================================================
local function FormatDuration(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 100 then
        return math.floor(seconds / 60 + 0.5) .. "m"
    elseif seconds > 5 then
        return math.floor(seconds + 0.5) .. "s"
    else
        return string.format("%.1f", seconds)
    end
end

-- Forward declarations (needed by OnClick closures in CreateIconButton)
local RebuildFrame

-- ============================================================================
-- Icon Button Creation
-- ============================================================================
local function CreateIconButton(parent, index, iconTable)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(ICON_SIZE)
    btn:SetHeight(ICON_SIZE)
    btn:RegisterForClicks("RightButtonUp")

    -- Dark 1px border backdrop (pfUI style)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropColor(0, 0, 0, 0.6)
    btn:SetBackdropBorderColor(0.1, 0.1, 0.1, 0.9)

    -- Icon texture (inset by 1px for border)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:Hide()

    -- Duration text below icon
    local dur = btn:CreateFontString(nil, "OVERLAY")
    dur:SetFont("Fonts\\FRIZQT__.TTF", DURATION_FONT_SIZE, "OUTLINE")
    dur:SetPoint("TOP", btn, "BOTTOM", 0, DURATION_OFFSET_Y)
    dur:SetJustifyH("CENTER")
    dur:SetTextColor(1, 1, 1, 1)
    dur:SetText("")

    -- Right-click to cancel player overflow buffs
    btn:SetScript("OnClick", function()
        local data = iconTable[index]
        if not data or not data.spellId then return end
        if data.source ~= "player" then return end

        -- CancelPlayerAuraSpellId(spellId, ignoreMissing)
        -- ignoreMissing=1 is required for overflow buffs that have no client aura slot
        if CancelPlayerAuraSpellId then
            CancelPlayerAuraSpellId(data.spellId, 1)
        end

        -- Remove from overflow tracking
        if CleveRoids.OverflowBuffs then
            CleveRoids.OverflowBuffs[data.spellId] = nil
        end

        -- Hide tooltip and rebuild
        GameTooltip:Hide()
        RebuildFrame()
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function()
        local data = iconTable[index]
        if not data or not data.spellId then return end
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMLEFT")
        local spellName = SpellInfo and SpellInfo(data.spellId) or ("Spell " .. data.spellId)
        if spellName then
            local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
            GameTooltip:AddLine(baseName, 1, 1, 1)
        end
        if data.remaining and data.remaining > 0 then
            GameTooltip:AddLine(FormatDuration(data.remaining) .. " remaining", 0.7, 0.7, 0.7)
        end
        if data.source == "player" then
            GameTooltip:AddLine("Right-click to cancel", 0.8, 0.8, 0.5)
        else
            GameTooltip:AddLine("Overflow buff (target)", 0.5, 1.0, 0.8)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:Hide()

    return {
        button = btn,
        icon = icon,
        duration = dur,
        spellId = nil,
        remaining = nil,
        source = nil,
    }
end

-- ============================================================================
-- Frame Creation
-- ============================================================================

-- Compute frame dimensions
local FRAME_WIDTH = ICONS_PER_ROW * (ICON_SIZE + ICON_SPACING) - ICON_SPACING
local FRAME_HEIGHT = LABEL_HEIGHT + NUM_ROWS * (ICON_SIZE + ROW_SPACING)

local function CreateBuffFrame(name, savedPosKey, defaultY, labelColor, iconTable)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(FRAME_HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, defaultY)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:Hide()

    -- Section label
    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    label:SetTextColor(labelColor[1], labelColor[2], labelColor[3], 0.8)
    label:SetText("")

    -- Create 16 icon slots in 2 rows of 8
    for i = 1, ICONS_PER_FRAME do
        iconTable[i] = CreateIconButton(frame, i, iconTable)
        local row = math.floor((i - 1) / ICONS_PER_ROW)
        local col = math.mod(i - 1, ICONS_PER_ROW)
        local xOff = col * (ICON_SIZE + ICON_SPACING)
        local yOff = -(LABEL_HEIGHT + row * (ICON_SIZE + ROW_SPACING))
        iconTable[i].button:SetPoint("TOPLEFT", frame, "TOPLEFT", xOff, yOff)
    end

    -- Shift+drag to move
    frame:SetScript("OnMouseDown", function()
        if IsShiftKeyDown() then
            frame:StartMoving()
        end
    end)
    frame:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        local _, _, _, x, y = frame:GetPoint(1)
        CleveRoidMacros = CleveRoidMacros or {}
        CleveRoidMacros[savedPosKey] = { x = x, y = y }
    end)

    -- Restore saved position
    CleveRoidMacros = CleveRoidMacros or {}
    if CleveRoidMacros[savedPosKey] then
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP",
            CleveRoidMacros[savedPosKey].x or 0,
            CleveRoidMacros[savedPosKey].y or defaultY)
    end

    return frame, label
end

-- ============================================================================
-- Data Collection
-- ============================================================================

local function GetPlayerOverflowBuffs()
    local results = {}
    local overflowBuffs = CleveRoids.OverflowBuffs
    if not overflowBuffs then return results end

    local now = GetTime()
    for spellId, entry in pairs(overflowBuffs) do
        if entry.timestamp and entry.durationSec then
            local remaining = entry.durationSec - (now - entry.timestamp)
            if remaining > 0 then
                table.insert(results, {
                    spellId = spellId,
                    remaining = remaining,
                    source = "player",
                })
            end
        end
    end

    table.sort(results, function(a, b) return a.remaining > b.remaining end)
    return results
end

local function GetTargetOverflowBuffs()
    local results = {}

    if not UnitExists("target") then return results end
    if not testMode and not (UnitInParty("target") or UnitInRaid("target")) then return results end

    local _, targetGuid = UnitExists("target")
    if not targetGuid then return results end

    local trackingData = CleveRoids.AllCasterAuraTracking
    if not trackingData or not trackingData[targetGuid] then return results end

    -- Build set of visible buff textures on target
    local visibleBuffs = {}
    for i = 1, 32 do
        local texture = UnitBuff("target", i)
        if not texture then break end
        visibleBuffs[texture] = true
    end

    local now = GetTime()
    local lib = CleveRoids.libdebuff

    for spellId, auraData in pairs(trackingData[targetGuid]) do
        if auraData.start and auraData.duration then
            local remaining = auraData.duration + auraData.start - now
            if remaining > 0 then
                local isVisible = false
                if not auraData._testEntry then
                    local spellIcon = lib and lib:GetCachedIcon(spellId)
                    isVisible = spellIcon and visibleBuffs[spellIcon]
                end
                if not isVisible then
                    table.insert(results, {
                        spellId = spellId,
                        remaining = remaining,
                        source = "target",
                    })
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.remaining > b.remaining end)
    return results
end

-- ============================================================================
-- Layout
-- ============================================================================

local function PopulateFrame(frame, label, labelText, iconTable, buffs, countRef)
    local count = table.getn(buffs)
    if count > ICONS_PER_FRAME then count = ICONS_PER_FRAME end

    local lib = CleveRoids.libdebuff

    for i = 1, count do
        local data = iconTable[i]
        local buff = buffs[i]

        local texture = lib and lib:GetCachedIcon(buff.spellId)
        if texture then
            data.icon:SetTexture(texture)
        else
            data.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        data.icon:Show()

        data.spellId = buff.spellId
        data.remaining = buff.remaining
        data.source = buff.source
        data.duration:SetText(FormatDuration(buff.remaining))
        data.button:EnableMouse(true)
        data.button:Show()
    end

    -- Hide unused
    for i = count + 1, ICONS_PER_FRAME do
        local data = iconTable[i]
        data.button:Hide()
        data.icon:Hide()
        data.duration:SetText("")
        data.spellId = nil
        data.remaining = nil
        data.source = nil
    end

    if count > 0 then
        label:SetText(labelText)
        frame:EnableMouse(true)
        frame:Show()
    else
        label:SetText("")
        frame:EnableMouse(false)
        frame:Hide()
    end

    return count
end

RebuildFrame = function()
    if not playerFrame then return end

    local pBuffs = GetPlayerOverflowBuffs()
    lastPlayerCount = PopulateFrame(playerFrame, playerLabelFs, "Overflow (You)", playerIcons, pBuffs)

    local tBuffs = GetTargetOverflowBuffs()
    local targetName = UnitExists("target") and UnitName("target") or "Target"
    lastTargetCount = PopulateFrame(targetFrame, targetLabelFs, "Overflow (" .. targetName .. ")", targetIcons, tBuffs)
end

-- Refresh only duration text (no full rebuild)
local function RefreshDurations()
    local anyExpired = false
    local now = GetTime()

    -- Player durations
    if playerFrame and playerFrame:IsVisible() then
        for i = 1, lastPlayerCount do
            local data = playerIcons[i]
            if data.spellId then
                local entry = CleveRoids.OverflowBuffs and CleveRoids.OverflowBuffs[data.spellId]
                if entry and entry.timestamp and entry.durationSec then
                    local remaining = entry.durationSec - (now - entry.timestamp)
                    if remaining > 0 then
                        data.remaining = remaining
                        data.duration:SetText(FormatDuration(remaining))
                    else
                        anyExpired = true
                    end
                else
                    anyExpired = true
                end
            end
        end
    end

    -- Target durations
    if targetFrame and targetFrame:IsVisible() then
        local targetGuid = nil
        if UnitExists("target") then
            local _, guid = UnitExists("target")
            targetGuid = guid
        end
        for i = 1, lastTargetCount do
            local data = targetIcons[i]
            if data.spellId and targetGuid then
                local remaining = CleveRoids.GetAllCasterAuraTimeRemaining(targetGuid, data.spellId) or 0
                if remaining > 0 then
                    data.remaining = remaining
                    data.duration:SetText(FormatDuration(remaining))
                else
                    anyExpired = true
                end
            else
                anyExpired = true
            end
        end
    end

    if anyExpired then
        RebuildFrame()
    end
end

-- ============================================================================
-- Test Mode
-- ============================================================================

local TEST_PLAYER_SPELL_IDS = {
    1126,   -- Mark of the Wild
    1243,   -- Power Word: Fortitude
    1461,   -- Arcane Intellect
    14752,  -- Divine Spirit
    976,    -- Shadow Protection
    6307,   -- Blood Pact
    20217,  -- Blessing of Kings
    19740,  -- Blessing of Might
    21849,  -- Gift of the Wild
    25898,  -- Greater Blessing of Kings
    25899,  -- Greater Blessing of Sanctuary
    25890,  -- Greater Blessing of Light
    10938,  -- Greater Power Word: Fortitude
    10157,  -- Greater Arcane Intellect
    20911,  -- Blessing of Sanctuary
    25782,  -- Greater Blessing of Might
}

local TEST_TARGET_SPELL_IDS = {
    467,    -- Thorns
    10060,  -- Power Infusion
    17007,  -- Leader of the Pack
    24932,  -- Leader of the Pack aura
    19506,  -- Trueshot Aura
    8936,   -- Regrowth
    774,    -- Rejuvenation
    139,    -- Renew
    1022,   -- Blessing of Protection
    6346,   -- Fear Ward
    1044,   -- Blessing of Freedom
    10958,  -- Shadow Protection (rank)
    27681,  -- Prayer of Spirit
    21562,  -- Prayer of Fortitude
    20914,  -- Blessing of Sanctuary (rank)
    25916,  -- Greater Blessing of Wisdom
}

local testTargetGuid = nil
local testStartTime = 0  -- when test mode was enabled (for duration calc)

-- Remove test entries from a specific GUID in AllCasterAuraTracking
local function ClearTestTargetData(guid)
    if not guid or not CleveRoids.AllCasterAuraTracking then return end
    local targetData = CleveRoids.AllCasterAuraTracking[guid]
    if not targetData then return end
    for spellId, entry in pairs(targetData) do
        if entry._testEntry then
            targetData[spellId] = nil
        end
    end
    if not next(targetData) then
        CleveRoids.AllCasterAuraTracking[guid] = nil
    end
end

-- Inject test entries for the current target
local function InjectTestTargetData()
    if not UnitExists("target") then return end
    local _, targetGuid = UnitExists("target")
    if not targetGuid then return end

    -- Clean up old test target if it changed
    if testTargetGuid and testTargetGuid ~= targetGuid then
        ClearTestTargetData(testTargetGuid)
    end

    testTargetGuid = targetGuid
    CleveRoids.AllCasterAuraTracking = CleveRoids.AllCasterAuraTracking or {}
    if not CleveRoids.AllCasterAuraTracking[targetGuid] then
        CleveRoids.AllCasterAuraTracking[targetGuid] = {}
    end

    local targetDurations = { 8, 15, 25, 40, 55, 90, 150, 240, 400, 500, 700, 1000, 1300, 1600, 2000, 3000 }
    for i = 1, table.getn(TEST_TARGET_SPELL_IDS) do
        local spellId = TEST_TARGET_SPELL_IDS[i]
        local dur = targetDurations[i] or 60
        CleveRoids.AllCasterAuraTracking[targetGuid][spellId] = {
            start = testStartTime,
            duration = dur,
            casterGuid = "test",
            _testEntry = true,
        }
    end
end

local function EnableTestMode()
    testMode = true
    testStartTime = GetTime()
    CleveRoids.OverflowBuffs = CleveRoids.OverflowBuffs or {}

    local playerDurations = { 5, 10, 30, 45, 60, 120, 180, 300, 450, 600, 900, 1200, 1500, 1800, 2400, 3600 }

    for i = 1, table.getn(TEST_PLAYER_SPELL_IDS) do
        local spellId = TEST_PLAYER_SPELL_IDS[i]
        local dur = playerDurations[i] or 60
        CleveRoids.OverflowBuffs[spellId] = {
            timestamp = testStartTime,
            durationSec = dur,
            _testEntry = true,
        }
    end

    -- Inject target test data if we have a target
    InjectTestTargetData()

    CleveRoids.Print("|cff00ff00Overflow buff frame test mode enabled|r")
    CleveRoids.Print("  Shift+drag to reposition the frames")

    RebuildFrame()
end

local function DisableTestMode()
    testMode = false

    if CleveRoids.OverflowBuffs then
        for spellId, entry in pairs(CleveRoids.OverflowBuffs) do
            if entry._testEntry then
                CleveRoids.OverflowBuffs[spellId] = nil
            end
        end
    end

    ClearTestTargetData(testTargetGuid)
    testTargetGuid = nil

    CleveRoids.Print("|cffff9900Overflow buff frame test mode disabled|r")

    RebuildFrame()
end

local function ToggleTestMode()
    if testMode then
        DisableTestMode()
    else
        EnableTestMode()
    end
end

CleveRoids.ToggleOverflowTest = ToggleTestMode

-- ============================================================================
-- OnUpdate Handler
-- ============================================================================
local function OnUpdate()
    updateElapsed = updateElapsed + arg1
    -- Check dirty flag every frame for responsive rebuilds after AURA_CAST events.
    -- By the time OnUpdate fires, the core handler has already updated OverflowBuffs.
    if dirty then
        dirty = false
        updateElapsed = 0
        RebuildFrame()
        return
    end
    if updateElapsed < UPDATE_INTERVAL then return end
    updateElapsed = 0
    RefreshDurations()
end

-- ============================================================================
-- Extension Registration
-- ============================================================================
local ext = CleveRoids.RegisterExtension("OverflowBuffFrame")

ext.OnTargetChanged = function()
    -- Re-inject test data for the new target during test mode
    if testMode then
        InjectTestTargetData()
    end
    RebuildFrame()
end

ext.OnAuraCast = function()
    -- Defer rebuild to OnUpdate: the core handler that populates OverflowBuffs
    -- registers for AURA_CAST_ON_SELF later (PLAYER_ENTERING_WORLD) than this
    -- extension (ADDON_LOADED), so it fires AFTER us. A direct RebuildFrame()
    -- here would read stale data.
    dirty = true
end

ext.OnGroupChanged = function()
    RebuildFrame()
end

ext.OnPlayerDead = function()
    if CleveRoids.OverflowBuffs then
        if testMode then
            for spellId, entry in pairs(CleveRoids.OverflowBuffs) do
                if not entry._testEntry then
                    CleveRoids.OverflowBuffs[spellId] = nil
                end
            end
        else
            CleveRoids.OverflowBuffs = {}
        end
    end
    RebuildFrame()
end

ext.OnLoad = function()
    playerFrame, playerLabelFs = CreateBuffFrame(
        "CleveRoidsOverflowPlayer", "overflowPlayerPos", -100,
        { 0.4, 0.7, 1.0 }, playerIcons)

    targetFrame, targetLabelFs = CreateBuffFrame(
        "CleveRoidsOverflowTarget", "overflowTargetPos", -170,
        { 0.4, 1.0, 0.7 }, targetIcons)

    ext.RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    ext.RegisterEvent("PARTY_MEMBERS_CHANGED", "OnGroupChanged")
    ext.RegisterEvent("RAID_ROSTER_UPDATE", "OnGroupChanged")
    ext.RegisterEvent("PLAYER_DEAD", "OnPlayerDead")

    if CleveRoids.hasNampower then
        ext.RegisterEvent("AURA_CAST_ON_SELF", "OnAuraCast")
    end

    -- Shared OnUpdate frame
    updateFrame = CreateFrame("Frame")
    updateFrame:SetScript("OnUpdate", OnUpdate)

    RebuildFrame()
end

_G["CleveRoids"] = CleveRoids
