local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("After-combat queue", function()
	local ns, runs
	before_each(function()
		ns = Helpers.LoadAddon(true)
		runs = {}
	end)

	local function Record(name)
		return function() runs[#runs + 1] = name end
	end

	it("runs kinds in a fixed order, coalesces repeats and honours cancellation", function()
		local a, b, c = {}, {}, {}
		ns.AfterCombat:Queue("position", a, Record("position a"))
		ns.AfterCombat:Queue("apply", b, Record("apply b (first)"))
		ns.AfterCombat:Queue("layout", a, Record("layout a"))
		ns.AfterCombat:Queue("apply", a, Record("apply a"))
		ns.AfterCombat:Queue("apply", b, Record("apply b"))
		ns.AfterCombat:Queue("restyle", c, Record("restyle c"))
		ns.AfterCombat:Cancel(c)
		assert.is_true(ns.AfterCombat:IsQueued(a, "layout"))
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.same({ "apply b", "apply a", "layout a", "position a" }, runs)
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(4, #runs, "each request runs once")
	end)

	it("keeps work queued while running for the next combat end", function()
		local owner = {}
		ns.AfterCombat:Queue("restyle", owner, function()
			runs[#runs + 1] = "denied"
			ns.AfterCombat:Queue("restyle", owner, Record("retried"))
		end)
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.same({ "denied" }, runs)
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.same({ "denied", "retried" }, runs)
	end)

	it("drops a released component's deferred work", function()
		local bar = ns.Components.Bar:New(CreateFrame("Frame"), {})
		bar:SetCombatDeferred(true)
		Mock.inCombat = true
		bar:Apply({ smooth = false })
		assert.is_true(ns.AfterCombat:IsQueued(bar, "apply"))
		bar:Release()
		Mock.inCombat = false
		assert.is_false(ns.AfterCombat:IsQueued(bar, "apply"))
		assert.has_no_error(function() Mock.FireEvent("PLAYER_REGEN_ENABLED") end)
	end)
end)
