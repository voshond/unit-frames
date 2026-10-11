local _, ns = ...
local AuraIcon = ns.AuraIcon

-- Independent buff/debuff containers. Blizzard owns selection, sorting,
-- cooldowns, durations, counts and dispel colours, including secret auras.
-- Our ordinary root frame never depends on a container's secret dimensions.
local Auras = ns.Component:Extend("Auras")
local KINDS = { "buffs", "debuffs" }
Auras.POSITIONS = {
	{ "top", "Top" }, { "bottom", "Bottom" },
	{ "left", "Left" }, { "right", "Right" },
}

Auras.ALIGNMENTS = {
	{ "start", "Left / top" }, { "center", "Centre" }, { "end", "Right / bottom" },
}

Auras.GROWTH = {
	{ "forward", "Right / down" }, { "reverse", "Left / up" },
}

Auras.DURATION_POSITIONS = AuraIcon.DURATION_POSITIONS

Auras.BUFF_FILTERS = {
	{ "HELPFUL", "All buffs" }, { "HELPFUL|PLAYER", "Cast by me" }, { "HELPFUL|RAID", "Raid buffs" },
}

Auras.DEBUFF_FILTERS = {
	{ "HARMFUL", "All debuffs" }, { "HARMFUL|PLAYER", "Cast by me" }, { "HARMFUL|RAID", "Dispellable by me" },
}

local function GroupSchema(label, filters, size, position)
	return {
		{ key = "enabled", type = "toggle", label = "Show " .. label, default = true },
		{ key = "filter", type = "select", label = "Which", values = filters, default = filters[1][1] },
		{ key = "max", type = "range", label = "Maximum shown", min = 1, max = 40, step = 1, default = 16 },
		{ key = "maxDuration", type = "range", label = "Maximum total duration", min = 0, max = 7200, step = 1, default = 0,
			tooltip = "0 = unrestricted. A limit excludes permanent effects and compares total duration, not time left." },
		{ key = "sort", type = "select", label = "Order", default = "expiration", values = {
			{ "expiration", "Time left" }, { "default", "Native priority" }, { "unitDebuff", "Raid debuff priority" },
		} },
		{ key = "size", type = "range", label = "Icon size", min = 10, max = 64, step = 1, default = size },
		{ key = "position", type = "select", label = "Side", values = Auras.POSITIONS, default = position },
		{ key = "alignment", type = "select", label = "Alignment", values = Auras.ALIGNMENTS, default = "start",
			tooltip = "Align the whole aura block along the selected side. Centre aligns the block, including wrapped rows." },
		{ key = "growth", type = "select", label = "Grow direction", values = Auras.GROWTH, default = "forward",
			tooltip = "Top/bottom: icons flow horizontally. Left/right: icons flow vertically. New rows or columns grow away from the frame." },
		{ key = "gap", type = "range", label = "Gap to the frame", min = 0, max = 30, step = 1, default = 2 },
		{ key = "offsetX", type = "range", label = "Offset X", min = -200, max = 200, step = 1, default = 0 },
		{ key = "offsetY", type = "range", label = "Offset Y", min = -200, max = 200, step = 1, default = 0 },
		{ key = "lineSize", type = "range", label = "Row / column length", min = 0, max = 600, step = 1, default = 0,
			tooltip = "0 follows the frame width (top/bottom) or height (left/right). Use offsets to separate buffs and debuffs placed on the same side." },
	}
end

Auras.schema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "spacing", type = "range", label = "Icon spacing", min = 0, max = 10, step = 1, default = 2 },
	{ key = "buffs", type = "group", label = "Buffs", schema = GroupSchema("buffs", Auras.BUFF_FILTERS, 20, "top") },
	{ key = "debuffs", type = "group", label = "Debuffs", schema = GroupSchema("debuffs", Auras.DEBUFF_FILTERS, 26, "bottom") },
}

-- Preserve the existing settings paths/order while sharing the artwork schema.
for i, opt in ipairs(AuraIcon.schema) do table.insert(Auras.schema, i + 2, ns.Util.Copy(opt)) end

function Auras:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent)
	self.frame:SetAllPoints(parent)
	self.containers = {}
	for _, kind in ipairs(KINDS) do
		local container = CreateFrame("AuraContainer", nil, self.frame, "CustomAuraContainerTemplate")
		self.containers[kind] = container
		container:AddAuraGroup(kind, kind == "buffs" and "HELPFUL" or "HARMFUL", {
			maxFrameCount = 16,
			sortMethod = AuraContainerSortMethod.ExpirationOnly,
			sortDirection = AuraContainerSortDirection.Normal,
			initializeFrame = function(button) self:InitButton(button, kind) end,
		})
	end
