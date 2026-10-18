local _, ns = ...
local Util = ns.Util

-- Blizzard's raid frame shield overflow strip, drawn additively and set up as
-- CompactUnitFrame does: the atlas (not its file), a 16 unit strip that starts
-- 7 units inside the bar's end and so reaches 9 units beyond it. Desaturated
-- so the configured colour tints it.
local EDGE_ATLAS = "RaidFrame-Shield-Overshield"
local STRIP_SIZE, STRIP_INSIDE = 16, 7
local SWITCH_TEXTURE = [[Interface\Buttons\WHITE8X8]]

--[[
A stepped warning at the end of a health bar while incoming healing goes past
full health: each level is a painted fade inside the bar plus Blizzard's edge
light, and stronger overheals light more levels, which reach further and stack.

Native calculators feed it, so Lua never reads a health or heal value:
  one per level  clamps incoming heals to the missing health plus the level's
                 share of maximum health; its "clamped" flag says the heal goes
                 past that boundary. The flag is secret in combat: it only
                 reaches SetAlphaFromBoolean on the level's gate frame.
  raw            clamps to maximum health, so its amount is above zero whenever
                 any heal is incoming, also at full health. The flags alone are
                 true at full health with nothing incoming, so the amount gates
                 the artwork: invisible 0..1 status bars are filled by any
                 amount, and the fade and light are anchored to their fills, so
                 they have no size while nothing is incoming.
Bar owns the instance (Bar spec.overheal) and calls Apply; the health driver
calls Update from the oUF health update, previews call Update or ShowSample.

Overheal:New(bar)
]]
local Overheal = ns.Object:Extend("Overheal")
ns.Overheal = Overheal

-- threshold: share of maximum health the heal has to reach past full health.
-- reach: share of the configured length. paint/light: share of the colour's
-- opacity for the fade and the edge light. Levels stack, so each adds to the last.
Overheal.LEVELS = {
	{ threshold = 1, reach = 0.35, paint = 0.35, light = 0.25 },
	{ threshold = 1.25, reach = 0.65, paint = 0.3, light = 0.35 },
	{ threshold = 1.5, reach = 1, paint = 0.3, light = 0.5 },
}

Overheal.LEVEL_CHOICES = {
	{ 1, "One: past full health" },
	{ 2, "Two: also 25% past" },
	{ 3, "Three: also 25% and 50% past" },
}

local function Off(cfg) return not cfg.enabled end

Overheal.schema = {
	{ key = "enabled", type = "toggle", label = "Show overheal", default = false,
		tooltip = "Lights the end of the health bar while incoming healing goes past full health. Bigger overheals reach further and glow brighter." },
	{ key = "levels", type = "select", label = "Levels", values = Overheal.LEVEL_CHOICES, default = 3, hidden = Off,
		tooltip = "Each level shows once the incoming heal reaches that far past maximum health, as a share of maximum health. Each level costs one more heal prediction per health update." },
	{ key = "color", type = "color", label = "Colour", hasAlpha = true, default = { 1, 0.7, 0.35, 1 }, hidden = Off },
	{ key = "length", type = "range", label = "Length", min = 8, max = 120, step = 1, default = 40, hidden = Off,
		tooltip = "How far the strongest level reaches into the bar." },
	{ key = "edge", type = "toggle", label = "Edge glow", default = true, hidden = Off,
		tooltip = "Blizzard's shield overflow glow on the bar's end, brighter with every level." },
}

-- Which way the end of the bar faces, by orientation and fill direction.
local OUTWARD = {
	HORIZONTAL = { [false] = { 1, 0 }, [true] = { -1, 0 } },
	VERTICAL = { [false] = { 0, 1 }, [true] = { 0, -1 } },
}

-- Puts the atlas's end edge on the bar's end. The artwork is drawn for a bar
-- ending on the right; other ends mirror or rotate its own sub-rectangle, so
-- the coordinates come from the atlas, never from the whole file.
local function ApplyArtwork(strip, orientation, reverseFill)
	strip:SetAtlas(EDGE_ATLAS, false)
	if orientation == "HORIZONTAL" and not reverseFill then return end
	local info = C_Texture.GetAtlasInfo(EDGE_ATLAS)
	local l, r, t, b = 0, 1, 0, 1
	if info then l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord end
	if orientation == "HORIZONTAL" then
		strip:SetTexCoord(r, l, t, b)
	elseif reverseFill then
		strip:SetTexCoord(l, t, r, t, l, b, r, b)
	else
		strip:SetTexCoord(r, t, l, t, r, b, l, b)
	end
end

-- Transparent away from the bar's end, the colour at it. Horizontal gradients
-- run from left to right, vertical ones from bottom to top.
local function Paint(texture, orientation, reverseFill, r, g, b, a)
	local clear, solid = CreateColor(r, g, b, 0), CreateColor(r, g, b, a)
	if reverseFill then
		texture:SetGradient(orientation, solid, clear)
	else
		texture:SetGradient(orientation, clear, solid)
	end
end

-- An invisible 0..1 status bar: any incoming heal fills it.
local function Switch(parent)
	local switch = CreateFrame("StatusBar", nil, parent)
	switch:SetStatusBarTexture(SWITCH_TEXTURE)
	switch:SetStatusBarColor(0, 0, 0, 0)
	switch:SetMinMaxValues(0, 1)
	switch:SetValue(0)
	return switch
