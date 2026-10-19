local _, ns = ...
local Skin = ns.Skin

--[[
Virtualised list (Blizzard ScrollBox). Only visible rows exist.
opts: rowHeight, stickyHeaders, onSelect(item)
Items: { id, text, header = true|nil, sticky = true|nil, depth = 0.. (indent level) }
With stickyHeaders, the sticky header above the first visible row stays pinned
until the next header pushes it out.
]]
local ScrollList = ns.Widget:Extend("ScrollList")

function ScrollList:OnCreate(parent, opts)
	local frame = CreateFrame("Frame", nil, parent)
	self.frame = frame

	local box = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	box:SetPoint("TOPLEFT")
	box:SetPoint("BOTTOMRIGHT", -12, 0)
	local bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
	bar:SetHideIfUnscrollable(true)
	self.box = box

	self.rowHeight = opts.rowHeight or 20
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(self.rowHeight)
	view:SetElementInitializer("Button", function(row, item)
		self:InitRow(row, item)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	if opts.stickyHeaders then self:CreateStickyHeader() end
end

function ScrollList:CreateStickyHeader()
	local clip = CreateFrame("Frame", nil, self.frame)
	clip:SetAllPoints(self.box)
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(self.box:GetFrameLevel() + 10)
	local sticky = CreateFrame("Frame", nil, clip, "BackdropTemplate")
	sticky:SetHeight(self.rowHeight)
	sticky:EnableMouse(true)
	Skin.ApplyPanel(sticky, "panel")
	sticky.text = Skin.FontString(sticky, "header")
	sticky.text:SetPoint("LEFT", 4, 0)
	sticky.text:SetPoint("RIGHT", -4, 0)
	sticky.text:SetJustifyH("LEFT")
	sticky:Hide()
	self.sticky = sticky
	self.box:RegisterCallback(BaseScrollBoxEvents.OnScroll, function() self:UpdateStickyHeader() end, self)
end

function ScrollList:UpdateStickyHeader()
	local sticky, items = self.sticky, self.items or {}
	if not sticky then return end
	local offset = self.box:GetDerivedScrollOffset()
	local first = math.min(math.floor(offset / self.rowHeight) + 1, #items)
	local header
	for index = first, 1, -1 do
		if items[index].header then header = items[index]; break end
	end
	sticky:SetShown(header and header.sticky or false)
	if not sticky:IsShown() then return end
	sticky.text:SetText(header.text)
	local following = items[first + 1]
	local push = following and following.header and offset - (first - 1) * self.rowHeight or 0
	sticky:SetPoint("TOPLEFT", 0, push)
	sticky:SetPoint("TOPRIGHT", 0, push)
end

function ScrollList:InitRow(row, item)
	if not row.text then
		row.highlight = row:CreateTexture(nil, "BACKGROUND")
		row.highlight:SetAllPoints()
		row.text = Skin.FontString(row)
		row.text:SetPoint("LEFT", 6, 0)
		row.text:SetPoint("RIGHT", -4, 0)
		row.text:SetJustifyH("LEFT")
		row:SetScript("OnEnter", function(r)
			if not r.item.header and r.item.id ~= self.selected then
				r.highlight:SetColorTexture(unpack(Skin.colors.hover))
			end
		end)
		row:SetScript("OnLeave", function(r)
			self:StyleRow(r)
		end)
		row:SetScript("OnClick", function(r)
			if not r.item.header then
				self:Select(r.item.id, true)
			end
		end)
	end
	row.item = item
	row.text:SetText(item.text)
	row.text:SetFontObject(item.header and Skin.fonts.header or Skin.fonts.normal)
	row.text:SetPoint("LEFT", (item.header and 4 or 12) + (item.depth or 0) * 12, 0)
	self:StyleRow(row)
end

function ScrollList:StyleRow(row)
	if row.item.id ~= nil and row.item.id == self.selected then
		row.highlight:SetColorTexture(unpack(Skin.colors.selected))
	else
		row.highlight:SetColorTexture(0, 0, 0, 0)
	end
end

function ScrollList:SetItems(items)
	self.items = items
	self.box:SetDataProvider(CreateDataProvider(items))
	self:UpdateStickyHeader()
end

function ScrollList:Select(id, notify)
	self.selected = id
	self.box:ForEachFrame(function(row)
		self:StyleRow(row)
	end)
	if notify and self.opts.onSelect then
		for _, item in ipairs(self.items or {}) do
			if item.id == id then
				self.opts.onSelect(item)
				break
			end
		end
	end
end
