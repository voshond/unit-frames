package.path = "./tests/?.lua;./?.lua;./?/init.lua;" .. package.path

local Helpers = require("helpers")
local Proof = require("wowproof")
local MockState = require("wowproof.adapters.mock_state")
local Raster = require("wowproof.raster")
local BlizzardArt = require("wowproof.sources.wow_ui_textures")
local ClientFiles = require("wowproof.sources.wago_casc")
local AtlasTable = require("wowproof.sources.atlas_table")

local Mock = Helpers.Mock

local ADDON_PREFIX = "interface\\addons\\"
local TEXTURE_EXTENSIONS = { "", ".tga", ".png" }
local FONT_DIR = "UnitFrames_Media/Fonts"
local FONT_FAMILY = "Roboto Condensed"
local FONT_WEIGHTS = { Light = 300, Regular = 400, Medium = 500, Bold = 700 }
local ART_REF = "d23deaf8f44a7d280dc974a5c9d5321c013db59b"
local ATLASES = dofile("tests/proof/atlases.lua")
local ART_DIR = os.getenv("UF_PROOF_ART") or ".proof-art"
local ART_FETCH = os.getenv("UF_PROOF_ART_FETCH") ~= "0"

local Setup = {}

local blizzardArt = BlizzardArt({
	ref = ART_REF,
	dir = ART_DIR,
	fetch = ART_FETCH,
	token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN"),
})
local clientFiles = ClientFiles({ build = ATLASES.build, dir = ART_DIR, fetch = ART_FETCH })

local function AddonFile(path)
	if type(path) ~= "string" or path:lower():sub(1, #ADDON_PREFIX) ~= ADDON_PREFIX then return nil end
	return (path:sub(#ADDON_PREFIX + 1):gsub("\\", "/"))
end

function Setup.AddonTexture(path)
	local file = AddonFile(path)
	if not file then return nil end
	for _, extension in ipairs(TEXTURE_EXTENSIONS) do
		local candidate = file .. extension
		if Raster.Exists(candidate) and candidate:lower():match("%.[tp][gn][ag]$") then return candidate end
	end
	return nil
end

function Setup.Texture(path)
	return Setup.AddonTexture(path) or blizzardArt(path) or clientFiles(path)
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

local function BackdropGeometry(frame, width, height)
	return setmetatable({
		GetWidth = function() return width end,
		GetHeight = function() return height end,
		GetEffectiveScale = function() return frame:GetEffectiveScale() end,
		GetEdgeSize = function() return frame:GetEdgeSize() end,
	}, { __index = frame })
end

function Setup.SettleBackdrops(layout)
	for _, frame in ipairs(Mock.objects) do
		local state = frame.__state
		local rect = state.backdrop and state.backdropSizeScript and layout:Rect(frame)
		if rect then
			local scale = layout:Scale(frame)
			local repeats = state.backdropRepeat
			BackdropTemplateMixin.SetupTextureCoordinates(BackdropGeometry(frame, rect.width / scale, rect.height / scale))
			state.backdropRepeat = repeats
		end
	end
end

function Setup.Proof(options)
	options = options or {}
	return Proof.New({
		adapter = Setup.Adapter(),
		outDir = options.outDir or os.getenv("UF_PROOF_DIR") or ".proof",
		title = options.title or "UnitFrames UI proof",
		settle = Setup.SettleBackdrops,
		assets = {
			textures = Setup.Texture,
			atlases = AtlasTable(ATLASES.atlases),
			fonts = { dirs = { FONT_DIR }, family = Setup.Font, default = FONT_FAMILY, defaultWeight = 500 },
		},
	})
end

return Setup
