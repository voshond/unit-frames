local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Combined performance capture", function()
	local UF, calls
	local function Tick(count, elapsed)
		for _ = 1, count do
			local driver = UF.Perf.driver
			local tick = driver and driver:GetScript("OnUpdate")
			if tick then tick(driver, elapsed or 0.1) end
		end
	end

	local function Prepare()
		Mock.profilerEnabled = true
		UF.Print = function() end
		UF.Units.Refresh = function() UF.Perf:Count("refresh") end
		calls = 0
		C_AddOnProfiler.MeasureCall = function(fn)
			calls = calls + 1
			fn()
			return { elapsedMilliseconds = calls, allocatedBytes = calls * 100, deallocatedBytes = 0, events = {} }
		end
	end

	before_each(function()
		UF = Helpers.LoadAddon(true, true)
		Prepare()
	end)

	it("adds five blank chat lines and collects baseline plus individual reports one call per interval", function()
		Mock.messages = {}
		UF.Print = function(_, ...) print(...) end
		SlashCmdList.UNITFRAMES("perf capture")
		for index = 1, 5 do assert.same({ " " }, Mock.messages[index]) end
		assert.is_not_nil(Mock.messages[6][1]:find("=|r performance capture start |c", 1, true))
		local report = UF.Perf.suite.report
		assert.is_true(report.capture)
		Tick(24)
		assert.is_true(UF.Perf.suite.details)
		assert.equals(24, calls)
		assert.is_nil(UF.Config.db.global.perfMeasurements)
		Tick(1, 20)
		assert.equals(25, calls, "a slow frame still collects only one detailed operation")
		assert.is_not_nil(UF.Config.db.global.perfMeasurements["measure schema"])
		assert.is_nil(UF.Config.db.global.perfMeasurements["measure units"])
		Tick(1)
		assert.equals(26, calls)
		assert.equals("completed", report.status)
		assert.equals(report, UF.Config.db.global.perfSuiteReport)
		assert.equals(10, #report.operations[2].samples)
		assert.equals(60, report.operations[2].counters.refresh)
		assert.equals(6, UF.Config.db.global.perfMeasurements["measure units"].counters.refresh)
		assert.equals(26, UF.Config.db.global.perfMeasurements["measure units"].ms)
		assert.same({ "clickgrid" }, report.skipped)
		assert.is_nil(UF.Perf.suite)
		assert.is_nil(UF.Perf.driver:GetScript("OnUpdate"))
		assert.is_nil(UF.Perf.driver:GetScript("OnEvent"))
	end)

	it("includes prepared ClickGrid without mixing detailed counters into suite totals", function()
		local cg
		UF, cg = Helpers.LoadClickGrid()
		Prepare()
		cg.Refresh = function() UF.Perf:Count("clickgridRefresh") end
		UF.Perf:Command("capture")
		Tick(38)
		assert.equals(38, calls)
		assert.is_nil(UF.Config.db.global.perfMeasurements["measure clickgrid"])
		Tick(1)
		local report = UF.Config.db.global.perfSuiteReport
		assert.equals(39, calls)
		assert.equals("completed", report.status)
		assert.equals(10, report.operations[3].counters.clickgridRefresh)
		assert.equals(1, UF.Config.db.global.perfMeasurements["measure clickgrid"].counters.clickgridRefresh)
		assert.same({}, report.skipped)
	end)

	it("cancels pending detailed operations on command or combat and retains the partial status", function()
		for _, cancel in ipairs({ "command", "combat" }) do
			UF.Perf:Command("capture")
			Tick(25)
			local before = calls
			if cancel == "command" then UF.Perf:Command("cancel")
			else Mock.FireEvent("PLAYER_REGEN_DISABLED") end
			Tick(10)
			assert.equals(before, calls)
			assert.equals("cancelled", UF.Config.db.global.perfSuiteReport.status)
			assert.is_nil(UF.Config.db.global.perfMeasurements["measure units"])
			assert.is_nil(UF.Perf.suite)
			assert.is_nil(UF.Perf.counters)
			assert.is_nil(UF.Perf.measuring)
		end
	end)

	it("cleans up if detailed report generation fails", function()
		UF.Perf.ReportMeasurement = function() error("detailed report failed") end
		UF.Perf:Command("capture")
		Tick(25)
		local report = UF.Config.db.global.perfSuiteReport
		assert.equals("failed", report.status)
		assert.is_not_nil(report.reason:find("detailed report failed", 1, true))
		assert.is_nil(UF.Perf.suite)
		assert.is_nil(UF.Perf.counters)
		assert.is_nil(UF.Perf.measuring)
		assert.is_nil(UF.Perf.driver:GetScript("OnUpdate"))
		Tick(10)
		assert.equals(25, calls)
	end)
end)
