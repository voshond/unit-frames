local _, ns = ...
local Media, Backdrop = ns.Media, ns.Components.Backdrop

-- Independent buff/debuff containers. Blizzard owns selection, sorting,
-- cooldowns, durations, counts and dispel colours, including secret auras.
-- Our ordinary root frame never depends on a container's secret dimensions.
local Auras = ns.Component:Extend("Auras")
local KINDS = { "buffs", "debuffs" }
local BORDER_PIECES = {
	"TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}
local DISPEL_TYPES = { "Magic", "Curse", "Disease", "Poison", "None" }
local dispelColorSchema = {}
for _, kind in ipairs(DISPEL_TYPES) do
	dispelColorSchema[#dispelColorSchema + 1] = {
		key = kind, type = "color", label = kind == "None" and "No dispel type" or kind,
		default = { AuraUtil.GetAuraBorderColor(kind):GetRGBA() },
	}
end

local durationFormatter
local function DurationFormatter()
	if not durationFormatter then
		durationFormatter = C_StringUtil.CreateSecondsFormatter()
		durationFormatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
		durationFormatter:SetRounding(Enum.SecondsFormatterRounding.Truncate)
		durationFormatter:SetCanRoundUpLastUnit(true)
		durationFormatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
		durationFormatter:SetMaxIntervalCurve(AuraContainerInbound.GetDefaultAuraDurationFormatter():GetMaxIntervalCurve())
		durationFormatter:SetDesiredUnitCount(1)
		durationFormatter:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.StripIgnoreLocale)
	end
	return durationFormatter
end

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

Auras.DURATION_POSITIONS = {
	{ "below", "Below the icon" }, { "CENTER", "Inside: centre" },
	{ "TOP", "Inside: top" }, { "BOTTOM", "Inside: bottom" },
}

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
	{ key = "showDuration", type = "toggle", label = "Show time left", default = true },
	{ key = "durationPosition", type = "select", label = "Time position", values = Auras.DURATION_POSITIONS, default = "below" },
	{ key = "durationSize", type = "range", label = "Time text size", min = 6, max = 32, step = 1, default = 10 },
	{ key = "showCount", type = "toggle", label = "Show stacks", default = true },
	{ key = "countSize", type = "range", label = "Stack text size", min = 6, max = 32, step = 1, default = 10 },
	{ key = "font", type = "font", label = "Font", inherit = "font" },
	{ key = "fontOutline", type = "select", label = "Font outline", values = ns.Theme.OUTLINES, default = "OUTLINE" },
	{ key = "dispelBorder", type = "toggle", label = "Colour debuff border by type", default = true,
		tooltip = "Tint the entire icon frame using Debuff border colours. Disable to use Icon frame > Border colour for every icon. Works in combat." },
	{ key = "dispelColors", type = "group", label = "Debuff border colours", schema = dispelColorSchema },
	{ key = "border", type = "group", label = "Icon frame", schema = Backdrop.schema,
		defaults = { size = 8, inset = 1, padding = 2, background = "None" } },
	{ key = "buffs", type = "group", label = "Buffs", schema = GroupSchema("buffs", Auras.BUFF_FILTERS, 20, "top") },
	{ key = "debuffs", type = "group", label = "Debuffs", schema = GroupSchema("debuffs", Auras.DEBUFF_FILTERS, 26, "bottom") },
}

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
	button.ufKind = kind
	button.ufPreview = preview and true or false
	-- The button includes the below-icon timer in its layout bounds. The
	-- artwork stays square, even when the container flows upwards.
	local iconFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
	iconFrame:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	button.ufIconFrame = iconFrame

	local icon = iconFrame:CreateTexture(nil, "ARTWORK")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.ufIcon = icon
	if not preview then button:SetIcon(icon) end

	local cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
	cooldown:SetHideCountdownNumbers(true)
	button.ufCooldown = cooldown
	if not preview then button:SetDurationCooldown(cooldown) end

	local cover = CreateFrame("Frame", nil, iconFrame)
	cover:SetAllPoints(iconFrame)
	cover:SetFrameLevel(cooldown:GetFrameLevel() + 1)

	-- The engine fills registered texts immediately, before OnApply.
	button.ufCountHolder = CreateFrame("Frame", nil, cover)
	button.ufCountHolder:SetAllPoints(iconFrame)
	button.ufCount = button.ufCountHolder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.ufCount:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
	if not preview then button:SetApplicationCount(button.ufCount, {}) end

	button.ufTime = cover:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	if not preview then button:SetDurationText(button.ufTime, { textFormatter = DurationFormatter() }) end

	-- A separate themed border lets the engine own the complete edge's
	-- colour/shown state. Hide the holder to toggle type colouring, and
	-- make the base edge transparent so no neutral border shows through.
	button.ufBorder = CreateFrame("Frame", nil, cover, "BackdropTemplate")
	button.ufBorder:SetAllPoints(iconFrame)
	button.ufDispelTextures = {}
	if preview then
		button:EnableMouse(false)
	else
		button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0)
	end
	if self.resolved then self:StyleButton(button) end
end

local function TextRoom(cfg)
	return cfg.showDuration and cfg.durationPosition == "below" and cfg.durationSize + 2 or 0
end

