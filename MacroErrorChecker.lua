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
    channeling = true, nochanneling = true,
    class = true, noclass = true,
    cdgcd = true, nocdgcd = true,
    combo = true, nocombo = true,
    cooldown = true, nocooldown = true,
    equipped = true, noequipped = true,
    form = true, noform = true,
    group = true,
    known = true, noknown = true,
    mod = true, nomod = true,
    mybuff = true, nomybuff = true,
    mydebuff = true, nomydebuff = true,
    myhp = true,
    myhplost = true,
    mypower = true,
    mypowerlost = true,
    myrawhp = true,
    myrawpower = true,
    pet = true, nopet = true,
    reactive = true, noreactive = true,
    resting = true, noresting = true,
    stance = true, nostance = true,
    stat = true,
    stealth = true, nostealth = true,
    swimming = true, noswimming = true,
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
    hp = true,
    hplost = true,
    inrange = true, noinrange = true,
    isnpc = true,
    isplayer = true,
    member = true,
    party = true, noparty = true,
    power = true,
    powerlost = true,
    raid = true, noraid = true,
    rawhp = true,
    rawpower = true,
    type = true, notype = true,
    targeting = true, notargeting = true,
    exists = true, noexists = true,
    onswingpending = true, noonswingpending = true,
    mybuffcount = true, nomybuffcount = true,
    mhimbue = true, nomhimbue = true,
    ohimbue = true, noohimbue = true,
}

-- Known valid commands
local VALID_COMMANDS = {
    ["/cast"] = true,
    ["/castpet"] = true,
    ["/cancelaura"] = true,
    ["/castsequence"] = true,
    ["/equip"] = true,
    ["/equipmh"] = true,
    ["/equipoh"] = true,
    ["/focus"] = true,
    ["/petattack"] = true,
    ["/petfollow"] = true,
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
    ["/target"] = true,
    ["/unqueue"] = true,
    ["/use"] = true,
    ["/unbuff"] = true,
    ["/unshift"] = true,
    ["/retarget"] = true,
    ["/macrocheck"] = true,
    ["/s"] = true,
    ["/y"] = true,
    ["/r"] = true,
    ["/bg"] = true,
    ["/e"] = true,
    ["/w"] = true,
    ["/g"] = true,
    ["/p"] = true,
    ["/invite"] = true,
    ["/trade"] = true,
    ["/db"] = true,
    ["/roll"] = true,
    ["/bow"] = true,
    ["/qh"] = true,
    ["/rinse"] = true,
    ["/am"] = true,
    ["/aux"] = true,
    ["/instancetimers"] = true,
    ["/umacro"] = true,
    ["/camp"] = true,
    ["/logout"] = true,
    ["/exit"] = true,
    ["/promote"] = true,
}

-- Commands that can have conditionals without actions
-- e.g., /petattack [harm] or /target [exists,hp:<=20]
local COMMANDS_NO_ACTION_NEEDED = {
    ["/petattack"] = true,
    ["/petfollow"] = true,
    ["/petwait"] = true,
    ["/petpassive"] = true,
    ["/petaggressive"] = true,
    ["/petdefensive"] = true,
    ["/target"] = true,
    ["/focus"] = true,
    ["/startattack"] = true,
    ["/stopattack"] = true,
    ["/stopcasting"] = true,
    ["/unqueue"] = true,
    ["/retarget"] = true,
    ["/stopmacro"] = true,
    ["/unshift"] = true,
}

-- Safe string operations to prevent addon errors from malformed macros
local function safeStringSub(str, startPos, endPos)
    if not str or type(str) ~= "string" then return "" end
    local len = string.len(str)
    if startPos < 1 then startPos = 1 end
    if endPos and endPos > len then endPos = len end
    return string.sub(str, startPos, endPos)
end

local function safeStringFind(str, pattern, init)
    if not str or type(str) ~= "string" then return nil end
    local success, result1, result2, result3 = pcall(string.find, str, pattern, init)
    if success then
        return result1, result2, result3
    end
    return nil
end

