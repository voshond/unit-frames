local _, wb = ...

-- Fake and live data helpers shared by the Workbench entries. Colours and
-- text formats live in the core (UF.Colors, UF.Formats).
local Data = {}
wb.Data = Data

Data.LIVE_UNITS = { player = true, pet = true, target = true, focus = true }

-- Source choices; entries pick the ones they support.
function Data.Sources(withTarget)
	local values = {
		{ "static", "Static (sliders)" },
		{ "animated", "Animated" },
		{ "player", "Live: player" },
	}
	if withTarget then
		values[#values + 1] = { "pet", "Live: player pet" }
		values[#values + 1] = { "target", "Live: target" }
		values[#values + 1] = { "focus", "Live: focus" }
	end
	return values
end

function Data.IsLive(data)
	return Data.LIVE_UNITS[data.source] == true
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

Data.POWER_TYPES = {
	{ "MANA", "Mana" },
	{ "RAGE", "Rage" },
	{ "ENERGY", "Energy" },
	{ "FOCUS", "Focus" },
	{ "RUNIC_POWER", "Runic power" },
}

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