function Auras:StyleButton(button)
	local cfg = self.resolved
	local size = cfg[button.ufKind].size
	button:SetSize(size, size + TextRoom(cfg))
	button.ufIconFrame:SetSize(size, size)
	Backdrop.ApplyToFixedSize(button.ufIconFrame, cfg.border, size, size)
	-- Keep a drawable centre even at the smallest icon size.
	local pad = cfg.border.enabled and math.min(cfg.border.padding, (size - 2) / 2) or 0
	for _, region in ipairs({ button.ufIcon, button.ufCooldown }) do
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", button.ufIconFrame, "TOPLEFT", pad, -pad)
		region:SetPoint("BOTTOMRIGHT", button.ufIconFrame, "BOTTOMRIGHT", -pad, pad)
	end
	local font, outline = Media:Fetch("font", cfg.font), Media:Outline(cfg.fontOutline)
	for _, entry in ipairs({ { button.ufCount, cfg.countSize }, { button.ufTime, cfg.durationSize } }) do
		if not entry[1]:SetFont(font, entry[2], outline) then
			entry[1]:SetFont(Media:Fetch("font", Media.LSM:GetDefault("font")), entry[2], outline)
		end
	end
	button.ufTime:ClearAllPoints()
	if cfg.durationPosition == "below" then
		button.ufTime:SetPoint("TOP", button.ufIconFrame, "BOTTOM", 0, -1)
	else
		local y = cfg.durationPosition == "TOP" and -2 or cfg.durationPosition == "BOTTOM" and 2 or 0
		button.ufTime:SetPoint(cfg.durationPosition, button.ufIconFrame, cfg.durationPosition, 0, y)
	end
	button.ufCountHolder:SetShown(cfg.showCount)
	button.ufTime:SetShown(cfg.showDuration)
	self:StyleDispelBorder(button, size)
end

function Auras:StyleDispelBorder(button, size)
	local cfg = self.resolved
	-- Re-register after applying the backdrop: its setters reset vertex
	-- colours, and inbound options are copied by the engine, not shared.
	if not button.ufPreview then
		for _, texture in ipairs(button.ufDispelTextures) do button:RemoveDispelTypeTexture(texture) end
	end
	button.ufDispelTextures = {}
	local enabled = cfg.border.enabled and cfg.dispelBorder and button.ufKind == "debuffs"
	button.ufBorder:SetShown(enabled)
	if not enabled then
		button.ufBorder:ClearBackdrop()
		return
	end
	local border = ns.Util.Copy(cfg.border)
	border.background = "None"
	Backdrop.ApplyToFixedSize(button.ufBorder, border, size, size)
	local backdrop = button.ufBorder:GetBackdrop()
	if backdrop and backdrop.edgeFile and backdrop.edgeFile ~= "" then
		button.ufIconFrame:SetBackdropBorderColor(0, 0, 0, 0)
		for _, piece in ipairs(BORDER_PIECES) do
			local texture = button.ufBorder[piece]
			button.ufDispelTextures[#button.ufDispelTextures + 1] = texture
			if not button.ufPreview then
				button:AddDispelTypeTexture(texture, {
					style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
					showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = true,
					customDispelColorMap = self.dispelColors,
				})
			end
		end
	end
end

function Auras:OnApply(cfg)
	self.dispelColors = {}
	for _, kind in ipairs(DISPEL_TYPES) do
		self.dispelColors[kind] = CreateColor(ns.Util.UnpackColor(cfg.dispelColors[kind]))
	end
	for _, kind in ipairs(KINDS) do
		local container, group = self.containers[kind], cfg[kind]
		container:SetAuraGroupEnabled(kind, group.enabled)
		container:SetAuraGroupFilterString(kind, group.filter)
		container:SetAuraGroupMaxFrameCount(kind, group.max)
		container:SetAuraGroupLayout(kind, {
			elementWidth = group.size, elementHeight = group.size + TextRoom(cfg),
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
		local minimum = group.size + (vertical and TextRoom(self.resolved) or 0)
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

local function MatchesSampleFilter(aura, filter)
	if filter:find("PLAYER", 1, true) and aura.sourceUnit ~= "player" then return false end
	if filter:find("RAID", 1, true) and not aura.isRaid then return false end
	return true
end

function Auras:RenderSamples()
	for _, kind in ipairs(KINDS) do
		local container, cfg = self.previewContainers[kind], self.resolved[kind]
		local elements = {}
		if cfg.enabled then
			for _, aura in ipairs(self.previewData[kind] or {}) do
				if #elements >= cfg.max then break end
				if MatchesSampleFilter(aura, cfg.filter) then
					local index = #elements + 1
					local button = container.ufButtons[index]
					if not button then
						button = CreateFrame("Button", nil, container)
						self:InitButton(button, kind, true)
						container.ufButtons[index] = button
					end
					button.ufIcon:SetTexture(aura.icon)
					button.ufCount:SetText((aura.applications or 1) > 1 and aura.applications or "")
					local duration = aura.duration or 0
					local remaining = aura.remaining or duration
					button.ufTime:SetText(duration > 0 and DurationFormatter():Format(remaining) or "")
					if duration > 0 then
						button.ufCooldown:SetCooldown(GetTime() - (duration - remaining), duration)
						button.ufCooldown:Pause()
						button.ufCooldown:Show()
					else
						button.ufCooldown:Hide()
					end
					if kind == "debuffs" then
						local color = self.dispelColors[aura.dispelName or "None"] or self.dispelColors.None
						for _, texture in ipairs(button.ufDispelTextures) do
							texture:SetVertexColor(color:GetRGBA())
						end
					end
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