end

local function Fill(texture, switch)
	local fill = switch:GetStatusBarTexture()
	texture:SetPoint("TOPLEFT", fill, "TOPLEFT")
	texture:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
end

-- Pins a switch to the whole bar's end, `beyond` units past it.
local function Pin(switch, bar, layout, orientation, outward, length, beyond)
	switch:ClearAllPoints()
	for _, pair in ipairs(layout.inset) do
		switch:SetPoint(pair[1], bar, pair[2], outward[1] * beyond, outward[2] * beyond)
	end
	if orientation == "HORIZONTAL" then
		switch:SetWidth(length)
	else
		switch:SetHeight(length)
	end
	switch:SetOrientation(orientation)
end

function Overheal:Init(bar)
	self.bar = bar
	self.enabled = false
	self.count = 0
	self.levels = {}
	self.calculators = {}
	-- Not the clipping frame: the edge light reaches past the bar's end.
	self.holder = CreateFrame("Frame", nil, bar.overlay)
	self.holder:SetAllPoints(bar.bar)
	self.holder:Hide()
end

-- Level widgets are created when first shown: most bars never enable this.
function Overheal:EnsureLevel(index)
	local level = self.levels[index]
	if level then return level end
	level = { gate = CreateFrame("Frame", nil, self.holder) }
	level.gate:SetAllPoints(self.holder)
	level.gate:SetAlpha(0)
	level.fade = Switch(level.gate)
	level.paint = level.gate:CreateTexture(nil, "ARTWORK")
	level.paint:SetColorTexture(1, 1, 1, 1)
	Fill(level.paint, level.fade)
	level.light = Switch(level.gate)
	level.strip = level.gate:CreateTexture(nil, "OVERLAY")
	level.strip:SetBlendMode("ADD")
	level.strip:SetDesaturated(true)
	Fill(level.strip, level.light)
	self.levels[index] = level
	return level
end

-- layout: the bar's Bar.LAYOUT entry; its inset pair pins the artwork to the
-- whole bar's end, like an overlay segment.
function Overheal:Apply(cfg, orientation, reverseFill, layout)
	self.enabled = cfg.enabled
	self.count = cfg.enabled and cfg.levels or 0
	self.holder:SetShown(cfg.enabled)
	local outward = OUTWARD[orientation][reverseFill]
	local r, g, b, a = Util.UnpackColor(cfg.color)
	for index, def in ipairs(Overheal.LEVELS) do
		local shown = index <= self.count
		local level = shown and self:EnsureLevel(index) or self.levels[index]
		if level then
			self:ClearLevel(level)
			level.gate:SetShown(shown)
			if shown then
				local reach = math.max(1, math.floor(cfg.length * def.reach + 0.5))
				Pin(level.fade, self.bar.bar, layout, orientation, outward, reach, 0)
				Paint(level.paint, orientation, reverseFill, r, g, b, a * def.paint)
				Pin(level.light, self.bar.bar, layout, orientation, outward, STRIP_SIZE, STRIP_SIZE - STRIP_INSIDE)
				ApplyArtwork(level.strip, orientation, reverseFill)
				level.strip:SetVertexColor(r, g, b, a * def.light)
				level.strip:SetShown(cfg.edge)
			end
		end
	end
end

function Overheal:ClearLevel(level)
	level.gate:SetAlpha(0)
	level.fade:SetValue(0)
	level.light:SetValue(0)
end

-- Index 0 is the raw amount; every level has its own boundary.
function Overheal:GetCalculator(index)
	local calculator = self.calculators[index]
	if not calculator then
		calculator = CreateUnitHealPredictionCalculator()
		if index == 0 then
			calculator:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MaximumHealth)
		else
			calculator:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
			calculator:SetIncomingHealOverflowPercent(Overheal.LEVELS[index].threshold)
		end
		self.calculators[index] = calculator
	end
	return calculator
end

-- Live: `unit` may have secret health and heals. Every result goes straight
-- into a widget.
function Overheal:Update(unit)
	if not self.enabled then return end
	local raw = self:GetCalculator(0)
	UnitGetDetailedHealPrediction(unit, "player", raw)
	local amount = raw:GetIncomingHeals()
	for index = 1, self.count do
		local level, calculator = self.levels[index], self:GetCalculator(index)
		UnitGetDetailedHealPrediction(unit, "player", calculator)
		local _, _, _, clamped = calculator:GetIncomingHeals()
		level.gate:SetAlphaFromBoolean(clamped, 1, 0)
		level.fade:SetValue(amount)
		level.light:SetValue(amount)
	end
end

-- Samples: plain values (health, healthMax, heal), so plain arithmetic is fine.
function Overheal:ShowSample(values)
	if not self.enabled then return end
	for index = 1, self.count do
		local level = self.levels[index]
		local past = values.heal > 0 and values.health + values.heal > values.healthMax * Overheal.LEVELS[index].threshold
		level.gate:SetAlpha(past and 1 or 0)
		level.fade:SetValue(values.heal)
		level.light:SetValue(values.heal)
	end
end
