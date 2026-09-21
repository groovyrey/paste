local FOLDER = "Orbyte"

local ok, err = pcall(function()
	if isfolder(FOLDER) then
		print("Orbyte folder already exists.")
		return
	end
	makefolder(FOLDER)
	print("Created Orbyte folder.")
end)

if not ok then
	print("Failed to check/create Orbyte folder:", err)
end