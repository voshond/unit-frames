local _, ns = ...
local Util, Media = ns.Util, ns.Media

local SWITCH_TEXTURE = [[Interface\Buttons\WHITE8X8]]
local STRIPES = "Interface\\AddOns\\" .. ns.name .. "\\Media\\Stripes" -- scripts/generate-stripes.lua
local SKULL = [[Interface\TargetingFrame\UI-TargetingFrame-Skull]]
local ICON_KEYS = ns.IconPlacement.PrefixedKeys("lethalIcon")
-- How far a lethal probe reaches: its artwork slides in over (artwork size / this) of health.
local PROBE_LENGTH = 50000

--[[
The damage the player's DoTs will still deal (ns.DotTracker), drawn on a
health bar: one segment per DoT, pinned at the end of the health fill and
chained back into it, like an inset segment. Where the last one ends is where
health will be once the DoTs are done; reaching the bar's start means death.

Lua never compares the estimate with health, which is secret. Segments share
the bar's (secret) scale through SetRange. The kill icon and tint ride the
end of an invisible probe, a very long StatusBar ranged 0..current health and
filled with the estimate, inside a clipping gate the size of the artwork: the
artwork only reaches into the gate when the probe is full.

Bar owns the instance (Bar spec.pendingDamage) and forwards SetRange, its size
and Apply. The UF_PendingDamage element and previews call SetDots; the health
update and previews call SetHealth.

PendingDamage:New(bar)
]]
local PendingDamage = ns.Object:Extend("PendingDamage")
ns.PendingDamage = PendingDamage

PendingDamage.MAX_SEGMENTS = 6

PendingDamage.COLOR_MODES = {
	{ "school", "By spell school" },
	{ "spell", "Different colour per DoT" },
	{ "single", "One colour" },
}

-- A pattern repeats over each DoT's fill, so the marker reads apart from the
-- bar's own fills (heals, shields) whatever their colours.
PendingDamage.PATTERNS = {
	{ "stripes", "Diagonal stripes" },
	{ "none", "None" },
}

PendingDamage.SCHOOL_COLORS = {
	[1] = { 1, 0.3, 0.3 },
	[2] = { 1, 0.9, 0.45 },
	[4] = { 1, 0.55, 0.15 },
	[8] = { 0.35, 1, 0.35 },
	[16] = { 0.45, 0.8, 1 },
	[20] = { 0.75, 0.6, 1 },
	[32] = { 0.7, 0.35, 1 },
	[64] = { 1, 0.55, 1 },
}

-- Each spell keeps the colour it got first this session, so recasts don't reshuffle.
local PALETTE = {
	{ 0.95, 0.3, 0.3 }, { 0.3, 0.75, 1 }, { 1, 0.8, 0.2 }, { 0.45, 1, 0.45 },
	{ 0.85, 0.4, 1 }, { 1, 0.55, 0.15 }, { 0.3, 1, 0.9 }, { 1, 0.45, 0.75 },
}
local WHITE = { 1, 1, 1 }
local paletteByName, nextPalette = {}, 1

local function Off(cfg) return not cfg.enabled end
local function Single(cfg) return Off(cfg) or cfg.colorMode == "single" end
local function NotSingle(cfg) return Off(cfg) or cfg.colorMode ~= "single" end
local function NoPattern(cfg) return Off(cfg) or cfg.pattern == "none" end
local function NoIcon(cfg) return Off(cfg) or not cfg.lethalIcon end
local function NoTint(cfg) return Off(cfg) or not cfg.lethalTint end

