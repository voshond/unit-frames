local Helpers = require("helpers")

describe("Shared row definitions", function()
	it("owns independent specs and preserves consumer text defaults", function()
		local ns = Helpers.LoadAddon(true)
		local standalone = ns.UnitRows.Spec("health", { left = "name", right = "health:value" })
		standalone.segments[2].mode = "append"
		standalone.textDefaults.left = "none"
		local unit = ns.UnitRows.Spec("health")
		assert.equals("overlay", unit.segments[2].mode)
		assert.equals("name", unit.textDefaults.left)
		assert.equals("level:class", unit.textDefaults.belowLeft.format)
		assert.is_false(unit.textDefaults.belowLeft.enabled)
		assert.is_nil(ns.UnitRows.Spec("health", { left = "name" }).textDefaults.belowLeft)
		assert.equals("xp:value:percent", ns.UnitRows.Spec("experience").textDefaults.center)
	end)
end)
