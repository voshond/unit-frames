local _, ns = ...

--[[
Vertically scrolling panel for free-form content (Blizzard ScrollBox with a
linear view). Put children on :GetContent() and call :SetContentHeight(h)
after laying them out.
]]
local ScrollPanel = ns.Widget:Extend("ScrollPanel")

function ScrollPanel:OnCreate(parent)
	local frame = CreateFrame("Frame", nil, parent)
	self.frame = frame

	local box = CreateFrame("Frame", nil, frame, "WowScrollBox")
	box:SetPoint("TOPLEFT")
	box:SetPoint("BOTTOMRIGHT", -12, 0)
	local bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
	bar:SetHideIfUnscrollable(true)
	self.box = box

	-- Must exist (and be flagged) before the view is initialised.
	local content = CreateFrame("Frame", nil, box)
	content.scrollable = true
	content:SetSize(1, 1)
	self.content = content

	local view = CreateScrollBoxLinearView()
	view:SetPanExtent(30)
	ScrollUtil.InitScrollBoxWithScrollBar(box, bar, view)

	-- Hook, not SetScript: the ScrollBox has its own OnSizeChanged handler.
	box:HookScript("OnSizeChanged", function(_, width)
		content:SetWidth(width)
	end)
end

function ScrollPanel:GetContent()
	return self.content
end

function ScrollPanel:GetScrollPercentage()
	return self.box:GetScrollPercentage()
end

function ScrollPanel:SetScrollPercentage(value)
	self.box:SetScrollPercentage(value, ScrollBoxConstants.NoScrollInterpolation)
end

function ScrollPanel:SetContentHeight(height)
	self.content:SetWidth(self.box:GetWidth())
	self.content:SetHeight(math.max(height, 1))
	self.box:FullUpdate(ScrollBoxConstants.UpdateImmediately)
end
