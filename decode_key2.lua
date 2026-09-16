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

local PREMIUM_JSON = '{"success":true,"valid":true,"error_code":"SUCCESS","message":"Key valid! HWID bound (R","session_id":"__dec_bp__","hwid":"0","Activat":true,"activated":true,"premium":true,"IsPremium":true,"DecodeIsPremium":true,"key":"__dec_bp__"}'

local RT = request or http_request
if type(RT) == "function" then
  request = function(tab)
    local args = tab
    if type(tab) ~= "table" then args = {} end
    local call = {Url = args.Url, Method = args.Method}
    if type(args.Headers) == "table" then call.Headers = {} for k, v in pairs(args.Headers) do call.Headers[k] = v end end
    local r = RT(call)
    if r and type(r.Body) == "string" then
      local head = (r.Body:gsub("^%s+", "")):sub(1, 1)
      if head == "{" then
        r.Body = PREMIUM_JSON
      end
    end
    return r
  end
end

do
  local g = getgenv and getgenv() or (getfenv and getfenv(0)) or _G
  if type(g) == "table" then
    g.DecodeIsPremium = true
    g.IsPremium = true
    g.PremiumChecked = true
  end
end

loadstring(game:HttpGet("https://raw.githubusercontent.com/ItzYumi/Decode/refs/heads/main/DE%3ACODE.lua", true))()