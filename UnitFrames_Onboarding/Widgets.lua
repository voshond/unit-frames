local _, ob = ...
local UF = UnitFrames
local Skin = UF.Skin
local C = Skin.colors

--[[
The guide's look: flat panels from the shared Skin, an accent glow made of
two soft outer rings, and Roboto Condensed headings when UnitFrames_Media
is loaded. Controls extend UF.Widget like the Workbench's.
]]
ob.COLORS = {
	rail = { 0.035, 0.035, 0.05, 1 },
	well = { 0.03, 0.03, 0.045, 1 },
	ink = { 0.05, 0.05, 0.07, 1 },
	faint = { 0.36, 0.36, 0.41, 1 },
	off = { 0.13, 0.13, 0.16, 0.6 },
	cast = { 1, 0.7, 0, 1 },
	group = { 0.33, 0.84, 0.54, 1 },
	aura = { 0.69, 0.49, 1, 1 },
	import = { 1, 0.48, 0.35, 1 },
}
local COLORS = ob.COLORS

ob.CHECK = [[Interface\Buttons\UI-CheckBox-Check]]

local HEADING_FONTS = { "Roboto Condensed Bold", "Friz Quadrata TT" }
local BODY_FONTS = { "Roboto Condensed", "Friz Quadrata TT" }

local function FontKey(candidates)
	for _, key in ipairs(candidates) do
		if UF.Media.LSM:IsValid("font", key) then return key end
	end
	return UF.Media.LSM:GetDefault("font")
end

function ob.Font(size, heading)
	return UF.Media:GetFontObject(FontKey(heading and HEADING_FONTS or BODY_FONTS), size)
end

function ob.Text(parent, size, color, heading)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(ob.Font(size, heading))
	text:SetTextColor(unpack(color or C.text))
	text:SetJustifyH("LEFT")
	return text
end

function ob.Panel(frame, background, border)
	frame:SetBackdrop({ bgFile = Skin.WHITE, edgeFile = Skin.WHITE, edgeSize = 1 })
	ob.Paint(frame, background, border)
end

function ob.Paint(frame, background, border)
	frame:SetBackdropColor(unpack(background))
	frame:SetBackdropBorderColor(unpack(border or background))
end

-- Two rings outside `frame` in `color`, hidden until shown.
function ob.Glow(frame, color)
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetAllPoints()
	glow:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	for index, ring in ipairs({ { 2, 0.55 }, { 5, 0.18 } }) do
		local edge = CreateFrame("Frame", nil, glow, "BackdropTemplate")
		edge:SetPoint("TOPLEFT", -ring[1], ring[1])
		edge:SetPoint("BOTTOMRIGHT", ring[1], -ring[1])
		edge:SetBackdrop({ edgeFile = Skin.WHITE, edgeSize = index })
		edge:SetBackdropBorderColor(color[1], color[2], color[3], ring[2])
	end
	glow:Hide()
	return glow
end

--[[
Selectable flat button: chips (step 2), tiles (step 3), preset cards.
opts: text, font (LSM key), width, height, accent (colour), dot, tooltip, onClick(self)
]]
local Chip = UF.Widget:Extend("OnboardingChip")
ob.Widgets = { Chip = Chip }

function Chip:OnCreate(parent, opts)
	local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
	self.frame = frame
	self.accent = opts.accent or C.accent
	ob.Panel(frame, C.button, C.border)
	self.glow = ob.Glow(frame, self.accent)
	self.text = ob.Text(frame, opts.size or 12)
	self.text:SetJustifyH("CENTER")
	self.text:SetPoint("CENTER")
	if opts.font then self.text:SetFontObject(UF.Media:GetFontObject(opts.font, opts.size or 12)) end
	self.text:SetText(opts.text or "")
	frame:SetSize(opts.width or math.max(54, self.text:GetStringWidth() + 28), opts.height or 28)
	if opts.dot then
		self.dot = frame:CreateTexture(nil, "OVERLAY")
		self.dot:SetTexture(Skin.WHITE)
		self.dot:SetSize(6, 6)
		self.dot:SetPoint("TOPRIGHT", -6, -6)
	end
	frame:SetScript("OnEnter", function() self.hover = true; self:UpdateColors() end)
	frame:SetScript("OnLeave", function() self.hover = false; self:UpdateColors() end)
	frame:SetScript("OnClick", function() if self.opts.onClick then self.opts.onClick(self) end end)
	UF.Widget.AttachTooltip(frame, opts.text, opts.tooltip)
	self:UpdateColors()
end

function Chip:SetSelected(selected)
	self.selected = selected and true or false
	self:UpdateColors()
end

function Chip:UpdateColors()
	local accent, selected = self.accent, self.selected
	local background = selected and { accent[1], accent[2], accent[3], 0.2 } or (self.hover and C.buttonHover or C.button)
	ob.Paint(self.frame, background, (selected or self.hover) and accent or C.border)
	self.text:SetTextColor(unpack(selected and accent or C.text))
	self.glow:SetShown(selected)
	if self.dot then self.dot:SetVertexColor(unpack(selected and accent or COLORS.faint)) end
end

--[[
Preset card: a dark well for a mini preview, the name, two tags and a check
badge when chosen. opts: name, tags, onClick(self)
]]
local Card = Chip:Extend("OnboardingCard")
ob.Widgets.Card = Card

function Card:OnCreate(parent, opts)
	Chip.OnCreate(self, parent, { width = opts.width or 190, height = 176, onClick = opts.onClick, text = "" })
	local frame = self.frame
	self.well = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	self.well:SetPoint("TOPLEFT", 1, -1)
	self.well:SetPoint("TOPRIGHT", -1, -1)
	self.well:SetHeight(94)
	ob.Panel(self.well, COLORS.well)
	self.name = ob.Text(frame, 17, C.text, true)
	self.name:SetPoint("TOPLEFT", 14, -106)
	self.name:SetText(opts.name)
	local previous
	for _, tag in ipairs(opts.tags or {}) do
		local pill = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		ob.Panel(pill, { 1, 1, 1, 0.06 })
		local text = ob.Text(pill, 10, C.textDim)
		text:SetPoint("CENTER")
		text:SetText(tag)
		pill:SetSize(text:GetStringWidth() + 14, 18)
		pill:SetPoint("TOPLEFT", previous or frame, previous and "TOPRIGHT" or "TOPLEFT", previous and 6 or 14, previous and 0 or -138)
		previous = pill
	end
	self.badge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	self.badge:SetSize(20, 20)
	self.badge:SetPoint("TOPRIGHT", -12, -104)
	ob.Panel(self.badge, C.accent)
	local check = self.badge:CreateTexture(nil, "OVERLAY")
	check:SetTexture(ob.CHECK)
	check:SetVertexColor(unpack(COLORS.ink))
	check:SetAllPoints()
	self:UpdateColors()
end

function Card:UpdateColors()
	Chip.UpdateColors(self)
	ob.Paint(self.frame, C.panel, (self.selected or self.hover) and C.accent or C.border)
	if self.badge then self.badge:SetShown(self.selected) end
end
