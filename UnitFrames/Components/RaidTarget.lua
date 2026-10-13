local _, ns = ...

-- The raid marker: oUF's RaidTargetIndicator drives the texture on live
-- frames; previews use SetIndex.
local RaidTarget = ns.Components.StackIcon:Extend("RaidTarget")

RaidTarget.stackKey = "raidTarget"
RaidTarget.ANCHORS = ns.DecorationStack.ANCHORS

RaidTarget.MARKERS = {
	{ 0, "None" }, { 1, "Star" }, { 2, "Circle" }, { 3, "Diamond" },
	{ 4, "Triangle" }, { 5, "Moon" }, { 6, "Square" }, { 7, "Cross" }, { 8, "Skull" },
}

RaidTarget.schema = RaidTarget.BuildIconSchema()

function RaidTarget:OnCreate(parent, spec)
	ns.Components.StackIcon.OnCreate(self, parent, spec)
	self.texture:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
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
