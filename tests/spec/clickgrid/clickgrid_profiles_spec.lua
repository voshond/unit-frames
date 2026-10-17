local Helpers = require("helpers")

describe("ClickGrid profile strings #profiles", function()
	local UF, CG
	before_each(function()
		UF, CG = Helpers.LoadClickGrid()
	end)

	it("prepares new raid and tank headers when switching profiles with the panel hidden", function()
		local original = UF.Profiles:GetCurrent()
		assert.is_true(UF.Profiles:Create("Flat with tanks"))
		Helpers.Mock.inCombat = true
		CG.Config:Set("panel.mode", "flat")
		CG.Config:Set("panel.tanks", true)
		assert.is_true(UF.Profiles:Switch(original))
		Helpers.Mock.inCombat = false
		Helpers.Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_nil(CG.headers.raid)
		assert.is_nil(CG.headers.tanks)
		CG.panel:Hide()
		assert.is_true(UF.Profiles:Switch("Flat with tanks"))
		for _, key in ipairs({ "raid", "tanks" }) do
			local header = CG.headers[key]
			assert.equals(CG.panel, header:GetParent())
			assert.is_not_nil(header:GetAttribute("child40"))
			assert.equals(1, header:GetAttribute("startingIndex"))
		end
		assert.equals(UF.Units.STYLE, UF.oUF:GetActiveStyle())
		assert.is_true(UF.Profiles:Switch(original))
		CG.panel:Hide()
		assert.is_true(UF.Profiles:Switch("Flat with tanks"))
		assert.equals(250, #CG.frames)
	end)

	it("travels with the style string and is validated before anything is written", function()
		CG.Config:Set("panel.columns", 3)
		CG.Config:Set("border.border", "Blizzard Raid")
		CG.Config:SetStyle("member", "width", 151)
		local text = UF.Profiles:Export("style")
		assert.equals(3, UF.Profiles:Decode(text).data.clickgrid.settings.panel.columns)
		UF.Profiles:Reset()
		assert.same({}, CG.Config:Get())
		assert.is_true(UF.Profiles:Import(text))
		assert.equals(3, CG.Config:Resolved().panel.columns)
		assert.equals("Blizzard Raid", CG.Config:Resolved().border.border)
		assert.equals(151, CG.Config:GetStyle("member").width)

		-- An invalid fixed slot rejects the whole import.
		local payload = UF.Profiles:Decode(text)
		payload.data.units = { player = { width = 199 } }
		payload.data.clickgrid.settings.slots = { slot1 = { spell = "not an id" } }
		local E = C_EncodingUtil
		local bad = "!UF1!" .. E.EncodeBase64(E.CompressString(E.SerializeCBOR(payload)))
		local ok, reason = UF.Profiles:Import(bad)
		assert.is_false(ok)
		assert.is_not_nil(reason:find("ClickGrid", 1, true))
		assert.is_nil(UF.Config:GetUnitConfig("player").width)
	end)

	it("shares click bindings as their own string for the same class", function()
		local secretClass = UnitClass
		UnitClass = function() return "Warrior", "WARRIOR", 1 end
		CG.Config:SetBinding(1, "none", "hostile", "action", "assist")
		local text = UF.Profiles:Export("clickgrid.bindings")
		CG.Config.bindings:Reset()
		local ok, reason = UF.Profiles:Import(text, "Elsewhere")
		assert.is_false(ok)
		assert.equals("ClickGrid click bindings aren't stored per profile.", reason)
		assert.is_true(UF.Profiles:Import(text))
		assert.equals("assist", CG.Config:GetBindings().button1.none.hostile.action)

		UnitClass = function() return "Mage", "MAGE", 8 end
		ok, reason = UF.Profiles:Import(text)
		assert.is_false(ok)
		assert.equals("These bindings are for Warrior spells.", reason)
		-- An opaque class can't be compared: the bindings import.
		UnitClass = secretClass
		assert.is_true(UF.Profiles:Import(text))
	end)
end)

describe("Combined profile strings #profiles", function()
	local UF, CG
	before_each(function()
		UF, CG = Helpers.LoadClickGrid()
		UnitClass = function() return "Warrior", "WARRIOR", 1 end
	end)

	it("carries style and bindings together", function()
		UF.Config:SetUnitValue("player", "width", 266)
		CG.Config:SetBinding(1, "none", "hostile", "action", "assist")
		local text = UF.Profiles:Export("all")
		UF.Profiles:Reset()
		CG.Config.bindings:Reset()
		local ok, dropped, label = UF.Profiles:Import(text, "Everything")
		assert.is_true(ok)
		assert.same({}, dropped)
		assert.equals("all settings", label)
		assert.equals("Everything", UF.Profiles:GetCurrent())
		assert.equals(266, UF.Config:GetUnitConfig("player").width)
		assert.equals("assist", CG.Config:GetBindings().button1.none.hostile.action)
	end)

	it("imports the style and skips bindings of another class", function()
		UF.Config:SetUnitValue("player", "width", 266)
		local text = UF.Profiles:Export("all")
		UF.Config:SetUnitValue("player", "width", nil)
		UnitClass = function() return "Mage", "MAGE", 8 end
		local ok, dropped = UF.Profiles:Import(text)
		assert.is_true(ok)
		assert.same({ "ClickGrid click bindings (These bindings are for Warrior spells.)" }, dropped)
		assert.equals(266, UF.Config:GetUnitConfig("player").width)
	end)
end)

describe("Profiles Workbench entry with ClickGrid #profiles", function()
	it("offers each export and all settings last", function()
		local _, _, wb = Helpers.LoadClickGrid(true)
		wb:Open("profiles")
		local labels = {}
		for i = 1, 3 do labels[i] = wb.handle.buttons[i].text:GetText() end
		assert.same({ "Export style", "Export ClickGrid click bindings", "Export all settings" }, labels)
	end)
end)
