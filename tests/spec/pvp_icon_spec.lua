local Helpers = require("helpers")
local Mock = Helpers.Mock

local ATLASES = {
	Alliance = "UI-HUD-UnitFrame-SmallCircle-Alliance",
	Horde = "UI-HUD-UnitFrame-SmallCircle-Horde",
	FFA = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
}

describe("PvP flag icons", function()
	local ns, frame, uf, flag
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		uf = frame.uf
		flag = uf:GetPart("pvp")
	end)

	it("offers and binds an icon with its background circle on every unit frame", function()
		for _, unit in ipairs(ns.Units.order) do
			local live = ns.Units.frames[unit]
			local icon = live.uf:GetPart("pvp")
			assert.is_not_nil(ns.Schema.Find(live.uf:GetSchema(), "pvp.anchor"), unit)
			assert.equals(icon:GetWidget(), live.PvPIndicator)
			assert.equals(icon.background, live.PvPIndicator.Background)
			assert.is_false(live.PvPIndicator.useAtlasSize, "configured size, not atlas size")
			assert.is_true(live:IsElementEnabled("PvPIndicator"))
			assert.is_false(icon:GetWidget():IsShown(), "hidden until the unit is flagged")
			assert.equals("UI-HUD-UnitFrame-SmallCircle", icon.background.__state.atlas)
		end
		ns.Config:SetUnitValue("target", "pvp.enabled", false)
		assert.is_false(ns.Units.frames.target:IsElementEnabled("PvPIndicator"))
		assert.is_true(frame:IsElementEnabled("PvPIndicator"))
		ns.Config:SetUnitValue("target", "pvp.enabled", true)
		assert.is_true(ns.Units.frames.target:IsElementEnabled("PvPIndicator"))
	end)

	it("re-enables the element when the background circle is switched", function()
		flag:SetSample("Horde")
		frame.calls = {}
		ns.Config:SetUnitValue("player", "pvp.background", false)
		assert.is_nil(rawget(frame.PvPIndicator, "Background"))
		assert.is_false(flag.background:IsShown())
		assert.same({ "disable PvPIndicator", "enable PvPIndicator" },
			{ frame.calls[1], frame.calls[2] }, "oUF must see the new sub-widget")
		frame.calls = {}
		ns.Config:SetUnitValue("player", "pvp.size", 30)
		for _, call in ipairs(frame.calls) do
			assert.is_false(call == "disable PvPIndicator", "unrelated changes keep the subscription")
		end
		ns.Config:SetUnitValue("player", "pvp.background", true)
		assert.equals(flag.background, frame.PvPIndicator.Background)
	end)

	it("joins the decoration stack and collapses when the unit is not flagged", function()
		ns.Config:SetUnitValue("player", "pvp.anchor", "TOP")
		ns.Config:SetUnitValue("player", "pvp.order", 2)
		uf:GetPart("raidTarget"):SetIndex(8)
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, { uf:GetPart("raidTarget"):GetFrame():GetPoint() })
		flag:SetSample("Alliance")
		-- Marker 20 + gap 2 + flag 18 = 40 wide.
		assert.same({ "CENTER", frame, "TOP", -10, 0 }, { uf:GetPart("raidTarget"):GetFrame():GetPoint() })
		assert.same({ "CENTER", frame, "TOP", 11, 0 }, { flag:GetFrame():GetPoint() })
		assert.equals(18, flag:GetFrame():GetWidth())
		flag:SetSample("off")
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, { uf:GetPart("raidTarget"):GetFrame():GetPoint() })
		assert.is_false(flag.background:IsShown())
	end)

	it("reflows after native element rebinding hides the flag", function()
		rawset(flag:GetWidget(), "__strict", true)
		ns.oUF.Private = { GameVersion = { Forever = true }, GameCompatibility = {} }
		assert(loadfile("UnitFrames/Libs/oUF/elements/pvpindicator.lua"))("oUF", ns)
		local element = ns.oUF.elements.PvPIndicator
		frame.RegisterEvent, frame.UnregisterEvent = function() end, function() end
		local disable, enable = frame.DisableElement, frame.EnableElement
		frame.DisableElement = function(self, name)
			if name == "PvPIndicator" then element.disable(self) end
			disable(self, name)
		end
		frame.EnableElement = function(self, name)
			if name == "PvPIndicator" then element.enable(self, self.__unit) end
			enable(self, name)
		end
		ns.Config:SetUnitValue("player", "pvp.anchor", "TOP")
		uf:GetPart("raidTarget"):SetIndex(8)
		flag:SetSample("Alliance")
		assert.same({ "CENTER", frame, "TOP", -10, 0 }, { uf:GetPart("raidTarget"):GetFrame():GetPoint() })
		ns.Config:SetUnitValue("player", "pvp.background", false)
		assert.is_false(flag:GetWidget():IsShown(), "native Disable hides art without PostUpdate")
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, { uf:GetPart("raidTarget"):GetFrame():GetPoint() },
			"binding must recalculate the stack after the native disable")
	end)

	it("lets Blizzard's secret-safe helper choose the art and keeps a slot for an opaque state", function()
		rawset(flag:GetWidget(), "__strict", true)
		ns.oUF.Private = { GameVersion = { Forever = true }, GameCompatibility = {} }
		assert(loadfile("UnitFrames/Libs/oUF/elements/pvpindicator.lua"))("oUF", ns)
		local element, handlers, received = ns.oUF.elements.PvPIndicator, {}, nil
		frame.RegisterEvent = function(_, event, handler) handlers[event] = handler end
		frame.UnregisterEvent = function(_, event) handlers[event] = nil end
		UnitFactionGroup = function() error("the addon must not derive a live PvP flag") end
		UnitFrameUtil.UpdateUnitPvPIndicator = Mock.SecureDelegate(function(elements, unit, checkMercenary)
			received = elements
			assert.equals("player", unit)
			assert.is_true(checkMercenary)
			local info = Mock.pvpInfo[unit] or { pvpIconAtlas = "", showPvPIcon = false }
			if info.showPvPIcon == true or Mock.IsSecret(info.showPvPIcon) then
				elements.pvpIcon:SetAtlas(info.pvpIconAtlas, false)
			end
			elements.pvpIcon:SetShown(info.showPvPIcon)
			elements.pvpBackground:SetShown(info.showPvPIcon)
		end)
		assert.is_true(element.enable(frame, "player"))
		assert.is_not_nil(handlers.PLAYER_PVP_FLAG_CHANGED)
		assert.is_not_nil(handlers.UNIT_FACTION)

		ns.Config:SetUnitValue("player", "pvp.anchor", "TOP")
		uf:GetPart("raidTarget"):SetIndex(8)
		Mock.pvpInfo.player = { pvpIconAtlas = ATLASES.Horde, showPvPIcon = true }
		handlers.PLAYER_PVP_FLAG_CHANGED(frame, "PLAYER_PVP_FLAG_CHANGED")
		assert.equals(flag:GetWidget(), received.pvpIcon)
		assert.equals(flag.background, received.pvpBackground)
		assert.equals(ATLASES.Horde, flag:GetWidget().__state.atlas)
		assert.is_true(flag:GetWidget():IsShown())
		assert.same({ "CENTER", frame, "TOP", -10, 0 }, { uf:GetPart("raidTarget"):GetFrame():GetPoint() },
			"oUF's PostUpdate reflows the stack")

		Mock.pvpInfo.player = { pvpIconAtlas = Secret(ATLASES.FFA), showPvPIcon = Secret(true) }
		handlers.UNIT_FACTION(frame, "UNIT_FACTION", "player")
		assert.is_true(Mock.IsSecret(flag:GetWidget():IsShown()))
		assert.same({ "CENTER", frame, "TOP", -10, 0 }, { uf:GetPart("raidTarget"):GetFrame():GetPoint() },
			"an opaque shown state keeps its slot")

		Mock.pvpInfo.player = nil
		handlers.PLAYER_PVP_FLAG_CHANGED(frame, "PLAYER_PVP_FLAG_CHANGED")
		assert.is_false(flag:GetWidget():IsShown())
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, { uf:GetPart("raidTarget"):GetFrame():GetPoint() })
		element.disable(frame)
		assert.is_nil(handlers.PLAYER_PVP_FLAG_CHANGED)
		assert.is_false(flag.background:IsShown())
	end)

	it("copies player settings and releases preview visuals", function()
		ns.Config:SetUnitValue("player", "pvp.anchor", "BOTTOMLEFT")
		ns.Config:SetUnitValue("player", "pvp.background", false)
		ns.Units:CopyPlayerSettings("focus")
		local focus = ns.Units.frames.focus.uf
		assert.equals("BOTTOMLEFT", focus:GetPart("pvp").resolved.anchor)
		assert.is_false(focus:GetPart("pvp").resolved.background)
		local preview = ns.Units:CreateFrame("target", UIParent)
		local previewFlag = preview:GetPart("pvp")
		previewFlag:SetSample("FFA")
		preview:Release()
		assert.is_false(previewFlag:GetFrame():IsShown())
		assert.is_nil(preview:GetDecorations().members.pvp)
	end)
