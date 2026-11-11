local Helpers = require("helpers")

describe("ClickGrid member heals by default #buffs", function()
	local UF, CG

	local function Native()
		local member = CG.headers.party:GetAttribute("child1").Member
		return member.uf:GetPart("auras"):GetContainer("buffs").__state.groups.buffs
	end

	local function SampleIcons(auras)
		local icons = {}
		for _, button in ipairs(auras.previewContainers.buffs.ufButtons) do
			if button:IsShown() then icons[#icons + 1] = button.ufIcon:GetTexture():match("([^\\]+)$") end
		end
		return icons
	end

	it("enables member buffs with My heals & shields on a fresh profile", function()
		UF, CG = Helpers.LoadClickGrid()
		UnitClass = function() return "Warrior", "WARRIOR", 1 end
		CG:Refresh()
		local buffs = CG.Config.styles.member:Resolved().auras.buffs
		assert.is_true(buffs.enabled)
		assert.equals(UF.Components.Auras.MY_HEALS, buffs.filter)
		assert.equals(0, buffs.maxDuration)
		assert.is_true(Native().enabled)
		assert.equals("HELPFUL|PLAYER", Native().filter)
		assert.same({}, Native().candidateFilters.includeSpellIDs)
	end)

	it("keeps an explicit member buff choice on update", function()
		UF, CG = Helpers.LoadClickGrid(false, { member = { auras = { buffs = {
			enabled = false, filter = "HELPFUL|PLAYER|RAID_IN_COMBAT" } } } })
		local buffs = CG.Config.styles.member:Resolved().auras.buffs
		assert.is_false(buffs.enabled)
		assert.equals("HELPFUL|PLAYER|RAID_IN_COMBAT", buffs.filter)
		assert.is_nil(Native().candidateFilters)
	end)

	it("passes a druid's Rejuvenation ranks of both ID sets to member cells", function()
		UF, CG = Helpers.LoadClickGrid()
		UnitClass = function() return "Druid", "DRUID", 11 end
		CG:Refresh()
		local include = Native().candidateFilters.includeSpellIDs
		for _, id in ipairs({ 774, 9841, 25299, 417057, 8936, 408124 }) do assert.is_true(include[id], id) end
		assert.is_nil(include[17])
	end)

	it("previews the player's own class heals on member cells", function()
		local wb
		UF, CG, wb = Helpers.LoadClickGrid(true)
		UnitClass = function() return "Druid", "DRUID", 11 end
		wb:Open("clickgrid.panel")
		assert.same({ "Spell_Nature_Rejuvenation" }, SampleIcons(wb.handle.cells[1].member:GetPart("auras")))
		UnitClass = function() return "Priest", "PRIEST", 5 end
		wb:UpdateData()
		assert.same({ "Spell_Holy_Renew", "Spell_Holy_PowerWordShield" }, SampleIcons(wb.handle.cells[1].member:GetPart("auras")))
		UnitClass = function() return "Warrior", "WARRIOR", 1 end
		wb:UpdateData()
		assert.same({}, SampleIcons(wb.handle.cells[1].member:GetPart("auras")))
	end)
end)
