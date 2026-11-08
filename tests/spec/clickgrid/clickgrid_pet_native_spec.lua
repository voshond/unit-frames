local Helpers = require("helpers")
local Mock = Helpers.Mock

local function Read(path)
	local file = io.open(path)
	if not file then return nil end
	local text = file:read("*a")
	file:close()
	return text
end

describe("ClickGrid native pet assignment", function()
	it("uses Blizzard token normalization and oUF child updates through owner replacement in combat", function()
		local source = Read("examples/wow-ui-source-forever/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua")
		if not source then return end
		local UF, CG = Helpers.LoadClickGrid()
		CG.Config:SetStyle("pet", "display", "inline")
		local cell = CG.headers.party:GetAttribute("child1")
		local pet = cell.Pet
		local environment = setmetatable({
			CopyTable = function(value) return value end,
			GetFrameMetatable = function()
				return { __index = {
					GetAttribute = function(frame, prefix, name, suffix)
						return frame:GetAttribute(name and prefix .. name .. (suffix or "") or prefix)
					end,
					GetParent = function(frame) return frame:GetParent() end,
				} }
			end,
			UnitHasVehicleUI = function() return false end,
			IsShiftKeyDown = function() return false end,
			IsControlKeyDown = function() return false end,
			IsAltKeyDown = function() return false end,
			gsub = string.gsub,
		}, { __index = _G })
		local helpers = assert(loadstring(assert(source:match("^(.-)function SecureButton_GetEffectiveButton"))))
		setfenv(helpers, environment)
		helpers()
		local native = { Private = {
			unitExists = function(unit) return unit ~= nil end,
			UpdateUnits = function(frame, unit, real)
				local changed = frame.__unit ~= unit
				frame.__unit, frame.__realUnit = unit, real
				return changed
			end,
		} }
		local oufSource = Read("UnitFrames/Libs/oUF/ouf.lua")
		local prefix = assert(oufSource:match("^(.-)local frame_metatable"))
		local chunk = assert(loadstring(prefix .. "\nreturn onAttributeChanged"))
		setfenv(chunk, environment)
		local changed = chunk("UnitFrames", { oUF = native })
		cell.hasChildren = true
		Mock.inCombat = true
		local count = #CG.frames
		for _, owner in ipairs({ "raid22", "party3", "player" }) do
			Mock.RunUntainted(function()
				cell:SetAttribute("unit", owner)
				changed(cell, "unit", owner)
			end)
			assert.equals(CG.PetUnit(owner), pet.__unit)
			assert.equals(CG.PetUnit(owner), environment.SecureButton_GetModifiedUnit(pet))
		end
		assert.equals(count, #CG.frames)
		assert.equals(UF.oUF, CG.UF.oUF)
		local driverSource = Read("examples/wow-ui-source-forever/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua")
		local driverPrefix = assert(driverSource:match("^(.-)local function resolveDriver"))
		local driver = assert(loadstring(driverPrefix .. "\nreturn SecureStateDriverManager_UpdateUnitWatch, unitExistsCache"))
		local present = false
		environment.UnitExists = function(unit)
			assert.equals("playerpet", unit)
			return present
		end
		environment.UnitIsVisible = function() return false end
		setfenv(driver, environment)
		local watch, cache = driver()
		for _, exists in ipairs({ false, true, false }) do
			present = exists
			wipe(cache)
			Mock.RunUntainted(watch, pet, false)
			assert.equals(exists, pet:IsShown())
			assert.equals(CG.metrics.member.width - (exists and CG.metrics.pet.width + CG.metrics.pet.gap or 0),
				cell.Member.uf:GetRow("health"):GetBar():GetKnownSize())
		end
	end)
end)
