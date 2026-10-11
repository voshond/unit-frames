--[[
Tiny test runner with a busted-compatible subset (describe / it /
before_each / after_each and the assert.* used in our specs), so specs run
without installing anything:

  luajit tests/run.lua            all specs
  luajit tests/run.lua bar        only spec files whose name contains "bar"

Run from the repository root. Also syntax-checks every addon Lua file.
]]
local filter = arg[1]

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

local function RunBlock(block, prefix)
	for _, test in ipairs(block.tests) do
		if test.block then
			RunBlock(test.block, prefix .. test.block.name .. " ")
		else
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
		end
	end
end

local function ListFiles(command)
	local files = {}
	local handle = io.popen(command)
	for line in handle:lines() do
		files[#files + 1] = line
	end
	handle:close()
	table.sort(files)
	return files
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

package.path = "./tests/?.lua;" .. package.path
for _, file in ipairs(ListFiles("ls tests/spec/*_spec.lua")) do
	if not filter or file:find(filter, 1, true) then
		root = { name = "", tests = {}, before = {}, after = {} }
		current = root
		dofile(file)
		RunBlock(root, "")
	end
end

print()
for _, failure in ipairs(failures) do
	print("FAIL " .. failure)
end
print(string.format("%d passed, %d failed, %d syntax errors", passed, failed, syntaxErrors))
os.exit((failed == 0 and syntaxErrors == 0) and 0 or 1)
