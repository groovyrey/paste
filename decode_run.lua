local pre = [[
do
  local g = getgenv and getgenv() or (getfenv and getfenv(0)) or _G
  if type(g) == "table" then
    g.DecodeIsPremium = true
    g.IsPremium = true
    g.PremiumChecked = true
  end
end
local ov = readfile
if type(ov) == "function" then
  readfile = function(p)
    local r = ov(p)
    if type(r) == "string" and string.find(tostring(p), "config.json", 1, true) then
      local ok, hs = pcall(function() return game:GetService("HttpService") end)
      if ok then
        local ok2, t = pcall(function() return hs:JSONDecode(r) end)
        if ok2 and type(t) == "table" then
          local stack = {t}
          while #stack > 0 do
            local n = stack[#stack]
            stack[#stack] = nil
            if type(n) == "table" then
              for k, v in pairs(n) do
                if type(k) == "string" and string.find(string.lower(tostring(k)), "prem") then
                  n[k] = true
                elseif type(v) == "table" then
                  stack[#stack + 1] = v
                end
              end
            end
          end
          local ok3, enc = pcall(function() return hs:JSONEncode(t) end)
          if ok3 then return enc end
        end
      end
    end
    return r
  end
end
]]
local urls = {
  "https://raw.githubusercontent.com/DCDScript/Function/refs/heads/main/Steal%20An%20Egg/Function.luau",
  "https://raw.githubusercontent.com/DCDScript/Function/refs/heads/main/Steal%20An%20Egg/Function2.luau",
  "https://raw.githubusercontent.com/groovyrey/paste/main/UI_premium2.luau",
}
for _, u in ipairs(urls) do
  local s = game:HttpGet(u, true)
  local f, e = loadstring(pre .. s)
  assert(f, u .. " : " .. tostring(e))
  local ok, r = pcall(f)
  print("[Decode] " .. tostring(u:match("([^/]+)%.luau")) .. (ok and " ok" or " ERR " .. tostring(r)))
end