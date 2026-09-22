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

-- Cache-buster: executors cache HttpGet by URL, so append the run time to every
-- module URL to guarantee clients always pick up the newest pushed code.
local CACHE_BUST = "?t=" .. tostring(os.time())

local MODULE_PATH = FOLDER .. "/ModernUI.lua"
local MODULE_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/ModernUI.lua" .. CACHE_BUST
local FLOADER_PATH = FOLDER .. "/FeatureLoader.lua"
local FLOADER_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/FeatureLoader.lua" .. CACHE_BUST
local CONFIG_PATH = FOLDER .. "/config.json"
local CONFIG_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/config.json" .. CACHE_BUST
local NNOTIF_PATH = FOLDER .. "/NotificationSystem.lua"
local NNOTIF_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/NotificationSystem.lua" .. CACHE_BUST
local SAE_PATH = FOLDER .. "/SAE.lua"
local SAE_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/SAE.lua" .. CACHE_BUST

local HttpService = game:GetService("HttpService")

local API_BASE = "https://orbyte-core.appleflux.workers.dev"
local TOKEN_PATH = FOLDER .. "/token.txt"
local DEVICE_PATH = FOLDER .. "/device.id"

--// SESSION GUARD ----------------------------------------------------------
-- Strict single-instance: executing the entry again in the same session must
-- not stack a second copy of Orbyte (windows, key gate, features, ...).
local PREV_NOTIF = _G.OrbyteNotif
if _G.OrbyteSession then
	print("[Orbyte] Already running in this session — skipping duplicate.")
	if type(PREV_NOTIF) == "table" and type(PREV_NOTIF.Push) == "function" then
		pcall(PREV_NOTIF.Push, PREV_NOTIF, {
			Title = "Orbyte",
			Message = "Already running — only one session is allowed.",
			Type = "Warning",
		})
	end
	return
end

local function main()

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

-- GitHub-driven config (games + features). Always fetched fresh so editing
-- config.json on GitHub updates every client; cached copy is the fallback.
local function loadConfig()
	local src

	local ok, fetched = pcall(function()
		return game:HttpGet(CONFIG_URL)
	end)
	if ok and type(fetched) == "string" and #fetched > 0 then
		src = fetched
		if type(writefile) == "function" and folderOk then
			pcall(function() writefile(CONFIG_PATH, src) end)
		end
	elseif type(readfile) == "function" then
		local okCached, cached = pcall(function()
			return readfile(CONFIG_PATH)
		end)
		if okCached and type(cached) == "string" and #cached > 0 then
			src = cached
		end
	end

	if type(src) ~= "string" or #src == 0 then
		return nil
	end

	local okJson, parsed = pcall(function()
		return HttpService:JSONDecode(src)
	end)
	if not okJson or type(parsed) ~= "table" then
		return nil
	end
	return parsed
end

-- Same loader pattern: fetch the notification module fresh, cache it, fall
-- back to the cached copy if the fetch fails.
local function loadNotificationSystem()
	local src

	local ok, fetched = pcall(function()
		return game:HttpGet(NNOTIF_URL, true)
	end)
	if ok and type(fetched) == "string" and #fetched > 0 then
		src = fetched
		if type(writefile) == "function" and folderOk then
			pcall(function() writefile(NNOTIF_PATH, src) end)
		end
	elseif type(readfile) == "function" then
		local okCached, cached = pcall(function()
			return readfile(NNOTIF_PATH)
		end)
		if okCached and type(cached) == "string" and #cached > 0 then
			src = cached
		end
	end

	if type(src) ~= "string" or #src == 0 then
		return nil
	end

	local okFn, fn = pcall(loadstring, src)
	if not okFn or type(fn) ~= "function" then
		return nil
	end
	local okMod, Notif = pcall(fn)
	if okMod and type(Notif) == "table" and type(Notif.new) == "function" then
		return Notif
	end
	return nil
end

-- SAE.lua registers its own features ("SAE", "InstantTP") against the
-- loader/modules we pass it. Same load pattern: fresh fetch, cache, fallback.
local function loadSAEFeatures()
	local src

	local ok, fetched = pcall(function()
		return game:HttpGet(SAE_URL, true)
	end)
	if ok and type(fetched) == "string" and #fetched > 0 then
		src = fetched
		if type(writefile) == "function" and folderOk then
			pcall(function() writefile(SAE_PATH, src) end)
		end
	elseif type(readfile) == "function" then
		local okCached, cached = pcall(function()
			return readfile(SAE_PATH)
		end)
		if okCached and type(cached) == "string" and #cached > 0 then
			src = cached
		end
	end

	if type(src) ~= "string" or #src == 0 then
		return nil
	end

	local okFn, fn = pcall(loadstring, src)
	if not okFn or type(fn) ~= "function" then
		return nil
	end
	local okMod, mod = pcall(fn)
	if okMod and type(mod) == "function" then
		return mod
	end
	return nil
