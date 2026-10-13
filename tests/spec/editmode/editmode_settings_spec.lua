local Helpers = require("helpers")

-- Quick settings in Blizzard's Edit Mode dialog are generated from each
-- unit's schema; these expectations pin their labels, bounds and defaults.
describe("Edit Mode quick settings", function()
	local ns, settings
	before_each(function()
		ns = Helpers.LoadAddon(true)
		local lem = LibStub:NewLibrary("LibEditMode", 999)
		lem.SettingType = { Slider = "slider", Checkbox = "checkbox", Dropdown = "dropdown" }
		lem.frameSelections = {}
		settings = {}
		function lem:AddFrame() end
		function lem:RegisterCallback() end
		function lem:AddFrameSettings(frame, list) settings[frame] = list end
		function lem:AddFrameSettingsButtons() end
		assert(loadfile("UnitFrames/Integration/EditMode.lua"))("UnitFrames", ns)
		ns.oUF:RunFactories()
	end)

	local function Plain(list)
		local out = {}
		for i, setting in ipairs(list) do
			out[i] = {}
			for k, v in pairs(setting) do
				if type(v) ~= "function" then out[i][k] = v end
			end
		end
		return out
	end

	it("describes width, rows and optional parts from the unit schema", function()
		local player = Plain(settings[ns.Units.frames.player])
		assert.same({ kind = "slider", name = "Width", default = 230, minValue = 60, maxValue = 600, valueStep = 1 }, player[1])
		assert.same({ kind = "checkbox", name = "Show health", default = true }, player[2])
		assert.same({ kind = "checkbox", name = "Show experience", default = true }, player[4])
		assert.same({ kind = "checkbox", name = "Show portrait", default = true }, player[5])
		assert.same({ kind = "checkbox", name = "Show buffs & debuffs", default = true }, player[6])
		assert.equals("Castbar", player[7].name)
		assert.equals("bottom", player[7].default)
		assert.same({ value = "health", text = "Over the health bar" }, player[7].values[4])
		assert.equals(7, #player)
		local tot = Plain(settings[ns.Units.frames.targettarget])
		assert.same({ kind = "slider", name = "Width", default = 140, minValue = 60, maxValue = 600, valueStep = 1 }, tot[1])
		assert.same({ kind = "checkbox", name = "Show portrait", default = false }, tot[4])
		assert.same({ kind = "checkbox", name = "Show buffs & debuffs", default = false }, tot[5])
		assert.equals("off", tot[6].default)
	end)

	it("reads resolved values and clears a setting that returns to its default", function()
		local width = settings[ns.Units.frames.target][1]
		assert.equals(230, width.get())
		width.set(nil, 260)
		assert.equals(260, ns.Config:GetUnitConfig("target").width)
		assert.equals(260, width.get())
		width.set(nil, 230)
		assert.is_nil(ns.Config:GetUnitConfig("target").width)
	end)
end)
