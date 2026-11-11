local _, CG = ...
local UF, oUF = CG.UF, CG.UF.oUF

CG.PetSchema = {
	{ key = "display", type = "select", label = "Pet display", default = "inline",
		values = { { "off", "Off" }, { "group", "Separate group" }, { "inline", "Inside member" } } },
	{ key = "interactive", type = "toggle", label = "Allow pet interaction", default = true,
		tooltip = "Pet bars receive click spells and mouseover casts. Off: pet bars are mouse-transparent. Changes apply after combat." },
	{ key = "side", type = "select", label = "Pet side", default = "RIGHT",
		values = { { "LEFT", "Left" }, { "RIGHT", "Right" } }, hidden = function(cfg) return cfg.display ~= "inline" end },
	{ key = "gap", type = "range", label = "Gap to member", min = 0, max = 30, step = 1, default = 1,
		hidden = function(cfg) return cfg.display ~= "inline" end },
	{ key = "includeInWidth", type = "toggle", label = "Width includes pet", default = true,
		tooltip = "On: members keep their configured width and the pet and gap take their space from it. Off: members grow by the pet's width and gap.",
		hidden = function(cfg) return cfg.display ~= "inline" end },
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
					self:WatchInlinePet(cell)
				end
				index = index + 1
				cell = header:GetAttribute("child" .. index)
			end
			self.inlineHeaders[header] = true
		end
	end
	oUF:SetActiveStyle(previous)
end

-- An inline pet sits over its member: entering it leaves the member.
-- Non-interactive pets take no mouse motion, so they never highlight.
function CG:WatchPetHover(frame)
	frame:HookScript("OnEnter", function()
		local member = frame:GetParent().Member
		if member then member.uf:SetHovered(false) end
	end)
end

function CG:RefreshPet(frame, changes, layout)
	local button, cell = self:GetGridButton(frame), frame:GetParent()
	local separate = cell:GetParent() == self.headers.pets
	local active = separate and self.metrics.pet.mode == "group" or not separate and self.metrics.pet.mode == "inline"
	if not active or not self.activeHeaders[cell:GetParent()] then
		self:DeactivateFrame(frame)
		if not separate then self:ReserveMember(cell.Member.uf, false, false) end
		return false
	end
	local activated = button.inactive or not button.refreshed
	local cfg = self.Config.styles.pet:Resolved()
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
			self:ReserveMember(cell.Member.uf, true, frame:IsShown())
			local point, x, y = cell.Member.uf:GetReserveAnchor()
			frame:SetPoint(point, cell.Member, point, x, y)
			frame:SetFrameLevel(cell.Member:GetFrameLevel() + 1)
		end
	end
	if styled or layoutChanged or changes and changes.petInteraction then
		frame:SetMouseClickEnabled(cfg.interactive)
		frame:SetMouseMotionEnabled(cfg.interactive)
		if not cfg.interactive then frame.uf:SetHovered(false) end
	end
	if styled or activated then UF.Units:UpdateFrame(frame, "UnitFramesClickGridRefresh") end
	button.refreshed = true
	return activated
end

function CG:ReserveMember(uf, reserved, present)
	local pet = self.metrics.pet
	if reserved and pet.mode == "inline" then uf:SetReserve(pet.side, pet.width + pet.gap, pet.included) else uf:SetReserve(nil) end
	uf:SetReserveActive(present)
end

function CG:WatchInlinePet(cell)
	local function Update()
		if self.metrics.pet.mode == "inline" then cell.Member.uf:SetReserveActive(cell.Pet:IsShown()) end
	end
	cell.Pet:HookScript("OnShow", Update)
	cell.Pet:HookScript("OnHide", Update)
end