end

--// KEY API CLIENT ---------------------------------------------------------

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

local NotifModule = loadNotificationSystem()
local notify = nil
if NotifModule then
	local okNew, inst = pcall(NotifModule.new, NotifModule, { Theme = ModernUI.Theme })
	if okNew and inst then
		notify = inst
		_G.OrbyteNotif = inst
	end
end

-- Toast helper that no-ops (falls back to print) if notifications are
-- unavailable, so the client never hard-fails on it.
local function showNotif(title, message, kind, duration)
	local okPush, err = pcall(function()
		if notify then
			notify:Push({ Title = title, Message = message, Type = kind, Duration = duration })
		end
	end)
	if not okPush or not notify then
		print(("[Orbyte] %s %s"):format(tostring(title), tostring(message)))
	end
end

local SPLASH_SIZE = Vector2.new(320, 260)
local MAIN_SIZE = Vector2.new(360, 460)
local CHOOSER_SIZE = Vector2.new(320, 380)

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local FEATURE_DEFS = {
	InfiniteJump = { label = "Infinite Jump" },
	WalkSpeed = { label = "Speed Boost", args = { 32 } },
	Noclip = { label = "Noclip" },
	ESP = { label = "ESP" },
	SAE = {
		label = "SAE Panel",
		kind = "action",
		action = function(Loader)
			if Loader.IsEnabled("SAE") then
				Loader.Disable("SAE")
			else
				Loader.Enable("SAE")
			end
		end,
	},
	SaeCopyPos = {
		label = "Save Root Position",
		hint = "Position…",
		kind = "button",
		action = function()
			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root then
				showNotif("Copy position", "No character root found.", "Warning")
				return nil
			end
			local pos = root.Position
			return ("%.2f, %.2f, %.2f"):format(pos.X, pos.Y, pos.Z)
		end,
	},
}

local DEFAULT_FEATURES = { "InfiniteJump", "WalkSpeed", "Noclip", "ESP" }

-- ONE shared Loader for the whole session. Every window must drive this same
-- instance: creating a fresh Loader per window (and re-registering features)
-- spawns duplicate Noclip/ESP instances that fight over the same parts and
-- each restore only their own state — Noclip "stays on after being turned
-- off" and other features behave randomly.
local SharedLoader = nil
local loaderLoaded = false

local function getSharedLoader()
	if loaderLoaded then return SharedLoader end
	loaderLoaded = true

	local okLoader, Loader = pcall(loadFeatureLoader)
	if not (okLoader and type(Loader) == "table") then
		return nil
	end
	SharedLoader = Loader
	return Loader
end

local function registerOrbyteFeatures(Loader)
	local okSAE, SAEFn = pcall(loadSAEFeatures)
	if okSAE and type(SAEFn) == "function" then
		pcall(SAEFn, Loader, ModernUI, NotifModule)
	end

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
end

-- All Orbyte features (built-ins + SAE) registered exactly once against the
-- shared loader, so no duplicate cleanup/instances can accumulate.
local featuresRegistered = false

local function ensureRegistered()
	if featuresRegistered then return true end
	local Loader = getSharedLoader()
	if not Loader then return false end
	registerOrbyteFeatures(Loader)
	featuresRegistered = true
	return true
end

local function openModernUI(uiTitle, features)
	local ui = ModernUI.new({ Title = uiTitle or "Orbyte", Size = MAIN_SIZE })

	ui:AddButton("Collapse / Expand", function()
		ui:ToggleCollapsed()
	end)

	if not ensureRegistered() then
		ui:AddLabel("FeatureLoader unavailable.")
		return
	end

	-- Fresh window = fresh state: nothing may leak over from a previous window
	-- (which was the bug behind "Noclip still on while its toggle is off").
	local Loader = getSharedLoader()
	Loader.DisableAll()

	local unpackArgs = table.unpack or unpack

	local function buildToggles(features)
		for _, name in ipairs(features) do
			local def = FEATURE_DEFS[name] or {}
			local label = def.label or tostring(name)
			local args = def.args or {}

			if def.kind == "action" and type(def.action) == "function" then
				-- Plain button (no textbox): opens/toggles a custom panel.
				ui:AddButton(label, function()
					def.action(Loader)
				end)
			elseif def.kind == "button" and type(def.action) == "function" then
				local result = ui:AddTextBox(def.hint or "—")
				ui:AddButton(label, function()
					local value = def.action()
					if value then
						result.Text = tostring(value)
					end
				end)
			else
				ui:AddToggle(label, false, function(state)
					if state then
						Loader.Enable(name, unpackArgs(args))
					else
						Loader.Disable(name)
					end
				end)
			end
		end
	end

	ui:AddLabel(uiTitle or "Orbyte v1.0")
	ui:AddLabel("Features")
	buildToggles(features or DEFAULT_FEATURES)
