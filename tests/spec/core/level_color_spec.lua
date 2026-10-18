local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Level difficulty colour", function()
	local ns

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
	end)

	local IMPOSSIBLE = "|cffff1a1a"
	local FAIR = "|cffffd100"

	local function Compile(pieces, levelColor)
		return ns.TextTemplate.Compile({ pieces = pieces, levelColor = levelColor })
	end

	local function BelowLeft()
		return ns.Units.frames.target.uf:GetRow("health"):GetText("belowLeft")
	end

	it("tints only the level piece of attackable units", function()
		local pieces = { { source = "level", before = "L", after = "!" }, { literal = " Warrior" } }
		assert.equals("L30! Warrior", Compile(pieces, true).live("target"), "not attackable: the text's own colour")
		Mock.attackable.target = true
		assert.equals("L" .. FAIR .. "30|r! Warrior", Compile(pieces, true).live("target"))
		Mock.difficulties.target = Enum.RelativeContentDifficulty.Impossible
		assert.equals("L" .. IMPOSSIBLE .. "30|r! Warrior", Compile(pieces, true).live("target"))
		assert.equals(IMPOSSIBLE .. "30+|r", Compile({ { source = "smartlevel" } }, true).live("target"))
		assert.equals("L30! Warrior", Compile(pieces).live("target"), "off by default")
	end)

	it("leaves dead and offline units to their frame look", function()
		local pieces = { { source = "level" } }
		Mock.attackable.target = true
		Mock.dead.target = true
		assert.equals(30, Compile(pieces, true).live("target"), "dead")
		Mock.dead.target = nil
		Mock.ghosts.target = true
		assert.equals(30, Compile(pieces, true).live("target"), "ghost")
		Mock.ghosts.target = nil
		local connected = UnitIsConnected
		UnitIsConnected = function() return false end
		assert.equals(30, Compile(pieces, true).live("target"), "offline")
		UnitIsConnected = connected
		assert.equals(FAIR .. "30|r", Compile(pieces, true).live("target"))
		assert.is_true(Compile(pieces, true).sharedEvents.PLAYER_DEAD, "follows death and release")
		assert.is_nil(Compile(pieces).sharedEvents)
		local target = ns.Units:GetSample("target")
		target.status = "dead"
		assert.equals("42", Compile(pieces, true).sample(target), "dead sample #workbench")
	end)

	it("updates on attackability changes and compiles apart", function()
		local pieces = { { source = "level" } }
		assert.is_true(Compile(pieces, true).events:find("UNIT_FACTION", 1, true) ~= nil)
		assert.is_nil(Compile(pieces).events:find("UNIT_FACTION", 1, true))
		assert.is_false(ns.TextTemplate.Signature({ pieces = pieces }) == ns.TextTemplate.Signature({ pieces = pieces, levelColor = true }))
		local name = { { source = "name" } }
		assert.equals(ns.TextTemplate.Signature({ pieces = name }), ns.TextTemplate.Signature({ pieces = name, levelColor = true }),
			"texts without a level are unaffected")
	end)

	it("previews hostile samples in their difficulty colour #workbench", function()
		local target = ns.Units:GetSample("target")
		local pieces = { { source = "smartlevel" }, { source = "creatureType", before = " " } }
		assert.equals(IMPOSSIBLE .. "42+|r Humanoid", Compile(pieces, true).sample(target))
		target.level = 31
		assert.equals(FAIR .. "31+|r Humanoid", Compile(pieces, true).sample(target))
		assert.equals("42", Compile({ { source = "level" } }, true).sample(ns.Units:GetSample("pet")), "friendly NPC")
		assert.equals("44", Compile({ { source = "level" } }, true).sample(ns.Units:GetSample("focus")), "player")
	end)

	it("is a slot option for texts that show a level", function()
		local text = BelowLeft()
		local option = ns.Schema.Find(text:GetSchema(), "levelColor")
		assert.is_false(option.default)
		local cfg = text.resolved
		assert.equals("level:info", cfg.format)
		assert.is_false(option.hidden(cfg))
		assert.is_true(option.hidden({ format = "health:value" }))
		assert.is_false(option.hidden({ format = ns.Components.Text.CUSTOM, piece1 = { source = "level" } }))
		assert.is_true(option.hidden({ format = ns.Components.Text.CUSTOM, piece1 = { source = "name" } }))
	end)

	it("is on by default for target, target of target and focus", function()
		local expected = { player = false, pet = false, target = true, targettarget = true, focus = true, focustarget = false }
		for unit, on in pairs(expected) do
			local uf = ns.Units.frames[unit].uf
			for _, row in ipairs({ "health", "power" }) do
				for _, slot in ipairs(ns.Components.TextBar.SLOTS) do
					assert.equals(on, uf:GetRow(row):GetText(slot.key).resolved.levelColor, unit .. " " .. row .. "." .. slot.key)
				end
			end
		end
		assert.is_nil(BelowLeft():GetPresetTag(), "the default level text colours its level")
	end)

	it("moves a preset off its shared tag only while it colours a level", function()
		local text = BelowLeft()
		ns.Config:SetUnitValue("target", "health.belowLeft.levelColor", false)
		ns.Config:SetUnitValue("target", "health.belowLeft.format", "smartlevel")
		assert.equals("smartlevel", text:GetPresetTag())
		ns.Config:SetUnitValue("target", "health.belowLeft.levelColor", true)
		assert.is_nil(text:GetPresetTag())
		Mock.attackable.target = true
		assert.equals(FAIR .. "30+|r", text:GetTemplate().live("target"))
		ns.Config:SetUnitValue("target", "health.belowLeft.format", ns.Components.Text.CUSTOM)
		assert.equals(FAIR .. "30+|r", text:GetTemplate().live("target"), "custom pieces copied from the preset")
		ns.Config:SetUnitValue("target", "health.belowLeft.levelColor", false)
		assert.equals("30+", text:GetTemplate().live("target"))
		ns.Config:SetUnitValue("target", "health.belowLeft.levelColor", true)
		ns.Config:SetUnitValue("target", "health.belowLeft.format", "health:value")
		assert.equals("health:value", text:GetPresetTag(), "nothing to colour")
	end)
end)
