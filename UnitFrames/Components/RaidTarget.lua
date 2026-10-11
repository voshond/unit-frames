local _, ns = ...

-- Layout only: oUF drives the texture on live frames; previews use SetIndex.
local RaidTarget = ns.Component:Extend("RaidTarget")

RaidTarget.ANCHORS = ns.DecorationStack.ANCHORS

RaidTarget.MARKERS = {
	{ 0, "None" }, { 1, "Star" }, { 2, "Circle" }, { 3, "Diamond" },
	{ 4, "Triangle" }, { 5, "Moon" }, { 6, "Square" }, { 7, "Cross" }, { 8, "Skull" },
}

RaidTarget.schema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "anchor", type = "select", label = "Anchor", values = RaidTarget.ANCHORS, default = "TOP",
		tooltip = "Icons sharing a position line up as one group: edges and the centre keep the group centred, border corners grow inward from the corner. Portrait anchors keep it inside a bottom corner and require an enabled portrait." },
	{ key = "order", type = "range", label = "Order", min = 1, max = 10, step = 1, default = 1,
		tooltip = "Icons sharing a position run left to right (top to bottom on the sides) by order. Absent icons leave no gap." },
	{ key = "gap", type = "range", label = "Gap to next icon", min = 0, max = 20, step = 1, default = 2 },
	{ key = "size", type = "range", label = "Size", min = 8, max = 64, step = 1, default = 20,
		tooltip = "Portrait icons shrink to fit if the portrait is smaller than this size." },
	{ key = "offsetX", type = "range", label = "Horizontal offset", min = -100, max = 100, step = 1, default = 0,
		tooltip = "Positive moves right; negative moves left. Moves only this icon, not the rest of its group." },
	{ key = "offsetY", type = "range", label = "Vertical offset", min = -100, max = 100, step = 1, default = 0,
		tooltip = "Positive moves up; negative moves down. Moves only this icon, not the rest of its group." },
}

function RaidTarget:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent)
	self.texture = self.frame:CreateTexture(nil, "OVERLAY")
	self.texture:SetAllPoints(self.frame)
	self.texture:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
	self.texture:Hide()
	-- oUF calls this after showing or hiding the marker, also in combat.
	self.texture.PostUpdate = function() self:Reflow() end
end

function RaidTarget:OnApply(cfg)
	if self.layoutContext then
		self:Layout(self.layoutContext)
	else
		self:SetSize(cfg.size, cfg.size)
	end
end

function RaidTarget:SetEnabled(enabled)
	self.enabled = enabled and true or false
	local stack = self.layoutContext and self.layoutContext.decorations
	if not stack then
		self.frame:SetShown(self.enabled)
		return
	end
	local cfg = self.resolved
	stack:Set("raidTarget", { host = self.frame, widgets = { self.texture }, enabled = self.enabled,
		anchor = cfg.anchor, size = cfg.size, order = cfg.order, gap = cfg.gap, x = cfg.offsetX, y = cfg.offsetY })
	stack:Reflow()
end

-- Joins the frame's decoration stack. Keep this above portraits, bars and
-- the overlay castbar.
function RaidTarget:Layout(context)
	self.layoutContext = context
	self.frame:SetFrameLevel(context.root:GetFrameLevel() + 20)
	self:SetEnabled(self.resolved.enabled)
end

function RaidTarget:Reflow()
	local stack = self.layoutContext and self.layoutContext.decorations
	if stack and not self.released then stack:Reflow() end
end

function RaidTarget:OnRelease()
	local stack = self.layoutContext and self.layoutContext.decorations
	if stack then stack:Remove("raidTarget") end
end

function RaidTarget:GetWidget()
	return self.texture
end

function RaidTarget:SetIndex(index)
	if index and index > 0 then
		SetRaidTargetIconTexture(self.texture, index)
		self.texture:Show()
	else
		self.texture:Hide()
	end
	self:Reflow()
end