PendingDamage.schema = {
	{ key = "enabled", type = "toggle", label = "Show DoT damage", default = false,
		tooltip = "Marks the damage your damage over time spells will still deal, from the end of the health fill back into it. If the marker reaches the start of the bar, they will kill it. Estimated from your casts and their ticks while the unit is your target or focus." },
	{ key = "colorMode", type = "select", label = "DoT colours", values = PendingDamage.COLOR_MODES, default = "school", hidden = Off },
	{ key = "color", type = "color", label = "DoT colour", hasAlpha = true, default = { 0.7, 0.3, 1, 0.75 }, hidden = NotSingle },
	{ key = "opacity", type = "range", label = "DoT opacity", min = 0.1, max = 1, step = 0.05, default = 0.75, hidden = Single },
	{ key = "texture", type = "statusbar", label = "DoT texture", inherit = "barTexture", hidden = Off },
	{ key = "pattern", type = "select", label = "DoT pattern", values = PendingDamage.PATTERNS, default = "stripes",
		hidden = Off },
	{ key = "patternColor", type = "color", label = "Pattern colour", default = { 0, 0, 0 },
		hidden = NoPattern },
	{ key = "patternOpacity", type = "range", label = "Stripe opacity", min = 0, max = 1, step = 0.05, default = 0.35,
		hidden = NoPattern },
	{ key = "dividers", type = "toggle", label = "Dividers between DoTs", default = true, hidden = Single },
	{ key = "edge", type = "toggle", label = "Line where health will end", default = true, hidden = Off },
	{ key = "waitMode", type = "select", label = "Wait for a DoT's first tick", values = ns.DotTracker.WAIT_MODES,
		default = "off", hidden = Off,
		tooltip = "When unsure: a DoT whose tick size hasn't been seen yet (or a finisher with unknown combo points) only counts once it has ticked. Always: only DoTs that have ticked count." },
	{ key = "lethalTint", type = "toggle", label = "Tint the bar when lethal", default = false, hidden = Off },
	{ key = "lethalTintColor", type = "color", label = "Lethal tint", hasAlpha = true, default = { 1, 0.1, 0.1, 0.35 },
		hidden = NoTint },
}

