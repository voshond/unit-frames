local _, ns = ...
local Bar, Text = ns.Components.Bar, ns.Components.Text

--[[
A Bar with three text slots (left, centre, right) spanning the bar. Each slot
can be turned on/off, aligned and given a format (what it shows).

spec: everything Bar takes (segments, colorInherit), plus
  formats       format ids the texts may show (Core/Formats.lua)
  textDefaults  default format per slot, e.g. { left = "name", right = "health:value" }
]]
local TextBar = ns.Component:Extend("TextBar")

TextBar.SLOTS = {
	{ key = "left", label = "Left text", justifyH = "LEFT" },
	{ key = "center", label = "Centre text", justifyH = "CENTER" },
	{ key = "right", label = "Right text", justifyH = "RIGHT" },
}

function TextBar:OnCreate(parent, spec)
	self.bar = Bar:New(parent, {}, spec)
	self.frame = self.bar:GetFrame()
	local host = self.bar:GetTextParent()
	self.texts = {}
	for _, slot in ipairs(TextBar.SLOTS) do
		self.texts[slot.key] = Text:New(host, {}, { host = host, formats = spec.formats })
	end
end

function TextBar:GetSchema()
	if self.schemaCache then
		return self.schemaCache
	end
	local textDefaults = self.spec.textDefaults or {}
	local schema = {
		{ key = "enabled", type = "toggle", label = "Enabled", default = true },
		{ key = "bar", type = "group", label = "Bar", schema = self.bar:GetSchema(), defaults = self.spec.barDefaults },
	}
	for _, slot in ipairs(TextBar.SLOTS) do
		local format = textDefaults[slot.key]
		schema[#schema + 1] = {
			key = slot.key, type = "group", label = slot.label, schema = self.texts[slot.key]:GetSchema(),
			-- Slots without a default format start switched off.
			defaults = { justifyH = slot.justifyH, format = format or "none", enabled = format ~= nil },
		}
	end
	self.schemaCache = schema
	return schema
end

function TextBar:OnApply()
	self:ApplyChild(self.bar, "bar")
	for _, slot in ipairs(TextBar.SLOTS) do
		self:ApplyChild(self.texts[slot.key], slot.key)
	end
end

function TextBar:OnRelease()
	self.bar:Release()
	for _, text in pairs(self.texts) do
		text:Release()
	end
end

function TextBar:GetBar()
	return self.bar
end

function TextBar:GetText(key)
	return self.texts[key]
end

-- Iterates enabled texts: for key, text in row:EnabledTexts() do ... end
function TextBar:EnabledTexts()
	local i = 0
	return function()
		while true do
			i = i + 1
			local slot = TextBar.SLOTS[i]
			if not slot then
				return nil
			end
			local text = self.texts[slot.key]
			if text:IsEnabled() then
				return slot.key, text
			end
		end
	end
end

-- Fills every enabled text from its format (see Text:ShowSample/ShowLive).
function TextBar:ShowSample(values)
	for _, text in self:EnabledTexts() do
		text:ShowSample(values)
	end
end

function TextBar:ShowLive(unit)
	for _, text in self:EnabledTexts() do
		text:ShowLive(unit)
	end
end

-- Passthroughs to the bar for convenience.
function TextBar:SetRange(min, max) self.bar:SetRange(min, max) end
function TextBar:SetValue(value) self.bar:SetValue(value) end
function TextBar:SetSegmentValue(key, value) self.bar:SetSegmentValue(key, value) end
function TextBar:SetColor(r, g, b, a) self.bar:SetColor(r, g, b, a) end
function TextBar:ClearColor() self.bar:ClearColor() end

