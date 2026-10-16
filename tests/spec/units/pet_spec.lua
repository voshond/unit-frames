local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Player pet", function()
	local ns, frame
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.pet
	end)

	it("spawns a compact pet frame with its own position, health, power, shields and auras #shields", function()
		assert.equals("pet", frame.__unit)
		assert.equals("UnitFramesPet", frame:GetName())
		assert.is_true(frame:IsProtected())
		assert.equals(170, frame:GetWidth())
		assert.equals(39, frame:GetHeight())
		assert.same({ "CENTER", UIParent, "CENTER", -90, -235 }, frame:GetAnchor("CENTER"))
		assert.equals(frame, ns.EditMode.frames.pet.frame)
		assert.is_true(frame:IsElementEnabled("Health"))
		assert.is_true(frame:IsElementEnabled("Power"))
		assert.is_true(frame:IsElementEnabled("UF_Auras"))
		assert.is_not_nil(frame.Health.DamageAbsorb)
		assert.is_false(frame:IsElementEnabled("Portrait"))
		assert.is_false(frame:IsElementEnabled("UF_Castbar"))
		assert.is_nil(frame.UF_Experience)
		assert.is_nil(ns.Schema.Find(frame.uf:GetSchema(), "experience"))
		assert.equals("[uf:name]", frame.tags[frame.uf:GetRow("health"):GetText("left"):GetFrame()])
	end)

	it("uses pet reaction colours and its actual power type rather than the owner's class or power", function()
		UnitIsPlayer = function(unit) return unit == "player" end
		UnitReaction = function(unit) assert.equals("pet", unit); return 5 end
		frame.Health.UpdateColor(frame, "UNIT_FACTION", "pet")
		assert.same(ns.Config:GetTheme().colors.friendly, frame.Health.__state.color)
		for _, token in ipairs({ "FOCUS", "MANA" }) do
			UnitPowerType = function(unit) assert.equals("pet", unit); return 0, token end
			frame.Power.UpdateColor(frame, "UNIT_DISPLAYPOWER", "pet")
			assert.same(ns.Config:GetTheme().colors[ns.Colors.POWER_KEYS[token]], frame.Power.__state.color)
		end
	end)

	it("binds pet auras and optional casts without changing player or target data", function()
		ns.oUF.elements.UF_Auras.update(frame, "UnitFramesRefresh")
		for _, kind in ipairs({ "buffs", "debuffs" }) do
			assert.equals("pet", frame.uf:GetPart("auras"):GetContainer(kind):GetUnit())
		end
		ns.Config:SetUnitValue("pet", "castbar.enabled", true)
		assert.is_true(frame:IsElementEnabled("UF_Castbar"))
		ns.oUF.elements.UF_Castbar.enable(frame, "pet")
		local queried
		UnitCastingInfo = function(unit) queried = unit; return Secret("Firebolt"), nil, Secret(135812) end
		ns.oUF.elements.UF_Castbar.update(frame, "UnitFramesRefresh")
		assert.equals("pet", queried)
		queried = nil
		ns.oUF.elements.UF_Castbar.update(frame, "UNIT_SPELLCAST_START", "player")
		assert.is_nil(queried)
		assert.equals("bottom", ns.Units.frames.player.uf.resolved.castbar.placement)
		assert.equals(230, ns.Units.frames.target.uf.resolved.width)
	end)

	it("copies the player style once while keeping the pet's position and excluding player XP", function()
		ns.Config:SetPosition("Healer", "pet", "TOP", -90, -200)
		ns.EditMode.layout = "Healer"
		ns.EditMode:ApplyPosition("pet")
		ns.Config:SetUnitValue("player", "castbar.enabled", true)
		ns.Config:SetUnitValue("player", "width", 280)
		ns.Config:SetUnitValue("player", "health.bar.segments.absorb.placement", "append")
		ns.Config:SetUnitValue("player", "auras.debuffs.position", "right")
		assert.is_true(ns.Units:CopyPlayerSettings("pet"))
		assert.equals(280, frame.uf.resolved.width)
		assert.equals("append", frame.uf.resolved.health.bar.segments.absorb.placement)
		assert.equals("right", frame.uf.resolved.auras.debuffs.position)
		assert.is_true(frame:IsElementEnabled("Portrait"))
		assert.is_true(frame:IsElementEnabled("UF_Castbar"))
		assert.is_nil(ns.Config:GetUnitConfig("pet").experience)
		assert.is_nil(frame.UF_Experience)
		assert.same({ "TOP", UIParent, "TOP", -90, -200 }, frame:GetAnchor("TOP"))
		ns.Config:SetUnitValue("pet", "width", 190)
		assert.equals(280, ns.Units.frames.player.uf.resolved.width)
		ns.Config:SetUnitValue("player", "auras.debuffs.position", "bottom")
		assert.equals("right", frame.uf.resolved.auras.debuffs.position)
	end)

	it("renders a friendly focus-powered pet sample without mutating player samples", function()
		local preview = ns.Units:CreateFrame("pet", CreateFrame("Frame"))
		local sample = ns.Units:GetSample("pet")
		ns.Units:ShowSample(preview, sample)
		assert.equals("Wolf", preview:GetRow("health"):GetText("left"):GetFrame():GetText())
		assert.equals("Beast", sample.creatureType)
		assert.equals("normal", sample.classification)
		assert.is_false(sample.isPlayer)
		assert.same(ns.Config:GetTheme().colors.friendly, preview:GetRow("health"):GetBar().bar.__state.color)
		assert.same(ns.Config:GetTheme().colors.focus, preview:GetRow("power"):GetBar().bar.__state.color)
		sample.buffs[1].remaining = 1
		assert.equals(1800, ns.Units:GetSample("pet").buffs[1].remaining)
		assert.equals("Uther", ns.Units.SAMPLE.name)
		preview:Release()
	end)

	it("offers the pet as a live data source in the standalone bar previews", function()
		local wb
		ns, wb = Helpers.LoadWorkbench()
		wb:Open("bar.power")
		local source = ns.Schema.Find(wb.dataTarget.schema, "source")
		local found = false
		for _, choice in ipairs(source.values) do
			if choice[1] == "pet" then found = true end
		end
		assert.is_true(found)
		UnitPowerType = function(unit) assert.equals("pet", unit); return 2, "FOCUS" end
		wb.dataTarget.set("source", "pet")
		wb:OnUpdate(0.1)
		assert.same(ns.Config:GetTheme().colors.focus, wb.handle.parts.row:GetBar().bar.__state.color)
	end)
