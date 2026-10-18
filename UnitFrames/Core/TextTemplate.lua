local _, ns = ...
local Sources = ns.TextSources

--[[
The text composer: compiles a slot's content into a template that oUF tags,
live previews and samples all use, so they cannot disagree.

  Template.Compile({ pieces = { ... }, whileCasting = "spell" | "keep",
    whileStatus = "status" | "keep" }, context)
  Template.Get(def, context)   the same, shared between equal contents

context describes the slot's host: { player = false } on frames that don't
always show the player, { bar = "health" } on a health bar's slots. Sources a
host can't provide (player-only values elsewhere, this bar's values outside
a bar) compile to nothing, like unknown ones. No context means every source
except this bar's values (the global [uf:<preset>] tags).

Pieces, in order:
  { source = "<id>", before = "", after = "" }
      a source's text; the affixes show only when that text is non-empty
      (native WrapString, also for secret text). Unknown sources and
      "none" compile to nothing.
  { literal = " " }
      unconditional text. Only built-in presets use these, to keep their
      historical output; they are not a user-facing piece type.

whileCasting = "spell" shows the spell name instead while the unit casts.
whileStatus = "status" (the default) shows "Dead" or "Offline" in place of
health and power values while the unit is dead, a ghost or offline: the
first health value shows the word, the other values nothing, so their
affixes disappear with them ("1 / 82" becomes "Dead", a power text empties).
Texts that show the Offline / dead source themselves keep their values.

The template has
  live(unit)      possibly secret text; "" for an absent unit
  sample(values)  the same for plain sample values
  events          union of the sources' events (space separated, in order)
  sharedEvents    set of those that carry no unit
  sources         ids of the sources it shows, in order
  empty           true when it can never show anything

No result is inspected: sources' nil becomes "" by a type check, affixes are
decided natively, and pieces are joined by string.format with every text and
literal passed as an argument, never interpolated into the format.
]]
local Template = {}
ns.TextTemplate = Template

local CAST_SOURCE = "cast.spell"
local STATUS_SOURCE = "status"

-- Health and power values, which a dead or offline unit replaces.
local function StatusValue(source)
	return source.id:match("^health%.") ~= nil or source.id:match("^power%.") ~= nil
end

