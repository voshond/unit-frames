local Helpers = require("helpers")

describe("My heals & shields buff filter #buffs", function()
	local ns, Auras

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Auras = ns.Components.Auras
	end)

	local function PlayAs(class)
		UnitClass = function() return class, class, 1 end
	end

	local function Count(set)
		local count = 0
		for _ in pairs(set) do count = count + 1 end
		return count
	end

	it("passes the player's own heal, shield and proc families as native include IDs", function()
		PlayAs("DRUID")
		local filters = Auras.CandidateFilters({ filter = Auras.MY_HEALS, maxDuration = 0 })
		assert.is_nil(filters.maxDuration)
		for _, id in ipairs({ 774, 25299, 417057, 9858, 436937, 408124, 408120 }) do
			assert.is_true(filters.includeSpellIDs[id], id)
		end
		assert.is_nil(filters.includeSpellIDs[139])
		assert.equals("HELPFUL|PLAYER", Auras.GroupFilter("buffs", Auras.MY_HEALS))
		PlayAs("PRIEST")
		local priest = Auras.CandidateFilters({ filter = Auras.MY_HEALS, maxDuration = 60 }).includeSpellIDs
		assert.is_true(priest[17] and priest[139] and priest[401877])
		PlayAs("SHAMAN")
		assert.is_true(Auras.IncludeSpellIDs(Auras.MY_HEALS)[974])
	end)

	it("gives non-healing classes an empty include list, so nothing passes", function()
		for _, class in ipairs({ "WARRIOR", "ROGUE", "HUNTER", "WARLOCK" }) do
			PlayAs(class)
			assert.equals(0, Count(Auras.CandidateFilters({ filter = Auras.MY_HEALS, maxDuration = 0 }).includeSpellIDs), class)
		end
	end)

	it("falls back to every class's heals while the player's class is opaque", function()
		UnitClass = function() return Helpers.Mock.Secret("Druid"), Helpers.Mock.Secret("DRUID"), 11 end
		local ids = Auras.IncludeSpellIDs(Auras.MY_HEALS)
		assert.is_true(ids[774] and ids[17] and ids[408521])
	end)

	it("keeps plain filters free of include IDs", function()
		assert.is_nil(Auras.CandidateFilters({ filter = "HELPFUL|PLAYER", maxDuration = 0 }))
		assert.same({ maxDuration = 30 }, Auras.CandidateFilters({ filter = "HELPFUL|PLAYER|RAID_IN_COMBAT", maxDuration = 30 }))
	end)

	it("applies include IDs only when they change, like maxDuration", function()
		PlayAs("DRUID")
		local calls, count = {}, 0
		local container = { SetAuraGroupCandidateFilters = function(_, _, filters)
			count = count + 1
			calls[count] = filters
		end }
		local group = { filter = "HELPFUL|PLAYER", maxDuration = 0 }
		Auras.ApplyGroupCandidates(container, "buffs", group)
		Auras.ApplyGroupCandidates(container, "buffs", group)
		assert.equals(1, count)
		assert.is_nil(calls[1])
		group.filter = Auras.MY_HEALS
		Auras.ApplyGroupCandidates(container, "buffs", group)
		Auras.ApplyGroupCandidates(container, "buffs", { filter = Auras.MY_HEALS, maxDuration = 0 })
		assert.equals(2, count)
		assert.is_true(calls[2].includeSpellIDs[774])
		group.maxDuration = 45
		Auras.ApplyGroupCandidates(container, "buffs", group)
		assert.equals(3, count)
		assert.same(45, calls[3].maxDuration)
		PlayAs("PRIEST")
		Auras.ApplyGroupCandidates(container, "buffs", group)
		assert.equals(4, count)
		assert.is_true(calls[4].includeSpellIDs[17])
	end)

	it("matches samples only when their spell is in the include list", function()
		PlayAs("DRUID")
		local include = Auras.IncludeSpellIDs(Auras.MY_HEALS)
		local rejuvenation = { spellId = 9841, sourceUnit = "player", duration = 12 }
		local renew = { spellId = 139, sourceUnit = "player", duration = 15 }
		assert.is_true(Auras.MatchesSampleFilter(rejuvenation, "HELPFUL|PLAYER", 0, include))
		assert.is_false(Auras.MatchesSampleFilter(renew, "HELPFUL|PLAYER", 0, include))
		assert.is_false(Auras.MatchesSampleFilter({ spellId = 774, sourceUnit = "party1", duration = 12 }, "HELPFUL|PLAYER", 0, include))
		assert.is_true(Auras.MatchesSampleFilter(renew, "HELPFUL|PLAYER", 0))
	end)

	it("keeps the raid-in-combat choice with a label that says what it covers", function()
		local labels = {}
		for _, entry in ipairs(Auras.BUFF_FILTERS) do labels[entry[1]] = entry[2] end
		assert.equals("My heals & shields", labels[Auras.MY_HEALS])
		assert.equals("My raid-flagged buffs (no shields)", labels["HELPFUL|PLAYER|RAID_IN_COMBAT"])
	end)
end)
