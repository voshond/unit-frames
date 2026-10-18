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
  inline    for group: shown inside its parent's section instead of as a
            section of its own
  onSet, invoke           settings-store hooks (Core/Store.lua)
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
Returns a fresh table callers may keep, except inside a sharing scope
(Schema.Shared below), where results are shared and read-only.

Group default overrides are kept as layers (lowest priority first) rather
than merged copies. Each group's effective overrides are its `defaults`
merged with (Util.Merge) the outer group's effective overrides at its key, so
a key's value folds the layers from the highest down: the highest value
wins, except that tables merge with the tables beneath them. Values are only
computed where config leaves an option unset. Layers are shared schema and
caller tables and are never modified.
]]
local NO_LAYERS, NO_DEFAULTS = {}, {}

local function LayeredValue(layers, key)
	local value
	for i = #layers, 1, -1 do
		local layerValue = layers[i][key]
		if layerValue ~= nil then
			if value == nil then
				value = layerValue
			elseif type(value) ~= "table" then
				break
			elseif type(layerValue) == "table" then
				value = Util.Merge(Util.Copy(layerValue), value)
			end
		end
	end
	return value
end

-- Lists holding only a group's own defaults, shared per descriptor: most
-- groups have no outer override, and layer lists are never modified.
local defaultLayers = setmetatable({}, { __mode = "k" })

local function DefaultLayers(opt)
	local layers = defaultLayers[opt]
	if not layers then
		layers = { opt.defaults or NO_DEFAULTS }
		defaultLayers[opt] = layers
	end
	return layers
end

