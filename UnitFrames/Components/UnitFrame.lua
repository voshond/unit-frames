local _, ns = ...
local Backdrop, TextBar = ns.Components.Backdrop, ns.Components.TextBar
local Castbar, Portrait = ns.Components.Castbar, ns.Components.Portrait

--[[
A unit frame made of rows stacked top to bottom inside one bordered frame.
Each row is a TextBar (bar + left/centre/right text) with its own height and
on/off toggle; switched-off rows collapse and the frame shrinks.

Optional extras:
  portrait  a column left or right of the rows, as tall as all rows together
  castbar   placed as an extra row at the top or bottom, or over the health
            row (it covers the health bar only while casting)

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

function UnitFrame:OnCreate(parent, spec)
	self.frame = spec.frame or CreateFrame("Frame", nil, parent)
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
	}
	if self.portrait then
		schema[#schema + 1] = { key = "portrait", type = "group", label = "Portrait", defaults = self.spec.portrait.defaults,
			schema = GroupSchema(self.portrait, {
				{ key = "position", type = "select", label = "Side", values = UnitFrame.SIDES, default = "LEFT" },
				{ key = "size", type = "range", label = "Width", min = 0, max = 200, step = 1, default = 0,
					tooltip = "0 = square, as wide as the rows are tall." },
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
	self:Layout()
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
	local portrait = self.portrait
	if portrait then
		portrait:ClearAllPoints()
		if cfg.portrait.enabled and stackHeight > 0 then
			portraitWidth = cfg.portrait.size > 0 and cfg.portrait.size or stackHeight
			local side = cfg.portrait.position
			portrait:SetSize(portraitWidth, stackHeight)
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
		component:SetPoint("TOPLEFT", self.frame, "TOPLEFT", left, -y)
		component:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -right, -y)
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

	self:Resize(cfg.width + portraitWidth, math.max(stackHeight + 2 * pad, 1))
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
	for _, row in ipairs(self.rows) do
		row.component:Release()
	end
	if self.portrait then
		self.portrait:Release()
	end
	if self.castbar then
		self.castbar:Release()
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
