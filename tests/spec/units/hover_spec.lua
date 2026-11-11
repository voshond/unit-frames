local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Mouseover highlight", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		-- Unitless: the tooltip skips, the highlight does not.
		for _, frame in pairs(ns.Units.frames) do frame.__unit = nil end
	end)

	it("is offered on every unit frame and lightens it while the mouse is over it", function()
		for _, unit in ipairs(ns.Units.order) do
			local frame = ns.Units.frames[unit]
			local hover = frame.uf.hover
			assert.is_not_nil(ns.Schema.Find(frame.uf:GetSchema(), "hover.color"), unit)
			assert.is_true(frame.uf.resolved.hover.enabled, unit)
			assert.is_false(hover:IsShown(), unit)
			frame:RunScript("OnEnter")
			assert.is_true(hover:IsShown(), unit)
			assert.same({ 1, 1, 1, 0.12 }, hover.__state.colorTexture)
			frame:RunScript("OnLeave")
			assert.is_false(hover:IsShown(), unit)
		end
	end)

	it("draws above the bars and below the frame border", function()
		local frame = ns.Units.frames.target
		local level = frame.uf.hoverHost:GetFrameLevel()
		assert.equals(frame.uf.hoverHost, frame.uf.hover:GetParent())
		assert.is_true(level > frame.uf:GetRow("health"):GetFrame():GetFrameLevel())
		assert.is_true(level < frame:GetFrameLevel() + ns.Components.Backdrop.LEVELS.frame)
	end)

	it("keeps the hovered state through restyles and follows the settings, also in combat", function()
		local frame = ns.Units.frames.player
		local hover = frame.uf.hover
		frame:RunScript("OnEnter")
		ns.Config:SetUnitValue("player", "hover.color", { 0.2, 0.6, 1, 0.3 })
		assert.is_true(hover:IsShown(), "restyles keep the hovered state")
		assert.same({ 0.2, 0.6, 1, 0.3 }, hover.__state.colorTexture)
		ns.Config:SetUnitValue("player", "hover.enabled", false)
		assert.is_false(hover:IsShown())
		ns.Config:SetUnitValue("player", "hover.enabled", true)
		assert.is_true(hover:IsShown())
		Mock.inCombat = true
		frame:RunScript("OnLeave")
		assert.is_false(hover:IsShown())
		frame:RunScript("OnEnter")
		assert.is_true(hover:IsShown())
		Mock.inCombat = false
	end)

	it("copies with the player style", function()
		ns.Config:SetUnitValue("player", "hover.color", { 1, 0, 0, 0.5 })
		assert.is_true(ns.Units:CopyPlayerSettings("focus"))
		assert.same({ 1, 0, 0, 0.5 }, ns.Units.frames.focus.uf.resolved.hover.color)
	end)

	it("migrates the old flat hover toggle and colour into the group", function()
		assert.same({ hover = { enabled = false, color = { 1, 0, 1, 0.3 } } },
			ns.Units:MigrateConfig({ hover = false, hoverColor = { 1, 0, 1, 0.3 } }))
		assert.same({ hover = { color = { 1, 0, 1, 0.3 } } }, ns.Units:MigrateConfig({ hoverColor = { 1, 0, 1, 0.3 } }))
		assert.same({ hover = { enabled = false } }, ns.Units:MigrateConfig({ hover = { enabled = false } }))
	end)
end)
