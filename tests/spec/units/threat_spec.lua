local Helpers = require("helpers")
local Mock = Helpers.Mock

local function GlowColor(uf) return uf.threatGlow.textures[1].__state.vertexColor end

-- The theme's colour of a threat stage, opaque or transparent.
local function Stage(ns, key, alpha)
	local r, g, b = ns.Colors.Theme(key)
	return { r, g, b, alpha or 1 }
end

local function Threat(status, percent)
	return function() return status == 3, status, percent, percent, 1000 end
end

describe("Threat glow #threat", function()
	local ns, frame, uf, element
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.target
		uf = frame.uf
		element = ns.oUF.elements.UF_Threat
	end)

	it("is on for target and focus, offered off for their targets and absent elsewhere", function()
		for _, unit in ipairs({ "target", "focus" }) do
			local resolved = ns.Units.frames[unit].uf.resolved.threat
			assert.is_true(resolved.enabled, unit)
			assert.equals("percent", resolved.colorBy, unit)
			assert.equals("medium", resolved.showFrom, unit)
			assert.equals("soft", resolved.corners, unit)
			assert.is_true(ns.Units.frames[unit]:IsElementEnabled("UF_Threat"), unit)
		end
		for _, unit in ipairs({ "targettarget", "focustarget" }) do
			assert.is_false(ns.Units.frames[unit].uf.resolved.threat.enabled, unit)
			assert.is_false(ns.Units.frames[unit]:IsElementEnabled("UF_Threat"), unit)
		end
		for _, unit in ipairs({ "player", "pet" }) do
			assert.is_nil(ns.Schema.Find(ns.Units.frames[unit].uf:GetSchema(), "threat.enabled"), unit)
			assert.is_nil(ns.Units.frames[unit].uf.threatGlow, unit)
		end
	end)

	it("colours the player's threat % by stage from the chosen stage on", function()
		local asked
		UnitDetailedThreatSituation = function(unit, mob)
			asked = { unit, mob }
			return false, 0, 30, 30, 100
		end
		element.update(frame)
		assert.same({ "player", "target" }, asked)
		assert.is_true(uf.threatGlow:IsShown())
		assert.same(Stage(ns, "threatLow", 0), GlowColor(uf), "low stays hidden from medium")
		for _, case in ipairs({ { 50, "threatMedium" }, { 79.9, "threatMedium" }, { 80, "threatHigh" }, { 100, "threatAggro" } }) do
			UnitDetailedThreatSituation = Threat(0, case[1])
			element.update(frame)
			assert.same(Stage(ns, case[2]), GlowColor(uf), tostring(case[1]))
		end
		ns.Config:SetUnitValue("target", "threat.showFrom", "low")
		UnitDetailedThreatSituation = Threat(0, 30)
		element.update(frame)
		assert.same(Stage(ns, "threatLow"), GlowColor(uf))
		ns.Config:SetUnitValue("target", "threat.showFrom", "aggro")
		assert.same(Stage(ns, "threatLow", 0), GlowColor(uf), "re-applies the stored threat")
	end)

	it("colours by threat status on request", function()
		ns.Config:SetUnitValue("target", "threat.colorBy", "status")
		for status, key in pairs({ [1] = "threatMedium", [2] = "threatHigh", [3] = "threatAggro" }) do
			UnitDetailedThreatSituation = Threat(status, 10)
			element.update(frame)
			assert.same(Stage(ns, key), GlowColor(uf), tostring(status))
		end
		UnitDetailedThreatSituation = Threat(0, 99)
		element.update(frame)
		assert.equals(0, GlowColor(uf)[4])
	end)

	it("stays transparent off the threat list, also from the first stage, and skips absent units", function()
		ns.Config:SetUnitValue("target", "threat.showFrom", "low")
		UnitDetailedThreatSituation = function() end
		element.update(frame)
		assert.is_true(uf.threatGlow:IsShown(), "transparent, not hidden")
		assert.same({ 0, 0, 0, 0 }, GlowColor(uf))
		UnitExists = function() return false end
		UnitDetailedThreatSituation = function() error("absent units are not asked") end
		assert.has_no_error(function() element.update(frame) end)
	end)

	it("passes secret threat values to the curve without testing them", function()
		Mock.inCombat = true
		for _, by in ipairs({ "percent", "status" }) do
			ns.Config:SetUnitValue("target", "threat.colorBy", by)
			UnitDetailedThreatSituation = function()
				return Mock.Secret(true), Mock.Secret(2), Mock.Secret(90), Mock.Secret(110), Mock.Secret(5000)
			end
			assert.has_no_error(function() element.update(frame) end)
			assert.is_true(uf.threatGlow:IsShown())
			assert.is_true(Mock.IsSecret(GlowColor(uf)[1]), by)
		end
	end)

	it("follows theme colour changes", function()
		UnitDetailedThreatSituation = Threat(3, 100)
		element.update(frame)
		ns.Config:SetThemeValue("colors.threatAggro", { 0.5, 0, 1, 1 })
		uf:Apply()
		assert.same({ 0.5, 0, 1, 1 }, GlowColor(uf))
	end)

	it("registers both threat events unit-less and resets on disable", function()
		local handlers = {}
		frame.RegisterEvent = function(_, event, handler, shared)
			assert.is_true(shared, event)
			handlers[event] = handler
		end
		frame.UnregisterEvent = function(_, event) handlers[event] = nil end
		UnitDetailedThreatSituation = Threat(3, 100)
		assert.is_true(element.enable(frame))
		assert.is_not_nil(handlers.UNIT_THREAT_SITUATION_UPDATE)
		assert.is_not_nil(handlers.UNIT_THREAT_LIST_UPDATE)
		handlers.UNIT_THREAT_SITUATION_UPDATE(frame, "UNIT_THREAT_SITUATION_UPDATE", "player")
		assert.same(Stage(ns, "threatAggro"), GlowColor(uf))
		element.disable(frame)
		assert.is_nil(next(handlers))
		assert.equals(0, GlowColor(uf)[4])
	end)

	it("applies size, opacity and corners and follows toggles in any order", function()
		ns.Config:SetUnitValue("target", "threat.opacity", 0.6)
		ns.Config:SetUnitValue("target", "threat.size", 20)
		assert.equals(0.6, uf.threatGlow:GetAlpha())
		local halo = uf.threatGlow.Halo
		assert.equals("Interface\\AddOns\\UnitFrames\\Media\\GlowFrameSoft", halo:GetTexture())
		-- One level under the frame, so its backdrop and bars cover the inner edge.
		assert.equals(uf.frame:GetFrameLevel() - 1, uf.threatGlow:GetFrameLevel())
		assert.equals(uf.frame, uf.threatGlow:GetParent())
		uf.frame:SetFrameLevel(uf.frame:GetFrameLevel() + 5)
		assert.is_true(uf.threatGlow:GetFrameLevel() < uf.frame:GetFrameLevel(), "re-levelling the frame leaves the glow under it")
		-- The reach outside the frame follows the size whatever the corners.
		for corners, file in pairs({ sharp = "GlowFrame", soft = "GlowFrameSoft", round = "GlowFrameRound" }) do
			ns.Config:SetUnitValue("target", "threat.corners", corners)
			assert.equals("Interface\\AddOns\\UnitFrames\\Media\\" .. file, halo:GetTexture(), corners)
			assert.equals(ns.Glow.FRAME_SHAPES[corners].margin, halo:GetTextureSliceMargins(), corners)
			assert.equals(20, math.floor(halo:GetScale() * 31 + 0.5), corners)
		end
		uf:SetThreat(3, 100)
		ns.Config:SetUnitValue("target", "threat.enabled", false)
		assert.is_false(uf.threatGlow:IsShown())
		assert.is_false(frame:IsElementEnabled("UF_Threat"))
		ns.Config:SetUnitValue("target", "threat.enabled", true)
		assert.is_true(uf.threatGlow:IsShown())
		assert.is_true(frame:IsElementEnabled("UF_Threat"))
		ns.Config:SetUnitValue("targettarget", "threat.enabled", true)
		assert.is_true(ns.Units.frames.targettarget:IsElementEnabled("UF_Threat"))
	end)

	it("keeps each frame's own glow when copying player settings #copy", function()
		ns.Config:SetUnitValue("target", "threat.opacity", 0.4)
		assert.is_true(ns.Units:CopyPlayerSettings("target"))
		assert.equals(0.4, uf.resolved.threat.opacity)
		assert.is_true(ns.Units:CopyPlayerSettings("targettarget"))
		assert.is_false(ns.Units.frames.targettarget.uf.resolved.threat.enabled)
	end)
