local _, ns = ...
local Auras = ns.Components.Auras
local AuraBar = Auras:Extend("AuraBar")
local KINDS = { "buffs", "debuffs" }
local Backdrop = ns.Components.Backdrop
local LAYOUT_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"

-- A separate structural row, using the same native aura presentation as blocks.
-- Only horizontal capacity matters: square artwork may exceed the row height
-- and is centred behind fixed, addon-owned clipping viewports.
--
-- spec.collapsible: the row can collapse while it shows no icon, lending its
-- space to a neighbouring bar (UnitFrame). Whether any live icon is shown is
-- never read in Lua: a hidden native "presence" container sizes a clipping
-- viewport through anchors, and the neighbour anchors to that viewport.
-- Everything depending on it opts into the forbidden layout aspect.
local schema = ns.Schema.Without(ns.Util.Copy(Auras.schema), { buffs = true, debuffs = true })
schema = ns.Schema.Override(schema, "enabled", { default = false })
schema = ns.Schema.Override(schema, "durationPosition", { default = "BOTTOM",
	tooltip = "Below the icon resolves to inside-bottom for this row. Text remains inside the visible strip.",
	hint = "Below the icon is shown inside-bottom in this row; the saved choice is retained." })
AuraBar.schema = ns.Schema.Insert(schema, "enabled", {
	{ key = "position", type = "select", label = "Row position", default = "bottom",
		values = { { "top", "Top" }, { "bottom", "Bottom" } } },
	{ key = "height", type = "range", label = "Row height", min = 2, max = 100, step = 1, default = 18,
		tooltip = "Crops centred square icons vertically; icon width controls their size. This row can coexist with Buffs & debuffs.",
		hint = "Square icons are centred and cropped by height. A section too narrow for one icon stays empty. Icons do not receive mouse input." },
	{ key = "padding", type = "range", label = "Inner padding", min = 0, max = 20, step = 1, default = 0 },
	{ key = "fadeIn", type = "toggle", label = "Fade in new auras", default = true,
		tooltip = "Native assignment fades the artwork on arrival and replacement, without moving click regions. Static samples do not animate." },
	{ key = "fadeDuration", type = "range", label = "Fade duration", min = 0.05, max = 0.5, step = 0.05, default = 0.15 },
	{ key = "sectionGap", type = "range", label = "Gap between categories", min = 0, max = 30, step = 1, default = 2 },
	{ key = "buffWidthPercent", type = "range", label = "Buff share of width (%)", min = 0, max = 100, step = 1, default = 50,
		tooltip = "Enabled categories keep their share even when empty. Disable a category to give the other the full width." },
	{ key = "rowBackdrop", type = "group", label = "Row background", schema = Backdrop.artSchema,
		defaults = { enabled = false, border = "None", inset = 0 } },
})
for _, kind in ipairs(KINDS) do
	local source = ns.Schema.Find(Auras.schema, kind)
	local group = ns.Schema.Without(ns.Util.Copy(source.schema), {
		position = true, alignment = true, growth = true, gap = true, offsetX = true, offsetY = true, lineSize = true,
	})
	group = ns.Schema.Override(group, "size", { label = "Icon width", default = 32,
		tooltip = "Artwork stays square and centred vertically. Icons wider than their section show none." })
	group = ns.Schema.Override(group, "sort", {
		hint = "Time samples sort by remaining time, permanent last. Native and raid priority previews are illustrative; Blizzard selects live auras." })
	local sides = { { "left", "Left" }, { "right", "Right" } }
	if kind == "debuffs" then table.insert(sides, 1, { "opposite", "Opposite buffs" }) end
	group = ns.Schema.Insert(group, "size", {
		{ key = "entrySide", type = "select", label = "Fill from", default = kind == "buffs" and "left" or "opposite",
			values = sides,
			tooltip = kind == "buffs" and "Chooses the buff section's side and fill direction. Debuffs occupy the opposite section."
				or "Chooses the fill direction within the debuff section. Opposite buffs preserves inward filling when the buff side changes." },
	})
	AuraBar.schema[#AuraBar.schema + 1] = { key = kind, type = "group", label = source.label, schema = group }
end

-- Offered where the owner can lend the row's space to its health bar.
function AuraBar.BuildSchema(spec)
	local out = ns.Schema.Concat(AuraBar.schema)
	if not (spec and spec.collapsible) then return out end
	return ns.Schema.Insert(out, "position", {
		{ key = "collapse", type = "toggle", label = "Collapse into health when empty", default = true,
			tooltip = "While neither category shows an icon, the row and the gap to the health bar disappear and health grows into their space. The row then sits directly above or below the health bar. Health texts keep their place." },
	})
end

-- hostWidth is the known row width, supplied by UnitFrameLayout.
function AuraBar.Geometry(cfg, hostWidth)
	local width = math.max(0, hostWidth - 2 * cfg.padding)
	local height = math.max(0, cfg.height - 2 * cfg.padding)
	local both = cfg.buffs.enabled and cfg.debuffs.enabled
	local gap = both and math.min(width, cfg.sectionGap) or 0
	local available = width - gap
	local buffWidth = cfg.buffs.enabled and (both and available * cfg.buffWidthPercent / 100 or available) or 0
	local widths = { buffs = buffWidth, debuffs = cfg.debuffs.enabled and available - buffWidth or 0 }
	local buffsLeft = cfg.buffs.entrySide == "left"
	local leftWidth = buffsLeft and widths.buffs or widths.debuffs
	local result = {}
	for _, kind in ipairs(KINDS) do
		local group, sectionWidth = cfg[kind], widths[kind]
		local sectionLeft = kind == "buffs" and buffsLeft or kind == "debuffs" and not buffsLeft
		local left = sectionLeft
		if kind == "debuffs" and group.entrySide ~= "opposite" then left = group.entrySide == "left" end
		local columns = math.max(0, math.floor((sectionWidth + cfg.spacing) / (group.size + cfg.spacing)))
		result[kind] = { width = sectionWidth, height = height, left = left,
			x = cfg.padding + (sectionLeft and 0 or leftWidth + gap),
			capacity = group.enabled and height > 0 and math.min(group.max, columns) or 0,
			lineSize = columns > 0 and columns * group.size + (columns - 1) * cfg.spacing or group.size }
	end
	return result
end

-- Where the row draws: the row frame, or for collapsible rows a clipping
-- viewport that native anchors size (always created with the aspect).
function AuraBar:GetViewport()
	if not self.viewport then
		if self.spec.collapsible then
			self.viewport = CreateFrame("Frame", nil, self.frame, LAYOUT_TEMPLATE)
			self.viewport:SetClipsChildren(true)
		else
			self.viewport = self.frame
		end
	end
	return self.viewport
end

function AuraBar:GetContainerParent(kind)
	self.sections = self.sections or {}
	if not self.sections[kind] then
		local section = CreateFrame("Frame", nil, self:GetViewport())
		section:SetClipsChildren(true)
		self.sections[kind] = section
	end
	return self.sections[kind]
end

function AuraBar:GetArtworkConfig()
	return self.artConfig
end

function AuraBar:OnCreate(parent, spec)
	Auras.OnCreate(self, parent)
	self.frame:ClearAllPoints()
	local viewport = self:GetViewport()
	self.background = CreateFrame("Frame", nil, viewport, "BackdropTemplate")
	self.background:SetFrameLevel(viewport:GetFrameLevel())
	self.background:SetAllPoints(self.frame)
end

-- Created with the live containers, when the row is first enabled.
function AuraBar:CreateContainers()
	if not Auras.CreateContainers(self) then return false end
	if self.spec.collapsible then
		ns.Perf:Begin("aura presence")
		-- At most one artless button per category, mirroring the row's
		-- filters and capacity: its flow extent is one cell exactly while
		-- the row would show any icon, else Blizzard's 1-unit minimum.
		local presence = CreateFrame("AuraContainer", nil, self.frame, "CustomAuraContainerTemplate")
		for _, kind in ipairs(KINDS) do
			presence:AddAuraGroup(kind, kind == "buffs" and "HELPFUL" or "HARMFUL", {
				maxFrameCount = 1,
				sortMethod = AuraContainerSortMethod.ExpirationOnly,
				sortDirection = AuraContainerSortDirection.Normal,
				initializeFrame = function(button) button:EnableMouse(false) end,
			})
		end
		presence:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
		presence:SetEnabled(false)
		if self.unit then presence:SetUnit(self.unit) end
		self.presence = presence
		ns.Perf:End("aura presence")
	end
	return true
end

local function ArtworkConfig(cfg)
	ns.Perf:Count("auraArtConfigBuild")
	local art = ns.Util.Copy(cfg)
	if cfg.durationPosition == "below" then art.durationPosition = "BOTTOM" end
	return art
end

function AuraBar:OnApply(cfg)
	ns.Perf:Begin("aura art config")
	self.artConfig = ns.Schema.Memo(ArtworkConfig, cfg)
	self.dispelColors = ns.AuraIcon.DispelColors(cfg, self.dispelColors)
	if cfg.enabled then self:CreateContainers() end
	if self.presence then
		for _, kind in ipairs(KINDS) do
			self.presence:SetAuraGroupFilterString(kind, cfg[kind].filter)
			Auras.ApplyGroupCandidates(self.presence, kind, cfg[kind])
		end
	end
	ns.Perf:End("aura art config")
	Auras.OnApply(self, cfg)
end

function AuraBar:InitButton(button, kind, preview)
	button.ufEntryAnimation, button.ufEntryRegistered, button.ufSampleIcon = false, false, false
	Auras.InitButton(self, button, kind, preview)
	-- Clipping of hit regions is not proven on the client. No mouse input,
	-- tooltips or buff cancellation in this strip, even outside combat.
	button:EnableMouse(false)
	local animation = button.ufIconFrame:CreateAnimationGroup()
	local alpha = animation:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.15)
	button.ufEntryAnimation, button.ufEntryAlpha = animation, alpha
	if self.resolved then self:ConfigureAnimation(button) end
