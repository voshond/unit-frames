local _, ns = ...
local Media, Util = ns.Media, ns.Util
local Backdrop = ns.Components.Backdrop

--[[
A status bar: health, power, experience, cast progress, ...

Structure (frame tree):
  frame    root, carries the optional border/background (Backdrop)
  bar      the StatusBar, inset inside the border
  clip     clips the segments to the bar's bounds
  overlay  above everything; spark lives here and text components are parented here

Segments are extra StatusBars chained to the end of the main fill, the same
way oUF does heal prediction. They are declared per instance through `spec`:
  Bar:New(parent, config, { segments = {
      { key = "heal",   label = "Incoming heals", mode = "append", colorInherit = "colors.heal" },
      { key = "absorb", label = "Absorbs",        mode = "append", colorInherit = "colors.absorb" },
      { key = "healAbsorb", label = "Heal absorbs", mode = "inset", colorInherit = "colors.healAbsorb" },
  } })
  append: starts where the previous append segment (or the fill) ends and grows outward
  inset:  pinned at the fill's end and grows back into the fill
  overlay: pinned at the whole bar's end and grows inward, even at full health

Segment positions are pure anchoring and every value goes straight into a
StatusBar, so all of this works with secret values.

SetTint(r, g, b, amount) temporarily recolours the bar (ready checks). The
data colour may be secret, so instead of blending it the tint is drawn over
the fill and background and faded with region alpha. Segment colours are
plain settings and blend directly.
]]
local Bar = ns.Component:Extend("Bar")

Bar.ORIENTATIONS = {
	{ "HORIZONTAL", "Horizontal" },
	{ "VERTICAL", "Vertical" },
}

Bar.SHIELD_PLACEMENTS = {
	{ "overlay", "Overlay health" },
	{ "append", "After health" },
}

Bar.schema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "texture", type = "statusbar", label = "Texture", inherit = "barTexture" },
	{ key = "color", type = "color", label = "Colour", inherit = "colors.health",
		tooltip = "Used until the data source sets a colour (class, power type, ...)." },
	{ key = "orientation", type = "select", label = "Orientation", values = Bar.ORIENTATIONS, default = "HORIZONTAL" },
	{ key = "reverseFill", type = "toggle", label = "Reverse fill", default = false },
	{ key = "smooth", type = "toggle", label = "Smooth changes", default = true },
	{ key = "spark", type = "toggle", label = "Spark", default = false },
	{ key = "background", type = "group", label = "Background", schema = {
		{ key = "enabled", type = "toggle", label = "Enabled", default = true },
		{ key = "useBarColor", type = "toggle", label = "Tint with bar colour", default = true },
		{ key = "alpha", type = "range", label = "Opacity", min = 0, max = 1, step = 0.05, default = 0.25,
			hidden = function(cfg) return not cfg.useBarColor end },
		{ key = "color", type = "color", label = "Colour", default = { 0, 0, 0, 0.5 },
			hidden = function(cfg) return cfg.useBarColor end },
	} },
	{ key = "border", type = "group", label = "Border", schema = Backdrop.schema, defaults = { enabled = false } },
}

-- Where segments and the spark attach, per orientation and fill direction.
-- Each pair is { segment point, point on the target fill texture }.
local LAYOUT = {
	HORIZONTAL = {
		[false] = {
			append = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } },
			inset = { { "TOPRIGHT", "TOPRIGHT" }, { "BOTTOMRIGHT", "BOTTOMRIGHT" } },
			spark = "RIGHT",
		},
		[true] = {
			append = { { "TOPRIGHT", "TOPLEFT" }, { "BOTTOMRIGHT", "BOTTOMLEFT" } },
			inset = { { "TOPLEFT", "TOPLEFT" }, { "BOTTOMLEFT", "BOTTOMLEFT" } },
			spark = "LEFT",
		},
	},
	VERTICAL = {
		[false] = {
			append = { { "BOTTOMLEFT", "TOPLEFT" }, { "BOTTOMRIGHT", "TOPRIGHT" } },
			inset = { { "TOPLEFT", "TOPLEFT" }, { "TOPRIGHT", "TOPRIGHT" } },
			spark = "TOP",
		},
		[true] = {
			append = { { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } },
			inset = { { "BOTTOMLEFT", "BOTTOMLEFT" }, { "BOTTOMRIGHT", "BOTTOMRIGHT" } },
			spark = "BOTTOM",
		},
	},
}
Bar.LAYOUT = LAYOUT

