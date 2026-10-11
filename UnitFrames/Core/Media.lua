local _, ns = ...

local LSM = LibStub("LibSharedMedia-3.0")

local Media = {}
ns.Media = Media
Media.LSM = LSM

-- A plain 1px line border (use with border size 1) for flat looks.
LSM:Register("border", "UnitFrames Pixel", [[Interface\Buttons\WHITE8X8]])

-- LibSharedMedia media types used by schema option types.
Media.TYPES = {
	font = "font",
	statusbar = "statusbar",
	border = "border",
	background = "background",
}

function Media:Fetch(kind, key)
	return LSM:Fetch(kind, key, true) or LSM:Fetch(kind, LSM:GetDefault(kind))
end

function Media:List(kind)
	return LSM:List(kind)
end

-- Forever rejects "NONE" as a font flag; no flags is "".
function Media:Outline(flags)
	if flags == nil or flags == "NONE" then
		return ""
	end
	return flags
end

-- Ordinary FontStrings may use SetFont; menu FontStrings use GetFontObject.
function Media:ApplyFont(fontString, key, size, flags)
	local outline = self:Outline(flags)
	if not fontString:SetFont(self:Fetch("font", key), size, outline) then
		fontString:SetFont(self:Fetch("font", LSM:GetDefault("font")), size, outline)
	end
end

-- Raw SetFont on a font file the client hasn't loaded yet is unreliable in
-- Forever (see docs/03 §2.6), so every font gets a Font object up front.
local preloaded = {}
local fontCount = 0

local function Preload(key)
	local path = LSM:Fetch("font", key, true)
	if not path or preloaded[path] then
		return
	end
	fontCount = fontCount + 1
	local font = CreateFont("UnitFramesPreloadFont" .. fontCount)
	font:SetFont(path, 12, "")
	preloaded[path] = font
end

-- A Font object for a font key at one size, e.g. for font previews in menus
-- (Blizzard's menu font strings forbid SetFont but allow SetFontObject).
local fontObjects = {}
function Media:GetFontObject(key, size)
	local id = key .. "@" .. size
	local font = fontObjects[id]
	if not font then
		fontCount = fontCount + 1
		font = CreateFont("UnitFramesFont" .. fontCount)
		if not font:SetFont(self:Fetch("font", key), size, "") then
			font:SetFont(self:Fetch("font", LSM:GetDefault("font")), size, "")
		end
		fontObjects[id] = font
	end
	return font
end

function Media:Initialize()
	for _, key in ipairs(LSM:List("font")) do
		Preload(key)
	end
	LSM.RegisterCallback(self, "LibSharedMedia_Registered", function(_, kind, key)
		if kind == "font" then
			Preload(key)
		end
	end)
end
