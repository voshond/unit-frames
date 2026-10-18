local _, ns = ...
local Util = ns.Util

-- Blizzard's raid frame shield overflow strip: bright at the bar's end,
-- drawn additively. Desaturated so the configured colour tints it.
local EDGE_TEXTURE = [[Interface\RaidFrame\Shield-Overshield]]
local SWITCH_TEXTURE = [[Interface\Buttons\WHITE8X8]]

--[[
An edge warning on a health bar while incoming healing goes past full health.

Two native calculators feed it, so Lua never reads a health or heal value:
  overflow  clamps incoming heals to the missing health plus the configured
            share of maximum health; its "clamped" flag says the heal goes
            past that boundary. The flag is secret in combat: it only reaches
            SetAlphaFromBoolean on the gate frame.
  raw       clamps to maximum health, so its amount is above zero whenever any
            heal is incoming, also at full health. The flag alone is true at
            full health with nothing incoming, so the amount gates the strip:
            an invisible 0..1 status bar is filled by any amount, and the strip
            is anchored to its fill, so it has no size while nothing is incoming.
Bar owns the instance (Bar spec.overheal) and calls Apply; the health driver
calls Update from the oUF health update, previews call Update or ShowSample.

Overheal:New(bar)
]]
local Overheal = ns.Object:Extend("Overheal")
ns.Overheal = Overheal

-- Shares of maximum health the heal has to reach past full health.
Overheal.THRESHOLDS = {
	{ 1, "Past full health" }, { 1.05, "5% past full health" }, { 1.1, "10% past full health" },
	{ 1.25, "25% past full health" }, { 1.5, "50% past full health" },
}

Overheal.schema = {
	{ key = "enabled", type = "toggle", label = "Show overheal", default = false,
		tooltip = "Lights the end of the health bar while incoming healing goes past full health." },
	{ key = "threshold", type = "select", label = "Show when", values = Overheal.THRESHOLDS, default = 1,
		hidden = function(cfg) return not cfg.enabled end,
		tooltip = "How far incoming healing must reach beyond maximum health, as a share of maximum health." },
	{ key = "color", type = "color", label = "Colour", hasAlpha = true, default = { 1, 0.82, 0.45, 1 },
		hidden = function(cfg) return not cfg.enabled end },
	{ key = "size", type = "range", label = "Size", min = 4, max = 40, step = 1, default = 16,
		hidden = function(cfg) return not cfg.enabled end,
		tooltip = "Length of the glow along the bar." },
}

-- Texture coordinates that put the artwork's bright edge on the bar's end,
-- by orientation and fill direction. Vertical strips rotate the artwork.
local COORDS = {
	HORIZONTAL = { [false] = { 0, 1, 0, 1 }, [true] = { 1, 0, 0, 1 } },
	VERTICAL = { [false] = { 1, 0, 0, 0, 1, 1, 0, 1 }, [true] = { 0, 0, 1, 0, 0, 1, 1, 1 } },
}

function Overheal:Init(bar)
	self.bar = bar
	self.enabled = false
	self.gate = CreateFrame("Frame", nil, bar.clip)
	self.gate:SetAllPoints(bar.bar)
	self.gate:SetAlpha(0)
	self.gate:Hide()
	self.switch = CreateFrame("StatusBar", nil, self.gate)
	self.switch:SetStatusBarTexture(SWITCH_TEXTURE)
	self.switch:SetStatusBarColor(0, 0, 0, 0)
	self.switch:SetMinMaxValues(0, 1)
	self.switch:SetValue(0)
	self.strip = self.gate:CreateTexture(nil, "OVERLAY")
	self.strip:SetTexture(EDGE_TEXTURE)
	self.strip:SetBlendMode("ADD")
	self.strip:SetDesaturated(true)
	local fill = self.switch:GetStatusBarTexture()
	self.strip:SetPoint("TOPLEFT", fill, "TOPLEFT")
	self.strip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
end

-- layout: the bar's Bar.LAYOUT entry; its inset pair pins the strip to the
-- whole bar's end, like an overlay segment.
function Overheal:Apply(cfg, orientation, reverseFill, layout)
	self.enabled = cfg.enabled
	self.gate:SetShown(cfg.enabled)
	if not cfg.enabled then
		self:Clear()
		return
	end
	local switch = self.switch
	switch:ClearAllPoints()
	for _, pair in ipairs(layout.inset) do
		switch:SetPoint(pair[1], self.bar.bar, pair[2])
	end
	if orientation == "HORIZONTAL" then
		switch:SetWidth(cfg.size)
	else
		switch:SetHeight(cfg.size)
	end
	switch:SetOrientation(orientation)
	self.strip:SetTexCoord(unpack(COORDS[orientation][reverseFill]))
	self.strip:SetVertexColor(Util.UnpackColor(cfg.color))
	if self.overflow then self.overflow:SetIncomingHealOverflowPercent(cfg.threshold) end
	self.threshold = cfg.threshold
end

function Overheal:Clear()
	self.gate:SetAlpha(0)
	self.switch:SetValue(0)
end

-- Calculators are created on first use: most bars never enable this.
function Overheal:GetCalculators()
	if not self.overflow then
		self.overflow = CreateUnitHealPredictionCalculator()
		self.overflow:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
		self.overflow:SetIncomingHealOverflowPercent(self.threshold)
		self.raw = CreateUnitHealPredictionCalculator()
		self.raw:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MaximumHealth)
	end
	return self.overflow, self.raw
end

-- Live: `unit` may have secret health and heals. Every result goes straight
-- into a widget.
function Overheal:Update(unit)
	if not self.enabled then return end
	local overflow, raw = self:GetCalculators()
	UnitGetDetailedHealPrediction(unit, "player", overflow)
	UnitGetDetailedHealPrediction(unit, "player", raw)
	local _, _, _, clamped = overflow:GetIncomingHeals()
	self.gate:SetAlphaFromBoolean(clamped, 1, 0)
	self.switch:SetValue((raw:GetIncomingHeals()))
end

-- Samples: plain values (health, healthMax, heal), so plain arithmetic is fine.
function Overheal:ShowSample(values)
	if not self.enabled then return end
	local past = values.health + values.heal > values.healthMax * self.threshold
	self.gate:SetAlpha(past and values.heal > 0 and 1 or 0)
	self.switch:SetValue(values.heal)
end
