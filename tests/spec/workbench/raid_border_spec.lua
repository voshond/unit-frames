local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Native raid border previews and live frames", function()
	it("offers native artwork in the player selector and preserves resting tints", function()
		local UF, workbench = Helpers.LoadWorkbench()
		workbench:Open("unit.player")
		local found = false
		for _, name in ipairs(UF.Media:List("border")) do
			if name == "Blizzard Raid" then found = true end
		end
		assert.is_true(found)
		assert.is_nil(UF.Media.LSM:Fetch("border", "Blizzard Raid", true), "not an LSM edge file")
		UF.Config:SetUnitValue("player", "border.border", "Blizzard Raid")
		local live = UF.Units.frames.player.uf
		local B = UF.Components.Backdrop
		assert.equals([[Interface\RaidFrame\RaidBorder-UpperLeft]], B.BorderTextures(live.border)[1]:GetTexture())
		assert.equals(B.BorderTextures(live.border)[1]:GetTexture(), B.BorderTextures(workbench.handle.parts.uf.border)[1]:GetTexture())
		live:SetResting(true, false)
		for _, texture in ipairs(B.BorderTextures(live.border)) do
			assert.same(live.resolved.resting.color, texture.__state.vertexColor)
		end
		live:SetResting(false)
		assert.same(live.resolved.border.color, B.BorderTextures(live.border)[1].__state.vertexColor)
	end)

	it("switches gallery borders without retaining artwork and handles opaque fixed dimensions", function()
		local UF, workbench = Helpers.LoadWorkbench()
		local B = UF.Components.Backdrop
		local entry = workbench.entries.raidBorder
		local handle = entry.create(CreateFrame("Frame"))
		handle.frame:SetSize(220, 100)
		handle:Apply(entry.defaultConfig)
		local corner = B.BorderTextures(handle.frame)[1]
		local art = corner:GetParent()
		assert.equals(32, corner:GetWidth())
		for _ = 1, 2 do
			handle:Apply({ border = { border = "Blizzard Tooltip" } })
			assert.is_false(art:IsShown())
			assert.equals([[Interface\Tooltips\UI-Tooltip-Border]], handle.frame:GetBackdrop().edgeFile)
			handle:Apply({ border = { enabled = false } })
			assert.is_false(art:IsShown())
			assert.is_nil(handle.frame:GetBackdrop())
			handle:Apply({ border = { border = "Blizzard Raid", background = "None", size = 8 } })
			assert.is_true(art:IsShown())
			assert.equals(corner, B.BorderTextures(handle.frame)[1])
			assert.equals(16, corner:GetWidth())
		end
		local cfg = UF.Schema.Resolve(B.schema, { border = "Blizzard Raid", background = "None" }, UF.Config:GetTheme())
		Mock.SetEngineSize(handle.frame, Mock.Secret(24), Mock.Secret(24))
		assert.has_no_error(function()
			B.ApplyToFixedSize(handle.frame, cfg, 24, 24)
			B.ApplyToFixedSize(handle.frame, cfg, 32, 32)
		end)
		handle:Release()
		assert.is_false(handle.frame:IsShown())
	end)

	it("keeps native aura dispel colours across restyles and toggles in live and sample icons", function()
		local UF = Helpers.LoadAddon(true, true)
		local B = UF.Components.Backdrop
		UF.Config:SetUnitValue("player", "auras.border.border", "Blizzard Raid")
		local auras = UF.Units.frames.player.uf:GetPart("auras")
		local button = auras:GetContainer("debuffs"):GetAuraGroupFrame("debuffs", 1)
		local magic = { AuraUtil.GetAuraBorderColor("Magic"):GetRGBA() }
		assert.equals(8, #button.ufDispelTextures)
		for _, texture in ipairs(button.ufDispelTextures) do assert.same(magic, texture.__state.vertexColor) end
		assert.same({ 0, 0, 0, 0 }, B.BorderTextures(button.ufIconFrame)[1].__state.vertexColor)
		UF.Config:SetUnitValue("player", "auras.showCount", false)
		assert.same(magic, button.ufDispelTextures[1].__state.vertexColor)
		UF.Config:SetUnitValue("player", "auras.dispelBorder", false)
		assert.equals(0, #button.ufDispelTextures)
		assert.same(auras.resolved.border.color, B.BorderTextures(button.ufIconFrame)[1].__state.vertexColor)
		UF.Config:SetUnitValue("player", "auras.dispelBorder", true)
		assert.equals(8, #button.ufDispelTextures)
		local sample = CreateFrame("Button")
		UF.AuraIcon.Create(sample, "debuffs", true, { harmful = true })
		local cfg = UF.Schema.Resolve(UF.AuraIcon.schema, { border = { border = "Blizzard Raid" } }, UF.Config:GetTheme())
		local palette = UF.AuraIcon.DispelColors(cfg)
		UF.AuraIcon.Apply(sample, cfg, 24, palette)
		UF.AuraIcon.DrawSample(sample, { icon = "sample", dispelName = "Magic" }, palette)
		assert.equals(8, #sample.ufDispelTextures)
		for _, texture in ipairs(sample.ufDispelTextures) do assert.same(magic, texture.__state.vertexColor) end
		UF.Config:SetUnitValue("player", "auras.border.border", "Blizzard Tooltip")
		assert.equals(8, #button.ufDispelTextures)
		assert.equals([[Interface\Tooltips\UI-Tooltip-Border]], button.ufDispelTextures[1]:GetTexture())
	end)

	it("updates the independent ClickGrid panel border in the live panel and preview", function()
		local UF, CG, workbench = Helpers.LoadClickGrid(true)
		workbench:Open("clickgrid.panel")
		local preview, B = workbench.handle, UF.Components.Backdrop
		local member = preview.cells[1].member
		local original = member.resolved.border.border
		assert.is_true(CG.Config:Set("border.border", "Blizzard Raid"))
		assert.is_true(CG.Config:Set("border.color", { 1, 0.5, 0.25, 1 }))
		local corner = B.BorderTextures(CG.background)[1]
		local art = corner:GetParent()
		assert.equals([[Interface\RaidFrame\RaidBorder-UpperLeft]], corner:GetTexture())
		assert.equals(corner:GetTexture(), B.BorderTextures(preview.background)[1]:GetTexture())
		assert.same({ 1, 0.5, 0.25, 1 }, corner.__state.vertexColor)
		assert.equals(original, member.resolved.border.border)
		CG.Config:Set("border.enabled", false)
		assert.is_false(art:IsShown())
		assert.is_nil(CG.background:GetBackdrop())
		CG.Config:Set("border.enabled", true)
		assert.is_true(art:IsShown())
		Mock.inCombat = true
		CG.Config:Set("border.border", "Blizzard Tooltip")
		assert.is_true(art:IsShown(), "protected panel restyling waits for combat")
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_false(art:IsShown())
		UF.Config:SetThemeValue("borderTexture", "UnitFrames Pixel")
		assert.equals("Blizzard Tooltip", CG.Config:Resolved().border.border, "an explicit panel override survives a theme change")
		CG.Config:Set("border", nil)
		assert.equals(UF.Config:GetTheme().borderTexture, CG.Config:Resolved().border.border)
		assert.equals(UF.Media:Fetch("border", "UnitFrames Pixel"), CG.background:GetBackdrop().edgeFile)
	end)
end)
