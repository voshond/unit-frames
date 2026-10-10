local _, ns = ...
local Skin = ns.Skin

--[[
Horizontal slider with a label and an editable value box.
opts: label, tooltip, min, max, step, onChange(value)
]]
local Slider = ns.Widget:Extend("Slider")

local function Round(value, step)
	return math.floor(value / step + 0.5) * step
end

function Slider:OnCreate(parent, opts)
	local frame = CreateFrame("Frame", nil, parent)
	self.frame = frame
	frame:SetHeight(36)
	self.step = opts.step or 1

	self.label = Skin.FontString(frame)
	self.label:SetPoint("TOPLEFT")
	self.label:SetJustifyH("LEFT")
	self.label:SetText(opts.label or "")
	ns.Widget.AttachTooltip(frame, opts.label, opts.tooltip)
	frame:EnableMouse(true)

	local input = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
	input:SetSize(48, 16)
	input:SetPoint("TOPRIGHT")
	input:SetAutoFocus(false)
	input:SetFontObject(Skin.fonts.normal)
	input:SetJustifyH("CENTER")
	Skin.ApplyPanel(input, "button")
	input:SetScript("OnEnterPressed", function(box)
		local value = tonumber(box:GetText())
		box:ClearFocus()
		if value then
			self:Commit(value)
		else
			self:SetValue(self.value)
		end
	end)
	input:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
		self:SetValue(self.value)
	end)
	self.input = input

	local slider = CreateFrame("Slider", nil, frame, "BackdropTemplate")
	slider:SetOrientation("HORIZONTAL")
	slider:SetHeight(8)
	slider:SetPoint("BOTTOMLEFT", 0, 4)
	slider:SetPoint("BOTTOMRIGHT", 0, 4)
	Skin.ApplyPanel(slider, "button")
	slider:SetThumbTexture(Skin.WHITE)
	local thumb = slider:GetThumbTexture()
	thumb:SetSize(8, 14)
	thumb:SetVertexColor(unpack(Skin.colors.accent))
	slider:SetMinMaxValues(opts.min or 0, opts.max or 1)
	slider:SetValueStep(self.step)
	slider:SetObeyStepOnDrag(true)
	slider:SetScript("OnValueChanged", function(_, value, userInput)
		if userInput then
			self:Commit(value)
		end
	end)
	slider:EnableMouseWheel(true)
	slider:SetScript("OnMouseWheel", function(_, delta)
		self:Commit(self.value + delta * self.step)
	end)
	self.slider = slider
	self.value = opts.min or 0
end

function Slider:Commit(value)
	local min, max = self.slider:GetMinMaxValues()
	value = ns.Util.Clamp(Round(value, self.step), min, max)
	if value == self.value then
		self:SetValue(value)
		return
	end
	self:SetValue(value)
	if self.opts.onChange then
		self.opts.onChange(value)
	end
end

function Slider:SetValue(value)
	self.value = value
	self.slider:SetValue(value)
	if self.step < 1 then
		self.input:SetText(string.format("%.2f", value))
	else
		self.input:SetText(string.format("%d", value))
	end
end

function Slider:GetValue()
	return self.value
end

function Slider:SetRange(min, max)
	self.slider:SetMinMaxValues(min, max)
end

function Slider:SetLabelColor(r, g, b)
	self.label:SetTextColor(r, g, b)
end
