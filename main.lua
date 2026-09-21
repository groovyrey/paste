--[[
	main.lua
	Single entry script that connects everything together:
	  1. builds an "Orbyte" splash window using the ModernUI module
	  2. ensures the Orbyte folder exists and shows whether it was found or created
	  3. a Continue button opens the ModernUI demo window (also module-driven)

	The ModernUI module is always fetched fresh from this repo and written into
	the Orbyte folder (falling back to the cached copy when offline), so edits
	are picked up on every run. All UI comes from ModernUI.lua.
--]]

local FOLDER = "Orbyte"
local MODULE_PATH = FOLDER .. "/ModernUI.lua"
local MODULE_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/ModernUI.lua"

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

--// BOOT ------------------------------------------------------------------

local ModernUI = loadModernUI()

local SPLASH_SIZE = Vector2.new(320, 210)
local MAIN_SIZE = Vector2.new(340, 420)

local function openModernUI()
	local ui = ModernUI.new({ Title = "Orbyte", Size = MAIN_SIZE })

	ui:AddLabel("Welcome to the app")

	ui:AddButton("Click Me", function()
		print("Button clicked!")
	end)

	ui:AddToggle("Enable Feature", false, function(state)
		print("Toggle:", state)
	end)

	ui:AddButton("Collapse / Expand", function()
		ui:ToggleCollapsed()
	end)

	ui:AddSlider("Volume", 0, 100, 50, function(value)
		print("Slider:", value)
	end)

	ui:AddTextBox("Enter name...", function(text, enterPressed)
		print("Text entered:", text)
	end)
end

-- Splash window: folder status + Continue.
local splash = ModernUI.new({ Title = "Orbyte", Size = SPLASH_SIZE })

local statusLabel = splash:AddLabel(folderMessage)
statusLabel.TextColor3 = folderOk
	and Color3.fromRGB(130, 220, 150)
	or Color3.fromRGB(255, 150, 150)

splash:AddButton("Continue", function()
	splash:Destroy()
	openModernUI()
end)