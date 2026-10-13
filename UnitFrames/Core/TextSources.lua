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

local function Percent(cur, max)
	if Util.IsSecret(cur) or Util.IsSecret(max) or max == 0 then
		return 0
	end
	return math.floor(cur / max * 100 + 0.5)
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
	label = "Name", group = "Identity",
	events = "UNIT_NAME_UPDATE",
	live = function(unit) return (UnitName(unit)) end,
	sample = function(v) return v.name end,
})

Sources.Register("level", {
	label = "Level", group = "Identity",
	events = "UNIT_LEVEL PLAYER_LEVEL_UP",
	live = function(unit) return UnitLevel(unit) end,
	sample = function(v) if v.level ~= nil then return tostring(v.level) end end,
})

-- Level with markers: "??" for skull level, "+" elite, "R" rare, "R+" rare
-- elite, "B" boss. Level and classification are not secret.
local CLASSIFICATION = { elite = "+", rare = "R", rareelite = "R+", worldboss = "B" }

local function SmartLevel(level, classification)
	local text = level and level > 0 and tostring(level) or "??"
	return text .. (CLASSIFICATION[classification] or "")
end

Sources.Register("smartlevel", {
	label = "Level with elite/rare marker", group = "Identity",
	events = "UNIT_LEVEL PLAYER_LEVEL_UP UNIT_CLASSIFICATION_CHANGED",
	live = function(unit) return SmartLevel(UnitLevel(unit), UnitClassification(unit)) end,
	sample = function(v) if v.level ~= nil then return SmartLevel(v.level, v.classification) end end,
})

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
Registers <kind>.current, .max, .percent and .missing. `api` provides
  live(unit)         current, max (may be secret)
  livePercent(unit)  0..100 (may be secret)
  liveMissing(unit)  missing amount as text, "" when nothing is missing
  sample             keys of current and max in the sample values
  player             player-only values: other units show nothing
]]
local function RegisterValues(kind, group, events, shared, api)
	local curKey, maxKey = api.sample[1], api.sample[2]
	local player = api.player
	local function Live(read)
		if not player then return read end
		return function(unit)
			if unit == "player" then return read(unit) end
		end
	end
	local function Register(key, label, optional, live, sample)
		Sources.Register(kind .. "." .. key, {
			label = label, group = group, optional = optional, player = player,
			events = events, shared = shared,
			live = Live(live),
			sample = function(v)
				if v[curKey] ~= nil and v[maxKey] ~= nil then return sample(v) end
			end,
		})
	end
	Register("current", "Current", false,
		function(unit) return Short((api.live(unit))) end,
		function(v) return Short(v[curKey]) end)
	Register("max", "Max", false,
		function(unit) return Short((select(2, api.live(unit)))) end,
		function(v) return Short(v[maxKey]) end)
	Register("percent", "Percent", false,
		function(unit) return string.format("%d%%", api.livePercent(unit)) end,
		function(v) return string.format("%d%%", Percent(v[curKey], v[maxKey])) end)
	Register("missing", "Missing", true,
		function(unit) return api.liveMissing(unit) end,
		function(v) return SampleMissing(v[curKey], v[maxKey]) end)
end

RegisterValues("health", "Health", "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION", false, {
	live = function(unit) return UnitHealth(unit), UnitHealthMax(unit) end,
	livePercent = function(unit) return UnitHealthPercent(unit, true, ns.Colors.PercentCurve()) end,
	liveMissing = function(unit) return C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit)) end,
	sample = { "health", "healthMax" },
})

RegisterValues("power", "Power", "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER", false, {
	live = function(unit) return UnitPower(unit), UnitPowerMax(unit) end,
	livePercent = function(unit) return UnitPowerPercent(unit, nil, false, ns.Colors.PercentCurve()) end,
	liveMissing = function(unit) return C_StringUtil.TruncateWhenZero(UnitPowerMissing(unit)) end,
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