end

function Auras:InitButton(button, kind, preview)
	AuraIcon.Create(button, kind, preview, self.spec)
	if self.resolved then self:StyleButton(button) end
end

function Auras:StyleButton(button)
	AuraIcon.Apply(button, self.resolved, self.resolved[button.ufKind].size, self.dispelColors)
end

function Auras:OnApply(cfg)
	self.dispelColors = AuraIcon.DispelColors(cfg)
	for _, kind in ipairs(KINDS) do
		local container, group = self.containers[kind], cfg[kind]
		container:SetAuraGroupEnabled(kind, group.enabled)
		container:SetAuraGroupFilterString(kind, group.filter)
		container:SetAuraGroupMaxFrameCount(kind, group.max)
		container:SetAuraGroupCandidateFilters(kind, group.maxDuration > 0 and { maxDuration = group.maxDuration } or nil)
		local sort = group.sort == "default" and AuraContainerSortMethod.Default
			or group.sort == "unitDebuff" and AuraContainerSortMethod.UnitFrameDebuff or AuraContainerSortMethod.ExpirationOnly
		container:SetAuraGroupSortMethod(kind, sort, AuraContainerSortDirection.Normal)
		container:SetAuraGroupLayout(kind, {
			elementWidth = group.size, elementHeight = group.size + AuraIcon.TextRoom(cfg),
			elementSpacing = cfg.spacing, lineSpacing = cfg.spacing,
		})
	end
	self:Layout()
	self:RestyleButtons()
end

-- Only the container's anchor refers to our ordinary host. We never read
-- secret sizes, install OnSizeChanged on it, or anchor another frame to it.
function Auras:Layout(width, height)
	self.hostWidth = width or self.hostWidth or self.frame:GetParent():GetWidth()
	self.hostHeight = height or self.hostHeight or self.frame:GetParent():GetHeight()
	for _, kind in ipairs(KINDS) do
		local group = self.resolved[kind]
		local container = self.previewData and self.previewContainers[kind] or self.containers[kind]
		local side = group.position
		local vertical = side == "left" or side == "right"
		local reverse = group.growth == "reverse"
		local align = group.alignment
		local x, y = group.offsetX, group.offsetY
		local point, framePoint, horizontal, upward
		if vertical then
			local edge = align == "center" and "" or align == "end" and "BOTTOM" or "TOP"
			point = edge .. (side == "left" and "RIGHT" or "LEFT")
			framePoint = edge .. side:upper()
			x = x + (side == "left" and -group.gap or group.gap)
			horizontal, upward = side == "right", reverse
		else
			local edge = align == "center" and "" or align == "end" and "RIGHT" or "LEFT"
			point = (side == "top" and "BOTTOM" or "TOP") .. edge
			framePoint = side:upper() .. edge
			y = y + (side == "top" and group.gap or -group.gap)
			horizontal, upward = not reverse, side == "top"
		end
		container:ClearAllPoints()
		container:SetPoint(point, self.frame:GetParent(), framePoint, x, y)
		local axis = vertical and AnchorUtil.FlowLayoutAxis.Vertical or AnchorUtil.FlowLayoutAxis.Horizontal
		local anchor = (upward and "BOTTOM" or "TOP") .. (horizontal and "LEFT" or "RIGHT")
		local directionX = horizontal and AnchorUtil.FlowDirection.Right or AnchorUtil.FlowDirection.Left
		local directionY = upward and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down
		local length = group.lineSize > 0 and group.lineSize or vertical and self.hostHeight or self.hostWidth
		local minimum = group.size + (vertical and AuraIcon.TextRoom(self.resolved) or 0)
		length = math.max(length, minimum)
		if self.previewData then
			local flow = container.ufFlow
			flow:SetLayoutAxis(axis)
			flow:SetAnchorPoint(anchor)
			flow:SetGrowthDirection(directionX, directionY)
			flow:SetMaximumLineSize(length)
			flow:Apply(container, { { elements = container.ufElements,
				elementSpacing = self.resolved.spacing, lineSpacing = self.resolved.spacing } })
		else
			container:SetFlowLayoutAxis(axis)
			container:SetFlowLayoutAnchorPoint(anchor)
			container:SetFlowLayoutGrowthDirection(directionX, directionY)
			container:SetFlowLayoutMaximumLineSize(length)
		end
	end
