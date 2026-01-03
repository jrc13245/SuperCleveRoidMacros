--[[
    CursiveCustomSpells Extension

    Automatically injects custom spell definitions into Cursive's tracking system.
    Any spell in this list will be tracked by Cursive when you cast it normally.

    Format:
        [spellID] = { name = "lowercase spell name", rank = X, duration = Y },

    Optional fields:
        variableDuration = true     -- Duration can be modified by talents/haste
        calculateDuration = func    -- Function returning dynamic duration
        numTicks = N                -- Number of DoT ticks (for tick tracking)
        darkHarvest = true          -- Affected by Dark Harvest talent
]]

local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids

--============================================================================
-- CUSTOM SPELL DEFINITIONS
-- Add your custom debuffs here. They will be auto-tracked when cast.
--============================================================================

CleveRoids.CustomCursiveSpells = CleveRoids.CustomCursiveSpells or {
    --========================================================================
    -- WARRIOR DEBUFFS (from database.turtlecraft.gg)
    --========================================================================

    -- Deep Wounds (talent proc, bleed over 12 sec - ticks every 3s)
    [12721] = { name = "deep wounds", rank = 1, duration = 6 },
    [12162] = { name = "deep wounds", rank = 1, duration = 6 },
    [12850] = { name = "deep wounds", rank = 2, duration = 6 },
    [12868] = { name = "deep wounds", rank = 3, duration = 6 },

    -- Hamstring (15 sec snare, 50% movement speed)
    [1715] = { name = "hamstring", rank = 1, duration = 15 },
    [7372] = { name = "hamstring", rank = 2, duration = 15 },
    [7373] = { name = "hamstring", rank = 3, duration = 15 },

    --========================================================================
    -- TAUNTS (personal debuffs)
    --========================================================================

    -- Taunt (Warrior, 3 sec)
    [355] = { name = "taunt", rank = 1, duration = 3 },
    [29060] = { name = "taunt", rank = 1, duration = 3 },  -- variant

    -- Growl (Druid Bear, 3 sec)
    [6795] = { name = "growl", rank = 1, duration = 3 },

    -- Mocking Blow (Warrior, 6 sec)
    [694] = { name = "mocking blow", rank = 1, duration = 6 },
    [7400] = { name = "mocking blow", rank = 2, duration = 6 },
    [7402] = { name = "mocking blow", rank = 3, duration = 6 },
    [20559] = { name = "mocking blow", rank = 4, duration = 6 },
    [20560] = { name = "mocking blow", rank = 5, duration = 6 },

    -- Hand of Reckoning (Paladin, 3 sec)
    [62124] = { name = "hand of reckoning", rank = 1, duration = 3 },

    --========================================================================
    -- PALADIN JUDGEMENT DEBUFFS
    -- Generic 20271 is handled specially below to detect seal type
    --========================================================================

    -- Judgement of the Crusader (10 sec, +holy damage taken)
    [21183] = { name = "judgement of the crusader", rank = 1, duration = 10 },
    [20188] = { name = "judgement of the crusader", rank = 2, duration = 10 },
    [20300] = { name = "judgement of the crusader", rank = 3, duration = 10 },
    [20301] = { name = "judgement of the crusader", rank = 4, duration = 10 },
    [20302] = { name = "judgement of the crusader", rank = 5, duration = 10 },
    [20303] = { name = "judgement of the crusader", rank = 6, duration = 10 },
    [20304] = { name = "judgement of the crusader", rank = 6, duration = 10 },  -- variant
    [25942] = { name = "judgement of the crusader", rank = 1, duration = 10 },  -- variant

    -- Judgement of Light (10 sec, heals attackers)
    [20185] = { name = "judgement of light", rank = 1, duration = 10 },
    [20344] = { name = "judgement of light", rank = 2, duration = 10 },
    [20345] = { name = "judgement of light", rank = 3, duration = 10 },
    [20346] = { name = "judgement of light", rank = 4, duration = 10 },

    -- Judgement of Wisdom (10 sec, restores mana to attackers)
    [20186] = { name = "judgement of wisdom", rank = 1, duration = 10 },
    [20354] = { name = "judgement of wisdom", rank = 2, duration = 10 },
    [20355] = { name = "judgement of wisdom", rank = 3, duration = 10 },
    [51750] = { name = "judgement of wisdom", rank = 5, duration = 10 },  -- Rank 5 cast (confirmed)
    [51751] = { name = "judgement of wisdom", rank = 4, duration = 10 },  -- Rank 4 cast
    [51752] = { name = "judgement of wisdom", rank = 5, duration = 10 },  -- debuff effect ID
    [25757] = { name = "judgement of wisdom", rank = 1, duration = 10 },  -- variant

    -- Judgement of Justice (10 sec, prevents fleeing)
    [20184] = { name = "judgement of justice", rank = 1, duration = 10 },
    [25945] = { name = "judgement of justice", rank = 2, duration = 10 },

    --========================================================================
    -- ROGUE POISONS
    --========================================================================

    -- Deadly Poison (12 sec, stacking nature DoT)
    [2818] = { name = "deadly poison", rank = 1, duration = 12 },
    [2819] = { name = "deadly poison", rank = 2, duration = 12 },
    [11353] = { name = "deadly poison", rank = 3, duration = 12 },
    [11354] = { name = "deadly poison", rank = 4, duration = 12 },
    [25349] = { name = "deadly poison", rank = 5, duration = 12 },
    [3583] = { name = "deadly poison", rank = 1, duration = 12 },   -- proc effect
    [10022] = { name = "deadly poison", rank = 2, duration = 12 },  -- proc effect
    [13582] = { name = "deadly poison", rank = 3, duration = 12 },  -- proc effect
    [21787] = { name = "deadly poison", rank = 4, duration = 12 },  -- proc effect
    [21788] = { name = "deadly poison", rank = 5, duration = 12 },  -- proc effect

    -- Crippling Poison (12 sec, -50% movement speed)
    [3409] = { name = "crippling poison", rank = 1, duration = 12 },
    [11201] = { name = "crippling poison", rank = 2, duration = 12 },
    [25809] = { name = "crippling poison", rank = 2, duration = 12 },  -- variant

    -- Wound Poison (15 sec, -healing received)
    [13218] = { name = "wound poison", rank = 1, duration = 15 },
    [13222] = { name = "wound poison", rank = 2, duration = 15 },
    [13223] = { name = "wound poison", rank = 3, duration = 15 },
    [13224] = { name = "wound poison", rank = 4, duration = 15 },
    [25648] = { name = "wound poison", rank = 5, duration = 15 },

    -- Mind-numbing Poison (10 sec, -casting speed)
    [5760] = { name = "mind-numbing poison", rank = 1, duration = 10 },
    [8692] = { name = "mind-numbing poison", rank = 2, duration = 10 },
    [11398] = { name = "mind-numbing poison", rank = 3, duration = 10 },
    [25810] = { name = "mind-numbing poison", rank = 2, duration = 10 },  -- variant

    --========================================================================
    -- THUNDERFURY PROC DEBUFFS
    --========================================================================

    -- Thunderfury - Nature Resist Reduction (12 sec, chains to 5 targets)
    [21992] = { name = "thunderfury", rank = 1, duration = 12 },
    -- Thunderfury - Attack Speed Slow (12 sec, -20% attack speed on primary target)
    [27648] = { name = "thunderfury slow", rank = 1, duration = 12 },

    --========================================================================
    -- CUSTOM/SERVER-SPECIFIC (add your own below)
    --========================================================================
    -- [12345] = { name = "custom debuff", rank = 1, duration = 18 },
}

