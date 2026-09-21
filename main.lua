--[[
	Orbyte — executor entry point.
	Paste this whole file into your executor. It only fetches the real client
	from the repo (always fresh) and runs it, so updates ship automatically
	without re-pasting anything.
]]

loadstring(game:HttpGet("https://raw.githubusercontent.com/groovyrey/paste/main/orbyte.lua", true))()