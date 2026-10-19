local _, CG = ...
local UF = CG.UF
local Preview = UF.Object:Extend("ClickGridPreview")
CG.Preview = Preview

local function EnableAuras(uf, enabled)
	for _, key in ipairs({ "auras", "auraBar" }) do
		local part = uf:GetPart(key)
		if part then part:SetEnabled(enabled and part.resolved.enabled) end
	end
end

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
	UF.Perf:Count("previewCellCreate")
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
		EnableAuras(uf, false)
		return false
	end
	uf:GetFrame():Show()
	UF.Units:ShowLive(uf, unit, cell)
	return true
end

function Preview:Apply(changes)
	if self.released then return end
	if InCombatLockdown() then
		CG:RequestRefresh()
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
	if not changes or changes.full or changes.layout then
		CG.Layout.Backdrop(self.background, self.frame, cfg.titles, cfg.border)
	end
	for _, cell in ipairs(self.cells) do
		if not changes or changes.full then cell.styled, cell.changes = false, nil
		else cell.changes = CG.MergeChanges(cell.changes or {}, changes) end
	end
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

function Preview:StyleCell(cell, changes)
	local cfg = self.cfg.panel
	local force = not cell.styled
	CG:ApplyUnitStyle(cell.member, "member", changes, self.layout, force)
	local targetStyled = CG:ApplyUnitStyle(cell.target, "target", changes, self.layout, force)
	local layoutChanged = force or not changes or changes.full or changes.layout
	if layoutChanged then
		cell.member:SetPoint("TOPLEFT", cell.frame, "TOPLEFT", 0, 0)
		cell.target:SetPoint("TOPLEFT", cell.frame, "TOPLEFT", CG.metrics.member.width + cfg.targetGap, 0)
	end
	if layoutChanged or targetStyled then
		cell.target:GetFrame():SetShown(CG.metrics.target.shown)
		if not CG.metrics.target.shown then EnableAuras(cell.target, false) end
	end
	CG:ApplyExtras(cell.member, cell, changes, force)
	cell.styled, cell.changes = true, nil
end

function Preview:FeedCell(cell, index, live, unit)
	UF.Perf:Count("previewFeed")
	if live then
		local present = self:ShowLive(cell.member, unit, cell)
		cell.slots:SetEnabled(present and cell.slots.resolved.enabled)
		if present then cell.slots:SetUnit(unit) end
		cell.status:HideIndicators()
		if CG.metrics.target.shown then self:ShowLive(cell.target, unit and unit .. "target", cell) end
	else
		if cell.sampleIndex ~= index then
			cell.memberValues, cell.targetValues = nil, nil
			cell.sampleIndex = index
		end
		local values = self:Values(index, cell.memberValues)
		cell.memberValues = values
		cell.member:GetFrame():Show()
		EnableAuras(cell.member, true)
		UF.Units:ShowSample(cell.member, values)
		cell.slots:SetEnabled(cell.slots.resolved.enabled)
		cell.slots:ShowSample(values)
		cell.status:ShowSample(index, self.data.readyCheck == "check", values)
		if CG.metrics.target.shown then
			cell.target:GetFrame():Show()
			EnableAuras(cell.target, true)
			local targetValues = self:Values(index, cell.targetValues)
			cell.targetValues = targetValues
			targetValues.name, targetValues.class, targetValues.reaction = "Enemy " .. index, nil, "hostile"
			targetValues.isPlayer = false
			targetValues.lastname = ""
			UF.Units:ShowSample(cell.target, targetValues)
		end
	end
end

function Preview:HideCell(cell)
	cell.frame:Hide()
	EnableAuras(cell.member, false)
	EnableAuras(cell.target, false)
	cell.slots:SetEnabled(false)
end

