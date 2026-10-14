--[[
Tiny test runner with a busted-compatible subset (describe / it /
before_each / after_each and the assert.* used in our specs), so specs run
without installing anything. Run from the repository root:

  luajit tests/run.lua                  all specs
  luajit tests/run.lua units            spec paths containing "units" (folder or file)
  luajit tests/run.lua units/           exactly the tests/spec/units/ folder
  luajit tests/run.lua shields_spec.lua exactly that spec file
  luajit tests/run.lua -t "full health" only tests whose full name contains the text
  luajit tests/run.lua --tag shields    only tests tagged #shields (in a describe or it name)
  luajit tests/run.lua -j               spec files in parallel, one process per CPU (-j 4: four)
  luajit tests/run.lua --times          also report how long each spec file took

Path filters are combined with "or"; -t and --tag narrow further. Every run
also syntax-checks every addon Lua file. A run that selects no tests fails.
]]
local pathFilters, nameFilters, tags = {}, {}, {}
local showTimes, jobs, childResult
do
	local i = 1
	local function Value(option)
		i = i + 1
		return arg[i] or error(option .. " needs a value")
	end
	while arg[i] do
		local value = arg[i]
		if value == "--times" then
			showTimes = true
		elseif value == "-t" or value == "--test" then
			nameFilters[#nameFilters + 1] = Value(value)
		elseif value == "--tag" then
			tags[#tags + 1] = Value(value):gsub("^#", "")
		elseif value == "-j" or value == "--jobs" then
			if arg[i + 1] and arg[i + 1]:match("^%d+$") then
				jobs = tonumber(Value(value))
			else
				jobs = 0 -- one per CPU
			end
		elseif value == "--child" then
			childResult = Value(value) -- internal: run one spec file for a parallel run
		elseif value:sub(1, 1) == "-" then
			error("unknown option " .. value)
		else
			pathFilters[#pathFilters + 1] = value
		end
		i = i + 1
	end
end

-- Wall-clock seconds; os.clock would miss time spent in spawned processes.
local Now = os.clock
do
	local ok, ffi = pcall(require, "ffi")
	if ok then
		ffi.cdef("typedef struct { long tv_sec; long tv_nsec; } uf_timespec; int clock_gettime(int, uf_timespec *);")
		local spec = ffi.new("uf_timespec")
		Now = function()
			ffi.C.clock_gettime(1, spec) -- CLOCK_MONOTONIC
			return tonumber(spec.tv_sec) + tonumber(spec.tv_nsec) / 1e9
		end
	end
end
local startedAt = Now()

-- Assertions -------------------------------------------------------------------

local function Describe(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

-- Mock widgets reference their parents (cycles), so they compare by identity.
local function IsMockObject(value)
	return type(value) == "table" and rawget(value, "__type") ~= nil
end

local function DeepEqual(a, b)
	if rawequal(a, b) then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" or IsMockObject(a) or IsMockObject(b) then
		return false
	end
	for k, v in pairs(a) do
		if not DeepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function Dump(value, indent)
	if IsMockObject(value) then
		return "<mock " .. value.__type .. ">"
	end
	if type(value) ~= "table" then
		return Describe(value)
	end
	indent = indent or ""
	local keys = {}
	for k in pairs(value) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
	local lines = { "{" }
	for _, k in ipairs(keys) do
		lines[#lines + 1] = indent .. "  " .. tostring(k) .. " = " .. Dump(value[k], indent .. "  ")
	end
	lines[#lines + 1] = indent .. "}"
	return table.concat(lines, "\n")
end

local luaAssert = assert
assert = setmetatable({}, { __call = function(_, ...) return luaAssert(...) end })

function assert.equals(expected, actual, message)
	if expected ~= actual then
		error((message and message .. ": " or "") .. "expected " .. Describe(expected) .. ", got " .. Describe(actual), 2)
	end
end
assert.are_equal = assert.equals

function assert.same(expected, actual, message)
	if not DeepEqual(expected, actual) then
		error((message and message .. ": " or "") .. "expected\n" .. Dump(expected) .. "\ngot\n" .. Dump(actual), 2)
	end
end
assert.are_same = assert.same

function assert.is_true(value, message)
	if value ~= true then
		error((message or "expected true") .. ", got " .. Describe(value), 2)
	end
end

function assert.is_false(value, message)
	if value ~= false then
		error((message or "expected false") .. ", got " .. Describe(value), 2)
	end
end

function assert.is_nil(value, message)
	if value ~= nil then
		error((message or "expected nil") .. ", got " .. Describe(value), 2)
	end
end

function assert.is_not_nil(value, message)
	if value == nil then
		error(message or "expected a value, got nil", 2)
	end
end

function assert.has_error(fn, message)
	if pcall(fn) then
		error(message or "expected an error", 2)
	end
end

function assert.has_no_error(fn, message)
	local ok, err = pcall(fn)
	if not ok then
		error((message and message .. ": " or "") .. "unexpected error: " .. tostring(err), 2)
	end
end

-- Spec DSL ------------------------------------------------------------------------

local root = { name = "", tests = {}, before = {}, after = {} }
local current = root

function describe(name, body)
	local block = { name = name, tests = {}, before = {}, after = {}, parent = current }
	table.insert(current.tests, { block = block })
	local previous = current
	current = block
	body()
	current = previous
end

function it(name, body)
	table.insert(current.tests, { name = name, body = body })
end

function before_each(fn)
	table.insert(current.before, fn)
end

function after_each(fn)
	table.insert(current.after, fn)
end

-- Runner -----------------------------------------------------------------------

local passed, failed, failures = 0, 0, {}

local function Hooks(block, field, out)
	if block.parent then
		Hooks(block.parent, field, out)
	end
	for _, fn in ipairs(block[field]) do
		out[#out + 1] = fn
	end
	return out
end

local function Selected(fullName)
	for _, text in ipairs(nameFilters) do
		if not fullName:find(text, 1, true) then
			return false
		end
	end
	if #tags == 0 then
		return true
	end
	for tag in fullName:gmatch("#([%w_%-]+)") do
		for _, wanted in ipairs(tags) do
			if tag == wanted then
				return true
			end
		end
	end
	return false
end

local function RunBlock(block, prefix)
	for _, test in ipairs(block.tests) do
		if test.block then
			RunBlock(test.block, prefix .. test.block.name .. " ")
		elseif Selected(prefix .. test.name) then
			local fullName = prefix .. test.name
			local ok, err = xpcall(function()
				for _, fn in ipairs(Hooks(block, "before", {})) do
					fn()
				end
				test.body()
				local after = Hooks(block, "after", {})
				for i = #after, 1, -1 do
					after[i]()
				end
			end, debug.traceback)
			if ok then
				passed = passed + 1
				io.write(".")
			else
				failed = failed + 1
				io.write("F")
				failures[#failures + 1] = fullName .. "\n    " .. tostring(err):gsub("\n", "\n    ")
			end
			io.flush()
		end
	end
end

local function Lines(command)
	local lines = {}
	local handle = io.popen(command)
	for line in handle:lines() do
		lines[#lines + 1] = line
	end
	handle:close()
	return lines
end

local function ListFiles(command)
	local files = Lines(command)
	table.sort(files)
	return files
end

local function Quote(text)
	return "'" .. text:gsub("'", "'\\''") .. "'"
end

local SPEC_DIR = "tests/spec/"
package.path = "./tests/?.lua;" .. package.path

-- Restores the globals a spec file assigned, so a serial run isolates files
-- like the one-process-per-file parallel run does.
local function RestoreGlobals(saved)
	for name in pairs(_G) do
		if saved[name] == nil then _G[name] = nil end
	end
	for name, value in pairs(saved) do
		_G[name] = value
	end
end

-- Runs one spec file (path relative to tests/spec/) in this process.
local function RunFile(file)
	local started, before = Now(), { passed = passed, failed = failed, failures = #failures }
	local globals = {}
	for name, value in pairs(_G) do globals[name] = value end
	root = { name = "", tests = {}, before = {}, after = {} }
	current = root
	local ok, err = xpcall(function() dofile(SPEC_DIR .. file) end, debug.traceback)
	if ok then
		RunBlock(root, "")
	else
		failed = failed + 1
		io.write("F")
		failures[#failures + 1] = file .. " failed to load\n    " .. tostring(err):gsub("\n", "\n    ")
	end
	RestoreGlobals(globals)
	local result = { file = file, passed = passed - before.passed, failed = failed - before.failed,
		seconds = Now() - started, failures = {} }
	for i = before.failures + 1, #failures do
		result.failures[#result.failures + 1] = failures[i]
	end
	return result
end

if childResult then
	local result = RunFile(pathFilters[1])
	local out = assert(io.open(childResult, "w"))
	out:write(string.format("return { file = %q, passed = %d, failed = %d, seconds = %.6f, failures = {\n",
		result.file, result.passed, result.failed, result.seconds))
	for _, failure in ipairs(result.failures) do
		out:write(string.format("%q,\n", failure))
	end
	out:write("} }\n")
	out:close()
	os.exit(0, true)
end

local function SpecSelected(file)
	if #pathFilters == 0 then
		return true
	end
	for _, filter in ipairs(pathFilters) do
		if filter:sub(-1) == "/" then
			if file:sub(1, #filter) == filter then return true end
		elseif filter:match("%.lua$") then
			if file == filter or file:match("([^/]+)$") == filter then return true end
		elseif file:find(filter, 1, true) then
			return true
		end
	end
	return false
end

-- Syntax check of all addon code (catches typos in files the specs don't load).
local syntaxErrors = 0
for _, file in ipairs(ListFiles("find UnitFrames UnitFrames_Workbench UnitFrames_ClickGrid -name '*.lua' -not -path '*/Libs/*'")) do
	local _, err = loadfile(file)
	if err then
		syntaxErrors = syntaxErrors + 1
		print("syntax error: " .. err)
	end
end

local syntaxSeconds = Now() - startedAt

local files = {}
for _, path in ipairs(ListFiles("find " .. SPEC_DIR .. " -name '*_spec.lua'")) do
	local file = path:sub(#SPEC_DIR + 1)
	if SpecSelected(file) then
		files[#files + 1] = file
	end
end

if jobs == 0 then
	jobs = tonumber(Lines("nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1")[1]) or 1
end

local results = {}
if jobs and jobs > 1 and #files > 1 then
	-- One process per spec file; xargs starts the next file as soon as a
	-- process finishes. Larger files go first, so long specs start early.
	local dir = Lines("mktemp -d")[1]
	local order = {}
	for index, file in ipairs(files) do
		local handle = assert(io.open(SPEC_DIR .. file))
		order[index] = { index = index, file = file, size = handle:seek("end") }
		handle:close()
	end
	table.sort(order, function(a, b) return a.size > b.size end)
	local list = assert(io.open(dir .. "/files", "w"))
	for _, entry in ipairs(order) do
		list:write(dir, "/", entry.index, ".lua ", entry.file, "\n")
	end
	list:close()
	local forward = {}
	for _, text in ipairs(nameFilters) do forward[#forward + 1] = "-t " .. Quote(text) end
	for _, tag in ipairs(tags) do forward[#forward + 1] = "--tag " .. Quote(tag) end
	local child = "exec luajit tests/run.lua " .. table.concat(forward, " ") .. ' --child "$0" "$1"'
	os.execute(string.format("xargs -P %d -L 1 sh -c %s < %s", jobs, Quote(child), Quote(dir .. "/files")))
	for index, file in ipairs(files) do
		local chunk = loadfile(dir .. "/" .. index .. ".lua")
		local result = chunk and chunk() or { file = file, passed = 0, failed = 1, seconds = 0,
			failures = { file .. " did not report a result (the spec process crashed)" } }
		results[#results + 1] = result
		passed, failed = passed + result.passed, failed + result.failed
		for _, failure in ipairs(result.failures) do
			failures[#failures + 1] = failure
		end
	end
	os.execute("rm -rf " .. Quote(dir))
else
	for _, file in ipairs(files) do
		results[#results + 1] = RunFile(file)
	end
end

print()
if showTimes then
	table.sort(results, function(a, b) return a.seconds > b.seconds end)
	print(string.format("%8s %6s %9s  %s", "seconds", "tests", "per test", "spec"))
	for _, result in ipairs(results) do
		local tests = result.passed + result.failed
		print(string.format("%8.2f %6d %9.3f  %s", result.seconds, tests, result.seconds / math.max(tests, 1), result.file))
	end
	print(string.format("%8.2f %6s %9s  %s", syntaxSeconds, "", "", "(addon syntax check)"))
	print(string.format("%8.2f %6d %9s  %s", Now() - startedAt, passed + failed, "", "(total, wall clock)"))
end
for _, failure in ipairs(failures) do
	print("FAIL " .. failure)
end
local selectedNothing = passed + failed == 0
if selectedNothing then
	print("No tests matched the given filters.")
end
print(string.format("%d passed, %d failed, %d syntax errors", passed, failed, syntaxErrors))
-- Closing the Lua state lets LuaJIT's profiler (luajit -jp=F tests/run.lua ...) report.
os.exit((failed == 0 and syntaxErrors == 0 and not selectedNothing) and 0 or 1, true)
