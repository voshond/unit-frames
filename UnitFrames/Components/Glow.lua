local _, ns = ...

-- A soft halo just outside a frame: one nine-sliced texture of our own
-- artwork (scripts/generate-glow.lua), drawn additively, brightest at the
-- frame's edge. Scaling the texture sets the drawn slice width, the glow's
-- reach; its anchor offsets are in the scaled texture's units. No dimensions
-- are read.
local Glow = {}
ns.Glow = Glow

local TEXTURE = "Interface\\AddOns\\" .. ns.name .. "\\Media\\Glow"
-- The artwork's slice margin in texels.
local MARGIN = 31

Glow.schema = {
	{ key = "size", type = "range", label = "Glow size", min = 4, max = 32, step = 1, default = 12,
		tooltip = "How far the glow reaches outside the frame. It never covers the frame itself." },
	{ key = "opacity", type = "range", label = "Glow opacity", min = 0.1, max = 1, step = 0.05, default = 1 },
}

-- A hidden holder; toggle it rather than its texture.
function Glow.Create(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetAllPoints(parent)
	local halo = holder:CreateTexture(nil, "OVERLAY")
	halo:SetTexture(TEXTURE)
	halo:SetTextureSliceMargins(MARGIN, MARGIN, MARGIN, MARGIN)
	halo:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
	halo:SetBlendMode("ADD")
	holder.Halo, holder.textures = halo, { halo }
	holder:Hide()
	return holder
end

local applied = setmetatable({}, { __mode = "k" })

-- The slices' inner edge meets the holder's edge: in the scaled texture's
-- units the anchor offset is the margin itself.
function Glow.Apply(holder, cfg)
	local previous = applied[holder]
	if previous and previous.size == cfg.size and previous.opacity == cfg.opacity then return end
	local halo = holder.Halo
	halo:SetScale(cfg.size / MARGIN)
	halo:ClearAllPoints()
	halo:SetPoint("TOPLEFT", holder, "TOPLEFT", -MARGIN, MARGIN)
	halo:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", MARGIN, -MARGIN)
	holder:SetAlpha(cfg.opacity)
	applied[holder] = { size = cfg.size, opacity = cfg.opacity }
	ns.Perf:Count("glowLayoutWrite")
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
