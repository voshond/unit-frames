local _, ns = ...
local Perf = ns.Perf
local WARMUPS, RUNS, INTERVAL = 2, 10, 0.1

function Perf:FinishSuite(status, reason)
	local suite = self.suite
	if not suite then return end
	self.suite = nil
	self:Cancel()
	ns.Events.UnregisterAllCallbacks(self)
	local report = suite.report
	report.status, report.reason = status, reason
	report.duration = GetTime() - suite.startedAt
	for _, operation in ipairs(report.operations) do self:SummarizeSuiteOperation(operation) end
	report.after = self:Snapshot()
	local global = ns.Config.db.global
	if not global.perfSuiteBaselineReport and global.perfSuiteReport and global.perfSuiteReport.status == "completed" then
		global.perfSuiteBaselineReport = ns.Util.Copy(global.perfSuiteReport)
	end
	global.perfSuiteReport = report
	if status == "failed" then ns.Logs:Error("baseline suite", reason)
	else ns.Logs:Info("baseline suite", status .. (reason and ": " .. reason or "")) end
	self:ReportSuite(report)
end

function Perf:TickSuite(elapsed)
	local suite = self.suite
	if not suite then return end
	if InCombatLockdown() then self:FinishSuite("cancelled", "combat started"); return end
	if not ns.Caps.profiler or not C_AddOnProfiler.IsEnabled() then
		self:FinishSuite("cancelled", "profiler disabled"); return
	end
	suite.elapsed = suite.elapsed + elapsed
	if suite.elapsed < INTERVAL then return end
	suite.elapsed = 0
	if suite.edit then self:TickSuiteEdit(suite); return end
	local operation = suite.report.operations[suite.index]
	local ok, result, counters = self:CaptureOperation(operation.name)
	if self.suite ~= suite then return end
	if not ok then self:FinishSuite("failed", tostring(result)); return end
	if suite.details then
		local title = "measure " .. operation.name
		self:Divider(title)
		local reported, err = pcall(self.ReportMeasurement, self, title, result, counters)
		if not reported then self:FinishSuite("failed", tostring(err)); return end
		if self.suite ~= suite then return end
		suite.index = suite.index + 1
		if suite.index <= #suite.report.operations then return end
		if suite.report.edits then suite.edit = 1
		else self:FinishSuite("completed") end
		return
	end
	suite.iteration = suite.iteration + 1
	if suite.iteration > WARMUPS then
		operation.samples[#operation.samples + 1] = { ms = result.elapsedMilliseconds,
			allocatedBytes = result.allocatedBytes, deallocatedBytes = result.deallocatedBytes,
			counters = counters, phases = self.Phases(result) }
		for key, count in pairs(counters) do operation.counters[key] = (operation.counters[key] or 0) + count end
	end
	if suite.iteration < WARMUPS + RUNS then return end
	suite.index, suite.iteration = suite.index + 1, 0
	if suite.index <= #suite.report.operations then return end
	if suite.report.capture then
		suite.index, suite.details = 1, true
		return
	end
	self:FinishSuite("completed")
end

function Perf:StartSuite(capture)
	if capture then
		for _ = 1, 5 do print(" ") end
		self:Divider("performance capture start")
	else self:Divider("baseline suite start") end
	if InCombatLockdown() then ns:Print("baseline suite must start outside combat"); return end
	if not ns.Caps.profiler or not C_AddOnProfiler.IsEnabled() then
		ns:Print("native addon profiler unavailable/disabled"); return
	end
	if self.counters or self.combatArmed or self.suite then
		ns:Print("cancel the current observation or suite first"); return
	end
	local report = { format = 2, suite = "baseline", status = "running", timestamp = GetServerTime(),
		capture = capture or nil,
		warmups = WARMUPS, runs = RUNS, interval = INTERVAL, context = self:SuiteContext(),
		before = self:Snapshot(), operations = {}, skipped = {} }
	local names = { "schema", "units" }
	local clickgrid = ns.ClickGrid and ns.ClickGrid.started
	if clickgrid then names[#names + 1] = "clickgrid"
	else report.skipped[#report.skipped + 1] = "clickgrid" end
	if capture and clickgrid then report.edits = {} end
	for _, name in ipairs(names) do
		report.operations[#report.operations + 1] = { name = name, samples = {}, counters = {} }
	end
	self.suite = { report = report, startedAt = GetTime(), index = 1, iteration = 0, elapsed = 0 }
	self.driver = self.driver or CreateFrame("Frame")
	self.driver:RegisterEvent("PLAYER_REGEN_DISABLED")
	self.driver:RegisterEvent("GROUP_ROSTER_UPDATE")
	self.driver:SetScript("OnEvent", function(_, event) self:FinishSuite("cancelled", event) end)
	self.driver:SetScript("OnUpdate", function(_, elapsed) self:TickSuite(elapsed) end)
	for _, event in ipairs({ "ThemeChanged", "UnitConfigChanged", "ClickGridConfigChanged" }) do
		ns.Events.RegisterCallback(self, event, function()
			if self.suite and self.suite.editing then return end
			self:FinishSuite("cancelled", "configuration changed")
		end)
	end
	self.driver:Show()
	ns:Print("baseline suite started: 2 warmups + 10 runs per operation, one call per 0.1 seconds")
	ns:Print("keep settings, units and preview state stable; /uf perf cancel stops the suite")
	if capture then ns:Print("detailed schema, unit and prepared ClickGrid reports follow the baseline runs") end
	if report.edits then ns:Print("ClickGrid settings edit probes follow the detailed reports, restoring overrides after each") end
end

function Perf:SuiteCommand(command)
	if command == "baseline" then self:StartSuite()
	elseif command == "report" then self:ReportSuite(ns.Config.db.global.perfSuiteReport)
	elseif command == "saved" then self:ReportSuite(ns.Config.db.global.perfSuiteBaselineReport, "saved comparison baseline")
	elseif command == "save" then
		self:Divider("save comparison baseline")
		local report = ns.Config.db.global.perfSuiteReport
		if self.suite or not report or report.status ~= "completed" then
			ns:Print("finish a baseline suite before saving a comparison baseline")
			return
		end
		ns.Config.db.global.perfSuiteBaselineReport = ns.Util.Copy(report)
		ns:Print("comparison baseline saved; /uf perf suite saved shows it; /reload writes it to SavedVariables")
	else
		self:Divider("baseline suite help")
		ns:Print("/uf perf suite baseline | report | save | saved")
	end
end
