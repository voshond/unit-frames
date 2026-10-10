local _, wb = ...
local UF = UnitFrames
local Workbench, Data = wb.Workbench, wb.Data
local C = UF.Components

-- A bar with a text on each end, the shape most unit frame bars have.
local function BarWithTexts(stage, spec)
	local bar = C.Bar:New(stage, {}, spec)
	local parent = bar:GetTextParent()
	local left = C.Text:New(parent, {})
	left:SetPoint("LEFT", parent, "LEFT", 4, 0)
	local right = C.Text:New(parent, {})
	right:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
	return Workbench.Composite({
		{ key = "bar", label = "Bar", component = bar },
		{ key = "left", label = "Left text", component = left },
		{ key = "right", label = "Right text", component = right },
	})
end

local TEXT_MODES = {
	{ "value", "Current / max" },
	{ "current", "Current" },
	{ "percent", "Percent" },
	{ "missing", "Missing" },
	{ "none", "None" },
}

-- Text for plain (non-secret) numbers.
local function StaticText(mode, cur, max)
	if mode == "value" then
		return string.format("%s / %s", Data.Short(cur), Data.Short(max))
	elseif mode == "current" then
		return Data.Short(cur)
	elseif mode == "percent" then
		return string.format("%d%%", max > 0 and math.floor(cur / max * 100 + 0.5) or 0)
	elseif mode == "missing" then
		return max - cur > 0 and ("-" .. Data.Short(max - cur)) or ""
	end
	return ""
end

local function Percent(value, max)
	return max * value / 100
end

local function Range(key, label, default, max, step)
	return { key = key, type = "range", label = label, min = 0, max = max or 100, step = step or 1, default = default,
		hidden = Data.HiddenWhenLive }
end

-- Health ------------------------------------------------------------------------

local HEALTH_SEGMENTS = {
	{ key = "heal", label = "Incoming heals", mode = "append", colorInherit = "colors.heal" },
	{ key = "absorb", label = "Absorb shields", mode = "append", colorInherit = "colors.absorb" },
	{ key = "healAbsorb", label = "Heal absorbs", mode = "inset", colorInherit = "colors.healAbsorb" },
}

local BORDER = { border = { enabled = true } }

local function ApplyHealthColor(bar, d, unit, fraction)
	if d.colorMode == "class" then
		local class = unit and select(2, UnitClass(unit)) or d.class
		bar:SetColor(Data.ClassColor(class))
	elseif d.colorMode == "gradient" then
		local color
		if unit then
			color = UnitHealthPercent(unit, true, Data.HealthCurve())
		else
			color = Data.HealthCurve():Evaluate(fraction)
		end
		bar:SetColor(color:GetRGBA())
	else
		bar:ClearColor()
	end
end

local function ShowStaticHealth(handle, d, healthPct, healPct, absorbPct, healAbsorbPct)
	local bar, left, right = handle.parts.bar, handle.parts.left, handle.parts.right
	local max = d.max
	local cur = Percent(healthPct, max)
	bar:SetRange(0, max)
	bar:SetValue(cur)
	bar:SetSegmentValue("heal", Percent(healPct, max))
	bar:SetSegmentValue("absorb", Percent(absorbPct, max))
	bar:SetSegmentValue("healAbsorb", Percent(healAbsorbPct, max))
	ApplyHealthColor(bar, d, nil, healthPct / 100)
	left:SetText(d.name)
	right:SetText(StaticText(d.rightText, cur, max))
end

-- Everything here may be secret: values go straight into widgets.
local function ShowLiveHealth(handle, d)
	local bar, left, right = handle.parts.bar, handle.parts.left, handle.parts.right
	local unit = d.source
	if not UnitExists(unit) then
		bar:SetRange(0, 1)
		bar:SetValue(0)
		left:SetText("no " .. unit)
		right:SetText("")
		return
	end
	local cur, max = UnitHealth(unit), UnitHealthMax(unit)
	bar:SetRange(0, max)
	bar:SetValue(cur)
	bar:SetSegmentValue("heal", UnitGetIncomingHeals(unit) or 0)
	bar:SetSegmentValue("absorb", UnitGetTotalAbsorbs(unit))
	bar:SetSegmentValue("healAbsorb", UnitGetTotalHealAbsorbs(unit))
	ApplyHealthColor(bar, d, unit)
	left:SetText(UnitName(unit))
	local mode = d.rightText
	if mode == "value" then
		right:SetFormattedText("%s / %s", Data.Short(cur), Data.Short(max))
	elseif mode == "current" then
		right:SetText(Data.Short(cur))
	elseif mode == "percent" then
		right:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, Data.PercentCurve()))
	elseif mode == "missing" then
		right:SetText(Data.Short(UnitHealthMissing(unit)))
	else
		right:SetText("")
	end
