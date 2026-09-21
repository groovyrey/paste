--[[
	ModernUI.client.lua
	Example LocalScript that uses the ModernUI module (ModernUI.lua).

	Loads the module from the executor's file API (saving it there first if
	missing) and falls back to fetching it from this repo. Then builds a demo
	window exactly like the old standalone ModernUI.client.lua did.
--]]

local MODULE_PATH = "ModernUI.lua"
local MODULE_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/ModernUI.lua"

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

local ModernUI = loadModernUI()

local ui = ModernUI.new({
	Title = "Modern UI",
	Size = Vector2.new(340, 420),
})

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