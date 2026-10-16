local _, ns = ...
local Castbar, TextBar = ns.Components.Castbar, ns.Components.TextBar
local CastbarFrame = ns.Component:Extend("CastbarFrame")

CastbarFrame.SWING_ROWS = {
	{ key = "mainHand", label = "Main hand" },
	{ key = "offHand", label = "Off hand" },
	{ key = "ranged", label = "Ranged" },
}

local SWING_SPEC = {
	textDefaults = { left = "none", right = "none" },
	barDefaults = { smooth = false, spark = true },
}

local function RowSchema(schema, height)
	return ns.Schema.Insert(schema, "enabled", {
		{ key = "height", type = "range", label = "Height", min = 2, max = 100, step = 1, default = height },
	})
end

function CastbarFrame.BuildSchema(spec)
	local schema = {
		{ key = "enabled", type = "toggle", label = "Enabled", default = not (spec and spec.standalone) },
		{ key = "width", type = "range", label = "Width", min = 80, max = 800, step = 1, default = 280 },
		{ key = "gap", type = "range", label = "Row spacing", min = 0, max = 20, step = 1, default = 2 },
		{ key = "castbar", type = "group", label = "Castbar",
			schema = RowSchema(Castbar.BuildSchema({ playerCast = true }), 24) },
	}
	for _, row in ipairs(CastbarFrame.SWING_ROWS) do
		schema[#schema + 1] = { key = row.key, type = "group", label = row.label,
			schema = RowSchema(TextBar.BuildSchema(SWING_SPEC), 10), defaults = { enabled = false } }
	end
	return schema
end

function CastbarFrame:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent)
	self.castbar = self:Own(Castbar:New(self.frame, self:ChildConfig("castbar"), { playerCast = true }))
	self.castbar:Hide()
	self.rows = {}
	for _, row in ipairs(self.SWING_ROWS) do
		self.rows[row.key] = self:Own(TextBar:New(self.frame, self:ChildConfig(row.key), SWING_SPEC))
		self.rows[row.key]:SetRange(0, 1)
		self.rows[row.key]:SetValue(0)
	end
end

function CastbarFrame:OnApply(cfg)
	self:ApplyChild(self.castbar, "castbar")
	for _, row in ipairs(self.SWING_ROWS) do
		self:ApplyChild(self.rows[row.key], row.key)
	end
	local height, count = 0, 0
	local function Place(component, options)
		component:ClearAllPoints()
		if not options.enabled then return end
		if count > 0 then height = height + cfg.gap end
		component:SetSize(cfg.width, options.height)
		component:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -height)
		height = height + options.height
		count = count + 1
	end
	Place(self.castbar, cfg.castbar)
	for _, row in ipairs(self.SWING_ROWS) do
		Place(self.rows[row.key], cfg[row.key])
	end
	self.hasRows = count > 0
	self.frame:SetSize(cfg.width, math.max(1, height))
end

function CastbarFrame:SetEnabled(enabled)
	self.enabled = enabled and true or false
	self.frame:SetShown(self.enabled and self.hasRows)
	if self.enabled then return end
	self.castbar:Hide()
	self.castbar:StopGCD()
end

function CastbarFrame:GetCastbar()
	return self.castbar
end

function CastbarFrame:GetRow(key)
	return self.rows[key]
end