local function AddEvents(events, shared, source)
	if not source.events then return end
	for event in source.events:gmatch("%S+") do
		if not events[event] then
			events[event] = true
			events[#events + 1] = event
		end
		if source.shared or (source.sharedEvents and source.sharedEvents[event]) then
			shared[event] = true
		end
	end
end

-- Whether a host with `context` can show `source`. This bar's values need a
-- bar; player-only values need a host that isn't known to be another unit.
function Template.Available(source, context)
	source = Sources.Resolve(source, context)
	if not source then return false end
	return not source.player or not context or context.player ~= false
end

local function Nodes(pieces, context)
	local nodes = {}
	for _, piece in ipairs(pieces or {}) do
		if piece.literal then
			nodes[#nodes + 1] = { literal = piece.literal }
		else
			local source = piece.source and Sources.Get(piece.source)
			if source and Template.Available(source, context) then
				local before, after = piece.before or "", piece.after or ""
				nodes[#nodes + 1] = { source = Sources.Resolve(source, context), piece = piece,
					before = before, after = after, affixed = before ~= "" or after ~= "" }
			end
		end
	end
	return nodes
end

-- One node's text. `read` picks the live or the sample function.
local function NodeText(node, read, arg)
	if node.literal then return node.literal end
	local text = read(node, arg)
	if type(text) == "nil" then return "" end
	if node.affixed then
		if type(text) ~= "string" then text = string.format("%s", text) end
		return C_StringUtil.WrapString(text, node.before, node.after)
	end
	return text
end

local function Composer(nodes, read)
	local n = #nodes
	if n == 0 then
		return function() return "" end
	end
	-- A single plain source passes its value through unchanged.
	if n == 1 and nodes[1].source and not nodes[1].affixed then
		local node = nodes[1]
		return function(arg)
			local text = read(node, arg)
			if type(text) == "nil" then return "" end
			return text
		end
	end
	local fmt = string.rep("%s", n)
	local args = {}
	return function(arg)
		for i = 1, n do
			args[i] = NodeText(nodes[i], read, arg)
		end
		local text = string.format(fmt, unpack(args, 1, n))
		for i = 1, n do args[i] = nil end
		return text
	end
end

local function ReadLive(node, unit) return node.source.live(unit, node.piece) end
local function ReadSample(node, values) return node.source.sample(values, node.piece) end

-- Reads with the status in place of the values; `state` is { arg, text }.
local function StatusReader(read)
	return function(node, state)
		if node.statusText then return state[2] end
		if node.statusValue then return nil end
		return read(node, state[1])
	end
end

-- Marks the value nodes a status replaces; false when the text has none or
-- shows the status itself.
local function MarkStatusNodes(nodes)
	local marked = false
	for _, node in ipairs(nodes) do
		if node.source and node.source.id == STATUS_SOURCE then return false end
	end
	for _, node in ipairs(nodes) do
		if node.source and StatusValue(node.source) then
			node.statusValue = true
			if not marked and node.source.id:match("^health%.") then node.statusText = true end
			marked = true
		end
	end
	return marked
end

function Template.Compile(def, context)
	local nodes = Nodes(def.pieces, context)
	local casting = def.whileCasting == "spell"
	local status = def.whileStatus ~= "keep" and MarkStatusNodes(nodes)
	local events, shared, sources = {}, {}, {}
	for _, node in ipairs(nodes) do
		if node.source then
			AddEvents(events, shared, node.source)
			sources[#sources + 1] = node.source.id
		end
	end
	if casting then AddEvents(events, shared, Sources.Get(CAST_SOURCE)) end
	if status then AddEvents(events, shared, Sources.Get(STATUS_SOURCE)) end

	local composeLive, composeSample = Composer(nodes, ReadLive), Composer(nodes, ReadSample)
	local statusLive = status and Composer(nodes, StatusReader(ReadLive))
	local statusSample = status and Composer(nodes, StatusReader(ReadSample))
	local statusState = {}
	local SpellName, SampleSpellName = Sources.SpellName, Sources.SampleSpellName
	local UnitStatus, STATUS_TEXT = Sources.UnitStatus, Sources.STATUS_TEXT

	local template = {
		events = #events > 0 and table.concat(events, " ") or nil,
		sharedEvents = next(shared) and shared or nil,
		sources = sources,
		empty = #nodes == 0 and not casting,
	}
	-- Explicit oUF tag refreshes also run on hidden frames with no unit.
	-- Avoid reading missing unit data or passing nil into native formatters.
	function template.live(unit)
		if not unit or not UnitExists(unit) then
			return ""
		end
		if casting then
			local name = SpellName(unit)
			if type(name) ~= "nil" then return name end
		end
		local word = status and STATUS_TEXT[UnitStatus(unit)]
		if word then
			statusState[1], statusState[2] = unit, word
			return statusLive(statusState)
		end
		return composeLive(unit)
	end
	function template.sample(values)
		if casting then
			local name = SampleSpellName(values)
			if type(name) ~= "nil" then return name end
		end
		local word = status and STATUS_TEXT[values.status]
		if word then
			statusState[1], statusState[2] = values, word
			return statusSample(statusState)
		end
		return composeSample(values)
	end
	return template
end

-- Signature of what a definition shows on a host: only the pieces it can
-- show, as concrete sources with the options they use, with length-prefixed
-- text so no two contents encode alike.
local function Encode(text)
	text = tostring(text or "")
	return #text .. ":" .. text
end

function Template.Signature(def, context)
	local out = { def.whileCasting == "spell" and "c" or "-", def.whileStatus == "keep" and "k" or "s" }
	for _, node in ipairs(Nodes(def.pieces, context)) do
		if node.literal then
			out[#out + 1] = "l" .. Encode(node.literal)
		else
			local options = {}
			for _, opt in ipairs(Sources.OPTIONS) do
				if node.source.options and node.source.options[opt.key] then
					local value = node.piece[opt.key]
					if value == nil then value = opt.default end
					options[#options + 1] = Encode(opt.key) .. Encode(value)
				end
			end
			out[#out + 1] = "s" .. Encode(node.source.id) .. Encode(node.before) .. Encode(node.after)
				.. #options .. ":" .. table.concat(options)
		end
	end
	return table.concat(out)
end

-- Templates held by texts, keyed by signature. Weak values: a template no
-- text holds any more is dropped.
local cache = setmetatable({}, { __mode = "v" })

function Template.Get(def, context)
	local signature = Template.Signature(def, context)
	local template = cache[signature]
	if not template then
		template = Template.Compile(def, context)
		template.signature = signature
		cache[signature] = template
	end
	return template
end
