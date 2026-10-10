local _, ns = ...
local Skin = ns.Skin

--[[
Flat push button.
opts: text, width, height, onClick(button), tooltip
]]
local Button = ns.Widget:Extend("Button")

function Button:OnCreate(parent, opts)
	local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
	self.frame = frame
	Skin.ApplyPanel(frame, "button")

	self.text = Skin.FontString(frame)
	self.text:SetPoint("CENTER")
	self:SetText(opts.text or "")
	frame:SetSize(opts.width or math.max(60, self.text:GetStringWidth() + 20), opts.height or 22)

	frame:SetScript("OnEnter", function()
		if not self.selected then
			frame:SetBackdropColor(unpack(Skin.colors.buttonHover))
		end
	end)
	frame:SetScript("OnLeave", function()
		self:UpdateColors()
	end)
	frame:SetScript("OnClick", function()
		if opts.onClick then
			opts.onClick(self)
		end
	end)
	ns.Widget.AttachTooltip(frame, opts.text, opts.tooltip)
end

function Button:SetText(text)
	self.text:SetText(text)
end

-- Selected buttons are highlighted (tabs, toggle groups).
function Button:SetSelected(selected)
	self.selected = selected
	self:UpdateColors()
end

function Button:UpdateColors()
	if self.selected then
		self.frame:SetBackdropColor(unpack(Skin.colors.selected))
		self.frame:SetBackdropBorderColor(unpack(Skin.colors.accent))
	else
		self.frame:SetBackdropColor(unpack(Skin.colors.button))
		self.frame:SetBackdropBorderColor(unpack(Skin.colors.border))
	end
end

function Button:SetEnabled(enabled)
	self.frame:SetEnabled(enabled)
	self.text:SetTextColor(unpack(enabled and Skin.colors.text or Skin.colors.textDim))
end
