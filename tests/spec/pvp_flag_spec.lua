local Helpers = require("helpers")
local Mock = Helpers.Mock

local ATLASES = {
	Alliance = "UI-HUD-UnitFrame-SmallCircle-Alliance",
	Horde = "UI-HUD-UnitFrame-SmallCircle-Horde",
	FFA = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
}

local function Flag(atlas)
	return " |A:" .. atlas .. ":0:0:0:0|a"
end

describe("PvP flags beside level and class", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		UnitLevel = function() return 42 end
		UnitClass = function() return "Mage", "MAGE" end
		UnitClassification = function() return "normal" end
	end)

	it("adds the native Alliance, Horde or FFA icon to both identity formats", function()
		for _, id in ipairs({ "level:class", "level:info" }) do
			for _, atlas in pairs(ATLASES) do
				Mock.pvpInfo.target = { pvpIconAtlas = atlas }
				assert.equals("42 Mage" .. Flag(atlas), ns.Formats.Get(id).text("target"))
			end
		end
	end)

	it("removes the flag without leftover markup or spacing when PvP ends", function()
		for _, id in ipairs({ "level:class", "level:info" }) do
			Mock.pvpInfo.player = { pvpIconAtlas = ATLASES.Horde }
			assert.equals("42 Mage" .. Flag(ATLASES.Horde), ns.Formats.Get(id).text("player"))
			Mock.pvpInfo.player = { pvpIconAtlas = "" }
			assert.equals("42 Mage", ns.Formats.Get(id).text("player"))
		end
	end)

	it("lets Blizzard determine mercenary flags instead of deriving them from a faction", function()
		UnitFactionGroup = function() error("the addon must not derive a live PvP flag from faction") end
		local called
		UnitFrameUtil.GetUnitPvPIndicatorDisplayInfo = function(unit, checkMercenary)
			called = unit
			assert.is_true(checkMercenary)
			return { pvpIconAtlas = ATLASES.Horde, showPvPIcon = Secret(true) }
		end
		assert.equals("42 Mage" .. Flag(ATLASES.Horde), ns.Formats.Get("level:class").text("target"))
		assert.equals("target", called)
	end)

	it("preserves NPC elite markers and creature type beside a PvP flag", function()
		UnitIsPlayer = function() return false end
		UnitCreatureType = function() return "Humanoid" end
		UnitClassification = function() return "elite" end
		Mock.pvpInfo.target = { pvpIconAtlas = ATLASES.Alliance }
		assert.equals("42+ Humanoid" .. Flag(ATLASES.Alliance), ns.Formats.Get("level:info").text("target"))
	end)

	it("passes secret atlas names and identity text through native formatting", function()
		for _, id in ipairs({ "level:class", "level:info" }) do
			for _, atlas in ipairs({ "", ATLASES.Alliance, ATLASES.FFA }) do
				Mock.pvpInfo.target = { pvpIconAtlas = Secret(atlas), showPvPIcon = Secret(atlas ~= "") }
				assert.is_true(Mock.IsSecret(ns.Formats.Get(id).text("target")), id)
			end
		end
		UnitClass = function() return Secret("Mage"), "MAGE" end
		Mock.pvpInfo.target = { pvpIconAtlas = ATLASES.Horde }
		assert.is_true(Mock.IsSecret(ns.Formats.Get("level:class").text("target")))
	end)

	it("skips PvP data for absent targets and follows the new unit when it returns", function()
		UnitExists = function() return false end
		UnitFrameUtil.GetUnitPvPIndicatorDisplayInfo = function() error("missing unit") end
		assert.equals("", ns.Formats.Get("level:class").text("target"))
		assert.equals("", ns.Formats.Get("level:info").text("target"))
		Mock.InstallUI()
		UnitClass = function() return "Mage", "MAGE" end
		Mock.pvpInfo.target = { pvpIconAtlas = ATLASES.FFA }
		assert.equals("30+ Mage" .. Flag(ATLASES.FFA), ns.Formats.Get("level:info").text("target"))
	end)

	it("subscribes both tags to faction/PvP updates and keeps other formats unchanged", function()
		for _, id in ipairs({ "level:class", "level:info" }) do
			for _, event in ipairs({ "UNIT_FACTION", "PLAYER_PVP_FLAG_CHANGED", "PLAYER_REGEN_ENABLED" }) do
				assert.is_not_nil(ns.oUF.Tags.Events["uf:" .. id]:find(event, 1, true), id .. ": " .. event)
			end
		end
		assert.is_true(ns.oUF.Tags.SharedEvents.PLAYER_PVP_FLAG_CHANGED)
		assert.is_true(ns.oUF.Tags.SharedEvents.PLAYER_REGEN_ENABLED)
		assert.is_nil(ns.oUF.Tags.SharedEvents.UNIT_FACTION, "UNIT_FACTION must still filter by unit")
		Mock.pvpInfo.player = { pvpIconAtlas = ATLASES.Alliance }
		assert.equals(42, ns.Formats.Get("level").text("player"))
		assert.equals("Mage", ns.Formats.Get("class").text("player"))
	end)
end)

describe("PvP flag Workbench previews", function()
	it("previews each flag on every frame in static and animated modes", function()
		local ns, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		for _, unit in ipairs(ns.Units.order) do
			wb:Select("unit." .. unit)
			wb.styleTarget.set("health.belowLeft.enabled", true)
			local text = wb.handle.parts.uf:GetRow("health"):GetText("belowLeft"):GetFrame()
			local plain = text:GetText()
			for _, source in ipairs({ "static", "animated" }) do
				wb.dataTarget.set("source", source)
				for state, atlas in pairs(ATLASES) do
					wb.dataTarget.set("pvp", state)
					assert.equals(plain .. Flag(atlas), text:GetText(), unit .. ": " .. state)
				end
				wb.dataTarget.set("pvp", "off")
				assert.equals(plain, text:GetText())
			end
			assert.is_nil(ns.Config:GetUnitConfig(unit).pvp, "preview data does not change live PvP settings")
		end
	end)
end)
