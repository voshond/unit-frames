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
		assert.same({ kind = "checkbox", name = "Show experience", default = false }, player[4])
		assert.same({ kind = "checkbox", name = "Show portrait", default = true }, player[5])
		assert.same({ kind = "checkbox", name = "Width includes portrait", default = false }, player[6])
		assert.same({ kind = "checkbox", name = "Show buffs & debuffs", default = true }, player[7])
		assert.same({ kind = "checkbox", name = "Show castbar", default = false }, player[8])
		assert.equals(8, #player)
		local tot = Plain(settings[ns.Units.frames.targettarget])
		assert.same({ kind = "slider", name = "Width", default = 140, minValue = 60, maxValue = 600, valueStep = 1 }, tot[1])
		assert.same({ kind = "checkbox", name = "Show portrait", default = false }, tot[4])
		assert.same({ kind = "checkbox", name = "Width includes portrait", default = false }, tot[5])
		assert.same({ kind = "checkbox", name = "Show buffs & debuffs", default = false }, tot[6])
		assert.same({ kind = "checkbox", name = "Show castbar", default = false }, tot[7])
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

	it("counts the portrait into the frame width from Edit Mode", function()
		local frame = ns.Units.frames.target
		local include = settings[frame][5]
		local before = frame.uf:GetFrame():GetWidth()
		assert.is_true(before > 230)
		include.set(nil, true)
		assert.is_true(ns.Config:GetUnitConfig("target").portrait.includeInWidth)
		assert.is_true(include.get())
		assert.equals(230, frame.uf:GetFrame():GetWidth())
		include.set(nil, false)
		assert.is_nil(ns.Util.GetPath(ns.Config:GetUnitConfig("target"), "portrait.includeInWidth"))
		assert.equals(before, frame.uf:GetFrame():GetWidth())
	end)
end)
