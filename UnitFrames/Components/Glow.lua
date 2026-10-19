local _, ns = ...

-- A soft halo just outside a frame: one nine-sliced texture of our own
-- artwork (scripts/generate-glow.lua), drawn additively, brightest at the
-- frame's edge. Scaling the texture sets the drawn slice width, the glow's
-- reach; its anchor offsets are in the scaled texture's units. No dimensions
-- are read.
local Glow = {}
ns.Glow = Glow

local REACH = 31
local MEDIA = "Interface\\AddOns\\" .. ns.name .. "\\Media\\"
-- Artwork and slice margin in texels: the reach outside the frame, plus for
-- glows under a frame the inset, corner radius and inner fade inside it.
local OUTSIDE = { texture = MEDIA .. "Glow", margin = REACH }
Glow.FRAME_SHAPES = {
	sharp = { texture = MEDIA .. "GlowFrame", margin = REACH + 12 },
	soft = { texture = MEDIA .. "GlowFrameSoft", margin = REACH + 20 },
	round = { texture = MEDIA .. "GlowFrameRound", margin = REACH + 32 },
}

Glow.schema = {
	{ key = "size", type = "range", label = "Glow size", min = 4, max = 32, step = 1, default = 12,
		tooltip = "How far the glow reaches outside the frame. It never covers the frame itself." },
	{ key = "opacity", type = "range", label = "Glow opacity", min = 0.1, max = 1, step = 0.05, default = 1 },
}

-- Corner shapes of glows drawn under a frame (Create with `under`).
Glow.CORNERS_OPTION = { key = "corners", type = "select", label = "Glow corners", default = "soft", values = {
	{ "sharp", "Sharp" }, { "soft", "Slightly rounded" }, { "round", "Rounded" },
}, tooltip = "Rounded corners soften the glow around the frame's corners. They grow with the glow size." }

Glow.UNDER_SCHEMA = ns.Schema.Concat(Glow.schema, { Glow.CORNERS_OPTION })

-- Holders drawn under a frame -> that frame.
local underFrames = setmetatable({}, { __mode = "k" })

-- One level below its frame. The level is fixed: the client re-levels
-- children above their parent whenever the parent's level changes, which
-- would lift the glow over the frame. Owners call this after re-levelling.
function Glow.SyncLevel(holder)
	local under = underFrames[holder]
	if not under then return end
	holder:SetFrameLevel(math.max(0, under:GetFrameLevel() - 1))
	holder:SetFixedFrameLevel(true)
end
local SyncLevel = Glow.SyncLevel

--[[
A hidden holder; toggle it rather than its texture. With `under` (the frame
the glow surrounds) the holder covers that frame one frame level below it,
so the frame's backdrop and contents sit on top of the glow; it starts
under the frame's edge (Glow.FRAME_SHAPES) and takes Glow.UNDER_SCHEMA.
The holder stays `parent`'s child for its visibility either way.
]]
function Glow.Create(parent, under)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetAllPoints(under or parent)
	local halo = holder:CreateTexture(nil, under and "BACKGROUND" or "OVERLAY")
	halo:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
	halo:SetBlendMode("ADD")
	holder.Halo, holder.textures = halo, { halo }
	underFrames[holder] = under
	SyncLevel(holder)
	holder:Hide()
	return holder
end

local applied = setmetatable({}, { __mode = "k" })

-- The glow reaches the same distance outside the frame for every shape: in
-- the scaled texture's units that is the anchor offset.
function Glow.Apply(holder, cfg)
	SyncLevel(holder)
	local corners = underFrames[holder] and cfg.corners or nil
	local previous = applied[holder]
	if previous and previous.size == cfg.size and previous.opacity == cfg.opacity and previous.corners == corners then return end
	local halo = holder.Halo
	local shape = corners and Glow.FRAME_SHAPES[corners] or OUTSIDE
	halo:SetTexture(shape.texture)
	halo:SetTextureSliceMargins(shape.margin, shape.margin, shape.margin, shape.margin)
	halo:SetScale(cfg.size / REACH)
	halo:ClearAllPoints()
	halo:SetPoint("TOPLEFT", holder, "TOPLEFT", -REACH, REACH)
	halo:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", REACH, -REACH)
	holder:SetAlpha(cfg.opacity)
	applied[holder] = { size = cfg.size, opacity = cfg.opacity, corners = corners }
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
