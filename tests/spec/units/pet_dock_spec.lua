local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Pet inside the player frame", function()
	local ns, player, pet

	local function PetPresent(present)
		UnitExists = function(unit) return unit == "player" or present and unit == "pet" end
		UnitIsVisible = function() return false end
		Mock.RunUntainted(Mock.TickUnitVisibility, pet)
	end

	local function Reserve()
		return pet.uf.layout.width + ns.Config:UnitStore("pet"):Resolved().dock.gap
	end

	local function Padding()
		return ns.Components.Backdrop.Padding(player.uf.resolved.border)
	end

	local function KnownWidth(key)
		return (player.uf:GetRow(key):GetBar():GetKnownSize())
	end

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		player, pet = ns.Units.frames.player, ns.Units.frames.pet
		PetPresent(true)
	end)

	it("keeps the separate pet frame by default", function()
		assert.is_false(ns.Config:UnitStore("pet"):Resolved().dock.enabled)
		assert.is_false(pet.uf.resolved.dock.enabled)
		assert.is_nil(player.uf.reserve)
		assert.is_nil(pet.uf.fillHeight)
		assert.same({ "CENTER", UIParent, "CENTER", -90, -235 }, pet:GetAnchor("CENTER"))
		assert.equals(player.uf.baseLayout.width, player:GetWidth())
		assert.is_nil(ns.Schema.Find(ns.Units:GetSchema("player"), "dock"))
		assert.is_nil(ns.Schema.Find(ns.Units:GetSchema("target"), "dock"))
	end)

	it("places the pet inside the player border at the player's inner height", function()
		local width, health, power = player.uf.baseLayout.width, KnownWidth("health"), KnownWidth("power")
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		local _, right, top, bottom = Padding()
		assert.is_true(top > 0)
		assert.equals(player.uf.layout.height - top - bottom, pet.uf.layout.height)
		assert.equals(pet.uf.layout.height, pet:GetHeight())
		assert.same({ "TOPRIGHT", player, "TOPRIGHT", -right, -top }, pet:GetAnchor("TOPRIGHT"))
		assert.is_nil(pet:GetAnchor("CENTER"))
		assert.equals(player:GetFrameLevel() + 1, pet:GetFrameLevel())
		assert.equals(width + Reserve(), player:GetWidth())
		assert.same({ "CENTER", UIParent, "CENTER", -280, -160 }, player:GetAnchor("CENTER"))
		assert.equals(health, KnownWidth("health"))
		assert.equals(power, KnownWidth("power"))
		ns.Config:SetUnitValue("pet", "dock.gap", 6)
		assert.equals(pet.uf.layout.width + 6, Reserve())
		assert.equals(width + Reserve(), player:GetWidth())
	end)

	it("fills the pet's space when the pet disappears in combat without resizing or rebuilding", function()
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		local reserve, width = Reserve(), player:GetWidth()
		local health, power = KnownWidth("health"), KnownWidth("power")
		local anchor = pet:GetAnchor("TOPRIGHT")
		Mock.inCombat = true
		ns.Perf.counters = {}
		for _, present in ipairs({ false, true, false, true }) do
			PetPresent(present)
			local grown = present and 0 or reserve
			assert.equals(present, pet:IsShown())
			assert.equals(width, player:GetWidth())
			assert.equals(health + grown, KnownWidth("health"))
			assert.equals(power + grown, KnownWidth("power"))
			assert.equals(health + grown, player.uf:GetRow("health").textWidth)
			assert.same({ "CENTER", UIParent, "CENTER", -280, -160 }, player:GetAnchor("CENTER"))
			assert.same(anchor, pet:GetAnchor("TOPRIGHT"))
		end
		local counters = ns.Perf.counters
		ns.Perf.counters = nil
		assert.is_nil(counters.componentCreate)
		assert.is_nil(counters.unitBind)
		assert.is_nil(counters.unitLayout)
		assert.is_false(ns.AfterCombat:IsQueued(player.uf, "layout"))
	end)

	it("keeps the pet's space through player restyles", function()
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		PetPresent(false)
		local health = KnownWidth("health")
		ns.Config:SetUnitValue("player", "width", 260)
		assert.equals(player.uf.baseLayout.width + Reserve(), player:GetWidth())
		assert.equals(health + 30, KnownWidth("health"))
		ns.Config:SetUnitValue("player", "health.height", 40)
		local _, _, top, bottom = Padding()
		assert.equals(player.uf.layout.height - top - bottom, pet.uf.layout.height)
		PetPresent(true)
		assert.equals(health + 30 - Reserve(), KnownWidth("health"))
	end)

	it("can take the pet's space from the configured player width, like the portrait", function()
		local width, health = player.uf.baseLayout.width, KnownWidth("health")
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		ns.Config:SetUnitValue("pet", "dock.includeInWidth", true)
		local _, right, top = Padding()
		assert.equals(width, player:GetWidth())
		assert.equals(health - Reserve(), KnownWidth("health"))
		assert.same({ "TOPRIGHT", player, "TOPRIGHT", -right, -top }, pet:GetAnchor("TOPRIGHT"))
		Mock.inCombat = true
		PetPresent(false)
		assert.equals(width, player:GetWidth())
		assert.equals(health, KnownWidth("health"))
		PetPresent(true)
		assert.equals(health - Reserve(), KnownWidth("health"))
		Mock.inCombat = false
		ns.Config:SetUnitValue("pet", "dock.includeInWidth", false)
		assert.equals(width + Reserve(), player:GetWidth())
		assert.equals(health, KnownWidth("health"))
	end)

	it("keeps secondary player columns beside an included pet", function()
		ns.Config:SetUnitValue("player", "barLayout", "columns")
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		ns.Config:SetUnitValue("pet", "dock.includeInWidth", true)
		local _, right = Padding()
		local power = player.uf:GetRow("power")
		assert.equals(player.uf.baseLayout.width, player:GetWidth())
		assert.equals(-right - Reserve(), power:GetFrame():GetAnchor("TOPRIGHT")[4])
		assert.equals(player.uf.resolved.power.columnWidth, power:GetBar():GetKnownSize())
		PetPresent(false)
		assert.equals(-right, power:GetFrame():GetAnchor("TOPRIGHT")[4])
		assert.equals(player.uf.resolved.power.columnWidth, power:GetBar():GetKnownSize())
	end)

	it("places the pet on the left with the player content beside it", function()
		local left = player.uf:GetRow("health"):GetFrame():GetAnchor("TOPLEFT")[4]
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		ns.Config:SetUnitValue("pet", "dock.side", "LEFT")
		local padLeft, _, top = Padding()
		assert.same({ "TOPLEFT", player, "TOPLEFT", padLeft, -top }, pet:GetAnchor("TOPLEFT"))
		assert.equals(left + Reserve(), player.uf:GetRow("health"):GetFrame():GetAnchor("TOPLEFT")[4])
		PetPresent(false)
		assert.equals(left, player.uf:GetRow("health"):GetFrame():GetAnchor("TOPLEFT")[4])
	end)

	it("moves the portrait on the pet's side inward and leaves the other side alone", function()
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		local _, right = Padding()
		local portrait = player.uf:GetPart("portrait"):GetFrame()
		assert.equals("TOPLEFT", portrait.__state.points[1][1])
		local x = portrait:GetAnchor("TOPLEFT")[4]
		PetPresent(false)
		assert.equals(x, portrait:GetAnchor("TOPLEFT")[4])
		ns.Config:SetUnitValue("player", "portrait.position", "RIGHT")
		PetPresent(true)
		assert.equals(-right - Reserve(), portrait:GetAnchor("TOPRIGHT")[4])
		PetPresent(false)
		assert.equals(-right, portrait:GetAnchor("TOPRIGHT")[4])
	end)

	it("keeps the player position and never overwrites the separate pet position from Edit Mode", function()
		ns.EditMode.layout = "Healer"
		ns.Config:SetPosition("Healer", "pet", "TOP", -90, -200)
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		ns.EditMode:SavePosition("Healer", "player", "LEFT", 10, 5)
		assert.same({ point = "LEFT", x = 10, y = 5 }, ns.Config:GetPosition("Healer", "player"))
		ns.EditMode:SavePosition("Healer", "pet", "CENTER", 5, 5)
		assert.same({ point = "TOP", x = -90, y = -200 }, ns.Config:GetPosition("Healer", "pet"))
		local _, right, top = Padding()
		assert.same({ "TOPRIGHT", player, "TOPRIGHT", -right, -top }, pet:GetAnchor("TOPRIGHT"))
		ns.Config:SetUnitValue("pet", "dock.enabled", false)
		assert.same({ "TOP", UIParent, "TOP", -90, -200 }, pet:GetAnchor("TOP"))
	end)

	it("restores both separate frames when switched off", function()
		local level, health = pet:GetFrameLevel(), KnownWidth("health")
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		PetPresent(false)
		ns.Config:SetUnitValue("pet", "dock.enabled", false)
		assert.is_nil(pet.uf.fillHeight)
		assert.is_nil(player.uf.reserve)
		assert.equals(level, pet:GetFrameLevel())
		assert.same({ "CENTER", UIParent, "CENTER", -90, -235 }, pet:GetAnchor("CENTER"))
		assert.equals(player.uf.baseLayout.width, player:GetWidth())
		Mock.inCombat = true
		PetPresent(true)
		PetPresent(false)
		assert.equals(health, KnownWidth("health"))
	end)

	it("defers docking changes until combat ends", function()
		Mock.inCombat = true
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		assert.is_nil(player.uf.reserve)
		assert.same({ "CENTER", UIParent, "CENTER", -90, -235 }, pet:GetAnchor("CENTER"))
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		local _, right, top, bottom = Padding()
		assert.same({ "TOPRIGHT", player, "TOPRIGHT", -right, -top }, pet:GetAnchor("TOPRIGHT"))
		assert.equals(player.uf.layout.height - top - bottom, pet:GetHeight())
		assert.equals(player.uf.baseLayout.width + Reserve(), player:GetWidth())
	end)

	it("copies the player style without changing the dock #copy", function()
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		ns.Config:SetUnitValue("pet", "dock.side", "LEFT")
		assert.is_true(ns.Units:CopyPlayerSettings("pet"))
		assert.is_true(pet.uf.resolved.dock.enabled)
		assert.equals("LEFT", pet.uf.resolved.dock.side)
		assert.equals("TOPLEFT", pet.__state.points[1][1])
	end)

	it("previews the docked pet at the player's inner height in the Workbench", function()
		local wb
		ns, wb = Helpers.LoadWorkbench()
		player = ns.Units.frames.player
		wb:Open("unit.pet")
		local natural = wb.handle.parts.uf.layout.height
		local function Inner()
			local _, _, top, bottom = Padding()
			return player.uf.layout.height - top - bottom
		end
		ns.Config:SetUnitValue("player", "health.height", 50)
		ns.Config:SetUnitValue("pet", "dock.enabled", true)
		assert.is_true(Inner() > natural)
		assert.equals(Inner(), wb.handle.parts.uf.layout.height)
		ns.Config:SetUnitValue("player", "health.height", 60)
		assert.equals(Inner(), wb.handle.parts.uf.layout.height)
		ns.Config:SetUnitValue("pet", "dock.enabled", false)
		assert.equals(natural, wb.handle.parts.uf.layout.height)
	end)
end)
