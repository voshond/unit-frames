local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("ClickGrid role ordering", function()
	local UF, CG
	before_each(function() UF, CG = Helpers.LoadClickGrid() end)

	it("supports all permutations through native assigned-role ordering without losing filters", function()
		local option = UF.Schema.Find(CG.Config.schema, "panel.roleOrder")
		assert.equals(7, #option.values)
		for index = 2, #option.values do
			local order = option.values[index][1]
			CG.Config:Set("panel.roleOrder", order)
			for _, header in pairs(CG.headers) do
				assert.equals("ASSIGNEDROLE", header:GetAttribute("groupBy"))
				assert.equals(order, header:GetAttribute("groupingOrder"))
				assert.equals("INDEX", header:GetAttribute("sortMethod"))
				assert.equals("ASC", header:GetAttribute("sortDir"))
			end
			assert.equals("1", CG.headers.group1:GetAttribute("groupFilter"))
		end
		CG.Config:Set("panel.mode", "flat")
		assert.equals("ASSIGNEDROLE", CG.headers.raid:GetAttribute("groupBy"))
		CG.Config:Set("panel.roleOrder", "roster")
		assert.is_nil(CG.headers.party:GetAttribute("groupBy"))
		assert.is_nil(CG.headers.raid:GetAttribute("groupingOrder"))
	end)

	it("defers secure changes and avoids component creation or binding recompilation", function()
		Mock.inCombat = true
		CG.Config:Set("panel.roleOrder", "TANK,DAMAGER,HEALER,NONE")
		assert.is_nil(CG.headers.party:GetAttribute("groupBy"))
		Mock.inCombat = false
		UF.Perf.counters = {}
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		local counters = UF.Perf.counters
		UF.Perf.counters = nil
		assert.is_nil(counters.componentCreate)
		assert.is_nil(counters.rootApply)
		assert.is_nil(counters.unitBind)
		assert.is_nil(counters.clickgridBindingsCompile)
		assert.equals("ASSIGNEDROLE", CG.headers.party:GetAttribute("groupBy"))
	end)
end)

describe("ClickGrid role ordering #workbench", function()
	it("reorders whole owner samples with stable ties and unassigned members last", function()
		local _, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		CG.Config:Set("panel.mode", "flat")
		CG.Config:Set("panel.roleOrder", "TANK,DAMAGER,HEALER,NONE")
		wb.dataTarget.set("count", 8)
		local actual = {}
		for index, cell in ipairs(wb.handle.cells) do actual[index] = cell.sampleIndex end
		assert.same({ 1, 3, 4, 5, 6, 7, 2, 8 }, actual)
		local order = wb.handle.orders["1:8"]
		wb.handle:ShowData({ source = "animated", count = 8 })
		wb.handle:Tick(0.2)
		assert.equals(order, wb.handle.orders["1:8"])
	end)
end)
