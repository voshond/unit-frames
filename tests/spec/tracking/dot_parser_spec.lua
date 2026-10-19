local Helpers = require("helpers")

describe("DoT description parser #dots", function()
	local Parser

	before_each(function()
		Parser = Helpers.LoadAddon().DotParser
	end)

	-- DoesItDie's own summary format, so its reviewed snapshot compares directly.
	local function Summary(name, desc, points)
		if Parser.IGNORED[name] then return "ignored (list)" end
		local dot = Parser.Describe(name, desc, points)
		if not dot then return "not tracked" end
		return string.format("%d dmg, school %d, %gs, every %gs -> %d ticks of %.1f",
			dot.total, dot.school, dot.duration, dot.interval, dot.totalTicks, dot.total / dot.totalTicks)
	end

	it("matches the reviewed result for every damage tooltip in Forever's spellbook", function()
		local spellbook = dofile("tests/fixtures/forever_dot_spellbook.lua")
		local tracked = 0
		for _, spell in ipairs(spellbook) do
			local points = spell.tooltip:find("Finishing move", 1, true) and 5 or nil
			assert.equals(spell.expected, Summary(spell.name, spell.tooltip, points), spell.key)
			if spell.expected:match("^%d") then tracked = tracked + 1 end
		end
		assert.equals(215, #spellbook)
		assert.is_true(tracked > 20)
	end)

	it("takes the periodic part after a direct hit", function()
		assert.equals("20 dmg, school 4, 15s, every 3s -> 5 ticks of 4.0", Summary("Immolate",
			"Burns the enemy for 11 Fire damage and then an additional 20 Fire damage over 15 sec."))
		assert.equals("39 dmg, school 20, 9s, every 3s -> 3 ticks of 13.0", Summary("Frostfire Bolt",
			"Launches a bolt of frostfire at the enemy, causing 412 Frostfire damage, slowing movement speed by 40% and causing an additional 39 Frostfire damage over 9 sec."))
	end)

	it("reads per-tick drains, known intervals and uneven tick shapes", function()
		assert.equals("150 dmg, school 32, 30s, every 3s -> 10 ticks of 15.0", Summary("Siphon Life",
			"Transfers 15 health from the target to the caster every 3 sec.  Lasts 30 sec."))
		assert.equals("84 dmg, school 32, 24s, every 2s -> 12 ticks of 7.0", Summary("Bane of Agony",
			"Banes the target with agony, causing 84 Shadow damage over 24 sec."))
		assert.is_not_nil(Parser.Describe("Bane of Agony", "causing 84 Shadow damage over 24 sec.").shape)
		assert.equals(1.5, Parser.Describe("Serpent Sting", "causing 20 Nature damage over 15 sec.").travel)
	end)

	it("reads finishers at the given combo points, including Forever's stray space", function()
		local rip = "Finishing move that causes damage over time. Damage increases per combo point and by your Attack Power: 1 point : 243 damage over 12 sec. 2 points: 396 damage over 12 sec. 3 points: 549 damage over 12 sec. 4 points: 702 damage over 12 sec. 5 points: 855 damage over 12 sec."
		assert.equals("243 dmg, school 1, 12s, every 2s -> 6 ticks of 40.5", Summary("Rip", rip, 1))
		assert.equals("855 dmg, school 1, 12s, every 2s -> 6 ticks of 142.5", Summary("Rip", rip, 5))
		local rupture = "Finishing move that causes damage over time, increased by your attack power. Lasts longer per combo point:\n   1 point: 25 damage over 8 secs\n   2 points: 36 damage over 10 secs\n   3 points: 50 damage over 12 secs\n   4 points: 66 damage over 14 secs\n   5 points: 87 damage over 16 secs"
		assert.equals("50 dmg, school 1, 12s, every 2s -> 6 ticks of 8.3", Summary("Rupture", rupture, 3))
		assert.equals("not tracked", Summary("Eviscerate",
			"Finishing move that causes damage per combo point:\n   1 point: 6-11 damage\n   5 points: 30-35 damage", 5))
		assert.is_true(Parser.IsFinisher(rip))
		assert.equals(1, Parser.AwardedComboPoints("Rake the target for 19 damage.  Awards 1 combo point."))
	end)

	it("ignores areas, channels, weapon poisons, heals, delayed damage and unreadable text", function()
		assert.equals("ignored (list)", Summary("Rain of Fire", "burn enemies for 240 Fire damage over 8 sec."))
		assert.equals("not tracked", Summary("Deadly Poison",
			"Coats a weapon with poison that lasts for 30 minutes.  Each strike has a 30% chance of poisoning the enemy for 36 Nature damage over 12 sec."))
		assert.equals("not tracked", Summary("Renew", "Heals the target of 830 damage over 15 sec."))
		assert.equals("not tracked", Summary("Curse of Doom", "causing 3200 Shadow damage after 1 min."))
		assert.is_nil(Parser.Describe("Corruption", nil))
		assert.is_nil(Parser.Describe("Corruption", Helpers.Mock.Secret("causing 40 Shadow damage over 12 sec.")))
	end)
end)
