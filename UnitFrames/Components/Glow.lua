local _, ns = ...

-- A soft halo around a frame from Blizzard's own glow border artwork: the
-- additive eight-piece box Blizzard_HelpPlate tints and draws around
-- highlighted areas. Pieces anchor to the holder, so no dimensions are read;
-- owners pass known configured sizes to keep the corners from overlapping.
local Glow = {}
ns.Glow = Glow

local CORNER = [[Interface\Common\GlowBorder-Corner]]
local TOP = [[Interface\Common\GlowBorder-Top]]
local LEFT = [[Interface\Common\GlowBorder-Left]]

-- { key, file, texture coordinates } as in Blizzard_HelpPlate.xml.
local PIECES = {
	{ "TopLeft", CORNER, 0, 1, 0, 1 },
	{ "TopRight", CORNER, 1, 0, 0, 1 },
	{ "BottomLeft", CORNER, 0, 1, 1, 0 },
	{ "BottomRight", CORNER, 1, 0, 1, 0 },
	{ "Top", TOP, 0, 1, 0, 1 },
	{ "Bottom", TOP, 0, 1, 1, 0 },
	{ "Left", LEFT, 0, 1, 0, 1 },
	{ "Right", LEFT, 1, 0, 0, 1 },
}

-- Edges stretch between the corners: { piece, first corner, its point, second corner, its point }.
local EDGES = {
	{ "Top", "TopLeft", "TOPRIGHT", "TopRight", "BOTTOMLEFT" },
	{ "Bottom", "BottomLeft", "TOPRIGHT", "BottomRight", "BOTTOMLEFT" },
	{ "Left", "TopLeft", "BOTTOMLEFT", "BottomLeft", "TOPRIGHT" },
	{ "Right", "TopRight", "BOTTOMLEFT", "BottomRight", "TOPRIGHT" },
}

Glow.schema = {
	{ key = "size", type = "range", label = "Glow size", min = 4, max = 32, step = 1, default = 16,
		tooltip = "Width of the glow's corners and edges." },
	{ key = "offset", type = "range", label = "Glow spread", min = 0, max = 32, step = 1, default = 8,
		tooltip = "How far the glow reaches outside the frame. The rest of its size lies inside." },
	{ key = "opacity", type = "range", label = "Glow opacity", min = 0.1, max = 1, step = 0.05, default = 1 },
	{ key = "additive", type = "toggle", label = "Additive glow", default = true,
		tooltip = "Brighten what lies beneath, like Blizzard's highlights. Disable for a flatter glow that stays visible on bright bars." },
}

-- A hidden holder; toggle it rather than its pieces.
function Glow.Create(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetAllPoints(parent)
	holder.textures = {}
	for _, piece in ipairs(PIECES) do
		local texture = holder:CreateTexture(nil, "OVERLAY")
		texture:SetTexture(piece[2])
		texture:SetTexCoord(piece[3], piece[4], piece[5], piece[6])
		holder[piece[1]] = texture
		holder.textures[#holder.textures + 1] = texture
	end
	for _, edge in ipairs(EDGES) do
		local texture = holder[edge[1]]
		texture:SetPoint("TOPLEFT", holder[edge[2]], edge[3])
		texture:SetPoint("BOTTOMRIGHT", holder[edge[4]], edge[5])
	end
	holder:Hide()
	return holder
end

-- width/height: the holder's known configured size, when the owner has one.
function Glow.Apply(holder, cfg, width, height)
	local offset = math.min(cfg.offset, cfg.size)
	local size = cfg.size
	if width and height then size = math.min(size, offset + math.floor(math.min(width, height) / 2)) end
	for _, key in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight" }) do
		holder[key]:SetSize(size, size)
		holder[key]:ClearAllPoints()
	end
	holder.TopLeft:SetPoint("TOPLEFT", holder, "TOPLEFT", -offset, offset)
	holder.TopRight:SetPoint("TOPRIGHT", holder, "TOPRIGHT", offset, offset)
	holder.BottomLeft:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", -offset, -offset)
	holder.BottomRight:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", offset, -offset)
	local blend = cfg.additive and "ADD" or "BLEND"
	for _, texture in ipairs(holder.textures) do texture:SetBlendMode(blend) end
	holder:SetAlpha(cfg.opacity)
end

function Glow.SetColor(holder, r, g, b, a)
	for _, texture in ipairs(holder.textures) do texture:SetVertexColor(r, g, b, a) end
end