end

Workbench:Register({
	id = "bar.health",
	category = "Bars",
	name = "Health",
	size = { 240, 28 },
	create = function(stage)
		return BarWithTexts(stage, { segments = HEALTH_SEGMENTS })
	end,
	defaultConfig = { bar = BORDER },
	presets = {
		{ name = "With shields", config = { bar = BORDER } },
		{ name = "Without shields", config = { bar = { border = { enabled = true }, segments = {
			heal = { enabled = false }, absorb = { enabled = false }, healAbsorb = { enabled = false },
		} } } },
		{ name = "Flat", config = { bar = { texture = "Solid", border = { enabled = true, border = "UnitFrames Pixel",
			size = 1, inset = 0, padding = 1, color = { 0, 0, 0, 1 } } } } },
		{ name = "Reversed", config = { bar = { reverseFill = true, border = { enabled = true } } } },
		{ name = "Vertical", size = { 34, 140 }, config = { bar = { orientation = "VERTICAL", border = { enabled = true } },
			left = { enabled = false }, right = { enabled = false } } },
	},
	data = {
		schema = {
			{ key = "source", type = "select", label = "Source", values = Data.Sources(true), default = "static" },
			Range("max", "Max health", 24000, 200000, 100),
			Range("health", "Health %", 65),
			Range("heal", "Incoming heals %", 15),
			Range("absorb", "Absorb shields %", 20),
			Range("healAbsorb", "Heal absorbs %", 8),
			{ key = "colorMode", type = "select", label = "Colour", default = "class", values = {
				{ "theme", "Theme colour" },
				{ "class", "Class colour" },
				{ "gradient", "Health gradient" },
			} },
			{ key = "class", type = "select", label = "Class", values = Data.Classes, default = "PALADIN",
				hidden = function(d) return d.colorMode ~= "class" or Data.IsLive(d) end },
			{ key = "name", type = "text", label = "Name", default = "Uther", hidden = Data.HiddenWhenLive },
			{ key = "rightText", type = "select", label = "Right text", values = TEXT_MODES, default = "value" },
		},
		update = function(handle, d)
			if d.source == "static" then
				ShowStaticHealth(handle, d, d.health, d.heal, d.absorb, d.healAbsorb)
			end
		end,
		tick = function(handle, d, es)
			if d.source == "animated" then
				local t = es.time
				ShowStaticHealth(handle, d, 10 + 85 * Data.Wave(t, 0.7), d.heal * Data.Wave(t, 1.3, 1),
					d.absorb * Data.Wave(t, 0.5, 2), d.healAbsorb * Data.Wave(t, 0.9, 3))
			elseif Data.IsLive(d) then
				ShowLiveHealth(handle, d)
			end
		end,
	},
})

-- Power ---------------------------------------------------------------------------

local function ShowStaticPower(handle, d, powerPct, costPct)
	local bar, left, right = handle.parts.bar, handle.parts.left, handle.parts.right
	local max = d.max
	local cur = Percent(powerPct, max)
	bar:SetRange(0, max)
	bar:SetValue(cur)
	bar:SetSegmentValue("cost", Percent(costPct, max))
	bar:SetColor(Data.PowerColor(d.powerType))
	left:SetText("")
	right:SetText(StaticText(d.rightText, cur, max))
end

local function ShowLivePower(handle, d)
	local bar, left, right = handle.parts.bar, handle.parts.left, handle.parts.right
	local unit = d.source
	if not UnitExists(unit) then
		bar:SetRange(0, 1)
		bar:SetValue(0)
		right:SetText("no " .. unit)
		return
	end
	local _, token = UnitPowerType(unit)
	local cur, max = UnitPower(unit), UnitPowerMax(unit)
	bar:SetRange(0, max)
	bar:SetValue(cur)
	bar:SetSegmentValue("cost", 0)
	bar:SetColor(Data.PowerColor(token))
	left:SetText("")
	local mode = d.rightText
	if mode == "value" then
		right:SetFormattedText("%s / %s", Data.Short(cur), Data.Short(max))
	elseif mode == "current" then
		right:SetText(Data.Short(cur))
	elseif mode == "percent" then
		right:SetFormattedText("%.0f%%", UnitPowerPercent(unit, nil, false, Data.PercentCurve()))
	elseif mode == "missing" and UnitPowerMissing then
		right:SetText(Data.Short(UnitPowerMissing(unit)))
	else
		right:SetText("")
	end
end

