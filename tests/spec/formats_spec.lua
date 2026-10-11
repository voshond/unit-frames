local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Live text formats", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
	end)

	it("returns empty text for absent units, including explicit settings refreshes", function()
		UnitExists = function(unit) return unit == "player" end
		UnitName = function() return nil end
		UnitClass = function() return nil end
		UnitLevel = function() return nil end
		UnitCreatureType = function() return nil end
		for _, unit in ipairs({ "target", "focus", "pet", "targettarget" }) do
			for _, format in ipairs(ns.Formats.list) do
				assert.equals("", format.text(unit), unit .. ": " .. format.id)
				assert.equals("", ns.oUF.Tags.Methods["uf:" .. format.id](unit), unit .. " tag: " .. format.id)
			end
		end
	end)

	it("tolerates missing identity data even when the unit exists", function()
		UnitName = function() return nil end
		UnitClass = function() return nil end
		UnitLevel = function() return 42 end
		UnitClassification = function() return "normal" end
		for _, id in ipairs({ "level:name", "level:class", "level:info" }) do
			assert.equals("42 ", ns.Formats.Get(id).text("target"), id)
		end
		UnitIsPlayer = function() return false end
		UnitCreatureType = function() return nil end
		assert.equals("42 ", ns.Formats.Get("level:info").text("target"))
	end)

	it("handles slider refreshes with no target and resumes text when the target returns", function()
		local exists = false
		UnitExists = function(unit) return unit ~= "target" or exists end
		UnitName = function() return exists and "Jaina" or nil end
		UnitClass = function() if exists then return "Mage", "MAGE" end end
		UnitLevel = function() return exists and 44 or nil end
		local frame = ns.Units.frames.target
		-- The regular oUF mock only records UpdateTags. Evaluate its bound
		-- formats here, as the real explicit refresh does even on hidden frames.
		frame.UpdateTags = function(self)
			for fs, tag in pairs(self.tags) do
				local id = tag:match("^%[uf:(.+)%]$")
				fs:SetText(ns.oUF.Tags.Methods["uf:" .. id](self.__unit))
			end
		end
		assert.has_no_error(function()
			ns.Config:SetUnitValue("target", "health.left.format", "level:name")
			ns.Config:SetUnitValue("target", "health.belowLeft.enabled", true)
			ns.Config:SetUnitValue("target", "health.belowLeft.format", "level:class")
			ns.Config:SetUnitValue("target", "raidTarget.offsetX", 5)
		end)
		local info = frame.uf:GetRow("health"):GetText("belowLeft"):GetFrame()
		assert.equals("", info:GetText())
		exists = true
		frame:UpdateTags()
		assert.equals("44 Mage", info:GetText())
		exists = false
		ns.Config:SetUnitValue("target", "raidTarget.offsetX", 6)
		assert.equals("", info:GetText())
	end)

	it("keeps secret identity values opaque for existing units", function()
		UnitName = function() return Secret("Jaina") end
		UnitClass = function() return Secret("Mage"), "MAGE" end
		for _, id in ipairs({ "name", "class", "level:name", "level:class", "level:info" }) do
			assert.is_true(Mock.IsSecret(ns.Formats.Get(id).text("target")), id)
		end
	end)
end)
