local _, ns = ...

-- Global look shared by every component. Component options with `inherit`
-- read from here unless the component overrides them.
local Theme = {}
ns.Theme = Theme

Theme.OUTLINES = {
	{ "", "None" },
	{ "OUTLINE", "Outline" },
	{ "THICKOUTLINE", "Thick outline" },
	{ "MONOCHROME", "Monochrome" },
}

local function Color(label, r, g, b, a)
	return { type = "color", label = label, default = { r, g, b, a or 1 } }
end

local function Colors(list)
	local schema = {}
	for _, entry in ipairs(list) do
		local opt = Color(entry[2], entry[3], entry[4], entry[5], entry[6])
		opt.key = entry[1]
		schema[#schema + 1] = opt
	end
	return schema
end

Theme.schema = {
	{ key = "font", type = "font", label = "Font", default = "Friz Quadrata TT" },
	{ key = "fontSize", type = "range", label = "Font size", min = 6, max = 32, step = 1, default = 11 },
	{ key = "fontOutline", type = "select", label = "Font outline", values = Theme.OUTLINES, default = "" },
	{ key = "barTexture", type = "statusbar", label = "Bar texture", default = "Blizzard Raid Bar" },
	-- Blizzard's tooltip border gives the chamfered ZPerl look.
	{ key = "borderTexture", type = "border", label = "Border", default = "Blizzard Tooltip" },
	{ key = "borderSize", type = "range", label = "Border size", min = 1, max = 32, step = 1, default = 12 },
	{ key = "borderColor", type = "color", label = "Border colour", default = { 0.5, 0.5, 0.5, 1 } },
	{ key = "backgroundTexture", type = "background", label = "Background", default = "Solid" },
	{ key = "backgroundColor", type = "color", label = "Background colour", default = { 0, 0, 0, 0.75 } },
	{ key = "colors", type = "group", label = "Colours", schema = Colors({
		{ "health", "Health", 0.1, 0.8, 0.1 },
		{ "healthLow", "Health (low)", 0.8, 0.1, 0.1 },
		{ "healthMid", "Health (mid)", 1, 0.8, 0 },
		{ "hostile", "Hostile NPC", 0.85, 0.15, 0.1 },
		{ "neutral", "Neutral NPC", 0.95, 0.8, 0.15 },
		{ "friendly", "Friendly NPC", 0.2, 0.75, 0.2 },
		{ "tapped", "Tapped by others", 0.55, 0.55, 0.55 },
		{ "disconnected", "Disconnected", 0.45, 0.45, 0.45 },
		{ "heal", "Incoming heals", 0.2, 1, 0.3, 0.5 },
		{ "absorb", "Absorb shields", 0.2, 0.65, 1, 0.75 },
		{ "healAbsorb", "Heal absorbs", 0.6, 0, 0, 0.6 },
		{ "mana", "Mana", 0, 0.38, 1 },
		{ "rage", "Rage", 0.9, 0.1, 0.1 },
		{ "energy", "Energy", 1, 0.85, 0.1 },
		{ "focus", "Focus", 1, 0.5, 0.25 },
		{ "runicPower", "Runic power", 0, 0.82, 1 },
		{ "comboPoints", "Combo points", 1, 0.96, 0.41 },
		{ "powerCost", "Power cost", 0.4, 0.4, 1, 0.6 },
		{ "experience", "Experience", 0.58, 0, 0.55 },
		{ "rested", "Rested", 0, 0.39, 0.88, 0.6 },
		{ "cast", "Cast", 1, 0.7, 0 },
		{ "channel", "Channel", 0, 1, 0 },
		{ "nonInterruptible", "Not interruptible", 0.7, 0.7, 0.7 },
		{ "castFailed", "Cast failed", 1, 0, 0 },
		{ "castSuccess", "Cast succeeded", 0, 1, 0 },
	}) },
}
