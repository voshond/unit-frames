local Helpers = require("helpers")
local Mock = Helpers.Mock

-- Spawns the frames with the player as `class` (UnitClass after InstallUI
-- returns secrets otherwise).
local function LoadAs(class)
	local ns = Helpers.LoadAddon(true)
	Mock.InstallUI()
	UnitClass = function() return class, class, 1 end
	ns.oUF:RunFactories()
	return ns
end

local function Keys(uf)
	local keys = {}
	for _, item in ipairs(uf.layout.rows) do keys[#keys + 1] = item.key end
	return keys
end

local function Watch(frame, handlers)
	frame.RegisterEvent = function(_, event, handler, unitless)
		handlers[event] = { handler = handler, unitless = unitless }
	end
	frame.UnregisterEvent = function(_, event) handlers[event] = nil end
end

local function Fill(points)
	local values = {}
	for i = 1, points:GetMax() do values[i] = points.points[i].bar:GetValue() end
	return values
end

describe("Combo points", function()
	local ns, frame, uf, points, handlers
	before_each(function()
		ns = LoadAs("ROGUE")
		frame = ns.Units.frames.target
		uf = frame.uf
		points = uf:GetPart("comboPoints")
		handlers = {}
		Watch(frame, handlers)
		UnitPowerMax = function(unit, powerType)
			assert.equals("player", unit)
			assert.equals(Enum.PowerType.ComboPoints, powerType)
			return 5
		end
	end)

	it("is a target row below the power bar by default and an opt-in player row", function()
		assert.equals(points, frame.UF_ComboPoints)
		assert.is_true(frame:IsElementEnabled("UF_ComboPoints"))
		assert.same({ "health", "power", "comboPoints" }, Keys(uf))
		local player = ns.Units.frames.player
		assert.is_false(player.uf:GetPart("comboPoints"):IsEnabled())
		assert.is_false(player:IsElementEnabled("UF_ComboPoints"))
		assert.same({ "health", "power" }, Keys(player.uf))
		ns.Config:SetUnitValue("player", "comboPoints.enabled", true)
		assert.is_true(player:IsElementEnabled("UF_ComboPoints"))
		assert.same({ "health", "power", "comboPoints" }, Keys(player.uf))
		for _, unit in ipairs({ "pet", "targettarget", "focus", "focustarget" }) do
			assert.is_nil(ns.Units.frames[unit].uf:GetPart("comboPoints"), unit)
			assert.is_nil(ns.Schema.Find(ns.Units.frames[unit].uf:GetSchema(), "comboPoints"), unit)
		end
	end)

	it("keeps each frame's own combo point settings when copying player settings #copy", function()
		ns.Config:SetUnitValue("target", "comboPoints.height", 10)
		ns.Config:SetUnitValue("player", "comboPoints.spacing", 6)
		ns.Config:SetUnitValue("player", "health.height", 30)
		ns.Units:CopyPlayerSettings("target")
		assert.equals(30, uf.resolved.health.height)
		assert.is_true(uf.resolved.comboPoints.enabled, "the player's opt-in row stays off only there")
		assert.equals(10, uf.resolved.comboPoints.height)
		assert.equals(2, uf.resolved.comboPoints.spacing)
		assert.is_true(frame:IsElementEnabled("UF_ComboPoints"))
	end)

	it("moves to the top or bottom and follows the power row even when that is off", function()
		local height = uf:GetFrame():GetHeight()
		ns.Config:SetUnitValue("target", "comboPoints.position", "top")
		assert.same({ "comboPoints", "health", "power" }, Keys(uf))
		ns.Config:SetUnitValue("target", "comboPoints.position", "bottom")
		assert.same({ "health", "power", "comboPoints" }, Keys(uf))
		ns.Config:SetUnitValue("target", "comboPoints.position", "power")
		ns.Config:SetUnitValue("target", "power.enabled", false)
		assert.same({ "health", "comboPoints" }, Keys(uf))
		ns.Config:SetUnitValue("target", "power.enabled", true)
		ns.Config:SetUnitValue("target", "comboPoints.height", 12)
		assert.equals(height + 4, uf:GetFrame():GetHeight())
		ns.Config:SetUnitValue("target", "comboPoints.enabled", false)
		assert.equals(height - 8 - 1, uf:GetFrame():GetHeight(), "the row and its spacing collapse")
		assert.is_false(frame:IsElementEnabled("UF_ComboPoints"))
		assert.is_false(points:GetFrame():IsShown())
		ns.Config:SetUnitValue("target", "comboPoints.enabled", true)
		assert.is_true(frame:IsElementEnabled("UF_ComboPoints"))
		assert.is_true(points:GetFrame():IsShown())
	end)

	it("spreads the maximum number of points across the row", function()
		local bar = ns.Components.PointBar:New(UIParent, {})
		bar:Layout(100)
		bar:SetMax(5)
		-- (100 - 4 gaps of 2) / 5 = 18.4 wide.
		for i = 1, 5 do
			local holder = bar.points[i].holder
			assert.is_true(holder:IsShown(), i)
			assert.equals(18.4, holder:GetWidth())
			assert.same({ "TOPLEFT", bar:GetFrame(), "TOPLEFT", (i - 1) * 20.4, 0 }, holder:GetAnchor("TOPLEFT"))
			assert.same({ "BOTTOMLEFT", bar:GetFrame(), "BOTTOMLEFT", (i - 1) * 20.4, 0 }, holder:GetAnchor("BOTTOMLEFT"))
			assert.same({ i - 1, i }, { bar.points[i].bar:GetMinMaxValues() })
		end
		assert.is_false(bar.points[6].holder:IsShown())
		bar:Apply({ spacing = 0 })
		assert.equals(20, bar.points[1].holder:GetWidth())
		bar:SetMax(3)
		assert.is_false(bar.points[4].holder:IsShown())
		assert.equals(100 / 3, bar.points[3].holder:GetWidth())
		bar:SetMax(12)
		assert.equals(ns.Components.PointBar.MAX_POINTS, bar:GetMax())
		-- The live row spans the frame between its border padding and the portrait.
		local item
		for _, row in ipairs(uf.layout.rows) do if row.key == "comboPoints" then item = row end end
		assert.equals(uf.layout.width - item.left - item.right, points.width)
	end)

	it("reads the points on the target, also after target changes, and passes secrets through", function()
		local element = ns.oUF.elements.UF_ComboPoints
		assert.is_nil(element.enable(frame, "focus"), "target and player frames only")
		assert.is_true(element.enable(frame, "target"))
		-- The power events are the player's, not the target frame's unit.
		for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_POWER_POINT_CHARGE", "UNIT_MAXPOWER",
			"PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED", "PLAYER_ENTERING_WORLD" }) do
			assert.is_true(handlers[event].unitless, event)
		end
		local asked
		GetComboPoints = function(unit, target)
			asked = { unit, target }
			return Secret(Mock.comboPoints)
		end
		Mock.comboPoints = 3
		handlers.UNIT_POWER_UPDATE.handler(frame, "UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
		assert.same({ "player", "target" }, asked)
		assert.equals(5, points:GetMax())
		for i, value in ipairs(Fill(points)) do
			assert.is_true(issecretvalue(value), "every point gets the secret count")
			assert.equals(3, value.secretValue, i)
		end
		Mock.comboPoints = 0
		handlers.UNIT_POWER_UPDATE.handler(frame, "UNIT_POWER_UPDATE", "target", "COMBO_POINTS")
		assert.equals(3, Fill(points)[1].secretValue, "the target's own power is not combo points")
		handlers.UNIT_POWER_FREQUENT.handler(frame, "UNIT_POWER_FREQUENT", "player", "ENERGY")
		assert.equals(3, Fill(points)[1].secretValue, "energy ticks are skipped")
		handlers.UNIT_POWER_FREQUENT.handler(frame, "UNIT_POWER_FREQUENT", "player", Secret("COMBO_POINTS"))
		assert.equals(0, Fill(points)[1].secretValue, "an opaque power type still updates")
		Mock.comboPoints = 4
		handlers.PLAYER_TARGET_CHANGED.handler(frame, "PLAYER_TARGET_CHANGED")
		assert.equals(4, Fill(points)[1].secretValue)
		Mock.comboPoints = 2
		handlers.COMBO_TARGET_CHANGED.handler(frame, "COMBO_TARGET_CHANGED")
		assert.equals(2, Fill(points)[1].secretValue)
		UnitPowerMax = function() return 6 end
		handlers.UNIT_MAXPOWER.handler(frame, "UNIT_MAXPOWER", "player", "COMBO_POINTS")
		assert.equals(6, points:GetMax())
		UnitPowerMax = function() return Secret(6) end
		element.update(frame, "UnitFramesRefresh")
		assert.equals(5, points:GetMax(), "an opaque maximum falls back to five")
		element.disable(frame)
		assert.same({}, handlers)
		assert.equals(0, Fill(points)[1])
		-- A player frame row shows the points on the current target.
		ns.Config:SetUnitValue("player", "comboPoints.enabled", true)
		local player = ns.Units.frames.player
		local playerHandlers = {}
		Watch(player, playerHandlers)
		asked = nil
		assert.is_true(element.enable(player, "player"))
		playerHandlers.PLAYER_TARGET_CHANGED.handler(player, "PLAYER_TARGET_CHANGED")
		assert.same({ "player", "target" }, asked)
		assert.equals(2, Fill(player.uf:GetPart("comboPoints"))[1].secretValue)
	end)

	it("takes no space and binds nothing for classes without combo points", function()
		ns = LoadAs("WARRIOR")
		local target = ns.Units.frames.target
		assert.same({ "health", "power" }, Keys(target.uf))
		assert.is_false(target.uf:GetPart("comboPoints"):IsEnabled())
		assert.is_false(target:IsElementEnabled("UF_ComboPoints"))
		assert.is_not_nil(ns.Schema.Find(target.uf:GetSchema(), "comboPoints.position"), "settings stay available")
		ns.Config:SetUnitValue("target", "comboPoints.position", "top")
		ns.Config:SetUnitValue("player", "comboPoints.enabled", true)
		assert.is_false(target:IsElementEnabled("UF_ComboPoints"))
		assert.is_false(ns.Units.frames.player:IsElementEnabled("UF_ComboPoints"))
	end)

	it("restyles its points and empties them on release", function()
		ns.Config:SetUnitValue("target", "comboPoints.color", { 1, 0, 0, 1 })
		ns.Config:SetUnitValue("target", "comboPoints.border.enabled", true)
		local point = points.points[1]
		assert.same({ 1, 0, 0, 1 }, point.bar.__state.color)
		assert.same({ "TOPLEFT", point.holder, "TOPLEFT", 1, -1 }, point.bar:GetAnchor("TOPLEFT"))
		ns.Config:SetUnitValue("target", "comboPoints.background.useBarColor", false)
		ns.Config:SetUnitValue("target", "comboPoints.background.enabled", false)
		assert.is_false(point.bg:IsShown())
		local preview = ns.Units:CreateFrame("target", UIParent)
		local previewPoints = preview:GetPart("comboPoints")
		previewPoints:Preview(4, 5)
		preview:Release()
		assert.equals(0, previewPoints:GetMax())
		assert.is_false(previewPoints:GetFrame():IsShown())
	end)
end)

