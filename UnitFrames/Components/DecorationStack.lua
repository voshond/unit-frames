local _, ns = ...

--[[
Small icons placed on a unit frame's edges (raid marker, group status icons).
Icons sharing an anchor form one group that collapses when an icon is absent
and stays aligned to its anchor:

  TOP, BOTTOM, CENTER       a row centred on the point
  LEFT, RIGHT               a column centred on the point, top to bottom
  TOPLEFT, BOTTOMLEFT       a row whose first icon is centred on the corner
  TOPRIGHT, BOTTOMRIGHT     a row whose last icon is centred on the corner
  PORTRAIT_<position>       the same nine positions inside the portrait: corners
                            grow inward from the corner, top, bottom and the
                            centre keep a row centred, left and right a column
  NAME                      a row before the leading name text, which makes room

Members run in `order` (left to right, top to bottom); `gap` follows each
member. Offsets nudge one icon without moving the others. Only configured
sizes are used: native icon dimensions can be opaque.

A member is present while one of its widgets is shown. oUF and samples show
and hide them in plain Lua; a secret shown state keeps the slot reserved.
A `present` function may decide instead (nil = unknown: keep the slot).
Absent members keep their single-icon position, so art shown before the
next Reflow is still placed on its anchor.

  stack:Set(key, member)   { host, enabled, anchor, size, gap, order, x, y, widgets, present }
  stack:Remove(key)
  stack:SetContext(ctx)    the owning UnitFrame's layout context
  stack:Reflow()           after visibility changes; moves only plain addon hosts
]]
local Stack = ns.Object:Extend("DecorationStack")
ns.DecorationStack = Stack

Stack.ANCHORS = {
	{ "TOPLEFT", "Border: top left" },
	{ "TOP", "Border: top" },
	{ "TOPRIGHT", "Border: top right" },
	{ "RIGHT", "Border: right" },
	{ "BOTTOMRIGHT", "Border: bottom right" },
	{ "BOTTOM", "Border: bottom" },
	{ "BOTTOMLEFT", "Border: bottom left" },
	{ "LEFT", "Border: left" },
	{ "CENTER", "Frame centre" },
	{ "PORTRAIT_TOPLEFT", "Inside portrait: top left" },
	{ "PORTRAIT_TOP", "Inside portrait: top" },
	{ "PORTRAIT_TOPRIGHT", "Inside portrait: top right" },
	{ "PORTRAIT_RIGHT", "Inside portrait: right" },
	{ "PORTRAIT_BOTTOMRIGHT", "Inside portrait: bottom right" },
	{ "PORTRAIT_BOTTOM", "Inside portrait: bottom" },
	{ "PORTRAIT_BOTTOMLEFT", "Inside portrait: bottom left" },
	{ "PORTRAIT_LEFT", "Inside portrait: left" },
	{ "PORTRAIT_CENTER", "Inside portrait: centre" },
}

-- How each anchor lays out its group. `point` is the anchor point, `axis`
-- the stacking direction and `pin` the part of the group held there: the
-- centre of the group, or of its first or last icon. Border icons are
-- centred on their point; portrait icons sit inside it, so their corner
-- pins hold an edge of the group instead.
local LAYOUT = {}
for point, layout in pairs({
	TOPLEFT = { axis = "x", pin = "first" }, TOP = { axis = "x", pin = "centre" },
	TOPRIGHT = { axis = "x", pin = "last" }, RIGHT = { axis = "y", pin = "centre" },
	BOTTOMRIGHT = { axis = "x", pin = "last" }, BOTTOM = { axis = "x", pin = "centre" },
	BOTTOMLEFT = { axis = "x", pin = "first" }, LEFT = { axis = "y", pin = "centre" },
	CENTER = { axis = "x", pin = "centre" },
}) do
	LAYOUT[point] = { point = point, axis = layout.axis, pin = layout.pin }
	LAYOUT["PORTRAIT_" .. point] = { point = point, axis = layout.axis, pin = layout.pin, portrait = true }
end

function Stack:Init()
	self.members = {}
	self.items, self.groups, self.ordered = {}, {}, {}
end

function Stack:SetContext(context)
	self.context = context
end

function Stack:Set(key, member)
	if not self.released then self.members[key] = member end
end

function Stack:Remove(key)
	self.members[key] = nil
	self.items[key] = nil
	self.orderDirty = true
end

local function Present(member)
	if member.present then
		local present = member.present()
		return issecretvalue(present) or present == nil or present
	end
	for _, widget in ipairs(member.widgets or member) do
		local shown = widget:IsShown()
		if issecretvalue(shown) or shown then return true end
	end
	return false
end