--============================================================================
-- PALADIN JUDGEMENT SEAL DETECTION
-- Maps seal buff textures to judgement debuff names and their reference spellIDs
--============================================================================

local sealToJudgement = {
    -- Seal texture -> { name, referenceSpellID (must be in trackedCurseIds), judgementTexture }
    ["Interface\\Icons\\Spell_Holy_RighteousnessAura"] = {
        name = "judgement of wisdom",
        spellID = 20186,  -- JoW rank 1 (in our custom list)
        texture = "Interface\\Icons\\Spell_Holy_RighteousnessAura",
    },
    ["Interface\\Icons\\Spell_Holy_HealingAura"] = {
        name = "judgement of light",
        spellID = 20185,  -- JoL rank 1 (in our custom list)
        texture = "Interface\\Icons\\Spell_Holy_HealingAura",
    },
    ["Interface\\Icons\\Spell_Holy_HolySmite"] = {
        name = "judgement of the crusader",
        spellID = 21183,  -- JotC rank 1 (in our custom list)
        texture = "Interface\\Icons\\Spell_Holy_HolySmite",
    },
    ["Interface\\Icons\\Spell_Holy_SealOfWrath"] = {
        name = "judgement of justice",
        spellID = 20184,  -- JoJ rank 1 (in our custom list)
        texture = "Interface\\Icons\\Spell_Holy_SealOfWrath",
    },
    ["Interface\\Icons\\Ability_ThunderClap"] = {
        name = "judgement of righteousness",
        spellID = 20187,  -- fallback, may need correct ID
        texture = "Interface\\Icons\\Ability_ThunderClap",
    },
    ["Interface\\Icons\\Spell_Holy_SealOfMight"] = {
        name = "judgement of command",
        spellID = 20467,  -- fallback, may need correct ID
        texture = "Interface\\Icons\\Spell_Holy_SealOfMight",
    },
}

