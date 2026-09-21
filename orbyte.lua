--[[
	orbyte.lua — full Orbyte client. Loaded via loadstring from main.lua, which
	is just a one-line fetcher you paste into the executor. Everything here:
	  1. builds an "Orbyte" splash window using the ModernUI module
	  2. ensures the Orbyte folder exists and shows whether it was found or created
	  3. verifies the user with the orbyte-core key API (cached token in the folder)
	  4. the main ModernUI window opens once verified, with FeatureLoader toggles

	The ModernUI + FeatureLoader modules are always fetched fresh from this repo
	and written into the Orbyte folder (falling back to the cached copies when
	offline), so edits are picked up on every run. All UI comes from ModernUI.lua;
	auth comes from orbyte-core (account 2).
--]]

local FOLDER = "Orbyte"
local MODULE_PATH = FOLDER .. "/ModernUI.lua"
local MODULE_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/ModernUI.lua"
local FLOADER_PATH = FOLDER .. "/FeatureLoader.lua"
local FLOADER_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/FeatureLoader.lua"

local API_BASE = "https://orbyte-core.appleflux.workers.dev"
local TOKEN_PATH = FOLDER .. "/token.txt"
local DEVICE_PATH = FOLDER .. "/device.id"

--// ORBYTE FOLDER CHECK ---------------------------------------------------

-- Ensures the Orbyte folder exists.
-- Returns success (boolean) and the status message to show.
local function checkFolder()
	local ok, result = pcall(function()
		return isfolder(FOLDER)
	end)

	if not ok then
		return false, "File API unavailable: " .. tostring(result)
	end

	if result then
		return true, "Orbyte folder found."
	end

	local created, err = pcall(function()
		makefolder(FOLDER)
	end)

	if created then
		return true, "Orbyte folder created."
	end

	return false, "Failed to create Orbyte folder: " .. tostring(err)
end

-- The module is stored inside the Orbyte folder, so the folder must exist
-- before we try to write/read it. Capture the status once here and reuse it
-- on the splash window.
local folderOk, folderMessage = checkFolder()

--// MODULE LOADER ---------------------------------------------------------

