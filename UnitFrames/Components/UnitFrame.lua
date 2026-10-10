local _, ns = ...
local Backdrop, TextBar = ns.Components.Backdrop, ns.Components.TextBar

--[[
A unit frame made of rows stacked top to bottom inside one bordered frame.
Each row is a TextBar (bar + left/centre/right text) with its own height and
on/off toggle; switched-off rows collapse and the frame shrinks.

The component only builds and lays out the visuals. Feeding unit data is
done by the owner: oUF for live frames (Units/), fake values in the Workbench.

spec:
  frame   use this frame as the root (the oUF unit button); else one is created
  width   default width
  rows    array of {
            key, label,
            spec      TextBar spec (segments, colorInherit, formats, textDefaults)
            defaults  row option defaults, e.g. { height = 24, right = { size = 9 } }
            options   extra row options (schema entries), e.g. health colour mode
          }
]]
local UnitFrame = ns.Component:Extend("UnitFrame")

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
	for _, row in ipairs(self.rows) do
		local rowSchema = {}
		for _, opt in ipairs(row.component:GetSchema()) do
			rowSchema[#rowSchema + 1] = opt
			if opt.key == "enabled" then
				rowSchema[#rowSchema + 1] = { key = "height", type = "range", label = "Height", min = 2, max = 100, step = 1,
					default = 20 }
				for _, extra in ipairs(row.def.options or {}) do
					rowSchema[#rowSchema + 1] = extra
				end
			end
		end
		schema[#schema + 1] = { key = row.def.key, type = "group", label = row.def.label, schema = rowSchema,
			defaults = row.def.defaults }
	end
	self.schemaCache = schema
	return schema
end

function UnitFrame:OnApply(cfg)
	Backdrop.ApplyTo(self.border, cfg.border)
	for _, row in ipairs(self.rows) do
		self:ApplyChild(row.component, row.def.key)
	end
	self:Layout()
end

function UnitFrame:Layout()
	local cfg = self.resolved
	local pad = cfg.border.enabled and cfg.border.padding or 0
	local y = pad
	local shown = 0
	for _, row in ipairs(self.rows) do
		local rowCfg = cfg[row.def.key]
		local component = row.component
		component:ClearAllPoints()
		if rowCfg.enabled then
			if shown > 0 then
				y = y + cfg.spacing
			end
			component:SetPoint("TOPLEFT", self.frame, "TOPLEFT", pad, -y)
			component:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -pad, -y)
			component:GetFrame():SetHeight(rowCfg.height)
			y = y + rowCfg.height
			shown = shown + 1
		end
	end
	self:Resize(cfg.width, math.max(y + pad, 1))
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