-- Detect active seal from player buffs and return judgement info
local function GetActiveSealJudgementInfo()
    for i = 1, 32 do
        local texture = GetPlayerBuffTexture(i)
        if not texture then break end
        if sealToJudgement[texture] then
            return sealToJudgement[texture]
        end
    end
    -- Fallback to generic judgement
    return { name = "judgement", spellID = 20271, texture = "Interface\\Icons\\Spell_Holy_RighteousFury" }
end

--============================================================================
-- AUTOMATIC INJECTION INTO CURSIVE
-- Hooks Cursive's LoadCurses to inject our spells after every reload
--============================================================================

local injectedCount = 0

local function InjectCustomSpells()
    if not Cursive or not Cursive.curses or not Cursive.curses.trackedCurseIds then
        return 0
    end

    local count = 0
    for spellID, data in pairs(CleveRoids.CustomCursiveSpells) do
        -- Get texture from SpellInfo (SuperWoW API)
        local name, rank, texture = SpellInfo(spellID)
        if texture then
            -- Always update/add (in case Cursive reloaded and cleared them)
            Cursive.curses.trackedCurseIds[spellID] = {
                name = data.name,
                rank = data.rank or 1,
                duration = data.duration,
                texture = texture,
                variableDuration = data.variableDuration,
                calculateDuration = data.calculateDuration,
                numTicks = data.numTicks,
                darkHarvest = data.darkHarvest,
            }
            Cursive.curses.trackedCurseNamesToTextures[data.name] = texture
            count = count + 1
        end
    end

    injectedCount = count
    return count
end

-- Hook Cursive's LoadCurses function to inject after every reload
local function HookCursiveLoadCurses()
    if not Cursive or not Cursive.curses or not Cursive.curses.LoadCurses then
        return false
    end

    -- Check if already hooked
    if Cursive.curses._customSpellsHooked then
        return true
    end

    -- Store original function
    local originalLoadCurses = Cursive.curses.LoadCurses

    -- Replace with hooked version
    Cursive.curses.LoadCurses = function(self)
        -- Call original first
        originalLoadCurses(self)

        -- Then inject our custom spells
        local count = InjectCustomSpells()
        if count > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CursiveCustomSpells]|r Injected " .. count .. " custom spells into Cursive.")
        end
    end

    Cursive.curses._customSpellsHooked = true
    return true
