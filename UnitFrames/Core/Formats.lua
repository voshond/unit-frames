local _, ns = ...
local Util = ns.Util

--[[
Text formats: what a text slot shows ("Name", "Current / max", ...).

Each format has
  text(unit)      live text, secret-safe: values only pass through
                  AbbreviateNumbers / string.format, never maths.
                  Registered as the oUF tag [uf:<id>].
  sample(values)  text for plain sample values (Workbench, test frames).
  events          oUF tag update events; shared = true when they have no unit.
  sharedEvents    set of unitless events when mixed with unit events.

Sample values: { name, level, className, pvp, health, healthMax, power, powerMax, xp, xpMax, rested }
]]
local Formats = { list = {}, byId = {} }
ns.Formats = Formats

local function Short(value)
	return AbbreviateNumbers(value)
end

local function Percent(cur, max)
	if Util.IsSecret(cur) or Util.IsSecret(max) or max == 0 then
		return 0
	end
	return math.floor(cur / max * 100 + 0.5)
end

function Formats.Register(id, format)
	format.id = id
	-- Explicit oUF tag refreshes also run on hidden frames with no unit.
	-- Avoid reading missing unit data or passing nil into native formatters.
	local text = format.text
	format.text = function(unit)
		if not unit or not UnitExists(unit) then
			return ""
		end
		return text(unit)
	end
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

local HEALTH_EVENTS = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION"
local POWER_EVENTS = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER"
local XP_EVENTS = "PLAYER_XP_UPDATE UPDATE_EXHAUSTION PLAYER_LEVEL_UP"
local PVP_EVENTS = "UNIT_FACTION PLAYER_PVP_FLAG_CHANGED PLAYER_REGEN_ENABLED"
local PVP_SHARED_EVENTS = { PLAYER_PVP_FLAG_CHANGED = true, PLAYER_REGEN_ENABLED = true }

Formats.PVP_FLAGS = {
	{ "off", "Not flagged" },
	{ "Alliance", "Alliance" },
	{ "Horde", "Horde" },
	{ "FFA", "Free-for-all" },
}

-- Forever's PvP atlases. Only samples select them in Lua; live flags use
-- Blizzard's secret-safe helper, including mercenary and FFA handling.
local PVP_ATLASES = {
	Alliance = "UI-HUD-UnitFrame-SmallCircle-Alliance",
	Horde = "UI-HUD-UnitFrame-SmallCircle-Horde",
	FFA = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
}

local function PvPFlag(unit)
	local info = UnitFrameUtil.GetUnitPvPIndicatorDisplayInfo(unit, true)
	-- WrapString returns empty text for an empty atlas, even when secret.
	-- Zero dimensions let the inline flag follow the text's font size.
	return C_StringUtil.WrapString(info.pvpIconAtlas, " |A:", ":0:0:0:0|a")
end

local function SamplePvPFlag(values)
	return C_StringUtil.WrapString(PVP_ATLASES[values.pvp] or "", " |A:", ":0:0:0:0|a")
end

Formats.Register("none", {
	label = "None",
	text = function() return "" end,
	sample = function() return "" end,
})

Formats.Register("name", {
	label = "Name",
	events = "UNIT_NAME_UPDATE",
	text = function(unit) return UnitName(unit) end,
	sample = function(v) return v.name end,
})

Formats.Register("level", {
	label = "Level",
	events = "UNIT_LEVEL PLAYER_LEVEL_UP",
	text = function(unit) return UnitLevel(unit) end,
	sample = function(v) return tostring(v.level) end,
})

Formats.Register("level:name", {
	label = "Level + name",
	events = "UNIT_NAME_UPDATE UNIT_LEVEL PLAYER_LEVEL_UP",
	text = function(unit) return string.format("%s %s", UnitLevel(unit) or "", (UnitName(unit)) or "") end,
	sample = function(v) return string.format("%s %s", v.level, v.name) end,
})

Formats.Register("class", {
	label = "Class",
	text = function(unit) return (UnitClass(unit)) end,
	sample = function(v) return v.className end,
})

Formats.Register("level:class", {
	label = "Level + class",
	events = "UNIT_LEVEL PLAYER_LEVEL_UP " .. PVP_EVENTS,
	sharedEvents = PVP_SHARED_EVENTS,
	text = function(unit) return string.format("%s %s%s", UnitLevel(unit) or "", (UnitClass(unit)) or "", PvPFlag(unit)) end,
	sample = function(v) return string.format("%s %s%s", v.level, v.className, SamplePvPFlag(v)) end,
})

-- Level with markers: "??" for skull level, "+" elite, "R" rare, "R+" rare
-- elite, "B" boss. Level and classification are not secret.
local CLASSIFICATION = { elite = "+", rare = "R", rareelite = "R+", worldboss = "B" }

local function SmartLevel(level, classification)
	local text = level and level > 0 and tostring(level) or "??"
	return text .. (CLASSIFICATION[classification] or "")
end

Formats.Register("smartlevel", {
	label = "Level (with elite/rare marker)",
	events = "UNIT_LEVEL PLAYER_LEVEL_UP UNIT_CLASSIFICATION_CHANGED",
	text = function(unit) return SmartLevel(UnitLevel(unit), UnitClassification(unit)) end,
	sample = function(v) return SmartLevel(v.level, v.classification) end,
})

