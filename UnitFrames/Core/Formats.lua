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

Sample values: { name, level, health, healthMax, power, powerMax, xp, xpMax, rested }
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
	text = function(unit) return string.format("%s %s", UnitLevel(unit), UnitName(unit)) end,
	sample = function(v) return string.format("%s %s", v.level, v.name) end,
})

-- Health ----------------------------------------------------------------------

Formats.Register("health:value", {
	label = "Health: current / max",
	events = HEALTH_EVENTS,
	text = function(unit)
		return string.format("%s / %s", Short(UnitHealth(unit)), Short(UnitHealthMax(unit)))
	end,
	sample = function(v) return string.format("%s / %s", Short(v.health), Short(v.healthMax)) end,
})

Formats.Register("health:current", {
	label = "Health: current",
	events = HEALTH_EVENTS,
	text = function(unit) return Short(UnitHealth(unit)) end,
	sample = function(v) return Short(v.health) end,
})

Formats.Register("health:percent", {
	label = "Health: percent",
	events = HEALTH_EVENTS,
	text = function(unit)
		return string.format("%d%%", UnitHealthPercent(unit, true, ns.Colors.PercentCurve()))
	end,
	sample = function(v) return string.format("%d%%", Percent(v.health, v.healthMax)) end,
})

Formats.Register("health:current:percent", {
	label = "Health: current | percent",
	events = HEALTH_EVENTS,
	text = function(unit)
		return string.format("%s | %d%%", Short(UnitHealth(unit)), UnitHealthPercent(unit, true, ns.Colors.PercentCurve()))
	end,
	sample = function(v) return string.format("%s | %d%%", Short(v.health), Percent(v.health, v.healthMax)) end,
})

Formats.Register("health:missing", {
	label = "Health: missing",
	events = HEALTH_EVENTS,
	text = function(unit) return C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit)) end,
	sample = function(v)
		local missing = v.healthMax - v.health
		return missing > 0 and Short(missing) or ""
	end,
})

-- Power -------------------------------------------------------------------------

Formats.Register("power:value", {
	label = "Power: current / max",
	events = POWER_EVENTS,
	text = function(unit)
		return string.format("%s / %s", Short(UnitPower(unit)), Short(UnitPowerMax(unit)))
	end,
	sample = function(v) return string.format("%s / %s", Short(v.power), Short(v.powerMax)) end,
})

Formats.Register("power:current", {
	label = "Power: current",
	events = POWER_EVENTS,
	text = function(unit) return Short(UnitPower(unit)) end,
	sample = function(v) return Short(v.power) end,
})

Formats.Register("power:percent", {
	label = "Power: percent",
	events = POWER_EVENTS,
	text = function(unit)
		return string.format("%d%%", UnitPowerPercent(unit, nil, false, ns.Colors.PercentCurve()))
	end,
	sample = function(v) return string.format("%d%%", Percent(v.power, v.powerMax)) end,
})

Formats.Register("power:missing", {
	label = "Power: missing",
	events = POWER_EVENTS,
	text = function(unit) return C_StringUtil.TruncateWhenZero(UnitPowerMissing(unit)) end,
	sample = function(v)
		local missing = v.powerMax - v.power
		return missing > 0 and Short(missing) or ""
	end,
})

-- Experience (player only; XP values are not secret, but stay pass-through
-- where we can) -------------------------------------------------------------------

local function XP()
	return UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0
end

Formats.Register("xp:value", {
	label = "XP: current / max",
	events = XP_EVENTS, shared = true,
	text = function()
		local cur, max = XP()
		return string.format("%s / %s", Short(cur), Short(max))
	end,
	sample = function(v) return string.format("%s / %s", Short(v.xp), Short(v.xpMax)) end,
})

Formats.Register("xp:percent", {
	label = "XP: percent",
	events = XP_EVENTS, shared = true,
	text = function()
		local cur, max = XP()
		return string.format("%d%%", Percent(cur, max))
	end,
	sample = function(v) return string.format("%d%%", Percent(v.xp, v.xpMax)) end,
})

Formats.Register("xp:value:percent", {
	label = "XP: current / max (percent)",
	events = XP_EVENTS, shared = true,
	text = function()
		local cur, max = XP()
		return string.format("%s / %s (%d%%)", Short(cur), Short(max), Percent(cur, max))
	end,
	sample = function(v)
		return string.format("%s / %s (%d%%)", Short(v.xp), Short(v.xpMax), Percent(v.xp, v.xpMax))
	end,
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
Formats.HEALTH = { "none", "name", "level", "level:name", "health:value", "health:current", "health:percent",
	"health:current:percent", "health:missing" }
Formats.POWER = { "none", "name", "level", "power:value", "power:current", "power:percent", "power:missing" }
Formats.EXPERIENCE = { "none", "level", "xp:value", "xp:percent", "xp:value:percent", "xp:rested" }
