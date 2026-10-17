local _, wb = ...
local UF = UnitFrames
local Workbench = wb.Workbench

--[[
Unit frames: a preview of the frame filled with sample values. The Style tab
edits the real, saved settings of that unit frame, so every change shows on
the preview and on the live frame at the same time.
]]

local function UnitHandle(stage, unit)
	return Workbench.ComponentHandle("uf", UF.Units:CreateFrame(unit, stage), function()
		return UF.Config:GetUnitConfig(unit)
	end)
end

local function UnitStyleTarget(unit)
	return function(handle)
		local schema = {}
		if unit ~= "player" then
			schema[#schema + 1] = {
				key = "copyPlayerSettings", type = "action", label = "Copy player settings",
				tooltip = "Replace this frame's style with the player's current settings, including sizes, text, portrait, castbar, auras, raid target, PvP flag and elite icons, range opacity and ready check colours. Position, player-only XP and combo points are not copied. This is a one-time copy, not a link.",
			}
		end
		for _, opt in ipairs(handle.schema) do schema[#schema + 1] = opt end
		-- Writes also refresh the live frame (UnitConfigChanged).
		local target = UF.Config:UnitStore(unit):Target(nil, function() return handle:Resolved() end)
		target.schema = schema
		local invoke = target.invoke
		target.invoke = function(path)
			if path == "copyPlayerSettings" then UF.Units:CopyPlayerSettings(unit) else invoke(path) end
		end
		return target
	end
end

local function Range(key, label, default)
	return { key = key, type = "range", label = label, min = 0, max = 100, step = 1, default = default }
end

-- Sample values from the Data tab percentages.
local function Values(unit, d, healthPct, time)
	local v = UF.Units:GetSample(unit)
	v.class = d.class
	v.isPlayer = not d.npc
	v.className = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[d.class]) or d.class
	v.reaction = d.reaction
	v.creatureType = d.creatureType
	v.classification = d.npc and d.classification or "normal"
	v.powerType = d.powerType
	v.health = v.healthMax * healthPct / 100
	v.absorb = v.healthMax * d.absorb / 100
	v.power = v.powerMax * d.power / 100
	if d.xp then v.xp = v.xpMax * d.xp / 100 end
	-- Animated: one more point per second, then empty again.
	if d.comboPoints then
		v.comboPoints = time and math.floor(time) % (v.comboPointsMax + 1) or d.comboPoints
	end
	v.showCast = d.showCast
	v.status = d.status ~= "none" and d.status or nil
	v.raidTarget = d.raidTarget
	v.pvp = d.pvp
	v.outOfRange = d.outOfRange
	v.resting = unit == "player" and d.resting
	v.restingAnimated = time ~= nil
	v.readyCheck = d.readyCheck ~= "off" and d.readyCheck or nil
	v.readyCheckTime = time
	v.animateAuras = time ~= nil
	v.castProgress = d.castProgress / 100
	-- Animated: one global cooldown every 1.5 seconds.
	if time then v.gcdProgress = time % 1.5 / 1.5 end
	-- Animated cycling: each category for two seconds, then none.
	local categories = UF.Components.CategoryAuras.CATEGORIES
	local cycled = time and categories[math.floor(time / 2) % (#categories + 1) + 1]
	v.categoryAuras = {}
	for key, aura in pairs(UF.Units.CATEGORY_SAMPLES) do
		local cycle = d.categoryAuras == "cycle" and (not time or cycled and cycled.key == key)
		if cycle or d.categoryAuras == "all" or d.categoryAuras == key then
			aura = UF.Util.Copy(aura)
			if time then aura.remaining = (aura.remaining - time - 1) % aura.duration + 1 end
			v.categoryAuras[key] = aura
		end
	end
	for _, kind in ipairs({ "buffs", "debuffs" }) do
		local samples = v[kind]
		v[kind] = {}
		for i = 1, d[kind .. "Count"] do
			local aura = UF.Util.Copy(samples[(i - 1) % #samples + 1])
			if time and aura.duration > 0 then
				aura.remaining = (aura.remaining - time - 1) % aura.duration + 1
			end
			v[kind][i] = aura
		end
	end
	return v
end

local function RegisterUnit(unit)
	local def, sample = UF.Units:GetDefinition(unit), UF.Units:GetSample(unit)
	local settingsPages = {
		{ id = "@icons", label = "Icons", paths = { "raidTarget", "pvp", "classification" } },
		{ id = "@effects", label = "State effects", paths = { "range" } },
	}
	if def.restingIcon then table.insert(settingsPages[1].paths, "restingIcon") end
	local effects = settingsPages[2].paths
	if def.resting then effects[#effects + 1] = "resting" end
	effects[#effects + 1] = "readyCheck"
	effects[#effects + 1] = "readyCheckIcon"
	-- Animated health waves; static uses the Data tab's health.
	local function ShowSample(handle, d, es)
		local animated = d.source == "animated"
		UF.Units:ShowSample(handle.parts.uf, Values(unit, d,
			animated and 10 + 85 * wb.Data.Wave(es.time, 0.7) or d.health, animated and es.time or nil))
	end
	local schema = {
		{ key = "source", type = "select", label = "Source", default = "static", values = {
			{ "static", "Static (sliders)" }, { "animated", "Animated" },
		} },
		Range("health", "Health %", 65),
		Range("absorb", "Absorb shields %", 15),
		Range("power", "Power %", 70),
		{ key = "outOfRange", type = "toggle", label = "Out of range", default = false,
			tooltip = "Preview the saved out-of-range opacity. Enable it in the frame's Out-of-range opacity style section first." },
		{ key = "powerType", type = "select", label = "Power type", values = wb.Data.POWER_TYPES, default = sample.powerType },
		{ key = "class", type = "select", label = "Class", values = wb.Data.Classes, default = sample.class,
			hidden = function(d) return d.npc end },
		{ key = "showCast", type = "toggle", label = "Show a cast", default = true,
			tooltip = "Sample cast on the castbar. Turn off to see the health bar under a castbar placed over it." },
		Range("castProgress", "Cast progress %", 60),
		{ key = "raidTarget", type = "select", label = "Raid target marker", default = 8,
			values = UF.Components.RaidTarget.MARKERS },
		{ key = "readyCheck", type = "select", label = "Ready check", default = "off", values = {
			{ "off", "None" }, { "waiting", "Waiting" }, { "ready", "Ready" }, { "notready", "Not ready" },
		}, tooltip = "Preview the saved ready check tints and icon. Static holds the answer; Animated loops a whole check: waiting, the answer, then the hold and fade after it ends." },
		{ key = "status", type = "select", label = "Offline / dead", default = "none",
			values = { { "none", "Neither" }, { "offline", "Offline" }, { "dead", "Dead" } },
			tooltip = "Sample state for the Offline / dead text source. The bars still show the sample values." },
		{ key = "pvp", type = "select", label = "PvP flag", default = "off", values = UF.Formats.PVP_FLAGS,
			tooltip = "Sample flag for the PvP flag icon and beside Level + class or Level + class or creature type text." },
		{ key = "buffsCount", type = "range", label = "Sample buffs", min = 0, max = 40, step = 1, default = 8,
			tooltip = "The Buffs style's filter and Maximum shown still apply." },
		{ key = "debuffsCount", type = "range", label = "Sample debuffs", min = 0, max = 40, step = 1, default = 5,
			tooltip = "The Debuffs style's filter and Maximum shown still apply." },
		{ key = "categoryAuras", type = "select", label = "Crowd control & defensives", default = "off", values = {
			{ "off", "None" }, { "crowdControl", "Crowd control" }, { "bigDefensive", "Big defensive" },
			{ "externalDefensive", "External defensive" }, { "important", "Important buff" }, { "all", "All (highest on top)" },
			{ "cycle", "Cycle" },
		}, tooltip = "Sample auras for the Crowd control & defensives icons. All stacks every sample; the highest enabled category covers the others. Cycle shows each category in turn in Animated previews, then none; Static shows them all." },
	}
	if unit == "player" then
		schema[#schema + 1] = { key = "resting", type = "toggle", label = "Resting", default = false,
			tooltip = "Preview the resting border, resting icon and Resting (zZz) text. Static holds the resting colour; Animated pulses it." }
		schema[#schema + 1] = Range("xp", "XP %", 42)
	else
		schema[#schema + 1] = { key = "npc", type = "toggle", label = "NPC", default = sample.isPlayer == false }
		schema[#schema + 1] = { key = "reaction", type = "select", label = "NPC reaction", default = sample.reaction or "hostile",
			values = { { "hostile", "Hostile" }, { "neutral", "Neutral" }, { "friendly", "Friendly" }, { "tapped", "Tapped by others" } },
			hidden = function(d) return not d.npc end }
		schema[#schema + 1] = { key = "creatureType", type = "text", label = "Creature type", default = sample.creatureType or "Humanoid",
			hidden = function(d) return not d.npc end }
		schema[#schema + 1] = { key = "classification", type = "select", label = "Classification", default = sample.classification or "normal",
			values = { { "normal", "Normal" }, { "elite", "Elite" }, { "rare", "Rare" }, { "rareelite", "Rare elite" }, { "worldboss", "Boss" } },
			hidden = function(d) return not d.npc end,
			tooltip = "Sample NPC classification for the elite / rare icon and the level marker texts." }
	end
	if def.comboPoints then
		schema[#schema + 1] = { key = "comboPoints", type = "range", label = "Combo points", min = 0,
			max = sample.comboPointsMax, step = 1, default = sample.comboPoints,
			hidden = function() return not UF.Units.PlayerHasComboPoints() end,
			tooltip = "Static holds this count; Animated counts up and empties again. Shown for rogues and druids, while the frame's Combo points row is enabled." }
	end
	Workbench:Register({
		id = "unit." .. unit,
		refreshOn = { { "UnitConfigChanged", unit } },
		category = "Unit frames",
		name = def.label,
		autoSize = true,
		size = { def.width, 60 },
		create = function(stage)
			return UnitHandle(stage, unit)
		end,
		styleTarget = UnitStyleTarget(unit),
		settingsPages = settingsPages,
		reset = function() UF.Config:UnitStore(unit):Reset() end,
		data = {
			schema = schema,
			update = ShowSample,
			tick = function(handle, d, es)
				if d.source == "animated" then ShowSample(handle, d, es) end
			end,
		},
	})
end

for _, unit in ipairs(UF.Units.order) do RegisterUnit(unit) end