end)

describe("PvP flag icon companions and previews", function()
	it("is not offered on ClickGrid group bars", function()
		local _, CG = Helpers.LoadClickGrid()
		for _, kind in ipairs({ "member", "target" }) do
			assert.is_nil(CG.definitions[kind].pvp, kind)
			assert.is_nil(CG:StyleSchema(kind) and UnitFrames.Schema.Find(CG:StyleSchema(kind), "pvp"), kind)
		end
	end)

	it("previews each flag on every frame in static and animated modes", function()
		local ns, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		for _, unit in ipairs(ns.Units.order) do
			wb:Select("unit." .. unit)
			local flag = wb.handle.parts.uf:GetPart("pvp")
			for _, source in ipairs({ "static", "animated" }) do
				wb.dataTarget.set("source", source)
				for state, atlas in pairs(ATLASES) do
					wb.dataTarget.set("pvp", state)
					assert.equals(atlas, flag:GetWidget().__state.atlas, unit .. ": " .. state)
					assert.is_true(flag:GetWidget():IsShown())
					assert.is_true(flag.background:IsShown())
				end
				wb.styleTarget.set("pvp.background", false)
				assert.is_false(flag.background:IsShown())
				wb.styleTarget.set("pvp.background", true)
				wb.dataTarget.set("pvp", "off")
				assert.is_false(flag:GetWidget():IsShown())
				assert.is_false(flag.background:IsShown())
			end
			wb:SelectSection("pvp")
			assert.equals(8, #wb.inspector.page.rows)
		end
	end)
end)
