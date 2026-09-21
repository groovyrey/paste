--[[
	ModernUI.client.lua
	Example LocalScript that uses the ModernUI module (ModernUI.lua).

	Always fetches the module fresh from this repo and writes it into the
	Orbyte folder (falling back to the cached copy when offline), so edits are
	picked up on every run. Then builds a demo window like the old standalone
	ModernUI.client.lua did.
--]]

local FOLDER = "Orbyte"
local MODULE_PATH = FOLDER .. "/ModernUI.lua"
local MODULE_URL = "https://raw.githubusercontent.com/groovyrey/paste/main/ModernUI.lua"

local function ensureFolder()
	if type(isfolder) ~= "function" then return end
	if type(makefolder) ~= "function" then return end
	pcall(function()
		if not isfolder(FOLDER) then
			makefolder(FOLDER)
		end
	end)
end

local function loadModernUI()
	local src

	local ok, fetched = pcall(function()
		return game:HttpGet(MODULE_URL, true)
	end)
	if ok and type(fetched) == "string" and #fetched > 0 then
		src = fetched
		if type(writefile) == "function" then
			ensureFolder()
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