end

function AuraBar:ConfigureAnimation(button)
	local animation = button.ufEntryAnimation
	if not animation then return end
	animation:Stop()
	button.ufEntryAlpha:SetDuration(self.resolved.fadeDuration)
	if not button.ufPreview then
		if button.ufEntryRegistered then button:RemoveAuraAssignedAnimation(animation) end
		button.ufEntryRegistered = self.resolved.fadeIn
		if button.ufEntryRegistered then button:AddAuraAssignedAnimation(animation) end
	end
end

function AuraBar:StyleButton(button)
	Auras.StyleButton(self, button)
	local size = self.resolved[button.ufKind].size
	local height = math.max(0, self.resolved.height - 2 * self.resolved.padding)
	button:SetHeight(height)
	button.ufIconFrame:ClearAllPoints()
	button.ufIconFrame:SetPoint("TOPLEFT", button, "TOPLEFT", 0, (size - height) / 2)
	-- Text belongs to the visible strip, while texture/cooldown/border stay square.
	button.ufCount:ClearAllPoints()
	button.ufCount:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
	button.ufTime:ClearAllPoints()
	local position = self.artConfig.durationPosition
	button.ufTime:SetPoint(position, button, position, 0, position == "TOP" and -2 or position == "BOTTOM" and 2 or 0)
	self:ConfigureAnimation(button)
