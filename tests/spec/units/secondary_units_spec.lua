local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Target, focus and their targets", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
	end)

	it("spawns separate oUF frames with health, power, tags and saved positions", function()
		for _, unit in ipairs(ns.Units.order) do
			local frame, def = ns.Units.frames[unit], ns.Units:GetDefinition(unit)
			assert.equals(unit, frame.__unit)
			assert.is_true(frame:IsProtected())
			assert.is_true(frame:IsElementEnabled("Health"))
			assert.is_true(frame:IsElementEnabled("Power"))
			local pos = def.defaultPosition
			assert.same({ pos.point, UIParent, pos.point, pos.x, pos.y }, frame:GetAnchor(pos.point))
			assert.equals(frame, ns.EditMode.frames[unit].frame)
			assert.equals("[uf:name]", frame.tags[frame.uf:GetRow("health"):GetText("left"):GetFrame()])
			if unit ~= "player" then
				assert.is_nil(frame.UF_Experience)
				assert.is_nil(frame.uf:GetRow("experience"))
			end
		end
	end)

	it("starts target and focus full-sized and their targets compact with optional extras", function()
		for _, unit in ipairs({ "target", "focus" }) do
			local frame = ns.Units.frames[unit]
			assert.is_false(frame:IsElementEnabled("UF_Castbar"))
			assert.is_true(frame:IsElementEnabled("UF_Auras"))
		end
		assert.equals("RIGHT", ns.Units.frames.target.uf.resolved.portrait.position)
		for _, unit in ipairs({ "targettarget", "focustarget" }) do
			local frame = ns.Units.frames[unit]
			assert.equals(140, frame:GetWidth())
			assert.equals(37, frame:GetHeight())
			assert.is_false(frame:IsElementEnabled("Portrait"))
			assert.is_false(frame:IsElementEnabled("UF_Castbar"))
			assert.is_false(frame:IsElementEnabled("UF_Auras"))
			assert.equals("[uf:health:percent]", frame.tags[frame.uf:GetRow("health"):GetText("right"):GetFrame()])
			ns.Config:SetUnitValue(unit, "auras.enabled", true)
			ns.Config:SetUnitValue(unit, "castbar.enabled", true)
			ns.Config:SetUnitValue(unit, "portrait.enabled", true)
			assert.is_true(frame:IsElementEnabled("UF_Auras"))
			assert.is_true(frame:IsElementEnabled("UF_Castbar"))
			assert.is_true(frame:IsElementEnabled("Portrait"))
		end
	end)

	it("keeps focus target defaults, settings and positions independent of target of target", function()
		local focusTarget, targetTarget = ns.Units.definitions.focustarget, ns.Units.definitions.targettarget
		focusTarget.rows[1].defaults.height = 30
		focusTarget.castbar.defaults.name.size = 12
		focusTarget.auras.defaults.buffs.size = 24
		assert.equals(20, targetTarget.rows[1].defaults.height)
		assert.equals(9, targetTarget.castbar.defaults.name.size)
		assert.equals(16, targetTarget.auras.defaults.buffs.size)
		ns.Config:SetUnitValue("focustarget", "width", 180)
		assert.equals(180, ns.Units.frames.focustarget.uf.resolved.width)
		assert.equals(140, ns.Units.frames.targettarget.uf.resolved.width)
		assert.equals(200, ns.Units.frames.focus.uf.resolved.width)
		ns.Config:SetPosition("Healer", "focustarget", "TOP", 20, -100)
		ns.EditMode.layout = "Healer"
		ns.EditMode:ApplyPosition("focustarget")
		ns.EditMode:ApplyPosition("targettarget")
		assert.same({ "TOP", UIParent, "TOP", 20, -100 }, ns.Units.frames.focustarget:GetAnchor("TOP"))
		assert.same({ "CENTER", UIParent, "CENTER", 510, -160 }, ns.Units.frames.targettarget:GetAnchor("CENTER"))
	end)

	it("keeps settings, defaults and layout positions independent", function()
		local player, target, focus = ns.Units.frames.player, ns.Units.frames.target, ns.Units.frames.focus
		ns.Config:SetUnitValue("target", "width", 310)
		ns.Config:SetUnitValue("target", "health.height", 40)
		ns.Config:SetUnitValue("focus", "auras.debuffs.position", "right")
		assert.equals(310, target.uf.resolved.width)
		assert.equals(230, player.uf.resolved.width)
		assert.equals(200, focus.uf.resolved.width)
		assert.equals(26, ns.Units:GetDefinition("player").rows[1].defaults.height)
		assert.equals("bottom", target.uf.resolved.auras.debuffs.position)
		assert.equals("right", focus.uf.resolved.auras.debuffs.position)
		ns.Config:SetPosition("Healer", "target", "TOP", 20, -100)
		ns.EditMode.layout = "Healer"
		ns.EditMode:ApplyPosition("target")
		ns.EditMode:ApplyPosition("focus")
		assert.same({ "TOP", UIParent, "TOP", 20, -100 }, target:GetAnchor("TOP"))
		assert.same({ "CENTER", UIParent, "CENTER", -280, -290 }, focus:GetAnchor("CENTER"))
	end)

	-- Each frame keeps its own combo point row (combo_points_spec #copy).
	local KEPT = { comboPoints = true }

	local function AssertCopied(frame, source)
		local function Compare(schema, actual, expected)
			for _, opt in ipairs(schema) do
				if KEPT[opt.key] then
					assert.same(frame.uf.resolved[opt.key], actual[opt.key], opt.key)
				elseif opt.type == "group" then
					Compare(opt.schema, actual[opt.key], expected[opt.key])
				else
					assert.same(expected[opt.key], actual[opt.key], opt.key)
				end
			end
		end
		Compare(frame.uf:GetSchema(), frame.uf.resolved, source)
	end

	it("copies effective player defaults to every secondary frame, not their differing defaults", function()
		local player = ns.Units.frames.player.uf.resolved
		for _, unit in ipairs({ "pet", "target", "targettarget", "focus", "focustarget" }) do
			assert.is_true(ns.Units:CopyPlayerSettings(unit))
			AssertCopied(ns.Units.frames[unit], player)
			assert.is_nil(ns.Config:GetUnitConfig(unit).experience)
			assert.is_nil(ns.Units.frames[unit].uf:GetRow("experience"))
		end
		assert.equals(230, ns.Units.frames.targettarget.uf.resolved.width)
		assert.is_true(ns.Units.frames.targettarget:IsElementEnabled("Portrait"))
		assert.is_false(ns.Units.frames.targettarget:IsElementEnabled("UF_Castbar"))
		assert.is_true(ns.Units.frames.targettarget:IsElementEnabled("UF_Auras"))
	end)

	it("replaces old style overrides with independent player settings without copying positions or XP", function()
		ns.Config:SetUnitValue("player", "width", 310)
		ns.Config:SetUnitValue("player", "health.height", 34)
		ns.Config:SetUnitValue("player", "auras.durationPosition", "CENTER")
		ns.Config:SetUnitValue("player", "auras.dispelColors.Magic", { 0.8, 0.1, 0.7, 1 })
		ns.Config:SetUnitValue("player", "experience.enabled", false)
		ns.Config:SetUnitValue("target", "border.color", { 1, 0, 0, 1 })
		ns.Config:SetUnitValue("target", "auras.buffs.size", 40)
		ns.Config:SetPosition("Healer", "target", "TOP", 30, -100)
		ns.EditMode.layout = "Healer"
		ns.EditMode:ApplyPosition("target")
		local playerConfig = ns.Util.Copy(ns.Config:GetUnitConfig("player"))
		ns.Units:CopyPlayerSettings("target")
		AssertCopied(ns.Units.frames.target, ns.Units.frames.player.uf.resolved)
		assert.same(playerConfig, ns.Config:GetUnitConfig("player"))
		assert.is_nil(ns.Config:GetUnitConfig("target").border)
		assert.is_nil(ns.Config:GetUnitConfig("target").experience)
		assert.same({ "TOP", UIParent, "TOP", 30, -100 }, ns.Units.frames.target:GetAnchor("TOP"))
		ns.Config:SetUnitValue("player", "auras.dispelColors.Magic", { 1, 1, 1, 1 })
		assert.same({ 0.8, 0.1, 0.7, 1 }, ns.Units.frames.target.uf.resolved.auras.dispelColors.Magic)
		ns.Config:SetUnitValue("target", "width", 280)
		assert.equals(310, ns.Units.frames.player.uf.resolved.width)
		assert.equals(200, ns.Units.frames.focus.uf.resolved.width)
	end)

	it("keeps inherited theme settings inherited after copying", function()
		ns.Units:CopyPlayerSettings("focus")
		local config = ns.Config:GetUnitConfig("focus")
		assert.is_nil(config.health and config.health.left and config.health.left.font)
		assert.is_nil(config.border and config.border.color)
		ns.Config:SetThemeValue("font", "Arial Narrow")
		ns.Config:SetThemeValue("borderColor", { 0.1, 0.2, 0.3, 1 })
		AssertCopied(ns.Units.frames.focus, ns.Units.frames.player.uf.resolved)
		assert.equals("Arial Narrow", ns.Units.frames.focus.uf.resolved.health.left.font)
		assert.is_false(ns.Units:CopyPlayerSettings("player"))
		assert.is_false(ns.Units:CopyPlayerSettings("missing"))
	end)

	it("colours NPCs by reaction and tapping, players by class, and disconnected units separately", function()
		local frame = ns.Units.frames.target
		local bar = frame.uf:GetRow("health"):GetBar()
		UnitIsPlayer = function(unit) assert.equals("target", unit); return false end
		for reaction, key in pairs({ [2] = "hostile", [4] = "neutral", [5] = "friendly" }) do
			UnitReaction = function() return reaction end
			frame.Health.UpdateColor(frame, "UNIT_FACTION", "target")
			assert.same(ns.Config:GetTheme().colors[key], bar.bar.__state.color)
		end
		assert.is_true(frame.Health.colorReaction)
		assert.is_true(frame.Health.colorTapping)
		UnitIsTapDenied = function() return true end
		frame.Health.UpdateColor(frame, "UNIT_FACTION", "target")
		assert.same(ns.Config:GetTheme().colors.tapped, bar.bar.__state.color)
		UnitIsPlayer = function() return true end
		UnitClass = function() return "Mage", "MAGE" end
		frame.Health.UpdateColor(frame, "UNIT_FACTION", "target")
		local r, g, b = ns.Colors.Class("MAGE")
		assert.same({ r, g, b, 1 }, bar.bar.__state.color)
		UnitIsConnected = function() return false end
		frame.Health.UpdateColor(frame, "UNIT_CONNECTION", "target")
		assert.same(ns.Config:GetTheme().colors.disconnected, bar.bar.__state.color)
	end)

	it("binds each aura container to its own unit without changing the other frames", function()
		for _, unit in ipairs({ "target", "focus", "targettarget", "focustarget" }) do
			ns.Config:SetUnitValue(unit, "auras.enabled", true)
			local frame = ns.Units.frames[unit]
			ns.oUF.elements.UF_Auras.update(frame, "UnitFramesRefresh")
			for _, kind in ipairs({ "buffs", "debuffs" }) do
				assert.equals(unit, frame.uf:GetPart("auras"):GetContainer(kind):GetUnit())
			end
		end
	end)

	it("refreshes casts on target changes and ignores casts from another unit", function()
		local update = ns.oUF.elements.UF_Castbar.update
		for _, unit in ipairs({ "target", "focus" }) do
			ns.Config:SetUnitValue(unit, "castbar.enabled", true)
			local frame, called = ns.Units.frames[unit], nil
			ns.oUF.elements.UF_Castbar.enable(frame, unit)
			UnitCastingInfo = function(token) called = token; return Mock.Secret("Frostbolt"), nil, Mock.Secret(1) end
			update(frame, "UnitFramesRefresh")
			assert.equals(unit, called)
			assert.is_true(frame.uf:GetPart("castbar"):GetFrame():IsShown())
			called = nil
			update(frame, "UNIT_SPELLCAST_START", "player")
			assert.is_nil(called)
			UnitCastingInfo = function() return nil end
			UnitChannelInfo = function() return nil end
			update(frame, "UnitFramesRefresh")
			assert.is_false(frame.uf:GetPart("castbar"):GetFrame():IsShown())
		end
	end)

	it("renders distinct per-unit samples without changing the shared sample data", function()
		for _, unit in ipairs({ "target", "targettarget", "focus", "focustarget" }) do
			local preview = ns.Units:CreateFrame(unit, CreateFrame("Frame"))
			local sample = ns.Units:GetSample(unit)
			ns.Units:ShowSample(preview, sample)
			assert.equals(sample.name, preview:GetRow("health"):GetText("left"):GetFrame():GetText())
			sample.buffs[1].remaining = 1
			assert.equals(1800, ns.Units:GetSample(unit).buffs[1].remaining)
			preview:Release()
		end
		assert.equals("Uther", ns.Units.SAMPLE.name)
	end)

	it("uses embedded oUF target/focus change events and polling for their targets", function()
		-- Load the actual embedded unit dispatch code, not a copy of its rules.
		ns.oUF.Private = { unitExists = function() return true end }
		function ns.oUF:RegisterMetaFunction(name, fn)
			for _, frame in pairs(ns.Units.frames) do frame[name] = fn end
		end
		assert(loadfile("UnitFrames/Libs/oUF/units.lua"))("oUF", ns)
		for unit, event in pairs({ target = "PLAYER_TARGET_CHANGED", focus = "PLAYER_FOCUS_CHANGED" }) do
			local frame, handlers = ns.Units.frames[unit], {}
			frame.RegisterEvent = function(_, name, handler) handlers[name] = handler end
			ns.oUF:HandleUnit(frame)
			assert.equals(frame.UpdateAllElements, handlers[event])
		end
		for _, unit in ipairs({ "targettarget", "focustarget" }) do
			local frame = ns.Units.frames[unit]
			frame.IsVisible = function() return true end
			ns.oUF:HandleEventlessUnit(frame)
			assert.is_true(frame:IsEventless())
		end
		local timer = Mock.objects[#Mock.objects]
		timer.elapsed = 0
		timer:RunScript("OnUpdate", 0.6)
		for _, unit in ipairs({ "targettarget", "focustarget" }) do
			local frame = ns.Units.frames[unit]
			assert.equals("UpdateAllElements OnUpdate", frame.calls[#frame.calls])
		end
	end)
end)
