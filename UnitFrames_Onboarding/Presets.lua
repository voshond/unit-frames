local _, ob = ...
local UF = UnitFrames

--[[
Getting started data. A preset's `style` has the shape of a style string's
data (Core/Profiles.lua: theme, units, sections such as timers), so it goes
through the same validation as an import. Missing parts mean defaults: every
preset replaces the theme, all unit frames and the timers.

Tweaks (step 2) and extras (step 3) change a composed copy of a preset:
  write(style, value)            change the style table
  read(resolved) -> value        the current choice, from Pending:Resolved()
]]
local Presets = { byId = {}, tweaksByKey = {}, extrasByKey = {} }
ob.Presets = Presets

local function EveryUnit(config)
	local units = {}
	for _, unit in ipairs(UF.Units.order) do units[unit] = UF.Util.Copy(config) end
	return units
end

Presets.list = {
	{ id = "default", name = "Default", tags = { "Balanced", "3D portraits" },
		pitch = "The shared UnitFrames style: centred texts, 3D portraits and a standalone castbar.",
		style = {} },
	{ id = "minimal", name = "Minimal", tags = { "Flat", "No portraits" },
		pitch = "Flat bars with a one-pixel border and no portraits. Calm and compact.",
		style = {
			theme = { borderTexture = "UnitFrames Pixel", borderSize = 1, borderColor = { 0, 0, 0, 1 },
				barTexture = "Solid", backgroundColor = { 0.06, 0.06, 0.08, 0.85 } },
			units = EveryUnit({ portrait = { enabled = false }, border = { padding = 1, inset = 1 } }),
		} },
	{ id = "classic", name = "Classic", tags = { "Gold trim", "Portraits" },
		pitch = "A nod to the old frames: gold trim, painted portraits and green health bars.",
		style = {
			theme = { font = "Friz Quadrata TT", fontSize = 12, borderTexture = "Blizzard Dialog Gold", borderSize = 16,
				borderColor = { 1, 1, 1, 1 }, barTexture = "Blizzard" },
			units = EveryUnit({ portrait = { mode = "2D" }, health = { colorMode = "theme" }, border = { padding = 5, inset = 4 } }),
		} },
	{ id = "healer", name = "Healer", tags = { "Wide bars", "Class colours" },
		pitch = "Wide, tall health bars in class colours. Pairs well with ClickGrid for your group.",
		style = {
			theme = { barTexture = "Blizzard Raid Bar", fontSize = 12 },
			units = EveryUnit({ portrait = { enabled = false }, health = { colorMode = "class", height = 30 } }),
		} },
}

-- Writes `path` = value into every unit frame of a style.
local function AllUnits(path)
	return function(style, value)
		for _, unit in ipairs(UF.Units.order) do UF.Util.SetPath(style.units[unit], path, value) end
	end
end

local BORDERS = {
	none = { borderTexture = "None", borderSize = 1 },
	pixel = { borderTexture = "UnitFrames Pixel", borderSize = 1, borderColor = { 0, 0, 0, 1 } },
	tooltip = { borderTexture = "Blizzard Tooltip", borderSize = 12, borderColor = { 0.5, 0.5, 0.5, 1 } },
	gold = { borderTexture = "Blizzard Dialog Gold", borderSize = 16, borderColor = { 1, 1, 1, 1 } },
}
local BORDER_OF = { None = "none", ["UnitFrames Pixel"] = "pixel", ["Blizzard Tooltip"] = "tooltip", ["Blizzard Dialog Gold"] = "gold" }

Presets.SIZES = { compact = 0.85, normal = 1, large = 1.2 }

