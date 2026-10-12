local _, ns = ...
local Bar, Text = ns.Components.Bar, ns.Components.Text

--[[
A Bar with text slots spanning the bar: left, centre, right, plus a smaller
text below the left and below the right one. Each slot can be turned on/off,
aligned and given a format (what it shows). When a "below" text is on, the
text above it moves to the top half (unless its position is set by hand).

spec: everything Bar takes (segments, colorInherit), plus
  formats       format ids the texts may show (Core/Formats.lua)
  textDefaults  default format per slot, e.g. { left = "name", right = "health:value" };
                { format = ..., enabled = false } offers a format but starts switched off
]]
local TextBar = ns.Component:Extend("TextBar")

TextBar.SLOTS = {
	{ key = "left", label = "Left text", justifyH = "LEFT" },
	{ key = "center", label = "Centre text", justifyH = "CENTER" },
	{ key = "right", label = "Right text", justifyH = "RIGHT" },
	{ key = "belowLeft", label = "Small text below left", justifyH = "LEFT", below = "left", size = 9 },
	{ key = "belowRight", label = "Small text below right", justifyH = "RIGHT", below = "right", size = 9 },
}

function TextBar:OnCreate(parent, spec)
	self.bar = self:Own(Bar:New(parent, {}, spec))
	self.frame = self.bar:GetFrame()
	local host = self.bar:GetTextParent()
	self.texts = {}
	for _, slot in ipairs(TextBar.SLOTS) do
		self.texts[slot.key] = self:Own(Text:New(host, {}, { host = host, formats = spec.formats }))
	end
end

function TextBar.BuildSchema(spec)
	spec = spec or {}
	local textDefaults = spec.textDefaults or {}
	local schema = {
		{ key = "enabled", type = "toggle", label = "Enabled", default = true },
		{ key = "bar", type = "group", label = "Bar", schema = Bar.BuildSchema(spec), defaults = ns.Util.Copy(spec.barDefaults) },
	}
	for _, slot in ipairs(TextBar.SLOTS) do
		local default = textDefaults[slot.key]
		local format, enabled = default, default ~= nil -- slots without a default start switched off
		if type(default) == "table" then
			format, enabled = default.format, default.enabled ~= false
		end
		schema[#schema + 1] = {
			key = slot.key, type = "group", label = slot.label, schema = Text.BuildSchema({ host = true, formats = spec.formats }),
			defaults = { justifyH = slot.justifyH, format = format or "none", enabled = enabled, size = slot.size },
		}
	end
	return schema
end

function TextBar:OnApply(cfg)
	self:ApplyChild(self.bar, "bar")
	for _, slot in ipairs(TextBar.SLOTS) do
		local text = self.texts[slot.key]
		if slot.below then
			text:SetAutoVertical("bottom")
		else
			local below = self:BelowSlot(slot.key)
			text:SetAutoVertical(below and cfg[below].enabled and "top" or "middle")
		end
		self:ApplyChild(text, slot.key)
	end
end

-- The key of the small slot below `key`, if any.
function TextBar:BelowSlot(key)
	for _, slot in ipairs(TextBar.SLOTS) do
		if slot.below == key then
			return slot.key
		end
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
function TextBar:SetTint(r, g, b, amount) self.bar:SetTint(r, g, b, amount) end
