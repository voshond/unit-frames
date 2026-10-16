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
		{ key = "swipe", type = "select", label = "Cooldown swipe", default = "normal", values = {
			{ "normal", "Progressing" }, { "reverse", "Decreasing" }, { "none", "None" },
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

-- The shared artwork options sit between the spacing and the two groups.
Auras.schema = ns.Schema.Insert({
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "spacing", type = "range", label = "Icon spacing", min = 0, max = 10, step = 1, default = 2 },
	{ key = "buffs", type = "group", label = "Buffs", schema = GroupSchema("buffs", Auras.BUFF_FILTERS, 20, "top") },
	{ key = "debuffs", type = "group", label = "Debuffs", schema = GroupSchema("debuffs", Auras.DEBUFF_FILTERS, 26, "bottom") },
}, "spacing", ns.Util.Copy(AuraIcon.schema))

function Auras:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent)
	self.frame:SetAllPoints(parent)
	self.containers = {}
end

-- Live containers are created when the part is first enabled. Adding a
-- native aura group immediately builds a batch of ten buttons (each with
-- its artwork), so parts that are never shown (aura bars and target auras
-- by default) would otherwise cost ~20 buttons each. Frames cannot be
-- destroyed: once created, containers stay. Returns true when created now.
function Auras:CreateContainers()
	if self.containers.buffs then return false end
	ns.Perf:Begin("aura containers")
	for _, kind in ipairs(KINDS) do
		local container = CreateFrame("AuraContainer", nil, self:GetContainerParent(kind), "CustomAuraContainerTemplate")
		self.containers[kind] = container
		container:AddAuraGroup(kind, kind == "buffs" and "HELPFUL" or "HARMFUL", {
			maxFrameCount = 16,
			sortMethod = AuraContainerSortMethod.ExpirationOnly,
			sortDirection = AuraContainerSortDirection.Normal,
			initializeFrame = function(button) self:InitButton(button, kind) end,
		})
		if self.unit then container:SetUnit(self.unit) end
	end
	ns.Perf:End("aura containers")
	return true
end

function Auras:GetContainerParent(kind)
	return self.frame
end

function Auras:GetArtworkConfig()
	return self.resolved
end

function Auras:GetSampleLimit(kind)
	return self.resolved[kind].max
end

-- Blocks retain their supplied fixture order. Other presentations may define
-- a plain-data ordering policy without touching live native selection.
function Auras:GetSampleOrder(kind)
	return self.previewData[kind] or {}
end

function Auras:DrawSample(button, aura)
	AuraIcon.DrawSample(button, aura, self.dispelColors)
end

function Auras:HideSample(button)
	button:Hide()
end

function Auras:InitButton(button, kind, preview)
	AuraIcon.Create(button, kind, preview, { harmful = kind == "debuffs",
		cancelBuffs = self.spec.cancelBuffs, clickThrough = self.spec.clickThrough })
	if self.resolved then
		self:StyleButton(button)
		button.ufStyleToken = self.styleToken
	end
end

-- Restyling every owned button dominates an apply (containers keep their
-- buttons, ~20 each, with or without auras), and most applies change
-- nothing about them. Buttons remember the token they were styled with; it
-- changes with anything their style reads: resolved settings, dispel
-- colours, and the font and border artwork those name (media can register
-- late).
local function StyleToken(auras, previous)
	local art = auras:GetArtworkConfig()
	local token = { resolved = auras.resolved, dispelColors = auras.dispelColors,
		font = ns.Media:Fetch("font", art.font), border = ns.Components.Backdrop.Info(art.border) }
	if previous and previous.dispelColors == token.dispelColors and previous.font == token.font
		and previous.border == token.border
		-- Shared settings (Schema.Shared) are compared once per refresh.
		and ns.Schema.Memo(ns.Util.Equals, previous.resolved, token.resolved) then
		return previous
	end
	return token
end

function Auras:StyleButton(button)
	ns.Perf:Count("auraButtonStyle")
	local group = self.resolved[button.ufKind]
	AuraIcon.Apply(button, self:GetArtworkConfig(), group.size, self.dispelColors, group.swipe)
end

-- A group's native candidate filters (nil = none).
function Auras.CandidateFilters(group)
	return group.maxDuration > 0 and { maxDuration = group.maxDuration } or nil
end

-- Native setters that do engine work even for unchanged values: candidate
-- filters re-register events and rebuild every aura; sort and group layout
-- request reassignment/relayout. Repeats are skipped per container and group.
-- (Enabled, filter string, maximum count and flow layout compare natively.)
local appliedGroups = setmetatable({}, { __mode = "k" })
local function Applied(container, kind)
	local groups = appliedGroups[container]
	if not groups then
		groups = {}
		appliedGroups[container] = groups
	end
	local applied = groups[kind]
	if not applied then
		applied = {}
		groups[kind] = applied
	end
	return applied
end

function Auras.ApplyGroupCandidates(container, kind, group)
	local applied = Applied(container, kind)
	if applied.maxDuration == group.maxDuration then return end
	applied.maxDuration = group.maxDuration
	container:SetAuraGroupCandidateFilters(kind, Auras.CandidateFilters(group))
end

function Auras.ApplyGroupSort(container, kind, method, direction)
	local applied = Applied(container, kind)
	if applied.sortMethod == method and applied.sortDirection == direction then return end
	applied.sortMethod, applied.sortDirection = method, direction
	container:SetAuraGroupSortMethod(kind, method, direction)
end

function Auras.ApplyGroupLayout(container, kind, width, height, spacing, lineSpacing)
	local applied = Applied(container, kind)
	if applied.width == width and applied.height == height and applied.spacing == spacing
		and applied.lineSpacing == lineSpacing then return end
	applied.width, applied.height, applied.spacing, applied.lineSpacing = width, height, spacing, lineSpacing
	container:SetAuraGroupLayout(kind, {
		elementWidth = width, elementHeight = height, elementSpacing = spacing, lineSpacing = lineSpacing,
	})
