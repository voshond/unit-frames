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

Segment positions are pure anchoring and every value goes straight into a
StatusBar, so all of this works with secret values.
]]
local Bar = ns.Component:Extend("Bar")

Bar.ORIENTATIONS = {
	{ "HORIZONTAL", "Horizontal" },
	{ "VERTICAL", "Vertical" },
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

function Bar:GetSchema()
	if self.schemaCache then
		return self.schemaCache
	end
	local schema = {}
	for i, opt in ipairs(Bar.schema) do
		schema[i] = opt
	end
	if self.spec.colorInherit then
		for i, opt in ipairs(schema) do
			if opt.key == "color" then
				local copy = Util.Copy(opt)
				copy.inherit = self.spec.colorInherit
				schema[i] = copy
			end
		end
	end
	if self.spec.segments and #self.spec.segments > 0 then
		local segmentSchema = {}
		for _, seg in ipairs(self.spec.segments) do
			segmentSchema[#segmentSchema + 1] = {
				key = seg.key, type = "group", label = seg.label or seg.key,
				schema = {
					{ key = "enabled", type = "toggle", label = "Enabled", default = true },
					{ key = "color", type = "color", label = "Colour", inherit = seg.colorInherit, default = { 1, 1, 1, 0.5 } },
					{ key = "texture", type = "statusbar", label = "Texture", inherit = "barTexture" },
				},
			}
		end
		schema[#schema + 1] = { key = "segments", type = "group", label = "Segments", schema = segmentSchema }
	end
	self.schemaCache = schema
	return schema
end

function Bar:OnCreate(parent, spec)
	self.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")

	self.bar = CreateFrame("StatusBar", nil, self.frame)
	self.bar:SetMinMaxValues(0, 1)
	self.bar:SetValue(1)

	self.bg = self.bar:CreateTexture(nil, "BACKGROUND")
	self.bg:SetAllPoints(self.bar)

	self.clip = CreateFrame("Frame", nil, self.bar)
	self.clip:SetAllPoints(self.bar)
	self.clip:SetClipsChildren(true)

	self.segments = {}
	self.segmentsByKey = {}
	for _, seg in ipairs(spec.segments or {}) do
		local entry = {
			key = seg.key,
			mode = seg.mode or "append",
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
		local sb = seg.bar
		sb:ClearAllPoints()
		sb:SetStatusBarTexture(Media:Fetch("statusbar", segCfg.texture))
		sb:SetStatusBarColor(Util.UnpackColor(segCfg.color))
		sb:SetOrientation(cfg.orientation)
		if segCfg.enabled then
			local target = seg.mode == "append" and previous or fill
			for _, pair in ipairs(layout[seg.mode]) do
				sb:SetPoint(pair[1], target, pair[2])
			end
			if seg.mode == "append" then
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
	self.spark:SetPoint("CENTER", fill, layout.spark)
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
	if horizontal then
		self.spark:SetSize(12, height * 2)
	else
		self.spark:SetSize(width * 2, 12)
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