Workbench:Register({
	id = "bar.power",
	category = "Bars",
	name = "Power / mana",
	size = { 240, 14 },
	create = function(stage)
		return BarWithTexts(stage, {
			colorInherit = "colors.mana",
			segments = { { key = "cost", label = "Spell cost", mode = "inset", colorInherit = "colors.powerCost" } },
		})
	end,
	defaultConfig = { bar = { border = { enabled = true, size = 8, inset = 2, padding = 2 } }, right = { size = 9 } },
	presets = {
		{ name = "Thin", size = { 240, 10 }, config = { bar = { border = { enabled = true, size = 8, inset = 2, padding = 2 } },
			right = { enabled = false } } },
		{ name = "No border", size = { 240, 10 }, config = { right = { size = 9 } } },
		{ name = "Without cost", config = { bar = { border = { enabled = true, size = 8, inset = 2, padding = 2 },
			segments = { cost = { enabled = false } } }, right = { size = 9 } } },
	},
	data = {
		schema = {
			{ key = "source", type = "select", label = "Source", values = Data.Sources(true), default = "static" },
			{ key = "powerType", type = "select", label = "Power type", values = Data.POWER_TYPES, default = "MANA",
				hidden = Data.HiddenWhenLive },
			Range("max", "Max power", 12000, 100000, 100),
			Range("power", "Power %", 70),
			Range("cost", "Spell cost %", 15),
			{ key = "rightText", type = "select", label = "Right text", values = TEXT_MODES, default = "value" },
		},
		update = function(handle, d)
			if d.source == "static" then
				ShowStaticPower(handle, d, d.power, d.cost)
			end
		end,
		tick = function(handle, d, es)
			if d.source == "animated" then
				-- Energy-style: fills up, spends a chunk, fills again.
				local fill = (es.time * 25) % 100
				ShowStaticPower(handle, d, fill, d.cost)
			elseif Data.IsLive(d) then
				ShowLivePower(handle, d)
			end
		end,
	},
})

-- Experience ------------------------------------------------------------------------

local function ShowExperience(handle, d, cur, max, rested, level)
	local bar, left, right = handle.parts.bar, handle.parts.left, handle.parts.right
	bar:SetRange(0, max)
	bar:SetValue(cur)
	bar:SetSegmentValue("rested", rested)
	left:SetFormattedText("Level %s", level)
	if UF.Util.IsSecret(cur) or UF.Util.IsSecret(max) then
		right:SetFormattedText("%s / %s", Data.Short(cur), Data.Short(max))
	elseif d.rightText == "none" then
		right:SetText("")
	elseif d.rightText == "percent" then
		right:SetText(StaticText("percent", cur, max))
	else
		right:SetFormattedText("%s / %s (%d%%)", Data.Short(cur), Data.Short(max), max > 0 and math.floor(cur / max * 100) or 0)
	end
end

Workbench:Register({
	id = "bar.experience",
	category = "Bars",
	name = "Experience",
	size = { 320, 16 },
	create = function(stage)
		return BarWithTexts(stage, {
			colorInherit = "colors.experience",
			segments = { { key = "rested", label = "Rested", mode = "append", colorInherit = "colors.rested" } },
		})
	end,
	defaultConfig = {
		bar = { smooth = true, border = { enabled = true, size = 8, inset = 2, padding = 2 } },
		left = { size = 9 },
		right = { size = 9 },
	},
	presets = {
		{ name = "Without rested", config = { bar = { border = { enabled = true, size = 8, inset = 2, padding = 2 },
			segments = { rested = { enabled = false } } }, left = { size = 9 }, right = { size = 9 } } },
		{ name = "Slim", size = { 320, 6 }, config = { left = { enabled = false }, right = { enabled = false } } },
	},
	data = {
		schema = {
			{ key = "source", type = "select", label = "Source", values = Data.Sources(false), default = "static" },
			Range("level", "Level", 24, 60),
			Range("max", "XP for level", 25000, 200000, 100),
			Range("xp", "XP %", 40),
			Range("rested", "Rested %", 30),
			{ key = "rightText", type = "select", label = "Right text", default = "value", values = {
				{ "value", "Current / max (%)" },
				{ "percent", "Percent" },
				{ "none", "None" },
			} },
		},
		update = function(handle, d)
			if d.source == "static" then
				ShowExperience(handle, d, Percent(d.xp, d.max), d.max, Percent(d.rested, d.max), d.level)
			end
		end,
		tick = function(handle, d, es)
			if d.source == "animated" then
				local xp = (es.time * 8) % 100
				ShowExperience(handle, d, Percent(xp, d.max), d.max, Percent(d.rested, d.max), d.level)
			elseif d.source == "player" then
				ShowExperience(handle, d, UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0, UnitLevel("player"))
			end
		end,
	},
})
