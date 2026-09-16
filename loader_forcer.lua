-- loader_forcer.lua : runs the original ItzYumi Decode loader but forces premium
-- in every payload it loads and in every config read. Copy-paste this as your
-- executor script; it pulls the real loader and boots it.

local BOOT = [[
do
    local _up = getgenv and getgenv() or (getfenv and getfenv(0)) or _G
    if type(_up) == "table" then
        _up.DecodeIsPremium = true
        _up.IsPremium = true
        _up.PremiumChecked = true
        _up["DecodeIsPremium"] = true
        _up["IsPremium"] = true
        _up["PremiumChecked"] = true
    end
end
]]

local _force_flagged = {}

local function forceBoolInJson(json)
    pcall(function()
        local hs = game:GetService("HttpService")
        local ok2, t = pcall(function() return hs:JSONDecode(json) end)
        if not (ok2 and type(t) == "table") then return end
        local stack = {t}; local changed = false
        while #stack > 0 do
            local node = table.remove(stack)
            if type(node) == "table" then
                for k, v in pairs(node) do
                    if type(k) == "string" and string.find(string.lower(k), "prem") then
                        node[k] = true; changed = true
                    elseif type(v) == "table" then table.insert(stack, v) end
                end
            end
        end
        if changed then
            local ok3, enc = pcall(function() return hs:JSONEncode(t) end)
            if ok3 and type(enc) == "string" then
                return enc
            end
        end
    end)
    return json
end

local old_readfile = readfile
if type(old_readfile) == "function" then
    readfile = function(path)
        local raw = old_readfile(path)
        if type(raw) == "string" and string.find(tostring(path), "config.json", 1, true) then
            return forceBoolInJson(raw)
        end
        return raw
    end
end

local old_loadstring = loadstring
if type(old_loadstring) == "function" then
    loadstring = function(code)
        return old_loadstring(BOOT .. code)
    end
end
local old_load = load
if type(old_load) == "function" then
    load = function(code, chunkname, mode, env)
        return old_load(BOOT .. code, chunkname, mode, env)
    end
end

-- boot the real loader
loadstring(game:HttpGet("https://raw.githubusercontent.com/ItzYumi/Decode/refs/heads/main/DE%3ACODE.lua"))()
