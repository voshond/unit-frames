local _, CG = ...
local UF = CG.UF
local Preview = {}
Preview.__index = Preview
CG.Preview = Preview

function Preview:New(parent)
	local result = setmetatable({ frame = CreateFrame("Frame", nil, parent), cells = {}, labels = {}, time = 0 }, self)
	result.background = CreateFrame("Frame", nil, result.frame, "BackdropTemplate")
	CG.previews[result] = true
	result:Apply()
	return result
end

function Preview:CreateCell()
	local host = CreateFrame("Frame", nil, self.frame)
	local member = UF.Units:CreateFromDefinition(CG.definitions.member, host, CG.Config:GetStyle("member"))
	local target = UF.Units:CreateFromDefinition(CG.definitions.target, host, CG.Config:GetStyle("target"))
	local slots = CG.Slots:New(member:GetFrame(), CG:SlotConfig(member))
	local status = CG.Status:Create(member:GetFrame(), member)
	member:SetCombatDeferred(true)
	target:SetCombatDeferred(true)
	slots:SetCombatDeferred(true)
	member:SetThemeManaged(true)
	target:SetThemeManaged(true)
	slots:SetThemeManaged(true)
	-- Plain samples drive ordinary buttons and never touch restricted live art.
	local cell = { frame = host, member = member, target = target, slots = slots, status = status }
	self.cells[#self.cells + 1] = cell
	return cell
end

function Preview:ShowLive(uf, unit, cell)
	if not unit or not UnitExists(unit) then uf:GetFrame():Hide(); return end
	uf:GetFrame():Show()
	local health = uf:GetRow("health")
	cell.calculator = cell.calculator or CreateUnitHealPredictionCalculator()
	local calculator = cell.calculator
	calculator:SetMaximumHealthMode(UF.Units:GetHealthMaximumMode(health:GetBar()))
	calculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
	UnitGetDetailedHealPrediction(unit, "player", calculator)
	health:SetRange(0, calculator:GetMaximumHealth())
	health:SetValue(UnitHealth(unit))
	health:SetSegmentValue("heal", UnitGetIncomingHeals(unit))
	health:SetSegmentValue("absorb", UnitGetTotalAbsorbs(unit))
	health:SetSegmentValue("healAbsorb", UnitGetTotalHealAbsorbs(unit))
	local mode = uf:GetRowConfig("health").colorMode
	if mode == "class" then health:SetColor(UF.Colors.Unit(unit))
	elseif mode == "gradient" then health:SetColor(UnitHealthPercent(unit, true, UF.Colors.HealthCurve()):GetRGB())
	else health:ClearColor() end
	health:ShowLive(unit)
	local power = uf:GetRow("power")
	local _, token = UnitPowerType(unit)
	power:SetRange(0, UnitPowerMax(unit))
	power:SetValue(UnitPower(unit))
	power:SetColor(UF.Colors.Power(token))
	power:ShowLive(unit)
	uf:SetRangeState(UnitInRange(unit))
	uf:GetAuras():SetUnit(unit)
	uf:GetRaidTarget():SetIndex(GetRaidTargetIndex(unit))
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
	self:ShowData(self.data or { source = "static", count = 5 })
end

local names = { "Tank", "Healer", "Mage", "Priest", "Druid", "Paladin", "Hunter", "Warlock" }
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

function Preview:ShowData(data, dataOnly)
	self.data = data
	if InCombatLockdown() then CG.pending = true; return end
	local count = data.count or 5
	local live = data.source == "live"
	if live then count = math.max(1, GetNumGroupMembers()) end
	local raid = live and IsInRaid() or count > 5
	local cfg = self.cfg.panel
	local layout = CG.Layout.Compute(cfg, CG.metrics.member, CG.metrics.target, self.cfg.titles, count)
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
			if not dataOnly or not cell.styled then
				cell.member:Apply(CG.Config:GetStyle("member"))
				cell.member:SetPoint("TOPLEFT", cell.frame, "TOPLEFT", 0, 0)
				cell.target:Apply(CG.Config:GetStyle("target"))
				cell.target:SetPoint("TOPLEFT", cell.frame, "TOPLEFT", CG.metrics.member.width + cfg.targetGap, 0)
				cell.target:GetFrame():SetShown(cfg.targets)
				cell.slots:Apply(CG:SlotConfig(cell.member))
				CG.Status:Apply(cell.member:GetFrame(), cell.status, self.cfg.indicators, false)
				cell.styled = true
			end
			local values = self:Values(index)
			if live then
				local source = CG.headers[key] and CG.headers[key]:GetAttribute("child" .. localIndex)
				local unit = source and source.Member.__unit
				if not raid and localIndex == 1 and not IsInGroup() then unit = "player" end
				self:ShowLive(cell.member, unit, cell)
				if cell.slots.previewData then
					cell.slots.previewData = nil
					for _, button in ipairs(cell.slots.samples or {}) do button:Hide() end
					cell.slots:SetEnabled(true)
				end
				if unit then cell.slots:SetUnit(unit) end
				for _, widget in pairs(cell.status) do widget:Hide() end
				if cfg.targets then self:ShowLive(cell.target, unit and unit .. "target", cell) end
			else
				cell.member:GetFrame():Show()
				UF.Units:ShowSample(cell.member, values)
				cell.slots:ShowSample(values)
				CG.Status:Sample(cell.status, self.cfg.indicators, index)
				local targetValues = UF.Util.Copy(values)
				targetValues.name, targetValues.class, targetValues.reaction = "Enemy " .. index, nil, "hostile"
				targetValues.isPlayer = false
				UF.Units:ShowSample(cell.target, targetValues)
			end
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
	for i = visible + 1, #self.cells do self.cells[i].frame:Hide() end
end

function Preview:Tick(elapsed)
	if self.data.source ~= "animated" and self.data.source ~= "live" then return end
	self.time = self.time + elapsed
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed < 0.1 then return end
	self.elapsed = 0
	self:ShowData(self.data, true)
end

function Preview:Release()
	if self.released then return end
	self.released = true
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
		CG.Status:Release(cell.status)
		cell.slots:Release()
		cell.member:Release()
		cell.target:Release()
		cell.frame:Hide()
	end
end
