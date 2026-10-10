local _, ns = ...
local Media, Util = ns.Media, ns.Util

-- Background + border around a frame. Defaults come from the theme, which
-- uses Blizzard's tooltip border for the chamfered "classic" look.
--
-- Other components embed it as a `border` group and call Backdrop.ApplyTo.
local Backdrop = ns.Component:Extend("Backdrop")

Backdrop.schema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "border", type = "border", label = "Border", inherit = "borderTexture" },
	{ key = "size", type = "range", label = "Border size", min = 1, max = 32, step = 1, inherit = "borderSize" },
	{ key = "color", type = "color", label = "Border colour", inherit = "borderColor" },
	{ key = "background", type = "background", label = "Background", inherit = "backgroundTexture" },
	{ key = "backgroundColor", type = "color", label = "Background colour", inherit = "backgroundColor" },
	{ key = "inset", type = "range", label = "Background inset", min = 0, max = 16, step = 1, default = 3,
		tooltip = "How far the background is pulled in from the outer edge, so it doesn't poke out of rounded corners." },
	{ key = "padding", type = "range", label = "Content padding", min = 0, max = 16, step = 1, default = 4,
		tooltip = "Space between the border and the content inside it." },
}

-- LSM's "None" entries are "", which BackdropTemplate treats as a texture.
local function Path(kind, key)
	local path = Media:Fetch(kind, key)
	if path == "" then
		return nil
	end
	return path
end

-- Applies resolved backdrop settings to a frame created with "BackdropTemplate".
function Backdrop.ApplyTo(frame, cfg)
	if not cfg.enabled then
		frame:ClearBackdrop()
		return
	end
	local inset = cfg.inset
	frame:SetBackdrop({
		bgFile = Path("background", cfg.background),
		edgeFile = Path("border", cfg.border),
		edgeSize = cfg.size,
		tile = true,
		tileSize = 16,
		insets = { left = inset, right = inset, top = inset, bottom = inset },
	})
	frame:SetBackdropColor(Util.UnpackColor(cfg.backgroundColor))
	frame:SetBackdropBorderColor(Util.UnpackColor(cfg.color))
end

-- Aura descendants can report secret dimensions even outside combat.
-- BackdropTemplate's Lua UV calculation does arithmetic on GetWidth/Height;
-- provide the known configured size to that calculation instead. Region
-- methods still operate on the real textures, never on this geometry view.
local fixedSizes = setmetatable({}, { __mode = "k" })
function Backdrop.ApplyToFixedSize(frame, cfg, width, height)
	local geometry = fixedSizes[frame]
	if not geometry then
		geometry = setmetatable({}, { __index = function(_, key) return frame[key] end })
		geometry.GetWidth = function() return geometry.width end
		geometry.GetHeight = function() return geometry.height end
		geometry.GetEffectiveScale = function() return frame:GetEffectiveScale() end
		geometry.GetEdgeSize = function() return frame:GetEdgeSize() end
		fixedSizes[frame] = geometry
		-- The owner updates the fixed size explicitly. Do not run an addon
		-- size-change script when Blizzard changes the aura's secret layout.
		frame:SetScript("OnSizeChanged", nil)
		frame.SetupTextureCoordinates = function()
			BackdropTemplateMixin.SetupTextureCoordinates(geometry)
		end
	end
	geometry.width, geometry.height = width, height
	Backdrop.ApplyTo(frame, cfg)
end

-- Anchors `content` inside `frame`, leaving room for the border.
function Backdrop.Inset(content, frame, cfg)
	local pad = cfg.enabled and cfg.padding or 0
	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
end

function Backdrop:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
end

function Backdrop:OnApply(cfg)
	Backdrop.ApplyTo(self.frame, cfg)
end

-- A disabled backdrop stays shown (it may hold content) but draws nothing.
function Backdrop:SetEnabled(enabled)
	self.enabled = enabled and true or false
end
