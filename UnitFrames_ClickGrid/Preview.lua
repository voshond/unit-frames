local _, CG = ...
local UF = CG.UF
local Preview = UF.Object:Extend("ClickGridPreview")
CG.Preview = Preview

function Preview:Init(parent)
	self.frame, self.cells, self.labels, self.time = CreateFrame("Frame", nil, parent), {}, {}, 0
	self.background = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
	self.frame:SetScript("OnSizeChanged", function()
		if self.onSizeChanged then self.onSizeChanged() end
	end)
	CG.previews[self] = true
	self:Apply()
end

-- The preview owns its script. Stage fitting subscribes without replacing it.
function Preview:SetSizeChangedCallback(callback)
	self.onSizeChanged = callback
end

function Preview:CreateCell()
	local host = CreateFrame("Frame", nil, self.frame)
	local member = UF.Units:CreateFromDefinition(CG.definitions.member, host, CG.Config:GetStyle("member"))
	local target = UF.Units:CreateFromDefinition(CG.definitions.target, host, CG.Config:GetStyle("target"))
	local status, slots = CG:AddMemberExtras(member, member:GetFrame(), false)
	for _, uf in ipairs({ member, target }) do
		uf:SetCombatDeferred(true)
		uf:SetThemeManaged(true)
	end
	-- Plain samples drive ordinary buttons and never touch restricted live art.
	local cell = { frame = host, member = member, target = target, slots = slots, status = status }
	self.cells[#self.cells + 1] = cell
	return cell
end

function Preview:ShowLive(uf, unit, cell)
	if not unit or not UnitExists(unit) then
		uf:GetFrame():Hide()
		local auras = uf:GetPart("auras")
		if auras then auras:SetEnabled(false) end
		return false
	end
	uf:GetFrame():Show()
	cell.calculator = cell.calculator or CreateUnitHealPredictionCalculator()
	UF.UnitRows.LiveHealth(uf:GetRow("health"), unit, cell.calculator, uf:GetRowConfig("health").colorMode)
	UF.UnitRows.LivePower(uf:GetRow("power"), unit)
	uf:SetRangeState(UnitInRange(unit))
	local auras = uf:GetPart("auras")
	auras:SetEnabled(auras.resolved.enabled)
	auras:SetUnit(unit)
	uf:GetPart("raidTarget"):SetIndex(GetRaidTargetIndex(unit))
	return true
end

function Preview:Apply()
	if self.released then return end
	if InCombatLockdown() then
		CG.pending = true
		if not self.notice then
			self.notice = self.frame:CreateFontString(nil, "OVERLAY")
			self.notice:SetFontObject(UF.Media:GetFontObject(UF.Config:GetTheme().font, 12))
			self.notice:SetPoint("CENTER")
			self.notice:SetText("Group preview updates resume after combat.")
		end
		self.notice:Show()
		if not self.cfg then self.frame:SetSize(350, 50) end
		return
	end
	if self.notice then self.notice:Hide() end
	local cfg = CG.Config:Resolved()
	self.cfg = cfg
	CG.Layout.Backdrop(self.background, self.frame, cfg.titles)
	for _, cell in ipairs(self.cells) do cell.styled = false end
	self:ShowData(self.data or { source = "static", count = 5 })
end

function Preview:ChangeSource(source)
	if self.source == source then return end
	self.source = source
	for _, cell in ipairs(self.cells) do
		for _, uf in ipairs({ cell.member, cell.target }) do
			local readyCheck, castbar = uf:GetReadyCheck(), uf:GetPart("castbar")
			if readyCheck then readyCheck:Set(nil) end
			uf:SetResting(false)
			uf:SetRangeState(true, false)
			if castbar then castbar:Hide() end
		end
		cell.status:HideIndicators()
	end
end

function Preview:StyleCell(cell)
	local cfg = self.cfg.panel
	cell.member:Apply(CG.Config:GetStyle("member"))
	cell.member:SetPoint("TOPLEFT", cell.frame, "TOPLEFT", 0, 0)
	cell.target:Apply(CG.Config:GetStyle("target"))
	cell.target:SetPoint("TOPLEFT", cell.frame, "TOPLEFT", CG.metrics.member.width + cfg.targetGap, 0)
	cell.target:GetFrame():SetShown(cfg.targets)
	local targetAuras = cell.target:GetPart("auras")
	if not cfg.targets and targetAuras then targetAuras:SetEnabled(false) end
	cell.slots:Apply(CG:SlotConfig(cell.member))
	cell.status:Apply(CG.Config:Get().indicators)
	cell.styled = true
end

function Preview:FeedCell(cell, index, live, unit)
	if live then
		local present = self:ShowLive(cell.member, unit, cell)
		cell.slots:SetEnabled(present and cell.slots.resolved.enabled)
		if present then cell.slots:SetUnit(unit) end
		cell.status:HideIndicators()
		if self.cfg.panel.targets then self:ShowLive(cell.target, unit and unit .. "target", cell) end
	else
		local values = self:Values(index)
		cell.member:GetFrame():Show()
		local auras = cell.member:GetPart("auras")
		auras:SetEnabled(auras.resolved.enabled)
		UF.Units:ShowSample(cell.member, values)
		cell.slots:SetEnabled(cell.slots.resolved.enabled)
		cell.slots:ShowSample(values)
		cell.status:ShowSample(index, self.data.readyCheck == "check")
		if self.cfg.panel.targets then
			cell.target:GetFrame():Show()
			local targetAuras = cell.target:GetPart("auras")
			targetAuras:SetEnabled(targetAuras.resolved.enabled)
			local targetValues = UF.Util.Copy(values)
			targetValues.name, targetValues.class, targetValues.reaction = "Enemy " .. index, nil, "hostile"
			targetValues.isPlayer = false
			UF.Units:ShowSample(cell.target, targetValues)
		end
	end
end

function Preview:HideCell(cell)
	cell.frame:Hide()
	cell.member:GetPart("auras"):SetEnabled(false)
	cell.target:GetPart("auras"):SetEnabled(false)
	cell.slots:SetEnabled(false)
end

local names = { "Tank", "Healer", "Mage", "Priest", "Druid", "Paladin", "Hunter", "Warlock" }
local READY_SAMPLES = { "ready", "ready", "notready", "waiting" }
local sampleBuffIDs = { [1] = 21562, [2] = 1459, [3] = 139, [4] = 774, [6] = 17, [7] = 33763 }
function Preview:Values(index)
	local value = UF.Util.Copy(UF.Units.SAMPLE)
	value.name = names[(index - 1) % #names + 1] .. " " .. index
	value.class = index % 3 == 0 and "MAGE" or index % 3 == 1 and "WARRIOR" or "PALADIN"
	value.showCast = false
	value.health = value.healthMax * (self.data.source == "animated" and (0.2 + 0.8 * (math.sin(self.time + index) + 1) / 2)
		or (index == 1 and 1 or 0.35 + 0.6 * ((index * 7) % 10) / 10))
	value.absorb = value.healthMax * 0.2
	value.raidTarget = index == 1 and 8 or nil
	-- Ready check demo: mixed answers; one in four never answers. Animated
	-- members answer one after another, then the check ends and fades.
	if self.data.readyCheck == "check" then
		value.readyCheck = READY_SAMPLES[(index - 1) % #READY_SAMPLES + 1]
		if self.data.source == "animated" then
			value.readyCheckTime, value.readyCheckAnswerAt = self.time, 0.4 + ((index - 1) % 5) * 0.5
		end
	end
	-- A few plain examples for the artwork already in UnitFrames; unrelated
	-- sample icons must not match a fixed slot by a made-up default ID.
	for i, aura in ipairs(value.buffs) do
		aura.spellId = sampleBuffIDs[i]
		if self.data.source == "animated" and aura.duration > 0 then
			aura.remaining = (aura.remaining - self.time - index) % aura.duration + 1
		end
	end
	return value
end

function Preview:ShowData(data)
	self.data = data
	if InCombatLockdown() then CG.pending = true; return end
	if self.released then return end
	self:ChangeSource(data.source)
	local count = data.count or 5
	local live = data.source == "live"
	if live then count = math.max(1, GetNumGroupMembers()) end
	local raid = live and IsInRaid() or count > 5
	local cfg = self.cfg.panel
	local layout = CG.Layout.Compute(cfg, CG.metrics.member, CG.metrics.target, self.cfg.titles, count, count)
	self.layout = layout
	local size = raid and layout.raid or count == 1 and layout.solo or layout.party
	self.frame:SetSize(size.width, size.height)
	local visible = 0
	local function Section(key, amount, first)
		local section = layout.sections[key]
		if not section then return end
		local label = self.labels[key]
		if not label then
			label = self.frame:CreateFontString(nil, "OVERLAY")
			self.labels[key] = label
		end
		local contentHeight = section.grid.height
		if key == "party" and count == 1 then contentHeight = layout.cellHeight end
		if key == "raid" then
			label:Hide()
			for column = 1, section.grid.columns do
				local columnKey = "column" .. column
				local columnLabel = self.labels[columnKey]
				if not columnLabel then
					columnLabel = self.frame:CreateFontString(nil, "OVERLAY")
					self.labels[columnKey] = columnLabel
				end
				CG.Layout.TitleInPreview(columnLabel, self.frame, "group" .. column,
					{ x = section.x + (column - 1) * (layout.cellWidth + cfg.spacingX), y = section.y,
						grid = { width = layout.cellWidth } }, self.cfg.titles, contentHeight, cfg.padding)
			end
		else CG.Layout.TitleInPreview(label, self.frame, key, section, self.cfg.titles, contentHeight, cfg.padding) end
		for localIndex = 1, amount do
			visible = visible + 1
			local index = first + localIndex - 1
			local cell = self.cells[visible] or self:CreateCell()
			local x, y = CG.Layout.Cell(localIndex, section.grid.columns, section.grid.rows, cfg.flow,
				layout.cellWidth, layout.cellHeight, cfg.spacingX, cfg.spacingY)
			cell.frame:ClearAllPoints()
			cell.frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", section.x + x, -(section.y + y))
			cell.frame:SetSize(layout.cellWidth, layout.cellHeight)
			cell.frame:Show()
			if not cell.styled then self:StyleCell(cell) end
			local source = live and CG.headers[key] and CG.headers[key]:GetAttribute("child" .. localIndex)
			local unit = source and source.Member.__unit
			if live and not raid and localIndex == 1 and not IsInGroup() then unit = "player" end
			self:FeedCell(cell, index, live, unit)
		end
	end
	for _, label in pairs(self.labels) do label:Hide() end
	if not raid then Section("party", count, 1)
	else
		if cfg.tanks then Section("tanks", live and cfg.tankSlots or math.min(2, cfg.tankSlots), 1) end
		if cfg.mode == "flat" then Section("raid", count, 1)
		else
			for group = 1, 8 do
				-- Live subgroup occupancy is not derivable from total raid size.
				-- Inspect all preallocated positions; ShowLive hides empty units.
				Section("group" .. group, live and 5 or math.max(0, math.min(5, count - (group - 1) * 5)), (group - 1) * 5 + 1)
			end
		end
	end
	for i = visible + 1, #self.cells do self:HideCell(self.cells[i]) end
end

function Preview:Tick(elapsed)
	if self.data.source ~= "animated" and self.data.source ~= "live" then return end
	self.time = self.time + elapsed
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed < 0.1 then return end
	self.elapsed = 0
	self:ShowData(self.data)
end

function Preview:Release()
	if self.released then return end
	self.released = true
	self.onSizeChanged = nil
	self.frame:SetScript("OnSizeChanged", nil)
	CG.previews[self] = nil
	self.frame:Hide()
	if InCombatLockdown() then
		CG.retiredPreviews = CG.retiredPreviews or {}
		CG.retiredPreviews[self] = true
		CG.pending = true
		return
	end
	self:ReleaseComponents()
end

function Preview:ReleaseComponents()
	for _, cell in ipairs(self.cells) do
		cell.member:Release() -- with its status indicators and slots
		cell.target:Release()
		cell.frame:Hide()
	end
end