end)

describe("Threat text #threat", function()
	local ns, source
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		source = ns.TextSources.Get("threat")
	end)

	it("shows the player's scaled threat, floored, and nothing off the list or at zero", function()
		local asked
		UnitDetailedThreatSituation = function(unit, mob)
			asked = { unit, mob }
			return true, 3, 72.6, 110, 5000
		end
		assert.equals("72%", ns.Formats.Get("threat").text("target"))
		assert.same({ "player", "target" }, asked)
		UnitDetailedThreatSituation = function() return false, 0, 0, 0, 0 end
		assert.equals("", ns.Formats.Get("threat").text("target"))
		UnitDetailedThreatSituation = function() end
		assert.equals("", ns.Formats.Get("threat").text("target"))
		assert.is_true(source.optional)
	end)

	it("passes secret threat values through natively", function()
		Mock.inCombat = true
		UnitDetailedThreatSituation = function()
			return Mock.Secret(true), Mock.Secret(3), Mock.Secret(100), Mock.Secret(110), Mock.Secret(5000)
		end
		assert.is_true(Mock.IsSecret(source.live("target")))
		assert.is_true(Mock.IsSecret(ns.Formats.Get("threat").text("target")))
	end)

	it("is a standalone preset on health and power slots and a custom piece", function()
		for _, list in ipairs({ ns.Formats.HEALTH, ns.Formats.POWER }) do
			local found = false
			for _, id in ipairs(list) do if id == "threat" then found = true end end
			assert.is_true(found)
		end
		assert.is_true(ns.oUF.Tags.SharedEvents.UNIT_THREAT_SITUATION_UPDATE)
		assert.is_not_nil(ns.oUF.Tags.Events["uf:threat"]:find("UNIT_THREAT_LIST_UPDATE", 1, true))
		assert.equals("Threat", source.group)
		assert.equals("100%", ns.Formats.Get("threat").sample({ threat = 100 }))
		assert.equals("", ns.Formats.Get("threat").sample({ threat = 0.4 }))
		assert.equals("", ns.Formats.Get("threat").sample({}))
	end)

	it("colours only the threat piece by stage, natively, and keeps empty text empty", function()
		local pieces = { { source = "name" }, { source = "threat", before = " (", after = ")" } }
		local template = ns.TextTemplate.Compile({ pieces = pieces, threatColor = true })
		UnitName = function() return "Mob" end
		for _, case in ipairs({ { 30, "ff40bf40" }, { 72.6, "ffffd100" }, { 85, "ffff8000" }, { 100, "ffff1a1a" } }) do
			UnitDetailedThreatSituation = Threat(0, case[1])
			assert.equals("Mob (|c" .. case[2] .. math.floor(case[1]) .. "%|r)", template.live("target"), tostring(case[1]))
		end
		UnitDetailedThreatSituation = Threat(0, 0)
		assert.equals("Mob", template.live("target"))
		UnitDetailedThreatSituation = function() end
		assert.equals("Mob", template.live("target"))
		assert.equals("|cffff800085%|r", ns.TextTemplate.Compile({ pieces = { { source = "threat" } }, threatColor = true })
			.sample({ threat = 85 }))
		assert.equals("Mob (85%)", ns.TextTemplate.Compile({ pieces = pieces, threatColor = false })
			.sample({ name = "Mob", threat = 85 }))
		assert.is_false(ns.TextTemplate.Signature({ pieces = pieces }) == ns.TextTemplate.Signature({ pieces = pieces, threatColor = true }))
		assert.is_false(ns.TextTemplate.Signature({ pieces = pieces, levelColor = true })
			== ns.TextTemplate.Signature({ pieces = pieces, threatColor = true }))
	end)

	it("tints secret threat text natively", function()
		Mock.inCombat = true
		UnitDetailedThreatSituation = function()
			return Mock.Secret(true), Mock.Secret(3), Mock.Secret(100), Mock.Secret(110), Mock.Secret(5000)
		end
		local template = ns.TextTemplate.Compile({ pieces = { { source = "threat" } }, threatColor = true })
		assert.is_true(Mock.IsSecret(template.live("target")))
	end)

	it("offers the slot option only for texts showing threat and drops the shared preset tag while on", function()
		local text = ns.Units.frames.target.uf:GetRow("health"):GetText("center")
		local option = ns.Schema.Find(text:GetSchema(), "threatColor")
		ns.Config:SetUnitValue("target", "health.center.format", "name")
		assert.is_true(option.hidden(text.resolved))
		ns.Config:SetUnitValue("target", "health.center.format", "threat")
		assert.is_false(option.hidden(text.resolved))
		assert.equals("threat", text:GetPresetTag())
		ns.Config:SetUnitValue("target", "health.center.threatColor", true)
		assert.is_nil(text:GetPresetTag())
		UnitDetailedThreatSituation = Threat(0, 85)
		assert.equals("|cffff800085%|r", text:GetTemplate().live("target"))
	end)
