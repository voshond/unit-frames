local _, ns = ...

-- Diagnostic state is session-local. No scripts are replaced, no unit data is
-- retained, and counters are inactive outside an explicitly requested run.
local Perf = {}
ns.Perf = Perf
local ADDONS = { "UnitFrames", "UnitFrames_ClickGrid", "UnitFrames_Workbench", "UnitFrames_Media" }
local THRESHOLDS = { "CountTimeOver1Ms", "CountTimeOver5Ms", "CountTimeOver10Ms", "CountTimeOver50Ms",
	"CountTimeOver100Ms", "CountTimeOver500Ms", "CountTimeOver1000Ms" }

function Perf:Count(key)
	if self.counters then self.counters[key] = (self.counters[key] or 0) + 1 end
end

local function ProfilerEnabled()
	return ns.Caps.profiler and C_AddOnProfiler.IsEnabled()
end

function Perf:Snapshot()
	local snapshot = { addons = {}, profiler = ProfilerEnabled() }
	if ns.Caps.addonMemory then UpdateAddOnMemoryUsage() end
	local metrics = Enum and Enum.AddOnProfilerMetric
	if snapshot.profiler then
		snapshot.overall = C_AddOnProfiler.GetOverallMetric(metrics.RecentAverageTime)
	end
	for _, name in ipairs(ADDONS) do
		local loaded = name == ns.name or C_AddOns.IsAddOnLoaded(name)
		local addon = { loaded = loaded }
		snapshot.addons[name] = addon
		if loaded then
			if ns.Caps.addonMemory then addon.memoryKB = GetAddOnMemoryUsage(name) end
			if snapshot.profiler then
				addon.recentMS = C_AddOnProfiler.GetAddOnMetric(name, metrics.RecentAverageTime)
				addon.sessionPeakMS = C_AddOnProfiler.GetAddOnMetric(name, metrics.PeakTime)
				addon.thresholds = {}
				for _, key in ipairs(THRESHOLDS) do
					if metrics[key] then addon.thresholds[key] = C_AddOnProfiler.GetAddOnMetric(name, metrics[key]) end
				end
			end
		end
	end
	return snapshot
end

function Perf:Report(snapshot, baseline)
	ns:Print("performance snapshot; profiler", snapshot.profiler and "enabled" or "unavailable/disabled")
	for _, name in ipairs(ADDONS) do
		local addon, before = snapshot.addons[name], baseline and baseline.addons[name]
		if not addon.loaded then
			ns:Print(name, "unloaded")
		else
			ns:Print(name, addon.memoryKB and string.format("Lua %.1f KB", addon.memoryKB) or "memory unavailable")
			if addon.recentMS then
				local share = snapshot.overall > 0 and string.format("; %.1f%% of overall recent average", 100 * addon.recentMS / snapshot.overall) or ""
				ns:Print(string.format("  recent %.3f ms/profiler tick; session peak %.3f ms%s", addon.recentMS, addon.sessionPeakMS, share))
				for _, key in ipairs(THRESHOLDS) do
					local value = addon.thresholds[key]
					local start = before and before.thresholds and before.thresholds[key]
					if value then ns:Print(" ", key, start and value - start or value, start and "window delta (ticks)" or "session ticks") end
				end
			end
			if before and before.memoryKB and addon.memoryKB then
				ns:Print(string.format("  Lua memory change %+.1f KB (GC/cache dependent)", addon.memoryKB - before.memoryKB))
			end
		end
	end
end

local function ReportCounters(counters)
	local keys = {}
	for key in pairs(counters) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do ns:Print(key, counters[key], "calls") end
end

function Perf:Cancel()
	if self.driver then self.driver:SetScript("OnUpdate", nil); self.driver:Hide() end
	self.counters, self.baseline, self.elapsed, self.seconds = nil, nil, nil, nil
end

function Perf:Watch(seconds)
	seconds = tonumber(seconds) or 60
	if seconds ~= seconds or seconds < 1 or seconds > 300 then
		ns:Print("watch duration must be 1–300 seconds")
		return
	end
	self:Cancel()
	self.baseline = self:Snapshot()
	self.counters, self.elapsed, self.seconds = {}, 0, seconds
	self.driver = self.driver or CreateFrame("Frame")
	self.driver:Show()
	-- One cancellable observation clock; only endpoints sample native metrics.
	self.driver:SetScript("OnUpdate", function(_, elapsed)
		self.elapsed = self.elapsed + elapsed
		if self.elapsed < self.seconds then return end
		local counters, baseline, duration = self.counters, self.baseline, self.elapsed
		self:Cancel()
		ns:Print(string.format("passive observation %.2f seconds", duration))
		self:Report(self:Snapshot(), baseline)
		ReportCounters(counters)
	end)
	ns:Print("observing for", seconds, "seconds; /uf perf cancel stops the window")
end

local operations = {
	units = function() for _, unit in ipairs(ns.Units.order) do ns.Units:Refresh(unit) end end,
	clickgrid = function()
		assert(ns.ClickGrid and ns.ClickGrid.started, "ClickGrid must already be loaded and prepared")
		ns.ClickGrid:Refresh()
	end,
	preview = function()
		assert(ns.ClickGrid and next(ns.ClickGrid.previews), "open a ClickGrid preview first")
		for preview in pairs(ns.ClickGrid.previews) do preview:ShowData(preview.data) end
	end,
	schema = function()
		for _, unit in ipairs(ns.Units.order) do
			ns.Schema.Resolve(ns.Units:GetSchema(unit), ns.Config:GetUnitConfig(unit), ns.Config:GetTheme())
		end
	end,
}

function Perf:Measure(operation)
	local run = operations[operation]
	if not run then ns:Print("measure operations: units, clickgrid, preview, schema"); return end
	if InCombatLockdown() then ns:Print("active measurements must wait until combat ends"); return end
	if not ProfilerEnabled() then ns:Print("native addon profiler unavailable/disabled"); return end
	if self.counters then ns:Print("cancel the observation window before an active measurement"); return end
	self.counters = {}
	-- A diagnostic operation can fail; always retire its instrumentation.
	local ok, result = pcall(C_AddOnProfiler.MeasureCall, run)
	local counters = self.counters
	self.counters = nil
	if not ok then ns:Print("measurement failed:", result); return end
	ns:Print(string.format("active %s: %.3f ms; allocated %s bytes; deallocated %s bytes", operation,
		result.elapsedMilliseconds, tostring(result.allocatedBytes), tostring(result.deallocatedBytes)))
	ReportCounters(counters)
end

function Perf:Command(arguments)
	local command, value = arguments:match("^(%S+)%s*(.-)$")
	if command == "watch" then
		if value ~= "" and not tonumber(value) then ns:Print("watch duration must be numeric"); return end
		self:Watch(value ~= "" and value or nil)
	elseif command == "cancel" then self:Cancel(); ns:Print("performance observation cancelled")
	elseif command == "measure" then self:Measure(value)
	elseif not command then self:Report(self:Snapshot())
	else ns:Print("/uf perf [watch <seconds> | cancel | measure <operation>]") end
end
