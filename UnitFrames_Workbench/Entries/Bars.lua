local _, wb = ...
local UF = UnitFrames
if not UF.isDevelopment then return end
local Workbench, Data = wb.Workbench, wb.Data
local C, Colors, Rows = UF.Components, UF.Colors, UF.UnitRows

-- One TextBar (bar + left/centre/right text) as an inspectable handle.
local function TextBarHandle(stage, spec)
	return Workbench.Composite({
		{ key = "row", label = "Bar", component = C.TextBar:New(stage, {}, spec) },
	})
end

local function Percent(value, max)
	return max * value / 100
end

local function Range(key, label, default, max, step)
	return { key = key, type = "range", label = label, min = 0, max = max or 100, step = step or 1, default = default,
		hidden = Data.IsLive }
end

local function NoUnit(row, unit)
	row:SetRange(0, 1)
	row:SetValue(0)
	for _, text in row:EnabledTexts() do
		text:SetText("")
	end
	row:GetText("center"):SetText("no " .. unit)
end

-- Health ------------------------------------------------------------------------

local HEALTH_SPEC = Rows.Spec("health", { left = "name", right = "health:value" })

local BORDER = { bar = { border = { enabled = true } } }

-- The standalone bar shows class colours only, also for NPCs.
local function ApplySampleHealthColor(row, d, fraction)
	if d.colorMode == "class" then
		row:SetColor(Colors.Class(d.class))
	elseif d.colorMode == "gradient" then
		row:SetColor(Colors.HealthCurve():Evaluate(fraction):GetRGB())
	else
		row:ClearColor()
	end
end

local function UnitClassColor(unit)
	return Colors.Class(select(2, UnitClass(unit)))
end

local function ShowStaticHealth(handle, d, healthPct, healPct, absorbPct, healAbsorbPct)
	local row, max = handle.parts.row, d.max
	local cur = Percent(healthPct, max)
	local absorb = Percent(absorbPct, max)
	Rows.SampleHealth(row, { health = cur, healthMax = max, heal = Percent(healPct, max),
		absorb = absorb, healAbsorb = Percent(healAbsorbPct, max) })
	ApplySampleHealthColor(row, d, healthPct / 100)
	row:ShowSample({ name = d.name, level = 42, health = cur, healthMax = max })
end

-- Everything here may be secret: values go straight into widgets.
local function ShowLiveHealth(handle, d)
	local row, unit = handle.parts.row, d.source
	if not UnitExists(unit) then
		return NoUnit(row, unit)
	end
	handle.healthValues = handle.healthValues or CreateUnitHealPredictionCalculator()
	Rows.LiveHealth(row, unit, handle.healthValues, d.colorMode, UnitClassColor)
end

