--[[
	Macro Error UI - Real-time visual error feedback in the macro editor
	Author: Mewtiny
	License: MIT License

	Provides:
	- Error summary panel anchored below MacroFrame
	- Red semi-transparent backdrop on error lines in the EditBox
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("MacroErrorUI")

-- Constants
local DEBOUNCE_DELAY = 0.3
local MAX_PANEL_HEIGHT = 120
local MAX_DISPLAY_ERRORS = 5
local HIGHLIGHT_POOL_SIZE = 20
local ERROR_FONT_POOL_SIZE = 6 -- header + max errors

-- State
local errorPanel = nil
local headerText = nil
local errorFontStrings = {}
local lineHighlights = {}
local lastKeystroke = 0
local pendingValidation = false
local lastSelectedMacro = nil
local updateFrame = nil
local hooked = false
local measureFs = nil  -- hidden FontString for measuring text width (wrap detection)

-- Cache for current errors (avoids re-validation on every frame)
local currentErrors = nil
local nameHighlight = nil -- Yellow backdrop behind macro name when name has errors

-- ============================================================================
-- Error Panel (Option A)
-- ============================================================================

local function CreateErrorPanel()
    if errorPanel then return end

    local panel = CreateFrame("Frame", "CleveRoidsErrorPanel", MacroFrame)
    -- Anchor to the scroll frame (text edit area) instead of the full MacroFrame,
    -- which can extend far below the visible UI on extended macro clients
    local scrollRef = MacroFrameScrollFrame or MacroFrame
    panel:SetPoint("TOPLEFT", scrollRef, "BOTTOMLEFT", 0, -27)
    panel:SetPoint("TOPRIGHT", scrollRef, "BOTTOMRIGHT", 0, -27)
    panel:SetHeight(1)
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.1, 0.05, 0.05, 0.92)
    panel:SetBackdropBorderColor(0.6, 0.1, 0.1, 0.8)
    panel:Hide()

    -- Header: "N error(s) found"
    headerText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerText:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    headerText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    headerText:SetTextColor(1, 0.3, 0.3, 1)

    -- Pre-allocate error message FontStrings
    for i = 1, MAX_DISPLAY_ERRORS do
        local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", headerText, "BOTTOMLEFT", 0, -2 - (i - 1) * 12)
        fs:SetPoint("TOPRIGHT", headerText, "BOTTOMRIGHT", 0, -2 - (i - 1) * 12)
        fs:SetJustifyH("LEFT")
        fs:Hide()
        errorFontStrings[i] = fs
    end

    errorPanel = panel
end

local function UpdateErrorPanel(errors)
    if not errorPanel then return end

    local count = errors and table.getn(errors) or 0

    if count == 0 then
        errorPanel:Hide()
        return
    end

    -- Header
    if count == 1 then
        headerText:SetText("1 error found")
    else
        headerText:SetText(count .. " errors found")
    end

    -- Populate error lines
    local displayed = 0
    for i = 1, MAX_DISPLAY_ERRORS do
        local fs = errorFontStrings[i]
        if i <= count then
            local err = errors[i]
            local linePrefix = err.line and ("Line " .. err.line .. ": ") or ""
            local msg = linePrefix .. (err.message or "Unknown error")
            -- Truncate long messages
            if string.len(msg) > 80 then
                msg = string.sub(msg, 1, 77) .. "..."
            end
            -- Name errors in yellow, syntax errors in red
            local color = err.type == "NAME_ERROR" and "|cffffcc60" or "|cffffa0a0"
            fs:SetText(color .. msg .. "|r")
            fs:Show()
            displayed = displayed + 1
        else
            fs:SetText("")
            fs:Hide()
        end
    end

    -- Show overflow indicator
    if count > MAX_DISPLAY_ERRORS then
        local lastFs = errorFontStrings[MAX_DISPLAY_ERRORS]
        lastFs:SetText("|cff888888... and " .. (count - MAX_DISPLAY_ERRORS + 1) .. " more|r")
        lastFs:Show()
    end

    -- Dynamic height: header(16) + padding(8+6) + lines(12 each)
    local linesShown = displayed
    if linesShown > MAX_DISPLAY_ERRORS then linesShown = MAX_DISPLAY_ERRORS end
    local height = 8 + 16 + 2 + (linesShown * 12) + 6
    if height > MAX_PANEL_HEIGHT then height = MAX_PANEL_HEIGHT end
    errorPanel:SetHeight(height)
    errorPanel:Show()
end

-- ============================================================================
-- Line Highlights (Option B)
-- ============================================================================

local function GetLineHeight()
    if not MacroFrameText then return 13 end
    local _, fontSize = MacroFrameText:GetFont()
    -- Use raw font size - this matches the EditBox's actual line spacing
    return fontSize or 13
end

local function GetTopTextInset()
    if not MacroFrameText then return 0 end
    -- GetTextInsets returns left, right, top, bottom padding inside the EditBox
    local success, l, r, t, b = pcall(MacroFrameText.GetTextInsets, MacroFrameText)
    if success and t then
        return t
    end
    return 0
end

local function EnsureHighlightPool()
    if table.getn(lineHighlights) >= HIGHLIGHT_POOL_SIZE then return end

    for i = table.getn(lineHighlights) + 1, HIGHLIGHT_POOL_SIZE do
        local tex = MacroFrameText:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(0.6, 0.08, 0.08, 0.25)
        tex:Hide()
        lineHighlights[i] = tex
    end
end

local function UpdateLineHighlights(errors)
    if not MacroFrameText then return end

    EnsureHighlightPool()

    -- Collect which lines have errors (deduplicate)
    local errorLines = {}
    if errors then
        for _, err in ipairs(errors) do
            if err.line then
                errorLines[err.line] = true
            end
        end
    end

    local lineHeight = GetLineHeight()
    local topInset = GetTopTextInset()
    local editWidth = MacroFrameText:GetWidth()
    if editWidth < 10 then editWidth = 260 end -- fallback

    -- Create measurement FontString lazily (same font as EditBox, hidden)
    if not measureFs then
        measureFs = (MacroFrame or UIParent):CreateFontString(nil, "OVERLAY")
        measureFs:Hide()
    end
    local fontPath, fontSize, fontFlags = MacroFrameText:GetFont()
    if fontPath then
        measureFs:SetFont(fontPath, fontSize, fontFlags)
    end

    -- Split macro text into logical lines for wrap calculation
    local text = MacroFrameText:GetText() or ""
    local logicalLines = {}
    local lineStart = 1
    while true do
        local nlPos = string.find(text, "\n", lineStart, true)
        if nlPos then
            table.insert(logicalLines, string.sub(text, lineStart, nlPos - 1))
            lineStart = nlPos + 1
        else
            table.insert(logicalLines, string.sub(text, lineStart))
            break
        end
    end

    -- Calculate visual line count for each logical line
    local visualCounts = {}
    for i, line in ipairs(logicalLines) do
        if line == "" or editWidth <= 0 then
            visualCounts[i] = 1
        else
            measureFs:SetText(line)
            local textWidth = measureFs:GetStringWidth()
            visualCounts[i] = math.max(1, math.ceil(textWidth / editWidth))
        end
    end

    local highlightIdx = 1
    for lineNum, _ in pairs(errorLines) do
        if highlightIdx > HIGHLIGHT_POOL_SIZE then break end

        local tex = lineHighlights[highlightIdx]

        -- Y offset: sum visual lines of all preceding logical lines
        local yLines = 0
        for i = 1, lineNum - 1 do
            yLines = yLines + (visualCounts[i] or 1)
        end
        local yOffset = -topInset - (yLines * lineHeight)
        local highlightHeight = (visualCounts[lineNum] or 1) * lineHeight

        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", MacroFrameText, "TOPLEFT", -2, yOffset)
        tex:SetWidth(editWidth + 4)
        tex:SetHeight(highlightHeight)
        tex:Show()

        highlightIdx = highlightIdx + 1
    end

    -- Hide unused highlights
    for i = highlightIdx, HIGHLIGHT_POOL_SIZE do
        if lineHighlights[i] then
            lineHighlights[i]:Hide()
        end
    end
end

-- ============================================================================
-- Name Highlight (yellow backdrop on macro name)
-- ============================================================================

local function CreateNameHighlight()
    if nameHighlight then return end
    -- Find the macro name display element
    -- Standard Blizzard_MacroUI uses MacroFrameSelectedMacroName (FontString)
    -- and MacroFrameSelectedMacroButton (icon)
    local nameFrame = getglobal("MacroFrameSelectedMacroName")
    if not nameFrame then return end

    -- FontStrings can't own textures, so create on their parent
    local parent = nameFrame:GetParent() or MacroFrame
    local tex = parent:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(0.7, 0.6, 0.1, 0.3)
    tex:SetPoint("TOPLEFT", nameFrame, "TOPLEFT", -3, 3)
    tex:SetPoint("BOTTOMRIGHT", nameFrame, "BOTTOMRIGHT", 3, -3)
    tex:Hide()
    nameHighlight = tex
end

local function UpdateNameHighlight(hasNameErrors)
    if not nameHighlight then
        CreateNameHighlight()
    end
    if nameHighlight then
        if hasNameErrors then
            nameHighlight:Show()
        else
            nameHighlight:Hide()
        end
    end
end

-- ============================================================================
-- Validation & Debounce
-- ============================================================================

-- Build a set of player spell names (lowercase) for name conflict checks
local function GetPlayerSpellNames()
    local spellNames = {}
    -- Primary source: CleveRoids.Spells indexed table
    if CleveRoids.Spells then
        for bookType, spells in CleveRoids.Spells do
            if type(spells) == "table" then
                for spellName, _ in pairs(spells) do
                    if type(spellName) == "string" then
                        spellNames[string.lower(spellName)] = true
                    end
                end
            end
        end
    end
    -- Fallback: iterate spellbook directly
    if not next(spellNames) then
        local i = 1
        while true do
            local name, rank = GetSpellName(i, "spell")
            if not name then break end
            spellNames[string.lower(name)] = true
            i = i + 1
        end
    end
    return spellNames
end

-- Build a set of player item names (lowercase) for name conflict checks
local function GetPlayerItemNames()
    local itemNames = {}
    if CleveRoids.Items then
        for key, value in pairs(CleveRoids.Items) do
            if type(key) == "string" and type(value) == "table" and value.name then
                itemNames[string.lower(value.name)] = true
            end
        end
    end
    return itemNames
end

-- Validate the current macro's name and return any name errors
local function ValidateMacroName()
    local nameErrors = {}
    if not MacroFrame or not MacroFrame.selectedMacro then return nameErrors end

    local selectedSlot = MacroFrame.selectedMacro
    local nameOk, name = pcall(GetMacroInfo, selectedSlot)
    if not nameOk or not name then return nameErrors end

    -- Blank/whitespace name
    local trimmedName = CleveRoids.Trim and CleveRoids.Trim(name) or name
    if trimmedName == "" then
        table.insert(nameErrors, {
            type = "NAME_ERROR",
            message = "Macro name is blank or only spaces"
        })
    end

    -- Spell conflict
    local lowerName = string.lower(name)
    local spellNames = GetPlayerSpellNames()
    if spellNames[lowerName] then
        table.insert(nameErrors, {
            type = "NAME_ERROR",
            message = "Name '" .. name .. "' conflicts with a spell/ability"
        })
    end

    -- Item conflict
    local itemNames = GetPlayerItemNames()
    if itemNames[lowerName] then
        table.insert(nameErrors, {
            type = "NAME_ERROR",
            message = "Name '" .. name .. "' conflicts with an item"
        })
    end

    -- Duplicate name check
    local dupeCount = 0
    for i = 1, 36 do
        local ok, otherName = pcall(GetMacroInfo, i)
        if ok and otherName and string.lower(otherName) == lowerName then
            dupeCount = dupeCount + 1
        end
    end
    if dupeCount > 1 then
        table.insert(nameErrors, {
            type = "NAME_ERROR",
            message = "Duplicate name '" .. name .. "' (used " .. dupeCount .. " times)"
        })
    end

    return nameErrors
end

local function RunValidation()
    if not MacroFrameText then return end

    local bodyText = MacroFrameText:GetText()
    if not bodyText or bodyText == "" then
        currentErrors = nil
        UpdateErrorPanel(nil)
        UpdateLineHighlights(nil)
        UpdateNameHighlight(false)
        return
    end

    -- Combine name errors + body errors
    local errors = {}

    local nameErrors = ValidateMacroName()
    local hasNameErrors = table.getn(nameErrors) > 0
    for _, err in ipairs(nameErrors) do
        table.insert(errors, err)
    end

    local bodyErrors = CleveRoids.ValidateMacroBody(bodyText)
    if bodyErrors then
        for _, err in ipairs(bodyErrors) do
            table.insert(errors, err)
        end
    end

    if table.getn(errors) == 0 then errors = nil end
    currentErrors = errors

    UpdateErrorPanel(errors)
    UpdateLineHighlights(errors)
    UpdateNameHighlight(hasNameErrors)
end

local function RequestValidation()
    lastKeystroke = GetTime()
    pendingValidation = true
end

local function OnUpdateTick()
    if not MacroFrame or not MacroFrame:IsVisible() then return end

    -- Debounced keystroke validation
    if pendingValidation and (GetTime() - lastKeystroke) >= DEBOUNCE_DELAY then
        pendingValidation = false
        RunValidation()
    end

    -- Detect macro selection change (poll-based, safer than hooking unknown functions)
    if MacroFrame.selectedMacro ~= lastSelectedMacro then
        lastSelectedMacro = MacroFrame.selectedMacro
        -- Immediate validation on selection change
        pendingValidation = false
        RunValidation()
    end
end

-- ============================================================================
-- Cleanup
-- ============================================================================

-- Report all macro errors to chat on frame close
local function ReportAllMacroErrors()
    local accountEntries = {} -- { {name=, slot=, errors=}, ... }
    local characterEntries = {}
    local nameCount = {} -- lowercase name -> count (for duplicate detection)
    local nameSlots = {} -- lowercase name -> { slot1, slot2, ... }
    local spellNames = GetPlayerSpellNames()
    local itemNames = GetPlayerItemNames()

    -- First pass: collect all macro names and body errors
    for i = 1, 36 do
        local nameOk, name = pcall(GetMacroInfo, i)
        if nameOk and name and name ~= "" then
            local errors = {}

            -- Validate body
            local _, _, body = GetMacroInfo(i)
            if body and body ~= "" then
                local bodyErrors = CleveRoids.ValidateMacroBody(body)
                if bodyErrors then
                    for _, err in ipairs(bodyErrors) do
                        table.insert(errors, err)
                    end
                end
            end

            -- Check blank/whitespace name
            local trimmedName = CleveRoids.Trim and CleveRoids.Trim(name) or name
            if trimmedName == "" then
                table.insert(errors, {
                    type = "NAME_ERROR",
                    message = "Macro name is blank or only spaces"
                })
            end

            -- Check if name matches a player spell
            local lowerNameCheck = string.lower(name)
            if spellNames[lowerNameCheck] then
                table.insert(errors, {
                    type = "NAME_ERROR",
                    message = "Name '" .. name .. "' conflicts with a known spell/ability"
                })
            end

            -- Check if name matches a player item
            if itemNames[lowerNameCheck] then
                table.insert(errors, {
                    type = "NAME_ERROR",
                    message = "Name '" .. name .. "' conflicts with an inventory item"
                })
            end

            -- Track name for duplicate detection
            local lowerName = string.lower(name)
            nameCount[lowerName] = (nameCount[lowerName] or 0) + 1
            if not nameSlots[lowerName] then nameSlots[lowerName] = {} end
            table.insert(nameSlots[lowerName], i)

            local entry = { name = name, slot = i, errors = errors }
            if i <= 18 then
                table.insert(accountEntries, entry)
            else
                table.insert(characterEntries, entry)
            end
        end
    end

    -- Second pass: inject duplicate name errors
    for lowerName, count in pairs(nameCount) do
        if count > 1 then
            local slots = nameSlots[lowerName]
            for _, slot in ipairs(slots) do
                -- Find the entry for this slot and add the error
                local list = slot <= 18 and accountEntries or characterEntries
                for _, entry in ipairs(list) do
                    if entry.slot == slot then
                        table.insert(entry.errors, 1, {
                            type = "NAME_ERROR",
                            message = "Duplicate name '" .. entry.name .. "' (used " .. count .. " times)"
                        })
                        break
                    end
                end
            end
        end
    end

    -- Output: filter to only entries with errors
    local accountErrors = {}
    local characterErrors = {}
    for _, entry in ipairs(accountEntries) do
        if table.getn(entry.errors) > 0 then
            table.insert(accountErrors, entry)
        end
    end
    for _, entry in ipairs(characterEntries) do
        if table.getn(entry.errors) > 0 then
            table.insert(characterErrors, entry)
        end
    end

    local totalMacros = table.getn(accountErrors) + table.getn(characterErrors)
    if totalMacros == 0 then return end

    DEFAULT_CHAT_FRAME:AddMessage("|cffff6060[MacroErrorChecker]|r Found errors in " .. totalMacros .. " macro(s):", 1, 0.8, 0.4)

    local function PrintSection(label, entries)
        if table.getn(entries) == 0 then return end
        DEFAULT_CHAT_FRAME:AddMessage("  |cff88aaff--- " .. label .. " ---|r")
        for _, entry in ipairs(entries) do
            local count = table.getn(entry.errors)
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff" .. entry.name .. "|r - " .. count .. " error(s)")
            for _, err in ipairs(entry.errors) do
                local linePrefix = err.line and ("L" .. err.line .. ": ") or ""
                local msg = linePrefix .. (err.message or "Unknown error")
                if string.len(msg) > 90 then
                    msg = string.sub(msg, 1, 87) .. "..."
                end
                -- Name errors in yellow, syntax errors in red
                local color = err.type == "NAME_ERROR" and "|cffffcc60" or "|cffffa0a0"
                DEFAULT_CHAT_FRAME:AddMessage("    " .. color .. msg .. "|r")
            end
        end
    end

    PrintSection("General Macros", accountErrors)
    PrintSection("Character Macros", characterErrors)
end

local function ClearAll()
    currentErrors = nil
    pendingValidation = false
    lastSelectedMacro = nil

    if errorPanel then
        errorPanel:Hide()
    end

    for i = 1, MAX_DISPLAY_ERRORS do
        if errorFontStrings[i] then
            errorFontStrings[i]:SetText("")
            errorFontStrings[i]:Hide()
        end
    end

    for i = 1, table.getn(lineHighlights) do
        if lineHighlights[i] then
            lineHighlights[i]:Hide()
        end
    end

    if nameHighlight then
        nameHighlight:Hide()
    end
end

-- ============================================================================
-- Hook Installation
-- ============================================================================

local function InstallHooks()
    if hooked then return end
    if not MacroFrameText or not MacroFrame then return end

    -- Skip if SuperMacro is active (it replaces the macro editor entirely)
    if SuperMacroFrame ~= nil then return end

    -- OnTextChanged: trigger debounced validation on every keystroke
    local origOnTextChanged = MacroFrameText:GetScript("OnTextChanged")
    MacroFrameText:SetScript("OnTextChanged", function()
        if origOnTextChanged then
            origOnTextChanged()
        end
        RequestValidation()
    end)

    -- OnShow: validate immediately when macro frame opens
    local origOnShow = MacroFrame:GetScript("OnShow")
    MacroFrame:SetScript("OnShow", function()
        if origOnShow then
            origOnShow()
        end
        -- Create panel lazily on first show
        CreateErrorPanel()
        -- Reset state and validate
        lastSelectedMacro = MacroFrame.selectedMacro
        RunValidation()
    end)

    -- OnHide: clean up everything
    local origOnHide = MacroFrame:GetScript("OnHide")
    MacroFrame:SetScript("OnHide", function()
        if origOnHide then
            origOnHide()
        end
        ClearAll()
        -- Report all macro errors to chat when closing the editor
        pcall(ReportAllMacroErrors)
    end)

    -- OnUpdate for debounce timer and selection change polling
    updateFrame = CreateFrame("Frame")
    updateFrame:SetScript("OnUpdate", function()
        local success, err = pcall(OnUpdateTick)
        if not success then
            -- Silently fail - don't spam errors every frame
            pendingValidation = false
        end
    end)

    hooked = true
end

-- ============================================================================
-- Extension Entry Points
-- ============================================================================

function Extension.OnAddonLoaded()
    if arg1 == "Blizzard_MacroUI" then
        InstallHooks()
    end
end

function Extension.OnLoad()
    -- Skip if SuperMacro is loaded (detected at load time)
    if SuperMacroFrame ~= nil then return end

    -- Listen for macro UI loading
    Extension.RegisterEvent("ADDON_LOADED", "OnAddonLoaded")

    -- If MacroFrame already exists (unlikely but safe), hook immediately
    if MacroFrame and MacroFrameText then
        InstallHooks()
    end
end

_G["CleveRoids"] = CleveRoids
