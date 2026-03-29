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
local COND_HIGHLIGHT_POOL_SIZE = 20
local COND_EVAL_INTERVAL = 0.5  -- seconds between conditional evaluations

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
local measureFs = nil  -- hidden FontString for measuring text width (GetStringWidth)
local wrapFs = nil     -- hidden FontString with SetWidth for height-based wrap detection

-- Cache for current errors (avoids re-validation on every frame)
local currentErrors = nil
local nameHighlight = nil -- Yellow backdrop behind macro name when name has errors
local condHighlights = {}        -- green texture pool for conditional highlights
local lastCondEvalTime = 0       -- GetTime() of last conditional evaluation
local lastCondFingerprint = nil  -- cache key to avoid repositioning when unchanged
local cachedMacroText = nil      -- text key for parsed line structure cache
local cachedLineData = nil       -- cached parsed lines: { {cmd, args, offsets, lineText}, ... }

-- Whitelist GUI state
local whitelistButton = nil
local whitelistPopup = nil
local WHITELIST_ROW_POOL_SIZE = 8
local whitelistRows = {}  -- pre-allocated label+remove rows

-- Forward declarations (defined later, referenced by whitelist GUI)
local RequestValidation

-- ============================================================================
-- Error Panel (Option A)
-- ============================================================================

local function CreateErrorPanel()
    if errorPanel then return end

    local panel = CreateFrame("Frame", "CleveRoidsErrorPanel", MacroFrame)
    -- Anchor to the scroll frame (text edit area) instead of the full MacroFrame,
    -- which can extend far below the visible UI on extended macro clients
    local scrollRef = MacroFrameScrollFrame or MacroFrame
    panel:SetPoint("TOPLEFT", scrollRef, "BOTTOMLEFT", -20, -47)
    panel:SetPoint("TOPRIGHT", scrollRef, "BOTTOMRIGHT", 0, -47)
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
-- Visual Line Break Detection
-- ============================================================================

-- Find character positions where each visual line starts in a text string.
-- Returns array of 1-based char indices: {1, 30, 58, ...}
-- Uses a width-constrained FontString (wrapFs) with GetHeight() to detect
-- wraps. SetNonSpaceWrap(true) is used to reliably detect line count (works
-- even for text with no spaces), then binary search with word-wrapping
-- (SetNonSpaceWrap false) finds actual break positions matching the EditBox's
-- word-wrap behavior.
local function FindVisualLineBreaks(text, editWidth, fs)
    local breaks = {1}
    local textLen = string.len(text)
    if textLen == 0 or editWidth <= 0 then return breaks end

    -- Initialize wrapFs lazily with same font, constrained to editWidth
    if not wrapFs then
        wrapFs = (MacroFrame or UIParent):CreateFontString(nil, "OVERLAY")
        wrapFs:Hide()
    end
    local fontPath, fontSize, fontFlags = fs:GetFont()
    if fontPath then
        wrapFs:SetFont(fontPath, fontSize, fontFlags)
    end
    wrapFs:SetWidth(editWidth)

    -- Get single line height for line counting
    wrapFs:SetText("M")
    local singleH = wrapFs:GetHeight()
    if not singleH or singleH <= 0 then return breaks end

    -- Use SetNonSpaceWrap to reliably detect total line count
    -- (works even for text with no spaces)
    wrapFs:SetNonSpaceWrap(true)
    wrapFs:SetText(text)
    local totalH = wrapFs:GetHeight()
    local numLines = math.floor(totalH / singleH + 0.5)
    if numLines <= 1 then
        wrapFs:SetNonSpaceWrap(false)
        return breaks
    end

    -- Switch to word wrapping for break position detection
    -- EditBox uses word wrapping (breaks at spaces), not character-level
    wrapFs:SetNonSpaceWrap(false)

    -- Binary search for each visual line break position
    local searchStart = 1
    for targetLine = 2, numLines do
        local lo, hi = searchStart, textLen
        local breakAt = textLen + 1
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            wrapFs:SetText(string.sub(text, 1, mid))
            local h = wrapFs:GetHeight()
            local lines = math.floor(h / singleH + 0.5)
            if lines < targetLine then
                lo = mid + 1
            else
                breakAt = mid
                hi = mid - 1
            end
        end
        if breakAt <= textLen then
            -- Word wrapping: the overflow is at breakAt, but the actual line
            -- break is at the start of the word that caused the overflow.
            -- Search backward for the last space to find the word boundary.
            local wordStart = breakAt
            for p = breakAt - 1, searchStart, -1 do
                if string.byte(text, p) == 32 then -- space
                    wordStart = p + 1
                    break
                end
            end
            table.insert(breaks, wordStart)
            searchStart = wordStart
        end
    end

    return breaks
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

    -- Create measurement FontString lazily (visible but offscreen for layout)
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
            visualCounts[i] = table.getn(FindVisualLineBreaks(line, editWidth, measureFs))
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
-- Command Whitelist GUI
-- ============================================================================

