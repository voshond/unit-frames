local Helpers = require("helpers")

describe("Generated buff catalogue #buffs", function()
	local catalog

	before_each(function()
		catalog = Helpers.LoadAddon().BuffCatalog
	end)

	local function contains(ids, wanted)
		for _, id in ipairs(ids) do
			if id == wanted then
				return true
			end
		end
		return false
	end

	it("expands any Rejuvenation rank to both rank sets", function()
		local rejuvenation = catalog.families[774]
		assert.equals("Rejuvenation", rejuvenation.name)
		assert.equals("DRUID", rejuvenation.class)
		assert.equals("hot", rejuvenation.kind)
		for _, id in ipairs({ 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299, 417057, 417062, 417068 }) do
			assert.is_true(contains(rejuvenation.ids, id), id)
			assert.equals(774, catalog.byId[id])
		end
	end)

	it("lists the core heals and shields of every healing class", function()
		local expected = {
			[139] = { "Renew", "PRIEST", "hot" },
			[8936] = { "Regrowth", "DRUID", "hot" },
			[17] = { "Power Word: Shield", "PRIEST", "absorb" },
			[408521] = { "Riptide", "SHAMAN", "hot" },
			[408124] = { "Lifebloom", "DRUID", "hot" },
			[408120] = { "Wild Growth", "DRUID", "hot" },
			[408514] = { "Earth Shield", "SHAMAN", "proc" },
			[401859] = { "Prayer of Mending", "PRIEST", "proc" },
		}
		for root, fields in pairs(expected) do
			local family = catalog.families[root]
			assert.same(fields, { family.name, family.class, family.kind })
		end
		assert.equals(139, catalog.byId[25315])
		assert.equals(17, catalog.byId[10901])
		assert.equals(401859, catalog.byId[401877])
	end)

	it("maps every family member back to its root", function()
		for root, family in pairs(catalog.families) do
			for _, id in ipairs(family.ids) do
				assert.equals(root, catalog.byId[id])
			end
		end
	end)

	it("flags only the raid-in-combat rank set", function()
		assert.is_true(catalog.raidInCombat[417057])
		assert.is_nil(catalog.raidInCombat[774])
		assert.is_nil(catalog.raidInCombat[17])
	end)

	it("gives non-healing classes no heal families", function()
		local healers = {}
		for _, family in pairs(catalog.families) do
			if family.kind == "hot" or family.kind == "absorb" or family.kind == "proc" then
				healers[family.class] = true
			end
		end
		assert.same({ DRUID = true, MAGE = true, PALADIN = true, PRIEST = true, SHAMAN = true }, healers)
	end)
end)
