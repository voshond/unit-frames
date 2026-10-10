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
		textDefaults = { left = "name", right = "health:value" },
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
}

function Units:GetDefinition(unit)
	return self.definitions[unit]
end

-- Builds the visual frame for `unit` (no data binding). `frame` is optional.
function Units:CreateFrame(unit, parent, frame)
	local def = self.definitions[unit]
	return ns.Components.UnitFrame:New(parent, ns.Config:GetUnitConfig(unit), {
		frame = frame, rows = def.rows, width = def.width,
	})
end

-- Sample values for previews and test frames.
Units.SAMPLE = {
	name = "Uther", level = 42,
	health = 15600, healthMax = 24000, heal = 2400, absorb = 3600, healAbsorb = 1200,
	power = 8400, powerMax = 12000, cost = 1500, powerType = "MANA",
	xp = 41000, xpMax = 98000, rested = 30000,
	class = "PALADIN",
}
