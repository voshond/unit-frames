local _, ns = ...
local Util = ns.Util

--[[
A schema is a list of option descriptors. It is the single definition of an
option: defaults, resolution, validation and the generated controls
(Workbench inspector, later the settings window and Edit Mode) all read it.

Descriptor fields:
  key       config key (required)
  type      toggle | range | select | color | font | statusbar | border | background | text | group
  label     display name (defaults to key)
  tooltip   help text
  hint      visible inspector help text (optional)
  default   value used when neither config nor theme provide one
  inherit   dot path into the theme, used when config has no value ("colors.health")
  min, max, step          for range
  values    for select: array of { value, label } or a function returning one
  schema    for group: nested schema
  defaults  for group: per-key default overrides, lets one group schema be reused
            with different defaults (e.g. Bar border off, Castbar border on)
  hidden(resolvedGroup)   hide the control when this returns true
]]
local Schema = {}
ns.Schema = Schema

local VALUE_TYPES = {
	toggle = "boolean",
	range = "number",
	select = nil, -- any of the listed values
	color = "table",
	font = "string",
	statusbar = "string",
	border = "string",
	background = "string",
	text = "string",
}

local function DefaultFor(opt, overrides)
	if overrides and overrides[opt.key] ~= nil then
		return overrides[opt.key]
	end
	return opt.default
end

-- Static defaults only (no theme). Used for AceDB defaults and tests.
function Schema.Defaults(schema, overrides)
	local out = {}
	for _, opt in ipairs(schema) do
		if opt.type == "group" then
			local groupOverrides = Util.Merge(Util.Copy(opt.defaults or {}), (overrides and overrides[opt.key]) or {})
			out[opt.key] = Schema.Defaults(opt.schema, groupOverrides)
		else
			local value = DefaultFor(opt, overrides)
			if value ~= nil then
				out[opt.key] = Util.Copy(value)
			end
		end
	end
	return out
end

--[[
Resolves the effective value of every option:
  1. the value in `config`
  2. the group's `defaults` override
  3. the theme value at `inherit`
  4. the descriptor `default`
Returns a fresh table; callers may keep it.
]]
function Schema.Resolve(schema, config, theme, overrides)
	local out = {}
	for _, opt in ipairs(schema) do
		local value = config and config[opt.key]
		if opt.type == "group" then
			local groupOverrides = Util.Merge(Util.Copy(opt.defaults or {}), (overrides and overrides[opt.key]) or {})
			out[opt.key] = Schema.Resolve(opt.schema, type(value) == "table" and value or nil, theme, groupOverrides)
		else
			if value == nil and overrides and overrides[opt.key] ~= nil then
				value = overrides[opt.key]
			end
			if value == nil and opt.inherit and theme then
				value = Util.GetPath(theme, opt.inherit)
			end
			if value == nil then
				value = opt.default
			end
			out[opt.key] = Util.Copy(value)
		end
	end
	return out
end

-- Composition. Each returns a new list and never mutates its inputs; the
-- descriptors themselves are shared, so copy the result before changing them.

-- Joins schemas in order.
function Schema.Concat(...)
	local out = {}
	for i = 1, select("#", ...) do
		for _, opt in ipairs((select(i, ...))) do out[#out + 1] = opt end
	end
	return out
end

-- Inserts `options` after the descriptor `afterKey`, or first when the schema
-- has no such key.
function Schema.Insert(schema, afterKey, options)
	local out, inserted = {}, false
	for _, opt in ipairs(schema) do
		out[#out + 1] = opt
		if opt.key == afterKey and not inserted then
			for _, extra in ipairs(options) do out[#out + 1] = extra end
			inserted = true
		end
	end
	if not inserted then return Schema.Concat(options, schema) end
	return out
end

-- Leaves out the descriptors whose keys are set in `keys`.
function Schema.Without(schema, keys)
	local out = {}
	for _, opt in ipairs(schema) do
		if not (keys and keys[opt.key]) then out[#out + 1] = opt end
	end
	return out
end

-- Replaces descriptor `key` with a copy carrying the changed `fields`.
function Schema.Override(schema, key, fields)
	local out = {}
	for i, opt in ipairs(schema) do
		if opt.key == key then
			opt = Util.Copy(opt)
			for field, value in pairs(fields) do opt[field] = value end
		end
		out[i] = opt
	end
	return out
end

function Schema.GetValues(opt)
	if type(opt.values) == "function" then
		return opt.values()
	end
	return opt.values or {}
end

-- Returns the descriptor for a dot path ("background.color") or nil.
function Schema.Find(schema, path)
	local current = schema
	local found
	for key in string.gmatch(path, "[^%.]+") do
		found = nil
		for _, opt in ipairs(current or {}) do
			if opt.key == key then
				found = opt
				break
			end
		end
		if not found then
			return nil
		end
		current = found.schema
	end
	return found
end

-- Returns a list of human-readable problems with `config` (empty when valid).
function Schema.Validate(schema, config, prefix, errors)
	errors = errors or {}
	prefix = prefix or ""
	for _, opt in ipairs(schema) do
		local path = prefix .. opt.key
		local value = config and config[opt.key]
		if value ~= nil then
			if opt.type == "group" then
				if type(value) ~= "table" then
					errors[#errors + 1] = path .. ": expected table"
				else
					Schema.Validate(opt.schema, value, path .. ".", errors)
				end
			elseif opt.type == "select" then
				local ok = false
				for _, entry in ipairs(Schema.GetValues(opt)) do
					if entry[1] == value then
						ok = true
						break
					end
				end
				if not ok then
					errors[#errors + 1] = path .. ": invalid choice " .. tostring(value)
				end
			else
				local expected = VALUE_TYPES[opt.type]
				if expected and type(value) ~= expected then
					errors[#errors + 1] = path .. ": expected " .. expected
				elseif opt.type == "range" and ((opt.min and value < opt.min) or (opt.max and value > opt.max)) then
					errors[#errors + 1] = path .. ": out of range"
				end
			end
		end
	end
	return errors
end
