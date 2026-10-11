local _, ns = ...
local Media, Util = ns.Media, ns.Util

--[[
A single line of text. Accepts secret strings and numbers: they render
normally, they just can't be read back (GetText returns a secret).

spec (optional):
  host     frame the text spans (left edge to right edge, minus `inset`), so
           the alignment option actually moves the text. Without a host the
           owner anchors the text itself.
  formats  list of format ids (Core/Formats.lua); adds a `format` option. The
           owner decides how to fill the text from it.
]]
local Text = ns.Component:Extend("Text")

Text.JUSTIFY = {
	{ "LEFT", "Left" },
	{ "CENTER", "Centre" },
	{ "RIGHT", "Right" },
}

Text.schema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "font", type = "font", label = "Font", inherit = "font" },
	{ key = "size", type = "range", label = "Size", min = 6, max = 40, step = 1, inherit = "fontSize" },
	{ key = "outline", type = "select", label = "Outline", values = ns.Theme.OUTLINES, inherit = "fontOutline" },
	{ key = "shadow", type = "toggle", label = "Shadow", default = true },
	{ key = "color", type = "color", label = "Colour", default = { 1, 1, 1, 1 } },
	{ key = "justifyH", type = "select", label = "Alignment", values = Text.JUSTIFY, default = "CENTER" },
}

Text.VERTICAL = {
	{ "auto", "Automatic" },
	{ "middle", "Middle" },
	{ "top", "Top" },
	{ "bottom", "Bottom" },
}

local HOST_OPTIONS = {
	{ key = "vertical", type = "select", label = "Vertical position", values = Text.VERTICAL, default = "auto",
		tooltip = "Automatic: middle, or decided by the owner (e.g. moves up to make room for a text below)." },
	{ key = "inset", type = "range", label = "Edge inset", min = 0, max = 30, step = 1, default = 4,
		tooltip = "Distance from the left and right edge." },
	{ key = "offsetX", type = "range", label = "Offset X", min = -100, max = 100, step = 1, default = 0 },
	{ key = "offsetY", type = "range", label = "Offset Y", min = -50, max = 50, step = 1, default = 0 },
}

function Text.BuildSchema(spec)
	spec = spec or {}
	local schema = {}
	if spec.formats then
		schema[1] = { key = "format", type = "select", label = "Shows", values = ns.Formats.Values(spec.formats),
			default = "none" }
	end
	for _, opt in ipairs(Text.schema) do
		schema[#schema + 1] = opt
	end
	if spec.host then
		for _, opt in ipairs(HOST_OPTIONS) do
			schema[#schema + 1] = opt
		end
	end
	return ns.Util.Copy(schema)
end

function Text:OnCreate(parent)
	self.frame = parent:CreateFontString(nil, "OVERLAY")
end

function Text:OnApply(cfg)
	local fs = self.frame
	if not fs:SetFont(Media:Fetch("font", cfg.font), cfg.size, Media:Outline(cfg.outline)) then
		fs:SetFont(Media:Fetch("font", Media.LSM:GetDefault("font")), cfg.size, Media:Outline(cfg.outline))
	end
	if cfg.shadow then
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
	else
		fs:SetShadowOffset(0, 0)
	end
	fs:SetTextColor(Util.UnpackColor(cfg.color))
	fs:SetJustifyH(cfg.justifyH)
	fs:SetWordWrap(false)
	self:Layout()
end

-- Transient room for an adjacent indicator, not a saved text-style override.
function Text:SetLeadingSpace(space)
	self.leadingSpace = space
	self:Layout()
end

function Text:Layout()
	local cfg, fs = self.resolved, self.frame
	if not cfg then return end
	local host = self.spec.host
	if host then
		local vertical = cfg.vertical
		if vertical == "auto" then
			vertical = self.autoVertical or "middle"
		end
		-- top/bottom sit 1px inside the edge; middle is centred.
		local edge, y = "", cfg.offsetY
		if vertical == "top" then
			edge, y = "TOP", y - 1
		elseif vertical == "bottom" then
			edge, y = "BOTTOM", y + 1
		end
		fs:ClearAllPoints()
		fs:SetPoint(edge .. "LEFT", host, edge .. "LEFT", cfg.inset + cfg.offsetX + (self.leadingSpace or 0), y)
		fs:SetPoint(edge .. "RIGHT", host, edge .. "RIGHT", -cfg.inset + cfg.offsetX, y)
	end
end

-- Where "auto" vertical position goes ("middle", "top", "bottom"); set by the
-- owner before applying.
function Text:SetAutoVertical(vertical)
	self.autoVertical = vertical
end

function Text:GetFormat()
	return self.resolved.format or "none"
end

-- Data API ------------------------------------------------------------------

function Text:SetText(text)
	self.frame:SetText(text)
end

function Text:SetFormattedText(fmt, ...)
	self.frame:SetFormattedText(fmt, ...)
end

function Text:SetTextColor(r, g, b, a)
	self.frame:SetTextColor(r, g, b, a or 1)
end

-- Fills the text from its format with plain sample values.
function Text:ShowSample(values)
	self.frame:SetText(ns.Formats.Get(self:GetFormat()).sample(values))
end

-- Fills the text from its format with the live (possibly secret) unit data.
function Text:ShowLive(unit)
	self.frame:SetText(ns.Formats.Get(self:GetFormat()).text(unit))
end
