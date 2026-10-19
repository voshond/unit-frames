local _, CG = ...
local UF = CG.UF

function CG.MergeChanges(into, changes)
	if into.full then return into end
	if changes.full then
		wipe(into)
		into.full = true
		return into
	end
	for key, value in pairs(changes) do if value then into[key] = true end end
	return into
end

function CG:RefreshChanges(kind, path)
	if not path then return { full = true } end
	if kind == "member" or kind == "target" then
		if not UF.Schema.Find(self:StyleSchema(kind), path) then return { full = true } end
		local changes = { layout = true, [kind] = true }
		if kind == "member" then
			changes.indicators = true
			changes.slots = path == "auras" or path:match("^auras%.") ~= nil
		end
		return changes
	end
	if kind ~= "settings" or not UF.Schema.Find(self.Config.schema, path) then return { full = true } end
	local root = path:match("^[^%.]+")
	if root == "indicators" or root == "slots" then return { [root] = true } end
	if root == "titles" or root == "border" or root == "panel" then
		return { layout = true, blizzard = root == "panel" }
	end
	return { full = true }
end

function CG:ApplyUnitStyle(uf, kind, changes, layout, force)
	local full = not changes or changes.full
	local fillChanged = kind == "target" and uf.fillHeight ~= layout.cellHeight
	if not full and not force and not changes[kind] and not fillChanged then return false end
	if kind == "target" then uf:SetFillHeight(layout.cellHeight) end
	uf:Apply(self.Config:GetStyle(kind))
	return true
end

function CG:ApplyExtras(uf, extras, changes, force)
	local full = not changes or changes.full
	local changed = false
	if extras.status and (full or force or changes.indicators) then
		extras.status:Apply(self.Config:GetIndicators())
		changed = true
	end
	if extras.slots and (full or force or changes.slots) then
		extras.slots:Apply(self:SlotConfig(uf))
		changed = true
	end
	return changed
end

local function DisableAuras(uf)
	for _, key in ipairs({ "auras", "auraBar" }) do
		local auras = uf:GetPart(key)
		if auras then auras:SetEnabled(false) end
	end
end

function CG:DeactivateFrame(frame)
	local button = self:GetGridButton(frame)
	if button.inactive then return end
	frame:Disable()
	RegisterAttributeDriver(frame, "state-visibility", "hide")
	frame:PauseAllElements()
	DisableAuras(frame.uf)
	if button.slots then button.slots:SetEnabled(false) end
	if frame.uf:GetReadyCheck() then frame.uf:GetReadyCheck():Set(nil) end
	UF.Units:ClearTags(frame)
	button.inactive = true
end

local function RefreshFrame(self, frame, changes, layout)
	local button = self:GetGridButton(frame)
	local kind, cell = button.kind, frame:GetParent()
	local activated = button.inactive or not button.refreshed
	if button.inactive then
		button.inactive = nil
		UnregisterAttributeDriver(frame, "state-visibility")
		frame:SetAttribute("statehidden", nil)
		frame:ResumeAllElements()
		frame:Enable()
	end
	local styled = self:ApplyUnitStyle(frame.uf, kind, changes, layout, activated)
	if styled then UF.Units:Bind(frame) end
	local extrasChanged = self:ApplyExtras(frame.uf, button, changes, activated)
	local layoutChanged = not changes or changes.full or changes.layout or activated
	if layoutChanged then
		frame:ClearAllPoints()
		if kind == "target" then
			frame:SetPoint("TOPLEFT", cell, "TOPLEFT", self.metrics.member.width + self.panelConfig.targetGap, 0)
		else frame:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0) end
		cell:SetSize(layout.cellWidth, layout.cellHeight)
	end
	if kind == "target" and (styled or layoutChanged) then
		if self.metrics.target.shown then
			UnregisterAttributeDriver(frame, "state-visibility")
			frame:SetAttribute("statehidden", nil)
			frame:ResumeAllElements()
			frame:Enable()
		else
			frame:Disable()
			RegisterAttributeDriver(frame, "state-visibility", "hide")
			frame:PauseAllElements()
			DisableAuras(frame.uf)
		end
	end
	if (styled or extrasChanged) and (kind ~= "target" or self.metrics.target.shown) then
		UF.Units:UpdateFrame(frame, "UnitFramesClickGridRefresh")
	end
	button.refreshed = true
	return activated
end

function CG:RefreshFrame(frame, changes, layout)
	return frame.uf:GetDecorations():Batch(RefreshFrame, self, frame, changes, layout)
end

function CG:CommitLayout()
	self.revision = (self.revision or 0) + 1
	for key, header in pairs(self.headers) do
		if key ~= "party" and self.activeHeaders[header] then header:SetAttribute("showRaid", true) end
		header:SetAttribute("ufcg-refresh", self.revision)
	end
end
