local _, CG = ...
local UF, oUF = CG.UF, CG.UF.oUF

function CG:CreateHeader(key, capacity, filter, role)
	-- SpawnHeader hides Blizzard party frames only if showParty is supplied
	-- here. Configure it later through normal header attributes instead.
	local header = oUF:SpawnHeader("UnitFramesClickGrid" .. key, "SecureGroupHeaderTemplate", {
		template = "UnitFramesClickGridCellTemplate", showRaid = true, showPlayer = true,
		showSolo = true, groupFilter = filter, roleFilter = role,
		unitsPerColumn = capacity, maxColumns = 1, startingIndex = -capacity,
		["oUF-initialConfigFunction"] = [[
			local header = self:GetParent()
			if not self:GetAttribute("oUF-onlyProcessChildren") then
				header = header:GetParent()
				self:SetAttribute("useparent-unit", true)
				self:SetAttribute("toggleForVehicle", not self:GetAttribute("ufcg-target"))
			end
			self:SetWidth(header:GetAttribute("member-width"))
			self:SetHeight(header:GetAttribute("cell-height"))
		]],
	})
	header:SetParent(self.panel)
	header:SetAttribute("member-width", self.metrics.member.width)
	header:SetAttribute("cell-height", self.metrics.member.height)
	-- The native header's negative starting index requests capacity dummy
	-- children. They are fully styled before any combat roster assignment.
	header:Show()
	for i = 1, capacity do
		local cell = header:GetAttribute("child" .. i)
		assert(cell, "Secure header did not prepare its full capacity")
		cell:SetSize(self.metrics.member.width, self.metrics.member.height)
	end
	header:Hide()
	header:SetAttribute("startingIndex", 1)
	header:SetAttribute("showSolo", false)
	self.headers[key] = header
	header.ufcgLabel = header:CreateFontString(nil, "OVERLAY")
	header.ufcgLabel:Hide()
	return header
end

function CG:Start()
	if self.started or not self.loaded or InCombatLockdown() then return end
	self:Measure()
	self.panel = CreateFrame("Frame", "UnitFramesClickGridPanel", UIParent, "SecureHandlerStateTemplate")
	self.background = CreateFrame("Frame", nil, self.panel, "BackdropTemplate")
	self.background:SetAllPoints()
	self.panel:SetAttribute("_onstate-roster", [[
		self:SetWidth(self:GetAttribute(newstate.."-width"))
		self:SetHeight(self:GetAttribute(newstate.."-height"))
	]])
	local previous = oUF:GetActiveStyle()
	oUF:SetActiveStyle(self.STYLE)
	self:CreateHeader("party", 5)
	self.headers.party:SetAttribute("showParty", true)
	self.headers.party:SetAttribute("showRaid", false)
	oUF:SetActiveStyle(previous)
	self.started = true
	UF.EditMode:Register(self.panel, "clickgrid.panel", "UnitFrames: ClickGrid", { point = "CENTER", x = 0, y = 0 }, "clickgrid.panel")
	self:Refresh()
	self:RegisterWorkbench()
end

function CG:EnsureHeaders(panel)
	local previous = oUF:GetActiveStyle()
	oUF:SetActiveStyle(self.STYLE)
	if panel.mode == "flat" then
		if not self.headers.raid then self:CreateHeader("raid", 40) end
	else
		for group = 1, 8 do
			local key = "group" .. group
			if not self.headers[key] then self:CreateHeader(key, 5, tostring(group)) end
		end
	end
	if panel.tanks and not self.headers.tanks then self:CreateHeader("tanks", 40, nil, "TANK") end
	oUF:SetActiveStyle(previous)
end

