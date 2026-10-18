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

	it("starts each report with a divider naming it", function()
		Mock.profilerEnabled = true
		UF.Perf:Measure("units")
		assert.is_not_nil(messages[1][1]:find("=|r measure units |c", 1, true))
		messages = {}
		UF.Perf:Report(UF.Perf:Snapshot())
		assert.is_not_nil(messages[1][1]:find("=|r snapshot |c", 1, true))
		UF.Perf:Watch(1)
		messages = {}
		local driver = UF.Perf.driver
		driver:GetScript("OnUpdate")(driver, 1)
		assert.is_not_nil(messages[1][1]:find("=|r watch 1 s |c", 1, true), "a watch report starts with its divider")
		for i = 2, #messages do
			assert.is_nil(tostring(messages[i][1]):find("=|r", 1, true), "only one divider per report")
		end
	end)

	it("observes only the next combat and retires its events after reporting", function()
		Mock.profilerEnabled = true
		local metric = Enum.AddOnProfilerMetric.CountTimeOver1Ms
		Mock.profilerMetrics.UnitFrames = { [metric] = 10 }
		UF.Perf:Command("combat")
		local driver = UF.Perf.driver
		assert.is_nil(driver:GetScript("OnUpdate"))
		UF.Perf:Count("outside")
		assert.is_nil(UF.Perf.counters)
		local updates = Mock.memoryUpdates
		Mock.time = 20
		Mock.inCombat = true
		Mock.FireEvent("PLAYER_REGEN_DISABLED")
		assert.equals(updates + 1, Mock.memoryUpdates)
		UF.Perf:Count("inside")
		local observed
		UF.Perf.Report = function(_, snapshot, baseline)
			observed = snapshot.addons.UnitFrames.thresholds.CountTimeOver1Ms - baseline.addons.UnitFrames.thresholds.CountTimeOver1Ms
		end
		Mock.profilerMetrics.UnitFrames[metric] = 14
		Mock.time = 23.5
		Mock.inCombat = false
		messages = {}
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(4, observed)
		assert.is_not_nil(messages[1][1]:find("combat 3.50 s", 1, true))
		assert.same({ "inside", 1, "calls" }, messages[2])
		assert.is_nil(UF.Perf.counters)
		assert.is_nil(UF.Perf.combatArmed)
		assert.is_nil(driver:GetScript("OnEvent"))
		Mock.FireEvent("PLAYER_REGEN_DISABLED")
		assert.is_nil(UF.Perf.counters)
	end)

	it("cancels or replaces armed and active combat observations", function()
		UF.Perf:Combat()
		UF.Perf:Cancel()
		Mock.FireEvent("PLAYER_REGEN_DISABLED")
		assert.is_nil(UF.Perf.counters)
		UF.Perf:Combat()
		Mock.inCombat = true
		Mock.FireEvent("PLAYER_REGEN_DISABLED")
		local counters = UF.Perf.counters
		UF.Perf:Combat()
		assert.equals(counters, UF.Perf.counters, "arming during combat preserves the active run")
		UF.Perf:Cancel()
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		UF.Perf:Combat()
		UF.Perf:Watch(1)
		assert.is_nil(UF.Perf.driver:GetScript("OnEvent"))
		UF.Perf:Combat()
		assert.is_nil(UF.Perf.driver:GetScript("OnUpdate"))
		Mock.profilerEnabled = true
		local calls = 0
		UF.Units.Refresh = function() calls = calls + 1 end
		UF.Perf:Measure("units")
		assert.equals(0, calls, "active measurements cannot consume an armed combat")
	end)

	it("measures startup on the next load only after arming it, and fails as unmeasured", function()
		Mock.profilerEnabled = true
		local runs = 0
		UF.Perf:Startup("units", function(n) runs = runs + n end, 1)
		assert.equals(1, runs)
		assert.same({}, messages, "unarmed: no measurement")
		UF.Perf:Command("startup")
		assert.is_true(UF.Config.db.global.measureStartup)
		messages = {}
		UF.Perf:Startup("units", function(n) runs = runs + n end, 2)
		assert.equals(3, runs)
		assert.is_nil(UF.Config.db.global.measureStartup, "armed for one load")
		assert.is_not_nil(messages[1][1]:find("=|r startup units |c", 1, true))
		messages = {}
		UF.Perf:Startup("clickgrid", function() end)
		assert.is_not_nil(messages[1][1]:find("=|r startup clickgrid |c", 1, true), "every startup of that load")
		assert.is_nil(UF.Perf.counters)
		assert.has_error(function() UF.Perf:Startup("clickgrid", function() error("boom") end) end)
		assert.is_nil(UF.Perf.counters)
	end)

	it("measures creating a released ClickGrid preview as a startup stand-in", function()
		local _, CG = Helpers.LoadClickGrid()
		UF = CG.UF
		UF.Print = function(_, ...) messages[#messages + 1] = { ... } end
		Mock.profilerEnabled = true
		local created
		local new = CG.Preview.New
		CG.Preview.New = function(...) created = new(...); return created end
		UF.Perf:Measure("create")
		assert.is_true(created.released)
		assert.equals(5, #created.cells)
		assert.is_nil(next(CG.previews))
		assert.is_nil(UF.Perf.counters)
		local reported
		for _, message in ipairs(messages) do
			if message[1] == "componentCreate" then reported = message[2] end
		end
		assert.is_true(reported > 0)
	end)

	it("isolates native aura creation and reports dispel registration cost", function()
		Mock.profilerEnabled = true
		local created
		local new = UF.Components.Auras.New
		UF.Components.Auras.New = function(...)
			created = new(...)
			return created
		end
		UF.Perf:Measure("auras")
		assert.is_true(created.released)
		assert.is_false(created.frame:GetParent():IsShown())
		assert.is_false(created.containers.buffs:IsEnabled())
		assert.is_nil(created.unit)
		assert.is_nil(UF.Perf.counters)
		local counters, phase = {}, false
		for _, message in ipairs(messages) do
			if message[3] == "calls" then counters[message[1]] = message[2] end
			if tostring(message[1]):find("dispel registration:", 1, true) then phase = true end
		end
		assert.is_true(counters.auraButtonCreate > 0)
		assert.is_true(counters.auraDispelRegister > 0)
		assert.is_true(phase)
		assert.is_nil(UF.Workbench)
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

	it("attributes exclusive phase cost and marks phases only while measuring", function()
		local events = {}
		local add = C_AddOnProfiler.AddMeasuredCallEvent
		C_AddOnProfiler.AddMeasuredCallEvent = function(name) events[#events + 1] = name; return add(name) end
		UF.Units:Refresh("player")
		assert.same({}, events, "no markers outside a measurement")
		local phases = UF.Perf.Phases({ elapsedMilliseconds = 10, allocatedBytes = 1000, events = {
			{ name = ">UnitFrame", elapsedMilliseconds = 1, allocatedBytes = 100 },
			{ name = ">resolve", elapsedMilliseconds = 2, allocatedBytes = 300 },
			{ name = "<resolve", elapsedMilliseconds = 5, allocatedBytes = 700 },
			{ name = "<UnitFrame", elapsedMilliseconds = 6, allocatedBytes = 800 },
		} })
		local byName = {}
		for _, phase in ipairs(phases) do byName[phase.name] = phase end
		assert.equals("resolve", phases[1].name)
		assert.same({ name = "resolve", ms = 3, bytes = 400, calls = 1 }, byName.resolve)
		assert.same({ name = "UnitFrame", ms = 2, bytes = 300, calls = 1 }, byName.UnitFrame)
		assert.same({ name = "unmarked", ms = 5, bytes = 300, calls = 0 }, byName.unmarked)
		Mock.profilerEnabled = true
		UF.Perf:Measure("units")
		C_AddOnProfiler.AddMeasuredCallEvent = add
		assert.is_nil(UF.Perf.measuring)
		local opened = {}
		for _, name in ipairs(events) do
			local kind, label = name:sub(1, 1), name:sub(2)
			opened[label] = (opened[label] or 0) + (kind == ">" and 1 or -1)
			assert.is_true(#name < 48)
		end
		for _, label in ipairs({ "UnitFrame", "resolve", "bind", "bind drivers", "bind tags", "bind decorations", "oUF elements", "oUF tags" }) do
			assert.is_not_nil(opened[label], label)
		end
		for label, open in pairs(opened) do assert.equals(0, open, label .. " is balanced") end
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