-- Players show their class, NPCs their creature type (which may be secret).
Formats.Register("level:info", {
	label = "Level + class or creature type",
	events = "UNIT_LEVEL PLAYER_LEVEL_UP UNIT_CLASSIFICATION_CHANGED " .. PVP_EVENTS,
	sharedEvents = PVP_SHARED_EVENTS,
	text = function(unit)
		local info
		if UnitIsPlayer(unit) then
			info = (UnitClass(unit)) or ""
		else
			info = UnitCreatureType(unit) or ""
		end
		return string.format("%s %s%s", SmartLevel(UnitLevel(unit), UnitClassification(unit)), info, PvPFlag(unit))
	end,
	sample = function(v)
		local info = v.isPlayer == false and (v.creatureType or "") or v.className
		return string.format("%s %s%s", SmartLevel(v.level, v.classification), info, SamplePvPFlag(v))
	end,
})

-- Values: the same six formats for health, power and experience ---------------

--[[
Registers <kind>:current, :value, :percent, :current:percent, :value:percent
and :missing. `api` provides
  live(unit)         current, max (may be secret)
  livePercent(unit)  0..100 (may be secret)
  liveMissing(unit)  missing amount as text, "" when nothing is missing
  sample             keys of current and max in the sample values
]]
local VALUE_FORMATS = {
	{ "current", "Current" },
	{ "value", "Current / max" },
	{ "percent", "Percent" },
	{ "current:percent", "Current | percent" },
	{ "value:percent", "Current / max | percent" },
	{ "missing", "Missing" },
}

local function SampleMissing(cur, max)
	local missing = max - cur
	return missing > 0 and Short(missing) or ""
end

local function RegisterValueFormats(kind, label, events, shared, api)
	local curKey, maxKey = api.sample[1], api.sample[2]
	local texts = {
		current = {
			function(unit) return Short((api.live(unit))) end,
			function(v) return Short(v[curKey]) end,
		},
		value = {
			function(unit)
				local cur, max = api.live(unit)
				return string.format("%s / %s", Short(cur), Short(max))
			end,
			function(v) return string.format("%s / %s", Short(v[curKey]), Short(v[maxKey])) end,
		},
		percent = {
			function(unit) return string.format("%d%%", api.livePercent(unit)) end,
			function(v) return string.format("%d%%", Percent(v[curKey], v[maxKey])) end,
		},
		["current:percent"] = {
			function(unit) return string.format("%s | %d%%", Short((api.live(unit))), api.livePercent(unit)) end,
			function(v) return string.format("%s | %d%%", Short(v[curKey]), Percent(v[curKey], v[maxKey])) end,
		},
		["value:percent"] = {
			function(unit)
				local cur, max = api.live(unit)
				return string.format("%s / %s | %d%%", Short(cur), Short(max), api.livePercent(unit))
			end,
			function(v)
				return string.format("%s / %s | %d%%", Short(v[curKey]), Short(v[maxKey]), Percent(v[curKey], v[maxKey]))
			end,
		},
		missing = {
			function(unit) return api.liveMissing(unit) end,
			function(v) return SampleMissing(v[curKey], v[maxKey]) end,
		},
	}
	local ids = {}
	for _, entry in ipairs(VALUE_FORMATS) do
		local id = kind .. ":" .. entry[1]
		Formats.Register(id, {
			label = label .. ": " .. entry[2]:lower(),
			events = events, shared = shared,
			text = texts[entry[1]][1],
			sample = texts[entry[1]][2],
		})
		ids[#ids + 1] = id
	end
	return ids
end

local HEALTH_VALUES = RegisterValueFormats("health", "Health", HEALTH_EVENTS, false, {
	live = function(unit) return UnitHealth(unit), UnitHealthMax(unit) end,
	livePercent = function(unit) return UnitHealthPercent(unit, true, ns.Colors.PercentCurve()) end,
	liveMissing = function(unit) return C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit)) end,
	sample = { "health", "healthMax" },
})

local POWER_VALUES = RegisterValueFormats("power", "Power", POWER_EVENTS, false, {
	live = function(unit) return UnitPower(unit), UnitPowerMax(unit) end,
	livePercent = function(unit) return UnitPowerPercent(unit, nil, false, ns.Colors.PercentCurve()) end,
	liveMissing = function(unit) return C_StringUtil.TruncateWhenZero(UnitPowerMissing(unit)) end,
	sample = { "power", "powerMax" },
})

-- Experience is player only and not secret, but stays pass-through where it can.
local function XP()
	return UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0
end

local XP_VALUES = RegisterValueFormats("xp", "XP", XP_EVENTS, true, {
	live = function() return XP() end,
	livePercent = function()
		local cur, max = XP()
		return Percent(cur, max)
	end,
	liveMissing = function()
		local cur, max = XP()
		if Util.IsSecret(cur) or Util.IsSecret(max) then
			return ""
		end
		return SampleMissing(cur, max)
	end,
	sample = { "xp", "xpMax" },
})

Formats.Register("xp:rested", {
	label = "XP: rested",
	events = XP_EVENTS, shared = true,
	text = function()
		local _, _, rested = XP()
		return Util.IsSecret(rested) and Short(rested) or (rested > 0 and ("Rested " .. Short(rested)) or "")
	end,
	sample = function(v) return v.rested > 0 and ("Rested " .. Short(v.rested)) or "" end,
})

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

local IDENTITY = { "none", "name", "level", "smartlevel", "level:name", "class", "level:class", "level:info" }
Formats.HEALTH = List(IDENTITY, HEALTH_VALUES)
Formats.POWER = List(IDENTITY, POWER_VALUES)
Formats.EXPERIENCE = List({ "none", "level" }, XP_VALUES, { "xp:rested" })