local function safeStringLen(str)
    if not str or type(str) ~= "string" then return 0 end
    return string.len(str)
end

local function safeTrim(str)
    if not str or type(str) ~= "string" then return "" end
    local success, result = pcall(CleveRoids.Trim, str)
    if success then return result end
    return str
end

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
    if not text or type(text) ~= "string" then return true end

    local openCount = 0
    local inQuotes = false
    local len = safeStringLen(text)

    for i = 1, len do
        local char = safeStringSub(text, i, i)
        if not char or char == "" then break end

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
    if not text or type(text) ~= "string" then return true end

    local quoteCount = 0
    local escaped = false
    local len = safeStringLen(text)

    for i = 1, len do
        local char = safeStringSub(text, i, i)
        if not char or char == "" then break end

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

    if not conditional or conditional == "" then
        return errors
    end

    -- Check if conditional is valid
    local baseCond = string.lower(safeTrim(conditional))
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
    if args and type(args) == "string" then
        local hasHpOrPower = safeStringFind(baseCond, "hp") or safeStringFind(baseCond, "power") or
                            safeStringFind(baseCond, "combo") or baseCond == "stat"
        if hasHpOrPower then
            local hasOperator = safeStringFind(args, "[<>=~]+")
            if args ~= "" and not hasOperator and not safeStringFind(args, "^%d+$") then
                -- Might be missing operator
                if not safeStringFind(args, "[a-zA-Z]") then
                    table.insert(errors, {
                        type = ERROR_TYPES.INVALID_OPERATOR,
                        conditional = conditional,
                        message = conditional .. " may need an operator (>, <, =, >=, <=)"
                    })
                end
            end
        end
    end

    return errors
end