end

-- Game chooser shown after a valid key. Presets and the Universal label come
-- from config.json on GitHub; each preset is a stub until it ships a loader.
-- Load GitHub config once and keep the client working if it fails.
local CONFIG = loadConfig()

local games = CONFIG and type(CONFIG.games) == "table" and CONFIG.games or {}
local universal = CONFIG and type(CONFIG.universal) == "table" and CONFIG.universal or {}
local universalFeatures = type(universal.features) == "table" and universal.features or nil
local univLabel = tostring(universal.label or "Universal — Launch Orbyte")

-- The window actually opened after the key gate passes.
local launchTitle = "Orbyte"
local launchFeatures = universalFeatures

local function launchOrbyte()
	local features = launchFeatures
	if type(features) ~= "table" or #features == 0 then
		features = universalFeatures
	end
	if type(features) == "table" and #features > 0 then
		showNotif("Orbyte", "Preset loaded.", "Success")
		openModernUI(launchTitle, features)
	else
		showNotif("Orbyte", "No presets configured yet.", "Warning")
	end
end

local function showKeyGate()
	-- A cached, still-valid token skips the key screen entirely.
	if tryBoot() then
		showNotif("Orbyte", "Welcome back.", "Success")
		launchOrbyte()
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

	local API_ERROR_MESSAGES = {
		invalid_key = "The key you entered isn't valid. Double-check it and try again.",
		revoked = "This key has been revoked. Contact the seller for a new one.",
		expired = "This key has expired. Contact the seller for a replacement.",
		hwid_bound = "This device is already linked to a different Orbyte key. Ask the seller to unbind your device, then try again.",
		device_limit = "This key is already in use on too many devices. Contact the seller to reset it.",
		missing_key_or_hwid = "A required value was missing. Restart Orbyte and try again.",
		bad_request = "The request was malformed. Restart Orbyte and try again.",
	}

	local function friendlyError(err)
		local msg = API_ERROR_MESSAGES[tostring(err)]
		if msg then return msg end
		return "Something went wrong. Try again in a bit. (" .. tostring(err) .. ")"
	end

	local function showApiError(msg)
		apiLabel.Text = friendlyError(msg)
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
			showNotif("Key verified", "Welcome back.", "Success")
			launchOrbyte()
		else
			local err = resp and resp.error or "Verification failed."
			local friendly = friendlyError(err)
			showApiError(friendly)
			showNotif("Key rejected", friendly, "Error")
		end
	end)
end

-- First screen: detect the current game, then route into the key gate. If the
-- detected game is supported we offer "Continue to <Game>"; otherwise we say
-- the game isn't supported. Universal is always offered as the default.
local currentUniverse = 0
pcall(function()
	currentUniverse = tonumber(game.GameId) or 0
end)
local currentPlace = tonumber(game.PlaceId) or 0

local matchedGame = nil
for _, g in ipairs(games) do
	local uni = tonumber(g.universeId or 0) or 0
	local pid = tonumber(g.id or 0) or 0
	if (uni > 0 and uni == currentUniverse) or (pid > 0 and pid == currentPlace) then
		matchedGame = g
		break
	end
end

local detector = ModernUI.new({ Title = "Orbyte — Game", Size = CHOOSER_SIZE })

if matchedGame then
	local name = tostring(matchedGame.name or "Game")
	launchTitle = "Orbyte — " .. name
	launchFeatures = type(matchedGame.features) == "table" and matchedGame.features or nil
	detector:AddLabel("Detected: " .. name)
	detector:AddButton("Continue to " .. name, function()
		detector:Destroy()
		showKeyGate()
	end)
else
	detector:AddLabel("Game Not Supported")
end

detector:AddLabel("Or launch Orbyte universally:")
detector:AddButton(univLabel, function()
	launchTitle = "Orbyte"
	launchFeatures = universalFeatures
	detector:Destroy()
	showKeyGate()
end)

end
--// main() -----------------------------------------------------------------

_G.OrbyteSession = true
local okRun, errRun = xpcall(main, function(e)
	return tostring(e)
end)
if not okRun then
	_G.OrbyteSession = nil
	local errMsg = tostring(errRun)
	local prev = _G.OrbyteNotif
	if type(prev) == "table" and type(prev.Push) == "function" then
		pcall(prev.Push, prev, {
			Title = "Orbyte",
			Message = "Failed to start: " .. errMsg,
			Type = "Error",
			Duration = 8,
		})
	end
	warn("[Orbyte] Failed to start: " .. errMsg)
end