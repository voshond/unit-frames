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

-- Phase markers for an active measurement only; elsewhere they are no-ops.
-- Labels are short static names (under the 48-byte allocation limit), cached
-- with their begin/end prefixes.
local function Prefixed(prefix)
	return setmetatable({}, { __index = function(labels, label)
		local value = prefix .. label
		labels[label] = value
		return value
	end })
end
local BEGIN, END = Prefixed(">"), Prefixed("<")

function Perf:Begin(label)
	if self.measuring then C_AddOnProfiler.AddMeasuredCallEvent(BEGIN[label]) end
end

function Perf:End(label)
	if self.measuring then C_AddOnProfiler.AddMeasuredCallEvent(END[label]) end
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

-- Separates consecutive reports in the chat frame.
local DIVIDER = string.rep("=", 12)
local function Divider(title)
	ns:Print(string.format("|cff808080%s|r %s |cff808080%s|r", DIVIDER, title, DIVIDER))
end

-- `untitled`: the caller has already started the report with its divider.
function Perf:Report(snapshot, baseline, untitled)
	if not untitled then Divider("snapshot") end
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
	if self.driver then
		self.driver:SetScript("OnUpdate", nil)
		self.driver:SetScript("OnEvent", nil)
		self.driver:UnregisterAllEvents()
		self.driver:Hide()
	end
	self.counters, self.baseline, self.elapsed, self.seconds = nil, nil, nil, nil
	self.combatArmed, self.startedAt = nil, nil
end

-- Observe exactly the next combat. Native metrics are sampled only at the
-- endpoints; counters run only between the two events, with no per-frame work.
function Perf:Combat()
	if InCombatLockdown() then ns:Print("arm the next combat outside combat"); return end
	self:Cancel()
	self.combatArmed = true
	self.driver = self.driver or CreateFrame("Frame")
	self.driver:RegisterEvent("PLAYER_REGEN_DISABLED")
	self.driver:SetScript("OnEvent", function(driver, event)
		if event == "PLAYER_REGEN_DISABLED" then
			driver:UnregisterEvent(event)
			self.baseline = self:Snapshot()
			self.counters, self.startedAt = {}, GetTime()
			driver:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			local counters, baseline, duration = self.counters, self.baseline, GetTime() - self.startedAt
			self:Cancel()
			Divider(string.format("combat %.2f s", duration))
			self:Report(self:Snapshot(), baseline, true)
			ReportCounters(counters)
		end
	end)
	ns:Print("next combat armed; /uf perf cancel disarms it")
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
		Divider(string.format("watch %g s", seconds))
		ns:Print(string.format("passive observation %.2f seconds", duration))
		self:Report(self:Snapshot(), baseline, true)
		ReportCounters(counters)
	end)
	ns:Print("observing for", seconds, "seconds; /uf perf cancel stops the window")
end

