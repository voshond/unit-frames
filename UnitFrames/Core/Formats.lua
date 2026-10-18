local _, ns = ...
local Sources, Template = ns.TextSources, ns.TextTemplate

--[[
Text formats: what a text slot shows ("Name", "Current / max", ...). Each
format is a preset, a named and fixed list of pieces over the text sources
(Core/TextSources.lua), compiled by the composer (Core/TextTemplate.lua).

Each format has
  label, pieces, whileCasting   its definition
  text(unit)      live text, secret-safe (the template's live function).
                  Registered as the oUF tag [uf:<id>].
  sample(values)  text for plain sample values (Workbench, test frames).
  events          oUF tag update events.
  sharedEvents    set of unitless events among them.

Sample values: { name, lastname, level, className, pvp, health, healthMax, power, powerMax, xp, xpMax, rested }
]]
local Formats = { list = {}, byId = {} }
ns.Formats = Formats

function Formats.Register(id, preset)
	local template = Template.Compile(preset)
	local relative = false
	for _, piece in ipairs(preset.pieces or {}) do
		local source = piece.source and Sources.Get(piece.source)
		if source and source.relative then relative = true end
	end
	local format = {
		id = id, label = preset.label, pieces = preset.pieces or {}, whileCasting = preset.whileCasting,
		-- Shows this bar's values: compiled per host, its own tag stays empty.
		relative = relative,
		template = template, text = template.live, sample = template.sample,
		events = template.events, sharedEvents = template.sharedEvents,
	}
	Formats.byId[id] = format
	Formats.list[#Formats.list + 1] = format
end

function Formats.Get(id)
	return Formats.byId[id] or Formats.byId.none
end

-- How much of a preset a host can show: "all", "some" or "none" (only
-- sources the host can't provide). Presets without sources show "all".
function Formats.Availability(id, context)
	local format = Formats.byId[id]
	if not format then return "none" end
	local available, missing = 0, 0
	for _, piece in ipairs(format.pieces) do
		local source = piece.source and Sources.Get(piece.source)
		if source then
			if Template.Available(source, context) then available = available + 1 else missing = missing + 1 end
		end
	end
	if missing == 0 then return "all" end
	return available > 0 and "some" or "none"
end

-- Select values for a list of format ids (schema "select" option), leaving
-- out presets the host can't show at all. `extra` entries are appended.
function Formats.Values(ids, context, extra)
	return function()
		local values = {}
		for _, id in ipairs(ids) do
			local format = Formats.byId[id]
			if format and Formats.Availability(id, context) ~= "none" then
				values[#values + 1] = { id, format.label }
			end
		end
		for _, entry in ipairs(extra or {}) do values[#values + 1] = entry end
		return values
	end
end

function Formats.SearchValues(ids, context)
	local values = {}
	for _, id in ipairs(ids) do
		local format = Formats.byId[id]
		if format and Formats.Availability(id, context) ~= "none" then values[#values + 1] = { id, format.label } end
	end
	return values
end

--[[
A preset as custom pieces { source, before, after } (fresh tables) plus its
casting behaviour. Literal text joins the next piece's `before` (or the last
piece's `after`), so it now disappears with that piece: missing identity
data no longer leaves a trailing space. Sources the host can't provide
become "none" in place.
]]
function Formats.Pieces(id, context)
	local format = Formats.byId[id]
	local pieces, pending = {}, ""
	for _, piece in ipairs(format and format.pieces or {}) do
		if piece.literal then
			pending = pending .. piece.literal
		else
			local source = Sources.Get(piece.source)
			local available = source and Template.Available(source, context)
			pieces[#pieces + 1] = { source = available and piece.source or "none",
				before = pending .. (piece.before or ""), after = piece.after or "" }
			pending = ""
		end
	end
	if pending ~= "" and #pieces > 0 then
		pieces[#pieces].after = pieces[#pieces].after .. pending
	end
	return pieces, format and format.whileCasting or "keep"
end

function Formats.Tag(id)
	return "[uf:" .. id .. "]"
end

Formats.PVP_FLAGS = {
	{ "off", "Not flagged" },
	{ "Alliance", "Alliance" },
	{ "Horde", "Horde" },
	{ "FFA", "Free-for-all" },
}

Formats.PVP_ATLASES = Sources.PVP_ATLASES

local function Source(id, before)
	return { source = id, before = before }
end

-- Identity presets keep their historical unconditional spaces (literals), so
-- missing identity data still leaves "42 ". The PvP flag brings its own space
-- and drops it when the unit isn't flagged.
local SPACE = { literal = " " }
local PVP = Source("pvp", " ")

Formats.Register("none", { label = "None" })
Formats.Register("resting", { label = "Resting (zZz)", pieces = { Source("resting") } })
Formats.Register("name", { label = "Character name", pieces = { Source("name") } })
Formats.Register("fullname", { label = "Full name", pieces = { Source("name"), Source("lastname", " ") } })
Formats.Register("level", { label = "Level", pieces = { Source("level") } })
Formats.Register("level:name", { label = "Level + name", pieces = { Source("level"), SPACE, Source("name") } })
Formats.Register("class", { label = "Class", pieces = { Source("class") } })
Formats.Register("level:class", { label = "Level + class", pieces = { Source("level"), SPACE, Source("class"), PVP } })
Formats.Register("smartlevel", { label = "Level (with elite/rare marker)", pieces = { Source("smartlevel") } })
Formats.Register("level:info", { label = "Level + class or creature type",
	pieces = { Source("smartlevel"), SPACE, Source("info"), PVP } })
Formats.Register("cast:name", { label = "Spell name while casting", pieces = { Source("cast.spell") } })

-- Kept as ids so saved settings resolve; a later step offers "while casting"
-- as a slot option instead of separate presets.
for _, id in ipairs({ "level:class", "level:info" }) do
	local base = Formats.Get(id)
	Formats.Register(id .. ":cast", { label = base.label .. " / spell name while casting",
		pieces = base.pieces, whileCasting = "spell" })
end

-- Values: the same six formats for health, power and experience ---------------

local VALUE_FORMATS = {
	{ "current", "Current", { "current" } },
	{ "value", "Current / max", { "current", "max" } },
	{ "percent", "Percent", { "percent" } },
	{ "current:percent", "Current | percent", { "current", "percent" } },
	{ "value:percent", "Current / max | percent", { "current", "max", "percent" } },
	{ "missing", "Missing", { "missing" } },
}

local SEPARATORS = { max = " / ", percent = " | " }

local function RegisterValueFormats(kind, label)
	local ids = {}
	for _, entry in ipairs(VALUE_FORMATS) do
		local pieces = {}
		for i, key in ipairs(entry[3]) do
			pieces[i] = Source(kind .. "." .. key, i > 1 and SEPARATORS[key] or nil)
		end
		local id = kind .. ":" .. entry[1]
		Formats.Register(id, { label = label .. ": " .. entry[2]:lower(), pieces = pieces })
		ids[#ids + 1] = id
	end
	return ids
end

local HEALTH_VALUES = RegisterValueFormats("health", "Health")
local POWER_VALUES = RegisterValueFormats("power", "Power")
local XP_VALUES = RegisterValueFormats("xp", "XP")
-- The same for whichever bar the slot is on (health, power or XP).
local BAR_VALUES = RegisterValueFormats("bar", "This bar")
Formats.Register("xp:rested", { label = "XP: rested", pieces = { Source("xp.rested") } })

-- Format id lists per bar kind (what a text slot on that bar can show).
local function List(...)
	local out = {}
	for i = 1, select("#", ...) do
		for _, id in ipairs((select(i, ...))) do
			out[#out + 1] = id
		end
	end
	return out
end

local IDENTITY = { "none", "name", "fullname", "level", "smartlevel", "level:name", "class", "level:class", "level:info", "resting" }
Formats.HEALTH = List(IDENTITY, HEALTH_VALUES, BAR_VALUES, { "cast:name", "level:class:cast", "level:info:cast" })
Formats.POWER = List(IDENTITY, POWER_VALUES, BAR_VALUES)
Formats.EXPERIENCE = List({ "none", "level", "resting" }, XP_VALUES, { "xp:rested" }, BAR_VALUES)
