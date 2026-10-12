local _, ns = ...

--[[
Small icons placed on a unit frame's edges (raid marker, group status icons).
Icons sharing an anchor form one group that collapses when an icon is absent
and stays aligned to its anchor:

  TOP, BOTTOM, CENTER       a row centred on the point
  LEFT, RIGHT               a column centred on the point, top to bottom
  TOPLEFT, BOTTOMLEFT       a row whose first icon is centred on the corner
  TOPRIGHT, BOTTOMRIGHT     a row whose last icon is centred on the corner
  PORTRAIT_<corner>         a row inside the portrait corner, growing inward
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
	{ "PORTRAIT_BOTTOMLEFT", "Inside portrait: bottom left" },
	{ "PORTRAIT_BOTTOMRIGHT", "Inside portrait: bottom right" },
}

-- Where the group is pinned along its axis: its centre, or the centre of
-- its first or last icon.
local PIN = {
	TOP = "centre", BOTTOM = "centre", CENTER = "centre", LEFT = "centre", RIGHT = "centre",
	TOPLEFT = "first", BOTTOMLEFT = "first", TOPRIGHT = "last", BOTTOMRIGHT = "last",
}

function Stack:Init()
	self.members = {}
end

function Stack:SetContext(context)
	self.context = context
end

function Stack:Set(key, member)
	if not self.released then self.members[key] = member end
end

function Stack:Remove(key)
	self.members[key] = nil
end

local function Present(member)
	if member.present then
		local present = member.present()
		return present == nil or present
	end
	for _, widget in ipairs(member.widgets or {}) do
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
	elseif member.anchor:match("^PORTRAIT_") then
		local portrait = context.portrait
		return portrait and math.min(member.size, portrait.width, portrait.height) or nil
	end
	return member.size
end

-- Puts one item of a group: `start` is its distance from the group's
-- leading edge, `total` the group's length.
local function Place(item, context, start, total, first, last)
	local member, size, host = item.member, item.size, item.member.host
	local anchor, x, y = member.anchor, member.x or 0, member.y or 0
	host:ClearAllPoints()
	local corner = anchor:match("^PORTRAIT_(.+)$")
	if anchor == "NAME" then
		host:SetPoint("RIGHT", context.name:GetFrame(), "LEFT", -(total - start - size), 0)
	elseif corner then
		local along = corner:find("LEFT") and start or start + size - total
		host:SetPoint(corner, context.portrait.frame, corner, along + x, y)
	else
		local pin = PIN[anchor]
		pin = pin == "first" and first / 2 or pin == "last" and total - last / 2 or total / 2
		local along = start + size / 2 - pin
		if anchor == "LEFT" or anchor == "RIGHT" then
			host:SetPoint("CENTER", context.root, anchor, x, -along + y)
		else
			host:SetPoint("CENTER", context.root, anchor, along + x, y)
		end
	end
end

local function Arrange(items, context, anchor)
	table.sort(items, function(a, b)
		if a.member.order ~= b.member.order then return (a.member.order or 0) < (b.member.order or 0) end
		return a.key < b.key
	end)
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
	local context, groups = self.context, {}
	for key, member in pairs(self.members) do
		local size = Size(member, context)
		member.host:SetShown(size ~= nil)
		if size then
			member.host:SetSize(size, size)
			local item = { key = key, member = member, size = size }
			-- Absent icons keep the position they would have alone.
			Place(item, context, 0, size, size, size)
			if Present(member) then
				groups[member.anchor] = groups[member.anchor] or {}
				table.insert(groups[member.anchor], item)
			end
		end
	end
	local nameSpace = 0
	for anchor, items in pairs(groups) do
		local total = Arrange(items, context, anchor)
		if anchor == "NAME" then nameSpace = total end
	end
	local name = context and context.name
	if self.nameText and (self.nameText ~= name or nameSpace == 0) then
		self.nameText:SetLeadingSpace(0)
		self.nameText = nil
	end
	if nameSpace > 0 then
		self.nameText = name
		name:SetLeadingSpace(nameSpace)
	end
end

function Stack:Release()
	if self.released then return end
	self.released = true
	if self.nameText then
		self.nameText:SetLeadingSpace(0)
		self.nameText = nil
	end
	self.members = {}
end
