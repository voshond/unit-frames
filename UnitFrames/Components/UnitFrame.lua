local _, ns = ...
local Backdrop, TextBar = ns.Components.Backdrop, ns.Components.TextBar
local Castbar, Portrait, Auras = ns.Components.Castbar, ns.Components.Portrait, ns.Components.Auras
local RaidTarget = ns.Components.RaidTarget

--[[
A unit frame made of rows stacked top to bottom inside one bordered frame.
Each row is a TextBar (bar + left/centre/right text) with its own height and
on/off toggle; switched-off rows collapse and the frame shrinks.

Optional extras:
  portrait  a column left or right, spanning all or the first few visible rows
  castbar   placed as an extra row at the top or bottom, or over the health
            row (it covers the health bar only while casting)
  auras     independently positioned buffs and debuffs on any side
  raidTarget  raid marker centred on a border or inside a portrait corner

The component only builds and lays out the visuals. Feeding unit data is
done by the owner: oUF for live frames (Units/), fake values in the Workbench.

spec:
  frame     use this frame as the root (the oUF unit button); else one is created
  width     default width (of the rows area, including the border padding)
  rows      array of {
              key, label,
              spec      TextBar spec (segments, colorInherit, formats, textDefaults)
              defaults  row option defaults, e.g. { height = 24, right = { size = 9 } }
              options   extra row options (schema entries), e.g. health colour mode
            }
  portrait  { defaults } to offer a portrait
  castbar   { defaults } to offer a castbar
  auras     { defaults, cancelBuffs } to offer buffs/debuffs
  raidTarget  { defaults } to offer a raid target icon
]]
local UnitFrame = ns.Component:Extend("UnitFrame")

UnitFrame.CASTBAR_PLACEMENTS = {
	{ "off", "Off" },
	{ "top", "Extra row at the top" },
	{ "bottom", "Extra row at the bottom" },
	{ "health", "Over the health bar" },
}

UnitFrame.SIDES = {
	{ "LEFT", "Left" },
	{ "RIGHT", "Right" },
}

UnitFrame.RANGE_MODES = {
	{ "group", "Group range" },
	{ "spell", "Spell range" },
}

-- Shared choices keep copied settings valid on units with fewer rows.
UnitFrame.PORTRAIT_ROW_SPANS = {
	{ 0, "All rows" },
	{ 1, "1 row" },
	{ 2, "2 rows" },
	{ 3, "3 rows" },
	{ 4, "4 rows" },
}