end

function Auras:OnApply(cfg)
	local Perf = ns.Perf
	Perf:Begin("aura groups")
	self.dispelColors = AuraIcon.DispelColors(cfg, self.dispelColors)
	if cfg.enabled then self:CreateContainers() end
	for _, kind in ipairs(self.containers.buffs and KINDS or {}) do
		local container, group = self.containers[kind], cfg[kind]
		container:SetAuraGroupEnabled(kind, group.enabled)
		container:SetAuraGroupFilterString(kind, group.filter)
		container:SetAuraGroupMaxFrameCount(kind, group.max)
		Auras.ApplyGroupCandidates(container, kind, group)
		local sort = group.sort == "default" and AuraContainerSortMethod.Default
			or group.sort == "unitDebuff" and AuraContainerSortMethod.UnitFrameDebuff or AuraContainerSortMethod.ExpirationOnly
		Auras.ApplyGroupSort(container, kind, sort, AuraContainerSortDirection.Normal)
	end
	self.styleToken = StyleToken(self, self.styleToken)
	Perf:End("aura groups")
	Perf:Begin("aura layout")
	self:Layout()
	Perf:End("aura layout")
	Perf:Begin("aura restyle")
	self:RestyleButtons()
	Perf:End("aura restyle")
end

-- Only the container's anchor refers to our ordinary host. We never read
-- secret sizes, install OnSizeChanged on it, or anchor another frame to it.
function Auras:Layout(width, height)
	self.hostWidth = width or self.hostWidth or self.frame:GetParent():GetWidth()
	self.hostHeight = height or self.hostHeight or self.frame:GetParent():GetHeight()
	for _, kind in ipairs(KINDS) do
		local group = self.resolved[kind]
		if self.containers[kind] then
			Auras.ApplyGroupLayout(self.containers[kind], kind, group.size,
				group.size + AuraIcon.TextRoom(self:GetArtworkConfig()), self.resolved.spacing, self.resolved.spacing)
		end
		local container = self.previewData and self.previewContainers[kind] or self.containers[kind]
		if not container then break end
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
local function Restyle(auras)
	for _, kind in ipairs(auras.containers.buffs and KINDS or {}) do
		local container = auras.containers[kind]
		for index = 1, container:GetAuraGroupFrameCount(kind) do
			local button = container:GetAuraGroupFrame(kind, index)
			if button.ufStyleToken ~= auras.styleToken then
				auras:StyleButton(button)
				button.ufStyleToken = auras.styleToken
			end
		end
	end
end

function Auras:RestyleButtons()
	if self.previewData then
		ns.AfterCombat:Cancel(self, "restyle")
		for _, kind in ipairs(KINDS) do
			for _, button in ipairs(self.previewContainers[kind].ufButtons) do
				self:StyleButton(button)
			end
		end
		self:RenderSamples()
		return
	end
	if InCombatLockdown() then
		ns.AfterCombat:Queue("restyle", self, Auras.RestyleButtons)
		return
	end
	local ok, reason = pcall(Restyle, self)
	if not ok then
		if not ns.AfterCombat:IsQueued(self, "restyle") then ns.Logs:Error("Auras restyle deferred", reason) end
		ns.AfterCombat:Queue("restyle", self, Auras.RestyleButtons)
	else
		ns.AfterCombat:Cancel(self, "restyle")
	end
end

function Auras:SetEnabled(enabled)
	self.enabled = enabled and true or false
	-- Enabled without enabled settings (an owner's override): configure the
	-- containers created now as an apply would have.
	if self.enabled and self:CreateContainers() then self:OnApply(self.resolved) end
	self.frame:SetShown(self.enabled)
	for _, kind in ipairs(KINDS) do
		local enabledGroup = self.enabled and self.resolved[kind].enabled
		if self.containers[kind] then
			self.containers[kind]:SetShown(enabledGroup and not self.previewData)
			self.containers[kind]:SetEnabled(enabledGroup and not self.previewData)
		end
		if self.previewContainers then
			self.previewContainers[kind]:SetShown(enabledGroup and self.previewData ~= nil)
		end
	end
end

function Auras:OnRelease()
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
	self.unit = unit
	for _, kind in ipairs(self.containers.buffs and KINDS or {}) do
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
			local container = CreateFrame("Frame", nil, self:GetContainerParent(kind))
			container.ufFlow = AnchorUtil.CreateFlowLayout()
			container.ufButtons, container.ufElements = {}, {}
			self.previewContainers[kind] = container
		end
	end
	self.previewData = values
	ns.AfterCombat:Cancel(self, "restyle")
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
	self.renderingSamples = true
	for _, kind in ipairs(KINDS) do
		local container, cfg = self.previewContainers[kind], self.resolved[kind]
		local elements = {}
		if cfg.enabled then
			for _, aura in ipairs(self:GetSampleOrder(kind)) do
				if #elements >= self:GetSampleLimit(kind) then break end
				if MatchesSampleFilter(aura, cfg.filter, cfg.maxDuration) then
					local index = #elements + 1
					local button = container.ufButtons[index]
					if not button then
						button = CreateFrame("Button", nil, container)
						self:InitButton(button, kind, true)
						container.ufButtons[index] = button
					end
					self:DrawSample(button, aura)
					button:Show()
					elements[index] = button
				end
			end
		end
		for index = #elements + 1, #container.ufButtons do self:HideSample(container.ufButtons[index]) end
		container.ufElements = elements
	end
	self:Layout()
	self.renderingSamples = nil
end
