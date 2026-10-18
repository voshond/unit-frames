local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Dead and offline value texts", function()
	local ns, saved

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		saved = { UnitIsConnected = UnitIsConnected, UnitIsDeadOrGhost = UnitIsDeadOrGhost }
		UnitName = function() return "Jaina", "Realm" end
		UnitHealth = function() return 1 end
		UnitHealthMax = function() return 82 end
		UnitHealthPercent = function() return 1 end
	end)

	after_each(function()
		for name, fn in pairs(saved) do _G[name] = fn end
	end)

	local function Live(id) return ns.Formats.Get(id).text("party1") end
	local function Compile(pieces, whileStatus)
		return ns.TextTemplate.Compile({ pieces = pieces, whileStatus = whileStatus })
	end

	it("replace health presets with Dead or Offline and empty power presets", function()
		local alive = Live("health:value")
		assert.is_true(alive ~= "Dead")
		Mock.ghosts.party1 = true
		assert.equals("Dead", Live("health:value"), "the separator disappears with the maximum")
		assert.equals("Dead", Live("health:value:percent"))
		assert.equals("Dead", ns.oUF.Tags.Methods["uf:health:percent"]("party1"))
		assert.equals("", Live("power:value"))
		assert.equals("Jaina", Live("name"), "identity texts keep their values")
		UnitIsConnected = function() return false end
		assert.equals("Offline", Live("health:value"))
		Mock.ghosts.party1 = nil
		UnitIsConnected = saved.UnitIsConnected
		assert.equals(alive, Live("health:value"))
	end)

	it("keep the other pieces of a custom text and follow its setting", function()
		local pieces = { { source = "name" }, { source = "health.percent", before = " " }, { source = "power.current", before = " | " } }
		Mock.dead.party1 = true
		assert.equals("Jaina Dead", Compile(pieces).live("party1"))
		assert.is_true(Compile(pieces, "keep").live("party1") ~= "Jaina Dead", "kept values")
		assert.is_false(ns.TextTemplate.Signature({ pieces = pieces }) == ns.TextTemplate.Signature({ pieces = pieces, whileStatus = "keep" }))
		local withStatus = { { source = "health.percent" }, { source = "status", before = " " } }
		assert.equals("1% Dead", Compile(withStatus).live("party1"), "a text showing the status itself keeps its values")
		assert.equals("", Compile({ { source = "power.current" } }).live("party1"))
		assert.is_true(Compile({ { source = "power.current" } }).sharedEvents.PLAYER_ALIVE)
		assert.is_nil(Compile({ { source = "name" } }).sharedEvents, "texts without values add no events")
	end)

	it("count opaque states as alive", function()
		UnitIsDeadOrGhost = function() return Mock.Secret(true) end
		UnitIsConnected = function() return Mock.Secret(false) end
		assert.is_true(Live("health:value") ~= "Dead")
	end)

	it("preview through the sample status #workbench", function()
		local values = ns.Units:GetSample("player")
		values.status = "dead"
		assert.equals("Dead", ns.Formats.Get("health:value").sample(values))
		assert.equals("", ns.Formats.Get("power:value").sample(values))
		values.status = "offline"
		assert.equals("Offline", ns.Formats.Get("health:percent").sample(values))
		values.status = nil
		assert.is_true(ns.Formats.Get("health:value").sample(values) ~= "Offline")
	end)

	it("is a custom slot option, written as on when a preset becomes custom", function()
		local text = ns.Units.frames.target.uf:GetRow("health"):GetText("right")
		local option = ns.Schema.Find(text:GetSchema(), "whileStatus")
		assert.equals("status", option.default)
		ns.Config:SetUnitValue("target", "health.right.format", ns.Components.Text.CUSTOM)
		assert.equals("status", ns.Config:GetUnitConfig("target").health.right.whileStatus)
		Mock.dead.target = true
		assert.equals("Dead", text:GetTemplate().live("target"))
		ns.Config:SetUnitValue("target", "health.right.whileStatus", "keep")
		assert.is_true(text:GetTemplate().live("target") ~= "Dead")
	end)
end)
