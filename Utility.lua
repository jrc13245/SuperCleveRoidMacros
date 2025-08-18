--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {} -- redundant since we're loading first but peace of mind if another file is added top of chain


function CleveRoids.Seq(_, i)
    return (i or 0) + 1
end

-- Trims any leading or trailing white space characters from the given string
-- str: The string to trim
-- returns: The trimmed string
function CleveRoids.Trim(str)
    if not str then
        return nil
    end
    return string.gsub(str,"^%s*(.-)%s*$", "%1")
end

do
  local _G = _G or getfenv(0)
  local CleveRoids = _G.CleveRoids or {}
  _G.CleveRoids = CleveRoids

  CleveRoids.__mo = CleveRoids.__mo or { sources = {}, current = nil }

  local PRIORITY = {
    pfui    = 3,   -- unitframe hovers should win
    blizz   = 3,   -- same level as pfui
    tooltip = 1,   -- lowest; don’t stomp frames
  }

  local function getBest()
    local bestSource, bestUnit, bestP = nil, nil, -1
    for source, unit in CleveRoids.__mo.sources do
      if unit and unit ~= "" then
        local p = PRIORITY[source] or 0
        if p > bestP then
          bestP, bestSource, bestUnit = p, source, unit
        end
      end
    end
    return bestSource, bestUnit
  end

  local function apply(unit)
    -- SuperWoW path if available; otherwise internal fallback
    if CleveRoids.hasSuperwow and _G.SetMouseoverUnit then
      _G.SetMouseoverUnit(unit) -- nil clears
    else
      CleveRoids.mouseoverUnit = unit
    end
    if CleveRoids.QueueActionUpdate then CleveRoids.QueueActionUpdate() end
  end

  function CleveRoids.SetMouseoverFrom(source, unit)
    -- set/refresh a source’s unit
    if not source then return end
    CleveRoids.__mo.sources[source] = unit
    local _, bestUnit = getBest()
    if bestUnit ~= CleveRoids.__mo.current then
      CleveRoids.__mo.current = bestUnit
      apply(bestUnit)
    end
  end

  function CleveRoids.ClearMouseoverFrom(source, unitIfMatch)
    if not source then return end
    if unitIfMatch and CleveRoids.__mo.sources[source] ~= unitIfMatch then
      return -- don’t clear if it was replaced meanwhile
    end
    CleveRoids.__mo.sources[source] = nil
    local _, bestUnit = getBest()
    if bestUnit ~= CleveRoids.__mo.current then
      CleveRoids.__mo.current = bestUnit
      apply(bestUnit)
    end
  end
end

-- TODO: Get rid of one Split function.  CleveRoids.splitString is ~10% slower
function CleveRoids.Split(s, p, trim)
    local r, o = {}, 1

    if not p or p == "" then
        if trim then
            s = CleveRoids.Trim(s)
        end
        for i = 1, string.len(s) do
            table.insert(r, string.sub(s, i, 1))
        end
        return r
    end

    repeat
        local b, e = string.find(s, p, o)
        if b == nil then
            local sub = string.sub(s, o)
            table.insert(r, trim and CleveRoids.Trim(sub) or sub)
            return r
        end
        if b > 1 then
            local sub = string.sub(s, o, b - 1)
            table.insert(r, trim and CleveRoids.Trim(sub) or sub)
        else
            table.insert(r, "")
        end
        o = e + 1
    until false
end

-- Splits the given string into a list of sub-strings
-- str: The string to split
-- seperatorPattern: The seperator between sub-string. May contain patterns
-- returns: A list of sub-strings
function CleveRoids.splitString(str, seperatorPattern)
    local tbl = {}
    if not str then
        return tbl
    end
    local pattern = "(.-)" .. seperatorPattern
    local lastEnd = 1
    local s, e, cap = string.find(str, pattern, 1)

    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(tbl,cap)
        end
        lastEnd = e + 1
        s, e, cap = string.find(str, pattern, lastEnd)
    end

    if lastEnd <= string.len(str) then
        cap = string.sub(str, lastEnd)
        table.insert(tbl, cap)
    end

    return tbl