-- The layers for group `opt`: its own defaults beneath the tables the outer
-- layers hold at its key. A non-table above every table leaves only the
-- defaults (as the merged form treated a missing or false group override).
local function GroupLayers(opt, layers)
	local key, first = opt.key, nil
	for i = #layers, 1, -1 do
		local layerValue = layers[i][key]
		if type(layerValue) == "table" then
			first = i
			break
		elseif layerValue ~= nil then
			break
		end
	end
	if not first then
		return DefaultLayers(opt)
	end
	local out = { opt.defaults or NO_DEFAULTS }
	for i = 1, first do
		local layerValue = layers[i][key]
		if type(layerValue) == "table" then
			out[#out + 1] = layerValue
		end
	end
	return out
end

local function ResolveValue(opt, value, theme, layers)
	if value ~= nil then return value, "Custom value" end
	value = LayeredValue(layers, opt.key)
	if value ~= nil then return value, "Frame default" end
	if opt.inherit and theme then
		value = Util.GetPath(theme, opt.inherit)
		if value ~= nil then return value, "Shared appearance" end
	end
	return opt.default, "Built-in default"
end

function Schema.Source(schema, config, theme, path, reset)
	local layers = NO_LAYERS
	for key in path:gmatch("[^%.]+") do
		local opt = Schema.Find(schema, key)
		if not opt then return end
		local value = config and config[key]
		if opt.type ~= "group" then
			if reset then value = nil end
			local resolved, source = ResolveValue(opt, value, theme, layers)
			return source, Util.Copy(resolved), opt.inherit
		end
		layers, schema = GroupLayers(opt, layers), opt.schema
		config = type(value) == "table" and value or nil
	end
end

local function Resolve(schema, config, theme, layers)
	-- Presized: growing a table key by key reallocates it several times.
	local out = table.create(0, #schema)
	for _, opt in ipairs(schema) do
		local value = config and config[opt.key]
		if opt.type == "group" then
			out[opt.key] = Resolve(opt.schema, type(value) == "table" and value or nil, theme, GroupLayers(opt, layers))
		else
			value = ResolveValue(opt, value, theme, layers)
			out[opt.key] = Util.Copy(value)
		end
	end
	return out
end

--[[
Sharing scope. Inside Schema.Shared(fn, ...), Schema.Memo hands out one
result per build function and keys, so a refresh applying the same style
to many frames resolves it once. Shared results must be treated as
read-only, and keyed tables must not change while the scope is open.
Outside a scope every call builds afresh.
]]
local scope
local NONE = {}

local function Sub(map, key)
	if key == nil then key = NONE end
	local sub = map[key]
	if not sub then
		sub = {}
		map[key] = sub
	end
	return sub
end

-- Runs fn(...) in a sharing scope (nested calls join the open one).
function Schema.Shared(fn, ...)
	if scope then
		fn(...)
		return
	end
	scope = {}
	-- A failure must not leave the scope open; it is rethrown unchanged.
	local ok, err = pcall(fn, ...)
	scope = nil
	if not ok then
		error(err, 0)
	end
end

-- build(a, b, c, ...) once per scope for the keys a, b and c; extra
-- arguments are passed on but are not part of the key.
function Schema.Memo(build, a, b, c, ...)
	if not scope then
		return build(a, b, c, ...)
	end
	local byC = Sub(Sub(Sub(scope, build), a), b)
	local key = c == nil and NONE or c
	local value = byC[key]
	if value == nil then
		value = build(a, b, c, ...)
		byC[key] = value
	end
	return value
end

local function ResolvePlain(schema, config, theme)
	ns.Perf:Count("resolveBuild")
	return Resolve(schema, config, theme, NO_LAYERS)
end

function Schema.Build(build, spec)
	ns.Perf:Count("schemaBuild")
	ns.Perf:Begin("schema build")
	local schema = build(spec)
	ns.Perf:End("schema build")
	return schema
end

-- Fresh tables outside a sharing scope; shared read-only ones inside it.
function Schema.Resolve(schema, config, theme, overrides)
	local Perf = ns.Perf
	Perf:Count("resolveCall")
	Perf:Begin("resolve")
	local resolved
	if overrides then
		Perf:Count("resolveBuild")
		resolved = Resolve(schema, config, theme, { overrides })
	else
		resolved = Schema.Memo(ResolvePlain, schema, config, theme)
	end
	Perf:End("resolve")
	return resolved
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

-- { r, g, b } or { r, g, b, a } with numbers from 0 to 1.
local function ValidColor(color)
	local count = 0
	for key, channel in pairs(color) do
		if type(key) ~= "number" or key < 1 or key > 4 or type(channel) ~= "number"
			or channel ~= channel or channel < 0 or channel > 1 then
			return false
		end
		count = count + 1
	end
	return count >= 3 and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil
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
				elseif opt.type == "range" and (value ~= value or (opt.min and value < opt.min) or (opt.max and value > opt.max)) then
					errors[#errors + 1] = path .. ": out of range"
				elseif opt.type == "color" and not ValidColor(value) then
					errors[#errors + 1] = path .. ": expected { r, g, b[, a] }"
				end
			end
		end
	end
	return errors
end

-- Option types that hold no saved value (UI actions, drop targets).
local NO_VALUE = { action = true, actionslot = true }

--[[
A copy of `config` with only the options `schema` defines and valid values,
for data from outside the running addon (imported strings, other versions).
Returns the copy and the dropped paths. `config` is never changed.
]]
function Schema.Sanitize(schema, config, prefix, dropped)
	dropped, prefix = dropped or {}, prefix or ""
	local out, known = {}, {}
	if type(config) ~= "table" then
		if config ~= nil then dropped[#dropped + 1] = prefix ~= "" and prefix:sub(1, -2) or "(all)" end
		return out, dropped
	end
	for _, opt in ipairs(schema) do
		known[opt.key] = true
		local value, path = config[opt.key], prefix .. opt.key
		if value == nil then
			-- unset: inherited or default
		elseif opt.type == "group" and type(value) == "table" then
			local group = Schema.Sanitize(opt.schema, value, path .. ".", dropped)
			if next(group) then out[opt.key] = group end
		elseif opt.type ~= "group" and not NO_VALUE[opt.type] and #Schema.Validate({ opt }, { [opt.key] = value }) == 0 then
			out[opt.key] = Util.Copy(value)
		else
			dropped[#dropped + 1] = path
		end
	end
	for key in pairs(config) do
		if not known[key] then dropped[#dropped + 1] = prefix .. tostring(key) end
	end
	return out, dropped
end
