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

Sample values: { name, level, className, pvp, health, healthMax, power, powerMax, xp, xpMax, rested }
]]
local Formats = { list = {}, byId = {} }
ns.Formats = Formats

function Formats.Register(id, preset)
	local template = Template.Compile(preset)
	local format = {
		id = id, label = preset.label, pieces = preset.pieces or {}, whileCasting = preset.whileCasting,
		template = template, text = template.live, sample = template.sample,
		events = template.events, sharedEvents = template.sharedEvents,
	}
	Formats.byId[id] = format
	Formats.list[#Formats.list + 1] = format
end

function Formats.Get(id)
	return Formats.byId[id] or Formats.byId.none
end

-- Select values for a list of format ids (schema "select" option).
function Formats.Values(ids)
	return function()
		local values = {}
		for _, id in ipairs(ids) do
			local format = Formats.byId[id]
			if format then
				values[#values + 1] = { id, format.label }
			end
		end
		return values
	end
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
Formats.Register("name", { label = "Name", pieces = { Source("name") } })
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

local IDENTITY = { "none", "name", "level", "smartlevel", "level:name", "class", "level:class", "level:info", "resting" }
Formats.HEALTH = List(IDENTITY, HEALTH_VALUES, { "cast:name", "level:class:cast", "level:info:cast" })
Formats.POWER = List(IDENTITY, POWER_VALUES)
Formats.EXPERIENCE = List({ "none", "level", "resting" }, XP_VALUES, { "xp:rested" })
