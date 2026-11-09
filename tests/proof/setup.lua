package.path = "./tests/?.lua;./?.lua;./?/init.lua;" .. package.path

local Helpers = require("helpers")
local Proof = require("wowproof")
local MockState = require("wowproof.adapters.mock_state")
local Raster = require("wowproof.raster")

local Mock = Helpers.Mock

local ADDON_PREFIX = "interface\\addons\\"
local TEXTURE_EXTENSIONS = { "", ".tga", ".png" }
local FONT_DIR = "UnitFrames_Media/Fonts"
local FONT_FAMILY = "Roboto Condensed"
local FONT_WEIGHTS = { Light = 300, Regular = 400, Medium = 500, Bold = 700 }

local Setup = {}

local function AddonFile(path)
	if type(path) ~= "string" or path:lower():sub(1, #ADDON_PREFIX) ~= ADDON_PREFIX then return nil end
	return (path:sub(#ADDON_PREFIX + 1):gsub("\\", "/"))
end

function Setup.Texture(path)
	local file = AddonFile(path)
	if not file then return nil end
	for _, extension in ipairs(TEXTURE_EXTENSIONS) do
		local candidate = file .. extension
		if Raster.Exists(candidate) and candidate:lower():match("%.[tp][gn][ag]$") then return candidate end
	end
	return nil
end

function Setup.Font(path)
	local file = AddonFile(path)
	local style = file and file:match("^" .. FONT_DIR .. "/RobotoCondensed%-(%a+)%.ttf$")
	if style then return FONT_FAMILY, FONT_WEIGHTS[style] or 400 end
	return nil
end

function Setup.Adapter()
	return MockState({
		isSecret = Mock.IsSecret,
		reveal = function(value) return value.secretValue end,
		objects = function() return Mock.objects end,
		globals = _G,
	})
end

function Setup.Proof(options)
	options = options or {}
	return Proof.New({
		adapter = Setup.Adapter(),
		outDir = options.outDir or os.getenv("UF_PROOF_DIR") or ".proof",
		title = options.title or "UnitFrames UI proof",
		assets = {
			textures = Setup.Texture,
			fonts = { dirs = { FONT_DIR }, family = Setup.Font, default = FONT_FAMILY, defaultWeight = 500 },
		},
	})
end

return Setup
