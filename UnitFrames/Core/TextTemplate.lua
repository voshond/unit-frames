local _, ns = ...
local Sources = ns.TextSources

--[[
The text composer: compiles a slot's content into a template that oUF tags,
live previews and samples all use, so they cannot disagree.

  Template.Compile({ pieces = { ... }, whileCasting = "spell" | "keep" })

Pieces, in order:
  { source = "<id>", before = "", after = "" }
      a source's text; the affixes show only when that text is non-empty
      (native WrapString, also for secret text). Unknown sources and
      "none" compile to nothing.
  { literal = " " }
      unconditional text. Only built-in presets use these, to keep their
      historical output; they are not a user-facing piece type.

whileCasting = "spell" shows the spell name instead while the unit casts.

The template has
  live(unit)      possibly secret text; "" for an absent unit
  sample(values)  the same for plain sample values
  events          union of the sources' events (space separated, in order)
  sharedEvents    set of those that carry no unit

No result is inspected: sources' nil becomes "" by a type check, affixes are
decided natively, and pieces are joined by string.format with every text and
literal passed as an argument, never interpolated into the format.
]]
local Template = {}
ns.TextTemplate = Template

local CAST_SOURCE = "cast.spell"

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

local function Nodes(pieces)
	local nodes = {}
	for _, piece in ipairs(pieces or {}) do
		if piece.literal then
			nodes[#nodes + 1] = { literal = piece.literal }
		else
			local source = piece.source and Sources.Get(piece.source)
			if source then
				local before, after = piece.before or "", piece.after or ""
				nodes[#nodes + 1] = { source = source, piece = piece, before = before, after = after,
					affixed = before ~= "" or after ~= "" }
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

function Template.Compile(def)
	local nodes = Nodes(def.pieces)
	local casting = def.whileCasting == "spell"
	local events, shared = {}, {}
	for _, node in ipairs(nodes) do
		if node.source then AddEvents(events, shared, node.source) end
	end
	if casting then AddEvents(events, shared, Sources.Get(CAST_SOURCE)) end

	local composeLive, composeSample = Composer(nodes, ReadLive), Composer(nodes, ReadSample)
	local SpellName, SampleSpellName = Sources.SpellName, Sources.SampleSpellName

	local template = {
		events = #events > 0 and table.concat(events, " ") or nil,
		sharedEvents = next(shared) and shared or nil,
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
		return composeLive(unit)
	end
	function template.sample(values)
		if casting then
			local name = SampleSpellName(values)
			if type(name) ~= "nil" then return name end
		end
		return composeSample(values)
	end
	return template
end
