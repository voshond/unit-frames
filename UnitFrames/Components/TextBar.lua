local _, ns = ...
local Bar, Text = ns.Components.Bar, ns.Components.Text

--[[
A Bar with text slots spanning the bar: left, centre, right, plus a smaller
text below the left and below the right one. Each slot can be turned on/off,
aligned and given a format (what it shows). When a "below" text is on, the
text above it moves to the top half (unless its position is set by hand).
The centred text layout instead keeps both lines together as one block
around the bar's middle, so a taller bar adds space around the block.

spec: everything Bar takes (segments, colorInherit), plus
  formats       format ids the texts may show (Core/Formats.lua)
  textContext   what the host provides to its texts (see Text); the bar adds
                its own `valueKind` ("health", "power", "xp") as `bar`
  textDefaults  default format per slot, e.g. { left = "name", right = "health:value" };
                { format = ..., enabled = false } offers a format but starts switched off
  nativeLayout  the bar can follow native geometry (see Bar); ExtendBar moves
                its top or bottom edge. The row frame stays an ordinary frame
                at the configured height (a covering castbar uses it). Texts
                live on the bar and follow it, so frames anchored to them
                (icons before the name) need the forbidden layout aspect too.
]]
local TextBar = ns.Component:Extend("TextBar")

TextBar.SLOTS = {
	{ key = "left", label = "Left text", justifyH = "LEFT" },
	{ key = "center", label = "Centre text", justifyH = "CENTER" },
	{ key = "right", label = "Right text", justifyH = "RIGHT" },
	{ key = "belowLeft", label = "Small text below left", justifyH = "LEFT", below = "left", size = 9 },
	{ key = "belowRight", label = "Small text below right", justifyH = "RIGHT", below = "right", size = 9 },
}

TextBar.TEXT_LAYOUTS = {
	{ "edges", "Top and bottom" },
	{ "centred", "Centred block" },
}

local function TextContext(spec)
	return ns.Util.Merge(ns.Util.Copy(spec.textContext or {}), { bar = spec.valueKind })
end

function TextBar:OnCreate(parent, spec)
	if spec.nativeLayout then
		self.frame = CreateFrame("Frame", nil, parent)
		self.bar = self:Own(Bar:New(self.frame, self:ChildConfig("bar"), spec))
		self.bar:GetFrame():SetAllPoints(self.frame)
	else
		self.bar = self:Own(Bar:New(parent, self:ChildConfig("bar"), spec))
		self.frame = self.bar:GetFrame()
	end
	local host = self.bar:GetTextParent()
	self.texts = {}
	for _, slot in ipairs(TextBar.SLOTS) do
		self.texts[slot.key] = self:Own(Text:New(host, self:ChildConfig(slot.key), { host = host, formats = spec.formats,
			context = TextContext(spec), schemaOwner = spec.schemaOwner }))
	end
end

function TextBar.BuildSchema(spec)
	spec = spec or {}
	local textDefaults = spec.textDefaults or {}
	local context = TextContext(spec)
	local schema = {
		{ key = "enabled", type = "toggle", label = "Enabled", default = true },
		{ key = "bar", type = "group", label = "Bar", schema = Bar.BuildSchema(spec), defaults = ns.Util.Copy(spec.barDefaults) },
		{ key = "textLayout", type = "select", label = "Text layout", values = TextBar.TEXT_LAYOUTS, default = "edges",
			tooltip = "Centred block: a text and the small text below it form one block in the middle of the bar. A taller bar adds space around the block instead of between its lines." },
		{ key = "lineGap", type = "range", label = "Line spacing", min = 0, max = 20, step = 1, default = 1,
			tooltip = "Space between the two lines of a centred block.",
			hidden = function(cfg) return cfg.textLayout ~= "centred" end },
	}
	for _, slot in ipairs(TextBar.SLOTS) do
		local default = textDefaults[slot.key]
		local format, enabled = default, default ~= nil -- slots without a default start switched off
		if type(default) == "table" then
			format, enabled = default.format, default.enabled ~= false
		end
		schema[#schema + 1] = {
			key = slot.key, type = "group", label = slot.label, textSlot = context,
			schema = Text.BuildSchema({ host = true, formats = spec.formats, context = context }),
			defaults = { justifyH = slot.justifyH, format = format or "none", enabled = enabled, size = slot.size },
		}
	end
	return schema
end

function TextBar:OnApply(cfg)
	self:ApplyChild(self.bar, "bar")
	local centred = cfg.textLayout == "centred"
	for _, slot in ipairs(TextBar.SLOTS) do
		local text = self.texts[slot.key]
		local above, below = slot.below, self:BelowSlot(slot.key)
		if centred then
			-- A block's lines sit around the middle by their font sizes and
			-- the gap: plain settings, never the (possibly secret) geometry.
			local gap = cfg.lineGap
			if above and cfg[above].enabled and cfg[slot.key].enabled then
				text:SetAutoVertical("middle", -(cfg[above].size + gap) / 2)
			elseif below and cfg[below].enabled and cfg[slot.key].enabled then
				text:SetAutoVertical("middle", (cfg[below].size + gap) / 2)
			else
				text:SetAutoVertical("middle")
			end
		elseif above then
			text:SetAutoVertical("bottom")
		else
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

-- Native-layout rows: the bar's far edge follows `region`, which must carry
-- the forbidden layout aspect itself ("BOTTOM": the bar's bottom meets the
-- region's top; "TOP": its top meets the region's bottom). The other edges
-- stay on the row; x shifts the followed side. No edge: back on the row.
function TextBar:ExtendBar(edge, region, x)
	local root = self.bar:GetFrame()
	root:ClearAllPoints()
	if edge == "BOTTOM" then
		root:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
		root:SetPoint("BOTTOMRIGHT", region, "TOPRIGHT", x, 0)
	elseif edge == "TOP" then
		root:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
		root:SetPoint("TOPLEFT", region, "BOTTOMLEFT", x, 0)
	else
		root:SetAllPoints(self.frame)
	end
end

function TextBar:SetKnownSize(width, height)
	self.bar:SetKnownSize(width, height)
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