local function RefreshWhitelistDisplay()
    if not whitelistPopup then return end

    local commands = CleveRoids.GetWhitelistedCommandsList()
    local count = table.getn(commands)

    -- Update rows
    for i = 1, WHITELIST_ROW_POOL_SIZE do
        local row = whitelistRows[i]
        if row then
            if i <= count then
                row.label:SetText(commands[i])
                row.frame:Show()
            else
                row.label:SetText("")
                row.frame:Hide()
            end
        end
    end

    -- Show overflow indicator
    local overflowText = whitelistPopup.overflowText
    if count > WHITELIST_ROW_POOL_SIZE then
        overflowText:SetText("|cff888888... and " .. (count - WHITELIST_ROW_POOL_SIZE) .. " more|r")
        overflowText:Show()
    else
        overflowText:SetText("")
        overflowText:Hide()
    end

    -- Dynamic height: title(20) + gap(8) + editbox(18) + rows(18 each) + padding
    local rowsShown = count
    if rowsShown > WHITELIST_ROW_POOL_SIZE then rowsShown = WHITELIST_ROW_POOL_SIZE end
    local height = 8 + 20 + 8 + 18 + 2 + (rowsShown * 18)
    if count > WHITELIST_ROW_POOL_SIZE then
        height = height + 14
    end
    height = height + 8  -- bottom padding
    whitelistPopup:SetHeight(height)

    -- Re-trigger error checking so results update in real time
    RequestValidation()
end

