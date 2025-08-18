--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

-- A list of all registered extensions
CleveRoids.Extensions = CleveRoids.Extensions or {}

-- Calls the "OnLoad" function of every extension
function CleveRoids.InitializeExtensions()
    for k, v in pairs(CleveRoids.Extensions) do
        local func = v["OnLoad"]
        if not func then
            CleveRoids.Print("CleveRoids.InitializeExtensions - Couldn't find 'OnLoad' function for extension "..k)
        else
            func()
        end
    end
end

-- Removes the given hook
-- hook: The hook to remove
function CleveRoids.RemoveHook(hook)
    _G[hook.name] = hook.original
end

-- Removes the given hook from the given object
-- object: The object to remove the hook from
-- hook: The hook to remove
function CleveRoids.RemoveMethodHook(object, hook)
    object[hook.name] = hook.original
end

-- Clears all previously declared hooks
function CleveRoids.ClearHooks()
    for k, v in pairs(CleveRoids.Extensions) do
        for k2, v2 in pairs(v.internal.memberHooks) do
            for k3, v3 in pairs(v2) do
                CleveRoids.RemoveMethodHook(k2, v3)
            end
        end

        for k2, v2 in pairs(v.internal.hooks) do
            CleveRoids.RemoveHook(v2)
        end
    end
end

-- Creates a new extension with the given name
-- name: the name of the extension
function CleveRoids.RegisterExtension(name)
    local extension = {
        internal =
        {
            frame = CreateFrame("FRAME"),
            eventHandlers = {},
            hooks = {},
            memberHooks = {},
        },
    }

    extension.RegisterEvent = function(eventName, callbackName)
        CleveRoids.RegisterEvent(name, eventName, callbackName)
    end

    extension.Hook = function(functionName, callbackName, dontCallOriginal)
        CleveRoids.RegisterHook(name, functionName, callbackName, dontCallOriginal)
    end

    extension.HookMethod = function(object, functionName, callbackName, dontCallOriginal)
        CleveRoids.RegisterMethodHook(name, object, functionName, callbackName, dontCallOriginal)
    end


    extension.UnregisterEvent = function(eventName, callbackName)
        CleveRoids.UnregisterEvent(name, eventName, callbackName)
    end

    extension.internal.OnEvent = function()
        local callbackName = extension.internal.eventHandlers[event]
        if callbackName then
            extension[callbackName]()
        end
    end


    -- This is a function wrapper that we swap with the function that we want to hook
    -- @return Value of Callback() or Origininal() if dontCallOriginal is false
    extension.internal.OnHook = function(object, functionName, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
        local hook

        if object then
            hook = extension.internal.memberHooks[object][functionName]
        else
            hook = extension.internal.hooks[functionName]
        end

        local retval = hook.callback(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
        if not hook.dontCallOriginal then
            retval = hook.original(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
        end
        return retval
    end


    extension.internal.frame:SetScript("OnEvent", extension.internal.OnEvent)

    CleveRoids.Extensions[name] = extension

    return extension
end

-- Registers a callback function for a given event name
-- extensionName: The name of the extension trying to register the callback
-- eventName: The event's name we'd like to register a callback for
-- callbackName: The name of the callback that get's called when the event fires
function CleveRoids.RegisterEvent(extensionName, eventName, callbackName)
    local extension = CleveRoids.Extensions[extensionName]
    extension.internal.eventHandlers[eventName] = callbackName
    extension.internal.frame:RegisterEvent(eventName)
end

-- Hooks the given function by it's name
-- extensionName: The name of the extension trying to register the callback
-- functionName: The name of the function that'll be hooked
-- callbackName: The name of the callback that get's called when the hooked function is called
-- dontCallOriginal: Set to true when the original function should not be called
function CleveRoids.RegisterHook(extensionName, functionName, callbackName, dontCallOriginal)
    local orig = _G[functionName]
    local extension = CleveRoids.Extensions[extensionName]

    if not orig then
        CleveRoids.Print("CleveRoids.RegisterHook - Invalid function to hook: "..functionName)
    end

    if not extension then
        CleveRoids.Print("CleveRoids.RegisterHook - Invalid extension: "..extension)
        return
    end

    if not extension[callbackName] then
        CleveRoids.Print("CleveRoids.RegisterHook - Couldn't find callback: "..callbackName)
        return
    end


    extension.internal.hooks[functionName] = {
        original = orig,
        callback = extension[callbackName],
        name = functionName,
        dontCallOriginal = dontCallOriginal
    }

    _G[functionName] = function(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
        return extension.internal.OnHook(nil, functionName, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
    end
end

-- Hooks the given object's function
-- object: The object you want to hook
-- extensionName: The name of the extension trying to register the callback
-- functionName: The name of the function that'll be hooked
-- callbackName: The name of the callback that get's called when the hooked function is called
function CleveRoids.RegisterMethodHook(extensionName, object, functionName, callbackName, dontCallOriginal)
    if not object then
        CleveRoids.Print("CleveRoids.RegisterMethodHook - The object could not be found!")
        return
    end

    if type(object) ~= "table" then
        CleveRoids.Print("CleveRoids.RegisterMethodHook - The object needs to be a table!")
        return
    end

    local orig = object[functionName]

    if not orig then
        CleveRoids.Print("CleveRoids.RegisterMethodHook - The object doesn't have a function named "..functionName)
        return
    end

    local extension = CleveRoids.Extensions[extensionName]

    if not extension then
        CleveRoids.Print("CleveRoids.RegisterMethodHook - Invalid extension: "..extension)
        return
    end

    if not extension[callbackName] then
        CleveRoids.Print("CleveRoids.RegisterMethodHook - Couldn't find callback: "..callbackName)
        return
    end

    if not extension.internal.memberHooks[object] then
        extension.internal.memberHooks[object] = {}
    end

    extension.internal.memberHooks[object][functionName] = {
        original = orig,
        callback = extension[callbackName],
        name = functionName,
        dontCallOriginal = dontCallOriginal
    }

    object[functionName] = function(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
        return extension.internal.OnHook(object, functionName, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
    end
end

function CleveRoids.UnregisterEvent(extensionName, eventName, callbackName)
    local extension = CleveRoids.Extensions[extensionName]
    if extension.internal.eventHandlers[eventName] then
        extension.internal.eventHandlers[eventName] = nil
        extension.internal.frame:UnregisterEvent(eventName)
    end
end

_G["CleveRoids"] = CleveRoids