end

function AuraBar:DrawSample(button, aura)
	Auras.DrawSample(self, button, aura)
	-- Plain sample identity only. Animated previews fade when a slot changes;
	-- static previews stay fully visible, including frozen timers.
	if self.enabled and self.previewData.animateAuras and self.resolved.fadeIn and button.ufSampleIcon ~= aura.icon then
		button.ufEntryAnimation:Stop()
		button.ufEntryAnimation:Play()
	elseif not self.enabled or not self.previewData.animateAuras or not self.resolved.fadeIn then
		button.ufEntryAnimation:Stop()
	end
	button.ufSampleIcon = aura.icon
end

function AuraBar:HideSample(button)
	button.ufEntryAnimation:Stop()
	button.ufSampleIcon = nil
	button:Hide()
end

function AuraBar:SetEnabled(enabled)
	Auras.SetEnabled(self, enabled)
	self:UpdatePresence()
	if self.previewContainers then
		for _, kind in ipairs(KINDS) do
			for _, button in ipairs(self.previewContainers[kind].ufButtons) do
				if not self.enabled or not self.previewData or not self.resolved[kind].enabled then
					button.ufEntryAnimation:Stop()
					button.ufSampleIcon = nil
				end
			end
		end
	end
end

-- The presence container follows the live unit only while collapsing.
function AuraBar:UpdatePresence()
	if not self.presence then return end
	local live = self.enabled and self.collapseGap ~= nil and not self.previewData
	self.presence:SetShown(live)
	self.presence:SetEnabled(live)
end

-- Set by the owner before Layout: the gap to the bar lent the row's space,
-- or nil while the row keeps its space.
function AuraBar:SetCollapse(gap)
	self.collapseGap = gap
	self:UpdatePresence()
end

function AuraBar:SetUnit(unit)
	Auras.SetUnit(self, unit)
	local presence = self.presence
	if presence then
		if presence:GetUnit() ~= unit then presence:SetUnit(unit) else presence:UpdateAllAuras() end
	end
end

