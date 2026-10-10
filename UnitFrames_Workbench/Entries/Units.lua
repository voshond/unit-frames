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
		return {
			schema = handle.schema,
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
local function Values(d, healthPct, time)
	local v = UF.Util.Copy(UF.Units.SAMPLE)
	v.class = d.class
	v.health = v.healthMax * healthPct / 100
	v.absorb = v.healthMax * d.absorb / 100
	v.power = v.powerMax * d.power / 100
	v.xp = v.xpMax * d.xp / 100
	v.showCast = d.showCast
	v.castProgress = d.castProgress / 100
	for _, kind in ipairs({ "buffs", "debuffs" }) do
		local samples = UF.Units.SAMPLE[kind]
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

Workbench:Register({
	id = "unit.player",
	category = "Unit frames",
	name = "Player",
	autoSize = true,
	size = { 230, 60 },
	create = function(stage)
		return UnitHandle(stage, "player")
	end,
	styleTarget = UnitStyleTarget("player"),
	reset = function()
		wipe(UF.Config:GetUnitConfig("player"))
		UF.Events:Fire("UnitConfigChanged", "player")
	end,
	data = {
		schema = {
			{ key = "source", type = "select", label = "Source", default = "static", values = {
				{ "static", "Static (sliders)" },
				{ "animated", "Animated" },
			} },
			Range("health", "Health %", 65),
			Range("absorb", "Absorb shields %", 15),
			Range("power", "Power %", 70),
			Range("xp", "XP %", 42),
			{ key = "class", type = "select", label = "Class", values = wb.Data.Classes, default = "PALADIN" },
			{ key = "showCast", type = "toggle", label = "Show a cast", default = true,
				tooltip = "Sample cast on the castbar. Turn off to see the health bar under a castbar placed over it." },
			Range("castProgress", "Cast progress %", 60),
			{ key = "buffsCount", type = "range", label = "Sample buffs", min = 0, max = 40, step = 1, default = 8,
				tooltip = "The Buffs style's filter and Maximum shown still apply." },
			{ key = "debuffsCount", type = "range", label = "Sample debuffs", min = 0, max = 40, step = 1, default = 5,
				tooltip = "The Debuffs style's filter and Maximum shown still apply." },
		},
		update = function(handle, d, es)
			local animated = d.source == "animated"
			UF.Units:ShowSample(handle.parts.uf, Values(d,
				animated and 10 + 85 * wb.Data.Wave(es.time, 0.7) or d.health, animated and es.time or nil))
		end,
		tick = function(handle, d, es)
			if d.source == "animated" then
				UF.Units:ShowSample(handle.parts.uf, Values(d, 10 + 85 * wb.Data.Wave(es.time, 0.7), es.time))
			end
		end,
	},
})
