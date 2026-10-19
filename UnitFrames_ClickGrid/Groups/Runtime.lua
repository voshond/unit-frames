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
function CG:Refresh(changes)
	UF.Schema.Shared(Refresh, self, changes)
end

function Refresh(self, changes)
	UF.Perf:Count("clickgridRefresh")
	assert(not InCombatLockdown(), "Healing panel changes must wait until combat ends")
	local full = not changes or changes.full or not self.layout
	if full then changes = nil end
	UF.Perf:Count(full and "clickgridFullRefresh" or "clickgridTargetedRefresh")
	local layoutChanged = full or changes.layout
	if full or changes.blizzard then self:UpdateBlizzardFrames() end
	if layoutChanged then self:LayoutPanel() end
	local bindings = full or changes.bindings
	for _, frame in ipairs(self.frames) do
		local cell = frame:GetParent()
		if not self.activeHeaders[cell:GetParent()] then
			self:DeactivateFrame(frame)
		else
			local activated = self:RefreshFrame(frame, changes, self.layout)
			bindings = bindings or activated
		end
	end
	if bindings then
		UF.Perf:Begin("bindings")
		self:ApplyBindings(true)
		UF.Perf:End("bindings")
	end
	if layoutChanged then self:CommitLayout() end
	for preview in pairs(self.previews) do preview:Apply(changes) end
end

-- Compiles the current specialization's bindings and writes the changed
-- attributes to every frame. `notify` announces the result to the binding
-- grid when no config change does (spell, macro and spec updates).
function CG:ApplyBindings(notify)
	UF.Perf:Count("clickgridBindingsCompile")
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
