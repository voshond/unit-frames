local _, ns = ...
local Util = ns.Util

--[[
Text sources: the single values a text slot is composed of ("Name", "Health
max", "PvP flag", ...). Sources are the only text code that reads the game API;
presets (Core/Formats.lua) and the composer (Core/TextTemplate.lua) combine
them. See docs/todos/04-design-text-slots.md.

Each source has
  label, group    inspector text
  events          oUF update events, space separated
  shared          true when none of its events carry a unit
  sharedEvents    set of unitless events when mixed with unit events
  player          only meaningful for the player unit (XP, resting)
  optional        normally absent in some states (missing at full, unflagged
                  PvP, ...): an inspector hint for where separators belong
  live(unit, piece)     possibly secret text, or nil; never inspected in Lua.
                        Called only for an existing unit.
  sample(values, piece) the same for plain sample values; nil when the sample
                        has no such value (a standalone bar's sample)

Results are strings (level passes its number through), or nil for no value.
The composer only checks their type.
]]
local Sources = { list = {}, byId = {} }
ns.TextSources = Sources

function Sources.Register(id, source)
	source.id = id
	Sources.byId[id] = source
	Sources.list[#Sources.list + 1] = source
end

function Sources.Get(id)
	return Sources.byId[id]
end

local function Short(value)
	return AbbreviateNumbers(value)
end

local function SampleMissing(cur, max)
	local missing = max - cur
	return missing > 0 and Short(missing) or ""
end

-- Identity --------------------------------------------------------------------

local PVP_EVENTS = "UNIT_FACTION PLAYER_PVP_FLAG_CHANGED PLAYER_REGEN_ENABLED"
local PVP_SHARED_EVENTS = { PLAYER_PVP_FLAG_CHANGED = true, PLAYER_REGEN_ENABLED = true }

-- Forever's PvP atlases. Only samples select them in Lua; live flags use
-- Blizzard's secret-safe helper, including mercenary and FFA handling.
Sources.PVP_ATLASES = {
	Alliance = "UI-HUD-UnitFrame-SmallCircle-Alliance",
	Horde = "UI-HUD-UnitFrame-SmallCircle-Horde",
	FFA = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
}
local PVP_ATLASES = Sources.PVP_ATLASES

-- WrapString returns empty text for an empty atlas, even when secret.
-- Zero dimensions let the inline flag follow the text's font size.
local function PvPMarkup(atlas)
	return C_StringUtil.WrapString(atlas, "|A:", ":0:0:0:0|a")
end

Sources.Register("name", {
	label = "Character name", group = "Identity",
	events = "UNIT_NAME_UPDATE",
	live = function(unit) return (UnitName(unit)) end,
	sample = function(v) return v.name end,
})

Sources.Register("lastname", {
	label = "Last name", group = "Identity", optional = true,
	events = "UNIT_NAME_UPDATE",
	-- Forever's Camelot NameUtil treats UnitName's second return as the surname.
	-- Pass it through unchanged: either name part may be secret.
	live = function(unit)
		local _, lastname = UnitName(unit)
		return lastname
	end,
	sample = function(v) return v.lastname end,
})

Sources.Register("level", {
	label = "Level", group = "Identity", difficulty = true,
	events = "UNIT_LEVEL PLAYER_LEVEL_UP",
	live = function(unit) return UnitLevel(unit) end,
	sample = function(v) if v.level ~= nil then return tostring(v.level) end end,
})

-- Level with markers: Blizzard's skull for too-high levels, "+" elite, "R" rare,
-- "R+" rare elite. Level and classification are not secret.
local CLASSIFICATION = { elite = "+", rare = "R", rareelite = "R+" }
local SKULL_LEVEL = "|A:UI-HUD-UnitFrame-Target-HighLevelTarget_Icon:0:0:0:0|a"

local function SmartLevel(level, classification)
	local text = level and level > 0 and tostring(level) or SKULL_LEVEL
	return text .. (CLASSIFICATION[classification] or "")
end

Sources.Register("smartlevel", {
	label = "Level with elite/rare marker", group = "Identity", difficulty = true,
	events = "UNIT_LEVEL PLAYER_LEVEL_UP UNIT_CLASSIFICATION_CHANGED",
	live = function(unit) return SmartLevel(UnitLevel(unit), UnitClassification(unit)) end,
	sample = function(v) if v.level ~= nil then return SmartLevel(v.level, v.classification) end end,
})

--[[
Difficulty colour of sources marked `difficulty` (the levels), as Blizzard's
target frame colours its level: only for units the player can attack, other
units keep the text's own colour, as do dead and offline units (their frame
look tints the text). Sample NPCs that aren't friendly count as attackable. Level and difficulty are not secret; the tint wraps only that
piece's text, natively.
]]
Sources.DIFFICULTY = {
	events = "UNIT_FACTION",
	live = function(unit)
		if Sources.UnitStatus(unit) then return nil end
		if UnitCanAttack("player", unit) then
			return GetDifficultyColor(C_PlayerInfo.GetContentDifficultyCreatureForPlayer(unit))
		end
	end,
	sample = function(v)
		if v.status == nil and v.isPlayer == false and v.reaction ~= "friendly" and v.level ~= nil then
			return GetCreatureDifficultyColor(v.level)
		end
	end,
}

local function ColorByte(value)
	return math.floor(value * 255 + 0.5)
end

function Sources.Tint(text, color)
	if type(text) == "nil" or not color then return text end
	if type(text) ~= "string" then text = string.format("%s", text) end
	local markup = string.format("|cff%02x%02x%02x", ColorByte(color.r), ColorByte(color.g), ColorByte(color.b))
	return C_StringUtil.WrapString(text, markup, "|r")
end

Sources.Register("class", {
	label = "Class", group = "Identity",
	live = function(unit) return (UnitClass(unit)) end,
	sample = function(v) return v.className end,
})

-- Players show their class, NPCs their creature type (which may be secret).
Sources.Register("info", {
	label = "Class or creature type", group = "Identity",
	live = function(unit)
		if UnitIsPlayer(unit) then
			return (UnitClass(unit))
		end
		return UnitCreatureType(unit)
	end,
	sample = function(v)
		if v.isPlayer == false then return v.creatureType end
		return v.className
	end,
})

Sources.Register("creatureType", {
	label = "Creature type", group = "Identity",
	live = function(unit) return UnitCreatureType(unit) end,
	sample = function(v) return v.creatureType end,
})

--[[
Offline or dead (also as a ghost), with Blizzard's own words, as compact
raid frames show it. These states aren't secret; an opaque one counts as
neither, like the group bars' death icon. Sample values: status = "offline"
or "dead".
]]
local function Plain(value)
	if Util.IsSecret(value) then return nil end
	return value
end

Sources.STATUS_TEXT = {
	offline = PLAYER_OFFLINE or "Offline",
	dead = DEAD or "Dead",
}

-- "offline", "dead" (also a ghost) or nil.
function Sources.UnitStatus(unit)
	if Plain(UnitIsConnected(unit)) == false then return "offline" end
	if Plain(UnitIsDeadOrGhost(unit)) then return "dead" end
end

Sources.Register("status", {
	label = "Offline / dead", group = "Identity", optional = true,
	events = "UNIT_HEALTH UNIT_CONNECTION PLAYER_DEAD PLAYER_ALIVE PLAYER_UNGHOST",
	sharedEvents = { PLAYER_DEAD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true },
	live = function(unit) return Sources.STATUS_TEXT[Sources.UnitStatus(unit)] end,
	sample = function(v) return Sources.STATUS_TEXT[v.status] end,
})

Sources.Register("pvp", {
	label = "PvP flag", group = "Identity", optional = true,
	events = PVP_EVENTS, sharedEvents = PVP_SHARED_EVENTS,
	live = function(unit) return PvPMarkup(UnitFrameUtil.GetUnitPvPIndicatorDisplayInfo(unit, true).pvpIconAtlas) end,
	sample = function(v) return PvPMarkup(PVP_ATLASES[v.pvp] or "") end,
})

Sources.Register("resting", {
	label = "Resting (zZz)", group = "Identity", optional = true, player = true,
	events = "PLAYER_UPDATE_RESTING PLAYER_ENTERING_WORLD", shared = true,
	live = function(unit) if unit == "player" and IsResting() then return "zZz" end end,
	sample = function(v) if v.resting then return "zZz" end end,
})

-- Cast -------------------------------------------------------------------------

-- Cast names can be opaque. Check only their type; pass the value to the
-- native text renderer unchanged. Channels use the same text choices.
Sources.CAST_EVENTS = "UNIT_SPELLCAST_START UNIT_SPELLCAST_DELAYED UNIT_SPELLCAST_STOP UNIT_SPELLCAST_FAILED UNIT_SPELLCAST_INTERRUPTED UNIT_SPELLCAST_CHANNEL_START UNIT_SPELLCAST_CHANNEL_UPDATE UNIT_SPELLCAST_CHANNEL_STOP"

function Sources.SpellName(unit)
	local name = UnitCastingInfo(unit)
	if type(name) ~= "nil" then return name end
	name = UnitChannelInfo(unit)
	if type(name) ~= "nil" then return name end
end

-- Samples cast unless the preview turns it off (`showCast = false`).
function Sources.SampleSpellName(v)
	if v.showCast ~= false then return v.spell end
end

Sources.Register("cast.spell", {
	label = "Spell name while casting", group = "Cast", optional = true,
	events = Sources.CAST_EVENTS,
	live = function(unit) return Sources.SpellName(unit) end,
	sample = function(v) return Sources.SampleSpellName(v) end,
})

-- Values: current, max, percent and missing for health, power and experience --

--[[
Piece options a source can use (`options = { number = true }`). Pieces store
them as their own settings; sources read them from the piece.
]]
Sources.OPTIONS = {
	{ key = "number", label = "Number style", default = "short", values = {
		{ "short", "Short (12.3K)" }, { "full", "Full (12,345)" }, { "plain", "Plain (12345)" },
	} },
	{ key = "decimals", label = "Decimals", default = 0, values = { { 0, "None (65%)" }, { 1, "One (65.4%)" } } },
}

local function Option(piece, key)
	local value = piece and piece[key]
	if value ~= nil then return value end
	for _, opt in ipairs(Sources.OPTIONS) do
		if opt.key == key then return opt.default end
	end
end

-- Native, secret-safe number styles.
function Sources.Number(value, style)
	if style == "full" then return BreakUpLargeNumbers(value) end
	if style == "plain" then return string.format("%d", value) end
	return Short(value)
end

-- 0..100 as "65%" or "65.4%". Plain values round; secret ones go to the
-- native formatter as they are.
local function PercentText(value, decimals)
	if decimals == 1 then return string.format("%.1f%%", value) end
	if not Util.IsSecret(value) then value = math.floor(value + 0.5) end
	return string.format("%d%%", value)
end

local function PlainPercent(cur, max)
	if Util.IsSecret(cur) or Util.IsSecret(max) or max == 0 then return 0 end
	return cur / max * 100
end

-- Missing share of plain values, rounded down like TruncateWhenZero, and
-- nothing when nothing is missing.
local function PlainMissingPercent(cur, max)
	if Util.IsSecret(cur) or Util.IsSecret(max) or max == 0 then return nil end
	local missing = math.floor((max - cur) / max * 100)
	if missing > 0 then return string.format("%d%%", missing) end
end

-- Maps 0..1 to the missing 100..0 for percent texts, without Lua maths.
local missingCurve
local function MissingCurve()
	if not missingCurve then
		missingCurve = C_CurveUtil.CreateCurve()
		missingCurve:AddPoint(0, 100)
		missingCurve:AddPoint(1, 0)
	end
	return missingCurve
end

-- Integer percent, empty at zero, decided natively for secret values.
local function NativeMissingPercent(percent)
	return C_StringUtil.WrapString(C_StringUtil.TruncateWhenZero(percent), "", "%")
end

--[[
Registers <kind>.current, .max, .percent, .missing and .missingPercent. `api`
provides
  live(unit)                current, max (may be secret)
  livePercent(unit)         0..100 (may be secret)
  liveMissing(unit)         missing amount as text, "" when nothing is missing
  liveMissingPercent(unit)  missing share as text, "" when nothing is missing
  sample                    keys of current and max in the sample values
  player                    player-only values: other units show nothing
]]
local VALUE_OPTIONS = { current = { number = true }, max = { number = true }, percent = { decimals = true } }

local function RegisterValues(kind, group, events, shared, api)
	local curKey, maxKey = api.sample[1], api.sample[2]
	local player = api.player
	local function Live(read)
		if not player then return read end
		return function(unit, piece)
			if unit == "player" then return read(unit, piece) end
		end
	end
	local function Register(key, label, optional, live, sample)
		Sources.Register(kind .. "." .. key, {
			label = label, group = group, optional = optional, player = player,
			events = events, shared = shared, options = VALUE_OPTIONS[key],
			live = Live(live),
			sample = function(v, piece)
				if v[curKey] ~= nil and v[maxKey] ~= nil then return sample(v, piece) end
			end,
		})
	end
	Register("current", "Current", false,
		function(unit, piece) return Sources.Number((api.live(unit)), Option(piece, "number")) end,
		function(v, piece) return Sources.Number(v[curKey], Option(piece, "number")) end)
	Register("max", "Max", false,
		function(unit, piece) return Sources.Number((select(2, api.live(unit))), Option(piece, "number")) end,
		function(v, piece) return Sources.Number(v[maxKey], Option(piece, "number")) end)
	Register("percent", "Percent", false,
		function(unit, piece) return PercentText(api.livePercent(unit), Option(piece, "decimals")) end,
		function(v, piece) return PercentText(PlainPercent(v[curKey], v[maxKey]), Option(piece, "decimals")) end)
	Register("missing", "Missing", true,
		function(unit) return api.liveMissing(unit) end,
		function(v) return SampleMissing(v[curKey], v[maxKey]) end)
	Register("missingPercent", "Missing percent", true,
		function(unit) return api.liveMissingPercent(unit) end,
		function(v) return PlainMissingPercent(v[curKey], v[maxKey]) end)
end

Sources.VALUE_KEYS = { "current", "max", "percent", "missing", "missingPercent" }

RegisterValues("health", "Health", "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION", false, {
	live = function(unit) return UnitHealth(unit), UnitHealthMax(unit) end,
	livePercent = function(unit) return UnitHealthPercent(unit, true, ns.Colors.PercentCurve()) end,
	liveMissing = function(unit) return C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit)) end,
	liveMissingPercent = function(unit) return NativeMissingPercent(UnitHealthPercent(unit, true, MissingCurve())) end,
	sample = { "health", "healthMax" },
})

