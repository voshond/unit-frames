local Helpers = require("helpers")
local Mock = Helpers.Mock

local ATLAS = "UI-HUD-UnitFrame-Player-Rest-Flipbook"

describe("Resting icons", function()
	local ns, frame, uf, icon
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		uf = frame.uf
		icon = uf:GetPart("restingIcon")
	end)

	it("offers and binds Blizzard's looping zZz on the player frame only", function()
		for _, unit in ipairs(ns.Units.order) do
			local live = ns.Units.frames[unit]
			if unit == "player" then
				assert.is_not_nil(ns.Schema.Find(live.uf:GetSchema(), "restingIcon.anchor"))
				assert.equals(icon:GetWidget(), live.RestingIndicator)
				assert.is_true(live:IsElementEnabled("RestingIndicator"))
			else
				assert.is_nil(live.uf:GetPart("restingIcon"), unit)
				assert.is_nil(ns.Schema.Find(live.uf:GetSchema(), "restingIcon"), unit)
			end
		end
		assert.equals(ATLAS, icon:GetWidget().__state.atlas)
		assert.is_false(icon:GetWidget().useAtlasSize, "configured size, not atlas size")
		assert.is_false(icon:GetWidget():IsShown(), "hidden until the player rests")
		assert.equals(icon:GetWidget(), icon.flipbook.__calls[1][2])
		assert.same({ "SetFlipBookRows", 7 }, icon.flipbook.__calls[2])
		assert.same({ "SetFlipBookColumns", 6 }, icon.flipbook.__calls[3])
		assert.same({ "SetFlipBookFrames", 42 }, icon.flipbook.__calls[4])
		assert.same({ "SetDuration", 1.5 }, icon.flipbook.__calls[5])
		ns.Config:SetUnitValue("player", "restingIcon.enabled", false)
		assert.is_false(frame:IsElementEnabled("RestingIndicator"))
		ns.Config:SetUnitValue("player", "restingIcon.enabled", true)
		assert.is_true(frame:IsElementEnabled("RestingIndicator"))
		local _, CG = Helpers.LoadClickGrid()
		for _, kind in ipairs({ "member", "target" }) do
			assert.is_nil(UnitFrames.Schema.Find(CG:StyleSchema(kind), "restingIcon"), kind)
		end
	end)

	it("keeps its art under oUF's native element, loops while resting and reflows the stack", function()
		rawset(icon:GetWidget(), "__strict", true)
		ns.oUF.Private = { unitIsUnit = function(a, b) return a == b end }
		assert(loadfile("UnitFrames/Libs/oUF/elements/restingindicator.lua"))("oUF", ns)
		local element, handlers = ns.oUF.elements.RestingIndicator, {}
		frame.RegisterEvent = function(_, event, handler) handlers[event] = handler end
		frame.UnregisterEvent = function(_, event) handlers[event] = nil end
		assert.is_true(element.enable(frame, "player"))
		assert.equals(ATLAS, icon:GetWidget().__state.atlas, "oUF's default art must not replace the flipbook")
		assert.is_nil(icon:GetWidget().__state.texCoords)

		ns.Config:SetUnitValue("player", "restingIcon.anchor", "TOP")
		ns.Config:SetUnitValue("player", "restingIcon.order", 2)
		local marker = uf:GetPart("raidTarget")
		marker:SetIndex(8)
		Mock.resting = true
		handlers.PLAYER_UPDATE_RESTING(frame, "PLAYER_UPDATE_RESTING")
		assert.is_true(icon:GetWidget():IsShown())
		assert.is_true(icon.animation:IsPlaying())
		-- Marker 20 + gap 2 + icon 20 = 42 wide.
		assert.same({ "CENTER", frame, "TOP", -11, 0 }, { marker:GetFrame():GetPoint() })
		assert.same({ "CENTER", frame, "TOP", 11, 0 }, { icon:GetFrame():GetPoint() })

		Mock.resting = false
		handlers.PLAYER_UPDATE_RESTING(frame, "PLAYER_UPDATE_RESTING")
		assert.is_false(icon:GetWidget():IsShown())
		assert.is_false(icon.animation:IsPlaying())
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, { marker:GetFrame():GetPoint() })
		element.disable(frame)
		assert.is_nil(handlers.PLAYER_UPDATE_RESTING)
	end)

	it("copies to no other unit and releases preview visuals", function()
		ns.Config:SetUnitValue("player", "restingIcon.anchor", "BOTTOMLEFT")
		ns.Units:CopyPlayerSettings("focus")
		assert.is_nil(ns.Config:GetUnitConfig("focus").restingIcon)
		local preview = ns.Units:CreateFrame("player", UIParent)
		local previewIcon = preview:GetPart("restingIcon")
		previewIcon:SetResting(true)
		assert.is_true(previewIcon.animation:IsPlaying())
		preview:Release()
		assert.is_false(previewIcon.animation:IsPlaying())
		assert.is_nil(preview:GetDecorations().members.restingIcon)
	end)
end)

describe("Resting icon previews", function()
	it("follows the resting sample in static and animated modes", function()
		local _, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		wb:Select("unit.player")
		local icon = wb.handle.parts.uf:GetPart("restingIcon")
		for _, source in ipairs({ "static", "animated" }) do
			wb.dataTarget.set("source", source)
			wb.dataTarget.set("resting", true)
			assert.is_true(icon:GetWidget():IsShown(), source)
			assert.is_true(icon.animation:IsPlaying(), source)
			wb.dataTarget.set("resting", false)
			assert.is_false(icon:GetWidget():IsShown(), source)
			assert.is_false(icon.animation:IsPlaying(), source)
		end
		wb:Select("unit.target")
		assert.is_nil(wb.handle.parts.uf:GetPart("restingIcon"))
	end)

	it("lists its settings in the player's resting section only", function()
		local _, wb = Helpers.LoadWorkbench()
		local function Listed(unit)
			wb:Open("unit." .. unit)
			wb:SelectSection("restingIcon")
			for _, row in ipairs(wb.inspector.page.rows) do
				if row.path and row.path:find("^restingIcon") then return true end
			end
			return false
		end
		assert.is_true(Listed("player"))
		assert.is_false(Listed("target"))
	end)
end)
