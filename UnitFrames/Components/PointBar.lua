local _, ns = ...
local Media, Util = ns.Media, ns.Util
local Backdrop = ns.Components.Backdrop

--[[
A row of equal points side by side (combo points), filled up to a value.

Structure: one holder per point (its border/background, Backdrop) with a
StatusBar inset inside it. Point i's bar spans [i - 1, i], so the same value
set on every bar fills whole points natively: a secret count needs no Lua
comparison or arithmetic.

The number of points is plain (UnitPowerMax for the player, or sample data);
SetMax lays them out across the width the owner gives Layout(width).

spec.available = false: the owner keeps it switched off (a UnitFrame whose
player's class has no combo points).
]]
local PointBar = ns.Component:Extend("PointBar")

PointBar.MAX_POINTS = 10

PointBar.schema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "spacing", type = "range", label = "Gap between points", min = 0, max = 20, step = 1, default = 2 },
	{ key = "texture", type = "statusbar", label = "Texture", inherit = "barTexture" },
	{ key = "color", type = "color", label = "Colour", inherit = "colors.comboPoints" },
	{ key = "background", type = "group", label = "Empty points", schema = {
		{ key = "enabled", type = "toggle", label = "Enabled", default = true },
		{ key = "useBarColor", type = "toggle", label = "Tint with point colour", default = true },
		{ key = "alpha", type = "range", label = "Opacity", min = 0, max = 1, step = 0.05, default = 0.25,
			hidden = function(cfg) return not cfg.useBarColor end },
		{ key = "color", type = "color", label = "Colour", default = { 0, 0, 0, 0.5 },
			hidden = function(cfg) return cfg.useBarColor end },
	} },
	{ key = "border", type = "group", label = "Border", schema = Backdrop.schema,
		defaults = { enabled = false, border = "UnitFrames Pixel", size = 1, inset = 0, padding = 1 } },
}

function PointBar:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent)
	self.width, self.max = 1, 0
	self.points = {}
	for i = 1, PointBar.MAX_POINTS do
		local holder = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
		local bar = CreateFrame("StatusBar", nil, holder)
		bar:SetMinMaxValues(i - 1, i)
		bar:SetValue(0)
		local bg = bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(bar)
		holder:Hide()
		self.points[i] = { holder = holder, bar = bar, bg = bg }
	end
end

function PointBar:OnApply(cfg)
	local texture = Media:Fetch("statusbar", cfg.texture)
	local r, g, b, a = Util.UnpackColor(cfg.color)
	local bgCfg = cfg.background
	for _, point in ipairs(self.points) do
		Backdrop.ApplyTo(point.holder, cfg.border)
		Backdrop.Inset(point.bar, point.holder, cfg.border)
		point.bar:SetStatusBarTexture(texture)
		point.bar:SetStatusBarColor(r, g, b, a)
		point.bg:SetTexture(texture)
		if bgCfg.useBarColor then
			point.bg:SetVertexColor(r, g, b, bgCfg.alpha)
		else
			point.bg:SetVertexColor(Util.UnpackColor(bgCfg.color))
		end
		point.bg:SetShown(bgCfg.enabled)
	end
	self:LayoutPoints()
end

-- The row's width, in plain numbers (the owner's layout).
function PointBar:Layout(width)
	self.width = width
	self:LayoutPoints()
end

function PointBar:LayoutPoints()
	local count = self.max
	local spacing = self.resolved.spacing
	local width = count > 0 and (self.width - spacing * (count - 1)) / count or 0
	for i, point in ipairs(self.points) do
		local holder = point.holder
		holder:ClearAllPoints()
		if i <= count then
			local x = (i - 1) * (width + spacing)
			holder:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, 0)
			holder:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, 0)
			holder:SetWidth(math.max(width, 1))
			holder:Show()
		else
			holder:Hide()
		end
	end
end

-- How many points the row has (plain; 0 shows none).
function PointBar:SetMax(max)
	max = math.max(0, math.min(math.floor(max or 0), PointBar.MAX_POINTS))
	if max == self.max then return end
	self.max = max
	self:LayoutPoints()
end

function PointBar:GetMax()
	return self.max
end

-- The filled amount; may be secret. It only goes to the StatusBars.
function PointBar:SetValue(value)
	for _, point in ipairs(self.points) do
		point.bar:SetValue(value)
	end
end

-- Plain sample values.
function PointBar:Preview(value, max)
	self:SetMax(max)
	self:SetValue(value or 0)
end

function PointBar:OnRelease()
	self:SetMax(0)
	self:SetValue(0)
end
