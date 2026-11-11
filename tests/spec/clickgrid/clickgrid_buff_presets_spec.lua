local Helpers = require("helpers")

describe("ClickGrid buff presets #buffs", function()
	local UF, CG, wb

	local function As(class, name)
		UnitClass = function() return name, class, 1 end
	end

	local function Icons(buttons)
		local icons = {}
		for _, button in ipairs(buttons) do
			if button:IsShown() then icons[#icons + 1] = button.ufIcon:GetTexture():match("([^\\]+)$") end
		end
		return icons
	end

	local function CardIcons(card)
		local placement = card.spec.placement
		if placement == "inside" then return Icons(card.slots.samples) end
		local part = card.member:GetPart(placement == "bar" and "auraBar" or "auras")
		return Icons(part.previewContainers.buffs.ufButtons)
	end

	local function SlotCandidates(index)
		local member = CG.headers.party:GetAttribute("child1").Member
		local slots = CG:GetGridButton(member).slots
		return slots.candidates["slot" .. index]
	end

	it("resolves each named set to a filter and every rank from the catalogue", function()
		UF, CG = Helpers.LoadClickGrid()
		As("DRUID", "Druid")
		local heals = CG.BuffPresets.Resolve("heals")
		assert.equals("HELPFUL|PLAYER", heals.filter)
		assert.is_true(heals.own)
		for _, id in ipairs({ 774, 25299, 417057, 8936, 408124 }) do assert.is_true(heals.ids[id], id) end
		assert.is_nil(heals.ids[17])
		assert.same({ 774, 8936, 408120, 408124 }, heals.families)
		local externals = CG.BuffPresets.Resolve("externals")
		assert.equals("HELPFUL", externals.filter)
		assert.is_false(externals.own)
		for _, id in ipairs({ 1022, 10060, 402004, 29166, 871, 22812 }) do assert.is_true(externals.ids[id], id) end
		assert.is_nil(externals.ids[774])
		assert.same({ 22812, 22842, 29166 }, { externals.families[1], externals.families[2], externals.families[3] })
		local raid = CG.BuffPresets.Resolve("raid")
		assert.equals("HELPFUL", raid.filter)
		for _, id in ipairs({ 1126, 21562, 1459, 5242 }) do assert.is_true(raid.ids[id], id) end
		assert.is_nil(raid.ids[1022])
	end)

	it("offers the sets as member buff filters", function()
		UF, CG = Helpers.LoadClickGrid()
		local option = UF.Schema.Find(CG:StyleSchema("member"), "auras.buffs.filter")
		local keys = {}
		for _, value in ipairs(option.values()) do keys[value[1]] = true end
		for _, preset in ipairs(CG.BuffPresets.LIST) do assert.is_true(keys[preset.filter], preset.id) end
		local bar = UF.Schema.Find(CG:StyleSchema("member"), "auraBar.buffs.filter")
		local barKeys = {}
		for _, value in ipairs(bar.values()) do barKeys[value[1]] = true end
		assert.is_true(barKeys[UF.Components.Auras.EXTERNALS])
	end)

	it("detects the default as my heals outside on top", function()
		UF, CG = Helpers.LoadClickGrid()
		assert.same({ preset = "heals", placement = "outside", side = "top" }, CG.BuffPresets.Current())
	end)

	it("fills one family per corner inside and matches every rank there", function()
		UF, CG = Helpers.LoadClickGrid()
		As("PRIEST", "Priest")
		assert.is_true(CG.BuffPresets.Apply("heals", "inside"))
		local member = CG.Config.styles.member:Resolved()
		assert.is_false(member.auras.buffs.enabled)
		assert.is_true(member.auras.enabled)
		local slots = CG.Config:Resolved().slots
		local expected = { { "139", "TOPLEFT" }, { "17", "TOPRIGHT" }, { "401859", "BOTTOMRIGHT" } }
		for i, want in ipairs(expected) do
			local slot = slots["slot" .. i]
			assert.is_true(slot.enabled)
			assert.equals(want[1], slot.spell)
			assert.equals(want[2], slot.anchor)
			assert.is_true(slot.own)
			assert.equals(0, slot.offsetX)
		end
		for _, id in ipairs({ 139, 25315, 425268 }) do assert.is_true(SlotCandidates(1)[id], id) end
		assert.same({ preset = "heals", placement = "inside", side = "top" }, CG.BuffPresets.Current())
	end)

	it("moves a set between the aura bar and outside without leaving it behind", function()
		UF, CG = Helpers.LoadClickGrid()
		As("DRUID", "Druid")
		assert.is_true(CG.BuffPresets.Apply("heals", "inside"))
		assert.is_true(CG.BuffPresets.Apply("externals", "bar"))
		local member = CG.Config.styles.member:Resolved()
		assert.is_true(member.auraBar.enabled)
		assert.is_true(member.auraBar.buffs.enabled)
		assert.is_false(member.auraBar.debuffs.enabled)
		assert.equals(UF.Components.Auras.EXTERNALS, member.auraBar.buffs.filter)
		assert.is_false(member.auras.buffs.enabled)
		assert.is_true(CG.Config:Resolved().slots.slot1.enabled, "a different set's slots stay")
		assert.same({ preset = "externals", placement = "bar", side = "top" }, CG.BuffPresets.Current())

		assert.is_true(CG.BuffPresets.Apply("heals", "outside", "bottom"))
		member = CG.Config.styles.member:Resolved()
		assert.is_false(member.auraBar.enabled)
		assert.is_true(member.auras.buffs.enabled)
		assert.equals(UF.Components.Auras.MY_HEALS, member.auras.buffs.filter)
		assert.equals("bottom", member.auras.buffs.position)
		local slots = CG.Config:Resolved().slots
		for i = 1, 3 do assert.is_false(slots["slot" .. i].enabled, i) end
		assert.equals("774", slots.slot1.spell)
	end)

	it("keeps the aura bar's debuffs when the bar was already on", function()
		UF, CG = Helpers.LoadClickGrid()
		CG.Config:SetStyle("member", "auraBar.enabled", true)
		assert.is_true(CG.BuffPresets.Apply("raid", "bar"))
		assert.is_true(CG.Config.styles.member:Resolved().auraBar.debuffs.enabled)
		assert.is_true(CG.BuffPresets.Apply("raid", "outside"))
		assert.is_true(CG.Config.styles.member:Resolved().auraBar.enabled)
		assert.is_false(CG.Config.styles.member:Resolved().auraBar.buffs.enabled)
	end)

	describe("Healing buffs page", function()
		before_each(function()
			UF, CG, wb = Helpers.LoadClickGrid(true)
			As("DRUID", "Druid")
			wb:Open("clickgrid.buffs")
		end)

		it("shows the set in all three placements from sample auras", function()
			local cards = wb.handle.cards
			assert.equals(3, #cards)
			local heals = { "Spell_Nature_Rejuvenation", "Spell_Nature_ResistNature", "Ability_Druid_Flourish", "INV_Misc_Herb_Felblossom" }
			assert.same(heals, CardIcons(cards[1]))
			assert.same({ heals[1], heals[2], heals[3] }, CardIcons(cards[2]))
			assert.is_true(#CardIcons(cards[3]) > 0)
			assert.is_true(cards[1].active)
			assert.is_false(cards[2].active)
			assert.equals("BOTTOMRIGHT", select(1, cards[2].slots.samples[3]:GetPoint()))
		end)

		it("applies a choice to the saved settings and marks its card", function()
			local target = wb.styleTarget
			assert.equals("heals", target.get("preset"))
			target.set("placement", "bar")
			local member = CG.Config.styles.member:Resolved()
			assert.is_true(member.auraBar.enabled)
			assert.equals(UF.Components.Auras.MY_HEALS, member.auraBar.buffs.filter)
			assert.is_true(wb.handle.cards[3].active)
			assert.is_false(wb.handle.cards[1].active)
			target.set("preset", "raid")
			assert.equals(UF.Components.Auras.RAID_BUFFS, CG.Config.styles.member:Resolved().auraBar.buffs.filter)
			assert.same({ "Spell_Nature_Thorns", "Spell_Nature_Regeneration" },
				{ CardIcons(wb.handle.cards[1])[1], CardIcons(wb.handle.cards[1])[2] })
		end)

		it("tells a class without heals that there is nothing to show", function()
			As("WARRIOR", "Warrior")
			wb.handle:Apply()
			for _, card in ipairs(wb.handle.cards) do
				assert.same({}, CardIcons(card))
				assert.is_not_nil(card.note:GetText():find("no heals", 1, true))
			end
		end)
	end)
end)