local names = { "Tank", "Healer", "Mage", "Priest", "Druid", "Paladin", "Hunter", "Warlock" }
local READY_SAMPLES = { "ready", "ready", "notready", "waiting" }
local sampleBuffIDs = { [1] = 21562, [2] = 1459, [3] = 139, [4] = 774, [6] = 17, [7] = 33763 }
-- Varied debuffs per member (positions in Units.SAMPLE.debuffs): typed
-- dispels next to an untyped crowd control, so debuff glows show both.
local SAMPLE_DEBUFFS = { { 1 }, { 2, 5 }, { 4, 3 }, {} }
-- Incoming heals as a share of maximum health. With their static health,
-- members 1, 4 and 5 cross one, two and three overheal levels.
local SAMPLE_HEALS = { [1] = 0.1, [4] = 0.45, [5] = 0.9 }
function Preview:Values(index, value)
	if not value then
		value = UF.Util.Copy(UF.Units.SAMPLE)
		-- Empty members still own their lists, like members with sample auras.
		if index % 4 == 0 then value.buffs = {} end
		value.debuffs = {}
		for i, position in ipairs(SAMPLE_DEBUFFS[(index - 1) % #SAMPLE_DEBUFFS + 1]) do
			value.debuffs[i] = UF.Util.Copy(UF.Units.SAMPLE.debuffs[position])
		end
	end
	value.animateAuras = self.data.source == "animated"
	value.name = names[(index - 1) % #names + 1] .. " " .. index
	value.lastname = "Example"
	value.class = index % 3 == 0 and "MAGE" or index % 3 == 1 and "WARRIOR" or "PALADIN"
	value.showCast = false
	value.health = value.healthMax * (self.data.source == "animated" and (0.2 + 0.8 * (math.sin(self.time + index) + 1) / 2)
		or (index == 1 and 1 or 0.35 + 0.6 * ((index * 7) % 10) / 10))
	value.absorb = value.healthMax * 0.2
	value.heal = value.healthMax * (SAMPLE_HEALS[index] or UF.Units.SAMPLE.heal / UF.Units.SAMPLE.healthMax)
	value.raidTarget = index == 1 and 8 or nil
	-- Member 3 is dead and member 5 a ghost, like the status indicator samples.
	value.status = (index == 3 or index == 5) and "dead" or nil
	-- Ready check demo: mixed answers; one in four never answers. Animated
	-- members answer one after another, then the check ends and fades.
	value.readyCheck, value.readyCheckTime, value.readyCheckAnswerAt = nil, nil, nil
	if self.data.readyCheck == "check" then
		value.readyCheck = READY_SAMPLES[(index - 1) % #READY_SAMPLES + 1]
		if self.data.source == "animated" then
			value.readyCheckTime, value.readyCheckAnswerAt = self.time, 0.4 + ((index - 1) % 5) * 0.5
		end
	end
	-- Mixed category samples: one category or none per member; Animated
	-- moves them along every two seconds.
	local categories = UF.Components.CategoryAuras.CATEGORIES
	local step = index + (self.data.source == "animated" and math.floor(self.time / 2) or 0)
	local category = self.data.categoryAuras ~= false and categories[step % (#categories + 2) + 1]
	value.categoryAuras = {}
	if category then value.categoryAuras[category.key] = UF.Util.Copy(UF.Units.CATEGORY_SAMPLES[category.key]) end
	-- A few plain examples for the artwork already in UnitFrames; unrelated
	-- sample icons must not match a fixed slot by a made-up default ID.
	for i, aura in ipairs(value.buffs) do
		aura.spellId = sampleBuffIDs[i]
		local remaining = UF.Units.SAMPLE.buffs[i].remaining
		aura.remaining = self.data.source == "animated" and aura.duration > 0
			and (remaining - self.time - index) % aura.duration + 1 or remaining
	end
	return value
end

function Preview:ShowData(data)
	self.data = data
	if InCombatLockdown() then CG:RequestRefresh(); return end
	if self.released then return end
	self:ChangeSource(data.source)
	local count = data.count or 5
	local live = data.source == "live"
	if live then count = math.max(1, GetNumGroupMembers()) end
	local raid = live and IsInRaid() or count > 5
	local cfg = self.cfg.panel
	local layout = CG.Layout.Compute(cfg, CG.metrics.member, CG.metrics.target, self.cfg.titles, self.cfg.border, count, count)
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
						grid = { width = layout.cellWidth } }, self.cfg.titles, contentHeight, layout.titlePadding)
			end
		else CG.Layout.TitleInPreview(label, self.frame, key, section, self.cfg.titles, contentHeight, layout.titlePadding) end
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
			if not cell.styled or cell.changes then self:StyleCell(cell, cell.changes) end
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
		CG:RequestRefresh()
		return
	end
	self:ReleaseComponents()
end

function Preview:ReleaseComponents()
	for _, cell in ipairs(self.cells) do
		cell.member:Release() -- with its status indicators and slots
		cell.target:Release()
		cell.memberValues, cell.targetValues = nil, nil
		cell.frame:Hide()
	end
end
