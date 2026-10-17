local _, CG = ...
local UF, oUF = CG.UF, CG.UF.oUF

-- Title font strings per secure header, kept off the header itself:
-- { label = section title, columns = flat raid column titles }.
local headerTitles = {}

function CG:GetHeaderTitles(header)
	return headerTitles[header]
end

function CG:CreateHeader(key, capacity, filter, role)
	UF.Perf:Count("headerCreate")
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
	header:SetParent(self.panel)
	header:SetAttribute("startingIndex", 1)
	header:SetAttribute("showSolo", false)
	self.headers[key] = header
	local titles = { label = header:CreateFontString(nil, "OVERLAY"), columns = {} }
	titles.label:Hide()
	headerTitles[header] = titles
	return header
end

local Start

function CG:Start()
	if self.started or not self.loaded or InCombatLockdown() then return end
	-- Members and targets are built from one style each: share their
	-- resolution while creating them, as a refresh does (Schema.Shared).
	UF.Perf:Startup("clickgrid", UF.Schema.Shared, Start, self)
end

function Start(self)
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

local Refresh

-- Members and targets share one style each, so a refresh resolves each
-- style once (Schema.Shared) instead of per frame.
function CG:Refresh()
	UF.Schema.Shared(Refresh, self)
end

function Refresh(self)
	UF.Perf:Count("clickgridRefresh")
	assert(not InCombatLockdown(), "Healing panel changes must wait until combat ends")
	self:Measure()
	local cfg = self.Config:Resolved()
	self:EnsureHeaders(cfg.panel)
	local layout = self.Layout.Compute(cfg.panel, self.metrics.member, self.metrics.target, cfg.titles, cfg.border)
	self.layout = layout
	local activeHeaders = {}
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
	self.Layout.Backdrop(self.background, self.panel, cfg.titles, cfg.border)
	for key, header in pairs(self.headers) do
		local section = layout.sections[key]
		local visible = section ~= nil
		activeHeaders[header] = visible
		-- Layouts absent from this selection cannot acquire combat members.
		if key ~= "party" and not visible then header:SetAttribute("showRaid", false) end
		local titles = headerTitles[header]
		for _, label in ipairs(titles.columns) do label:Hide() end
		if section then
			if key == "raid" then
				titles.label:Hide()
				for column = 1, section.grid.columns do
					local label = titles.columns[column]
					if not label then
						label = header:CreateFontString(nil, "OVERLAY")
						titles.columns[column] = label
					end
					self.Layout.TitleOnHeader(label, header, "group" .. column,
						{ grid = { width = layout.cellWidth } }, cfg.titles, layout.titlePadding,
						(column - 1) * (layout.cellWidth + cfg.panel.spacingX))
				end
			else self.Layout.TitleOnHeader(titles.label, header, key, section, cfg.titles, layout.titlePadding) end
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", self.panel, "TOPLEFT", section.x, -section.y)
			header:SetAttribute("_ignore", true)
			for attribute, value in pairs(self.Layout.Attributes(section.grid, cfg.panel)) do header:SetAttribute(attribute, value) end
			header:SetAttribute("_ignore", nil)
		else titles.label:Hide() end
		if key == "party" then
			header:SetAttribute("showSolo", cfg.panel.showSolo)
			header:SetVisibility("custom [group:raid] hide; " .. (cfg.panel.showSolo and "show" or "[group:party] show; hide"))
		else header:SetVisibility(visible and "custom [group:raid] show; hide" or "custom hide") end
	end
	for _, frame in ipairs(self.frames) do
		local button = self:GetGridButton(frame)
		local kind = button.kind
		local cell = frame:GetParent()
		if not activeHeaders[cell:GetParent()] then
			if not button.inactive then
				frame:Disable()
				RegisterAttributeDriver(frame, "state-visibility", "hide")
				frame:PauseAllElements()
				for _, key in ipairs({ "auras", "auraBar" }) do
					local auras = frame.uf:GetPart(key)
					if auras then auras:SetEnabled(false) end
				end
				if button.slots then button.slots:SetEnabled(false) end
				if frame.uf:GetReadyCheck() then frame.uf:GetReadyCheck():Set(nil) end
				for _, row in frame.uf:Rows() do
					for _, text in pairs(row.texts) do
						UF.TextTags.Unbind(text:GetFrame())
						frame:Untag(text:GetFrame())
					end
				end
				button.inactive = true
			end
		else
			if button.inactive then
				button.inactive = nil
				UnregisterAttributeDriver(frame, "state-visibility")
				frame:SetAttribute("statehidden", nil)
				frame:ResumeAllElements()
				frame:Enable()
			end
			if kind == "target" then frame.uf:SetFillHeight(layout.cellHeight) end
			frame.uf:Apply(self.Config:GetStyle(kind))
			UF.Units:Bind(frame)
			if button.status then button.status:Apply(self.Config:Get().indicators) end
			if button.slots then button.slots:Apply(self:SlotConfig(frame.uf)) end
			frame:ClearAllPoints()
			if kind == "target" then
				frame:SetPoint("TOPLEFT", cell, "TOPLEFT", self.metrics.member.width + cfg.panel.targetGap, 0)
				if self.metrics.target.shown then
					UnregisterAttributeDriver(frame, "state-visibility")
					frame:SetAttribute("statehidden", nil)
					frame:ResumeAllElements()
					frame:Enable()
				else
					frame:Disable()
					RegisterAttributeDriver(frame, "state-visibility", "hide")
					frame:PauseAllElements()
					-- Native aura containers own subscriptions independent of oUF.
					for _, key in ipairs({ "auras", "auraBar" }) do
						local auras = frame.uf:GetPart(key)
						if auras then auras:SetEnabled(false) end
					end
				end
			else frame:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0) end
			cell:SetSize(layout.cellWidth, layout.cellHeight)
			if kind ~= "target" or self.metrics.target.shown then
				UF.Units:UpdateFrame(frame, "UnitFramesClickGridRefresh")
			end
		end
	end
	UF.Perf:Begin("bindings")
	self:ApplyBindings(true)
	UF.Perf:End("bindings")
	-- _ignore itself does not trigger a native header refresh. Recalculate
	-- after all cell sizes and layout attributes have been applied.
	self.revision = (self.revision or 0) + 1
	for key, header in pairs(self.headers) do
		if key ~= "party" and activeHeaders[header] then header:SetAttribute("showRaid", true) end
		header:SetAttribute("ufcg-refresh", self.revision)
	end
	for preview in pairs(self.previews) do preview:Apply() end
end

-- Compiles the current specialization's bindings and writes the changed
-- attributes to every frame. `notify` announces the result to the binding
-- grid when no config change does (spell, macro and spec updates).
function CG:ApplyBindings(notify)
	local plan, errors = self.Bindings:Compile(self.Config:GetBindings())
	self.bindingErrors = errors
	if not self.Bindings:IsExternal() then
		for _, frame in ipairs(self.frames) do
			if not self:GetGridButton(frame).inactive then
				self.Bindings:Apply(frame, plan)
				if ClickCastFrames then ClickCastFrames[frame] = nil end
			end
		end
	end
	if notify then UF.Events:Fire("ClickGridBindingsCompiled") end
end