Workbench:Register({
	id = "bar.health",
	category = "Bars",
	name = "Health",
	size = { 240, 28 },
	create = function(stage)
		return TextBarHandle(stage, HEALTH_SPEC)
	end,
	defaultConfig = { row = BORDER },
	presets = {
		{ name = "With shields", config = { row = BORDER } },
		{ name = "Without shields", config = { row = { bar = { border = { enabled = true }, segments = {
			heal = { enabled = false }, absorb = { enabled = false }, healAbsorb = { enabled = false },
		} } } } },
		{ name = "Centre text", config = { row = { bar = { border = { enabled = true } },
			left = { enabled = false }, right = { enabled = false },
			center = { enabled = true, format = "health:current:percent" } } } },
		{ name = "Flat", config = { row = { bar = { texture = "Solid", border = { enabled = true, border = "UnitFrames Pixel",
			size = 1, inset = 0, padding = 1, color = { 0, 0, 0, 1 } } } } } },
		{ name = "Reversed", config = { row = { bar = { reverseFill = true, border = { enabled = true } } } } },
		{ name = "Vertical", size = { 34, 140 }, config = { row = { bar = { orientation = "VERTICAL", border = { enabled = true } },
			left = { enabled = false }, right = { enabled = false } } } },
	},
	data = {
		schema = {
			{ key = "source", type = "select", label = "Source", values = Data.Sources(true), default = "static" },
			Range("max", "Max health", 24000, 200000, 100),
			Range("health", "Health %", 65),
			Range("heal", "Incoming heals %", 15),
			Range("absorb", "Absorb shields %", 20),
			Range("healAbsorb", "Heal absorbs %", 8),
			{ key = "colorMode", type = "select", label = "Colour", default = "class", values = UF.Units.HEALTH_COLOR_MODES },
			{ key = "class", type = "select", label = "Class", values = Data.Classes, default = "PALADIN",
				hidden = function(d) return d.colorMode ~= "class" or Data.IsLive(d) end },
			{ key = "name", type = "text", label = "Name", default = "Uther", hidden = Data.IsLive },
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

local POWER_SPEC = Rows.Spec("power")

local THIN_BORDER = { enabled = true, size = 8, inset = 2, padding = 2 }

local function ShowStaticPower(handle, d, powerPct, costPct)
	local row, max = handle.parts.row, d.max
	local cur = Percent(powerPct, max)
	Rows.SamplePower(row, { power = cur, powerMax = max, cost = Percent(costPct, max), powerType = d.powerType })
	row:ShowSample({ name = "Uther", level = 42, power = cur, powerMax = max })
end

local function ShowLivePower(handle, d)
	local row, unit = handle.parts.row, d.source
	if not UnitExists(unit) then
		return NoUnit(row, unit)
	end
	Rows.LivePower(row, unit)
end

Workbench:Register({
	id = "bar.power",
	category = "Bars",
	name = "Power / mana",
	size = { 240, 14 },
	create = function(stage)
		return TextBarHandle(stage, POWER_SPEC)
	end,
	defaultConfig = { row = { bar = { border = THIN_BORDER }, right = { size = 9 } } },
	presets = {
		{ name = "Centre text", config = { row = { bar = { border = THIN_BORDER }, right = { enabled = false },
			center = { enabled = true, format = "power:value", size = 9 } } } },
		{ name = "Thin", size = { 240, 10 }, config = { row = { bar = { border = THIN_BORDER }, right = { enabled = false } } } },
		{ name = "No border", size = { 240, 10 }, config = { row = { right = { size = 9 } } } },
		{ name = "Without cost", config = { row = { bar = { border = THIN_BORDER, segments = { cost = { enabled = false } } },
			right = { size = 9 } } } },
	},
	data = {
		schema = {
			{ key = "source", type = "select", label = "Source", values = Data.Sources(true), default = "static" },
			{ key = "powerType", type = "select", label = "Power type", values = Data.POWER_TYPES, default = "MANA",
				hidden = Data.IsLive },
			Range("max", "Max power", 12000, 100000, 100),
			Range("power", "Power %", 70),
			Range("cost", "Spell cost %", 15),
		},
		update = function(handle, d)
			if d.source == "static" then
				ShowStaticPower(handle, d, d.power, d.cost)
			end
		end,
		tick = function(handle, d, es)
			if d.source == "animated" then
				-- Energy-style: fills up, spends a chunk, fills again.
				ShowStaticPower(handle, d, (es.time * 25) % 100, d.cost)
			elseif Data.IsLive(d) then
				ShowLivePower(handle, d)
			end
		end,
	},
})

-- Experience ------------------------------------------------------------------------

local XP_SPEC = Rows.Spec("experience", { left = "level", right = "xp:value:percent" })

local function ShowExperience(handle, cur, max, rested, level, live)
	local row = handle.parts.row
	Rows.Experience(row, cur, max, rested)
	if live then
		row:ShowLive("player")
	else
		row:ShowSample({ level = level, xp = cur, xpMax = max, rested = rested })
	end
end

Workbench:Register({
	id = "bar.experience",
	category = "Bars",
	name = "Experience",
	size = { 320, 16 },
	create = function(stage)
		return TextBarHandle(stage, XP_SPEC)
	end,
	defaultConfig = { row = { bar = { border = THIN_BORDER }, left = { size = 9 }, right = { size = 9 } } },
	presets = {
		{ name = "Centre text", config = { row = { bar = { border = THIN_BORDER }, left = { enabled = false },
			right = { enabled = false }, center = { enabled = true, format = "xp:value:percent", size = 9 } } } },
		{ name = "Without rested", config = { row = { bar = { border = THIN_BORDER, segments = { rested = { enabled = false } } },
			left = { size = 9 }, right = { size = 9 } } } },
		{ name = "Slim", size = { 320, 6 }, config = { row = { left = { enabled = false }, right = { enabled = false } } } },
	},
	data = {
		schema = {
			{ key = "source", type = "select", label = "Source", values = Data.Sources(false), default = "static" },
			Range("level", "Level", 24, 60),
			Range("max", "XP for level", 25000, 200000, 100),
			Range("xp", "XP %", 40),
			Range("rested", "Rested %", 30),
		},
		update = function(handle, d)
			if d.source == "static" then
				ShowExperience(handle, Percent(d.xp, d.max), d.max, Percent(d.rested, d.max), d.level)
			end
		end,
		tick = function(handle, d, es)
			if d.source == "animated" then
				ShowExperience(handle, Percent((es.time * 8) % 100, d.max), d.max, Percent(d.rested, d.max), d.level)
			elseif d.source == "player" then
				ShowExperience(handle, UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0, nil, true)
			end
		end,
	},
})
