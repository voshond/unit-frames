local _, CG = ...
local UF, oUF = CG.UF, CG.UF.oUF

CG.PetSchema = {
	{ key = "display", type = "select", label = "Pet display", default = "off",
		values = { { "off", "Off" }, { "group", "Separate group" }, { "inline", "Inside member" } } },
	{ key = "interactive", type = "toggle", label = "Allow pet interaction", default = false,
		tooltip = "Pet bars receive click spells and mouseover casts. Off: pet bars are mouse-transparent. Changes apply after combat." },
	{ key = "side", type = "select", label = "Pet side", default = "RIGHT",
		values = { { "LEFT", "Left" }, { "RIGHT", "Right" } }, hidden = function(cfg) return cfg.display ~= "inline" end },
	{ key = "gap", type = "range", label = "Gap to member", min = 0, max = 30, step = 1, default = 2,
		hidden = function(cfg) return cfg.display ~= "inline" end },
	{ key = "hover", type = "toggle", label = "Pet mouseover highlight", default = true },
	{ key = "hoverColor", type = "color", label = "Pet mouseover colour", default = { 0.2, 0.8, 1, 0.35 }, hasAlpha = true },
}

function CG.PetUnit(owner)
	if not owner then return nil end
	if owner == "player" then return "pet" end
	local kind, index = owner:match("^(%a+)(%d+)$")
	if kind ~= "party" and kind ~= "raid" then return nil end
	return kind .. "pet" .. index
end

function CG:PetCount()
	if self.metrics.pet.mode ~= "group" then return 0 end
	local count = 0
	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			if UnitExists("raidpet" .. index) then count = count + 1 end
		end
	else
		if UnitExists("pet") then count = 1 end
		for index = 1, math.max(0, GetNumGroupMembers() - 1) do
			if UnitExists("partypet" .. index) then count = count + 1 end
		end
	end
	return count
end

function CG:EnsureInlinePets(panel)
	local previous = oUF:GetActiveStyle()
	oUF:SetActiveStyle(self.STYLE .. "Pet")
	self.inlineHeaders = self.inlineHeaders or {}
	for key, header in pairs(self.headers) do
		local wanted = key == "party" or key == "tanks" and panel.tanks
			or panel.mode == "flat" and key == "raid" or panel.mode ~= "flat" and key:match("^group%d$")
		if wanted and not self.inlineHeaders[header] then
			local index = 1
			local cell = header:GetAttribute("child" .. index)
			while cell do
				if not cell.Pet then
					local frame = oUF:Spawn("raidpet1", cell:GetName() .. "Pet")
					frame:Disable()
					frame:SetParent(cell)
					frame:SetAttribute("useparent-unit", true)
					frame:SetAttribute("unitsuffix", "pet")
					frame:SetAttribute("toggleForVehicle", false)
					frame:SetAttribute("unit", nil)
					frame.isChild = true
					cell.Pet = frame
				end
				index = index + 1
				cell = header:GetAttribute("child" .. index)
			end
			self.inlineHeaders[header] = true
		end
	end
	oUF:SetActiveStyle(previous)
end

function CG:CreatePetHover(frame)
	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(frame:GetFrameLevel() + 30)
	local hover = overlay:CreateTexture(nil, "OVERLAY")
	hover:SetAllPoints()
	hover:Hide()
	self:GetGridButton(frame).hover = hover
	frame:HookScript("OnEnter", function()
		local cfg = self:GetGridButton(frame).petConfig
		if not cfg then return end
		if cfg.interactive and cfg.hover then hover:Show() end
		local cell = frame:GetParent()
		local owner = cell.Member and self:GetGridButton(cell.Member)
		if owner and owner.status then owner.status:SetHovered(false) end
	end)
	frame:HookScript("OnLeave", function() hover:Hide() end)
end

function CG:RefreshPet(frame, changes, layout)
	local button, cell = self:GetGridButton(frame), frame:GetParent()
	local separate = cell:GetParent() == self.headers.pets
	local active = separate and self.metrics.pet.mode == "group" or not separate and self.metrics.pet.mode == "inline"
	if not active or not self.activeHeaders[cell:GetParent()] then
		self:DeactivateFrame(frame)
		button.hover:Hide()
		return false
	end
	local activated = button.inactive or not button.refreshed
	local cfg = self.Config.styles.pet:Resolved()
	button.petConfig = cfg
	local layoutChanged = activated or not changes or changes.full or changes.layout
	local styled = self:ApplyUnitStyle(frame.uf, "pet", changes, layout, activated)
	if styled then UF.Units:Bind(frame) end
	if styled and not activated then frame:Enable() end
	if activated then
		UnregisterAttributeDriver(frame, "state-visibility")
		frame:SetAttribute("statehidden", nil)
		frame:ResumeAllElements()
		frame:Enable()
		button.inactive = nil
	end
	if styled or layoutChanged then
		frame:ClearAllPoints()
		frame:SetScale(1)
		if separate then
			frame:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
			cell:SetSize(self.metrics.pet.width, self.metrics.pet.height)
		else
			frame:SetPoint("TOPLEFT", cell, "TOPLEFT", layout.petX, 0)
			frame:SetFrameLevel(cell.Member:GetFrameLevel())
		end
	end
	if styled or layoutChanged or changes and changes.petInteraction then
		frame:SetMouseClickEnabled(cfg.interactive)
		frame:SetMouseMotionEnabled(cfg.interactive)
		button.hover:SetColorTexture(UF.Util.UnpackColor(cfg.hoverColor))
		button.hover:Hide()
	end
	if styled or activated then UF.Units:UpdateFrame(frame, "UnitFramesClickGridRefresh") end
	button.refreshed = true
	return activated
end
