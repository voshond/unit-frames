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
	self.presenter = UF.Components.Text:New(self.frame, {}, { host = self.frame })
	self.text = self.presenter:GetFrame()
end

function EmptyTarget:Apply(uf, height, shown)
	if not self.presenter.componentOwner then uf:Own(self.presenter) end
	UF.Components.Backdrop.ApplyTo(self.frame, uf.resolved.border)
	local cfg = CG.Config.styles.target:Resolved().emptyText
	local presentation = UF.Util.Copy(cfg)
	local lines = select(2, cfg.label:gsub("\n", "")) + 1
	if cfg.fit then
		local extent = cfg.rotation == 0 and height or uf.layout.width
		presentation.size = math.max(6, math.min(cfg.size, math.floor(extent / lines) - 2))
	end
	self.presenter:SetLineCount(lines)
	self.presenter:SetHostSize(uf.layout.width, height)
	self.presenter:Apply(presentation)
	self.presenter:SetText(cfg.label)
	self.frame:SetFrameLevel(self.frame:GetParent():GetFrameLevel())
	self.frame:SetShown(shown)
end

function EmptyTarget:Release()
	self.presenter:Release()
	self.frame:Hide()
end
