local _, ns = ...
local Rows = {}
ns.UnitRows = Rows

-- Structural row specs are copied for each consumer; text defaults are replaced,
-- not merged, so a standalone row can intentionally offer different slots.
local specs = {
	health = {
		overheal = true,
		pendingDamage = true,
		segments = {
			{ key = "heal", label = "Incoming heals", mode = "append", colorInherit = "colors.heal" },
			{ key = "absorb", label = "Absorb shields", mode = "overlay", configurablePlacement = true,
				appendToFill = true, colorInherit = "colors.absorb" },
			{ key = "healAbsorb", label = "Heal absorbs", mode = "inset", colorInherit = "colors.healAbsorb" },
		},
		formats = ns.Formats.HEALTH, valueKind = "health",
		textDefaults = { left = "name", right = "health:value", belowLeft = { format = "level:class", enabled = false } },
	},
	power = {
		colorInherit = "colors.mana",
		segments = { { key = "cost", label = "Spell cost", mode = "inset", colorInherit = "colors.powerCost" } },
		formats = ns.Formats.POWER, valueKind = "power",
		textDefaults = { right = "power:value" },
	},
	experience = {
		colorInherit = "colors.experience",
		segments = { { key = "rested", label = "Rested", mode = "append", colorInherit = "colors.rested" } },
		formats = ns.Formats.EXPERIENCE, valueKind = "xp",
		textDefaults = { center = "xp:value:percent" },
	},
}

function Rows.Spec(key, textDefaults)
	local spec = ns.Util.Copy(assert(specs[key], "Unknown unit row: " .. key))
	if textDefaults then spec.textDefaults = ns.Util.Copy(textDefaults) end
	return spec
end

-- The native calculator adds shields to the scale without Lua touching
-- secret health/absorb values. Hidden shields must not shrink the health fill.
function Rows.HealthMaximumMode(bar)
	local shield = bar.resolved.segments.absorb
	return shield.enabled and shield.placement == "append"
		and Enum.UnitMaximumHealthMode.WithAbsorbs or Enum.UnitMaximumHealthMode.Default
end

-- Sample writers accept deliberately plain values. Live subscriptions remain
-- with oUF; no live health/absorb arithmetic belongs in these functions.
function Rows.SampleHealth(row, values)
	local append = Rows.HealthMaximumMode(row:GetBar()) == Enum.UnitMaximumHealthMode.WithAbsorbs
	row:SetRange(0, values.healthMax + (append and values.absorb or 0))
	row:SetValue(values.health)
	row:SetSegmentValue("heal", math.min(values.heal, math.max(0, values.healthMax - values.health)))
	row:SetSegmentValue("absorb", values.absorb)
	row:SetSegmentValue("healAbsorb", values.healAbsorb)
	local overheal = row:GetBar():GetOverheal()
	if overheal then overheal:ShowSample(values) end
	local pending = row:GetBar():GetPendingDamage()
	if pending then pending:SetHealth(values.health) end
end

function Rows.SamplePower(row, values)
	row:GetBar():SetPowerBackground(values.powerType)
	row:SetRange(0, values.powerMax)
	row:SetValue(values.power)
	row:SetSegmentValue("cost", values.cost)
	row:SetColor(ns.Colors.Power(values.powerType))
end

-- Plain values: samples and the player's (non-secret) experience alike.
function Rows.Experience(row, current, maximum, rested)
	row:SetRange(0, maximum)
	row:SetValue(current)
	row:SetSegmentValue("rested", rested)
end

function Rows.PlayerExperience(row)
	Rows.Experience(row, UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0)
end

-- Health bar colour for a live unit: "class" uses classColor(unit)
-- (default: class for players, reaction/tapped for NPCs), "gradient" the
-- secret-safe health curve, anything else the configured bar colour.
function Rows.LiveHealthColor(row, mode, unit, classColor)
	if mode == "class" then
		row:SetColor((classColor or ns.Colors.Unit)(unit))
	elseif mode == "gradient" then
		row:SetColor(UnitHealthPercent(unit, true, ns.Colors.HealthCurve()):GetRGB())
	else
		row:ClearColor()
	end
end

-- Live writers for previews outside oUF (Workbench, ClickGrid): the owner polls
-- an explicit unit. Every value comes from the native heal prediction
-- calculator, as in oUF's Health element, and goes straight into widgets.
function Rows.LiveHealth(row, unit, calculator, colorMode, classColor)
	calculator:SetMaximumHealthMode(Rows.HealthMaximumMode(row:GetBar()))
	calculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
	UnitGetDetailedHealPrediction(unit, "player", calculator)
	row:SetRange(0, calculator:GetMaximumHealth())
	row:SetValue(calculator:GetCurrentHealth())
	row:SetSegmentValue("heal", (calculator:GetIncomingHeals()))
	row:SetSegmentValue("absorb", (calculator:GetDamageAbsorbs()))
	row:SetSegmentValue("healAbsorb", (calculator:GetHealAbsorbs()))
	local overheal = row:GetBar():GetOverheal()
	if overheal then overheal:Update(unit) end
	local pending = row:GetBar():GetPendingDamage()
	if pending then pending:SetHealth(calculator:GetCurrentHealth()) end
	Rows.LiveHealthColor(row, colorMode, unit, classColor)
	row:ShowLive(unit)
end

function Rows.LivePower(row, unit)
	local _, token = UnitPowerType(unit)
	row:GetBar():SetPowerBackground(token)
	row:SetRange(0, UnitPowerMax(unit))
	row:SetValue(UnitPower(unit))
	row:SetSegmentValue("cost", 0)
	row:SetColor(ns.Colors.Power(token))
	row:ShowLive(unit)
end
