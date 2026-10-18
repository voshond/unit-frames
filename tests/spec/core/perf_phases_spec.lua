local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Performance phase attribution", function()
	local UF, messages
	before_each(function()
		UF = Helpers.LoadAddon(true, true)
		Mock.profilerEnabled = true
		messages = {}
		UF.Print = function(_, ...) messages[#messages + 1] = { ... } end
	end)

	it("ranks exclusive time independently from allocation without mutating saved phases", function()
		local phases = UF.Perf.Phases({ elapsedMilliseconds = 12, allocatedBytes = 1000, events = {
			{ name = ">outer", elapsedMilliseconds = 1, allocatedBytes = 100 },
			{ name = ">inner", elapsedMilliseconds = 2, allocatedBytes = 300 },
			{ name = "<inner", elapsedMilliseconds = 8, allocatedBytes = 310 },
			{ name = ">inner", elapsedMilliseconds = 8, allocatedBytes = 310 },
			{ name = "<inner", elapsedMilliseconds = 10, allocatedBytes = 320 },
			{ name = "<outer", elapsedMilliseconds = 11, allocatedBytes = 900 },
		} })
		local before = UF.Util.Copy(phases)
		local timed = UF.Perf.RankPhases(phases, "ms")
		assert.equals("outer", phases[1].name)
		assert.same({ name = "inner", ms = 8, bytes = 20, calls = 2 }, timed[1])
		local ms, bytes = 0, 0
		for _, phase in ipairs(phases) do ms, bytes = ms + phase.ms, bytes + phase.bytes end
		assert.equals(12, ms)
		assert.equals(1000, bytes)
		assert.same(before, phases)
		local tied = { { name = "z", ms = 1 }, { name = "a", ms = 1 } }
		assert.equals("a", UF.Perf.RankPhases(tied, "ms")[1].name)
	end)

	it("shows a CPU hotspot outside the allocation cutoff and persists every phase", function()
		local events, ms, bytes = {}, 0, 0
		for index = 1, 17 do
			local name = index == 17 and "cpu hotspot" or "allocation " .. index
			events[#events + 1] = { name = ">" .. name, elapsedMilliseconds = ms, allocatedBytes = bytes }
			ms, bytes = ms + (index == 17 and 100 or 1), bytes + (index == 17 and 1 or 100)
			events[#events + 1] = { name = "<" .. name, elapsedMilliseconds = ms, allocatedBytes = bytes }
		end
		C_AddOnProfiler.MeasureCall = function(fn)
			fn()
			return { elapsedMilliseconds = ms, allocatedBytes = bytes, deallocatedBytes = 7, events = events }
		end
		UF.Perf:Measure("schema")
		local byTime, byAllocation
		for index, message in ipairs(messages) do
			local text = tostring(message[1])
			if text:find("phases by time", 1, true) then byTime = index end
			if text:find("phases by allocation", 1, true) then byAllocation = index end
		end
		assert.is_not_nil(byTime)
		assert.is_not_nil(byAllocation)
		assert.is_not_nil(messages[byTime + 1][1]:find("cpu hotspot:", 1, true))
		assert.equals(16, byAllocation - byTime)
		for index = byAllocation + 1, byAllocation + 15 do
			assert.is_nil(messages[index][1]:find("cpu hotspot:", 1, true))
		end
		local saved = UF.Config.db.global.perfMeasurements["measure schema"]
		assert.equals(18, #saved.phases)
		assert.equals(ms, saved.ms)
		assert.equals(bytes, saved.allocatedBytes)
		assert.equals(7, saved.deallocatedBytes)
		assert.equals("test-build", saved.context.client.build)
		assert.equals(6, saved.counters.resolveCall)
		assert.equals(6, saved.counters.resolveBuild)
		local snapshot = UF.Util.Copy(saved)
		UF.Perf:ReportPhases(saved.phases)
		assert.same(snapshot, saved)
		messages = {}
		UF.Perf:ReportPhases(saved.phases, #saved.phases)
		assert.equals(2 * (#saved.phases + 1), #messages)
		assert.is_not_nil(messages[1][1]:find("showing 18 of 18", 1, true))
		UF = Helpers.LoadAddon(true, true, UnitFramesDB)
		assert.same(snapshot, UF.Config.db.global.perfMeasurements["measure schema"])
	end)

	it("attributes cold schema construction separately and distinguishes scoped reuse from builds", function()
		local component = UF.Component:Extend("ProfiledSchema")
		component.BuildSchema = function() return { { key = "child", type = "group", schema = {} } } end
		component.OnCreate = function(self, parent)
			self.frame = CreateFrame("Frame", nil, parent)
			self:ChildConfig("child")
		end
		local spec, config = { schemaOwner = {} }, {}
		local first, second
		UF.Perf.startupArmed = true
		UF.Perf:Startup("schema probe", function()
			UF.Schema.Shared(function()
				first = component:New(UIParent, config, spec)
				second = component:New(UIParent, config, spec)
			end)
		end)
		local saved = UF.Config.db.global.perfMeasurements["startup schema probe"]
		assert.equals(1, saved.counters.schemaBuild)
		assert.equals(2, saved.counters.childConfigCall)
		assert.equals(1, saved.counters.childConfigBuild)
		assert.equals(2, saved.counters.resolveCall)
		assert.equals(1, saved.counters.resolveBuild)
		assert.equals(first.resolved, second.resolved)
		local phases = {}
		for _, phase in ipairs(saved.phases) do phases[phase.name] = phase end
		assert.equals(1, phases["schema build"].calls)
		assert.equals(2, phases["child config"].calls)
		assert.equals(2, phases.resolve.calls)
	end)

	it("counts uncached explicit overrides as resolution builds", function()
		local resolve = UF.Units.Refresh
		UF.Units.Refresh = function() UF.Schema.Resolve({}, nil, nil, {}) end
		local ok, _, counters = UF.Perf:CaptureOperation("units")
		UF.Units.Refresh = resolve
		assert.is_true(ok)
		assert.equals(6, counters.resolveCall)
		assert.equals(6, counters.resolveBuild)
	end)

	it("separates real cold unit spawning from Edit Mode registration", function()
		UF.Config.db.global.measureStartup = true
		UF = Helpers.LoadAddon(true, false, UnitFramesDB)
		Mock.profilerEnabled = true
		UF.Print = function() end
		UF.oUF:RunFactories()
		local report = UF.Config.db.global.perfMeasurements["startup units"]
		local phases = {}
		for _, phase in ipairs(report.phases) do phases[phase.name] = phase end
		assert.equals(6, phases["unit spawn"].calls)
		assert.equals(6, phases["edit mode registration"].calls)
		assert.is_true(report.counters.schemaBuild > 0)
		assert.is_not_nil(phases["schema build"])
		assert.is_nil(UF.Config.db.global.measureStartup)
	end)
end)
