local Helpers = require("helpers")
local Mock = Helpers.Mock

-- Mock-only engine oracle: production Lua must never read a secret alpha.
local function Alpha(frame)
	local alpha = frame:GetAlpha()
	if Mock.IsSecret(alpha) then return alpha.secretValue end
	return alpha
end

describe("Out-of-range opacity", function()
	local ns, frame, element
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.target
		element = ns.oUF.elements.UF_Range
	end)

	it("offers per-unit, opt-in settings and copies them independently", function()
		for _, unit in ipairs(ns.Units.order) do
			local live = ns.Units.frames[unit]
			assert.is_not_nil(ns.Schema.Find(live.uf:GetSchema(), "range.outsideAlpha"))
			assert.is_false(live.uf.resolved.range.enabled)
			assert.is_false(live:IsElementEnabled("UF_Range"))
			assert.equals(1, Alpha(live))
		end
		ns.Config:SetUnitValue("player", "range.enabled", true)
		ns.Config:SetUnitValue("player", "range.outsideAlpha", 0.3)
		ns.Config:SetUnitValue("player", "range.mode", "spell")
		ns.Config:SetUnitValue("player", "range.spell", "133")
		assert.is_true(ns.Units:CopyPlayerSettings("target"))
		assert.same(ns.Units.frames.player.uf.resolved.range, frame.uf.resolved.range)
		assert.equals(frame.uf, frame.UF_Range)
		assert.is_true(frame:IsElementEnabled("UF_Range"))
		ns.Config:SetUnitValue("player", "range.outsideAlpha", 0.7)
		assert.equals(0.3, frame.uf.resolved.range.outsideAlpha)
		assert.same({}, ns.Schema.Validate(frame.uf:GetSchema(), ns.Config:GetUnitConfig("target")))
	end)

	it("selects opacity natively for every secret range/checked combination, even in combat", function()
		ns.Config:SetUnitValue("target", "range.enabled", true)
		Mock.inCombat = true
		for _, inside in ipairs({ false, true }) do
			for _, checked in ipairs({ false, true }) do
				Mock.ranges.target = { inRange = Mock.Secret(inside), checked = Mock.Secret(checked) }
				element.update(frame, "UNIT_IN_RANGE_UPDATE", "target", Mock.Secret(inside))
				assert.equals(checked and not inside and 0.55 or 1, Alpha(frame))
				assert.is_true(Mock.IsSecret(frame:GetAlpha()), "native alpha must retain secrecy")
				local calls, native = frame.__calls, 0
				for _, call in ipairs(calls) do
					if call[1] == "SetAlphaFromBoolean" then native = native + 1 end
				end
				assert.is_true(native >= 2)
			end
		end
	end)

	it("reapplies the chosen opacity and restores normal opacity when disabled", function()
		ns.Config:SetUnitValue("target", "range.enabled", true)
		frame.uf:SetRangeState(Mock.Secret(false), Mock.Secret(true))
		for _, alpha in ipairs({ 0, 0.3, 1 }) do
			ns.Config:SetUnitValue("target", "range.outsideAlpha", alpha)
			assert.equals(alpha, Alpha(frame))
			frame.uf:Apply()
			assert.equals(alpha, Alpha(frame), "repeat application is safe")
		end
		ns.Config:SetUnitValue("target", "range.enabled", false)
		assert.equals(1, Alpha(frame))
		assert.is_false(frame:IsElementEnabled("UF_Range"))
		assert.is_nil(frame.UF_Range)
		frame.uf:SetRangeState(Mock.Secret(false), Mock.Secret(true))
		assert.equals(1, Alpha(frame), "disabled opacity ignores later data")
	end)

	it("follows the current oUF unit and resets for unavailable or disconnected units", function()
		ns.Config:SetUnitValue("target", "range.enabled", true)
		Mock.ranges.target = { inRange = false, checked = true }
		element.update(frame)
		assert.equals(0.55, Alpha(frame))
		frame.__unit = "focus"
		Mock.ranges.focus = { inRange = true, checked = true }
		element.update(frame)
		assert.equals(1, Alpha(frame))
		Mock.ranges.focus = { inRange = false, checked = true }
		element.update(frame)
		assert.equals(0.55, Alpha(frame))
		UnitExists = function() return false end
		element.update(frame)
		assert.equals(1, Alpha(frame))
		UnitExists = function() return true end
		UnitIsConnected = function() return false end
		element.update(frame)
		assert.equals(1, Alpha(frame))
		frame.__unit = nil
		assert.has_no_error(function() element.update(frame) end)
		assert.equals(1, Alpha(frame))
	end)

	it("passes spell results through native rendering and preserves unknown checks", function()
		ns.Config:SetUnitValue("target", "range.enabled", true)
		ns.Config:SetUnitValue("target", "range.mode", "spell")
		ns.Config:SetUnitValue("target", "range.spell", " 133 ")
		Mock.inCombat = true
		for _, inside in ipairs({ false, true, Mock.Secret(false), Mock.Secret(true) }) do
			Mock.spellRanges[133] = { target = inside }
			element.update(frame)
			local value = inside
			if Mock.IsSecret(inside) then value = inside.secretValue end
			assert.equals(value and 1 or 0.55, Alpha(frame))
		end
		Mock.spellRanges[133] = {}
		element.update(frame)
		assert.equals(1, Alpha(frame), "nil isn't treated as out of range")
		ns.Config:SetUnitValue("target", "range.spell", "Fireball")
		Mock.spellRanges.Fireball = { target = false }
		element.update(frame)
		assert.equals(0.55, Alpha(frame))
		ns.Config:SetUnitValue("target", "range.spell", "   ")
		element.update(frame)
		assert.equals(1, Alpha(frame), "blank spell isn't queried")
	end)

	it("uses events for group mode and stops spell polling on disable or mode changes", function()
		local handlers = {}
		frame.RegisterEvent = function(_, event, handler, shared)
			handlers[event] = handler
			assert.equals(event == "GROUP_ROSTER_UPDATE" and true or nil, shared)
		end
		frame.UnregisterEvent = function(_, event) handlers[event] = nil end
		local driver
		-- The shared, parentless polling frame (castbar fades also have OnUpdate).
		for _, obj in ipairs(Mock.objects) do
			if obj.__type == "Frame" and not obj:GetParent() and obj:GetScript("OnUpdate") then driver = obj end
		end
		assert.is_not_nil(driver)
		assert.is_false(driver:IsShown())
		ns.Config:SetUnitValue("target", "range.enabled", true)
		Mock.ranges.target = { inRange = false, checked = true }
		assert.is_true(element.enable(frame))
		assert.equals(0.55, Alpha(frame), "enable immediately checks current unit")
		assert.is_false(driver:IsShown(), "group checks do not poll")
		assert.is_not_nil(handlers.UNIT_IN_RANGE_UPDATE)
		Mock.ranges.target.inRange = true
		handlers.UNIT_IN_RANGE_UPDATE(frame)
		assert.equals(1, Alpha(frame))
		element.disable(frame)
		assert.is_nil(next(handlers))
		ns.Config:SetUnitValue("target", "range.mode", "spell")
		ns.Config:SetUnitValue("target", "range.spell", "133")
		Mock.spellRanges[133] = { target = false }
		element.enable(frame)
		assert.is_true(driver:IsShown())
		assert.is_nil(handlers.UNIT_IN_RANGE_UPDATE)
		assert.equals(0.55, Alpha(frame))
		Mock.spellRanges[133].target = true
		driver:RunScript("OnUpdate", 0.1)
		assert.equals(0.55, Alpha(frame))
		driver:RunScript("OnUpdate", 0.1)
		assert.equals(1, Alpha(frame))
		frame:Hide()
		Mock.spellRanges[133].target = false
		driver:RunScript("OnUpdate", 0.2)
		assert.equals(1, Alpha(frame), "hidden frames are skipped")
		frame:Show()
		driver:RunScript("OnUpdate", 0.2)
		assert.equals(0.55, Alpha(frame))
		frame.__unit = "focus"
		Mock.spellRanges[133].focus = true
		driver:RunScript("OnUpdate", 0.2)
		assert.equals(1, Alpha(frame), "polling follows oUF's unit")
		element.disable(frame)
		assert.is_false(driver:IsShown())
		assert.is_nil(next(handlers))
		assert.equals(1, Alpha(frame))
		ns.Config:SetUnitValue("target", "range.mode", "group")
		element.enable(frame)
		assert.is_false(driver:IsShown())
		assert.is_not_nil(handlers.UNIT_IN_RANGE_UPDATE)
		element.disable(frame)
	end)

	it("rebinds the oUF element when switching modes and supports unavailable APIs", function()
		ns.Config:SetUnitValue("target", "range.enabled", true)
		frame.calls = {}
		ns.Config:SetUnitValue("target", "range.mode", "spell")
		assert.equals("disable UF_Range", frame.calls[1])
		assert.equals("enable UF_Range", frame.calls[2])
		ns.Caps.spellRange = false
		ns.Config:SetUnitValue("target", "range.spell", "133")
		C_Spell.IsSpellInRange = function() error("unsupported API used") end
		element.update(frame)
		assert.equals(1, Alpha(frame))
		ns.Caps.groupRange = false
		ns.Config:SetUnitValue("target", "range.mode", "group")
		UnitInRange = function() error("unsupported API used") end
		element.update(frame)
		assert.equals(1, Alpha(frame))
		ns.Caps.booleanAlpha = false
		frame.SetAlphaFromBoolean = function() error("unsupported method used") end
		ns.Units:Refresh("target")
		assert.is_false(frame:IsElementEnabled("UF_Range"))
		assert.equals(1, Alpha(frame))
	end)