local function CreateWhitelistPopup()
    if whitelistPopup then return end

    local popup = CreateFrame("Frame", "CleveRoidsWhitelistPopup", UIParent)
    popup:SetWidth(220)
    popup:SetHeight(120)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)

    -- pfUI pixel-perfect flat style
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
    popup:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    popup:Hide()

    -- Drag handling
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    popup:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
    end)

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -8)
    title:SetText("Whitelisted Commands")
    title:SetTextColor(0.9, 0.8, 0.5, 1)

    -- Close button (flat X)
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetWidth(16)
    closeBtn:SetHeight(16)
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY")
    closeLbl:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    closeLbl:SetPoint("CENTER", 0, 0)
    closeLbl:SetText("x")
    closeLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    closeBtn:SetScript("OnEnter", function()
        closeLbl:SetTextColor(1, 0.3, 0.3, 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeLbl:SetTextColor(0.6, 0.6, 0.6, 1)
    end)
    closeBtn:SetScript("OnClick", function()
        popup:Hide()
    end)

    -- EditBox (flat style)
    local editBox = CreateFrame("EditBox", "CleveRoidsWhitelistEditBox", popup)
    editBox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    editBox:SetWidth(148)
    editBox:SetHeight(18)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(60)
    editBox:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetTextInsets(4, 4, 0, 0)
    editBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    editBox:SetBackdropColor(0.05, 0.05, 0.07, 0.9)
    editBox:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    -- Add button (flat style)
    local addBtn = CreateFrame("Button", nil, popup)
    addBtn:SetPoint("LEFT", editBox, "RIGHT", 4, 0)
    addBtn:SetWidth(40)
    addBtn:SetHeight(18)
    addBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    addBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    addBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
    addLbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    addLbl:SetPoint("CENTER", 0, 0)
    addLbl:SetText("Add")
    addLbl:SetTextColor(0.8, 0.8, 0.8, 1)
    addBtn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.25, 0.25, 0.25, 0.95)
        this:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
        addLbl:SetTextColor(1, 1, 1, 1)
    end)
    addBtn:SetScript("OnLeave", function()
        this:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        this:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
        addLbl:SetTextColor(0.8, 0.8, 0.8, 1)
    end)

    local function AddCommand()
        local text = editBox:GetText()
        if not text or CleveRoids.Trim(text) == "" then return end
        text = CleveRoids.Trim(text)
        CleveRoids.AddWhitelistedCommand(text)
        editBox:SetText("")
        editBox:ClearFocus()
        RefreshWhitelistDisplay()
    end

    addBtn:SetScript("OnClick", AddCommand)
    editBox:SetScript("OnEnterPressed", function()
        AddCommand()
    end)
    editBox:SetScript("OnEscapePressed", function()
        this:ClearFocus()
    end)

    -- Anchor for rows: below the editbox row
    local rowAnchor = editBox

    -- Pre-allocate row pool
    for i = 1, WHITELIST_ROW_POOL_SIZE do
        local rowFrame = CreateFrame("Frame", nil, popup)
        rowFrame:SetHeight(16)
        rowFrame:SetPoint("TOPLEFT", rowAnchor, "BOTTOMLEFT", 0, -2)
        rowFrame:SetPoint("RIGHT", popup, "RIGHT", -8, 0)
        rowFrame:Hide()

        local label = rowFrame:CreateFontString(nil, "OVERLAY")
        label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        label:SetPoint("LEFT", rowFrame, "LEFT", 2, 0)
        label:SetJustifyH("LEFT")
        label:SetTextColor(0.7, 0.7, 0.7, 1)

        -- Flat X remove button
        local removeBtn = CreateFrame("Button", nil, rowFrame)
        removeBtn:SetWidth(14)
        removeBtn:SetHeight(14)
        removeBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -1, 0)
        local removeLbl = removeBtn:CreateFontString(nil, "OVERLAY")
        removeLbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        removeLbl:SetPoint("CENTER", 0, 0)
        removeLbl:SetText("x")
        removeLbl:SetTextColor(0.5, 0.5, 0.5, 1)
        removeBtn.removeLbl = removeLbl
        removeBtn.rowIndex = i

        removeBtn:SetScript("OnEnter", function()
            this.removeLbl:SetTextColor(1, 0.3, 0.3, 1)
        end)
        removeBtn:SetScript("OnLeave", function()
            this.removeLbl:SetTextColor(0.5, 0.5, 0.5, 1)
        end)
        removeBtn:SetScript("OnClick", function()
            local idx = this.rowIndex
            local row = whitelistRows[idx]
            if row and row.label then
                local cmd = row.label:GetText()
                if cmd and cmd ~= "" then
                    CleveRoids.RemoveWhitelistedCommand(cmd)
                    RefreshWhitelistDisplay()
                end
            end
        end)

        whitelistRows[i] = { frame = rowFrame, label = label, removeBtn = removeBtn }
        rowAnchor = rowFrame
    end

    -- Overflow text
    local overflowText = popup:CreateFontString(nil, "OVERLAY")
    overflowText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    overflowText:SetPoint("TOPLEFT", whitelistRows[WHITELIST_ROW_POOL_SIZE].frame, "BOTTOMLEFT", 2, -2)
    overflowText:SetJustifyH("LEFT")
    overflowText:SetTextColor(0.5, 0.5, 0.5, 1)
    overflowText:Hide()
    popup.overflowText = overflowText

    whitelistPopup = popup
end

local function CreateWhitelistButton()
    if whitelistButton then return end
    if not MacroFrame then return end

    local btn = CreateFrame("Button", "CleveRoidsWhitelistButton", MacroFrame)
    btn:SetWidth(80)
    btn:SetHeight(18)
    btn:SetPoint("BOTTOMRIGHT", MacroFrame, "BOTTOMRIGHT", 8, 32)
    btn:SetFrameStrata("DIALOG")

    -- pfUI pixel-perfect flat style
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText("Whitelist")
    label:SetTextColor(0.8, 0.8, 0.8, 1)
    btn.label = label

    -- Hover highlight
    btn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.2, 0.2, 0.2, 0.95)
        this:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
        this.label:SetTextColor(1, 1, 1, 1)
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("Command Whitelist")
        GameTooltip:AddLine("Add third-party addon commands so the", 1, 1, 1, true)
        GameTooltip:AddLine("error checker stops flagging them.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        this:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
        this:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        this.label:SetTextColor(0.8, 0.8, 0.8, 1)
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        CreateWhitelistPopup()
        if whitelistPopup:IsVisible() then
            whitelistPopup:Hide()
        else
            RefreshWhitelistDisplay()
            whitelistPopup:Show()
        end
    end)

    whitelistButton = btn
end

-- ============================================================================
-- Live Conditional Highlighting
-- ============================================================================

