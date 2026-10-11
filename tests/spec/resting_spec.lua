local Helpers = require("helpers")
local Mock = Helpers.Mock

local function Border(uf) return uf.border.__state.backdropBorderColor end

describe("Player resting indicators", function()
	local ns, frame, uf, element
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		uf = frame.uf
		element = ns.oUF.elements.UF_Resting
	end)

	it("offers a default-enabled pulse only for the player", function()
		assert.is_true(uf.resolved.resting.enabled)
		assert.is_true(frame:IsElementEnabled("UF_Resting"))
		for _, unit in ipairs(ns.Units.order) do
			if unit ~= "player" then
				local other = ns.Units.frames[unit]
				assert.is_nil(ns.Schema.Find(other.uf:GetSchema(), "resting.enabled"))
				assert.is_false(other:IsElementEnabled("UF_Resting"))
			end
		end
		assert.is_true(ns.Units:CopyPlayerSettings("target"))
		assert.is_nil(ns.Config:GetUnitConfig("target").resting)
	end)

	it("fades to yellow and back over four seconds and restores the current style", function()
		Mock.resting = true
		element.update(frame)
		local original = ns.Util.Copy(uf.resolved.border.color)
		assert.same(original, Border(uf))
		uf.border:RunScript("OnUpdate", 2)
		assert.same(uf.resolved.resting.color, Border(uf))
		uf:Apply()
		assert.same(uf.resolved.resting.color, Border(uf), "apply preserves the pulse phase")
		uf.border:RunScript("OnUpdate", 2)
		assert.same(original, Border(uf))
		ns.Config:SetUnitValue("player", "border.color", { 0.2, 0.3, 0.4, 0.8 })
		Mock.resting = false
		element.update(frame)
		assert.is_nil(uf.border:GetScript("OnUpdate"))
		assert.same({ 0.2, 0.3, 0.4, 0.8 }, Border(uf))
	end)

	it("refreshes via shared events and follows oUF's unit in combat", function()
		local handlers = {}
		frame.RegisterEvent = function(_, event, handler, shared)
			assert.is_true(shared)
			handlers[event] = handler
		end
		frame.UnregisterEvent = function(_, event) handlers[event] = nil end
		Mock.resting = true
		Mock.inCombat = true
		assert.is_true(element.enable(frame))
		assert.is_not_nil(uf.border:GetScript("OnUpdate"))
		assert.is_not_nil(handlers.PLAYER_ENTERING_WORLD)
		frame.__unit = "vehicle"
		handlers.PLAYER_UPDATE_RESTING(frame)
		assert.is_nil(uf.border:GetScript("OnUpdate"))
		frame.__unit = "player"
		handlers.PLAYER_ENTERING_WORLD(frame)
		assert.is_not_nil(uf.border:GetScript("OnUpdate"))
		element.disable(frame)
		assert.is_nil(next(handlers))
		assert.is_nil(uf.border:GetScript("OnUpdate"))
	end)

	it("stops on disabled or missing borders, resumes on toggles, and cleans up on release", function()
		uf:SetResting(true)
		for _, path in ipairs({ "resting.enabled", "border.enabled" }) do
			ns.Config:SetUnitValue("player", path, false)
			assert.is_nil(uf.border:GetScript("OnUpdate"))
			ns.Config:SetUnitValue("player", path, true)
			uf:SetResting(true)
			assert.is_not_nil(uf.border:GetScript("OnUpdate"))
		end
		ns.Config:SetUnitValue("player", "border.border", "None")
		assert.is_nil(uf.border:GetScript("OnUpdate"))
		ns.Config:SetUnitValue("player", "border.border", "UnitFrames Pixel")
		assert.is_not_nil(uf.border:GetScript("OnUpdate"))
		uf:Release()
		assert.is_nil(uf.border:GetScript("OnUpdate"))
	end)

	it("provides a resting text tag that stays empty for other and absent units", function()
		local format = ns.Formats.Get("resting")
		assert.equals("", format.text("player"))
		Mock.resting = true
		assert.equals("zZz", format.text("player"))
		assert.equals("", format.text("target"))
		assert.equals("", format.text(nil))
		UnitExists = function() return false end
		assert.equals("", format.text("player"))
		assert.equals("zZz", format.sample({ resting = true }))
		assert.equals("", format.sample({ resting = false, rested = 30000 }))
		assert.is_true(ns.oUF.Tags.SharedEvents.PLAYER_UPDATE_RESTING)
		for _, list in ipairs({ ns.Formats.HEALTH, ns.Formats.POWER, ns.Formats.EXPERIENCE }) do
			local found = false
			for _, id in ipairs(list) do if id == "resting" then found = true end end
			assert.is_true(found)
		end
	end)
end)

describe("Resting Workbench preview", function()
	it("holds static colour, animates without resetting phase, and releases on entry switching", function()
		local ns, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		wb:Select("unit.player")
		wb.styleTarget.set("health.center.format", "resting")
		wb.styleTarget.set("health.center.enabled", true)
		local uf = wb.handle.parts.uf
		local text = uf:GetRow("health"):GetText("center"):GetFrame()
		wb.dataTarget.set("resting", true)
		assert.equals("zZz", text:GetText())
		assert.same(uf.resolved.resting.color, Border(uf))
		assert.is_nil(uf.border:GetScript("OnUpdate"))
		assert.is_nil(ns.Units.frames.player.uf.border:GetScript("OnUpdate"))
		wb.dataTarget.set("source", "animated")
		uf.border:RunScript("OnUpdate", 2)
		wb:OnUpdate(0.2)
		assert.same(uf.resolved.resting.color, Border(uf))
		uf.border:RunScript("OnUpdate", 2)
		assert.same(uf.resolved.border.color, Border(uf))
		wb.dataTarget.set("resting", false)
		assert.equals("", text:GetText())
		assert.is_nil(uf.border:GetScript("OnUpdate"))
		wb.dataTarget.set("resting", true)
		wb:Select("unit.target")
		assert.is_nil(uf.border:GetScript("OnUpdate"))
		assert.is_false(uf:GetFrame():IsShown())
	end)
end)