-- Exclusive time and allocation per phase: each interval between markers
-- belongs to the innermost open phase (outside any phase: "unmarked").
local function Phases(results)
	local phases, stack, ms, bytes = {}, {}, 0, 0
	local function Add(name, toMS, toBytes)
		local phase = phases[name] or { name = name, ms = 0, bytes = 0, calls = 0 }
		phases[name] = phase
		phase.ms, phase.bytes = phase.ms + toMS - ms, phase.bytes + toBytes - bytes
		ms, bytes = toMS, toBytes
		return phase
	end
	for _, event in ipairs(results.events or {}) do
		Add(stack[#stack] or "unmarked", event.elapsedMilliseconds, event.allocatedBytes)
		local kind, name = event.name:sub(1, 1), event.name:sub(2)
		if kind == ">" then
			stack[#stack + 1] = name
			local phase = phases[name] or { name = name, ms = 0, bytes = 0, calls = 0 }
			phases[name], phase.calls = phase, phase.calls + 1
		elseif kind == "<" then
			stack[#stack] = nil
		end
	end
	Add("unmarked", results.elapsedMilliseconds, results.allocatedBytes)
	local list = {}
	for _, phase in pairs(phases) do list[#list + 1] = phase end
	table.sort(list, function(a, b) return a.bytes > b.bytes end)
	return list
end
Perf.Phases = Phases

local function ReportPhases(results)
	for index, phase in ipairs(Phases(results)) do
		if index > 15 then break end
		ns:Print(string.format("  %s: %.3f ms, %.1f KB allocated, %d calls (exclusive)",
			phase.name, phase.ms, phase.bytes / 1024, phase.calls))
	end
end

local operations = {
	-- Native aura creation, isolated from oUF/ClickGrid. No unit or fake aura
	-- data is assigned. Each run retains engine frames until the next reload.
	auras = function()
		local host = CreateFrame("Frame", nil, UIParent)
		host:Hide()
		host:SetSize(240, 40)
		local auras = ns.Components.Auras:New(host, { enabled = true })
		auras:Release()
	end,
	units = function() for _, unit in ipairs(ns.Units.order) do ns.Units:Refresh(unit) end end,
	clickgrid = function()
		assert(ns.ClickGrid and ns.ClickGrid.started, "ClickGrid must already be loaded and prepared")
		ns.ClickGrid:Refresh()
	end,
	preview = function()
		assert(ns.ClickGrid and next(ns.ClickGrid.previews), "open a ClickGrid preview first")
		for preview in pairs(ns.ClickGrid.previews) do preview:ShowData(preview.data) end
	end,
	-- Builds and releases a hidden ClickGrid preview: 5 member/target cells
	-- composed like live grid members, as a stand-in for the panel's startup.
	-- Frames cannot be destroyed, so each run keeps their widgets until reload.
	create = function()
		assert(ns.ClickGrid and ns.ClickGrid.started, "ClickGrid must already be loaded and prepared")
		local preview = ns.ClickGrid.Preview:New(UIParent)
		preview.frame:Hide()
		preview:Release()
	end,
	schema = function()
		for _, unit in ipairs(ns.Units.order) do
			ns.Schema.Resolve(ns.Units:GetSchema(unit), ns.Config:GetUnitConfig(unit), ns.Config:GetTheme())
		end
	end,
}

-- Runs fn(...) inside an active measurement and reports it under `title`.
-- Returns whether it succeeded and the error otherwise.
local function Run(self, title, fn, ...)
	self.counters, self.measuring = {}, true
	-- A diagnostic operation can fail; always retire its instrumentation.
	local ok, result = pcall(C_AddOnProfiler.MeasureCall, fn, ...)
	local counters = self.counters
	self.counters, self.measuring = nil, nil
	Divider(title)
	if not ok then
		ns.Logs:Error(title, result)
		ns:Print("measurement failed:", result)
		return false, result
	end
	local summary = string.format("active %s: %.3f ms; allocated %s bytes; deallocated %s bytes", title,
		result.elapsedMilliseconds, tostring(result.allocatedBytes), tostring(result.deallocatedBytes))
	ns.Logs:Info(title, summary)
	ns:Print(summary)
	ReportCounters(counters)
	ReportPhases(result)
	return true
end

function Perf:Measure(operation)
	local run = operations[operation]
	if not run then ns:Print("measure operations: auras, units, clickgrid, preview, create, schema"); return end
	if InCombatLockdown() then ns:Print("active measurements must wait until combat ends"); return end
	if not ProfilerEnabled() then ns:Print("native addon profiler unavailable/disabled"); return end
	if self.counters or self.combatArmed then ns:Print("cancel the observation window before an active measurement"); return end
	Run(self, "measure " .. operation, run)
end

-- Startup measurement. "/uf perf startup" arms it for the next load only;
-- there each Perf:Startup call (unit frame spawning, the ClickGrid panel)
-- runs inside an active measurement. Otherwise it simply calls fn(...).
function Perf:ArmStartup()
	ns.Config.db.global.measureStartup = true
	ns:Print("startup will be measured once after the next /reload")
end

function Perf:Startup(label, fn, ...)
	local global = ns.Config.db and ns.Config.db.global
	if global and global.measureStartup then
		global.measureStartup = nil
		self.startupArmed = true
	end
	if not self.startupArmed or self.counters or InCombatLockdown() or not ProfilerEnabled() then
		return fn(...)
	end
	local ok, err = Run(self, "startup " .. label, fn, ...)
	-- Fail as an unmeasured startup would.
	if not ok then error(err, 0) end
end

function Perf:Command(arguments)
	local command, value = arguments:match("^(%S+)%s*(.-)$")
	if command == "watch" then
		if value ~= "" and not tonumber(value) then ns:Print("watch duration must be numeric"); return end
		self:Watch(value ~= "" and value or nil)
	elseif command == "cancel" then self:Cancel(); ns:Print("performance observation cancelled")
	elseif command == "measure" then self:Measure(value)
	elseif command == "startup" then self:ArmStartup()
	elseif command == "combat" then self:Combat()
	elseif not command then self:Report(self:Snapshot())
	else ns:Print("/uf perf [watch <seconds> | combat | cancel | measure <operation> | startup]") end
end