local function EnsureCondHighlightPool()
    if table.getn(condHighlights) >= COND_HIGHLIGHT_POOL_SIZE then return end

    for i = table.getn(condHighlights) + 1, COND_HIGHLIGHT_POOL_SIZE do
        local tex = MacroFrameText:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(0.08, 0.6, 0.08, 0.25)
        tex:Hide()
        condHighlights[i] = tex
    end
end

-- Test whether conditionals pass for a given command + alternative text.
-- Returns: true (passes), false (fails), nil (unconditional / no conditionals)
local function TestConditionalPasses(cmd, alternative)
    -- Strip ? tooltip hints (irrelevant for conditional evaluation)
    if string.find(alternative, "?", 1, true) then
        alternative = string.gsub(alternative, "%?", "")
    end

    local hasConditional = string.find(alternative, "%[") ~= nil

    -- Dynamic commands: delegate to TestAction
    if CleveRoids.dynamicCmds[cmd] then
        local result = CleveRoids.TestAction(cmd, alternative)
        if not hasConditional then
            return nil  -- unconditional
        end
        return result ~= nil and result ~= false
    end

    -- Non-dynamic commands: parse and evaluate Keywords manually
    if not hasConditional then
        return nil  -- unconditional
    end

    local ok, action, conditionals = pcall(CleveRoids.GetParsedMsg, alternative)
    if not ok or not conditionals then
        return nil
    end

    CleveRoids._isTestingAction = true

    local passes = true
    local k = next(conditionals)
    while k do
        if not CleveRoids.ignoreKeywords[k] then
            local handler = CleveRoids.Keywords[k]
            if not handler or not handler(conditionals) then
                passes = false
                break
            end
        end
        k = next(conditionals, k)
    end

    CleveRoids._isTestingAction = false
    return passes
end

-- Find character offset ranges for each semicolon-separated alternative.
-- Returns array of { start, finish } pairs (1-based indices within argsText).
local function FindAlternativeOffsets(argsText)
    local result = {}
    local inQuote = false
    local bracketDepth = 0
    local altStart = 1

    for i = 1, string.len(argsText) do
        local ch = string.sub(argsText, i, i)
        if ch == "\"" then
            inQuote = not inQuote
        elseif not inQuote then
            if ch == "[" then
                bracketDepth = bracketDepth + 1
            elseif ch == "]" then
                bracketDepth = bracketDepth - 1
                if bracketDepth < 0 then bracketDepth = 0 end
            elseif ch == ";" and bracketDepth == 0 then
                table.insert(result, { start = altStart, finish = i - 1 })
                altStart = i + 1
            end
        end
    end

    -- Final alternative (after last semicolon, or entire string if no semicolons)
    if altStart <= string.len(argsText) then
        table.insert(result, { start = altStart, finish = string.len(argsText) })
    end

    return result
end

-- Parse macro text into line structure (cached — only re-parses when text changes).
-- Returns array of { lineNum, cmd, args, argsStartInLine, offsets, lineText, alts }
local function GetParsedLineData(text)
    if text == cachedMacroText and cachedLineData then
        return cachedLineData
    end

    local data = {}
    local lineStart = 1
    local lineNum = 0

    while true do
        lineNum = lineNum + 1
        local nlPos = string.find(text, "\n", lineStart, true)
        local line
        if nlPos then
            line = string.sub(text, lineStart, nlPos - 1)
        else
            line = string.sub(text, lineStart)
        end

        -- Filter: only lines with conditionals
        if line and line ~= "" and not string.find(line, "^#showtooltip") and string.find(line, "%[") then
            local cmd, args = CleveRoids.SplitCommandAndArgs(line)
            if cmd and args and args ~= "" then
                local cmdLen = string.len(cmd)
                local argsStartInLine = string.find(line, args, cmdLen + 1, true)
                if argsStartInLine then
                    local offsets = FindAlternativeOffsets(args)
                    if table.getn(offsets) > 0 then
                        -- Pre-extract alternative substrings and conditional flags
                        local alts = {}
                        for i = 1, table.getn(offsets) do
                            local altText = string.sub(args, offsets[i].start, offsets[i].finish)
                            alts[i] = {
                                text = altText,
                                hasConditional = string.find(altText, "%[") ~= nil,
                                startInLine = argsStartInLine + offsets[i].start - 1,
                                endInLine = argsStartInLine + offsets[i].finish - 1,
                            }
                        end
                        table.insert(data, {
                            lineNum = lineNum,
                            cmd = cmd,
                            alts = alts,
                            lineText = line,
                        })
                    end
                end
            end
        end

        if not nlPos then break end
        lineStart = nlPos + 1
    end

    cachedMacroText = text
    cachedLineData = data
    return data
