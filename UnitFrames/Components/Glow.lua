local _, ns = ...

-- A soft halo around a frame from Blizzard's own glow border artwork: the
-- additive eight-piece box Blizzard_HelpPlate tints and draws around
-- highlighted areas. The art has a black, not transparent, background, so it
-- is always drawn additively. Pieces anchor to the holder, so no dimensions are read;
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
		texture:SetBlendMode("ADD")
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
	holder:SetAlpha(cfg.opacity)
end

-- Blizzard's action button spell alert (ActionButtonSpellAlerts.xml): a burst
-- flipbook once, then a looping one at 1.4 times the square button. The burst
-- is 150px around a 45px button. Desaturated, so owners can tint the gold art.
local PROC_START = "UI-HUD-ActionBar-Proc-Start-Flipbook"
local PROC_LOOP = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local PROC_SCALE, PROC_START_SCALE = 1.4, 150 / 45

local function FlipBook(group, texture, duration)
	local flip = group:CreateAnimation("FlipBook")
	flip:SetTarget(texture)
	flip:SetDuration(duration)
	flip:SetFlipBookRows(6)
	flip:SetFlipBookColumns(5)
	flip:SetFlipBookFrames(30)
	flip:SetFlipBookFrameWidth(0)
	flip:SetFlipBookFrameHeight(0)
end

-- A hidden holder for square owners; every show replays the burst.
function Glow.CreateProc(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetPoint("CENTER", parent, "CENTER")
	local start = holder:CreateTexture(nil, "OVERLAY")
	start:SetAtlas(PROC_START)
	start:SetPoint("CENTER", holder, "CENTER")
	local loop = holder:CreateTexture(nil, "OVERLAY")
	loop:SetAtlas(PROC_LOOP)
	loop:SetAllPoints(holder)
	holder.Start, holder.Loop, holder.textures = start, loop, { start, loop }
	for _, texture in ipairs(holder.textures) do texture:SetDesaturated(true) end

	holder.LoopAnim = holder:CreateAnimationGroup()
	holder.LoopAnim:SetLooping("REPEAT")
	FlipBook(holder.LoopAnim, loop, 1)
	holder.StartAnim = holder:CreateAnimationGroup()
	FlipBook(holder.StartAnim, start, 0.7)
	holder.StartAnim:SetScript("OnFinished", function()
		start:SetAlpha(0)
		loop:SetAlpha(1)
		holder.LoopAnim:Play()
	end)
	holder:SetScript("OnShow", function()
		holder.LoopAnim:Stop()
		start:SetAlpha(1)
		loop:SetAlpha(0)
		holder.StartAnim:Play()
	end)
	holder:SetScript("OnHide", function()
		holder.StartAnim:Stop()
		holder.LoopAnim:Stop()
	end)
	holder:Hide()
	return holder
end

-- size: the owner's known configured square size.
function Glow.ApplyProc(holder, cfg, size)
	holder:SetSize(size * PROC_SCALE, size * PROC_SCALE)
	holder.Start:SetSize(size * PROC_START_SCALE, size * PROC_START_SCALE)
	holder:SetAlpha(cfg.opacity)
end

function Glow.SetColor(holder, r, g, b, a)
	for _, texture in ipairs(holder.textures) do texture:SetVertexColor(r, g, b, a) end
end
