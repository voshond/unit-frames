local _, ns = ...
local Perf = ns.Perf

local function Statistics(samples, key)
	local values = {}
	for _, sample in ipairs(samples) do values[#values + 1] = sample[key] end
	table.sort(values)
	local count = #values
	if count == 0 then return nil end
	return { median = (values[math.floor((count + 1) / 2)] + values[math.ceil((count + 1) / 2)]) / 2,
		maximum = values[count] }
end

function Perf:SummarizeSuiteOperation(operation)
	operation.timeMS = Statistics(operation.samples, "ms")
	operation.allocatedBytes = Statistics(operation.samples, "allocatedBytes")
	operation.deallocatedBytes = Statistics(operation.samples, "deallocatedBytes")
end

function Perf:SuiteContext()
	local version, build, buildDate, interface = GetBuildInfo()
	local wb, cg = ns.Workbench, ns.ClickGrid
	local context = { client = { version = version, build = build, date = buildDate, interface = interface },
		version = ns.version, commit = ns.commit, profile = ns.Config.db:GetCurrentProfile(),
		buildIdentified = ns.commit ~= nil and ns.commit ~= "" and ns.commit ~= "unknown",
		groupSize = GetNumGroupMembers(), raid = IsInRaid(), profiler = true,
		workbenchShown = wb and wb.window and wb.window:IsShown() or false,
		entry = wb and wb.entry and wb.entry.id, loadedAddons = {},
		config = { theme = ns.Util.Copy(ns.Config:GetTheme()), units = {} } }
	for index = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(index)
		if C_AddOns.IsAddOnLoaded(name) then context.loadedAddons[#context.loadedAddons + 1] = name end
	end
	table.sort(context.loadedAddons)
	for _, unit in ipairs(ns.Units.order) do
		context.config.units[unit] = ns.Util.Copy(ns.Config:GetUnitConfig(unit))
	end
	if cg and cg.started then
		context.config.clickgrid = ns.Util.Copy(cg.Config:Resolved())
		context.config.member = ns.Util.Copy(cg.Config:GetStyle("member"))
		context.config.target = ns.Util.Copy(cg.Config:GetStyle("target"))
		context.clickgrid = { mode = context.config.clickgrid.panel.mode,
			targetsShown = cg:TargetsShown(), preparedFrames = #cg.frames, activeFrames = 0, previews = 0 }
		for _, frame in ipairs(cg.frames) do
			if not cg:GetGridButton(frame).inactive then
				context.clickgrid.activeFrames = context.clickgrid.activeFrames + 1
			end
		end
		for _ in pairs(cg.previews) do context.clickgrid.previews = context.clickgrid.previews + 1 end
	end
	return context
end

function Perf:ReportSuite(report, title)
	self:Divider(title or "baseline suite")
	if not report then ns:Print("no saved baseline suite report"); return end
	ns:Print("baseline suite", report.status, report.reason or "", "timestamp", report.timestamp)
	local context = report.context
	ns:Print("client", context.client.version, context.client.build, "addon", context.version,
		"commit", context.commit or "unavailable", "profile", context.profile)
	if context.buildIdentified == false then ns:Print("build revision unavailable; record the installed revision for comparisons") end
	ns:Print("group", context.groupSize, "raid", context.raid, "Workbench", context.workbenchShown,
		context.entry or "none")
	ns:Print("loaded addons:", table.concat(context.loadedAddons, ", "))
	if context.clickgrid then
		local cg = context.clickgrid
		ns:Print("ClickGrid", cg.mode, "targets", cg.targetsShown, "prepared frames", cg.preparedFrames,
			"active frames", cg.activeFrames, "previews", cg.previews)
	end
	for _, operation in ipairs(report.operations) do
		if operation.timeMS then
			ns:Print(string.format("%s: %d runs; median %.3f ms; slowest %.3f ms; allocated median %.1f KB, max %.1f KB",
				operation.name, #operation.samples, operation.timeMS.median, operation.timeMS.maximum,
				operation.allocatedBytes.median / 1024, operation.allocatedBytes.maximum / 1024))
			local keys = {}
			for key in pairs(operation.counters) do keys[#keys + 1] = key end
			table.sort(keys)
			for _, key in ipairs(keys) do ns:Print(" ", operation.name, key, operation.counters[key], "total calls") end
			self:ReportCacheReuse(operation.counters, operation.name .. " totals")
		else ns:Print(operation.name, "no recorded runs") end
	end
	for _, name in ipairs(report.skipped) do ns:Print("skipped", name, "not loaded/prepared") end
	ns:Print("active refresh costs; excludes deferred rendering and combat; memory deltas depend on GC/cache state")
	ns:Print("structured report: UnitFramesDB.global.perfSuiteReport; /reload writes it to SavedVariables")
end