end

--============================================================================
-- EXTENSION REGISTRATION
--============================================================================

local ext = CleveRoids.RegisterExtension("CursiveCustomSpells")
local hooked = false
local retryFrame = nil

-- Retry injection periodically until successful
local function StartRetryTimer()
    if retryFrame then return end

    retryFrame = CreateFrame("Frame")
    local elapsed = 0
    local attempts = 0

    retryFrame:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed >= 0.5 then  -- Check every 0.5 seconds
            elapsed = 0
            attempts = attempts + 1

            if HookCursiveLoadCurses() then
                hooked = true
                InjectCustomSpells()
                retryFrame:SetScript("OnUpdate", nil)
                retryFrame = nil
            elseif attempts >= 20 then  -- Give up after 10 seconds
                retryFrame:SetScript("OnUpdate", nil)
                retryFrame = nil
            end
        end
    end)
end

ext.OnLoad = function()
    -- Try to hook immediately (Cursive might already be loaded)
    if HookCursiveLoadCurses() then
        hooked = true
        InjectCustomSpells()
    else
        -- Start retry timer and also register events as backup
        StartRetryTimer()
        ext.RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    end
end

ext.OnPlayerEnteringWorld = function()
    if not hooked then
        if HookCursiveLoadCurses() then
            hooked = true
            InjectCustomSpells()
        end
    end
    -- Don't unregister - keep checking on zone changes
end

--============================================================================
-- PALADIN JUDGEMENT HOOK
-- Intercepts generic Judgement (20271) and applies correct debuff name
--============================================================================

local JUDGEMENT_SPELL_ID = 20271
local judgementHooked = false

local function HookJudgementDetection()
    if judgementHooked then return end
    if not Cursive or not Cursive.curses then return end

    -- DO NOT register 20271 in trackedCurseIds - we handle it ourselves
    -- This prevents Cursive's native handler from creating a duplicate

    -- Register our own UNIT_CASTEVENT handler
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UNIT_CASTEVENT")
    eventFrame:SetScript("OnEvent", function()
        local casterGuid, targetGuid, event, spellID = arg1, arg2, arg3, arg4

        -- Only handle our Judgement casts
        if event ~= "CAST" or spellID ~= JUDGEMENT_SPELL_ID then return end

        -- Check if it's the player casting
        local _, playerGuid = UnitExists("player")
        if casterGuid ~= playerGuid then return end

        -- Detect which seal is active and get full judgement info
        local info = GetActiveSealJudgementInfo()

        -- Make sure the reference spellID is in trackedCurseIds
        if not Cursive.curses.trackedCurseIds[info.spellID] then
            Cursive.curses.trackedCurseIds[info.spellID] = {
                name = info.name,
                rank = 1,
                duration = 10,
                texture = info.texture,
            }
        end

        -- Apply the curse manually with the correct name
        if not Cursive.curses.guids[targetGuid] then
            Cursive.curses.guids[targetGuid] = {}
        end

        Cursive.curses.guids[targetGuid][info.name] = {
            rank = 1,
            duration = 10,
            start = GetTime(),
            spellID = info.spellID,  -- Use the seal-specific spellID
            targetGuid = targetGuid,
            currentPlayer = true,
        }

        -- Add texture mapping for display
        Cursive.curses.trackedCurseNamesToTextures[info.name] = info.texture
    end)

    judgementHooked = true
end

-- Hook judgement detection when Cursive is ready
local judgementRetryFrame = CreateFrame("Frame")
judgementRetryFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
judgementRetryFrame:SetScript("OnEvent", function()
    -- Delay slightly to ensure Cursive is fully loaded
    local elapsed = 0
    judgementRetryFrame:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed >= 1 then
            HookJudgementDetection()
            judgementRetryFrame:SetScript("OnUpdate", nil)
        end
    end)
