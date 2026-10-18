local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Overheal edge indicator #overheal", function()
	local ns, saved

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		-- The engine's heal prediction calculators and unit data.
		Mock.InstallUI()
		saved = { UnitHealth = UnitHealth, UnitHealthMax = UnitHealthMax, UnitGetIncomingHeals = UnitGetIncomingHeals }
	end)

	after_each(function()
		for name, fn in pairs(saved) do _G[name] = fn end
	end)

	local function Bar(unit) return ns.Units.frames[unit or "player"].uf:GetRow("health"):GetBar() end
	local function Enable(path, value) ns.Config:SetUnitValue("player", "health.bar.overheal." .. (path or "enabled"), value == nil or value) end

	-- Secret health values, as in combat: the mock engine fills its calculators from these.
	local function Health(current, max, heal)
		_G.UnitHealth = function() return Mock.Secret(current) end
		_G.UnitHealthMax = function() return Mock.Secret(max) end
		_G.UnitGetIncomingHeals = function() return Mock.Secret(heal) end
	end

	local function Update()
		local health = ns.Units.frames.player.Health
		health:PostUpdate("player")
	end

	local function GateAlpha(overheal) return overheal.gate.__state.alpha.secretValue end
	local function Filled(overheal) return overheal.switch:GetValue().secretValue end

	it("is offered on health rows only and is off by default, creating nothing live", function()
		assert.is_not_nil(ns.Schema.Find(ns.Schema.Find(Bar():GetSchema(), "overheal").schema, "threshold"))
		assert.is_nil(ns.Schema.Find(ns.Units.frames.player.uf:GetRow("power"):GetBar():GetSchema(), "overheal"))
		assert.is_nil(Bar():GetOverheal())
		assert.is_false(Bar().overheal.gate:IsShown())
		assert.is_nil(rawget(ns.Units.frames.player.Health, "PostUpdate"))
		assert.is_nil(Bar().overheal.overflow, "calculators are created on first update")
		assert.is_nil(ns.Config:GetUnitConfig("player").health)
	end)

	it("binds to the oUF health update when enabled and unbinds when disabled", function()
		local health = ns.Units.frames.player.Health
		Enable()
		local overheal = Bar():GetOverheal()
		assert.is_true(Bar().overheal.gate:IsShown())
		assert.equals(overheal, health.ufOverheal)
		assert.equals("function", type(rawget(health, "PostUpdate")))
		Enable("enabled", false)
		assert.is_nil(Bar():GetOverheal())
		assert.is_nil(rawget(health, "PostUpdate"))
		assert.is_false(Bar().overheal.gate:IsShown())
		assert.equals(0, Bar().overheal.gate.__state.alpha)
		for _ = 1, 3 do
			Enable()
			Enable("enabled", false)
		end
		Enable()
		assert.equals(overheal, Bar():GetOverheal(), "toggling reuses the same widgets")
	end)

	it("configures its two native calculators: missing health at the threshold, and maximum health", function()
		Enable()
		Health(500, 1000, 50)
		Update()
		local overheal = Bar():GetOverheal()
		assert.equals(Enum.UnitIncomingHealClampMode.MissingHealth, overheal.overflow.incomingClampMode)
		assert.equals(1, overheal.overflow.incomingOverflow)
		assert.equals(Enum.UnitIncomingHealClampMode.MaximumHealth, overheal.raw.incomingClampMode)
		local created = overheal.overflow
		Enable("threshold", 1.25)
		assert.equals(1.25, overheal.overflow.incomingOverflow)
		assert.equals(created, overheal.overflow, "a threshold change reconfigures the calculator")
		assert.is_nil(rawget(ns.Units.frames.player.Health, "incomingHealClampMode"), "the shared prediction bar is untouched")
	end)

	it("lights the edge only when the heal passes the threshold, without reading secrets", function()
		Enable()
		local overheal = Bar():GetOverheal()
		Health(500, 1000, 500)
		Update()
		assert.equals(0, GateAlpha(overheal), "exactly full is not past full")
		Health(500, 1000, 501)
		Update()
		assert.equals(1, GateAlpha(overheal))
		assert.is_true(Mock.IsSecret(overheal.gate.__state.alpha), "the result stays secret")
		Enable("threshold", 1.1)
		Health(500, 1000, 601)
		Update()
		assert.equals(1, GateAlpha(overheal))
		Health(500, 1000, 600)
		Update()
		assert.equals(0, GateAlpha(overheal), "exactly 10% of maximum health past full is not past it")
	end)

	it("gates on any incoming heal, including at full health and with nothing incoming", function()
		Enable()
		local overheal = Bar():GetOverheal()
		Health(1000, 1000, 0)
		Update()
		assert.equals(0, Filled(overheal), "nothing incoming leaves the strip empty")
		Health(1000, 1000, 80)
		Update()
		assert.equals(1, GateAlpha(overheal))
		assert.equals(80, Filled(overheal), "the amount is not clamped to the missing health")
		local _, max = overheal.switch:GetMinMaxValues()
		assert.equals(1, max)
	end)

	it("anchors the strip to the whole bar's end for every orientation and fill direction", function()
		Enable()
		local overheal = Bar():GetOverheal()
		for _, orientation in ipairs({ "HORIZONTAL", "VERTICAL" }) do
			for _, reverse in ipairs({ false, true }) do
				Bar():Apply({ orientation = orientation, reverseFill = reverse, overheal = { enabled = true, size = 12 } })
				for _, pair in ipairs(ns.Components.Bar.LAYOUT[orientation][reverse].inset) do
					assert.same({ pair[1], Bar().bar, pair[2], 0, 0 }, overheal.switch:GetAnchor(pair[1]))
				end
				assert.equals(12, orientation == "HORIZONTAL" and overheal.switch:GetWidth() or overheal.switch:GetHeight())
				assert.equals(orientation, overheal.switch.__state.orientation)
				local coords = overheal.strip.__state.texCoords
				assert.equals(orientation == "HORIZONTAL" and 4 or 8, #coords)
				assert.equals(overheal.switch:GetStatusBarTexture(), select(2, overheal.strip:GetPoint(1)))
				assert.equals(overheal.switch:GetStatusBarTexture(), select(2, overheal.strip:GetPoint(2)))
			end
		end
	end)

	it("draws Blizzard's shield overflow artwork additively, tinted, and applies repeatedly", function()
		Enable()
		Enable("color", { 0.2, 0.6, 1, 0.5 })
		local overheal = Bar():GetOverheal()
		assert.equals([[Interface\RaidFrame\Shield-Overshield]], overheal.strip:GetTexture())
		assert.equals("ADD", overheal.strip.__state.blendMode)
		assert.is_true(overheal.strip.__state.desaturated)
		assert.same({ 0.2, 0.6, 1, 0.5 }, overheal.strip.__state.vertexColor)
		local points = overheal.switch:GetNumPoints()
		Bar():Apply(Bar().config)
		Bar():Apply(Bar().config)
		assert.equals(points, overheal.switch:GetNumPoints())
	end)

	it("shows plain samples through the same widgets", function()
		Enable()
		local overheal = Bar():GetOverheal()
		ns.UnitRows.SampleHealth(ns.Units.frames.player.uf:GetRow("health"), { health = 900, healthMax = 1000, heal = 200,
			absorb = 0, healAbsorb = 0 })
		assert.equals(1, overheal.gate.__state.alpha)
		assert.equals(200, overheal.switch:GetValue())
		ns.UnitRows.SampleHealth(ns.Units.frames.player.uf:GetRow("health"), { health = 900, healthMax = 1000, heal = 100,
			absorb = 0, healAbsorb = 0 })
		assert.equals(0, overheal.gate.__state.alpha, "an exact fill is not overheal")
		ns.UnitRows.SampleHealth(ns.Units.frames.player.uf:GetRow("health"), { health = 1000, healthMax = 1000, heal = 0,
			absorb = 0, healAbsorb = 0 })
		assert.equals(0, overheal.gate.__state.alpha)
	end)

	it("updates polled live previews from their own calculators", function()
		Enable()
		local overheal = Bar():GetOverheal()
		Health(990, 1000, 120)
		ns.UnitRows.LiveHealth(ns.Units.frames.player.uf:GetRow("health"), "player", CreateUnitHealPredictionCalculator(), "theme")
		assert.equals(1, GateAlpha(overheal))
		assert.equals(120, Filled(overheal))
	end)

	it("keeps the stock health prediction and shield behaviour unchanged", function()
		local health = ns.Units.frames.player.Health
		local before = { health.maximumHealthClampMode, health.damageAbsorbClampMode }
		Enable()
		assert.same(before, { health.maximumHealthClampMode, health.damageAbsorbClampMode })
		assert.equals(Enum.UnitDamageAbsorbClampMode.MaximumHealth, health.damageAbsorbClampMode)
		assert.is_not_nil(health.HealingAll)
		assert.is_not_nil(health.DamageAbsorb)
	end)
end)
