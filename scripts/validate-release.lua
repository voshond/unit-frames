-- Validate the staged installable bundle without loading client APIs.
local root, version = assert(arg[1], "bundle directory required"), assert(arg[2], "version required")
local addons = { "UnitFrames", "UnitFrames_Workbench", "UnitFrames_Media", "UnitFrames_ClickGrid" }
local checked = {}

local function Read(path)
	local file = assert(io.open(root .. "/" .. path, "rb"), "missing bundle file: " .. path)
	local content = file:read("*a")
	file:close()
	return content
end

local function Check(path)
	assert(not path:find("..", 1, true) and not path:match("^/"), "unsafe bundle reference: " .. path)
	if checked[path] then return end
	checked[path] = true
	local content = Read(path)
	if path:match("%.lua$") then
		assert(loadstring(content, "@" .. path))
	elseif path:match("%.xml$") then
		local directory = path:match("^(.*)/[^/]+$")
		content = content:gsub("<!%-%-.-%-%->", "")
		for file in content:gmatch('<%a+%s+file%s*=%s*["\']([^"\']+)["\']') do
			Check(directory .. "/" .. file:gsub("\\", "/"))
		end
	end
end

for _, addon in ipairs(addons) do
	assert(Read(addon .. "/LICENSE") == Read("LICENSE"), "outdated license in " .. addon)
	Read(addon .. "/NOTICE.txt")
	local toc = Read(addon .. "/" .. addon .. ".toc")
	assert(toc:match("## Interface:%s*(%d+)") == "16001", "unexpected client interface in " .. addon)
	assert(toc:match("## Version:%s*([^\r\n]+)") == version, "wrong version in " .. addon)
	for line in toc:gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" and not line:match("^#") then Check(addon .. "/" .. line:gsub("\\", "/")) end
	end
end

for _, addon in ipairs({ "UnitFrames", "UnitFrames_Media" }) do
	for _, license in ipairs({ "Ace3.txt", "LGPL-2.1.txt", "GPL-2.0.txt" }) do
		Read(addon .. "/Licenses/" .. license)
	end
end
Read("UnitFrames/Libs/oUF/LICENSE.txt")
Read("UnitFrames/Libs/LibEditMode/LICENSE.txt")
Read("UnitFrames_Media/Fonts/RobotoCondensed-OFL.txt")
for _, weight in ipairs({ "Light", "Regular", "Medium", "Bold" }) do
	Read("UnitFrames_Media/Fonts/RobotoCondensed-" .. weight .. ".ttf")
end
print("Release bundle references, versions, fonts and licenses verified.")