RegisterValues("power", "Power", "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER", false, {
	live = function(unit) return UnitPower(unit), UnitPowerMax(unit) end,
	livePercent = function(unit) return UnitPowerPercent(unit, nil, false, ns.Colors.PercentCurve()) end,
	liveMissing = function(unit) return C_StringUtil.TruncateWhenZero(UnitPowerMissing(unit)) end,
	liveMissingPercent = function(unit) return NativeMissingPercent(UnitPowerPercent(unit, nil, false, MissingCurve())) end,
	sample = { "power", "powerMax" },
})

-- Experience is player only and not secret, but stays pass-through where it can.
local XP_EVENTS = "PLAYER_XP_UPDATE UPDATE_EXHAUSTION PLAYER_LEVEL_UP"

local function XP()
	return UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0
end

RegisterValues("xp", "Experience", XP_EVENTS, true, {
	player = true,
	live = function() return XP() end,
	livePercent = function()
		local cur, max = XP()
		return PlainPercent(cur, max)
	end,
	liveMissing = function()
		local cur, max = XP()
		if Util.IsSecret(cur) or Util.IsSecret(max) then
			return ""
		end
		return SampleMissing(cur, max)
	end,
	liveMissingPercent = function()
		local cur, max = XP()
		return PlainMissingPercent(cur, max)
	end,
	sample = { "xp", "xpMax" },
})

