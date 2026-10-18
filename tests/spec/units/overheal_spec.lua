local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Stepped overheal indicator #overheal", function()
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
	local function Row() return ns.Units.frames.player.uf:GetRow("health") end
	local function Set(path, value) ns.Config:SetUnitValue("player", "health.bar.overheal." .. path, value) end
	local function Enable() Set("enabled", true) end

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

	-- Engine oracle: which levels a live update lit (tests alone read secrets).
	local function Lit(overheal)
		local lit = {}
		for index = 1, overheal.count do lit[index] = overheal.levels[index].gate.__state.alpha.secretValue end
		return lit
	end

	local function SampleLit(overheal)
		local lit = {}
		for index = 1, overheal.count do lit[index] = overheal.levels[index].gate.__state.alpha end
		return lit
	end

	local function Sample(health, heal)
		ns.UnitRows.SampleHealth(Row(), { health = health, healthMax = 1000, heal = heal, absorb = 0, healAbsorb = 0 })
	end

	it("is offered on health rows only and off by default, allocating no level artwork", function()
		local schema = ns.Schema.Find(Bar():GetSchema(), "overheal").schema
		assert.equals(3, ns.Schema.Find(schema, "levels").default)
		assert.is_nil(ns.Schema.Find(ns.Units.frames.player.uf:GetRow("power"):GetBar():GetSchema(), "overheal"))
		assert.is_nil(Bar():GetOverheal())
		assert.is_false(Bar().overheal.holder:IsShown())
		assert.same({}, Bar().overheal.levels)
		assert.same({}, Bar().overheal.calculators)
		assert.is_nil(rawget(ns.Units.frames.player.Health, "PostUpdate"))
		assert.is_nil(ns.Config:GetUnitConfig("player").health)
	end)

	it("binds to the oUF health update when enabled and unbinds when disabled", function()
		local health = ns.Units.frames.player.Health
		Enable()
		local overheal = Bar():GetOverheal()
		assert.equals(3, #overheal.levels)
		assert.equals(overheal, health.ufOverheal)
		assert.equals("function", type(rawget(health, "PostUpdate")))
		Set("enabled", false)
		assert.is_nil(Bar():GetOverheal())
		assert.is_nil(rawget(health, "PostUpdate"))
		assert.is_false(overheal.holder:IsShown())
		for _ = 1, 3 do
			Enable()
			Set("enabled", false)
		end
		Enable()
		assert.equals(3, #overheal.levels, "toggling reuses the same widgets")
	end)

	it("gives every level its own missing-health boundary and shares one raw amount", function()
		Enable()
		Health(500, 1000, 50)
		Update()
		local calculators = Bar():GetOverheal().calculators
		assert.equals(Enum.UnitIncomingHealClampMode.MaximumHealth, calculators[0].incomingClampMode)
		for index, threshold in ipairs({ 1, 1.25, 1.5 }) do
			assert.equals(Enum.UnitIncomingHealClampMode.MissingHealth, calculators[index].incomingClampMode)
			assert.equals(threshold, calculators[index].incomingOverflow)
		end
		assert.is_nil(rawget(ns.Units.frames.player.Health, "incomingHealClampMode"), "the shared prediction bar is untouched")
	end)

	it("lights more levels for bigger overheals, without reading secrets", function()
		Enable()
		local overheal = Bar():GetOverheal()
		Health(1000, 1000, 100)
		Update()
		assert.same({ 1, 0, 0 }, Lit(overheal), "a small heal at full health")
		assert.is_true(Mock.IsSecret(overheal.levels[1].gate.__state.alpha), "results stay secret")
		Health(1000, 1000, 251)
		Update()
		assert.same({ 1, 1, 0 }, Lit(overheal), "a heal of over 25% of maximum health")
		Health(1000, 1000, 501)
		Update()
		assert.same({ 1, 1, 1 }, Lit(overheal))
		Health(500, 1000, 500)
		Update()
		assert.same({ 0, 0, 0 }, Lit(overheal), "a heal that exactly fills the bar")
		Health(500, 1000, 750)
		Update()
		assert.same({ 1, 0, 0 }, Lit(overheal), "exactly 25% past full is not past it")
	end)

	it("gates every level on any incoming heal, including at full health and with nothing incoming", function()
		Enable()
		local overheal = Bar():GetOverheal()
		Health(1000, 1000, 0)
		Update()
		for _, level in ipairs(overheal.levels) do
			assert.equals(0, level.fade:GetValue().secretValue, "nothing incoming leaves the artwork empty")
			assert.equals(0, level.light:GetValue().secretValue)
		end
		Health(1000, 1000, 80)
		Update()
		for _, level in ipairs(overheal.levels) do
			assert.equals(80, level.fade:GetValue().secretValue)
			assert.equals(80, level.light:GetValue().secretValue)
			assert.equals(1, select(2, level.fade:GetMinMaxValues()))
		end
	end)

	it("runs only as many predictions as levels are shown", function()
		Set("levels", 1)
		Enable()
		Health(1000, 1000, 600)
		Update()
		local overheal = Bar():GetOverheal()
		assert.equals(1, overheal.count)
		assert.is_nil(overheal.calculators[2])
		assert.is_nil(overheal.levels[2], "unused levels are never built")
		Set("levels", 3)
		assert.equals(3, #overheal.levels)
		Set("levels", 2)
		assert.is_false(overheal.levels[3].gate:IsShown())
		assert.equals(0, overheal.levels[3].gate.__state.alpha)
	end)

	it("pins longer fades for stronger levels inside the bar's end, the edge light past it", function()
		Enable()
		Set("length", 60)
		local overheal = Bar():GetOverheal()
		local outward = { HORIZONTAL = { [false] = { 1, 0 }, [true] = { -1, 0 } }, VERTICAL = { [false] = { 0, 1 }, [true] = { 0, -1 } } }
		for _, orientation in ipairs({ "HORIZONTAL", "VERTICAL" }) do
			for _, reverse in ipairs({ false, true }) do
				Bar():Apply({ orientation = orientation, reverseFill = reverse, overheal = { enabled = true, length = 60 } })
				local out = outward[orientation][reverse]
				local inset = ns.Components.Bar.LAYOUT[orientation][reverse].inset
				local function Length(switch) return orientation == "HORIZONTAL" and switch:GetWidth() or switch:GetHeight() end
				for index, reach in ipairs({ 21, 39, 60 }) do
					local level = overheal.levels[index]
					for _, pair in ipairs(inset) do
						assert.same({ pair[1], Bar().bar, pair[2], 0, 0 }, level.fade:GetAnchor(pair[1]))
						assert.same({ pair[1], Bar().bar, pair[2], out[1] * 9, out[2] * 9 }, level.light:GetAnchor(pair[1]))
					end
					assert.equals(reach, Length(level.fade))
					assert.equals(16, Length(level.light))
					assert.equals(level.fade:GetStatusBarTexture(), select(2, level.paint:GetPoint(1)))
					assert.equals(level.light:GetStatusBarTexture(), select(2, level.strip:GetPoint(1)))
					-- Transparent away from the end, coloured at it.
					local gradient = level.paint.__state.gradient
					assert.equals(orientation, gradient[1])
					local atEnd = reverse and gradient[2] or gradient[3]
					local away = reverse and gradient[3] or gradient[2]
					assert.equals(0, away[4])
					assert.is_true(atEnd[4] > 0)
				end
				assert.equals(Bar().overlay, overheal.holder:GetParent(), "not the clipping frame")
			end
		end
	end)

	it("paints over the bar and adds Blizzard's edge atlas, brighter with every level", function()
		Enable()
		Set("color", { 0.2, 0.6, 1, 1 })
		local overheal = Bar():GetOverheal()
		local previous = 0
		for index, def in ipairs(ns.Overheal.LEVELS) do
			local level = overheal.levels[index]
			assert.equals("RaidFrame-Shield-Overshield", level.strip.__state.atlas)
			assert.equals("ADD", level.strip.__state.blendMode)
			assert.is_true(level.strip.__state.desaturated)
			assert.same({ 0.2, 0.6, 1, def.light }, level.strip.__state.vertexColor)
			assert.is_nil(level.paint.__state.blendMode, "painted, not added: visible on pale bars")
			assert.is_true(def.reach > previous)
			previous = def.reach
		end
		Set("edge", false)
		for _, level in ipairs(overheal.levels) do assert.is_false(level.strip:IsShown()) end
		local points = overheal.levels[1].fade:GetNumPoints()
		Bar():Apply(Bar().config)
		Bar():Apply(Bar().config)
		assert.equals(points, overheal.levels[1].fade:GetNumPoints())
	end)

	it("uses the atlas's own coordinates, mirrored or rotated for other bar ends", function()
		Mock.atlasInfo["RaidFrame-Shield-Overshield"] = { width = 16, height = 64, uv = { 0.25, 0.5, 0.1, 0.9 } }
		Enable()
		local strip = Bar():GetOverheal().levels[1].strip
		local function Coords(orientation, reverse)
			Bar():Apply({ orientation = orientation, reverseFill = reverse, overheal = { enabled = true } })
			return strip.__state.texCoords
		end
		assert.same({ 0.5, 0.25, 0.1, 0.9 }, Coords("HORIZONTAL", true))
		assert.same({ 0.5, 0.1, 0.25, 0.1, 0.5, 0.9, 0.25, 0.9 }, Coords("VERTICAL", false))
		assert.same({ 0.25, 0.1, 0.5, 0.1, 0.25, 0.9, 0.5, 0.9 }, Coords("VERTICAL", true))
		local call
		for _, entry in ipairs(strip.__calls) do
			if entry[1] == "SetAtlas" then call = entry end
		end
		assert.is_false(call[3], "the strip keeps the size it is anchored to")
		Mock.atlasInfo["RaidFrame-Shield-Overshield"] = nil
	end)

	it("steps plain samples through the same widgets", function()
		Enable()
		local overheal = Bar():GetOverheal()
		Sample(900, 150)
		assert.same({ 1, 0, 0 }, SampleLit(overheal))
		assert.equals(150, overheal.levels[1].fade:GetValue())
		Sample(900, 400)
		assert.same({ 1, 1, 0 }, SampleLit(overheal))
		Sample(1000, 600)
		assert.same({ 1, 1, 1 }, SampleLit(overheal))
		Sample(900, 100)
		assert.same({ 0, 0, 0 }, SampleLit(overheal), "an exact fill is not overheal")
		Sample(1000, 0)
		assert.same({ 0, 0, 0 }, SampleLit(overheal))
	end)

	it("updates polled live previews from their own calculators", function()
		Enable()
		local overheal = Bar():GetOverheal()
		Health(990, 1000, 300)
		ns.UnitRows.LiveHealth(Row(), "player", CreateUnitHealPredictionCalculator(), "theme")
		assert.same({ 1, 1, 0 }, Lit(overheal))
		assert.equals(300, overheal.levels[1].fade:GetValue().secretValue)
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