end

-- Evaluate which conditional alternatives pass for each line of macro text.
-- Returns: { [lineNum] = { startChar, endChar, lineText } }
local function EvaluateConditionals(text)
    local lineData = GetParsedLineData(text)
    local results = {}

    for _, entry in ipairs(lineData) do
        local anyConditionalSeen = false
        local allConditionalsFailed = true

        for i = 1, table.getn(entry.alts) do
            local alt = entry.alts[i]

            if alt.hasConditional then
                anyConditionalSeen = true
            end

            local ok, passed = pcall(TestConditionalPasses, entry.cmd, alt.text)
            if not ok then
                passed = false
            end

            if passed == true then
                allConditionalsFailed = false
                results[entry.lineNum] = { startChar = alt.startInLine, endChar = alt.endInLine, lineText = entry.lineText }
                break
            elseif passed == nil then
                if anyConditionalSeen and allConditionalsFailed then
                    results[entry.lineNum] = { startChar = alt.startInLine, endChar = alt.endInLine, lineText = entry.lineText }
                end
                break
            end
        end
    end

    return results
end

-- Position green highlights for passing conditional sections.
local function UpdateCondHighlights(condResults, errorLines)
    if not MacroFrameText then return end

    EnsureCondHighlightPool()

    local lineHeight = GetLineHeight()
    local topInset = GetTopTextInset()
    local editWidth = MacroFrameText:GetWidth()
    if editWidth < 10 then editWidth = 260 end

    -- Ensure measureFs exists (shared with UpdateLineHighlights)
    if not measureFs then
        measureFs = (MacroFrame or UIParent):CreateFontString(nil, "OVERLAY")
        measureFs:Hide()
    end
    local fontPath, fontSize, fontFlags = MacroFrameText:GetFont()
    if fontPath then
        measureFs:SetFont(fontPath, fontSize, fontFlags)
    end

    -- Split text into logical lines for wrap calculation
    local text = MacroFrameText:GetText() or ""
    local logicalLines = {}
    local ls = 1
    while true do
        local nlPos = string.find(text, "\n", ls, true)
        if nlPos then
            table.insert(logicalLines, string.sub(text, ls, nlPos - 1))
            ls = nlPos + 1
        else
            table.insert(logicalLines, string.sub(text, ls))
            break
        end
    end

    local visualCounts = {}
    for i, line in ipairs(logicalLines) do
        if line == "" or editWidth <= 0 then
            visualCounts[i] = 1
        else
            visualCounts[i] = table.getn(FindVisualLineBreaks(line, editWidth, measureFs))
        end
    end

    local highlightIdx = 1
    for lineNum, info in pairs(condResults) do
        if highlightIdx > COND_HIGHLIGHT_POOL_SIZE then break end
        -- Red overrides green
        if not errorLines[lineNum] then
            local tex = condHighlights[highlightIdx]

            -- Y offset: sum visual lines of preceding logical lines
            local yLines = 0
            for i = 1, lineNum - 1 do
                yLines = yLines + (visualCounts[i] or 1)
            end
            local yOffset = -topInset - (yLines * lineHeight)

            -- X offset via text measurement
            local prefix = string.sub(info.lineText, 1, info.startChar - 1)
            measureFs:SetText(prefix)
            local xOffset = measureFs:GetStringWidth()

            local section = string.sub(info.lineText, info.startChar, info.endChar)
            measureFs:SetText(section)
            local sectionWidth = measureFs:GetStringWidth()

            -- Handle wrapped lines: find actual visual line break positions
            -- instead of modular arithmetic (inaccurate with variable-width chars)
            local prefixWrappedLines = 0
            local effectiveX = xOffset
            local visualBreaks  -- computed on demand for wrapped lines

            if editWidth > 0 and (visualCounts[lineNum] or 1) > 1 then
                visualBreaks = FindVisualLineBreaks(info.lineText, editWidth, measureFs)

                -- Find which visual line startChar is on, measure X from that line's start
                for vl = table.getn(visualBreaks), 1, -1 do
                    if info.startChar >= visualBreaks[vl] then
                        prefixWrappedLines = vl - 1
                        local vlStart = visualBreaks[vl]
                        if vlStart < info.startChar then
                            measureFs:SetText(string.sub(info.lineText, vlStart, info.startChar - 1))
                            effectiveX = measureFs:GetStringWidth()
                        else
                            effectiveX = 0
                        end
                        break
                    end
                end
            end

            -- Adjust Y for the visual lines consumed by the prefix wrapping
            local adjustedYOffset = yOffset - (prefixWrappedLines * lineHeight)
            local sectionWraps = editWidth > 0 and effectiveX + sectionWidth > editWidth

            if sectionWraps then
                -- Section wraps: first texture covers from effectiveX to end of line
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", MacroFrameText, "TOPLEFT", effectiveX - 1, adjustedYOffset)
                tex:SetWidth(editWidth - effectiveX + 2)
                tex:SetHeight(lineHeight)
                tex:Show()

                -- Find how many continuation visual lines the section spans
                if not visualBreaks then
                    visualBreaks = FindVisualLineBreaks(info.lineText, editWidth, measureFs)
                end
                local endWrappedLines = 0
                for vl = table.getn(visualBreaks), 1, -1 do
                    if info.endChar >= visualBreaks[vl] then
                        endWrappedLines = vl - 1
                        break
                    end
                end
                local continuationLines = math.max(1, endWrappedLines - prefixWrappedLines)
                if continuationLines > 0 then
                    highlightIdx = highlightIdx + 1
                    if highlightIdx <= COND_HIGHLIGHT_POOL_SIZE then
                        local tex2 = condHighlights[highlightIdx]
                        tex2:ClearAllPoints()
                        tex2:SetPoint("TOPLEFT", MacroFrameText, "TOPLEFT", -1, adjustedYOffset - lineHeight)
                        tex2:SetWidth(editWidth + 2)
                        tex2:SetHeight(continuationLines * lineHeight)
                        tex2:Show()
                    end
                end
            else
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", MacroFrameText, "TOPLEFT", effectiveX - 1, adjustedYOffset)
                tex:SetWidth(sectionWidth + 2)
                tex:SetHeight(lineHeight)
                tex:Show()
            end

            highlightIdx = highlightIdx + 1
        end
    end

    -- Hide unused pool textures
    for i = highlightIdx, COND_HIGHLIGHT_POOL_SIZE do
        if condHighlights[i] then
            condHighlights[i]:Hide()
        end
    end