-- Parse and validate a single line
local function validateLine(line, lineNum)
    local errors = {}

    -- Skip comments and empty lines
    if not line or type(line) ~= "string" then
        return errors
    end

    line = safeTrim(line)
    if line == "" or safeStringSub(line, 1, 2) == "--" then
        return errors
    end

    -- Check for # directives - only #showtooltip is valid
    if safeStringSub(line, 1, 1) == "#" then
        local _, _, directive = safeStringFind(line, "^(#[a-z]+)")
        if directive then
            local lowerDirective = string.lower(directive)
            if lowerDirective ~= "#showtooltip" then
                table.insert(errors, {
                    type = ERROR_TYPES.INVALID_COMMAND,
                    line = lineNum,
                    command = directive,
                    message = "Unknown directive: " .. directive .. " (did you mean #showtooltip?)"
                })
            end
        end
        -- Valid #showtooltip or other # lines are skipped from further validation
        return errors
    end

    -- Wrap the entire validation in pcall to catch any unexpected errors
    local success, result = pcall(function()
        local localErrors = {}

        -- Check for valid command
        local _, _, cmd = safeStringFind(line, "^(/[a-z]+)")
        if cmd then
            local lowerCmd = string.lower(cmd)
            if not VALID_COMMANDS[lowerCmd] then
                table.insert(localErrors, {
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
            table.insert(localErrors, {
                type = ERROR_TYPES.MISMATCHED_BRACKETS,
                line = lineNum,
                message = bracketError or "Bracket mismatch"
            })
        end

        -- Check quotes
        local quotesOk, quoteError = checkQuotes(line)
        if not quotesOk then
            table.insert(localErrors, {
                type = ERROR_TYPES.MALFORMED_QUOTES,
                line = lineNum,
                message = quoteError or "Quote mismatch"
            })
        end

        -- Split by semicolons to handle multiple actions per line
        local actions = CleveRoids.splitStringIgnoringQuotes(line, ";")
        if not actions then
            return localErrors
        end

        for _, actionPart in ipairs(actions) do
            actionPart = safeTrim(actionPart)
            if actionPart ~= "" and safeStringSub(actionPart, 1, 1) ~= "/" then
                actionPart = "/" .. actionPart  -- Add leading slash if missing after split
            end

            -- Parse conditionals if present - use non-greedy match
            local condStart = safeStringFind(actionPart, "%[")
            local condEnd = nil
            local conditionBlock = nil

            if condStart then
                -- Find matching closing bracket
                local depth = 0
                local inQuotes = false
                local len = safeStringLen(actionPart)

                for i = condStart, len do
                    local char = safeStringSub(actionPart, i, i)
                    if not char or char == "" then break end

                    if char == '"' then
                        inQuotes = not inQuotes
                    elseif not inQuotes then
                        if char == "[" then
                            depth = depth + 1
                        elseif char == "]" then
                            depth = depth - 1
                            if depth == 0 then
                                condEnd = i
                                conditionBlock = safeStringSub(actionPart, condStart + 1, i - 1)
                                break
                            end
                        end
                    end
                end
            end

            if conditionBlock then
                if safeTrim(conditionBlock) == "" then
                    table.insert(localErrors, {
                        type = ERROR_TYPES.EMPTY_CONDITIONAL,
                        line = lineNum,
                        message = "Empty conditional block []"
                    })
                else
                    -- Check for invalid @ target syntax
                    local _, _, target = safeStringFind(conditionBlock, "(@[^%s,]+)")
                    if target and not safeStringFind(target, "^@[a-z]+%d*") then
                        table.insert(localErrors, {
                            type = ERROR_TYPES.INVALID_TARGET,
                            line = lineNum,
                            message = "Invalid target: " .. target
                        })
                    end

                    -- Parse individual conditionals
                    local condGroups = CleveRoids.splitStringIgnoringQuotes(conditionBlock, {",", " "})
                    if condGroups then
                        for _, condGroup in condGroups do
                            if condGroup ~= "" and condGroup ~= target then
                                local parts = CleveRoids.splitStringIgnoringQuotes(condGroup, ":")
                                if parts then
                                    local cond = string.lower(safeTrim(parts[1] or ""))
                                    local args = safeTrim(parts[2] or "")

                                    if cond ~= "" then
                                        -- Validate the conditional
                                        local condErrors = validateConditional(cond, args, nil)
                                        for _, err in condErrors do
                                            err.line = lineNum
                                            table.insert(localErrors, err)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                -- Check for action after conditionals
                -- Extract the command from this action part
                local _, _, cmdFromAction = safeStringFind(actionPart, "^(/[a-z]+)")
                local needsAction = true

                if cmdFromAction then
                    local lowerCmdFromAction = string.lower(cmdFromAction)
                    if COMMANDS_NO_ACTION_NEEDED[lowerCmdFromAction] then
                        needsAction = false
                    end
                end

                if needsAction then
                    local afterCond = safeStringSub(actionPart, (condEnd or 0) + 1)
                    local _, _, action = safeStringFind(afterCond, "^%s*[!~?]?(.+)")
                    if not action or safeTrim(action) == "" then
                        table.insert(localErrors, {
                            type = ERROR_TYPES.EMPTY_ACTION,
                            line = lineNum,
                            message = "Conditional has no action"
                        })
                    end
                end
            end
        end

        return localErrors
    end)

    if success and result then
        return result
    elseif not success then
        -- An error occurred during validation
        return {{
            type = "VALIDATION_ERROR",
            line = lineNum,
            message = "Internal error validating line: " .. tostring(result)
        }}
    end

    return errors
end

-- Validate an entire macro
function CleveRoids.ValidateMacro(macroName)
    -- Wrap entire function in pcall for safety
    local success, result = pcall(function()
        local errors = {}

        if not macroName or macroName == "" then
            return {{
                type = "ERROR",
                message = "No macro name provided"
            }}
        end

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
        if not lines then
            return {{
                type = "ERROR",
                message = "Failed to parse macro body"
            }}
        end

        for lineNum, line in ipairs(lines) do
            local lineErrors = validateLine(line, lineNum)
            if lineErrors then
                for _, err in lineErrors do
                    table.insert(errors, err)
                end
            end
        end

        return errors
    end)

    if success then
        return result
    else
        -- Return a safe error message if validation itself fails
        return {{
            type = "CRITICAL_ERROR",
            message = "Critical error validating macro: " .. tostring(result)
        }}
    end
end

-- Validate all macros
function CleveRoids.ValidateAllMacros()
    local results = {}
    local totalErrors = 0

    -- Account-wide macros are indexed from 1 up to GetNumMacros().
    -- Character-specific macros occupy the slots immediately following the account-wide ones.
    -- In Classic clients, the macro UI has 18 General (Account) slots and 18 Character-Specific slots.
    local numAccountMacros = GetNumMacros()

    -- The WoW API GetMacroInfo(index) supports indexing up to 36 (1-18 for General, 19-36 for Character)
    -- in Classic clients, even though the total is GetNumMacros() + GetNumCharacterMacros() in Retail.
    -- To ensure we check all 36 possible slots:
    local totalSlots = 36

    for i = 1, totalSlots do
        local nameSuccess, name = pcall(GetMacroInfo, i)

        -- Check if GetMacroInfo returned a name (i.e., the slot is used)
        if nameSuccess and name and name ~= "" then
            -- Wrap each macro validation in pcall so one bad macro doesn't stop all validation
            local errorsSuccess, errors = pcall(CleveRoids.ValidateMacro, name)

            if errorsSuccess and errors and table.getn(errors) > 0 then
                results[name] = errors
                totalErrors = totalErrors + table.getn(errors)
            end
        end
    end

    return results, totalErrors
end

-- Print errors for a macro
function CleveRoids.PrintMacroErrors(macroName)
    local success, errors = pcall(CleveRoids.ValidateMacro, macroName)

    if not success then
        CleveRoids.Print("|cffff0000Error|r: Failed to validate macro '" .. tostring(macroName) .. "': " .. tostring(errors))
        return
    end

    if not errors or table.getn(errors) == 0 then
        CleveRoids.Print("|cff00ff00✓|r Macro '" .. macroName .. "' has no syntax errors")
        return
    end

    CleveRoids.Print("|cffff0000✗|r Macro '" .. macroName .. "' has " .. table.getn(errors) .. " error(s):")

    for _, err in errors do
        if err and err.message then
            local line = err.line and ("Line " .. err.line .. ": ") or ""
            local msg = "|cffffaa00" .. line .. "|r" .. err.message
            pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, "  " .. msg)
        end
    end
end

-- Print all macro errors
function CleveRoids.PrintAllMacroErrors()
    local success, results, totalErrors = pcall(CleveRoids.ValidateAllMacros)

    if not success then
        CleveRoids.Print("|cffff0000Error|r: Failed to validate macros: " .. tostring(results))
        return
    end

    if totalErrors == 0 then
        CleveRoids.Print("|cff00ff00✓|r All macros are error-free!")
        return
    end

    local macroCount = 0
    for _ in pairs(results) do macroCount = macroCount + 1 end

    CleveRoids.Print("|cffff0000Found " .. totalErrors .. " error(s) in " .. macroCount .. " macro(s):|r")

    for macroName, errors in pairs(results) do
        if macroName and errors then
            pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, " ")
            pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, "|cffff8800" .. macroName .. "|r (" .. table.getn(errors) .. " error(s)):")

            for _, err in errors do
                if err and err.message then
                    local line = err.line and ("Line " .. err.line .. ": ") or ""
                    local msg = "  |cffffaa00" .. line .. "|r" .. err.message
                    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, msg)
                end
            end
        end
    end
end

-- Slash command
SLASH_MACROCHECK1 = "/macrocheck"
SlashCmdList.MACROCHECK = function(msg)
    local success, result = pcall(function()
        msg = safeTrim(msg or "")

        if msg == "" or msg == "all" then
            CleveRoids.PrintAllMacroErrors()
        else
            CleveRoids.PrintMacroErrors(msg)
        end
    end)

    if not success then
        CleveRoids.Print("|cffff0000Error|r: Macro check failed: " .. tostring(result))
    end
end

CleveRoids.Print("Macro syntax checker loaded. Use /macrocheck [macroname] or /macrocheck all")
