local _, ns = ...
local Formats = ns.Formats

-- What each unit frame is made of (rows, segments, default texts). Used for
-- the live oUF frames and for Workbench previews alike.
local Units = { definitions = {}, frames = {}, order = { "player", "pet", "target", "targettarget", "focus", "focustarget" } }
ns.Units = Units

Units.HEALTH_COLOR_MODES = {
	{ "class", "Class / reaction colour" },
	{ "gradient", "Health gradient" },
	{ "theme", "Theme colour" },
}

-- The native calculator adds shields to the scale without Lua touching
-- secret health/absorb values. Hidden shields must not shrink the health fill.
function Units:GetHealthMaximumMode(bar)
	local shield = bar.resolved.segments.absorb
	return shield.enabled and shield.placement == "append"
		and Enum.UnitMaximumHealthMode.WithAbsorbs or Enum.UnitMaximumHealthMode.Default
end

local HEALTH_ROW = {
	key = "health", label = "Health",
	spec = {
		segments = {
			{ key = "heal", label = "Incoming heals", mode = "append", colorInherit = "colors.heal" },
			{ key = "absorb", label = "Absorb shields", mode = "overlay", configurablePlacement = true,
				appendToFill = true, colorInherit = "colors.absorb" },
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
	resting = true,
	width = 230,
	defaultPosition = { point = "CENTER", x = -280, y = -160 },
	rows = { HEALTH_ROW, POWER_ROW, EXPERIENCE_ROW },
	portrait = { defaults = { enabled = true } },
	-- Inside the unit frame the castbar uses the frame's border, not its own.
	castbar = { defaults = { placement = "bottom", height = 18, border = { enabled = false },
		name = { size = 10 }, time = { size = 10 } } },
	auras = { cancelBuffs = true, defaults = {} },
}

-- Each definition owns its defaults; changing a compact row must not change
-- the player or the other units that share the same components.
local function HealthRow(height, compact)
	local row = ns.Util.Copy(HEALTH_ROW)
	row.defaults.height = height
	row.spec.textDefaults.belowLeft.format = "level:info"
	if compact then
		row.defaults.left = { size = 10 }
		row.defaults.right = { size = 9, format = "health:percent" }
	end
	return row
end

local function PowerRow(height, compact)
	local row = ns.Util.Copy(POWER_ROW)
	row.defaults.height = height
	if compact then row.defaults.right = { size = 8, format = "power:percent" } end
	return row
end

Units.definitions.pet = {
	label = "Player pet", width = 170,
	-- Below/right of the player, clear of the existing focus position.
	defaultPosition = { point = "CENTER", x = -90, y = -235 },
	rows = { HealthRow(22, true), PowerRow(10, true) },
	portrait = { defaults = { enabled = false } },
	castbar = { defaults = { placement = "off", height = 14, border = { enabled = false },
		name = { size = 9 }, time = { size = 9 } } },
	auras = { defaults = { durationPosition = "CENTER", durationSize = 9, countSize = 8,
		buffs = { max = 6, size = 18 }, debuffs = { max = 6, size = 18 } } },
	sample = { name = "Wolf", level = 42, isPlayer = false, creatureType = "Beast", classification = "normal",
		reaction = "friendly", healthMax = 6000, health = 3900, heal = 600, absorb = 900, healAbsorb = 0,
		powerType = "FOCUS", powerMax = 100, power = 70, cost = 20,
		spell = "Bite", spellIcon = [[Interface\Icons\Ability_Druid_FerociousBite]], castTime = 1.5 },
}

Units.definitions.target = {
	label = "Target", width = 230,
	defaultPosition = { point = "CENTER", x = 280, y = -160 },
	rows = { HealthRow(26), PowerRow(12) },
	portrait = { defaults = { enabled = true, position = "RIGHT" } },
	castbar = ns.Util.Copy(Units.definitions.player.castbar),
	auras = { defaults = {} },
	sample = { name = "Scarlet Myrmidon", level = 42, isPlayer = false, creatureType = "Humanoid",
		classification = "elite", reaction = "hostile", powerType = "RAGE", powerMax = 100, power = 70, cost = 15,
		spell = "Mortal Strike", spellIcon = [[Interface\Icons\Ability_Warrior_SavageBlow]], castTime = 1.5 },
}

Units.definitions.targettarget = {
	label = "Target of target", width = 140,
	defaultPosition = { point = "CENTER", x = 510, y = -160 },
	rows = { HealthRow(20, true), PowerRow(8, true) },
	portrait = { defaults = { enabled = false } },
	castbar = { defaults = { placement = "off", height = 14, border = { enabled = false },
		name = { size = 9 }, time = { size = 9 } } },
	auras = { defaults = { enabled = false, durationPosition = "CENTER", durationSize = 9, countSize = 8,
		buffs = { max = 8, size = 16 }, debuffs = { max = 8, size = 18 } } },
	sample = { name = "Arthas", level = 44, className = "Warrior", class = "WARRIOR", isPlayer = true,
		powerType = "RAGE", powerMax = 100, power = 70, cost = 15 },
}

Units.definitions.focus = {
	label = "Focus", width = 200,
	defaultPosition = { point = "CENTER", x = -280, y = -290 },
	rows = { HealthRow(24), PowerRow(10) },
	portrait = { defaults = { enabled = false } },
	castbar = ns.Util.Copy(Units.definitions.player.castbar),
	auras = { defaults = {} },
	sample = { name = "Jaina", level = 44, className = "Mage", class = "MAGE", isPlayer = true,
		spell = "Frostbolt", spellIcon = [[Interface\Icons\Spell_Frost_FrostBolt02]], castTime = 2.5 },
}

-- Both target chains use the same compact style, with independent defaults.
Units.definitions.focustarget = ns.Util.Copy(Units.definitions.targettarget)
Units.definitions.focustarget.label = "Focus target"
Units.definitions.focustarget.defaultPosition = { point = "CENTER", x = -60, y = -290 }
Units.definitions.focustarget.sample = {
	name = "Thrall", level = 44, className = "Shaman", class = "SHAMAN", isPlayer = true,
}

function Units:GetDefinition(unit)
	return self.definitions[unit]
end

-- Builds the visual frame for `unit` (no data binding). `frame` is optional.
function Units:CreateFrame(unit, parent, frame)
	local def = self.definitions[unit]
	return self:CreateFromDefinition(def, parent, ns.Config:GetUnitConfig(unit), frame)
end

-- Companion styles have many instances and their own configuration keys.
-- A definition describes the visuals; the live unit token belongs to oUF.
function Units:CreateFromDefinition(def, parent, config, frame)
	return ns.Components.UnitFrame:New(parent, config or {}, {
		frame = frame, rows = def.rows, width = def.width, portrait = def.portrait, castbar = def.castbar,
		auras = def.auras, raidTarget = def.raidTarget or { defaults = {} }, resting = def.resting,
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

function Units:GetSample(unit)
	return ns.Util.Merge(ns.Util.Copy(self.SAMPLE), ns.Util.Copy(self.definitions[unit].sample or {}))
end
