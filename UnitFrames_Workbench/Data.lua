local _, wb = ...
local UF = UnitFrames
local Util = UF.Util

-- Fake and live data helpers shared by the Workbench entries.
local Data = {}
wb.Data = Data

Data.LIVE_UNITS = { player = true, target = true, focus = true }

-- Source choices; entries pick the ones they support.
function Data.Sources(withTarget)
	local values = {
		{ "static", "Static (sliders)" },
		{ "animated", "Animated" },
		{ "player", "Live: player" },
	}
	if withTarget then
		values[#values + 1] = { "target", "Live: target" }
		values[#values + 1] = { "focus", "Live: focus" }
	end
	return values
end

function Data.IsLive(data)
	return Data.LIVE_UNITS[data.source] == true
end

function Data.HiddenWhenLive(data)
	return Data.IsLive(data)
end

function Data.Classes()
	local values = {}
	for token in pairs(RAID_CLASS_COLORS) do
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or token
		values[#values + 1] = { token, name }
	end
	table.sort(values, function(a, b)
		return a[2] < b[2]
	end)
	return values
end

function Data.ClassColor(token)
	local color = RAID_CLASS_COLORS[token]
	if color then
		return color.r, color.g, color.b, 1
	end
	return 0.5, 0.5, 0.5, 1
end

function Data.ThemeColor(key)
	return Util.UnpackColor(UF.Config:GetTheme().colors[key])
end

-- Theme colour keys per power type token (UnitPowerType's second return).
Data.POWER_COLORS = {
	MANA = "mana",
	RAGE = "rage",
	ENERGY = "energy",
	FOCUS = "focus",
	RUNIC_POWER = "runicPower",
}

Data.POWER_TYPES = {
	{ "MANA", "Mana" },
	{ "RAGE", "Rage" },
	{ "ENERGY", "Energy" },
	{ "FOCUS", "Focus" },
	{ "RUNIC_POWER", "Runic power" },
}

function Data.PowerColor(token)
	local key = Data.POWER_COLORS[token]
	if key then
		return Data.ThemeColor(key)
	end
	local color = PowerBarColor and PowerBarColor[token]
	if color then
		return color.r, color.g, color.b, 1
	end
	return Data.ThemeColor("mana")
end

-- Health gradient as a colour curve (red -> yellow -> green). It works on
-- secret health through UnitHealthPercent(unit, true, curve). Rebuilt when
-- the theme colours change.
local healthCurve
UF.Events.RegisterCallback(Data, "ThemeChanged", function()
	healthCurve = nil
end)

function Data.HealthCurve()
	if not healthCurve then
		healthCurve = C_CurveUtil.CreateColorCurve()
		healthCurve:AddPoint(0, CreateColor(Data.ThemeColor("healthLow")))
		healthCurve:AddPoint(0.5, CreateColor(Data.ThemeColor("healthMid")))
		healthCurve:AddPoint(1, CreateColor(Data.ThemeColor("health")))
	end
	return healthCurve
end

-- Maps 0..1 to 0..100, for "%" texts from UnitHealthPercent/UnitPowerPercent.
local percentCurve
function Data.PercentCurve()
	if not percentCurve then
		percentCurve = C_CurveUtil.CreateCurve()
		percentCurve:AddPoint(0, 0)
		percentCurve:AddPoint(1, 100)
	end
	return percentCurve
end

-- AbbreviateNumbers accepts secret numbers (it returns a secret string).
function Data.Short(value)
	return AbbreviateNumbers(value)
end

-- Smooth 0..1 wave for animated sources.
function Data.Wave(time, speed, offset)
	return 0.5 + 0.5 * math.sin(time * (speed or 1) + (offset or 0))
end

Data.SPELLS = {
	{ name = "Fireball", icon = [[Interface\Icons\Spell_Fire_FlameBolt]], time = 3 },
	{ name = "Frostbolt", icon = [[Interface\Icons\Spell_Frost_FrostBolt02]], time = 2.5 },
	{ name = "Flash Heal", icon = [[Interface\Icons\Spell_Holy_FlashHeal]], time = 1.5 },
	{ name = "Arcane Missiles", icon = [[Interface\Icons\Spell_Nature_StarFall]], time = 5, channel = true },
	{ name = "Drain Life", icon = [[Interface\Icons\Spell_Shadow_LifeDrain02]], time = 5, channel = true },
}

function Data.SpellValues()
	local values = {}
	for i, spell in ipairs(Data.SPELLS) do
		values[#values + 1] = { i, spell.name .. (spell.channel and " (channel)" or "") }
	end
	return values
end