-- The member's icon size here, or nil where it cannot be placed.
local function Size(member, context)
	if not member.enabled or not context then return nil end
	if member.anchor == "NAME" then
		return context.name and member.size or nil
	end
	local layout = LAYOUT[member.anchor]
	if layout and layout.portrait then
		local portrait = context.portrait
		return portrait and math.min(member.size, portrait.width, portrait.height) or nil
	end
	return layout and member.size or nil
end

-- Puts one item of a group: `start` is its distance from the group's
-- leading edge, `total` the group's length.
local function Place(item, context, start, total, first, last)
	local member, size, host = item.member, item.size, item.member.host
	local anchor, x, y = member.anchor, member.x or 0, member.y or 0
	local point, relative, relativePoint
	if anchor == "NAME" then
		point, relative, relativePoint, x, y = "RIGHT", context.name:GetFrame(), "LEFT", -(total - start - size), 0
	else
		local layout = LAYOUT[anchor]
		local along
		if layout.portrait then
			-- Offset of the icon's own point from the group's matching point.
			along = layout.pin == "first" and start or layout.pin == "last" and start + size - total
				or start + (size - total) / 2
		else
			local pin = layout.pin == "first" and first / 2 or layout.pin == "last" and total - last / 2 or total / 2
			along = start + size / 2 - pin
		end
		point = layout.portrait and layout.point or "CENTER"
		relative = layout.portrait and context.portrait.frame or context.root
		relativePoint = layout.point
		if layout.axis == "y" then y = -along + y else x = along + x end
	end
	-- Only addon-computed geometry is compared, never native bounds.
	if item.host ~= host or item.point ~= point or item.relative ~= relative
		or item.relativePoint ~= relativePoint or item.x ~= x or item.y ~= y then
		host:ClearAllPoints()
		host:SetPoint(point, relative, relativePoint, x, y)
		item.host, item.point, item.relative, item.relativePoint, item.x, item.y = host, point, relative, relativePoint, x, y
	end
end

local function Order(a, b)
	if a.member.order ~= b.member.order then return (a.member.order or 0) < (b.member.order or 0) end
	return a.key < b.key
end

local function Arrange(items, context, anchor)
	local position = 0
	for _, item in ipairs(items) do
		item.start = position
		position = position + item.size + (item.member.gap or 0)
	end
	-- The name keeps the gap after the last icon; edges drop it.
	local total = anchor == "NAME" and position or position - (items[#items].member.gap or 0)
	for _, item in ipairs(items) do
		Place(item, context, item.start, total, items[1].size, items[#items].size)
	end
	return total
end

function Stack:Reflow()
	if self.released then return end
	ns.Perf:Count("decorationReflow")
	local context, groups = self.context, self.groups
	for key, member in pairs(self.members) do
		local item = self.items[key]
		if not item then
			item = { key = key }
			self.items[key], self.orderDirty = item, true
		end
		if item.member ~= member or item.order ~= member.order then self.orderDirty = true end
		item.order = member.order
		if item.member ~= member or item.appliedHost ~= member.host then
			item.member, item.host, item.shown, item.appliedSize = member, nil, nil, nil
			item.appliedHost = member.host
		end
	end
	if self.orderDirty then
		for i = #self.ordered, 1, -1 do self.ordered[i] = nil end
		for _, item in pairs(self.items) do self.ordered[#self.ordered + 1] = item end
		table.sort(self.ordered, Order)
		self.orderDirty = nil
	end
	for _, items in pairs(groups) do
		for i = #items, 1, -1 do items[i] = nil end
	end
	for _, item in ipairs(self.ordered) do
		local member = item.member
		local size = Size(member, context)
		local shown = size ~= nil
		if item.shown ~= shown then member.host:SetShown(shown); item.shown = shown end
		if size then
			if item.appliedSize ~= size then member.host:SetSize(size, size); item.appliedSize = size end
			item.size = size
			if Present(member) then
				groups[member.anchor] = groups[member.anchor] or {}
				table.insert(groups[member.anchor], item)
			else
				-- Absent icons keep the position they would have alone.
				Place(item, context, 0, size, size, size)
			end
		end
	end
	local nameSpace = 0
	for anchor, items in pairs(groups) do
		if #items > 0 then
			local total = Arrange(items, context, anchor)
			if anchor == "NAME" then nameSpace = total end
		end
	end
	local name = context and context.name
	if self.nameText and (self.nameText ~= name or nameSpace == 0) then
		self.nameText:SetLeadingSpace(0)
		self.nameText = nil
	end
	if nameSpace > 0 then
		self.nameText = name
		if self.nameSpace ~= nameSpace or self.appliedName ~= name then name:SetLeadingSpace(nameSpace) end
	end
	self.nameSpace, self.appliedName = nameSpace, name
end

function Stack:Release()
	if self.released then return end
	self.released = true
	if self.nameText then
		self.nameText:SetLeadingSpace(0)
		self.nameText = nil
	end
	self.members = {}
	self.items, self.groups, self.ordered, self.context = {}, {}, {}, nil
end
