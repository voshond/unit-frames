local _, ns = ...
local Skin = ns.Skin

--[[
Colour swatch with a label; opens Blizzard's colour picker.
opts: label, tooltip, hasAlpha (default true), onChange({ r, g, b, a })
]]
local ColorSwatch = ns.Widget:Extend("ColorSwatch")

function ColorSwatch:OnCreate(parent, opts)
	local frame = CreateFrame("Button", nil, parent)
	self.frame = frame
	frame:SetHeight(20)

	local swatch = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	swatch:SetSize(28, 14)
	swatch:SetPoint("LEFT")
	Skin.ApplyPanel(swatch, "button")
	self.swatch = swatch

	-- Two-tone backing so the alpha of the colour is visible.
	local back = swatch:CreateTexture(nil, "BACKGROUND", nil, 1)
	back:SetPoint("TOPLEFT", 1, -1)
	back:SetPoint("BOTTOMRIGHT", swatch, "BOTTOM", 0, 1)
	back:SetColorTexture(1, 1, 1, 1)

	self.color = swatch:CreateTexture(nil, "ARTWORK")
	self.color:SetPoint("TOPLEFT", 1, -1)
	self.color:SetPoint("BOTTOMRIGHT", -1, 1)

	self:CreateLabel(frame, opts.label):SetPoint("LEFT", swatch, "RIGHT", 6, 0)
	self.label:SetPoint("RIGHT")

	frame:SetScript("OnClick", function()
		self:OpenPicker()
	end)
	frame:SetScript("OnEnter", function()
		swatch:SetBackdropBorderColor(unpack(Skin.colors.accent))
	end)
	frame:SetScript("OnLeave", function()
		swatch:SetBackdropBorderColor(unpack(Skin.colors.border))
	end)
	ns.Widget.AttachTooltip(frame, opts.label, opts.tooltip)
	self.value = { 1, 1, 1, 1 }
end

function ColorSwatch:SetValue(color)
	self.value = { color[1], color[2], color[3], color[4] or 1 }
	self.color:SetColorTexture(self.value[1], self.value[2], self.value[3], self.value[4])
end

function ColorSwatch:GetValue()
	return self.value
end

function ColorSwatch:Commit(r, g, b, a)
	self:SetValue({ r, g, b, a })
	if self.opts.onChange then
		self.opts.onChange(self.value)
	end
end

function ColorSwatch:OpenPicker()
	local r, g, b, a = unpack(self.value)
	local hasAlpha = self.opts.hasAlpha ~= false
	-- The picker fires its callbacks while it sets itself up; ignore those.
	local ready = false
	local function OnPick()
		if not ready then
			return
		end
		local nr, ng, nb = ColorPickerFrame:GetColorRGB()
		local na = hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
		self:Commit(nr, ng, nb, na)
	end
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b,
		opacity = a,
		hasOpacity = hasAlpha,
		swatchFunc = OnPick,
		opacityFunc = OnPick,
		cancelFunc = function(previous)
			self:Commit(previous.r, previous.g, previous.b, previous.a or 1)
		end,
	})
	ready = true
end
