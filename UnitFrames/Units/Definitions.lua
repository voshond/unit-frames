local _, ns = ...
local Formats = ns.Formats

-- What each unit frame is made of (rows, segments, default texts). Used for
-- the live oUF frames and for Workbench previews alike.
local Units = { definitions = {}, frames = {} }
ns.Units = Units

Units.HEALTH_COLOR_MODES = {
	{ "class", "Class colour" },
	{ "gradient", "Health gradient" },
	{ "theme", "Theme colour" },
}

local HEALTH_ROW = {
	key = "health", label = "Health",
	spec = {
		segments = {
			{ key = "heal", label = "Incoming heals", mode = "append", colorInherit = "colors.heal" },
			{ key = "absorb", label = "Absorb shields", mode = "append", colorInherit = "colors.absorb" },
			{ key = "healAbsorb", label = "Heal absorbs", mode = "inset", colorInherit = "colors.healAbsorb" },
		},
		formats = Formats.HEALTH,
		textDefaults = { left = "name", right = "health:value", belowLeft = { format = "level:class", enabled = false } },
	},
	defaults = { height = 26 },
	options = {
		{ key = "colorMode", type = "select", label = "Bar colour", values = Units.HEALTH_COLOR_MODES, default = "class" },
	},
}

local POWER_ROW = {
	key = "power", label = "Power",
	spec = {
		colorInherit = "colors.mana",
		segments = { { key = "cost", label = "Spell cost", mode = "inset", colorInherit = "colors.powerCost" } },
		formats = Formats.POWER,
		textDefaults = { right = "power:value" },
	},
	defaults = { height = 12, right = { size = 9 } },
}

local EXPERIENCE_ROW = {
	key = "experience", label = "Experience",
	spec = {
		colorInherit = "colors.experience",
		segments = { { key = "rested", label = "Rested", mode = "append", colorInherit = "colors.rested" } },
		formats = Formats.EXPERIENCE,
		textDefaults = { center = "xp:value:percent" },
	},
	defaults = { height = 10, center = { size = 8 } },
}

Units.definitions.player = {
	label = "Player",
	width = 230,
	defaultPosition = { point = "CENTER", x = -280, y = -160 },
	rows = { HEALTH_ROW, POWER_ROW, EXPERIENCE_ROW },
	portrait = { defaults = { enabled = true } },
	-- Inside the unit frame the castbar uses the frame's border, not its own.
	castbar = { defaults = { placement = "bottom", height = 18, border = { enabled = false },
		name = { size = 10 }, time = { size = 10 } } },
	auras = { defaults = {} },
}

function Units:GetDefinition(unit)
	return self.definitions[unit]
end

-- Builds the visual frame for `unit` (no data binding). `frame` is optional.
function Units:CreateFrame(unit, parent, frame)
	local def = self.definitions[unit]
	return ns.Components.UnitFrame:New(parent, ns.Config:GetUnitConfig(unit), {
		frame = frame, rows = def.rows, width = def.width, portrait = def.portrait, castbar = def.castbar,
		auras = def.auras,
	})
end

-- Sample values for previews and test frames.
Units.SAMPLE = {
	name = "Uther", level = 42, className = "Paladin",
	health = 15600, healthMax = 24000, heal = 2400, absorb = 3600, healAbsorb = 1200,
	power = 8400, powerMax = 12000, cost = 1500, powerType = "MANA",
	xp = 41000, xpMax = 98000, rested = 30000,
	class = "PALADIN",
	spell = "Flash of Light", spellIcon = [[Interface\Icons\Spell_Holy_FlashHeal]], castProgress = 0.6, castTime = 1.5,
	buffs = {
		{ icon = [[Interface\Icons\Spell_Holy_WordFortitude]], duration = 3600, remaining = 1800, sourceUnit = "player", isRaid = true },
		{ icon = [[Interface\Icons\Spell_Holy_MagicalSentry]], duration = 3600, remaining = 180, sourceUnit = "party1", isRaid = true },
		{ icon = [[Interface\Icons\Spell_Holy_Renew]], duration = 15, remaining = 8, sourceUnit = "player" },
		{ icon = [[Interface\Icons\Spell_Nature_Rejuvenation]], duration = 12, remaining = 5, sourceUnit = "party1" },
		{ icon = [[Interface\Icons\Spell_Nature_ResistNature]], duration = 20, remaining = 14, sourceUnit = "party1" },
		{ icon = [[Interface\Icons\Spell_Holy_PowerWordShield]], duration = 30, remaining = 21, sourceUnit = "player" },
		{ icon = [[Interface\Icons\Spell_Nature_LifeBloom]], duration = 15, remaining = 9, applications = 3, sourceUnit = "player" },
		{ icon = [[Interface\Icons\Spell_Nature_Regeneration]], duration = 0, sourceUnit = "player", isRaid = true },
	},
	debuffs = {
		{ icon = [[Interface\Icons\Spell_Frost_FrostBolt02]], duration = 15, remaining = 7, dispelName = "Magic", sourceUnit = "player", isRaid = true },
		{ icon = [[Interface\Icons\Spell_Shadow_CurseOfTongues]], duration = 24, remaining = 18, dispelName = "Curse", sourceUnit = "party1", isRaid = true },
		{ icon = [[Interface\Icons\Spell_Shadow_AbominationExplosion]], duration = 20, remaining = 13, dispelName = "Disease", applications = 2, sourceUnit = "party1", isRaid = true },
		{ icon = [[Interface\Icons\Spell_Nature_CorrosiveBreath]], duration = 12, remaining = 6, dispelName = "Poison", applications = 4, sourceUnit = "player", isRaid = true },
		{ icon = [[Interface\Icons\Ability_Gouge]], duration = 15, remaining = 11, sourceUnit = "party1" },
	},
}
