local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Performance settings edit probes", function()
	local UF, CG, messages
	before_each(function()
		UF, CG = Helpers.LoadClickGrid()
		Mock.profilerEnabled = true
		messages = {}
		UF.Print = function(_, ...) messages[#messages + 1] = { ... } end
	end)

	it("measures actual store callbacks and restores overrides outside the timed operation", function()
		local settings = UF.Util.Copy(CG.Config:Get())
		local member = UF.Util.Copy(CG.Config:GetStyle("member"))
		local target = UF.Util.Copy(CG.Config:GetStyle("target"))
		local bindings = UF.Util.Copy(CG.Config:GetBindings())
		local measure, captured = C_AddOnProfiler.MeasureCall, {}
		C_AddOnProfiler.MeasureCall = function(fn)
			return measure(function()
				fn()
				captured.settings = UF.Util.Copy(CG.Config:Get())
				captured.member = UF.Util.Copy(CG.Config:GetStyle("member"))
				captured.target = UF.Util.Copy(CG.Config:GetStyle("target"))
				captured.bindings = UF.Util.Copy(CG.Config:GetBindings())
			end)
		end
		for _, operation in ipairs({ "indicators", "titles", "spacing", "member", "target", "slots", "bindings" }) do
			UF.Perf:Command("edit " .. operation)
			local report = UF.Config.db.global.perfMeasurements["edit " .. operation]
			assert.is_not_nil(report, operation)
			assert.is_true(report.edit.restored)
			assert.is_true(report.edit.before ~= report.edit.value)
			local kind = (operation == "member" or operation == "target" or operation == "bindings") and operation or "settings"
			assert.equals(report.edit.value, UF.Util.GetPath(captured[kind], report.edit.path))
			if operation == "bindings" then assert.is_nil(report.counters.clickgridRefresh)
			else assert.equals(1, report.counters.clickgridRefresh) end
			assert.same(settings, CG.Config:Get(), operation .. " restores settings")
			assert.same(member, CG.Config:GetStyle("member"), operation .. " restores member")
			assert.same(target, CG.Config:GetStyle("target"), operation .. " restores target")
			assert.same(bindings, CG.Config:GetBindings(), operation .. " restores bindings")
			assert.is_nil(UF.Perf.counters)
			assert.is_nil(UF.Perf.measuring)
		end
	end)

	it("restores original overrides after a refresh error and permits a later probe", function()
		CG.Config.styles.member:Set("width", 241)
		local before = UF.Util.Copy(CG.Config:GetStyle("member"))
		local refresh, calls = CG.Refresh, 0
		CG.Refresh = function(self)
			calls = calls + 1
			if calls == 1 then error("edit refresh failed") end
			return refresh(self)
		end
		UF.Perf:MeasureEdit("member")
		assert.same(before, CG.Config:GetStyle("member"))
		assert.is_nil(UF.Perf.counters)
		assert.is_nil(UF.Perf.measuring)
		assert.is_nil(UF.Config.db.global.perfMeasurements)
		UF.Perf:MeasureEdit("member")
		assert.is_true(UF.Config.db.global.perfMeasurements["edit member"].edit.restored)
	end)

	it("restores settings when reporting fails after the measured callback", function()
		local before = UF.Util.Copy(CG.Config:Get())
		UF.Perf.ReportPhases = function() error("report failed") end
		assert.has_no_error(function() UF.Perf:MeasureEdit("titles") end)
		assert.same(before, CG.Config:Get())
		assert.is_nil(UF.Perf.counters)
		assert.is_nil(UF.Perf.measuring)
		local reported
		for _, message in ipairs(messages) do
			if message[1] == "measurement reporting failed:" then reported = message[2] end
		end
		assert.is_not_nil(reported:find("report failed", 1, true))
	end)

	it("does not write during combat, other observations, or unavailable profiling", function()
		local writes = 0
		CG.Config.settings.Set = function() writes = writes + 1 end
		Mock.inCombat = true
		UF.Perf:MeasureEdit("titles")
		Mock.inCombat = false
		local logged = UnitFramesLogs.general[#UnitFramesLogs.general]
		assert.equals("active measurement refused", logged.context)
		assert.equals("active measurements must wait until combat ends", logged.message)
		Mock.profilerEnabled = false
		UF.Perf:MeasureEdit("titles")
		Mock.profilerEnabled = true
		UF.Perf:Watch(10)
		UF.Perf:MeasureEdit("titles")
		assert.equals(10, UF.Perf.seconds)
		UF.Perf:Cancel()
		UF.Perf:Combat()
		UF.Perf:MeasureEdit("titles")
		assert.is_true(UF.Perf.combatArmed)
		UF.Perf:Cancel()
		UF.Perf:StartSuite()
		UF.Perf:MeasureEdit("titles")
		assert.is_not_nil(UF.Perf.suite)
		UF.Perf:Cancel()
		UF.Perf:MeasureEdit("invalid")
		assert.equals(0, writes)
	end)
end)
