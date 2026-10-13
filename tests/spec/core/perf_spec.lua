local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Opt-in performance diagnostics", function()
	local UF, messages
	before_each(function()
		UF = Helpers.LoadAddon(true, true)
		messages = {}
		UF.Print = function(_, ...) messages[#messages + 1] = { ... } end
	end)

	it("does no sampling, counting or clock creation by default", function()
		UF.Units:Refresh("player")
		assert.is_nil(UF.Perf.counters)
		assert.is_nil(UF.Perf.driver)
		assert.equals(0, Mock.memoryUpdates)
	end)

	it("snapshots loaded addons without loading Workbench and labels session metrics", function()
		Mock.profilerEnabled = true
		local metrics = Enum.AddOnProfilerMetric
		Mock.profilerMetrics.UnitFrames = { [metrics.RecentAverageTime] = 2, [metrics.PeakTime] = 8 }
		Mock.profilerMetrics.overall = { [metrics.RecentAverageTime] = 10 }
		local snapshot = UF.Perf:Snapshot()
		assert.is_true(snapshot.addons.UnitFrames.loaded)
		assert.is_false(snapshot.addons.UnitFrames_Workbench.loaded)
		assert.equals(8, snapshot.addons.UnitFrames.sessionPeakMS)
		assert.is_nil(UF.Workbench)
		assert.has_no_error(function() UF.Perf:Report(snapshot) end)
	end)

	it("bounds, replaces and retires observation windows with counter deltas", function()
		Mock.profilerEnabled = true
		local metric = Enum.AddOnProfilerMetric.CountTimeOver1Ms
		Mock.profilerMetrics.UnitFrames = { [metric] = 10 }
		UF.Perf:Watch(1)
		UF.Units:Refresh("player")
		assert.equals(1, UF.Perf.counters.unitBind)
		local observed
		UF.Perf.Report = function(_, snapshot, baseline)
			observed = snapshot.addons.UnitFrames.thresholds.CountTimeOver1Ms - baseline.addons.UnitFrames.thresholds.CountTimeOver1Ms
		end
		Mock.profilerMetrics.UnitFrames[metric] = 13
		local driver = UF.Perf.driver
		driver:GetScript("OnUpdate")(driver, 1)
		assert.equals(3, observed)
		assert.is_nil(driver:GetScript("OnUpdate"))
		assert.is_nil(UF.Perf.counters)
		UF.Perf:Watch(1)
		UF.Perf:Watch(2)
		assert.equals(driver, UF.Perf.driver)
		assert.equals(2, UF.Perf.seconds)
		UF.Perf:Cancel()
		UF.Perf:Watch(301)
		assert.is_nil(UF.Perf.counters)
	end)

	it("measures only explicit prepared operations outside combat and cleans up failures", function()
		Mock.profilerEnabled = true
		assert.has_no_error(function() UF.Perf:Measure("units") end)
		assert.is_nil(UF.Perf.counters)
		assert.has_no_error(function() UF.Perf:Measure("clickgrid") end)
		assert.is_nil(UF.Perf.counters)
		local calls = 0
		UF.Units.Refresh = function() calls = calls + 1 end
		Mock.inCombat = true
		UF.Perf:Measure("units")
		assert.equals(0, calls)
		Mock.inCombat = false
		Mock.profilerEnabled = false
		UF.Perf:Measure("units")
		assert.equals(0, calls)
	end)

	it("dispatches slash commands and degrades when optional APIs are absent", function()
		SlashCmdList.UNITFRAMES("perf watch 2")
		assert.equals(2, UF.Perf.seconds)
		SlashCmdList.UNITFRAMES("perf cancel")
		assert.is_nil(UF.Perf.counters)
		UF.Caps.profiler, UF.Caps.addonMemory = false, false
		assert.has_no_error(function() SlashCmdList.UNITFRAMES("perf") end)
		SlashCmdList.UNITFRAMES("perf watch invalid")
		assert.is_nil(UF.Perf.counters)
	end)
end)
