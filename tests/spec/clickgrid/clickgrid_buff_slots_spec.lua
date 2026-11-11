local Helpers = require("helpers")

describe("ClickGrid fixed buff slots match every rank #buffs", function()
	local UF, CG, slots

	before_each(function()
		UF, CG = Helpers.LoadClickGrid()
		slots = CG:GetGridButton(CG.headers.party:GetAttribute("child1").Member).slots
	end)

	local function Candidates()
		return slots.container.__state.slots.slot1.candidateFilters.includeSpellIDs
	end

	it("lists every Rejuvenation rank of both ID sets for a slot set to 774", function()
		CG.Config:Set("slots.slot1.spell", "774")
		CG.Config:Set("slots.slot1.enabled", true)
		for _, id in ipairs({ 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299, 417057, 417062, 417068 }) do
			assert.is_true(Candidates()[id], id)
		end
		assert.equals("774", CG.Config:Get().slots.slot1.spell)
	end)

	it("passes unknown IDs through beside expanded families", function()
		CG.Config:Set("slots.slot1.spell", "2061, 139")
		CG.Config:Set("slots.slot1.enabled", true)
		assert.is_true(Candidates()[2061])
		assert.is_true(Candidates()[25315])
		assert.is_true(Candidates()[425268])
		assert.is_nil(Candidates()[774])
	end)

	it("keeps native candidates when another rank of the same family is typed", function()
		CG.Config:Set("slots.slot1.spell", "774")
		CG.Config:Set("slots.slot1.enabled", true)
		local calls, set = 0, slots.container.SetAuraSlotCandidateFilters
		slots.container.SetAuraSlotCandidateFilters = function(...)
			calls = calls + 1
			return set(...)
		end
		CG.Config:Set("slots.slot1.spell", "9841, 417060")
		assert.equals(0, calls)
		CG.Config:Set("slots.slot1.spell", "139")
		assert.equals(1, calls)
	end)

	it("shows a druid's rank 10 Rejuvenation on a slot set to rank 1", function()
		CG.Config:Set("slots.slot1.spell", "774")
		CG.Config:Set("slots.slot1.own", false)
		CG.Config:Set("slots.slot1.enabled", true)
		assert.is_true(Candidates()[9841])
		local rejuvenation = UF.Util.Copy(UF.Units.SAMPLE.buffs[4])
		rejuvenation.spellId = 9841
		slots:ShowSample({ buffs = { rejuvenation } })
		assert.is_true(slots.samples[1]:IsShown())
	end)

	it("writes a picked family's root ID and stores no picker value", function()
		assert.is_true(CG.Config:Set("slots.slot1.spell", "2061"))
		assert.is_true(CG.Config:Set("slots.slot1.family", 408521))
		local slot = CG.Config:Get().slots.slot1
		assert.equals("408521", slot.spell)
		assert.is_nil(slot.family)
		assert.is_true(CG.Config:Set("slots.slot1.family", ""))
		assert.equals("408521", CG.Config:Get().slots.slot1.spell)
	end)

	it("offers every catalogued family once in the picker, by class then name", function()
		local values = UF.Schema.GetValues(UF.Schema.Find(CG.SlotSchema, "slot1.family"))
		assert.same({ "", "Pick a spell" }, values[1])
		local seen, count = {}, 0
		for i = 2, #values do
			local root = values[i][1]
			assert.is_nil(seen[root])
			seen[root], count = true, count + 1
		end
		for _ in pairs(UF.BuffCatalog.families) do count = count - 1 end
		assert.equals(0, count)
		assert.is_true(seen[774])
	end)
end)
