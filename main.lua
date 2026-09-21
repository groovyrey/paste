--[[
	main.lua
	Single entry script that connects everything together:
	  1. builds an "Orbyte" splash window using the ModernUI module
	  2. checks the Orbyte folder and shows whether it was found or created
	  3. a Continue button opens the ModernUI demo window (also module-driven)

	The ModernUI module is loaded from the executor file API (saved there first
	if missing) with a fallback to this repo. All UI comes from ModernUI.lua.
--]]

local MODULE_PATH = "ModernUI.lua"
local MODULE_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/ModernUI.lua"

local FOLDER = "Orbyte"

--// MODULE LOADER ---------------------------------------------------------

local function ensureModuleFile()
	if type(writefile) ~= "function" then return end
	if type(isfile) == "function" and isfile(MODULE_PATH) then return end
	local ok, src = pcall(function()
		return game:HttpGet(MODULE_URL, true)
	end)
	if ok and type(src) == "string" and #src > 0 then
		pcall(function() writefile(MODULE_PATH, src) end)
	end
end

local function loadModernUI()
	ensureModuleFile()

	local mod
	local ok = pcall(function()
		if type(readfile) ~= "function" then error("no executor file API") end
		local src = readfile(MODULE_PATH)
		if type(src) ~= "string" or #src == 0 then error("module file empty") end
		local fn = assert(loadstring(src))
		mod = fn()
	end)
	if ok and type(mod) == "table" then
		return mod
	end

	local src = assert(game:HttpGet(MODULE_URL, true))
	local fn = assert(loadstring(src))
	return fn()
end

--// ORBYTE FOLDER CHECK ---------------------------------------------------

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

--// BOOT ------------------------------------------------------------------

local ModernUI = loadModernUI()

local SPLASH_SIZE = Vector2.new(320, 210)
local MAIN_SIZE = Vector2.new(340, 420)

local function openModernUI()
	local ui = ModernUI.new({ Title = "Modern UI", Size = MAIN_SIZE })

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

local folderOk, folderMessage = checkFolder()

local statusLabel = splash:AddLabel(folderMessage)
statusLabel.TextColor3 = folderOk
	and Color3.fromRGB(130, 220, 150)
	or Color3.fromRGB(255, 150, 150)

splash:AddButton("Continue", function()
	splash:Destroy()
	openModernUI()
end)