describe("Combo point Workbench previews", function()
	local function Tick(workbench, seconds)
		for _ = 1, math.floor(seconds / 0.1 + 0.5) do
			Mock.time = Mock.time + 0.1
			workbench:OnUpdate(0.1)
		end
	end

	it("shows the sample count, holds it when static and counts up when animated", function()
		local _, wb = Helpers.LoadWorkbench()
		UnitClass = function() return "Druid", "DRUID", 11 end
		wb:Toggle()
		wb:Select("unit.player")
		assert.is_false(wb.handle.parts.uf:GetPart("comboPoints"):IsEnabled(), "opt-in on the player")
		wb:Select("unit.target")
		local uf = wb.handle.parts.uf
		local points = uf:GetPart("comboPoints")
		assert.is_true(points:IsEnabled())
		assert.equals(5, points:GetMax())
		assert.equals(3, points.points[1].bar:GetValue())
		local opt = UnitFrames.Schema.Find(wb.dataTarget.schema, "comboPoints")
		assert.is_false(opt.hidden())
		wb.dataTarget.set("comboPoints", 5)
		assert.equals(5, points.points[1].bar:GetValue())
		Tick(wb, 1)
		assert.equals(5, points.points[1].bar:GetValue(), "static holds the count")
		wb.dataTarget.set("source", "animated")
		-- Sample mid-second: one more point per whole second.
		Tick(wb, 0.5)
		local seen = { [points.points[1].bar:GetValue()] = true }
		for _ = 1, 6 do
			Tick(wb, 1)
			seen[points.points[1].bar:GetValue()] = true
		end
		for count = 0, 5 do assert.is_true(seen[count], count) end
	end)

	it("hides the sample control and the row for other classes", function()
		local _, wb = Helpers.LoadWorkbench()
		UnitClass = function() return "Warrior", "WARRIOR", 1 end
		wb:Toggle()
		wb:Select("unit.target")
		local uf = wb.handle.parts.uf
		assert.is_false(uf:GetPart("comboPoints"):IsEnabled())
		for _, item in ipairs(uf.layout.rows) do assert.is_true(item.key ~= "comboPoints") end
		assert.is_true(UnitFrames.Schema.Find(wb.dataTarget.schema, "comboPoints").hidden())
	end)
end)