-- Collapsing, the viewport covers the row plus the gap while any icon is
-- shown, else nothing. Samples are plain; live auras size it natively: an
-- icon makes the presence extent one cell (row + gap + 1), none leaves the
-- 1-unit minimum, and the viewport's -1 offset removes that unit.
function AuraBar:AnchorViewport()
	local viewport, gap = self.viewport, self.collapseGap
	if viewport == self.frame then return end
	viewport:ClearAllPoints()
	if not gap or not (self.previewData or self.presence) then
		viewport:SetAllPoints(self.frame)
		return
	end
	local top = self.resolved.position == "top"
	local height = self.resolved.height + gap
	if self.previewData then
		local shown = #self.previewContainers.buffs.ufElements + #self.previewContainers.debuffs.ufElements > 0
		local extent = shown and height or 0
		if top then
			viewport:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
			viewport:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT", 0, -extent)
		else
			viewport:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
			viewport:SetPoint("TOPRIGHT", self.frame, "BOTTOMRIGHT", 0, extent)
		end
		return
	end
	local presence = self.presence
	local edge = top and "TOPLEFT" or "BOTTOMLEFT"
	presence:ClearAllPoints()
	presence:SetPoint(edge, self.frame, edge, 0, 0)
	presence:SetFlowLayoutAnchorPoint(edge)
	presence:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right,
		top and AnchorUtil.FlowDirection.Down or AnchorUtil.FlowDirection.Up)
	for _, kind in ipairs(KINDS) do
		Auras.ApplyGroupLayout(presence, kind, 1, height + 1, 0, 0)
	end
	if top then
		viewport:SetPoint("BOTTOMLEFT", presence, "BOTTOMLEFT", 0, 1)
		viewport:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0)
	else
		viewport:SetPoint("TOPLEFT", presence, "TOPLEFT", 0, -1)
		viewport:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
	end
end

function AuraBar:Layout(width)
	self.hostWidth = width or self.hostWidth or self.frame:GetParent():GetWidth()
	Backdrop.ApplyToFixedSize(self.background, self.resolved.rowBackdrop, self.hostWidth, self.resolved.height, false)
	self.geometry = AuraBar.Geometry(self.resolved, self.hostWidth)
	for _, kind in ipairs(KINDS) do
		local geometry, group = self.geometry[kind], self.resolved[kind]
		local section = self:GetContainerParent(kind)
		section:ClearAllPoints()
		section:SetPoint("TOPLEFT", self.frame, "TOPLEFT", geometry.x, -self.resolved.padding)
		section:SetSize(geometry.width, geometry.height)
		local live = self.containers[kind]
		if live then
			live:SetAuraGroupMaxFrameCount(kind, geometry.capacity)
			live:SetAuraGroupEnabled(kind, geometry.capacity > 0)
			if self.presence then self.presence:SetAuraGroupEnabled(kind, geometry.capacity > 0) end
			Auras.ApplyGroupLayout(live, kind, group.size, geometry.height, self.resolved.spacing, 0)
		end
		local container = self.previewData and self.previewContainers[kind] or live
		local anchor = geometry.left and "TOPLEFT" or "TOPRIGHT"
		local direction = geometry.left and AnchorUtil.FlowDirection.Right or AnchorUtil.FlowDirection.Left
		if not container then
			-- Never enabled: no live containers yet.
		elseif self.previewData then
			container:ClearAllPoints()
			container:SetPoint(anchor, section, anchor, 0, 0)
			local flow = container.ufFlow
			flow:SetLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
			flow:SetAnchorPoint(anchor)
			flow:SetGrowthDirection(direction, AnchorUtil.FlowDirection.Down)
			flow:SetMaximumLineSize(geometry.lineSize)
			flow:Apply(container, { { elements = container.ufElements, elementSpacing = self.resolved.spacing, lineSpacing = 0 } })
		else
			container:ClearAllPoints()
			container:SetPoint(anchor, section, anchor, 0, 0)
			container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
			container:SetFlowLayoutAnchorPoint(anchor)
			container:SetFlowLayoutGrowthDirection(direction, AnchorUtil.FlowDirection.Down)
			container:SetFlowLayoutMaximumLineSize(geometry.lineSize)
		end
	end
	self:AnchorViewport()
	if self.previewData and not self.renderingSamples then self:RenderSamples() end
end

function AuraBar:GetSampleLimit(kind)
	return self.geometry[kind].capacity
end

-- Time samples sort by remaining time, permanent last, stable fixture ties.
-- Native/raid priority use explicit illustrative fixture ranks, not live IDs
-- or a reimplementation of Blizzard's hidden priorities.
function AuraBar:GetSampleOrder(kind)
	local entries = {}
	local sort = self.resolved[kind].sort
	for index, aura in ipairs(self.previewData[kind] or {}) do
		local rank
		if sort == "expiration" then
			rank = (aura.duration or 0) > 0 and (aura.remaining or aura.duration) or math.huge
		else
			rank = aura[sort == "unitDebuff" and "sampleRaidPriority" or "sampleNativePriority"] or index
		end
		entries[#entries + 1] = { aura = aura, rank = rank, index = index }
	end
	table.sort(entries, function(a, b) return a.rank < b.rank or a.rank == b.rank and a.index < b.index end)
	local ordered = {}
	for index, entry in ipairs(entries) do ordered[index] = entry.aura end
	return ordered
end
