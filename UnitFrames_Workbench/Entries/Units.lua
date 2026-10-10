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
local function Values(d, healthPct)
	local v = UF.Util.Copy(UF.Units.SAMPLE)
	v.class = d.class
	v.health = v.healthMax * healthPct / 100
	v.absorb = v.healthMax * d.absorb / 100
	v.power = v.powerMax * d.power / 100
	v.xp = v.xpMax * d.xp / 100
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
		},
		update = function(handle, d)
			if d.source == "static" then
				UF.Units:ShowSample(handle.parts.uf, Values(d, d.health))
			end
		end,
		tick = function(handle, d, es)
			if d.source == "animated" then
				UF.Units:ShowSample(handle.parts.uf, Values(d, 10 + 85 * wb.Data.Wave(es.time, 0.7)))
			end
		end,
	},
})