local SPARK_TEXTURE = [[Interface\CastingBar\UI-CastingBar-Spark]]

function Bar.BuildSchema(spec)
	spec = spec or {}
	local schema = Util.Copy(Bar.schema)
	if spec.colorInherit then
		schema = ns.Schema.Override(schema, "color", { inherit = spec.colorInherit })
	end
	if spec.segments and #spec.segments > 0 then
		local segmentSchema = {}
		for _, seg in ipairs(spec.segments) do
			segmentSchema[#segmentSchema + 1] = {
				key = seg.key, type = "group", label = seg.label or seg.key,
				schema = {
					{ key = "enabled", type = "toggle", label = "Enabled", default = true },
					{ key = "color", type = "color", label = "Colour", inherit = seg.colorInherit, default = { 1, 1, 1, 0.5 } },
					{ key = "texture", type = "statusbar", label = "Texture", inherit = "barTexture" },
				},
			}
			if seg.configurablePlacement then
				local options = segmentSchema[#segmentSchema].schema
				options[#options + 1] = {
					key = "placement", type = "select", label = "Placement",
					values = Bar.SHIELD_PLACEMENTS, default = seg.mode,
					tooltip = "Overlay health draws inward from the end of the bar. After health reserves space within the bar for shields after the health fill, including at full health; health text stays unchanged.",
				}
			end
		end
		schema[#schema + 1] = { key = "segments", type = "group", label = "Segments", schema = segmentSchema }
	end
	return schema
end

function Bar:OnCreate(parent, spec)
	self.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")

	self.bar = CreateFrame("StatusBar", nil, self.frame)
	self.bar:SetMinMaxValues(0, 1)
	self.bar:SetValue(1)

	self.bg = self.bar:CreateTexture(nil, "BACKGROUND")
	self.bg:SetAllPoints(self.bar)
	self.tintBg = self.bar:CreateTexture(nil, "BACKGROUND", nil, 1)
	self.tintBg:SetAllPoints(self.bar)
	self.tintBg:SetDesaturated(true)
	self.tintBg:Hide()

	self.clip = CreateFrame("Frame", nil, self.bar)
	self.clip:SetAllPoints(self.bar)
	self.clip:SetClipsChildren(true)
	-- Above the fill (the clip frame draws over the bar), below the segments.
	self.tintFill = self.clip:CreateTexture(nil, "BACKGROUND")
	self.tintFill:SetDesaturated(true)
	self.tintFill:Hide()

	self.segments = {}
	self.segmentsByKey = {}
	for _, seg in ipairs(spec.segments or {}) do
		local entry = {
			key = seg.key,
			mode = seg.mode or "append",
			appendToFill = seg.appendToFill,
			bar = CreateFrame("StatusBar", nil, self.clip),
		}
		entry.bar:SetMinMaxValues(0, 1)
		entry.bar:SetValue(0)
		self.segments[#self.segments + 1] = entry
		self.segmentsByKey[seg.key] = entry
	end

	self.overlay = CreateFrame("Frame", nil, self.bar)
	self.overlay:SetAllPoints(self.bar)
	self.overlay:SetFrameLevel(self.bar:GetFrameLevel() + 3)

	self.spark = self.overlay:CreateTexture(nil, "OVERLAY")
	self.spark:SetTexture(SPARK_TEXTURE)
	self.spark:SetBlendMode("ADD")

	self.bar:SetScript("OnSizeChanged", function(_, width, height)
		self:SizeParts(width, height)
	end)
end

function Bar:OnApply(cfg)
	Backdrop.ApplyTo(self.frame, cfg.border)
	Backdrop.Inset(self.bar, self.frame, cfg.border)

	local texture = Media:Fetch("statusbar", cfg.texture)
	self.bar:SetStatusBarTexture(texture)
	self.bar:SetOrientation(cfg.orientation)
	self.bar:SetReverseFill(cfg.reverseFill)
	self.bg:SetTexture(texture)
	self.bg:SetShown(cfg.background.enabled)
	self.tintBg:SetTexture(texture)
	self.tintFill:SetTexture(texture)
	self.tintFill:ClearAllPoints()
	self.tintFill:SetAllPoints(self.bar:GetStatusBarTexture())
	self:ApplyTint()

	if cfg.smooth and ns.Caps.smoothBars then
		self.interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut
	else
		self.interpolation = nil
	end

	if self.dataColor then
		self:SetColor(unpack(self.dataColor, 1, 4))
	else
		self:ApplyColor(Util.UnpackColor(cfg.color))
	end

	local layout = LAYOUT[cfg.orientation][cfg.reverseFill]
	local fill = self.bar:GetStatusBarTexture()
	local previous = fill
	for _, seg in ipairs(self.segments) do
		local segCfg = cfg.segments[seg.key]
		local mode = segCfg.placement or seg.mode
		local sb = seg.bar
		sb:ClearAllPoints()
		sb:SetStatusBarTexture(Media:Fetch("statusbar", segCfg.texture))
		sb:SetStatusBarColor(self:SegmentColor(segCfg.color))
		sb:SetOrientation(cfg.orientation)
		if segCfg.enabled then
			local target = mode == "append" and (seg.appendToFill and fill or previous)
				or (mode == "overlay" and self.bar or fill)
			for _, pair in ipairs(layout[mode == "overlay" and "inset" or mode]) do
				sb:SetPoint(pair[1], target, pair[2])
			end
			if mode == "append" then
				sb:SetReverseFill(cfg.reverseFill)
				previous = sb:GetStatusBarTexture()
			else
				sb:SetReverseFill(not cfg.reverseFill)
			end
			sb:Show()
		else
			sb:Hide()
		end
	end

	self.spark:ClearAllPoints()
	-- Fill geometry can be secret. Native anchors follow its cross-axis
	-- bounds without passing GetSize/OnSizeChanged values to texture setters.
	-- Extend the glow six units beyond either edge, with a twelve-unit width.
	if cfg.orientation == "HORIZONTAL" then
		self.spark:SetWidth(12)
		self.spark:SetPoint("TOP", fill, "TOP" .. layout.spark, 0, 6)
		self.spark:SetPoint("BOTTOM", fill, "BOTTOM" .. layout.spark, 0, -6)
	else
		self.spark:SetHeight(12)
		self.spark:SetPoint("LEFT", fill, layout.spark .. "LEFT", -6, 0)
		self.spark:SetPoint("RIGHT", fill, layout.spark .. "RIGHT", 6, 0)
	end
	self.spark:SetRotation(cfg.orientation == "VERTICAL" and math.pi / 2 or 0)
	self.spark:SetShown(cfg.spark)

	self:SizeParts(self.bar:GetSize())
end

-- Segments must be as long as the whole bar so their values use the same scale.
function Bar:SizeParts(width, height)
	if not self.resolved then
		return
	end
	local horizontal = self.resolved.orientation == "HORIZONTAL"
	for _, seg in ipairs(self.segments) do
		if horizontal then
			seg.bar:SetWidth(width)
		else
			seg.bar:SetHeight(height)
		end
	end
end

function Bar:ApplyColor(r, g, b, a)
	self.bar:SetStatusBarColor(r, g, b, a or 1)
	local bg = self.resolved.background
	if bg.useBarColor then
		self.bg:SetVertexColor(r, g, b, bg.alpha)
	else
		self.bg:SetVertexColor(Util.UnpackColor(bg.color))
	end
end

-- Data API ------------------------------------------------------------------
-- All of these accept secret values.

function Bar:SetRange(min, max)
	self.bar:SetMinMaxValues(min, max)
	for _, seg in ipairs(self.segments) do
		seg.bar:SetMinMaxValues(min, max)
	end
end

function Bar:SetValue(value)
	if self.interpolation then
		self.bar:SetValue(value, self.interpolation)
	else
		self.bar:SetValue(value)
	end
end

function Bar:SetSegmentValue(key, value)
	local seg = self.segmentsByKey[key]
	if not seg then
		return
	end
	if self.interpolation then
		seg.bar:SetValue(value, self.interpolation)
	else
		seg.bar:SetValue(value)
	end
end

function Bar:HasSegment(key)
	return self.segmentsByKey[key] ~= nil
end

-- The StatusBar of an enabled segment (for oUF sub-widgets), else nil.
function Bar:GetSegmentBar(key)
	local seg = self.segmentsByKey[key]
	if seg and self.resolved.segments[key].enabled then
		return seg.bar
	end
end

-- Colour set by the data source (class colour, power colour, curve result).
-- It survives re-styling until ClearColor.
function Bar:SetColor(r, g, b, a)
	self.dataColor = { r, g, b, a or 1 }
	self:ApplyColor(r, g, b, a)
end

function Bar:ClearColor()
	self.dataColor = nil
	self:ApplyColor(Util.UnpackColor(self.resolved.color))
end

-- Plain tint colour over the bar at `amount` (0..1, default 1); no colour
-- or a zero amount removes it. It survives re-styling until removed.
function Bar:SetTint(r, g, b, amount)
	amount = amount or 1
	if r == nil or amount <= 0 then
		self.tint = nil
	else
		self.tint = { r, g, b, math.min(amount, 1) }
	end
	self:ApplyTint()
end

function Bar:ApplyTint()
	local tint, cfg = self.tint, self.resolved
	local background = cfg.background
	-- A fixed background colour stays; one tinted with the bar colour fades
	-- over to the tint like the fill.
	local tintBackground = tint ~= nil and background.enabled and background.useBarColor
	self.tintFill:SetShown(tint ~= nil)
	self.tintBg:SetShown(tintBackground)
	if tint then
		self.tintFill:SetVertexColor(tint[1], tint[2], tint[3], 1)
		self.tintFill:SetAlpha(tint[4])
	end
	if tintBackground then
		self.tintBg:SetVertexColor(tint[1], tint[2], tint[3], background.alpha)
		self.tintBg:SetAlpha(tint[4])
		self.bg:SetAlpha(1 - tint[4])
	else
		self.bg:SetAlpha(1)
	end
	for _, seg in ipairs(self.segments) do
		seg.bar:SetStatusBarColor(self:SegmentColor(cfg.segments[seg.key].color))
	end
end

-- A segment's configured colour blended towards the tint.
function Bar:SegmentColor(color)
	local r, g, b, a = Util.UnpackColor(color)
	local tint = self.tint
	if not tint then
		return r, g, b, a
	end
	local t = tint[4]
	return r + (tint[1] - r) * t, g + (tint[2] - g) * t, b + (tint[3] - b) * t, a
end

function Bar:GetTint()
	if self.tint then
		return unpack(self.tint, 1, 4)
	end
end

-- Engine-driven fill from a Duration object (casts). direction is an
-- Enum.StatusBarTimerDirection value.
function Bar:SetTimerDuration(duration, direction)
	self.bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, direction)
end

-- Frame that texts should be parented to, so they draw above the segments.
function Bar:GetTextParent()
	return self.overlay
end

function Bar:GetStatusBar()
	return self.bar
end