Presets.tweaks = {
	{ key = "font", label = "Font", media = "font", choices = {
		{ "Roboto Condensed Medium", "Roboto" }, { "Friz Quadrata TT", "Friz Quadrata" },
		{ "Arial Narrow", "Arial Narrow" }, { "Morpheus", "Morpheus" } },
		write = function(style, value) style.theme.font = value end,
		read = function(resolved) return resolved.theme.font end },
	{ key = "barTexture", label = "Bar texture", media = "statusbar", choices = {
		{ "Solid", "Flat" }, { "Blizzard Raid Bar", "Raid bar" }, { "Blizzard", "Classic" }, { "Blizzard Character Skills Bar", "Gloss" } },
		write = function(style, value) style.theme.barTexture = value end,
		read = function(resolved) return resolved.theme.barTexture end },
	{ key = "border", label = "Border", choices = { { "none", "None" }, { "pixel", "Pixel" }, { "tooltip", "Tooltip" }, { "gold", "Gold" } },
		write = function(style, value) UF.Util.Merge(style.theme, UF.Util.Copy(BORDERS[value])) end,
		read = function(resolved) return BORDER_OF[resolved.theme.borderTexture] end },
	{ key = "healthColor", label = "Health colour", choices = { { "class", "Class" }, { "theme", "Green" }, { "gradient", "Gradient" } },
		write = AllUnits("health.colorMode"),
		read = function(resolved) return resolved.units.player.health.colorMode end },
	{ key = "portrait", label = "Portraits", choices = { { "3D", "3D" }, { "2D", "Painted" }, { "class", "Class icon" }, { "off", "Off" } },
		write = function(style, value)
			AllUnits("portrait.enabled")(style, value ~= "off")
			if value ~= "off" then AllUnits("portrait.mode")(style, value) end
		end,
		read = function(resolved)
			local portrait = resolved.units.player.portrait
			return portrait.enabled and portrait.mode or "off"
		end },
	{ key = "size", label = "Size", choices = { { "compact", "Compact" }, { "normal", "Normal" }, { "large", "Large" } },
		read = function(_, pending) return pending.size end },
}

local function UnitExtra(unit, path, extra)
	extra.write = function(style, value) UF.Util.SetPath(style.units[unit], path, value) end
	extra.read = function(resolved) return UF.Util.GetPath(resolved.units[unit], path) == true end
	return extra
end

local function TimerExtra(path, extra)
	extra.write = function(style, value) UF.Util.SetPath(style.timers, path, value) end
	extra.read = function(resolved) return UF.Util.GetPath(resolved.timers, path) == true end
	extra.area, extra.accent = "center", "cast"
	return extra
end

-- Step 3 tiles; `area` places them on the screen map (Steps/Extras.lua).
Presets.extras = {
	UnitExtra("player", "castbar.enabled", { key = "playerCast", label = "Player castbar", area = "player",
		hint = "A castbar attached to your own frame." }),
	UnitExtra("player", "experience.enabled", { key = "playerXP", label = "Experience", area = "player",
		hint = "Your XP and rested bar under the player frame." }),
	UnitExtra("player", "comboPoints.enabled", { key = "comboPoints", label = "Combo points", area = "player",
		hint = "Pips for rogues and druids in cat form." }),
	UnitExtra("target", "castbar.enabled", { key = "targetCast", label = "Target castbar", area = "target",
		hint = "See what your target is casting, and whether you can interrupt it." }),
	UnitExtra("focus", "castbar.enabled", { key = "focusCast", label = "Focus castbar", area = "focus",
		hint = "Keep an eye on your focus target's casts." }),
	TimerExtra("enabled", { key = "timers", label = "Timer bars",
		hint = "A big standalone castbar in the middle of the screen." }),
	TimerExtra("castbar.gcd.enabled", { key = "gcd", label = "Global cooldown",
		hint = "A thin global cooldown sweep under the timer castbar." }),
	TimerExtra("mainHand.enabled", { key = "swing", label = "Swing timer",
		hint = "Main-hand swings, for melee classes." }),
}

for _, preset in ipairs(Presets.list) do Presets.byId[preset.id] = preset end
for _, tweak in ipairs(Presets.tweaks) do Presets.tweaksByKey[tweak.key] = tweak end
for _, extra in ipairs(Presets.extras) do Presets.extrasByKey[extra.key] = extra end

-- Choices this client can show: media choices need their LibSharedMedia key.
function Presets.Choices(tweak)
	if not tweak.media then return tweak.choices end
	local choices = {}
	for _, choice in ipairs(tweak.choices) do
		if UF.Media.LSM:IsValid(tweak.media, choice[1]) then choices[#choices + 1] = choice end
	end
	return choices
end
