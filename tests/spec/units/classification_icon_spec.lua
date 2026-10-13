local Helpers = require("helpers")
local Mock = Helpers.Mock

local ATLASES = {
	elite = "nameplates-icon-elite-gold",
	worldboss = "nameplates-icon-elite-gold",
	rareelite = "nameplates-icon-elite-silver",
	rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
}

describe("Elite / rare icons", function()
	local ns, frame, uf, icon, handlers
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.target
		uf = frame.uf
		icon = uf:GetPart("classification")
		handlers = {}
		frame.RegisterEvent = function(_, event, handler, shared)
			handlers[event] = handler
			assert.is_nil(shared, "classification changes carry a unit")
		end
		frame.UnregisterEvent = function(_, event) handlers[event] = nil end
	end)

	it("offers and binds an icon on every unit frame but not on ClickGrid bars", function()
		for _, unit in ipairs(ns.Units.order) do
			local live = ns.Units.frames[unit]
			assert.is_not_nil(ns.Schema.Find(live.uf:GetSchema(), "classification.anchor"), unit)
			assert.equals(live.uf:GetPart("classification"), live.UF_Classification)
			assert.is_true(live:IsElementEnabled("UF_Classification"))
			assert.is_false(live.uf:GetPart("classification"):GetWidget():IsShown())
		end
		ns.Config:SetUnitValue("target", "classification.enabled", false)
		assert.is_false(frame:IsElementEnabled("UF_Classification"))
		ns.Config:SetUnitValue("target", "classification.enabled", true)
		assert.is_true(frame:IsElementEnabled("UF_Classification"))
		local _, CG = Helpers.LoadClickGrid()
		for _, kind in ipairs({ "member", "target" }) do
			assert.is_nil(UnitFrames.Schema.Find(CG:StyleSchema(kind), "classification"), kind)
		end
	end)

	it("uses Blizzard's elite, rare-elite, rare and boss art and hides for other units", function()
		local element = ns.oUF.elements.UF_Classification
		assert.is_true(element.enable(frame, "target"))
		for classification, atlas in pairs(ATLASES) do
			UnitClassification = function(unit)
				assert.equals("target", unit)
				return classification
			end
			handlers.UNIT_CLASSIFICATION_CHANGED(frame, "UNIT_CLASSIFICATION_CHANGED", "target")
			assert.equals(atlas, icon:GetWidget().__state.atlas, classification)
			assert.is_true(icon:GetWidget():IsShown())
		end
		for _, classification in ipairs({ "normal", "trivial", "minus" }) do
			UnitClassification = function() return classification end
			element.update(frame, "PLAYER_TARGET_CHANGED")
			assert.is_false(icon:GetWidget():IsShown(), classification)
		end
		UnitClassification = function() return "elite" end
		handlers.UNIT_CLASSIFICATION_CHANGED(frame, "UNIT_CLASSIFICATION_CHANGED", "focus")
		assert.is_false(icon:GetWidget():IsShown(), "other units' events are ignored")
		element.update(frame, "PLAYER_TARGET_CHANGED")
		assert.is_true(icon:GetWidget():IsShown())
		UnitExists = function() return false end
		UnitClassification = function() error("no data for a missing unit") end
		element.update(frame, "PLAYER_TARGET_CHANGED")
		assert.is_false(icon:GetWidget():IsShown())
		UnitExists = function() return true end
		UnitClassification = function() return Secret("elite") end
		element.update(frame, "PLAYER_TARGET_CHANGED")
		assert.is_false(icon:GetWidget():IsShown(), "an opaque classification is not inspected")
		UnitClassification = function() return "rare" end
		element.update(frame, "PLAYER_TARGET_CHANGED")
		element.disable(frame)
		assert.is_nil(handlers.UNIT_CLASSIFICATION_CHANGED)
		assert.is_false(icon:GetWidget():IsShown())
	end)

	it("joins the decoration stack beside other icons and leaves no gap when absent", function()
		ns.Config:SetUnitValue("target", "classification.anchor", "TOP")
		ns.Config:SetUnitValue("target", "classification.order", 2)
		local marker = uf:GetPart("raidTarget")
		marker:SetIndex(8)
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, { marker:GetFrame():GetPoint() })
		icon:SetClassification("elite")
		-- Marker 20 + gap 2 + icon 18 = 40 wide.
		assert.same({ "CENTER", frame, "TOP", -10, 0 }, { marker:GetFrame():GetPoint() })
		assert.same({ "CENTER", frame, "TOP", 11, 0 }, { icon:GetFrame():GetPoint() })
		icon:SetClassification(nil)
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, { marker:GetFrame():GetPoint() })
		ns.Config:SetUnitValue("target", "classification.anchor", "PORTRAIT_BOTTOMLEFT")
		icon:SetClassification("rareelite")
		assert.same({ "BOTTOMLEFT", uf:GetPart("portrait"):GetFrame(), "BOTTOMLEFT", 0, 0 }, { icon:GetFrame():GetPoint() })
	end)
end)

describe("Elite / rare icon previews", function()
	it("follows the NPC sample classification and hides for players", function()
		local ns, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		wb:Select("unit.target")
		local icon = wb.handle.parts.uf:GetPart("classification")
		assert.equals(ATLASES.elite, icon:GetWidget().__state.atlas, "the target sample is an elite NPC")
		assert.is_true(icon:GetWidget():IsShown())
		for _, source in ipairs({ "static", "animated" }) do
			wb.dataTarget.set("source", source)
			for classification, atlas in pairs(ATLASES) do
				wb.dataTarget.set("classification", classification)
				assert.equals(atlas, icon:GetWidget().__state.atlas, classification)
				assert.is_true(icon:GetWidget():IsShown())
			end
			wb.dataTarget.set("classification", "normal")
			assert.is_false(icon:GetWidget():IsShown())
			wb.dataTarget.set("classification", "elite")
			wb.dataTarget.set("npc", false)
			assert.is_false(icon:GetWidget():IsShown(), "players have no classification marker")
			wb.dataTarget.set("npc", true)
		end
		wb:Select("unit.player")
		assert.is_false(wb.handle.parts.uf:GetPart("classification"):GetWidget():IsShown())
	end)
end)