end)

--============================================================================
-- JUDGEMENT REFRESH ON MELEE HIT
-- Judgement of Light/Wisdom refresh their duration when the Paladin hits
--============================================================================

local judgementNames = {
    ["judgement of wisdom"] = true,
    ["judgement of light"] = true,
    ["judgement of the crusader"] = true,
    ["judgement of justice"] = true,
    ["judgement of righteousness"] = true,
    ["judgement of command"] = true,
}

-- Refresh all active judgements on a target
local function RefreshJudgementsOnTarget(targetGuid)
    if not Cursive or not Cursive.curses or not Cursive.curses.guids then return end
    if not targetGuid or not Cursive.curses.guids[targetGuid] then return end

    local now = GetTime()
    for curseName, curseData in pairs(Cursive.curses.guids[targetGuid]) do
        if judgementNames[curseName] and curseData.currentPlayer then
            -- Refresh the timer
            curseData.start = now
        end
    end
end

-- Hook melee combat events for auto attacks
local meleeRefreshFrame = CreateFrame("Frame")
meleeRefreshFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
meleeRefreshFrame:SetScript("OnEvent", function()
    -- Auto attack hit patterns (vanilla WoW format)
    -- "You hit TargetName for X damage."
    -- "You crit TargetName for X damage."
    local msg = arg1
    if not msg then return end

    -- Parse target name from combat message
    local targetName = nil

    -- Pattern: "You hit TargetName for X"
    local _, _, name = string.find(msg, "^You hit (.+) for")
    if name then targetName = name end

    -- Pattern: "You crit TargetName for X"
    if not targetName then
        _, _, name = string.find(msg, "^You crit (.+) for")
        if name then targetName = name end
    end

    if not targetName then return end

    -- Check if current target matches the hit target
    local currentTargetName = UnitName("target")
    if currentTargetName and currentTargetName == targetName then
        local _, targetGuid = UnitExists("target")
        if targetGuid then
            RefreshJudgementsOnTarget(targetGuid)
        end
    end
end)

-- Hook UNIT_CASTEVENT for melee ability hits (Crusader Strike, etc.)
local meleeAbilityFrame = CreateFrame("Frame")
meleeAbilityFrame:RegisterEvent("UNIT_CASTEVENT")
meleeAbilityFrame:SetScript("OnEvent", function()
    local casterGuid, targetGuid, event, spellID = arg1, arg2, arg3, arg4

    -- Only handle CAST events (successful casts)
    if event ~= "CAST" then return end

    -- Check if it's the player casting
    local _, playerGuid = UnitExists("player")
    if casterGuid ~= playerGuid then return end

    -- Skip Judgement itself (20271) - it applies, doesn't refresh
    if spellID == JUDGEMENT_SPELL_ID then return end

    -- Only refresh for melee abilities (instant casts with target)
    -- We can't easily detect "melee only" so refresh on any successful cast on target
    if targetGuid and targetGuid ~= "" then
        RefreshJudgementsOnTarget(targetGuid)
    end
end)

--============================================================================
-- CONSOLE COMMANDS: /cleveroid cursive
--============================================================================

local originalConsoleHandler = CleveRoids.HandleConsoleCommand

