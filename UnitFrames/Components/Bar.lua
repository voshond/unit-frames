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

spec.overheal: the bar offers an Overheal edge warning (Components/Overheal.lua).

spec.nativeLayout: the owner may anchor the bar to native, possibly secret
geometry (a collapsing aura row). The root opts into Blizzard's forbidden
layout aspect at creation, so no size script runs: the owner supplies its
plain row size through SetKnownSize for the border and segment lengths.

SetTint(r, g, b, amount) temporarily recolours the bar (ready checks). The
data colour may be secret, so instead of blending it the tint is drawn over
the fill and background and crossfaded by opacity. Segment colours are
plain settings and blend directly. Fades use vertex colour alpha only: a
texture's SetAlpha replaces its vertex alpha (the background's opacity).
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
Bar.SPARK_TEXTURE = SPARK_TEXTURE
local NATIVE_LAYOUT_TEMPLATE = "BackdropTemplate,DisableUntrustedLayoutScriptsTemplate"

-- Puts a spark texture at the end of a StatusBar fill texture.
-- Fill geometry can be secret. Native anchors follow its cross-axis
-- bounds without passing GetSize/OnSizeChanged values to texture setters.
-- Extend the glow six units beyond either edge, with a twelve-unit width.
function Bar.AnchorSpark(spark, fill, orientation, reverseFill)
	local edge = LAYOUT[orientation][reverseFill].spark
	spark:ClearAllPoints()
	if orientation == "HORIZONTAL" then
		spark:SetTexCoord(0, 1, 0, 1)
		spark:SetWidth(12)
		spark:SetPoint("TOP", fill, "TOP" .. edge, 0, 6)
		spark:SetPoint("BOTTOM", fill, "BOTTOM" .. edge, 0, -6)
	else
		-- Rotate the artwork within the already horizontal spark rectangle.
		-- SetRotation rotates the rendered rectangle too, distorting its
		-- cross-axis span when width and height have already been swapped.
		spark:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
		spark:SetHeight(12)
		spark:SetPoint("LEFT", fill, edge .. "LEFT", -6, 0)
		spark:SetPoint("RIGHT", fill, edge .. "RIGHT", 6, 0)
	end
