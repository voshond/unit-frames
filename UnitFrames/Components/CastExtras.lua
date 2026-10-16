local _, ns = ...
local Media, Util = ns.Media, ns.Util
local Bar = ns.Components.Bar

--[[
Player castbar extras, owned by a Castbar created with spec.playerCast.

Latency zone: a StatusBar over the cast fill, filled from the end of the
cast (the draining start of a channel). Range is the cast length and value
the zone, both in plain seconds; the engine clamps the rest, so neither
geometry nor secret cast values enter Lua arithmetic. Without a plain cast
length the zone stays hidden.

GCD strip: a StatusBar the engine drives from the GCD's duration object, with
a spark at its fill end. It sits next to the castbar, not inside it, so it
runs for instant casts while the castbar is hidden without touching what
the castbar covers.
]]
local Extras = {}
ns.CastExtras = Extras

Extras.LATENCY_MODES = {
	{ "latency", "Latency" },
	{ "queue", "Spell queue window" },
}

Extras.GCD_POSITIONS = {
	{ "full", "Whole bar" },
	{ "top", "Top edge" },
	{ "bottom", "Bottom edge" },
}

local NATIVE_LAYOUT_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"

function Extras.BuildSchema()
	return {
		{ key = "latency", type = "group", label = "Latency zone", schema = {
			{ key = "enabled", type = "toggle", label = "Enabled", default = true },
			{ key = "mode", type = "select", label = "Zone", values = Extras.LATENCY_MODES, default = "queue",
				tooltip = "Latency: the time between sending a cast and the server starting it, or your world latency. Spell queue window: the time at the end of a cast in which the next spell can already be queued." },
			{ key = "color", type = "color", label = "Colour", default = { 0.9, 0.1, 0.1, 0.6 } },
		} },
		{ key = "gcd", type = "group", label = "Global cooldown", schema = {
			{ key = "enabled", type = "toggle", label = "Enabled", default = false,
				tooltip = "Shows the global cooldown on the castbar's place, also after instant casts while no cast is shown." },
			{ key = "position", type = "select", label = "Position", values = Extras.GCD_POSITIONS, default = "bottom",
				tooltip = "Edges are left and right on a vertical castbar." },
			{ key = "height", type = "range", label = "Thickness", min = 1, max = 10, step = 1, default = 2,
				hidden = function(cfg) return cfg.position == "full" end },
			{ key = "color", type = "color", label = "Colour", default = { 1, 1, 1, 0.4 } },
			{ key = "spark", type = "toggle", label = "Spark", default = true },
		} },
	}
end

-- Seconds of a plain cast, nil when the times are secret.
function Extras.CastTime(startMs, endMs)
	if Util.IsSecret(startMs) or Util.IsSecret(endMs) or type(startMs) ~= "number" or type(endMs) ~= "number" then
		return nil
	end
	return (endMs - startMs) / 1000
end

-- Latency zone ----------------------------------------------------------------

local Latency = ns.Object:Extend("CastLatency")
Extras.Latency = Latency

function Latency:Init(bar)
	local statusBar = bar:GetStatusBar()
	self.bar = CreateFrame("StatusBar", nil, statusBar)
	self.bar:SetAllPoints(statusBar)
	self.bar:SetFrameLevel(statusBar:GetFrameLevel() + 1)
	self.bar:Hide()
end

function Latency:Apply(cfg, barCfg)
	self.cfg, self.barCfg = cfg, barCfg
	self.bar:SetStatusBarTexture(Media:Fetch("statusbar", barCfg.texture))
	self.bar:SetStatusBarColor(Util.UnpackColor(cfg.color))
	self.bar:SetOrientation(barCfg.orientation)
	if not cfg.enabled then
		self:Hide()
	end
end

function Latency:Seconds(measured)
	if self.cfg.mode == "queue" then
		return C_Spell.GetSpellQueueWindow() / 1000
	end
	if measured then
		return measured
	end
	local _, _, _, world = GetNetStats()
	return world / 1000
end

-- info: castTime (plain seconds or nil), latency (measured seconds or nil), channel.
function Latency:Show(info)
	local castTime = info.castTime
	if not self.cfg.enabled or not castTime or castTime <= 0 then
		self:Hide()
		return
	end
	-- A cast ends at the fill's far end; a channel drains back to its start.
	local reverse = self.barCfg.reverseFill
	if not info.channel then
		reverse = not reverse
	end
	self.bar:SetReverseFill(reverse)
	self.bar:SetMinMaxValues(0, castTime)
	self.bar:SetValue(self:Seconds(info.latency))
	self.bar:Show()
end

function Latency:Hide()
	self.bar:Hide()
end

-- GCD strip -------------------------------------------------------------------

local GCD = ns.Object:Extend("CastGCD")
Extras.GCD = GCD

function GCD:Init(parent, anchor, nativeLayout)
	self.anchor = anchor
	self.bar = CreateFrame("StatusBar", nil, parent, nativeLayout and NATIVE_LAYOUT_TEMPLATE or nil)
	self.bar:SetMinMaxValues(0, 1)
	self.bar:SetValue(0)
	self.spark = self.bar:CreateTexture(nil, "OVERLAY")
	self.spark:SetTexture(Bar.SPARK_TEXTURE)
	self.spark:SetBlendMode("ADD")
	self.bar:Hide()
end

local EDGE_POINTS = {
	HORIZONTAL = { top = { "TOPLEFT", "TOPRIGHT" }, bottom = { "BOTTOMLEFT", "BOTTOMRIGHT" } },
	VERTICAL = { top = { "TOPLEFT", "BOTTOMLEFT" }, bottom = { "TOPRIGHT", "BOTTOMRIGHT" } },
}

function GCD:Apply(cfg, barCfg)
	self.cfg = cfg
	local bar, anchor, orientation = self.bar, self.anchor, barCfg.orientation
	bar:SetStatusBarTexture(Media:Fetch("statusbar", barCfg.texture))
	bar:SetStatusBarColor(Util.UnpackColor(cfg.color))
	bar:SetOrientation(orientation)
	bar:SetReverseFill(barCfg.reverseFill)
	bar:ClearAllPoints()
	if cfg.position == "full" then
		bar:SetAllPoints(anchor)
	else
		for _, point in ipairs(EDGE_POINTS[orientation][cfg.position]) do
			bar:SetPoint(point, anchor, point)
		end
		if orientation == "HORIZONTAL" then
			bar:SetHeight(cfg.height)
		else
			bar:SetWidth(cfg.height)
		end
	end
	Bar.AnchorSpark(self.spark, bar:GetStatusBarTexture(), orientation, barCfg.reverseFill)
	self.spark:SetShown(cfg.spark)
	if not cfg.enabled then
		self:Stop()
	end
end

function GCD:IsEnabled()
	return self.cfg ~= nil and self.cfg.enabled
end

-- Above the castbar's fill, below its texts; the castbar's level is set by
-- its host after creation.
function GCD:Present()
	self.bar:SetFrameLevel(self.anchor:GetFrameLevel() + 2)
	self.bar:Show()
end

function GCD:Start(duration)
	self.bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
	self:Present()
end

function GCD:Preview(progress)
	self.bar:SetMinMaxValues(0, 1)
	self.bar:SetValue(progress)
	self:Present()
end

function GCD:Stop()
	self.bar:Hide()
end

function GCD:Release()
	self:Stop()
	self.bar:ClearAllPoints()
end
