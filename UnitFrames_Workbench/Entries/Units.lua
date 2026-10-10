local _, wb = ...
local UF = UnitFrames
local Workbench = wb.Workbench

--[[
Unit frames: a preview of the frame filled with sample values. The Style tab
edits the real, saved settings of that unit frame, so every change shows on
the preview and on the live frame at the same time.
]]

local function UnitHandle(stage, unit)
	local uf = UF.Units:CreateFrame(unit, stage)
	return {
		frame = uf:GetFrame(),
		parts = { uf = uf },
		schema = uf:GetSchema(),
		Apply = function()
			uf:Apply(UF.Config:GetUnitConfig(unit))
		end,
		Resolved = function()
			return uf.resolved
		end,
		Release = function()
			uf:Release()
		end,
	}
end

local function UnitStyleTarget(unit)
	return function(handle)
		local schema = {}
		if unit ~= "player" then
			schema[#schema + 1] = {
				key = "copyPlayerSettings", type = "action", label = "Copy player settings",
				tooltip = "Replace this frame's style with the player's current settings, including sizes, text, portrait, castbar and auras. Position and player-only XP are not copied. This is a one-time copy, not a link.",
				run = function()
					if UF.Units:CopyPlayerSettings(unit) then
						-- Inspector pages are cached across preview recreation; use
						-- the current handle rather than capturing a released one.
						Workbench.handle:Apply()
						Workbench:UpdateData()
					end
				end,
			}
		end
		for _, opt in ipairs(handle.schema) do schema[#schema + 1] = opt end
		return {
			schema = schema,
			get = function(path)
				return UF.Util.GetPath(UF.Config:GetUnitConfig(unit), path)
			end,
			set = function(path, value)
				UF.Config:SetUnitValue(unit, path, value) -- also refreshes the live frame
				handle:Apply()
				Workbench:UpdateData()
			end,
			resolved = function()
				return handle:Resolved()
			end,
		}
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
	v.showCast = d.showCast
	v.castProgress = d.castProgress / 100
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
	local schema = {
		{ key = "source", type = "select", label = "Source", default = "static", values = {
			{ "static", "Static (sliders)" }, { "animated", "Animated" },
		} },
		Range("health", "Health %", 65),
		Range("absorb", "Absorb shields %", 15),
		Range("power", "Power %", 70),
		{ key = "powerType", type = "select", label = "Power type", values = wb.Data.POWER_TYPES, default = sample.powerType },
		{ key = "class", type = "select", label = "Class", values = wb.Data.Classes, default = sample.class,
			hidden = function(d) return d.npc end },
		{ key = "showCast", type = "toggle", label = "Show a cast", default = true,
			tooltip = "Sample cast on the castbar. Turn off to see the health bar under a castbar placed over it." },
		Range("castProgress", "Cast progress %", 60),
		{ key = "buffsCount", type = "range", label = "Sample buffs", min = 0, max = 40, step = 1, default = 8,
			tooltip = "The Buffs style's filter and Maximum shown still apply." },
		{ key = "debuffsCount", type = "range", label = "Sample debuffs", min = 0, max = 40, step = 1, default = 5,
			tooltip = "The Debuffs style's filter and Maximum shown still apply." },
	}
	if unit == "player" then
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
			hidden = function(d) return not d.npc end }
	end
	Workbench:Register({
		id = "unit." .. unit,
		category = "Unit frames",
		name = def.label,
		autoSize = true,
		size = { def.width, 60 },
		create = function(stage)
			return UnitHandle(stage, unit)
		end,
		styleTarget = UnitStyleTarget(unit),
		reset = function()
			wipe(UF.Config:GetUnitConfig(unit))
			UF.Events:Fire("UnitConfigChanged", unit)
		end,
		data = {
			schema = schema,
			update = function(handle, d, es)
				local animated = d.source == "animated"
				UF.Units:ShowSample(handle.parts.uf, Values(unit, d,
					animated and 10 + 85 * wb.Data.Wave(es.time, 0.7) or d.health, animated and es.time or nil))
			end,
			tick = function(handle, d, es)
				if d.source == "animated" then
					UF.Units:ShowSample(handle.parts.uf, Values(unit, d, 10 + 85 * wb.Data.Wave(es.time, 0.7), es.time))
				end
			end,
		},
	})
end

for _, unit in ipairs(UF.Units.order) do RegisterUnit(unit) end
