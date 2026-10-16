--[[
Guards saved-variable meaning during refactors: every schema, its static
defaults and its theme-resolved defaults are serialised and compared with
tests/fixtures/schema_snapshot.txt. Intentional changes regenerate it with

  UPDATE_SNAPSHOTS=1 luajit tests/run.lua snapshot
]]
local Helpers = require("helpers")

local FIXTURE = "tests/fixtures/schema_snapshot.txt"

-- Compact, deterministic lines: one per option path and one per value path.
local function Inline(value)
	if type(value) == "table" then
		local items = {}
		for i, v in ipairs(value) do items[i] = Inline(v) end
		local keys = {}
		for k in pairs(value) do if type(k) ~= "number" then keys[#keys + 1] = k end end
		table.sort(keys)
		for _, k in ipairs(keys) do items[#items + 1] = k .. "=" .. Inline(value[k]) end
		return "{" .. table.concat(items, ",") .. "}"
	elseif type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "function" then
		return "<function>"
	end
	return tostring(value)
end

-- Long texts and value lists are recorded as checksums to keep the fixture small.
local function Hash(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
	return string.format("#%08x", h)
end

local DESCRIPTOR_FIELDS = { "type", "label", "default", "inherit", "min", "max", "step" }

local function Options(schema, prefix, out)
	for _, opt in ipairs(schema) do
		local path = prefix .. opt.key
		local fields = {}
		for _, field in ipairs(DESCRIPTOR_FIELDS) do
			if opt[field] ~= nil then fields[#fields + 1] = field .. "=" .. Inline(opt[field]) end
		end
		if opt.values then
			fields[#fields + 1] = "values=" .. Hash(Inline(type(opt.values) == "function" and opt.values() or opt.values))
		end
		if opt.tooltip then fields[#fields + 1] = "tooltip=" .. Hash(opt.tooltip) end
		if opt.hint then fields[#fields + 1] = "hint=" .. Hash(opt.hint) end
		if opt.hidden then fields[#fields + 1] = "hidden" end
		if opt.defaults then fields[#fields + 1] = "defaults=" .. Inline(opt.defaults) end
		out[#out + 1] = path .. " " .. table.concat(fields, " ")
		if opt.schema then Options(opt.schema, path .. ".", out) end
	end
	return out
end

local function Values(tbl, prefix, out)
	local keys = {}
	for k in pairs(tbl) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) == "number"
	end)
	for _, k in ipairs(keys) do
		local v = tbl[k]
		if type(v) == "table" and next(v) ~= nil and v[1] == nil then
			Values(v, prefix .. tostring(k) .. ".", out)
		else
			out[#out + 1] = prefix .. tostring(k) .. " = " .. Inline(v)
		end
	end
	return out
end

local function Subjects()
	local UF, CG = Helpers.LoadClickGrid()
	local C, theme = UF.Components, UF.Config:GetTheme()
	local subjects = {}
	local function Add(name, schema, extra)
		subjects[#subjects + 1] = { name = name, schema = schema,
			defaults = UF.Schema.Defaults(schema), resolved = UF.Schema.Resolve(schema, nil, theme), extra = extra }
	end
	Add("theme", UF.Theme.schema)
	Add("backdrop", C.Backdrop.schema)
	Add("text", C.Text.BuildSchema({ host = true, formats = UF.Formats.HEALTH }))
	Add("castbar", C.Castbar.BuildSchema())
	Add("castbar.player", C.Castbar.BuildSchema({ playerCast = true }))
	Add("portrait", C.Portrait.schema)
	Add("raidTarget", C.RaidTarget.schema)
	Add("auras", C.Auras.schema)
	Add("auraBar", C.AuraBar.schema)
	Add("auraIcon", UF.AuraIcon.schema)
	for _, unit in ipairs(UF.Units.order) do
		local def = UF.Units:GetDefinition(unit)
		Add("unit." .. unit, C.UnitFrame.BuildSchema(UF.Units:GetSpec(def)), def)
	end
	for _, row in ipairs({ "health", "power", "experience" }) do
		Add("row." .. row, C.TextBar.BuildSchema(UF.UnitRows.Spec(row)))
	end
	for _, kind in ipairs({ "member", "target" }) do
		Add("clickgrid." .. kind, CG:StyleSchema(kind), CG.definitions[kind])
	end
	Add("clickgrid.settings", CG.Config.schema)
	Add("clickgrid.slots", CG.Slots.schema)
	Add("clickgrid.bindings", CG.Bindings.schema)
	return subjects
end

local function Render()
	local parts = {}
	for _, subject in ipairs(Subjects()) do
		parts[#parts + 1] = "## " .. subject.name
		for _, line in ipairs(Options(subject.schema, "option ", {})) do parts[#parts + 1] = line end
		for _, line in ipairs(Values(subject.defaults, "default ", {})) do parts[#parts + 1] = line end
		for _, line in ipairs(Values(subject.resolved, "resolved ", {})) do parts[#parts + 1] = line end
		if subject.extra then
			for _, line in ipairs(Values(subject.extra, "definition ", {})) do parts[#parts + 1] = line end
		end
	end
	return table.concat(parts, "\n") .. "\n"
end

describe("Schema snapshot", function()
	it("keeps every schema, default and resolved default unchanged", function()
		local actual = Render()
		if os.getenv("UPDATE_SNAPSHOTS") then
			local file = assert(io.open(FIXTURE, "w"))
			file:write(actual)
			file:close()
			return
		end
		local file = io.open(FIXTURE)
		assert.is_not_nil(file, "missing " .. FIXTURE .. "; run with UPDATE_SNAPSHOTS=1")
		local expected = file:read("*a")
		file:close()
		if expected ~= actual then
			local expectedLines, line = {}, 0
			for l in expected:gmatch("[^\n]*\n") do expectedLines[#expectedLines + 1] = l end
			for l in actual:gmatch("[^\n]*\n") do
				line = line + 1
				if expectedLines[line] ~= l then
					error(string.format("snapshot differs at line %d:\n  expected %s  got      %s",
						line, tostring(expectedLines[line]), l))
				end
			end
			error("snapshot differs: expected " .. #expectedLines .. " lines, got " .. line)
		end
	end)
end)
