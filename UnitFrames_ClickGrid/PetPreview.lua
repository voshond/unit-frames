local _, CG = ...
local UF, Preview = CG.UF, CG.Preview

local function EnableAuras(uf, enabled)
	for _, key in ipairs({ "auras", "auraBar" }) do
		local part = uf:GetPart(key)
		if part then part:SetEnabled(enabled and part.resolved.enabled) end
	end
end

function Preview:CreatePet(host)
	local pet = UF.Units:CreateFromDefinition(CG.definitions.pet, host, CG.Config:GetStyle("pet"))
	pet:SetCombatDeferred(true)
	pet:SetThemeManaged(true)
	return { uf = pet, dirty = true }
end

function Preview:StylePet(pet, host, inline)
	local cfg = CG.Config.styles.pet:Resolved()
	pet.uf:Apply(CG.Config:GetStyle("pet"))
	local frame = pet.uf:GetFrame()
	frame:ClearAllPoints()
	if inline then
		frame:SetPoint("TOP" .. cfg.side, host, "TOP" .. cfg.side, cfg.side == "LEFT" and cfg.inset or -cfg.inset, -cfg.inset)
		frame:SetScale(math.min(1, math.max(1, CG.metrics.member.height - cfg.inset * 2) / pet.uf.layout.height,
			math.max(1, CG.metrics.member.width - cfg.inset * 2) / pet.uf.layout.width))
		frame:SetFrameLevel(host:GetFrameLevel() + 40)
	else
		frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
		frame:SetScale(1)
	end
	pet.dirty = nil
end

function Preview:FeedPet(pet, index, live, unit, present)
	pet.uf:GetFrame():SetShown(present)
	EnableAuras(pet.uf, present)
	if not present then return end
	if live then
		self:ShowLive(pet.uf, unit, pet)
		return
	end
	local values = pet.values
	if not values then
		values = UF.Util.Copy(UF.Units.SAMPLE)
		values.buffs, values.debuffs = {}, {}
		pet.values = values
	end
	values.name, values.lastname, values.class, values.isPlayer = "Pet " .. index, "", nil, false
	values.showCast, values.raidTarget = false, nil
	values.health = values.healthMax * (self.source == "animated" and (0.3 + 0.7 * (math.sin(self.time + index) + 1) / 2) or 0.65)
	UF.Units:ShowSample(pet.uf, values)
end

function Preview:FeedInlinePet(cell, index, live, unit)
	if CG.metrics.pet.mode ~= "inline" then
		if cell.pet then self:FeedPet(cell.pet, index, live, nil, false) end
		return
	end
	cell.pet = cell.pet or self:CreatePet(cell.frame)
	if cell.pet.dirty then self:StylePet(cell.pet, cell.member:GetFrame(), true) end
	local petUnit = live and (cell.petUnit or CG.PetUnit(unit))
	local present = live and petUnit and UnitExists(petUnit) or not live and index % 3 == 1
	self:FeedPet(cell.pet, index, live, petUnit, present == true)
end

function Preview:PetRoster(live, count)
	if CG.metrics.pet.mode ~= "group" then return 0 end
	if not live then return math.ceil(count / 3) end
	return CG:PetCount()
end

function Preview:ShowPetGroup(live, count)
	self.petCells = self.petCells or {}
	local section = self.layout.sections.pets
	local label = self.labels.pets
	if section and count > 0 then
		if not label then label = self.frame:CreateFontString(nil, "OVERLAY"); self.labels.pets = label end
		CG.Layout.TitleInPreview(label, self.frame, "pets", section, self.cfg.titles, section.grid.height, self.layout.titlePadding)
	end
	for index = 1, section and count or 0 do
		local cell = self.petCells[index]
		if not cell then
			local host = CreateFrame("Frame", nil, self.frame)
			cell = { frame = host, pet = self:CreatePet(host) }
			self.petCells[index] = cell
		end
		local x, y = CG.Layout.Cell(index, section.grid.columns, section.capacity.rows, self.cfg.panel.flow,
			CG.metrics.pet.width, CG.metrics.pet.height, self.cfg.panel.spacingX, self.cfg.panel.spacingY)
		cell.frame:ClearAllPoints()
		cell.frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", section.x + x, -section.y - y)
		cell.frame:SetSize(CG.metrics.pet.width, CG.metrics.pet.height)
		cell.frame:Show()
		if cell.pet.dirty then self:StylePet(cell.pet, cell.frame, false) end
		local source = live and CG.headers.pets and CG.headers.pets:GetAttribute("child" .. index)
		local unit = source and source.Pet.__unit
		self:FeedPet(cell.pet, index, live, unit, not live or unit and UnitExists(unit) == true)
	end
	for index = (section and count or 0) + 1, #self.petCells do
		local cell = self.petCells[index]
		cell.frame:Hide()
		EnableAuras(cell.pet.uf, false)
	end
end

function Preview:DirtyPets(changes)
	if changes and not changes.full and not changes.pet and not changes.layout then return end
	for _, cell in ipairs(self.cells) do if cell.pet then cell.pet.dirty = true end end
	for _, cell in ipairs(self.petCells or {}) do cell.pet.dirty = true end
end

function Preview:ReleasePets()
	for _, cell in ipairs(self.cells) do if cell.pet then cell.pet.uf:Release() end end
	for _, cell in ipairs(self.petCells or {}) do
		cell.pet.uf:Release()
		cell.frame:Hide()
	end
end