local function Rested(rested)
	if Util.IsSecret(rested) then return Short(rested) end
	if rested > 0 then return "Rested " .. Short(rested) end
end

Sources.Register("xp.rested", {
	label = "Rested", group = "Experience", optional = true, player = true,
	events = XP_EVENTS, shared = true,
	live = function(unit)
		if unit == "player" then return Rested((select(3, XP()))) end
	end,
	sample = function(v) if v.rested ~= nil then return Rested(v.rested) end end,
})

-- This bar's value -------------------------------------------------------------

--[[
bar.<key> means <kind>.<key> of the bar the slot is on (its context's `bar`:
"health", "power" or "xp"). Templates resolve them to the concrete source
before anything else, so they compile, share and update exactly like it;
slots outside a bar don't offer them.
]]
local BAR_LABELS = { current = "Current", max = "Max", percent = "Percent", missing = "Missing",
	missingPercent = "Missing percent" }

for _, key in ipairs(Sources.VALUE_KEYS) do
	Sources.Register("bar." .. key, {
		label = BAR_LABELS[key], group = "This bar", relative = key,
		optional = key == "missing" or key == "missingPercent", options = VALUE_OPTIONS[key],
	})
end

-- The concrete source behind `source` on a host, or nil when it has none.
function Sources.Resolve(source, context)
	if not source.relative then return source end
	local kind = context and context.bar
	return kind and Sources.Get(kind .. "." .. source.relative) or nil
end
