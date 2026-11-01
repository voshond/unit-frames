local _, ns = ...
local Units = ns.Units

local PetDock = {}
ns.PetDock = PetDock

function PetDock:Config()
	return ns.Config:UnitStore("pet"):Resolved().dock
end

function PetDock:FillHeight(unit)
	if unit ~= "pet" or not self:Config().enabled then return nil end
	local cfg = ns.Config:UnitStore("player"):Resolved()
	local layout = ns.UnitFrameLayout.Compute(Units:GetSpec(Units.definitions.player), cfg)
	return ns.Components.UnitFrame.InnerHeight(cfg, layout.height)
end

function PetDock:Watch(pet)
	if self.watching then return end
	self.watching = true
	local function Update()
		if self.docked then Units.frames.player.uf:SetReserveActive(pet:IsShown()) end
	end
	pet:HookScript("OnShow", Update)
	pet:HookScript("OnHide", Update)
end

PetDock.placement = {
	Apply = function()
		local player, pet = Units.frames.player, Units.frames.pet
		local point, x, y = player.uf:GetReserveAnchor()
		pet:ClearAllPoints()
		pet:SetPoint(point, player, point, x, y)
	end,
	Save = function() return nil end,
}

function PetDock:Place()
	if InCombatLockdown() then
		ns.AfterCombat:Queue("position", self, function() self:Place() end)
		return
	end
	local player, pet = Units.frames.player, Units.frames.pet
	if not player or not pet then return end
	local cfg = self:Config()
	if not cfg.enabled and not self.docked then return end
	self.docked = cfg.enabled
	if cfg.enabled then
		self:Watch(pet)
		self.petLevel = self.petLevel or pet:GetFrameLevel()
		player.uf:SetReserveActive(pet:IsShown())
		player.uf:SetReserve(cfg.side, pet.uf.layout.width + cfg.gap, cfg.includeInWidth)
		pet:SetFrameLevel(player:GetFrameLevel() + 1)
		ns.EditMode:SetPlacement("pet", self.placement)
	else
		player.uf:SetReserve(nil)
		pet:SetFrameLevel(self.petLevel)
		self.petLevel = nil
		ns.EditMode:SetPlacement("pet", nil)
	end
	ns.EditMode:ApplyPosition("pet")
end

function PetDock:Refreshed(unit)
	local pet = Units.frames.pet
	if unit ~= "player" and unit ~= "pet" or not pet then return end
	if unit == "player" and pet.uf.fillHeight ~= self:FillHeight("pet") then
		Units:Refresh("pet")
		return
	end
	self:Place()
end

ns.oUF:Factory(function() PetDock:Refreshed("player") end)