end)

describe("Range Workbench previews", function()
	it("lets both sample sources tune the saved fade without changing live range data", function()
		local ns, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		for _, unit in ipairs(ns.Units.order) do
			wb:Select("unit." .. unit)
			local preview = wb.handle.parts.uf:GetFrame()
			wb.styleTarget.set("range.enabled", true)
			wb.styleTarget.set("range.outsideAlpha", 0.3)
			assert.equals(1, Alpha(preview))
			wb.dataTarget.set("outOfRange", true)
			assert.equals(0.3, Alpha(preview))
			assert.equals(1, Alpha(ns.Units.frames[unit]), "preview doesn't feed live range state")
			wb.dataTarget.set("source", "animated")
			wb:OnUpdate(0.3)
			assert.equals(0.3, Alpha(preview))
			wb.styleTarget.set("range.outsideAlpha", 0)
			assert.equals(0, Alpha(preview))
			wb.dataTarget.set("outOfRange", false)
			assert.equals(1, Alpha(preview))
			wb.dataTarget.set("outOfRange", true)
			wb.styleTarget.set("range.enabled", false)
			assert.equals(1, Alpha(preview))
			wb:SelectSection("range")
			assert.is_false(wb.inspector.page.rows[4].region:IsShown(), "spell entry is hidden for group mode")
			wb.styleTarget.set("range.mode", "spell")
			wb.inspector:Refresh()
			assert.is_true(wb.inspector.page.rows[4].region:IsShown())
		end
		local old = wb.handle.parts.uf
		wb:Select("bar.health")
		assert.is_false(old:GetFrame():IsShown(), "switching entries releases the preview")
	end)
end)
