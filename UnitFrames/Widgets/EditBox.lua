local _, ns = ...
local Skin = ns.Skin

--[[
Single-line text input with a label. Commits on Enter or when focus is lost.
opts: label, tooltip, onChange(text)
]]
local EditBox = ns.Widget:Extend("EditBox")

function EditBox:OnCreate(parent, opts)
	local frame = CreateFrame("Frame", nil, parent)
	self.frame = frame
	frame:SetHeight(38)

	self:CreateLabel(frame, opts.label):SetPoint("TOPLEFT")

	local input = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
	input:SetHeight(20)
	input:SetPoint("BOTTOMLEFT")
	input:SetPoint("BOTTOMRIGHT")
	input:SetAutoFocus(false)
	input:SetFontObject(Skin.fonts.normal)
	input:SetTextInsets(6, 6, 0, 0)
	Skin.ApplyPanel(input, "button")
	local function Commit(box)
		box:ClearFocus()
		local text = box:GetText()
		if text ~= self.value then
			self.value = text
			if opts.onChange then
				opts.onChange(text)
			end
		end
	end
	input:SetScript("OnEnterPressed", Commit)
	input:SetScript("OnEditFocusLost", Commit)
	input:SetScript("OnEscapePressed", function(box)
		box:SetText(self.value or "")
		box:ClearFocus()
	end)
	self.input = input
	ns.Widget.AttachTooltip(frame, opts.label, opts.tooltip)
	frame:EnableMouse(true)
end

function EditBox:SetValue(text)
	self.value = text or ""
	self.input:SetText(self.value)
end

function EditBox:GetValue()
	return self.value
end

function EditBox:OnRelease()
	self.input:SetScript("OnEnterPressed", nil)
	self.input:SetScript("OnEditFocusLost", nil)
	self.input:SetScript("OnEscapePressed", nil)
	self.input:ClearFocus()
end