function UnitFrame:OnCreate(parent, spec)
	self.frame = spec.frame or CreateFrame("Frame", nil, parent)
	self.rangeInRange, self.rangeChecked = true, false
	-- The unit button may not be a BackdropTemplate frame; draw the border on a child.
	self.border = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
	self.border:SetAllPoints(self.frame)
	self.border:SetFrameLevel(self.frame:GetFrameLevel())

	self.rows = {}
	self.rowsByKey = {}
	for _, def in ipairs(spec.rows) do
		local row = TextBar:New(self.frame, {}, def.spec)
		self.rows[#self.rows + 1] = { def = def, component = row }
		self.rowsByKey[def.key] = row
	end
	if spec.portrait then
		self.portrait = Portrait:New(self.frame, {})
	end
	if spec.castbar then
		self.castbar = Castbar:New(self.frame, {})
		self.castbar:GetFrame():Hide()
	end
	if spec.auras then
		self.auras = Auras:New(self.frame, {}, { cancelBuffs = spec.auras.cancelBuffs, clickThrough = spec.auras.clickThrough })
	end
	if spec.raidTarget then
		self.raidTarget = RaidTarget:New(self.frame, {})
	end
end

-- Copies a component's schema, inserting `extra` options after "enabled"
-- (or at the top) and leaving out keys listed in `skip`.
local function GroupSchema(component, extra, skip)
	local schema, inserted = {}, false
	local function Insert()
		for _, opt in ipairs(extra) do
			schema[#schema + 1] = opt
		end
		inserted = true
	end
	for _, opt in ipairs(component:GetSchema()) do
		if not (skip and skip[opt.key]) then
			schema[#schema + 1] = opt
		end
		if opt.key == "enabled" then
			Insert()
		end
	end
	if not inserted then
		local merged = {}
		for _, opt in ipairs(extra) do
			merged[#merged + 1] = opt
		end
		for _, opt in ipairs(schema) do
			merged[#merged + 1] = opt
		end
		schema = merged
	end
	return schema
end

local function HeightOption(default, hidden)
	return { key = "height", type = "range", label = "Height", min = 2, max = 100, step = 1, default = default or 20,
		hidden = hidden }
end

function UnitFrame:GetSchema()
	if self.schemaCache then
		return self.schemaCache
	end
	local schema = {
		{ key = "width", type = "range", label = "Width", min = 60, max = 600, step = 1, default = self.spec.width or 230 },
		{ key = "spacing", type = "range", label = "Row spacing", min = 0, max = 20, step = 1, default = 1 },
		{ key = "border", type = "group", label = "Frame border", schema = Backdrop.schema,
			defaults = { enabled = true, padding = 4 } },
		{ key = "range", type = "group", label = "Out-of-range opacity", schema = {
			{ key = "enabled", type = "toggle", label = "Enabled", default = false },
			{ key = "outsideAlpha", type = "range", label = "Out-of-range opacity", min = 0, max = 1, step = 0.05, default = 0.55,
				tooltip = "0 = transparent, 1 = fully opaque. In-range and unavailable checks stay fully opaque. Fades the whole frame, including its extras." },
			{ key = "mode", type = "select", label = "Range check", values = UnitFrame.RANGE_MODES, default = "group",
				tooltip = "Group range uses the game's group-member check (normally 40 yards), not enemy distance. Spell range checks the chosen spell against this frame's unit, including enemy targets." },
			{ key = "spell", type = "text", label = "Spell ID or name", default = "",
				hidden = function(cfg) return cfg.mode ~= "spell" end,
				tooltip = "Choose a spell you know that applies to this unit (a heal for allies, an attack for enemies). Unknown spells, invalid targets and spells without a range check do not fade the frame. Names must match your client language." },
		} },
	}
	if self.portrait then
		schema[#schema + 1] = { key = "portrait", type = "group", label = "Portrait", defaults = self.spec.portrait.defaults,
			schema = GroupSchema(self.portrait, {
				{ key = "position", type = "select", label = "Side", values = UnitFrame.SIDES, default = "LEFT" },
				{ key = "rowSpan", type = "select", label = "Rows to span", values = UnitFrame.PORTRAIT_ROW_SPANS, default = 0,
					tooltip = "Count visible rows from the top, including a castbar in its own row. Disabled rows are skipped. Rows below the portrait use the full width. All rows follows the whole frame." },
				{ key = "size", type = "range", label = "Width", min = 0, max = 200, step = 1, default = 0,
					tooltip = "0 = square, as wide as the rows the portrait spans are tall." },
				{ key = "gap", type = "range", label = "Gap to the bars", min = 0, max = 20, step = 1, default = 2 },
			}) }
	end
	for _, row in ipairs(self.rows) do
		local extra = { HeightOption() }
		for _, opt in ipairs(row.def.options or {}) do
			extra[#extra + 1] = opt
		end
		schema[#schema + 1] = { key = row.def.key, type = "group", label = row.def.label,
			schema = GroupSchema(row.component, extra), defaults = row.def.defaults }
	end
	if self.castbar then
		local function OverHealth(cfg)
			return cfg.placement == "health" or cfg.placement == "off"
		end
		schema[#schema + 1] = { key = "castbar", type = "group", label = "Castbar", defaults = self.spec.castbar.defaults,
			schema = GroupSchema(self.castbar, {
				{ key = "placement", type = "select", label = "Placement", values = UnitFrame.CASTBAR_PLACEMENTS,
					default = "bottom" },
				HeightOption(18, OverHealth),
			}, { enabled = true }) }
	end
	if self.auras then
		schema[#schema + 1] = { key = "auras", type = "group", label = "Buffs & debuffs", schema = self.auras:GetSchema(),
			defaults = self.spec.auras.defaults }
	end
	if self.raidTarget then
		schema[#schema + 1] = { key = "raidTarget", type = "group", label = "Raid target icon", schema = self.raidTarget:GetSchema(),
			defaults = self.spec.raidTarget.defaults }
	end
	self.schemaCache = schema
	return schema
end

function UnitFrame:OnApply(cfg)
	Backdrop.ApplyTo(self.border, cfg.border)
	for _, row in ipairs(self.rows) do
		self:ApplyChild(row.component, row.def.key)
	end
	if self.portrait then
		self:ApplyChild(self.portrait, "portrait")
	end
	if self.castbar then
		self:ApplyChild(self.castbar, "castbar")
		self.castbar:SetEnabled(cfg.castbar.placement ~= "off")
	end
	if self.auras then
		self:ApplyChild(self.auras, "auras")
	end
	if self.raidTarget then
		self:ApplyChild(self.raidTarget, "raidTarget")
	end
	self:Layout()
	self:ApplyRangeOpacity()
end

-- Neither range result may be tested in Lua: both can be secret in combat.
-- Native selection also restores full opacity when no range check was made.
function UnitFrame:ApplyRangeOpacity()
	local cfg = self.resolved.range
	if cfg.enabled and ns.Caps.booleanAlpha then
		self.frame:SetAlphaFromBoolean(self.rangeInRange, 1, cfg.outsideAlpha)
		self.frame:SetAlphaFromBoolean(self.rangeChecked, self.frame:GetAlpha(), 1)
	else
		self.frame:SetAlpha(1)
	end
end

function UnitFrame:SetRangeState(inRange, checkedRange)
	self.rangeInRange, self.rangeChecked = inRange, checkedRange
	self:ApplyRangeOpacity()
end

-- Where the castbar actually goes: "health" falls back to the top row when
-- the health row is switched off.
function UnitFrame:GetCastbarPlacement()
	if not self.castbar then
		return "off"
	end
	local placement = self.resolved.castbar.placement
	if placement == "health" and not (self.rowsByKey.health and self.resolved.health.enabled) then
		return "top"
	end
	return placement
end

function UnitFrame:Layout()
	local cfg = self.resolved
	local pad = cfg.border.enabled and cfg.border.padding or 0

	-- Stack items top to bottom.
	local items = {}
	local placement = self:GetCastbarPlacement()
	if placement == "top" then
		items[#items + 1] = { component = self.castbar, height = cfg.castbar.height }
	end
	for _, row in ipairs(self.rows) do
		local rowCfg = cfg[row.def.key]
		row.component:ClearAllPoints()
		if rowCfg.enabled then
			items[#items + 1] = { component = row.component, height = rowCfg.height }
		end
	end
	if placement == "bottom" then
		items[#items + 1] = { component = self.castbar, height = cfg.castbar.height }
	end

	local stackHeight = 0
	for i, item in ipairs(items) do
		stackHeight = stackHeight + item.height + (i > 1 and cfg.spacing or 0)
	end

	-- Portrait column beside the rows.
	local left, right, portraitWidth = pad, pad, 0
	local portraitRows, portraitHeight = 0, 0
	local portrait = self.portrait
	if portrait then
		portrait:ClearAllPoints()
		if cfg.portrait.enabled and stackHeight > 0 then
			portraitRows = cfg.portrait.rowSpan == 0 and #items or math.min(cfg.portrait.rowSpan, #items)
			for i = 1, portraitRows do
				portraitHeight = portraitHeight + items[i].height + (i > 1 and cfg.spacing or 0)
			end
			portraitWidth = cfg.portrait.size > 0 and cfg.portrait.size or portraitHeight
			local side = cfg.portrait.position
			portrait:SetSize(portraitWidth, portraitHeight)
			portrait:SetPoint("TOP" .. side, self.frame, "TOP" .. side, side == "LEFT" and pad or -pad, -pad)
			if side == "LEFT" then
				left = left + portraitWidth + cfg.portrait.gap
			else
				right = right + portraitWidth + cfg.portrait.gap
			end
			portraitWidth = portraitWidth + cfg.portrait.gap
		end
	end

	local y = pad
	for i, item in ipairs(items) do
		if i > 1 then
			y = y + cfg.spacing
		end
		local component = item.component
		component:ClearAllPoints()
		component:SetPoint("TOPLEFT", self.frame, "TOPLEFT", i <= portraitRows and left or pad, -y)
		component:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -(i <= portraitRows and right or pad), -y)
		component:GetFrame():SetHeight(item.height)
		y = y + item.height
	end

	if self.castbar then
		local castFrame = self.castbar:GetFrame()
		if placement == "health" then
			-- Covers the health row while a cast is shown.
			local health = self.rowsByKey.health:GetFrame()
			self.castbar:ClearAllPoints()
			self.castbar:SetAllPoints(health)
			castFrame:SetFrameLevel(health:GetFrameLevel() + 10)
		else
			castFrame:SetFrameLevel(self.frame:GetFrameLevel() + 1)
		end
		self.castbar:SetOpaque(placement == "health")
	end

	local width = cfg.width + portraitWidth
	self:Resize(width, math.max(stackHeight + 2 * pad, 1))

	if self.auras then
		self.auras:Layout(width, math.max(stackHeight + 2 * pad, 1))
	end
	if self.raidTarget then
		local anchorPortrait = portraitWidth > 0 and portrait or nil
		self.raidTarget:Layout(self.frame, anchorPortrait,
			anchorPortrait and portraitWidth - cfg.portrait.gap or 0, portraitHeight)
	end
end

-- Unit buttons are protected: resizing them waits until combat ends.
local pending = {}
local regenFrame = CreateFrame("Frame")
regenFrame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	for component in pairs(pending) do
		pending[component] = nil
		component:Layout()
	end
end)

function UnitFrame:Resize(width, height)
	if self.frame:IsProtected() and InCombatLockdown() then
		pending[self] = true
		regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	self.frame:SetSize(width, height)
end

function UnitFrame:OnRelease()
	pending[self] = nil
	for _, row in ipairs(self.rows) do
		row.component:Release()
	end
	if self.portrait then
		self.portrait:Release()
	end
	if self.castbar then
		self.castbar:Release()
	end
	if self.auras then
		self.auras:Release()
	end
	if self.raidTarget then
		self.raidTarget:Release()
	end
end

function UnitFrame:SetCombatDeferred(deferred)
	ns.Component.SetCombatDeferred(self, deferred)
	for _, row in ipairs(self.rows) do row.component:SetCombatDeferred(deferred) end
	for _, child in ipairs({ self.portrait or false, self.castbar or false, self.auras or false, self.raidTarget or false }) do
		if child then child:SetCombatDeferred(deferred) end
	end
end

-- A row's TextBar, by key ("health", "power", ...).
function UnitFrame:GetRow(key)
	return self.rowsByKey[key]
end

-- Resolved row config (enabled, height, extra options, ...).
function UnitFrame:GetRowConfig(key)
	return self.resolved[key]
end

-- Iterates rows: for key, row, rowConfig in frame:Rows() do ... end
function UnitFrame:Rows()
	local i = 0
	return function()
		i = i + 1
		local row = self.rows[i]
		if row then
			return row.def.key, row.component, self.resolved[row.def.key]
		end
	end
end

function UnitFrame:GetPortrait()
	return self.portrait
end

function UnitFrame:GetCastbar()
	return self.castbar
end

function UnitFrame:GetAuras()
	return self.auras
end

function UnitFrame:GetRaidTarget()
	return self.raidTarget
end
