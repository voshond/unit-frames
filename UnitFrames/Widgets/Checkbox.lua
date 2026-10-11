local _, ns = ...
local Skin = ns.Skin

--[[
Checkbox with a label.
opts: label, tooltip, onChange(value)
]]
local Checkbox = ns.Widget:Extend("Checkbox")

function Checkbox:OnCreate(parent, opts)
	local frame = CreateFrame("Button", nil, parent)
	self.frame = frame
	frame:SetHeight(20)

	local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	box:SetSize(14, 14)
	box:SetPoint("LEFT", 0, 0)
	Skin.ApplyPanel(box, "button")
	self.box = box

	self.check = box:CreateTexture(nil, "OVERLAY")
	self.check:SetTexture([[Interface\Buttons\UI-CheckBox-Check]])
	self.check:SetPoint("CENTER")
	self.check:SetSize(18, 18)

	self:CreateLabel(frame, opts.label):SetPoint("LEFT", box, "RIGHT", 6, 0)
	self.label:SetPoint("RIGHT")

	frame:SetScript("OnClick", function()
		self:SetValue(not self.value)
		if opts.onChange then
			opts.onChange(self.value)
		end
	end)
	frame:SetScript("OnEnter", function()
		box:SetBackdropBorderColor(unpack(Skin.colors.accent))
	end)
	frame:SetScript("OnLeave", function()
		box:SetBackdropBorderColor(unpack(Skin.colors.border))
	end)
	ns.Widget.AttachTooltip(frame, opts.label, opts.tooltip)
	self:SetValue(false)
end

function Checkbox:SetValue(value)
	self.value = value and true or false
	self.check:SetShown(self.value)
end

function Checkbox:GetValue()
	return self.value
end