end

function CleveRoids.splitStringIgnoringQuotes(str, separator)
    local result = {}
    local temp = ""
    local insideQuotes = false
    local separators = {}

    if type(separator) == "table" then
        for _, s in separator do
            separators[s] = s
        end
    else
        separators[separator or ";"] = separator or ";"
    end

    for i = 1, string.len(str) do
        local char = string.sub(str, i, i)

        if char == "\"" then
            insideQuotes = not insideQuotes
            temp = temp .. char
        elseif char == separators[char] and not insideQuotes then
            temp = CleveRoids.Trim(temp)
            if temp ~= "" then table.insert(result, temp) end
            temp = ""
        else
            temp = temp .. char
        end
    end

    -- Add the last segment if it exists
    if temp ~= "" then
        temp = CleveRoids.Trim(temp)
        table.insert(result, temp)
    end

    -- if nothing was found, return the empty string
    return (next(result) and result or {""})
end

-- Prints all the given arguments into WoW's default chat frame
function CleveRoids.Print(...)
    local c = "|cFF4477FFCleveR|r|cFFFFFFFFoid :: |r"
    local out = ""

    for i=1, arg.n, 1 do
        out = out..tostring(arg[i]).."  "
    end
    if WowLuaFrameOutput then
        WowLuaFrameOutput:AddMessage(out)
    else
        if not DEFAULT_CHAT_FRAME:IsVisible() then
            FCF_SelectDockFrame(DEFAULT_CHAT_FRAME)
        end
        DEFAULT_CHAT_FRAME:AddMessage(c..out)
    end
end

function CleveRoids.PrintI(msg, depth)
    depth = depth or 0
    msg = string.rep("    ", depth) .. tostring(msg)
    CleveRoids.Print(msg)
end

function CleveRoids.PrintT(t, depth)
    depth = depth or 0
    local cs = "|cffc8c864"
    local ce = "|r"

    if t == nil or type(t) ~= "table" then
        CleveRoids.PrintI(t, depth)
    else
        for k, v in pairs(t) do
            if type(v) == "table" then
                CleveRoids.PrintI(cs..tostring(k)..":"..ce.." <TABLE>", depth)
                CleveRoids.PrintT(v, depth + 1)
            else
                CleveRoids.PrintI(cs..tostring(k)..ce..": "..tostring(v), depth)
            end
        end
    end
end

CleveRoids.kmods = {
    ctrl  = IsControlKeyDown,
    alt   = IsAltKeyDown,
    shift = IsShiftKeyDown,
    mod   = function() return (IsControlKeyDown() or IsAltKeyDown() or IsShiftKeyDown()) end,
    nomod = function() return (not IsControlKeyDown() and not IsAltKeyDown() and not IsShiftKeyDown()) end,
}

CleveRoids.operators = {
    ["<"] = "lt",
    ["lt"] = "<",
    [">"] = "gt",
    ["gt"] = ">",
    ["="] = "eq",
    ["eq"] = "=",
    ["<="] = "lte",
    ["lte"] = "<=",
    [">="] = "gte",
    ["gte"] = ">=",
    ["~="] = "ne",
    ["ne"] = "~=",
}

CleveRoids.comparators = {
    lt  = function(a, b) return (a <  b) end,
    gt  = function(a, b) return (a >  b) end,
    eq  = function(a, b) return (a == b) end,
    lte = function(a, b) return (a <= b) end,
    gte = function(a, b) return (a >= b) end,
    ne  = function(a, b) return (a ~= b) end,
}
CleveRoids.comparators["<"]  = CleveRoids.comparators.lt
CleveRoids.comparators[">"]  = CleveRoids.comparators.gt
CleveRoids.comparators["="]  = CleveRoids.comparators.eq
CleveRoids.comparators["<="] = CleveRoids.comparators.lte
CleveRoids.comparators[">="] = CleveRoids.comparators.gte
CleveRoids.comparators["~="] = CleveRoids.comparators.ne


_G["CleveRoids"] = CleveRoids
