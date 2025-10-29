--[[
	Macro Syntax Error Checker
	Author: Mewtiny
	License: MIT License

	Validates macro syntax and reports errors to help users debug their macros
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

-- Known valid conditionals
local VALID_CONDITIONALS = {
    -- General
    actionbar = true, noactionbar = true,
    button = true,
    channeling = true, nochanneling = true,
    class = true, noclass = true,
    cdgcd = true, nocdgcd = true,
    combo = true, nocombo = true,
    cooldown = true, nocooldown = true,
    equipped = true, noequipped = true,
    flyable = true, noflyable = true,
    flying = true, noflying = true,
    form = true, noform = true,
    group = true, nogroup = true,
    indoors = true, noindoors = true,
    known = true, noknown = true,
    mod = true, nomod = true,
    mounted = true, nomounted = true,
    mybuff = true, nomybuff = true,
    mydebuff = true, nomydebuff = true,
    myhp = true, nomyhp = true,
    myhplost = true, nomyhplost = true,
    mypower = true, nomypower = true,
    mypowerlost = true, nomypowerlost = true,
    myrawhp = true, nomyrawhp = true,
    myrawpower = true, nomyrawpower = true,
    outdoors = true, nooutdoors = true,
    pet = true, nopet = true,
    petbuff = true, nopetbuff = true,
    petdebuff = true, nopetdebuff = true,
    reactive = true, noreactive = true,
    resting = true, noresting = true,
    stance = true, nostance = true,
    stat = true, nostat = true,
    stealth = true, nostealth = true,
    swimming = true, noswimming = true,
    talent = true, notalent = true,
    zone = true, nozone = true,

    -- Unit based
    alive = true, noalive = true,
    buff = true, nobuff = true,
    casting = true, nocasting = true,
    combat = true, nocombat = true,
    dead = true, nodead = true,
    debuff = true, nodebuff = true,
    harm = true, noharm = true,
    help = true, nohelp = true,
    hp = true, nohp = true,
    hplost = true, nohplost = true,
    inrange = true, noinrange = true,
    isnpc = true, noisnpc = true,
    isplayer = true, noisplayer = true,
    member = true, nomember = true,
    party = true, noparty = true,
    power = true, nopower = true,
    powerlost = true, nopowerlost = true,
    raid = true, noraid = true,
    rawhp = true, norawhp = true,
    rawpower = true, norawpower = true,
    type = true, notype = true,
    targeting = true, notargeting = true,
    exists = true, noexists = true,
}

-- Known valid commands
local VALID_COMMANDS = {
    ["/cast"] = true,
    ["/castpet"] = true,
    ["/cancelaura"] = true,
    ["/cancelform"] = true,
    ["/castsequence"] = true,
    ["/castrandom"] = true,
    ["/changeactionbar"] = true,
    ["/clearfocus"] = true,
    ["/cleartarget"] = true,
    ["/click"] = true,
    ["/dismount"] = true,
    ["/equip"] = true,
    ["/equipmh"] = true,
    ["/equipoh"] = true,
    ["/equipslot"] = true,
    ["/focus"] = true,
    ["/petattack"] = true,
    ["/petfollow"] = true,
    ["/petstay"] = true,
    ["/petwait"] = true,
    ["/petpassive"] = true,
    ["/petaggressive"] = true,
    ["/petdefensive"] = true,
    ["/print"] = true,
    ["/run"] = true,
    ["/runmacro"] = true,
    ["/script"] = true,
    ["/startattack"] = true,
    ["/stopattack"] = true,
    ["/stopcasting"] = true,
    ["/stopmacro"] = true,
    ["/stopspelltarget"] = true,
    ["/swapactionbar"] = true,
    ["/target"] = true,
    ["/targetenemy"] = true,
    ["/targetfriend"] = true,
    ["/targetlastenemy"] = true,
    ["/targetlastfriend"] = true,
    ["/targetlasttarget"] = true,
    ["/targetparty"] = true,
    ["/targetraid"] = true,
    ["/unqueue"] = true,
    ["/use"] = true,
    ["/userandom"] = true,
    ["/unbuff"] = true,
    ["/unshift"] = true,
    ["/retarget"] = true,
}

-- Error types
local ERROR_TYPES = {
    INVALID_CONDITIONAL = "Invalid conditional",
    MISMATCHED_BRACKETS = "Mismatched brackets",
    EMPTY_CONDITIONAL = "Empty conditional block",
    INVALID_OPERATOR = "Invalid operator",
    MISSING_ARGUMENT = "Missing argument",
    INVALID_COMMAND = "Unknown command",
    INVALID_TARGET = "Invalid target format",
    MALFORMED_QUOTES = "Malformed quotes",
    EMPTY_ACTION = "Empty action",
    INVALID_SYNTAX = "Invalid syntax",
}

CleveRoids.MacroErrors = {}

-- Check if a string has balanced brackets
local function checkBrackets(text)
    local openCount = 0
    local inQuotes = false

    for i = 1, string.len(text) do
        local char = string.sub(text, i, i)

        if char == '"' then
            inQuotes = not inQuotes
        elseif not inQuotes then
            if char == "[" then
                openCount = openCount + 1
            elseif char == "]" then
                openCount = openCount - 1
                if openCount < 0 then
                    return false, "Extra closing bracket"
                end
            end
        end
    end

    if openCount > 0 then
        return false, "Missing closing bracket"
    elseif openCount < 0 then
        return false, "Extra closing bracket"
    end

    return true
end

-- Check if quotes are balanced
local function checkQuotes(text)
    local quoteCount = 0
    local escaped = false

    for i = 1, string.len(text) do
        local char = string.sub(text, i, i)

        if escaped then
            escaped = false
        elseif char == "\\" then
            escaped = true
        elseif char == '"' then
            quoteCount = quoteCount + 1
        end
    end

    local quotient = math.floor(quoteCount / 2)
    if (quoteCount - (quotient * 2)) ~= 0 then
        return false, "Unmatched quotes"
    end

    return true
end

-- Validate conditional syntax
local function validateConditional(conditional, args, action)
    local errors = {}

    -- Check if conditional is valid
    local baseCond = string.lower(conditional)
    if not VALID_CONDITIONALS[baseCond] then
        table.insert(errors, {
            type = ERROR_TYPES.INVALID_CONDITIONAL,
            conditional = conditional,
            message = "Unknown conditional: " .. conditional
        })
    end

    -- Check for required arguments
    local needsArgs = {
        combo = true,
        hp = true, myhp = true, rawhp = true, myrawhp = true,
        power = true, mypower = true, rawpower = true, myrawpower = true,
        hplost = true, myhplost = true,
        powerlost = true, mypowerlost = true,
        stat = true,
        talent = true,
        actionbar = true,
        button = true,
        form = true, stance = true,
    }

    if needsArgs[baseCond] and (not args or args == "") and (not action or action == "") then
        table.insert(errors, {
            type = ERROR_TYPES.MISSING_ARGUMENT,
            conditional = conditional,
            message = conditional .. " requires an argument"
        })
    end

    -- Check operator syntax for numeric comparisons
    if args and string.find(baseCond, "hp") or string.find(baseCond, "power") or
       string.find(baseCond, "combo") or baseCond == "stat" then
        local hasOperator = string.find(args, "[<>=~]+")
        if args ~= "" and not hasOperator and not string.find(args, "^%d+$") then
            -- Might be missing operator
            if not string.find(args, "[a-zA-Z]") then
                table.insert(errors, {
                    type = ERROR_TYPES.INVALID_OPERATOR,
                    conditional = conditional,
                    message = conditional .. " may need an operator (>, <, =, >=, <=)"
                })
            end
        end
    end

    return errors
end

-- Parse and validate a single line
local function validateLine(line, lineNum)
    local errors = {}

    -- Skip comments and empty lines
    line = CleveRoids.Trim(line)
    if line == "" or string.sub(line, 1, 2) == "--" or string.sub(line, 1, 1) == "#" then
        return errors
    end

    -- Check for valid command
    local _, _, cmd = string.find(line, "^(/[a-z]+)")
    if cmd then
        local lowerCmd = string.lower(cmd)
        if not VALID_COMMANDS[lowerCmd] then
            table.insert(errors, {
                type = ERROR_TYPES.INVALID_COMMAND,
                line = lineNum,
                command = cmd,
                message = "Unknown command: " .. cmd
            })
        end
    end

    -- Check brackets
    local bracketsOk, bracketError = checkBrackets(line)
    if not bracketsOk then
        table.insert(errors, {
            type = ERROR_TYPES.MISMATCHED_BRACKETS,
            line = lineNum,
            message = bracketError
        })
    end

    -- Check quotes
    local quotesOk, quoteError = checkQuotes(line)
    if not quotesOk then
        table.insert(errors, {
            type = ERROR_TYPES.MALFORMED_QUOTES,
            line = lineNum,
            message = quoteError
        })
    end

    -- Split by semicolons to handle multiple actions per line
    local actions = CleveRoids.splitStringIgnoringQuotes(line, ";")

    for _, actionPart in ipairs(actions) do
        actionPart = CleveRoids.Trim(actionPart)
        if actionPart ~= "" and string.sub(actionPart, 1, 1) ~= "/" then
            actionPart = "/" .. actionPart  -- Add leading slash if missing after split
        end

        -- Parse conditionals if present - use non-greedy match
        local condStart = string.find(actionPart, "%[")
        local condEnd = nil
        local conditionBlock = nil

        if condStart then
            -- Find matching closing bracket
            local depth = 0
            local inQuotes = false
            for i = condStart, string.len(actionPart) do
                local char = string.sub(actionPart, i, i)
                if char == '"' then
                    inQuotes = not inQuotes
                elseif not inQuotes then
                    if char == "[" then
                        depth = depth + 1
                    elseif char == "]" then
                        depth = depth - 1
                        if depth == 0 then
                            condEnd = i
                            conditionBlock = string.sub(actionPart, condStart + 1, i - 1)
                            break
                        end
                    end
                end
            end
        end

        if conditionBlock then
            if CleveRoids.Trim(conditionBlock) == "" then
                table.insert(errors, {
                    type = ERROR_TYPES.EMPTY_CONDITIONAL,
                    line = lineNum,
                    message = "Empty conditional block []"
                })
            else
                -- Check for invalid @ target syntax
                local _, _, target = string.find(conditionBlock, "(@[^%s,]+)")
                if target and not string.find(target, "^@[a-z]+%d*") then
                    table.insert(errors, {
                        type = ERROR_TYPES.INVALID_TARGET,
                        line = lineNum,
                        message = "Invalid target: " .. target
                    })
                end

                -- Parse individual conditionals
                for _, condGroup in CleveRoids.splitStringIgnoringQuotes(conditionBlock, {",", " "}) do
                    if condGroup ~= "" and condGroup ~= target then
                        local parts = CleveRoids.splitStringIgnoringQuotes(condGroup, ":")
                        local cond = string.lower(CleveRoids.Trim(parts[1] or ""))
                        local args = CleveRoids.Trim(parts[2] or "")

                        if cond ~= "" then
                            -- Validate the conditional
                            local condErrors = validateConditional(cond, args, nil)
                            for _, err in condErrors do
                                err.line = lineNum
                                table.insert(errors, err)
                            end
                        end
                    end
                end
            end

            -- Check for action after conditionals
            local afterCond = string.sub(actionPart, (condEnd or 0) + 1)
            local _, _, action = string.find(afterCond, "^%s*[!~?]?(.+)")
            if not action or CleveRoids.Trim(action) == "" then
                table.insert(errors, {
                    type = ERROR_TYPES.EMPTY_ACTION,
                    line = lineNum,
                    message = "Conditional has no action"
                })
            end
        end
    end

    return errors
end

-- Validate an entire macro
function CleveRoids.ValidateMacro(macroName)
    local errors = {}
    local macroID = GetMacroIndexByName(macroName)

    if not macroID or macroID == 0 then
        return {{
            type = "ERROR",
            message = "Macro not found: " .. tostring(macroName)
        }}
    end

    local name, texture, body = GetMacroInfo(macroID)
    if not body or body == "" then
        return {{
            type = "ERROR",
            message = "Macro is empty"
        }}
    end

    -- Split into lines
    local lines = CleveRoids.splitString(body, "\n")

    for lineNum, line in ipairs(lines) do
        local lineErrors = validateLine(line, lineNum)
        for _, err in lineErrors do
            table.insert(errors, err)
        end
    end

    return errors
end

-- Validate all macros
function CleveRoids.ValidateAllMacros()
    local results = {}
    local totalErrors = 0

    local numMacros = GetNumMacros()
    for i = 1, numMacros do
        local name = GetMacroInfo(i)
        if name then
            local errors = CleveRoids.ValidateMacro(name)
            if errors and table.getn(errors) > 0 then
                results[name] = errors
                totalErrors = totalErrors + table.getn(errors)
            end
        end
    end

    return results, totalErrors
end

-- Print errors for a macro
function CleveRoids.PrintMacroErrors(macroName)
    local errors = CleveRoids.ValidateMacro(macroName)

    if not errors or table.getn(errors) == 0 then
        CleveRoids.Print("|cff00ff00✓|r Macro '" .. macroName .. "' has no syntax errors")
        return
    end

    CleveRoids.Print("|cffff0000✗|r Macro '" .. macroName .. "' has " .. table.getn(errors) .. " error(s):")

    for _, err in errors do
        local line = err.line and ("Line " .. err.line .. ": ") or ""
        local msg = "|cffffaa00" .. line .. "|r" .. err.message
        DEFAULT_CHAT_FRAME:AddMessage("  " .. msg)
    end
end

-- Print all macro errors
function CleveRoids.PrintAllMacroErrors()
    local results, totalErrors = CleveRoids.ValidateAllMacros()

    if totalErrors == 0 then
        CleveRoids.Print("|cff00ff00✓|r All macros are error-free!")
        return
    end

    CleveRoids.Print("|cffff0000Found " .. totalErrors .. " error(s) in " .. table.getn(results) .. " macro(s):|r")

    for macroName, errors in pairs(results) do
        DEFAULT_CHAT_FRAME:AddMessage(" ")
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800" .. macroName .. "|r (" .. table.getn(errors) .. " error(s)):")

        for _, err in errors do
            local line = err.line and ("Line " .. err.line .. ": ") or ""
            local msg = "  |cffffaa00" .. line .. "|r" .. err.message
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        end
    end
end

-- Slash command
SLASH_MACROCHECK1 = "/macrocheck"
SlashCmdList.MACROCHECK = function(msg)
    msg = CleveRoids.Trim(msg or "")

    if msg == "" or msg == "all" then
        CleveRoids.PrintAllMacroErrors()
    else
        CleveRoids.PrintMacroErrors(msg)
    end
end

CleveRoids.Print("Macro syntax checker loaded. Use /macrocheck [macroname] or /macrocheck all")
