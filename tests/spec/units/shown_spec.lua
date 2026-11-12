local Helpers = require("helpers")
local Mock = Helpers.Mock

local function Watched(frame)
	return frame:IsEnabled() and true or false
end

describe("Show frame", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
	end)

	after_each(function()
		Mock.inCombat = false
	end)

	it("is offered on every unit's layout page and on by default", function()
		for _, unit in ipairs(ns.Units.order) do
			local opt = ns.Schema.Find(ns.Units:GetSchema(unit), "shown")
			assert.equals("toggle", opt.type, unit)
			assert.is_true(opt.default, unit)
			assert.is_true(Watched(ns.Units.frames[unit]), unit)
		end
	end)

	it("drops the unit watch when switched off and restores it when switched on", function()
		local frame = ns.Units.frames.pet
		ns.Config:SetUnitValue("pet", "shown", false)
		assert.is_false(Watched(frame))
		assert.is_false(frame:IsShown())
		assert.is_true(Watched(ns.Units.frames.player))

		ns.Config:SetUnitValue("pet", "shown", nil)
		assert.is_true(Watched(frame))
	end)

	it("waits for combat to end", function()
		local frame = ns.Units.frames.focus
		Mock.inCombat = true
		ns.Config:SetUnitValue("focus", "shown", false)
		assert.is_true(Watched(frame))

		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_false(Watched(frame))
	end)

	it("keeps each frame's own visibility when copying the player style", function()
		ns.Config:SetUnitValue("player", "shown", false)
		ns.Config:SetUnitValue("target", "shown", false)
		ns.Units:CopyPlayerSettings("focus")
		assert.is_nil(ns.Config:GetUnitConfig("focus").shown)
		assert.is_true(Watched(ns.Units.frames.focus))
		ns.Units:CopyPlayerSettings("target")
		assert.is_false(ns.Config:GetUnitConfig("target").shown)
	end)
end)