end

-- Access to existing buttons (including enumeration) may be denied while
-- aura data is secret. Reapply at the next combat end in that case.
local pending = {}
local regenFrame = CreateFrame("Frame")
regenFrame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	for auras in pairs(pending) do
		pending[auras] = nil
		auras:RestyleButtons()
	end
end)

local function Restyle(auras)
	for _, kind in ipairs(KINDS) do
		local container = auras.containers[kind]
		for index = 1, container:GetAuraGroupFrameCount(kind) do
			auras:StyleButton(container:GetAuraGroupFrame(kind, index))
		end
	end
end

function Auras:RestyleButtons()
	if self.previewData then
		pending[self] = nil
		for _, kind in ipairs(KINDS) do
			for _, button in ipairs(self.previewContainers[kind].ufButtons) do
				self:StyleButton(button)
			end
		end
		self:RenderSamples()
		return
	end
	if InCombatLockdown() or not pcall(Restyle, self) then
		pending[self] = true
		regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		pending[self] = nil
	end
end

function Auras:SetEnabled(enabled)
	self.enabled = enabled and true or false
	self.frame:SetShown(self.enabled)
	for _, kind in ipairs(KINDS) do
		local enabledGroup = self.enabled and self.resolved[kind].enabled
		self.containers[kind]:SetShown(enabledGroup and not self.previewData)
		self.containers[kind]:SetEnabled(enabledGroup and not self.previewData)
		if self.previewContainers then
			self.previewContainers[kind]:SetShown(enabledGroup and self.previewData ~= nil)
		end
	end
end

function Auras:OnRelease()
	pending[self] = nil
	-- Disabling clears auras and unregisters dynamic events/private callbacks.
	-- SetUnit requires a string; nil is not a supported cleanup operation.
	self:SetEnabled(false)
end

function Auras:GetContainer(kind)
	return self.containers[kind]
end

function Auras:SetUnit(unit)
	if self.previewData then
		self.previewData = nil
		self:SetEnabled(self.enabled)
		self:Layout()
		self:RestyleButtons()
	end
	for _, kind in ipairs(KINDS) do
		local container = self.containers[kind]
		if container:GetUnit() ~= unit then
			container:SetUnit(unit)
		else
			container:UpdateAllAuras()
		end
	end
end

-- Sample buttons are ordinary addon widgets: no restricted aura instances,
-- global data-provider changes, or writes to engine-owned display elements.
-- Their visuals and Blizzard flow layout use the same settings as live auras.
function Auras:ShowSample(values)
	if not self.previewContainers then
		self.previewContainers = {}
		for _, kind in ipairs(KINDS) do
			local container = CreateFrame("Frame", nil, self.frame)
			container.ufFlow = AnchorUtil.CreateFlowLayout()
			container.ufButtons, container.ufElements = {}, {}
			self.previewContainers[kind] = container
		end
	end
	self.previewData = values
	pending[self] = nil
	self:SetEnabled(self.enabled)
	self:RenderSamples()
end

local function MatchesSampleFilter(aura, filter, maxDuration)
	if filter:find("PLAYER", 1, true) and aura.sourceUnit ~= "player" then return false end
	if filter:find("RAID", 1, true) and not aura.isRaid then return false end
	if maxDuration > 0 and ((aura.duration or 0) == 0 or aura.duration > maxDuration) then return false end
	return true
end

-- Shared artwork for flowing groups and companion fixed-slot samples.
function Auras:RenderSamples()
	for _, kind in ipairs(KINDS) do
		local container, cfg = self.previewContainers[kind], self.resolved[kind]
		local elements = {}
		if cfg.enabled then
			for _, aura in ipairs(self.previewData[kind] or {}) do
				if #elements >= cfg.max then break end
				if MatchesSampleFilter(aura, cfg.filter, cfg.maxDuration) then
					local index = #elements + 1
					local button = container.ufButtons[index]
					if not button then
						button = CreateFrame("Button", nil, container)
						self:InitButton(button, kind, true)
						container.ufButtons[index] = button
					end
					AuraIcon.DrawSample(button, aura, self.dispelColors)
					button:Show()
					elements[index] = button
				end
			end
		end
		for index = #elements + 1, #container.ufButtons do container.ufButtons[index]:Hide() end
		container.ufElements = elements
	end
	self:Layout()
end