for _, option in ipairs(ns.IconPlacement.BuildSchema({
	keys = ICON_KEYS,
	defaults = { anchor = "CENTER", size = 16, order = 8 },
	fields = {
		enabled = { label = "Kill icon", hidden = Off,
			tooltip = "A skull in the decoration stack while your DoTs will finish the unit. Its slot stays reserved while DoTs are active because lethal visibility is secret." },
	},
})) do
	if option.key ~= "lethalIcon" then option.hidden = NoIcon end
	PendingDamage.schema[#PendingDamage.schema + 1] = option
end

local function PaletteColor(name)
	local index = paletteByName[name]
	if not index then
		index = (nextPalette - 1) % #PALETTE + 1
		paletteByName[name], nextPalette = index, nextPalette + 1
	end
	return PALETTE[index]
end

local function EntryColor(cfg, entry)
	if cfg.colorMode == "single" then return Util.UnpackColor(cfg.color) end
	local rgb = cfg.colorMode == "school" and (PendingDamage.SCHOOL_COLORS[entry.school] or WHITE) or PaletteColor(entry.name)
	return rgb[1], rgb[2], rgb[3], cfg.opacity
end

local function Switch(parent)
	local switch = CreateFrame("StatusBar", nil, parent)
	switch:SetStatusBarTexture(SWITCH_TEXTURE)
	switch:SetStatusBarColor(0, 0, 0, 0)
	switch:SetMinMaxValues(0, 1)
	switch:SetValue(0)
	return switch
end

-- A clipping gate with a probe ending at its right edge and artwork riding the probe's fill.
local function Lethal(parent, artwork)
	local gate = CreateFrame("Frame", nil, parent)
	gate:SetClipsChildren(true)
	gate:Hide()
	local probe = Switch(gate)
	probe:SetPoint("TOPRIGHT", gate, "TOPRIGHT")
	probe:SetPoint("BOTTOMRIGHT", gate, "BOTTOMRIGHT")
	probe:SetWidth(PROBE_LENGTH)
	local texture = probe:CreateTexture(nil, "OVERLAY")
	texture:SetPoint("TOPRIGHT", probe:GetStatusBarTexture(), "TOPRIGHT")
	texture:SetPoint("BOTTOMRIGHT", probe:GetStatusBarTexture(), "BOTTOMRIGHT")
	if artwork then artwork(texture) end
	return { gate = gate, probe = probe, texture = texture }
end

local function SetValue(statusBar, value, interpolation)
	if interpolation then statusBar:SetValue(value, interpolation) else statusBar:SetValue(value) end
end

function PendingDamage:Init(bar)
	self.bar = bar
	self.enabled, self.count, self.total = false, 0, 0
	self.entries = {}
	self.holder = CreateFrame("Frame", nil, bar.clip)
	self.holder:SetAllPoints(bar.bar)
	self.holder:Hide()
end

-- Built when first enabled: most bars never show DoTs.
function PendingDamage:Build()
	if self.segments then return end
	self.segments = {}
	for index = 1, PendingDamage.MAX_SEGMENTS do
		local segment = { bar = Switch(self.holder) }
		segment.pattern = segment.bar:CreateTexture(nil, "OVERLAY")
		segment.pattern:SetTexture(STRIPES, "REPEAT", "REPEAT")
		segment.pattern:SetHorizTile(true)
		segment.pattern:SetVertTile(true)
		self.segments[index] = segment
	end
	self.ink = CreateFrame("Frame", nil, self.holder)
	self.ink:SetAllPoints(self.holder)
	self.ink:SetFrameLevel(self.holder:GetFrameLevel() + 2)
	for _, segment in ipairs(self.segments) do
		segment.divider = self.ink:CreateTexture(nil, "OVERLAY")
		segment.divider:SetColorTexture(0, 0, 0, 0.85)
		segment.divider:Hide()
	end
	self.edge = self.ink:CreateTexture(nil, "OVERLAY", nil, 1)
	self.edge:SetColorTexture(1, 1, 1, 0.9)
	self.edge:Hide()
	local overlay = self.bar.overlay
	self.tint = Lethal(overlay, function(texture) texture:SetColorTexture(1, 1, 1, 1) end)
	self.tint.gate:SetAllPoints(self.bar.bar)
	self.iconHost = CreateFrame("Frame", nil, overlay)
	self.icon = Lethal(self.iconHost, function(texture) texture:SetTexture(SKULL) end)
	self.icon.gate:SetAllPoints(self.iconHost)
end

-- Points `region` at the far edge of a segment's fill (where it ends inside the health fill).
local function AtFarEdge(region, fill, chain, thickness, horizontal)
	region:ClearAllPoints()
	region:SetPoint(chain[1][2], fill, chain[1][2])
	region:SetPoint(chain[2][2], fill, chain[2][2])
	if horizontal then region:SetWidth(thickness) else region:SetHeight(thickness) end
end

-- layout: the bar's Bar.LAYOUT entry. The first segment is pinned like an
-- inset one; the others continue from the previous segment's far end.
function PendingDamage:Apply(cfg, orientation, reverseFill, layout)
	self.cfg, self.enabled = cfg, cfg.enabled
	self.holder:SetShown(cfg.enabled)
	if not cfg.enabled then
		if self.segments then
			self.tint.gate:Hide()
			self.icon.gate:Hide()
		end
		return
	end
	self:Build()
	self.horizontal = orientation == "HORIZONTAL"
	self.chain = ns.Components.Bar.LAYOUT[orientation][not reverseFill].append
	local texture = Media:Fetch("statusbar", cfg.texture)
	local previous = self.bar.bar:GetStatusBarTexture()
	for index, segment in ipairs(self.segments) do
		local statusBar = segment.bar
		statusBar:ClearAllPoints()
		for _, pair in ipairs(index == 1 and layout.inset or self.chain) do
			statusBar:SetPoint(pair[1], previous, pair[2])
		end
		statusBar:SetStatusBarTexture(texture)
		statusBar:SetOrientation(orientation)
		statusBar:SetReverseFill(not reverseFill)
		previous = statusBar:GetStatusBarTexture()
		AtFarEdge(segment.divider, previous, self.chain, 1, self.horizontal)
		-- Over the fill, not as it: a plain texture repeats; a stretched fill would smear the hatch.
		segment.pattern:ClearAllPoints()
		segment.pattern:SetPoint("TOPLEFT", previous, "TOPLEFT")
		segment.pattern:SetPoint("BOTTOMRIGHT", previous, "BOTTOMRIGHT")
		segment.pattern:SetVertexColor(cfg.patternColor[1], cfg.patternColor[2], cfg.patternColor[3], cfg.patternOpacity)
		segment.pattern:SetShown(cfg.pattern ~= "none")
	end

	self:Layout(self.layoutContext)
	self.tint.texture:SetVertexColor(Util.UnpackColor(cfg.lethalTintColor))
	if self.width then self:SetLength(self.width, self.height) end
	if self.max then self:SetRange(0, self.max) end
	if self.health then self:SetHealth(self.health) end
	self:Draw()
end

-- The bar's plain inner size: segments span the whole bar to share its scale.
function PendingDamage:SetLength(width, height)
	self.width, self.height = width, height
	if not self.segments then return end
	for _, segment in ipairs(self.segments) do
		if self.horizontal then segment.bar:SetWidth(width) else segment.bar:SetHeight(height) end
	end
	self.tint.texture:SetWidth(width)
end

-- Accepts secret values (the health scale).
function PendingDamage:SetRange(min, max)
	self.max = max
	if not self.segments then return end
	for _, segment in ipairs(self.segments) do segment.bar:SetMinMaxValues(min, max) end
end

-- Current health, possibly secret: the lethal probes' scale.
function PendingDamage:SetHealth(current)
	self.health = current
	if not self.segments then return end
	self.tint.probe:SetMinMaxValues(0, current)
	self.icon.probe:SetMinMaxValues(0, current)
	self:UpdateLethal()
end

-- entries: { name, school, damage } oldest first (DotTracker:Breakdown); plain values.
function PendingDamage:SetDots(entries, count, total)
	self.entries, self.count, self.total = entries or self.entries, count or 0, total or 0
	if self.segments then self:Draw() end
end

function PendingDamage:Draw()
	local cfg, entries, count = self.cfg, self.entries, self.count
	if not cfg or not cfg.enabled then return end
	local single = cfg.colorMode == "single"
	local max = PendingDamage.MAX_SEGMENTS
	local used = single and math.min(count, 1) or math.min(count, max)
	local interpolation = self.bar.interpolation
	for index, segment in ipairs(self.segments) do
		local value = 0
		if index <= used then
			if single then
				value = self.total
			else
				value = entries[index].damage
				-- More DoTs than segments: the last one also covers the rest.
				if index == max then
					for rest = max + 1, count do value = value + entries[rest].damage end
				end
			end
			segment.bar:SetStatusBarColor(EntryColor(cfg, entries[index]))
		end
		SetValue(segment.bar, value, interpolation)
		segment.divider:SetShown(cfg.dividers and not single and index < used)
	end
	if used > 0 and cfg.edge then
		AtFarEdge(self.edge, self.segments[used].bar:GetStatusBarTexture(), self.chain, 2, self.horizontal)
		self.edge:Show()
	else
		self.edge:Hide()
	end
	self.icon.probe:SetValue(self.total)
	self.tint.probe:SetValue(self.total)
	self:UpdateLethal()
end

-- Shown only with DoTs and a health scale: an unscaled probe would read as lethal.
function PendingDamage:UpdateLethal()
	local cfg = self.cfg
	if not cfg or not self.segments then return end
	local active = cfg.enabled and self.count > 0 and self.health ~= nil
	self.icon.gate:SetShown(active and cfg.lethalIcon)
	self.tint.gate:SetShown(active and cfg.lethalTint)
	local stack = self.layoutContext and self.layoutContext.decorations
	if stack then stack:Reflow() end
end

function PendingDamage:Layout(context, enabled)
	self.layoutContext = context
	if enabled ~= nil then self.layoutEnabled = enabled end
	if not self.icon then return end
	local cfg = ns.IconPlacement.Read(self.cfg, ICON_KEYS)
	cfg.enabled = self.cfg.enabled and cfg.enabled and self.layoutEnabled ~= false
	local size = cfg.size
	if context and cfg.anchor:match("^PORTRAIT_") and context.portrait then
		size = math.min(size, context.portrait.width, context.portrait.height)
	end
	self.icon.texture:SetWidth(size)
	if context then
		if self.iconParent ~= context.root then
			self.iconHost:SetParent(context.root)
			self.iconParent = context.root
		end
		context.decorations:Set("pendingDamage", ns.IconPlacement.Member(cfg, self.iconHost, { self.icon.gate }))
		return
	end
	self.iconHost:SetSize(size, size)
	self.iconHost:SetPoint("CENTER", self.bar.bar, "CENTER")
end

function PendingDamage:Release()
	local stack = self.layoutContext and self.layoutContext.decorations
	if stack then
		stack:Remove("pendingDamage")
		stack:Reflow()
	end
	if self.iconHost then
		self.iconHost:Hide()
		self.icon.gate:Hide()
		self.tint.gate:Hide()
	end
	self.holder:Hide()
	self.layoutContext = nil
end

function PendingDamage:GetWaitMode()
	return self.cfg and self.cfg.waitMode or "off"
end

-- Samples: plain values.pendingDamage ({ name, school, damage }) and health.
function PendingDamage:ShowSample(values)
	local entries, total = values.pendingDamage or {}, 0
	for _, entry in ipairs(entries) do total = total + entry.damage end
	self:SetHealth(values.health)
	self:SetDots(entries, #entries, total)
end

-- Polled previews: whatever the tracker knows about `unit` while it runs.
function PendingDamage:ShowLive(unit)
	local tracker = ns.DotTracker
	local key = tracker:IsActive() and tracker:KeyFor(unit) or nil
	local total, count, entries = tracker:Breakdown(key, self:GetWaitMode(), self.liveEntries)
	self.liveEntries = entries
	self:SetDots(entries, count, total)
end
