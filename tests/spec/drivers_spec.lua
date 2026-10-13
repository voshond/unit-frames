local Helpers = require("helpers")
local Mock = Helpers.Mock

-- Mock-only engine oracle: production Lua must never read a secret alpha.
local function Alpha(frame)
	local alpha = frame:GetAlpha()
	if Mock.IsSecret(alpha) then return alpha.secretValue end
	return alpha
end

describe("Unit data drivers", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true)
		Mock.InstallUI()
	end)

	local function CheckDriver(name, driver)
		for _, source in ipairs({ "bind", "sample", "live" }) do
			local kind = type(driver[source])
			assert.is_true(kind == "function" or driver[source] == false,
				name .. " declares its " .. source .. " source (a function, or false with a reason)")
		end
		if driver.bind then assert.equals("string", type(driver.element), name .. " names its oUF element") end
	end

	it("declare live, sample and polled sources for every row, part and frame state", function()
		local Drivers = ns.UnitDrivers
		for _, part in ipairs(ns.Components.UnitFrame.PARTS) do
			CheckDriver("part " .. part.key, Drivers.Part(part.key))
		end
		for _, unit in ipairs(ns.Units.order) do
			for _, row in ipairs(ns.Units:GetDefinition(unit).rows) do
				CheckDriver("row " .. row.key, Drivers.Row(row.key))
			end
		end
		for _, driver in ipairs(Drivers.frame) do
			CheckDriver("frame " .. driver.key, driver)
			assert.equals(driver, Drivers.frame[driver.key])
		end
		assert.has_error(function() Drivers.Part("unknown") end)
	end)

	local function Preview(unit, config)
		return ns.Units:CreateFromDefinition(ns.Units:GetDefinition(unit), UIParent, config)
	end

	it("polls an explicit unit through the same range rules as the oUF element", function()
		local uf = Preview("target", { range = { enabled = true, mode = "spell", spell = " 133 " } })
		Mock.ranges.party1 = { inRange = true, checked = true }
		Mock.spellRanges[133] = { party1 = false }
		ns.Units:ShowLive(uf, "party1", {})
		assert.equals(0.55, Alpha(uf:GetFrame()), "spell mode, not group range")

		uf:Apply({ range = { enabled = true } })
		ns.Caps.groupRange = false
		UnitInRange = function() error("unsupported API used") end
		ns.Units:ShowLive(uf, "party1", {})
		assert.equals(1, Alpha(uf:GetFrame()), "unavailable group range is unchecked")
	end)

	it("polls enabled rows and parts, reusing the caller's heal calculator", function()
		local uf = Preview("target", { power = { enabled = false } })
		local power = uf:GetRow("power"):GetBar()
		local before = power.bar.__state.value
		Mock.raidTargets = { focus = 3 }
		local ctx = {}
		ns.Units:ShowLive(uf, "focus", ctx)
		local calculator = assert(ctx.calculator)
		ns.Units:ShowLive(uf, "focus", ctx)
		assert.equals(calculator, ctx.calculator)
		assert.equals("focus", uf:GetPart("portrait").shownUnit)
		local elite = uf:GetPart("classification"):GetWidget()
		assert.equals(ns.Components.Classification.ATLASES.elite, elite.__state.atlas)
		assert.is_true(elite:IsShown())
		assert.is_true(uf:GetPart("raidTarget"):GetWidget():IsShown())
		assert.equals(before, power.bar.__state.value, "a disabled row isn't polled")
	end)
end)