end

-- Orchestrator: evaluate conditionals and update highlights
local function RunConditionalEvaluation()
    if not MacroFrameText then return end

    local text = MacroFrameText:GetText()
    if not text or text == "" then
        -- Hide all green highlights
        for i = 1, table.getn(condHighlights) do
            if condHighlights[i] then condHighlights[i]:Hide() end
        end
        lastCondFingerprint = nil
        return
    end

    local ok, condResults = pcall(EvaluateConditionals, text)
    if not ok or not condResults then
        return
    end

    -- Build fingerprint from results
    local parts = {}
    for lineNum, info in pairs(condResults) do
        table.insert(parts, lineNum .. ":" .. info.startChar .. ":" .. info.endChar)
    end
    table.sort(parts)
    local fingerprint = table.concat(parts, "|")

    if fingerprint == lastCondFingerprint then return end
    lastCondFingerprint = fingerprint

    -- Build errorLines set from currentErrors
    local errorLines = {}
    if currentErrors then
        for _, err in ipairs(currentErrors) do
            if err.line then
                errorLines[err.line] = true
            end
        end
    end

    UpdateCondHighlights(condResults, errorLines)
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

RequestValidation = function()
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
        lastCondFingerprint = nil  -- force re-evaluation on selection change
        cachedMacroText = nil      -- invalidate line structure cache
        cachedLineData = nil
        -- Immediately hide stale green highlights from previous macro
        for i = 1, table.getn(condHighlights) do
            if condHighlights[i] then condHighlights[i]:Hide() end
        end
        RunValidation()
    end

    -- Periodic conditional evaluation (live green highlights)
    local now = GetTime()
    if (now - lastCondEvalTime) >= COND_EVAL_INTERVAL then
        lastCondEvalTime = now
        pcall(RunConditionalEvaluation)
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

    for i = 1, table.getn(condHighlights) do
        if condHighlights[i] then condHighlights[i]:Hide() end
    end
    lastCondFingerprint = nil
    lastCondEvalTime = 0
    cachedMacroText = nil
    cachedLineData = nil

    if whitelistPopup then
        whitelistPopup:Hide()
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
        -- Create UI lazily on first show
        CreateErrorPanel()
        CreateWhitelistButton()
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
    -- Skip if macro checker is disabled
    if CleveRoidMacros and CleveRoidMacros.macrocheck == 0 then return end

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
