local _, ns = ...

-- Look of our own UI (settings, Workbench). Restyle everything from here.
local Skin = {}
ns.Skin = Skin

local WHITE = [[Interface\Buttons\WHITE8X8]]
Skin.WHITE = WHITE

Skin.colors = {
	window = { 0.05, 0.05, 0.07, 0.97 },
	panel = { 0.09, 0.09, 0.11, 1 },
	border = { 0.24, 0.24, 0.29, 1 },
	button = { 0.15, 0.15, 0.18, 1 },
	buttonHover = { 0.21, 0.21, 0.26, 1 },
	accent = { 0.31, 0.64, 1, 1 },
	selected = { 0.31, 0.64, 1, 0.22 },
	hover = { 1, 1, 1, 0.06 },
	text = { 0.92, 0.92, 0.92, 1 },
	textDim = { 0.58, 0.58, 0.63, 1 },
	warning = { 1, 0.35, 0.3, 1 },
}

Skin.fonts = {
	normal = "GameFontHighlightSmall",
	title = "GameFontNormal",
	header = "GameFontNormalSmall",
}

-- Flat 1px-bordered panel. The frame must inherit "BackdropTemplate".
function Skin.ApplyPanel(frame, background, border)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(unpack(Skin.colors[background or "panel"]))
	frame:SetBackdropBorderColor(unpack(Skin.colors[border or "border"]))
end

function Skin.FontString(parent, font, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY", Skin.fonts[font or "normal"])
	fs:SetWordWrap(false)
	return fs
end
