local usage = "luajit scripts/read-perf.lua [SavedVariables/UnitFrames.lua] [all|suite|saved|edits|measurement title]"
local path, selection = arg[1], arg[2] or "all"
if path == "--help" then print(usage); return end
if not path or (not path:find("/", 1, true) and not path:match("%.lua$")) then
	selection = path or "all"
	local remembered = assert(io.open("plans/perf-saved-path", "rb"), "No remembered path; supply a SavedVariables file. " .. usage)
	path = assert(remembered:read("*l"), "Remembered SavedVariables path is empty")
	remembered:close()
end

local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()
assert(source:byte(1) ~= 27, "Expected text SavedVariables")
local saved = {}
local chunk = assert(loadstring(source, "@" .. path))
setfenv(chunk, saved)
chunk()
local global = assert(saved.UnitFramesDB and saved.UnitFramesDB.global, "No UnitFramesDB.global in " .. path)

local ns = { Print = function(_, ...)
	local values = {}
	for index = 1, select("#", ...) do values[index] = tostring(select(index, ...)) end
	print((table.concat(values, " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
end }
for _, name in ipairs({ "Perf", "PerfPhases", "PerfSuiteReport" }) do
	assert(loadfile("UnitFrames/Core/" .. name .. ".lua"))("UnitFrames", ns)
end

local function Measurement(title, report)
	ns.Perf:Divider(title)
	ns:Print("timestamp", report.timestamp)
	local context = report.context
	if context then
		ns:Print("client", context.client.version, context.client.build, "addon", context.version,
			"commit", context.commit or "unavailable", "profile", context.profile)
	end
	ns:Print(string.format("%.3f ms; allocated %.1f KB; deallocated %.1f KB", report.ms,
		report.allocatedBytes / 1024, report.deallocatedBytes / 1024))
	local counters, keys = report.counters or {}, {}
	for key in pairs(counters) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do ns:Print(key, counters[key], "calls") end
	ns.Perf:ReportCacheReuse(counters)
	local phases = report.phases or {}
	ns.Perf:ReportPhases(phases, #phases)
	if report.edit then ns:Print("edit", report.edit.path, "restored", report.edit.restored) end
end

print("Saved diagnostics: " .. path)
if selection == "all" or selection == "suite" then ns.Perf:ReportSuite(global.perfSuiteReport) end
if selection == "saved" then
	ns.Perf:ReportSuite(global.perfSuiteBaselineReport, "saved comparison baseline")
elseif selection == "all" or selection == "edits" then
	local titles = {}
	for title in pairs(global.perfMeasurements or {}) do
		if selection == "all" or title:find("^edit ") then titles[#titles + 1] = title end
	end
	table.sort(titles)
	for _, title in ipairs(titles) do Measurement(title, global.perfMeasurements[title]) end
elseif selection ~= "suite" then
	local report = global.perfMeasurements and global.perfMeasurements[selection]
	assert(report, "No saved measurement: " .. selection)
	Measurement(selection, report)
end
