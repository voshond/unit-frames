local _, CG = ...
local UF = CG.UF
local EmptyTarget = UF.Object:Extend("ClickGridEmptyTarget")
CG.EmptyTarget = EmptyTarget
EmptyTarget.TEXT = "No\nTarget"

-- Plain artwork below a member's target bar. The bar covers it while the
-- target exists; native unit watches hide the bar and reveal it otherwise.
function EmptyTarget:Init(parent, bar)
	self.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	self.frame:SetAllPoints(bar)
	self.frame:SetFrameLevel(parent:GetFrameLevel())
	self.text = self.frame:CreateFontString(nil, "OVERLAY")
	self.text:SetPoint("CENTER")
	self.text:SetJustifyH("CENTER")
	self.text:SetWordWrap(false)
end

function EmptyTarget:Apply(uf, height, shown)
	local theme = UF.Config:GetTheme()
	UF.Components.Backdrop.ApplyTo(self.frame, uf.resolved.border)
	UF.Media:ApplyFont(self.text, theme.font, math.max(6, math.min(theme.fontSize, math.floor(height / 2) - 2)), theme.fontOutline)
	self.text:SetTextColor(0.6, 0.6, 0.6, 1)
	self.text:SetText(self.TEXT)
	self.frame:SetShown(shown)
end
