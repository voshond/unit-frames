local _, ns = ...
local Rows = {}
ns.UnitRows = Rows

-- Structural row specs are copied for each consumer; text defaults are replaced,
-- not merged, so a standalone row can intentionally offer different slots.
local specs = {
	health = {
		segments = {
			{ key = "heal", label = "Incoming heals", mode = "append", colorInherit = "colors.heal" },
			{ key = "absorb", label = "Absorb shields", mode = "overlay", configurablePlacement = true,
				appendToFill = true, colorInherit = "colors.absorb" },
			{ key = "healAbsorb", label = "Heal absorbs", mode = "inset", colorInherit = "colors.healAbsorb" },
		},
		formats = ns.Formats.HEALTH,
		textDefaults = { left = "name", right = "health:value", belowLeft = { format = "level:class", enabled = false } },
	},
	power = {
		colorInherit = "colors.mana",
		segments = { { key = "cost", label = "Spell cost", mode = "inset", colorInherit = "colors.powerCost" } },
		formats = ns.Formats.POWER,
		textDefaults = { right = "power:value" },
	},
	experience = {
		colorInherit = "colors.experience",
		segments = { { key = "rested", label = "Rested", mode = "append", colorInherit = "colors.rested" } },
		formats = ns.Formats.EXPERIENCE,
		textDefaults = { center = "xp:value:percent" },
	},
}

function Rows.Spec(key, textDefaults)
	local spec = ns.Util.Copy(assert(specs[key], "Unknown unit row: " .. key))
	if textDefaults then spec.textDefaults = ns.Util.Copy(textDefaults) end
	return spec
end

-- Sample writers accept deliberately plain values. Live subscriptions remain
-- with oUF; no live health/absorb arithmetic belongs in these functions.
function Rows.SampleHealth(row, values)
	local append = ns.Units:GetHealthMaximumMode(row:GetBar()) == Enum.UnitMaximumHealthMode.WithAbsorbs
	row:SetRange(0, values.healthMax + (append and values.absorb or 0))
	row:SetValue(values.health)
	row:SetSegmentValue("heal", math.min(values.heal, math.max(0, values.healthMax - values.health)))
	row:SetSegmentValue("absorb", values.absorb)
	row:SetSegmentValue("healAbsorb", values.healAbsorb)
end

function Rows.SamplePower(row, values)
	row:SetRange(0, values.powerMax)
	row:SetValue(values.power)
	row:SetSegmentValue("cost", values.cost)
	row:SetColor(ns.Colors.Power(values.powerType))
end

function Rows.Experience(row, current, maximum, rested)
	row:SetRange(0, maximum)
	row:SetValue(current)
	row:SetSegmentValue("rested", rested)
end
