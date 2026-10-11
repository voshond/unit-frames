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

describe("Live row writers", function()
	local Mock = Helpers.Mock

	local function Row(ns, key, config)
		return ns.Components.TextBar:New(CreateFrame("Frame"), config or {}, ns.UnitRows.Spec(key))
	end

	it("reads every health value from the native calculator, never a nilable direct API", function()
		local ns = Helpers.LoadAddon(true)
		Mock.InstallUI()
		_G.UnitGetIncomingHeals = function() return nil end -- documented as nilable
		local row = Row(ns, "health", { bar = { segments = { absorb = { placement = "append" } } } })
		local calculator = CreateUnitHealPredictionCalculator()
		ns.UnitRows.LiveHealth(row, "player", calculator, "class")
		local bar = row:GetBar()
		assert.equals(Enum.UnitMaximumHealthMode.WithAbsorbs, calculator.maximumMode)
		assert.equals(Enum.UnitDamageAbsorbClampMode.MaximumHealth, calculator.damageAbsorbMode)
		assert.equals(1100, bar.bar.__state.max.secretValue, "health plus appended shields")
		assert.equals(500, bar.bar.__state.value.secretValue)
		assert.is_true(Mock.IsSecret(bar.segmentsByKey.heal.bar.__state.value))
		assert.equals(0, bar.segmentsByKey.heal.bar.__state.value.secretValue)
		assert.equals(100, bar.segmentsByKey.absorb.bar.__state.value.secretValue)
	end)

	it("clears a sample spell cost when switching power to a live unit", function()
		local ns = Helpers.LoadAddon(true)
		Mock.InstallUI()
		local row = Row(ns, "power")
		ns.UnitRows.SamplePower(row, ns.Units.SAMPLE)
		ns.UnitRows.LivePower(row, "player")
		assert.equals(0, row:GetBar().segmentsByKey.cost.bar.__state.value)
	end)
end)