end

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
	if spec.overheal then
		schema[#schema + 1] = { key = "overheal", type = "group", label = "Overheal", schema = ns.Overheal.schema }
	end
	return schema
end

function Bar:OnCreate(parent, spec)
	self.frame = CreateFrame("Frame", nil, parent, spec.nativeLayout and NATIVE_LAYOUT_TEMPLATE or "BackdropTemplate")

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
	-- Covers a dead unit's fill in one uniform colour (ApplyGhost anchors it).
	self.ghostFill = self.clip:CreateTexture(nil, "BACKGROUND", nil, 1)
	self.ghostFill:SetDesaturated(true)
	self.ghostFill:Hide()

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

	-- Created before the texts, which join the overlay later and so draw above it.
	if spec.overheal then self.overheal = ns.Overheal:New(self) end

	self.spark = self.overlay:CreateTexture(nil, "OVERLAY")
	self.spark:SetTexture(SPARK_TEXTURE)
	self.spark:SetBlendMode("ADD")

	if spec.nativeLayout then
		-- oUF's health element reads the StatusBar's size on every update to
		-- size prediction bars; anchored to native geometry it is secret.
		-- Lua callers get the plain known size instead (methods only shadow
		-- the widget's Lua table; the engine keeps using the real geometry).
		local bar = self.bar
		function bar.GetWidth() return (self:GetKnownInnerSize()) end
		function bar.GetHeight() return select(2, self:GetKnownInnerSize()) end
		function bar.GetSize() return self:GetKnownInnerSize() end
	else
		self.bar:SetScript("OnSizeChanged", function(_, width, height)
			self:SizeParts(width, height)
		end)
	end
end

function Bar:OnApply(cfg)
	if self.spec.nativeLayout then
		Backdrop.ApplyToFixedSize(self.frame, cfg.border, self:GetKnownSize())
	else
		Backdrop.ApplyTo(self.frame, cfg.border)
	end
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
	self.ghostFill:SetTexture(texture)
	self:ApplyTint()
	self:ApplyGhost()

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

	if self.overheal then self.overheal:Apply(cfg.overheal, cfg.orientation, cfg.reverseFill, layout) end

	Bar.AnchorSpark(self.spark, fill, cfg.orientation, cfg.reverseFill)
	self.spark:SetShown(cfg.spark and self.sparkActive ~= false)

	if self.spec.nativeLayout then
		self:SizeParts(self:GetKnownInnerSize())
	else
		self:SizeParts(self.bar:GetSize())
	end
end

function Bar:SetSparkActive(active)
	self.sparkActive = active
	if self.resolved then self.spark:SetShown(self.resolved.spark and active ~= false) end
end

-- Native-layout bars: the row size the owner laid out, in plain numbers.
-- A collapsing row can make the bar longer than this; a horizontal bar
-- keeps its width, so only vertical bars' segments then use a stale length.
function Bar:SetKnownSize(width, height)
	self.knownWidth, self.knownHeight = width, height
	if self.resolved then
		Backdrop.ApplyToFixedSize(self.frame, self.resolved.border, width, height)
		self:SizeParts(self:GetKnownInnerSize())
	end
end

function Bar:GetKnownSize()
	return self.knownWidth or 1, self.knownHeight or 1
end

-- The StatusBar's share of the known size, inside the border padding.
function Bar:GetKnownInnerSize()
	local width, height = self:GetKnownSize()
	if not self.resolved then return width, height end
	local border = self.resolved.border
	local left, right, top, bottom = Backdrop.Padding(border)
	return math.max(0, width - left - right), math.max(0, height - top - bottom)
end

-- Segments must be as long as the whole bar so their values use the same scale.
-- A bar anchored to secret geometry reports secret dimensions, which size
-- setters refuse from addon code: its segments keep their last plain length.
function Bar:SizeParts(width, height)
	if not self.resolved then
		return
	end
	local horizontal = self.resolved.orientation == "HORIZONTAL"
	if Util.IsSecret(horizontal and width or height) then
		return
	end
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
		-- A tint fades this background out as its own fades in.
		local tint = self.tint and self.tint[4] or 0
		self.bg:SetVertexColor(r, g, b, bg.alpha * (1 - tint))
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

-- The StatusBar of an enabled segment (for oUF sub-widgets), else nil.
function Bar:GetSegmentBar(key)
	local seg = self.segmentsByKey[key]
	if seg and self.resolved.segments[key].enabled then
		return seg.bar
	end
end

-- The overheal edge warning when it is offered and enabled, else nil.
function Bar:GetOverheal()
	if self.overheal and self.resolved.overheal.enabled then
		return self.overheal
	end
end

-- Colour set by the data source (class colour, power colour, curve result).
-- It survives re-styling until ClearColor.
function Bar:SetColor(r, g, b, a)
	self.dataColor = self.dataColor or {}
	self.dataColor[1], self.dataColor[2], self.dataColor[3], self.dataColor[4] = r, g, b, a or 1
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
		self.tintStorage = self.tintStorage or {}
		self.tint = self.tintStorage
		self.tint[1], self.tint[2], self.tint[3], self.tint[4] = r, g, b, math.min(amount, 1)
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
		self.tintFill:SetVertexColor(tint[1], tint[2], tint[3], tint[4])
	end
	if tintBackground then
		self.tintBg:SetVertexColor(tint[1], tint[2], tint[3], background.alpha * tint[4])
	end
	-- The bar-coloured background's share (ApplyColor). The data colour
	-- may be secret; it is only passed back to the texture.
	if self.dataColor then
		self:ApplyColor(unpack(self.dataColor, 1, 4))
	else
		self:ApplyColor(Util.UnpackColor(cfg.color))
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

-- Opaque greyscale paint over the fill of a dead unit's bar, so the data
-- colour no longer shows through, blended from white towards the plain colour
-- at `amount` (0..1, default 1). `wholeBar` paints the bar's whole length
-- instead (health: a StatusBar still draws a sliver at its minimum). nil
-- shows the fill again. It survives re-styling until removed.
function Bar:SetGhost(r, g, b, amount, wholeBar)
	if r == nil then
		self.ghost = nil
	else
		self.ghostStorage = self.ghostStorage or {}
		self.ghost = self.ghostStorage
		self.ghost[1], self.ghost[2], self.ghost[3], self.ghost[4] = r, g, b, math.min(amount or 1, 1)
		self.ghost.wholeBar = wholeBar == true
	end
	self:ApplyGhost()
end

function Bar:ApplyGhost()
	local ghost = self.ghost
	self.ghostFill:SetShown(ghost ~= nil)
	if not ghost then return end
	self.ghostFill:ClearAllPoints()
	self.ghostFill:SetAllPoints(ghost.wholeBar and self.bar or self.bar:GetStatusBarTexture())
	local t = ghost[4]
	self.ghostFill:SetVertexColor(1 + (ghost[1] - 1) * t, 1 + (ghost[2] - 1) * t, 1 + (ghost[3] - 1) * t, 1)
end

function Bar:GetGhost()
	if self.ghost then
		return unpack(self.ghost, 1, 4)
	end
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