end)

describe("Embedded oUF pet lifecycle", function()
	local oldWatch, oldSecureUnit, oldModifiedUnit, oldPet, oldClickCast
	before_each(function()
		oldWatch, oldSecureUnit, oldModifiedUnit = RegisterUnitWatch, SecureButton_GetUnit, SecureButton_GetModifiedUnit
		oldPet, oldClickCast = PetFrame, ClickCastFrames
		Helpers.LoadAddon(true)
	end)
	after_each(function()
		RegisterUnitWatch, SecureButton_GetUnit, SecureButton_GetModifiedUnit = oldWatch, oldSecureUnit, oldModifiedUnit
		PetFrame, ClickCastFrames = oldPet, oldClickCast
	end)

	it("uses secure pet clicks/watch, replaces Blizzard's pet frame and updates only the player's pet", function()
		local present, updates, watched = false, {}, {}
		UnitExists = function(unit) return unit == "pet" and present end
		RegisterUnitWatch = function(frame)
			watched[frame] = true
			frame:SetShown(UnitExists(frame:GetAttribute("unit")))
		end
		SecureButton_GetUnit = function(frame) return frame:GetAttribute("unit") end
		SecureButton_GetModifiedUnit = SecureButton_GetUnit
		UIParent.__strict = true
		PetFrame = Mock.NewObject("Frame", UIParent)
		PetFrame.__strict = true
		PetFrame:RegisterEvent("UNIT_PET")
		function PetFrame:SetRolesets(value) self.rolesets = value end
		local native = { Private = {
			argcheck = function() end, nierror = error, GameVersion = { Forever = true },
			unitExists = UnitExists,
			UpdateUnits = function(frame, unit, realUnit)
				local changed = frame.__unit ~= unit
				frame.__unit, frame.__realUnit = unit, realUnit or unit
				return changed
			end,
		} }
		local package = { oUF = native }
		local metadata = C_AddOns.GetAddOnMetadata
		C_AddOns.GetAddOnMetadata = function() return nil end
		assert(loadfile("UnitFrames/Libs/oUF/ouf.lua"))("oUF", package)
		C_AddOns.GetAddOnMetadata = metadata
		assert(loadfile("UnitFrames/Libs/oUF/blizzard.lua"))("oUF", package)
		assert(loadfile("UnitFrames/Libs/oUF/units.lua"))("oUF", package)
		local prototype = native.Private.frame_metatable.__index
		prototype.__strict = true
		function prototype:RegisterEvent(event, handler) self[event] = handler end
		function prototype:SetRolesets(value) self.rolesets = value end
		native:RegisterStyle("PetProbe", function(frame, unit) frame.styledUnit = unit end)
		native:AddElement("PetProbe", function(_, event, unit)
			updates[#updates + 1] = { event, unit }
		end, function() return true end, function() end)
		local pet = native:Spawn("pet", "NativePetProbe")
		assert.equals("pet", pet.styledUnit)
		assert.equals("pet", pet:GetAttribute("unit"))
		assert.equals("target", pet:GetAttribute("*type1"))
		assert.equals("togglemenu", pet:GetAttribute("*type2"))
		assert.is_true(watched[pet])
		assert.is_false(pet:IsShown())
		assert.equals("alwaysBlocked", PetFrame.rolesets)
		assert.is_nil(next(PetFrame.__state.events))

		present = true
		RegisterUnitWatch(pet) -- simulate the engine's secure existence driver
		assert.is_true(pet:IsShown())
		pet.UNIT_PET(pet, "UNIT_PET", "player")
		assert.same({ "UNIT_PET", "pet" }, updates[1])
		pet.UNIT_PET(pet, "UNIT_PET", "player") -- replacement while still visible
		assert.equals(2, #updates)
		pet.UNIT_PET(pet, "UNIT_PET", "party1")
		pet.UNIT_PET(pet, "UNIT_PET", "target")
		assert.equals(2, #updates)
		present = false
		RegisterUnitWatch(pet)
		pet.UNIT_PET(pet, "UNIT_PET", "player")
		assert.is_false(pet:IsShown())
		assert.equals(2, #updates)
		present = true
		RegisterUnitWatch(pet)
		pet.PLAYER_ENTERING_WORLD(pet, "PLAYER_ENTERING_WORLD")
		assert.same({ "PLAYER_ENTERING_WORLD", "pet" }, updates[3])
	end)
end)
