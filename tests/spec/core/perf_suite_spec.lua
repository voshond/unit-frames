local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Automated performance baseline suite", function()
	local UF
	local function Tick(count, elapsed)
		for _ = 1, count do
			local driver = UF.Perf.driver
			local tick = driver and driver:GetScript("OnUpdate")
			if tick then tick(driver, elapsed or 0.1) end
		end
	end

	before_each(function()
		UF = Helpers.LoadAddon(true, true)
		Mock.profilerEnabled = true
		UF.Print = function() end
	end)

	it("runs one operation per interval, excludes warmups and saves deterministic summaries", function()
		local calls = 0
		C_AddOnProfiler.MeasureCall = function(fn)
			calls = calls + 1
			fn()
			return { elapsedMilliseconds = calls, allocatedBytes = calls * 100,
				deallocatedBytes = calls * 10, events = {} }
		end
		UF.Units.Refresh = function() UF.Perf:Count("refresh") end
		SlashCmdList.UNITFRAMES("perf suite baseline")
		Tick(1, 0.05)
		assert.equals(0, calls)
		Tick(1, 0.05)
		assert.equals(1, calls)
		Tick(1, 20)
		assert.equals(2, calls, "a slow frame never runs a catch-up batch")
		Tick(22)
		local report = UF.Config.db.global.perfSuiteReport
		assert.equals("completed", report.status)
		assert.equals(24, calls)
		assert.equals(2, #report.operations)
		assert.same({ "clickgrid" }, report.skipped)
		local schema, units = report.operations[1], report.operations[2]
		assert.equals(10, #schema.samples)
		assert.equals(7.5, schema.timeMS.median)
		assert.equals(12, schema.timeMS.maximum)
		assert.equals(750, schema.allocatedBytes.median)
		assert.equals(75, schema.deallocatedBytes.median)
		assert.equals(19.5, units.timeMS.median)
		assert.equals(60, units.counters.refresh)
		assert.equals(6, units.samples[1].counters.refresh)
		assert.equals("unmarked", units.samples[1].phases[1].name)
		assert.is_nil(UF.Perf.suite)
		assert.is_nil(UF.Perf.counters)
		assert.is_nil(UF.Perf.measuring)
		assert.is_nil(UF.Perf.driver:GetScript("OnUpdate"))
		assert.is_nil(UF.Perf.driver:GetScript("OnEvent"))
		assert.is_nil(UF.Workbench)
		assert.has_no_error(function() UF.Perf:Command("suite report") end)
		UF = Helpers.LoadAddon(true, true, UnitFramesDB)
		assert.equals(report, UF.Config.db.global.perfSuiteReport)
		assert.is_nil(UF.Perf.suite)
		assert.is_nil(UF.Perf.driver)
		assert.has_no_error(function() UF.Perf:Command("suite report") end)
	end)

	it("records client, addons and independent settings and includes prepared ClickGrid", function()
		local _, CG = Helpers.LoadClickGrid()
		UF = CG.UF
		UF.Print = function() end
		Mock.profilerEnabled = true
		Mock.loadedAddons.OtherAddon = true
		Mock.loadedAddons.UnloadedAddon = false
		Mock.groupSize = 5
		UF.Perf:StartSuite()
		local report = UF.Perf.suite.report
		assert.equals("clickgrid", report.operations[3].name)
		assert.equals(Mock.API.Snapshot().version:match("%.(%d+)$"), report.context.client.build)
		assert.equals(UF.commit, report.context.commit)
		assert.equals(5, report.context.groupSize)
		assert.equals(UF.Config.db:GetCurrentProfile(), report.context.profile)
		assert.is_false(report.context.workbenchShown)
		local loaded = {}
		for _, name in ipairs(report.context.loadedAddons) do loaded[name] = true end
		assert.is_true(loaded.OtherAddon)
		assert.is_nil(loaded.UnloadedAddon)
		assert.is_true(report.context.config.theme ~= UF.Config:GetTheme())
		assert.is_not_nil(report.context.config.clickgrid)
		assert.equals(CG.Config:Resolved().panel.mode, report.context.clickgrid.mode)
		assert.equals(CG:TargetsShown(), report.context.clickgrid.targetsShown)
		assert.equals(#CG.frames, report.context.clickgrid.preparedFrames)
		assert.equals(0, report.context.clickgrid.previews)
		Tick(36)
		assert.equals("completed", report.status)
		assert.equals(10, #report.operations[3].samples)
		assert.equals(10, report.operations[3].counters.clickgridRefresh)
	end)

	it("preserves a completed comparison baseline across later successful and cancelled runs", function()
		UF.Perf:SuiteCommand("save")
		assert.is_nil(UF.Config.db.global.perfSuiteBaselineReport)
		UF.Perf:StartSuite()
		Tick(24)
		local original = UF.Util.Copy(UF.Config.db.global.perfSuiteReport)
		UF.Perf:StartSuite()
		UF.Perf:SuiteCommand("save")
		assert.is_nil(UF.Config.db.global.perfSuiteBaselineReport)
		UF.Perf:Cancel()
		local baseline = UF.Config.db.global.perfSuiteBaselineReport
		assert.same(original, baseline)
		assert.is_true(baseline ~= UF.Config.db.global.perfSuiteReport)
		UF.Perf:StartSuite()
		Tick(24)
		assert.same(original, baseline)
		assert.equals(baseline, UF.Config.db.global.perfSuiteBaselineReport)
		UF.Perf:SuiteCommand("save")
		assert.same(UF.Config.db.global.perfSuiteReport, UF.Config.db.global.perfSuiteBaselineReport)
		assert.is_true(UF.Config.db.global.perfSuiteReport ~= UF.Config.db.global.perfSuiteBaselineReport)
		assert.has_no_error(function() UF.Perf:SuiteCommand("saved") end)
		UF = Helpers.LoadAddon(true, true, UnitFramesDB)
		assert.is_not_nil(UF.Config.db.global.perfSuiteBaselineReport)
	end)

	it("marks unidentified builds and retains complete phase data beyond chat limits", function()
		UF.commit = "unknown"
		UF.Perf:StartSuite()
		assert.is_false(UF.Perf.suite.report.context.buildIdentified)
		UF.Perf:Cancel()
		UF.commit = "abc123"
		UF.Perf:StartSuite()
		assert.is_true(UF.Perf.suite.report.context.buildIdentified)
		Tick(24)
		local sample = UF.Config.db.global.perfSuiteReport.operations[2].samples[1]
		local phases = {}
		for _, phase in ipairs(sample.phases) do phases[phase.name] = phase end
		assert.is_not_nil(phases["bind drivers"])
		assert.is_not_nil(phases["bind tags"])
		assert.is_not_nil(phases["bind decorations"])
		assert.is_true(#sample.phases > 15)
		assert.equals(sample.counters.resolveCall, phases.resolve.calls + sample.counters.resolveReuse)
		assert.is_true(phases["resolve reuse"].calls >= sample.counters.resolveReuse)
	end)

	it("cancels on combat events or lockdown and retains explicitly partial results", function()
		UF.Perf:StartSuite()
		Tick(3)
		Mock.inCombat = true
		Mock.FireEvent("PLAYER_REGEN_DISABLED")
		local report = UF.Config.db.global.perfSuiteReport
		assert.equals("cancelled", report.status)
		assert.equals(1, #report.operations[1].samples)
		assert.is_nil(report.operations[2].timeMS)
		assert.is_nil(UF.Perf.driver:GetScript("OnUpdate"))
		UF.Perf:StartSuite()
		assert.is_nil(UF.Perf.suite)
		Mock.inCombat = false
		UF.Perf:StartSuite()
		Mock.inCombat = true
		Tick(1)
		assert.equals("combat started", UF.Config.db.global.perfSuiteReport.reason)
	end)

	it("retires callbacks and reports for manual cancellation, roster changes and settings edits", function()
		UF.Perf:StartSuite()
		UF.Perf:Command("cancel")
		local cancelled = UF.Config.db.global.perfSuiteReport
		assert.equals("cancelled", cancelled.status)
		UF.Config:SetThemeValue("fontSize", 13)
		assert.equals(cancelled, UF.Config.db.global.perfSuiteReport)
		UF.Perf:StartSuite()
		Mock.FireEvent("GROUP_ROSTER_UPDATE")
		assert.equals("GROUP_ROSTER_UPDATE", UF.Config.db.global.perfSuiteReport.reason)
		UF.Perf:StartSuite()
		UF.Config:SetUnitValue("player", "width", 310)
		assert.is_nil(UF.Perf.suite)
		assert.equals("configuration changed", UF.Config.db.global.perfSuiteReport.reason)
	end)

	it("refuses unavailable profiling and competing observations without replacing them", function()
		Mock.profilerEnabled = false
		UF.Perf:StartSuite()
		assert.is_nil(UF.Perf.driver)
		Mock.profilerEnabled = true
		UF.Perf:Watch(10)
		UF.Perf:StartSuite()
		assert.equals(10, UF.Perf.seconds)
		assert.is_nil(UF.Perf.suite)
		UF.Perf:Cancel()
		UF.Perf:Combat()
		UF.Perf:StartSuite()
		assert.is_true(UF.Perf.combatArmed)
		UF.Perf:Cancel()
		UF.Perf:StartSuite()
		local suite = UF.Perf.suite
		UF.Perf:Measure("units")
		UF.Perf:StartSuite()
		assert.equals(suite, UF.Perf.suite)
		assert.equals(0, #suite.report.operations[1].samples)
		Mock.profilerEnabled = false
		Tick(1)
		assert.equals("profiler disabled", UF.Config.db.global.perfSuiteReport.reason)
	end)

	it("cleans measurement state on operation failure and lets later runs recover", function()
		local refresh = UF.Units.Refresh
		UF.Units.Refresh = function() error("suite operation failed") end
		UF.Perf:StartSuite()
		Tick(13)
		local report = UF.Config.db.global.perfSuiteReport
		assert.equals("failed", report.status)
		assert.is_not_nil(report.reason:find("suite operation failed", 1, true))
		assert.equals(10, #report.operations[1].samples)
		assert.is_nil(UF.Perf.counters)
		assert.is_nil(UF.Perf.measuring)
		assert.is_nil(UF.Perf.suite)
		assert.is_nil(UF.Perf.driver:GetScript("OnUpdate"))
		UF.Units.Refresh = refresh
		UF.Perf:StartSuite()
		Tick(24)
		assert.equals("completed", UF.Config.db.global.perfSuiteReport.status)
	end)
end)
