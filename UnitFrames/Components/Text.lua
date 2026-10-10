local _, ns = ...
local Media, Util = ns.Media, ns.Util

-- A single line of text. Accepts secret strings and numbers: they render
-- normally, they just can't be read back (GetText returns a secret).
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