-- Always tries to fetch the latest module from the repo so edits stay in sync,
-- persists it inside the Orbyte folder, and only falls back to the cached file
-- when the fetch fails.
local function loadModernUI()
	local src

	local ok, fetched = pcall(function()
		return game:HttpGet(MODULE_URL, true)
	end)
	if ok and type(fetched) == "string" and #fetched > 0 then
		src = fetched
		if type(writefile) == "function" and folderOk then
			pcall(function() writefile(MODULE_PATH, src) end)
		end
	elseif type(readfile) == "function" then
		local okCached, cached = pcall(function()
			return readfile(MODULE_PATH)
		end)
		if okCached and type(cached) == "string" and #cached > 0 then
			src = cached
		end
	end

	assert(type(src) == "string" and #src > 0, "ModernUI.module: no source available")
	local fn = assert(loadstring(src))
	return fn()
end

-- Same loader as the UI module: always fetch fresh from the repo, cache it in
-- the Orbyte folder, and only fall back to the cached copy when offline.
local function loadFeatureLoader()
	local src

	local ok, fetched = pcall(function()
		return game:HttpGet(FLOADER_URL, true)
	end)
	if ok and type(fetched) == "string" and #fetched > 0 then
		src = fetched
		if type(writefile) == "function" and folderOk then
			pcall(function() writefile(FLOADER_PATH, src) end)
		end
	elseif type(readfile) == "function" then
		local okCached, cached = pcall(function()
			return readfile(FLOADER_PATH)
		end)
		if okCached and type(cached) == "string" and #cached > 0 then
			src = cached
		end
	end

	assert(type(src) == "string" and #src > 0, "FeatureLoader.module: no source available")
	local fn = assert(loadstring(src))
	return fn()
end

--// KEY API CLIENT ---------------------------------------------------------

local HttpService = game:GetService("HttpService")

-- Returns a stable device id that survives restarts (persisted in the folder).
local function deviceId()
	if folderOk and type(readfile) == "function" then
		local ok, existing = pcall(function() return readfile(DEVICE_PATH) end)
		if ok and type(existing) == "string" and #existing > 0 then
			return existing
		end
	end
	local id = tostring(os.time()) .. "-" .. HttpService:GenerateGUID(false)
	if folderOk and type(writefile) == "function" then
		pcall(function() writefile(DEVICE_PATH, id) end)
	end
	return id
end

local function hwid()
	local exe = "unknown"
	if type(getexecutorname) == "function" then
		exe = getexecutorname()
	elseif type(identifyexecutor) == "function" then
		local ok, name = pcall(identifyexecutor)
		if ok and type(name) == "string" then exe = name end
	end
	local lp = game:GetService("Players").LocalPlayer
	return exe .. "|" .. tostring(lp and lp.UserId or 0) .. "|" .. deviceId()
end

-- POST JSON to the API. Returns (parsed response | nil, error | nil).
local function apiCall(path, payload)
	local code, body
	local ok = pcall(function()
		if type(request) == "function" or type(http_request) == "function" then
			local fn = type(request) == "function" and request or http_request
			local res = fn({
				Url = API_BASE .. path,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(payload),
			})
			code = res.StatusCode or res.status_code or res.Status or 0
			body = tostring(res.Body or res.body or "")
		else
			local ok1, b1 = pcall(function()
				return game:HttpPostAsync(API_BASE .. path, HttpService:JSONEncode(payload), Enum.HttpContentType.ApplicationJson, true)
			end)
			if ok1 then
				code, body = 200, tostring(b1 or "")
			else
				local b2 = game:HttpPost(API_BASE .. path, HttpService:JSONEncode(payload), true, Enum.HttpContentType.ApplicationJson)
				code, body = 200, tostring(b2 or "")
			end
		end
	end)
	if not ok then return nil, "request_failed" end
	if not code then return nil, "request_failed" end

	local parsed
	local okJson = pcall(function()
		parsed = HttpService:JSONDecode(body or "")
	end)
	if not okJson or type(parsed) ~= "table" then
		return nil, "HTTP " .. tostring(code)
	end
	return parsed, nil
end

-- True if a cached token still validates; otherwise clears the stale token.
local function tryBoot()
	if not folderOk or type(readfile) ~= "function" then return false end
	local okTok, token = pcall(function() return readfile(TOKEN_PATH) end)
	if not okTok or type(token) ~= "string" or #token < 4 then return false end

	local resp = apiCall("/api/orbyte/boot", { token = token, hwid = hwid() })
	if resp and resp.ok then return true end

	if type(writefile) == "function" then
		pcall(function() writefile(TOKEN_PATH, "") end)
	end
	return false
end

--// BOOT ------------------------------------------------------------------

local ModernUI = loadModernUI()

local SPLASH_SIZE = Vector2.new(320, 260)
local MAIN_SIZE = Vector2.new(360, 460)

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function toggleFeature(Loader, name, state, ...)
	if state then
		Loader.Enable(name, ...)
	else
		Loader.Disable(name)
	end
end

local function openModernUI()
	local ui = ModernUI.new({ Title = "Orbyte", Size = MAIN_SIZE })

	local okLoader, Loader = pcall(loadFeatureLoader)
	if not (okLoader and type(Loader) == "table") then
		ui:AddButton("Collapse / Expand", function()
			ui:ToggleCollapsed()
		end)
		ui:AddLabel("FeatureLoader unavailable.")
		return
	end

	ui:AddButton("Collapse / Expand", function()
		ui:ToggleCollapsed()
	end)

	--// REGISTER ORBYTE FEATURES ------------------------------------------

	-- Noclip: keeps every character part non-collidable while on.
	Loader.Register("Noclip", function()
		local affected = {}

		local function apply(character)
			if not character then return end
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					part.CanCollide = false
					table.insert(affected, part)
				end
			end
		end

		local connSpawn = LocalPlayer.CharacterAdded:Connect(apply)
		apply(LocalPlayer.Character)

		return function()
			connSpawn:Disconnect()
			for _, part in ipairs(affected) do
				part.CanCollide = true
			end
		end
	end)

-- ESP: box highlights around every other player while on.
	Loader.Register("ESP", function()
		local highlights = {}
		local connections = {}

		local function add(player)
			local character = player.Character
			if not character or highlights[player] then return end
			local box = Instance.new("Highlight")
			box.FillTransparency = 0
			box.FillColor = Color3.fromRGB(60, 130, 255)
			box.OutlineTransparency = 0
			box.OutlineColor = Color3.new(1, 1, 1)
			box.Parent = character
			highlights[player] = box
		end

		local function remove(player)
			local box = highlights[player]
			if box then
				pcall(function() box:Destroy() end)
				highlights[player] = nil
			end
		end

		local function wire(player)
			if player == LocalPlayer then return end
			add(player)
			local conn = player.CharacterAdded:Connect(function() add(player) end)
			table.insert(connections, conn)
		end

		for _, player in ipairs(Players:GetPlayers()) do
			wire(player)
		end

		table.insert(connections, Players.PlayerAdded:Connect(function(player)
			wire(player)
		end))
		table.insert(connections, Players.PlayerRemoving:Connect(remove))

		return function()
			for _, conn in ipairs(connections) do
				pcall(function() conn:Disconnect() end)
			end
			for _, box in pairs(highlights) do
				pcall(function() box:Destroy() end)
			end
		end
	end)

	--// BUILD UI -----------------------------------------------------------

	ui:AddLabel("Orbyte v1.0")

	ui:AddLabel("Movement")

	ui:AddToggle("Infinite Jump", Loader.IsEnabled("InfiniteJump"), function(state)
		toggleFeature(Loader, "InfiniteJump", state)
	end)

	ui:AddToggle("Speed Boost", Loader.IsEnabled("WalkSpeed"), function(state)
		toggleFeature(Loader, "WalkSpeed", state, 32)
	end)

	ui:AddToggle("Noclip", Loader.IsEnabled("Noclip"), function(state)
		toggleFeature(Loader, "Noclip", state)
	end)

	ui:AddLabel("Visual")

	ui:AddToggle("ESP", Loader.IsEnabled("ESP"), function(state)
		toggleFeature(Loader, "ESP", state)
	end)
end

-- Authenticated sessions skip the splash entirely.
if tryBoot() then
	openModernUI()
	return
end

-- Key gate: folder status + key entry + verify.
local splash = ModernUI.new({ Title = "Orbyte", Size = SPLASH_SIZE })

local folderLabel = splash:AddLabel(folderMessage)
folderLabel.TextColor3 = folderOk
	and Color3.fromRGB(130, 220, 150)
	or Color3.fromRGB(255, 150, 150)

local apiLabel = splash:AddLabel("Enter your Orbyte key to continue.")
apiLabel.TextColor3 = Color3.fromRGB(235, 235, 240)

local keyBox = splash:AddTextBox("Enter Orbyte key")

local function showApiError(msg)
	apiLabel.Text = tostring(msg)
	apiLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
end

splash:AddButton("Verify", function()
	local key = (keyBox.Text or ""):gsub("%s+", ""):upper()
	if #key < 8 then
		showApiError("Enter a valid key.")
		return
	end

	local resp = apiCall("/api/orbyte/verify", { key = key, hwid = hwid() })
	if resp and resp.ok and type(resp.token) == "string" then
		if folderOk and type(writefile) == "function" then
			pcall(function() writefile(TOKEN_PATH, resp.token) end)
		end
		splash:Destroy()
		openModernUI()
	else
		local err = resp and resp.error or "Verification failed."
		showApiError("Verification failed: " .. tostring(err))
	end
end)