CleveRoids.HandleConsoleCommand = function(msg)
    local cmd, args = string.match(msg or "", "^(%S+)%s*(.*)$")
    cmd = cmd and string.lower(cmd) or ""

    if cmd == "cursive" then
        local subcmd, subargs = string.match(args or "", "^(%S+)%s*(.*)$")
        subcmd = subcmd and string.lower(subcmd) or "list"

        if subcmd == "list" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CursiveCustomSpells]|r Custom spell list:")
            local count = 0
            for spellID, data in pairs(CleveRoids.CustomCursiveSpells) do
                local status = ""
                if Cursive and Cursive.curses and Cursive.curses.trackedCurseIds[spellID] then
                    status = " |cff00ff00[active]|r"
                else
                    status = " |cffff0000[not loaded]|r"
                end
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  [%d] %s (rank %d, %ds)%s",
                    spellID, data.name, data.rank or 1, data.duration, status))
                count = count + 1
            end
            if count == 0 then
                DEFAULT_CHAT_FRAME:AddMessage("  (none - edit CursiveCustomSpells.lua to add)")
            end
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  Hook status: %s",
                hooked and "|cff00ff00active|r" or "|cffff0000not hooked|r"))

        elseif subcmd == "add" then
            local spellID, duration, customName = string.match(subargs, "^(%d+)%s+(%d+)%s*(.*)$")
            spellID = tonumber(spellID)
            duration = tonumber(duration)

            if not spellID or not duration then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Usage:|r /cleveroid cursive add <spellID> <duration> [name]")
                return
            end

            local name, rank, texture = SpellInfo(spellID)
            if not name then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error:|r Spell ID " .. spellID .. " not found.")
                return
            end

            local spellName = customName ~= "" and string.lower(customName) or string.lower(name)

            CleveRoids.CustomCursiveSpells[spellID] = {
                name = spellName,
                rank = 1,
                duration = duration,
            }

            -- Inject immediately
            if Cursive and Cursive.curses then
                Cursive.curses.trackedCurseIds[spellID] = {
                    name = spellName,
                    rank = 1,
                    duration = duration,
                    texture = texture,
                }
                Cursive.curses.trackedCurseNamesToTextures[spellName] = texture
            end

            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CursiveCustomSpells]|r Added: [%d] %s (%ds) - will auto-track on cast",
                spellID, spellName, duration))
            DEFAULT_CHAT_FRAME:AddMessage("  Note: Edit CursiveCustomSpells.lua to make permanent.")

        elseif subcmd == "remove" then
            local spellID = tonumber(subargs)
            if not spellID then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Usage:|r /cleveroid cursive remove <spellID>")
                return
            end

            if CleveRoids.CustomCursiveSpells[spellID] then
                local name = CleveRoids.CustomCursiveSpells[spellID].name
                CleveRoids.CustomCursiveSpells[spellID] = nil

                if Cursive and Cursive.curses and Cursive.curses.trackedCurseIds[spellID] then
                    Cursive.curses.trackedCurseIds[spellID] = nil
                end

                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CursiveCustomSpells]|r Removed: [%d] %s",
                    spellID, name))
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error:|r Spell ID " .. spellID .. " not in custom list.")
            end

        elseif subcmd == "inject" then
            local count = InjectCustomSpells()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[CursiveCustomSpells]|r Injected %d spell(s).", count))

        elseif subcmd == "debugseal" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CursiveCustomSpells]|r Scanning player buffs for seals:")
            for i = 1, 32 do
                local texture = GetPlayerBuffTexture(i)
                if not texture then break end
                local match = sealToJudgement[texture] and "|cff00ff00 MATCH|r" or ""
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  [%d] %s%s", i, texture, match))
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CursiveCustomSpells]|r Known seal textures:")
            for tex, data in pairs(sealToJudgement) do
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s -> %s", tex, data.name))
            end

        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CursiveCustomSpells]|r Commands:")
            DEFAULT_CHAT_FRAME:AddMessage("  /cleveroid cursive list - Show custom spells and status")
            DEFAULT_CHAT_FRAME:AddMessage("  /cleveroid cursive add <spellID> <duration> [name]")
            DEFAULT_CHAT_FRAME:AddMessage("  /cleveroid cursive remove <spellID>")
            DEFAULT_CHAT_FRAME:AddMessage("  /cleveroid cursive inject - Force re-injection")
        end
        return
    end

    if originalConsoleHandler then
        originalConsoleHandler(msg)
    end
end

return ext