function CG:Refresh()
	assert(not InCombatLockdown(), "Healing panel changes must wait until combat ends")
	self:Measure()
	local cfg = self.Config:Resolved()
	self:EnsureHeaders(cfg.panel)
	local layout = self.Layout.Compute(cfg.panel, self.metrics.member, self.metrics.target, cfg.titles)
	self.layout = layout
	self.panel:SetScale(cfg.panel.scale)
	for _, state in ipairs({ "party", "raid", "solo" }) do
		self.panel:SetAttribute(state .. "-width", layout[state].width)
		self.panel:SetAttribute(state .. "-height", layout[state].height)
	end
	-- Precompute each party size outside combat. The secure driver selects
	-- bounds as members join/leave, while the header retains all five cells.
	for count = 2, 5 do
		self.panel:SetAttribute("party" .. count .. "-width", layout.partySizes[count].width)
		self.panel:SetAttribute("party" .. count .. "-height", layout.partySizes[count].height)
	end
	local size = IsInRaid() and layout.raid or IsInGroup()
		and layout.partySizes[math.max(2, math.min(5, GetNumGroupMembers()))] or layout.solo
	self.panel:SetSize(size.width, size.height)
	RegisterStateDriver(self.panel, "roster", "[group:raid] raid; [@party4,exists] party5; [@party3,exists] party4; [@party2,exists] party3; [group:party] party2; solo")
	RegisterAttributeDriver(self.panel, "state-visibility", not cfg.panel.enabled and "hide"
		or cfg.panel.showSolo and "show" or "[group] show; hide")
	self.Layout.Backdrop(self.background, self.panel, cfg.titles)
	for key, header in pairs(self.headers) do
		local section = layout.sections[key]
		local visible = section ~= nil
		for _, label in ipairs(header.ufcgColumnLabels or {}) do label:Hide() end
		if section then
			if key == "raid" then
				header.ufcgLabel:Hide()
				header.ufcgColumnLabels = header.ufcgColumnLabels or {}
				for column = 1, section.grid.columns do
					local label = header.ufcgColumnLabels[column]
					if not label then
						label = header:CreateFontString(nil, "OVERLAY")
						header.ufcgColumnLabels[column] = label
					end
					self.Layout.TitleOnHeader(label, header, "group" .. column,
						{ grid = { width = layout.cellWidth } }, cfg.titles, cfg.panel.padding,
						(column - 1) * (layout.cellWidth + cfg.panel.spacingX))
				end
			else self.Layout.TitleOnHeader(header.ufcgLabel, header, key, section, cfg.titles, cfg.panel.padding) end
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", self.panel, "TOPLEFT", section.x, -section.y)
			header:SetAttribute("_ignore", true)
			for attribute, value in pairs(self.Layout.Attributes(section.grid, cfg.panel)) do header:SetAttribute(attribute, value) end
			header:SetAttribute("_ignore", nil)
		else header.ufcgLabel:Hide() end
		if key == "party" then
			header:SetAttribute("showSolo", cfg.panel.showSolo)
			header:SetVisibility("custom [group:raid] hide; " .. (cfg.panel.showSolo and "show" or "[group:party] show; hide"))
		else header:SetVisibility(visible and "custom [group:raid] show; hide" or "custom hide") end
	end
	local plan, errors = self.Bindings:Compile(self.Config:GetBindings())
	self.bindingErrors = errors
	local external = self.Bindings:IsExternal()
	for _, frame in ipairs(self.frames) do
		local kind = frame.ufcgKind
		frame.uf:Apply(self.Config:GetStyle(kind))
		UF.Units:Bind(frame)
		if frame.ufcgStatus then self.Status:Apply(frame, frame.ufcgStatus, cfg.indicators, true) end
		if frame.ufcgSlots then frame.ufcgSlots:Apply(self:SlotConfig(frame.uf)) end
		frame:ClearAllPoints()
		local cell = frame:GetParent()
		if kind == "target" then
			frame:SetPoint("TOPLEFT", cell, "TOPLEFT", self.metrics.member.width + cfg.panel.targetGap, 0)
			if cfg.panel.targets then
				UnregisterAttributeDriver(frame, "state-visibility")
				frame:SetAttribute("statehidden", nil)
				RegisterUnitWatch(frame)
			else RegisterAttributeDriver(frame, "state-visibility", "hide") end
		else frame:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0) end
		cell:SetSize(layout.cellWidth, layout.cellHeight)
		if not external then
			self.Bindings:Apply(frame, plan)
			if ClickCastFrames then ClickCastFrames[frame] = nil end
		end
		frame:UpdateAllElements("UnitFramesClickGridRefresh")
		frame:UpdateTags()
	end
	-- _ignore itself does not trigger a native header refresh. Recalculate
	-- after all cell sizes and layout attributes have been applied.
	self.revision = (self.revision or 0) + 1
	for _, header in pairs(self.headers) do header:SetAttribute("ufcg-refresh", self.revision) end
	for preview in pairs(self.previews) do preview:Apply() end
end
