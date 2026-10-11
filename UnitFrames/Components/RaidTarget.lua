local _, ns = ...

-- Layout only: oUF drives the texture on live frames; previews use SetIndex.
local RaidTarget = ns.Component:Extend("RaidTarget")

RaidTarget.ANCHORS = {
	{ "TOPLEFT", "Border: top left" },
	{ "TOP", "Border: top" },
	{ "TOPRIGHT", "Border: top right" },
	{ "RIGHT", "Border: right" },
	{ "BOTTOMRIGHT", "Border: bottom right" },
	{ "BOTTOM", "Border: bottom" },
	{ "BOTTOMLEFT", "Border: bottom left" },
	{ "LEFT", "Border: left" },
	{ "PORTRAIT_BOTTOMLEFT", "Inside portrait: bottom left" },
	{ "PORTRAIT_BOTTOMRIGHT", "Inside portrait: bottom right" },
}

RaidTarget.MARKERS = {
	{ 0, "None" }, { 1, "Star" }, { 2, "Circle" }, { 3, "Diamond" },
	{ 4, "Triangle" }, { 5, "Moon" }, { 6, "Square" }, { 7, "Cross" }, { 8, "Skull" },
}

RaidTarget.schema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "anchor", type = "select", label = "Anchor", values = RaidTarget.ANCHORS, default = "TOP",
		tooltip = "Border anchors centre the icon on the edge. Portrait anchors keep it inside a bottom corner and require an enabled portrait." },
	{ key = "size", type = "range", label = "Size", min = 8, max = 64, step = 1, default = 20,
		tooltip = "Portrait icons shrink to fit if the portrait is smaller than this size." },
	{ key = "offsetX", type = "range", label = "Horizontal offset", min = -100, max = 100, step = 1, default = 0,
		tooltip = "Positive moves right; negative moves left." },
	{ key = "offsetY", type = "range", label = "Vertical offset", min = -100, max = 100, step = 1, default = 0,
		tooltip = "Positive moves up; negative moves down." },
}

function RaidTarget:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent)
	self.texture = self.frame:CreateTexture(nil, "OVERLAY")
	self.texture:SetAllPoints(self.frame)
	self.texture:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
	self.texture:Hide()
end

function RaidTarget:OnApply(cfg)
	if self.owner then
		self:Layout(self.owner, self.portrait, self.portraitWidth, self.portraitHeight)
	else
		self:SetSize(cfg.size, cfg.size)
	end
end

function RaidTarget:SetEnabled(enabled)
	self.enabled = enabled and true or false
	self.frame:SetShown(self.enabled and self.available ~= false)
end

-- Border positions attach the centre; portrait positions attach the matching
-- corner, so the whole icon is inside at zero offset. Explicit offsets may
-- move it outside. Keep this above portraits, bars and the overlay castbar.
function RaidTarget:Layout(owner, portrait, portraitWidth, portraitHeight)
	self.owner, self.portrait = owner, portrait
	self.portraitWidth, self.portraitHeight = portraitWidth, portraitHeight
	local cfg = self.resolved
	local corner = cfg.anchor:match("^PORTRAIT_(.+)$")
	self.available = not corner or portrait ~= nil
	self:ClearAllPoints()
	self.frame:SetFrameLevel(owner:GetFrameLevel() + 20)
	if corner and portrait then
		local size = math.min(cfg.size, portraitWidth, portraitHeight)
		self:SetSize(size, size)
		self:SetPoint(corner, portrait:GetFrame(), corner, cfg.offsetX, cfg.offsetY)
	elseif not corner then
		self:SetSize(cfg.size, cfg.size)
		self:SetPoint("CENTER", owner, cfg.anchor, cfg.offsetX, cfg.offsetY)
	end
	self:SetEnabled(cfg.enabled)
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
end