end)

describe("Threat Workbench preview #threat", function()
	it("holds the chosen threat, climbs when animated, and follows the style", function()
		local ns, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		wb:Select("unit.target")
		wb.styleTarget.set("health.center.format", "threat")
		wb.styleTarget.set("health.center.enabled", true)
		wb.styleTarget.set("health.center.threatColor", true)
		local uf = wb.handle.parts.uf
		local text = uf:GetRow("health"):GetText("center"):GetFrame()
		assert.equals("|cffff1a1a100%|r", text:GetText())
		assert.same(Stage(ns, "threatAggro"), GlowColor(uf))
		wb.dataTarget.set("threat", 60)
		assert.same(Stage(ns, "threatMedium"), GlowColor(uf))
		assert.equals("|cffffd10060%|r", text:GetText())
		wb.dataTarget.set("threatStatus", "off")
		assert.equals(0, GlowColor(uf)[4])
		assert.equals("", text:GetText())
		wb.styleTarget.set("threat.enabled", false)
		assert.is_false(uf.threatGlow:IsShown())
		wb.styleTarget.set("threat.enabled", true)
		assert.is_true(uf.threatGlow:IsShown())
		wb.dataTarget.set("source", "animated")
		local colors, seen = {}, 0
		for _ = 1, 10 do
			wb:OnUpdate(1)
			local c = GlowColor(uf)
			local key = table.concat({ c[1], c[2], c[3], c[4] }, ",")
			if not colors[key] then colors[key], seen = true, seen + 1 end
		end
		assert.is_true(seen >= 3, "animated climbs through the stages")
		wb:Select("unit.player")
		assert.is_nil(wb.handle.parts.uf.threatGlow)
	end)
end)
