local Helpers = require("helpers")
local Mock = Helpers.Mock

-- Scenarios and in-game log replays ported from DoesItDie's tools/test_tracking.py.
local SPELLS = {
	[1] = { "Corruption", "Corrupts the target, causing 40 Shadow damage over 12 sec." },
	[2] = { "Rake", "Rake the target for 19 damage and an additional 39 damage over 9 sec.  Awards 1 combo point." },
	[3] = { "Claw", "Claw the enemy, causing 27 additional damage.  Awards 1 combo point." },
	[4] = { "Rip", "Finishing move that causes damage over time. 1 point : 42 damage over 12 sec. 2 points: 71 damage over 12 sec. 5 points: 138 damage over 12 sec." },
	[5] = { "Rend", "Wounds the target causing them to bleed for 45 damage over 9 sec." },
	[6] = { "Bane of Agony", "Afflicts the target with agony, causing 72 Shadow damage over 24 sec.  This damage is dealt slowly at first, and builds up as the Bane reaches its full duration." },
	[7] = { "Serpent Sting", "Stings the target, causing 10 Nature damage over 15 sec.  Only one Sting per Hunter can be active on any one target." },
}

describe("DoT tracker #dots", function()
	local ns, tracker, log, casts, waitMode, changes

	before_each(function()
		ns = Helpers.LoadAddon(true)
		Mock.InstallUI()
		tracker = ns.DotTracker
		for id, spell in pairs(SPELLS) do Mock.spells[id] = { name = spell[1], description = spell[2] } end
		Mock.guids.target = "mob"
		log, casts, waitMode, changes = {}, 0, "off", {}
		tracker:SetTrace(function(message) log[#log + 1] = string.format("%.2f %s", Mock.time, message) end)
		ns.Events.RegisterCallback(changes, "DotsChanged", function(_, key) changes[#changes + 1] = key end)
		tracker:Acquire("spec")
	end)

	after_each(function()
		ns.Events.UnregisterCallback(changes, "DotsChanged")
	end)

	local function Learn(tickKey, perTick) tracker.ticks[tickKey] = perTick end
	local function Send(id)
		casts = casts + 1
		local guid = "cast-" .. casts
		Mock.FireEvent("UNIT_SPELLCAST_SENT", "player", "", guid, id)
		return guid
	end
	local function Succeed(id, guid) Mock.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, id) end
	local function Cast(id) Succeed(id, Send(id)) end
	local function Target(key)
		Mock.guids.target = key
		Mock.FireEvent("PLAYER_TARGET_CHANGED")
	end
	local function Hit(amount, school, flag, unit)
		Mock.FireEvent("UNIT_COMBAT", unit or "target", "WOUND", flag or "", amount, school or 1)
	end
	local function Avoid(action, school, unit) Mock.FireEvent("UNIT_COMBAT", unit or "target", action, "", 0, school or 1) end
	local function Advance(seconds)
		Mock.time = Mock.time + seconds
		tracker.driver:RunScript("OnUpdate", seconds)
	end
	local function Marker()
		local damage, count = tracker:Breakdown(tracker:KeyFor("target"), waitMode)
		return damage .. " dmg from " .. count .. " DoT(s)"
	end
	local function MarkerOn(key) return tracker:Breakdown(key, waitMode) .. " dmg" end
	local function Logged(text)
		for _, line in ipairs(log) do
			if line:find(text, 1, true) then return true end
		end
		return false
	end
	local function Count(text)
		local count = 0
		for _, line in ipairs(log) do
			if line:find(text, 1, true) then count = count + 1 end
		end
		return count
	end

	describe("cast outcomes", function()
		it("shows a learned DoT at once and counts down per tick", function()
			Learn(1, 10); Cast(1)
			assert.equals("40 dmg from 1 DoT(s)", Marker())
			Advance(3); Hit(10, 32)
			assert.equals("30 dmg from 1 DoT(s)", Marker())
		end)

		it("drops a resisted DoT and does not bring it back on a same-school hit", function()
			Learn(1, 10); Cast(1); Advance(0.1); Avoid("RESIST", 32)
			assert.equals("0 dmg from 0 DoT(s)", Marker())
			assert.is_true(Logged("right after Corruption; dropped"))
			Advance(2.9); Hit(10, 32)
			assert.equals("0 dmg from 0 DoT(s)", Marker())
		end)

		it("keeps a landed bleed through a later dodged auto-attack, with its combo point", function()
			Learn(2, 13); Cast(2); Advance(0.05); Hit(19, 1); Advance(0.25); Avoid("DODGE")
			assert.equals("39 dmg from 1 DoT(s)", Marker())
			assert.equals(1, tracker.countedPoints)
		end)

		it("drops a parried bleed and takes its combo point back", function()
			Learn(2, 13); Cast(2); Advance(0.05); Avoid("PARRY")
			assert.equals("0 dmg from 0 DoT(s)", Marker())
			assert.equals(0, tracker.countedPoints)
		end)

		it("drops a DoT whose miss arrives just before the cast event, but not after an old miss", function()
			Learn(1, 10); Avoid("MISS", 32); Advance(0.1); Cast(1)
			assert.equals("0 dmg from 0 DoT(s)", Marker())
			tracker:Release("spec"); tracker:Acquire("spec")
			Learn(1, 10); Avoid("MISS"); Advance(1.0); Cast(1)
			assert.equals("40 dmg from 1 DoT(s)", Marker())
		end)

		it("keeps the ticking DoT when its recast is resisted", function()
			Learn(1, 10); Cast(1); Advance(3); Hit(10, 32); Advance(1)
			Cast(1); Advance(0.1); Avoid("RESIST", 32)
			assert.equals("30 dmg from 1 DoT(s)", Marker())
		end)

		it("ignores the pet's melee avoids next to a spell DoT, but not the spell's own resist", function()
			Learn(6, 6); Cast(6); Advance(0.1); Avoid("DODGE")
			assert.equals("72 dmg from 1 DoT(s)", Marker())
			Advance(0.1); Avoid("RESIST", 32)
			assert.equals("0 dmg from 0 DoT(s)", Marker())
		end)

		it("drops a spell DoT resisted after the pet's melee hit", function()
			Learn(6, 6); Cast(6); Advance(0.05); Hit(30, 1); Advance(0.1); Avoid("RESIST", 32)
			assert.equals("0 dmg from 0 DoT(s)", Marker())
		end)

		it("makes a spell DoT wait for its first tick after a miss in another school", function()
			Learn(6, 6); Cast(6); Advance(0.1); Avoid("MISS", 1)
			assert.equals("0 dmg from 0 DoT(s)", Marker())
			Advance(1.9); Hit(3, 32)
			assert.equals("69 dmg from 1 DoT(s)", Marker())
		end)

		it("drops a doubted spell DoT that never ticks", function()
			Learn(6, 6); Cast(6); Advance(0.1); Avoid("MISS", 1); Advance(5)
			assert.is_true(Logged("DROP Bane of Agony"))
		end)

		it("leaves the target's DoT alone when another mob resists", function()
			Learn(6, 6); Mock.guids.focus = "other"; Cast(6); Advance(0.1)
			Avoid("RESIST", 32, "focus")
			assert.equals("72 dmg from 1 DoT(s)", Marker())
		end)

		it("drops a parried physical DoT straight away", function()
			Learn(5, 15); Cast(5); Advance(0.05); Avoid("PARRY")
			assert.equals("0 dmg from 0 DoT(s)", Marker())
		end)
	end)

	describe("tick matching", function()
		it("replay: a Shadow Bolt landing with the first tick is swapped out", function()
			Cast(1); Advance(3.0); Hit(26, 32); Hit(10, 32)
			assert.equals("30 dmg from 1 DoT(s)", Marker())
			assert.is_true(Logged("SWAP Corruption tick: 26 was another hit, 10 is the tick"))
		end)

		it("does not swap when the tick comes first", function()
			Learn(1, 10); Cast(1); Advance(3.0); Hit(10, 32); Hit(26, 32)
			assert.equals("30 dmg from 1 DoT(s)", Marker())
		end)

		it("replay: relearns a wrong tick size from two ticks on the DoT's rhythm", function()
			Learn(1, 29); Cast(1)
			Advance(3.0); Hit(11, 32)
			assert.equals("116 dmg from 1 DoT(s)", Marker())
			Advance(3.0); Hit(10, 32)
			assert.equals("21 dmg from 1 DoT(s)", Marker())
			assert.equals(10.5, tracker.ticks[1])
			Advance(3.0); Hit(11, 32)
			assert.equals("11 dmg from 1 DoT(s)", Marker())
		end)

		it("does not relearn from two off-rhythm hits", function()
			Learn(1, 10); Cast(1)
			Advance(1.0); Hit(26, 32); Advance(1.0); Hit(27, 32)
			assert.equals(10, tracker.ticks[1])
		end)

		it("replay: follows Bane of Agony's back-loaded ramp", function()
			Cast(6)
			assert.equals("72 dmg from 1 DoT(s)", Marker())
			local remaining = {}
			for _, amount in ipairs({ 3, 3, 3, 3, 6, 6, 6, 6, 9, 9, 9, 9 }) do
				Advance(2.0); Hit(amount, 32)
				remaining[#remaining + 1] = Marker():match("^%d+")
			end
			assert.same({ "69", "66", "63", "60", "54", "48", "42", "36", "27", "18", "9", "0" }, remaining)
			assert.equals(12, Count("TICK Bane of Agony"))
			assert.is_false(Logged("RELEARN") or Logged("not matched"))
			assert.equals(6, tracker.ticks[6])
			Advance(3.0); Cast(6)
			assert.equals("72 dmg from 1 DoT(s)", Marker())
		end)

		it("replay: a missed Rip stays gone through white hits near its tick times", function()
			Learn("4x2", 15.2)
			Cast(3); Advance(0.05); Hit(20, 1); Advance(1); Cast(3); Advance(0.05); Hit(20, 1)
			Advance(1); Cast(4); Avoid("MISS")
			for _, step in ipairs({ { 0.8, 20 }, { 1.8, 20 }, { 1.0, 21 }, { 0.9, 22 }, { 1.8, 20 } }) do
				Advance(step[1]); Hit(step[2], 1)
			end
			assert.equals("0 dmg from 0 DoT(s)", Marker())
		end)

		it("replay: a landed Rip matches exactly its four ticks among same-sized white hits", function()
			for _ = 1, 3 do
				Cast(3); Advance(0.05); Hit(20, 1); Advance(1)
			end
			local start = 0
			Cast(4)
			local castAt = Mock.time
			for _, event in ipairs({ { 0.9, 21 }, { 1.3, 20 }, { 1.9, 21 }, { 2.5, 21 }, { 3.5, 20 }, { 3.9, 21 },
				{ 4.3, 22 }, { 5.5, 22 }, { 6.0, 20 }, { 6.8, 46 }, { 8.0, 20 } }) do
				Advance(event[1] - start); start = event[1]
				Hit(event[2], 1)
			end
			local ticks = {}
			for _, line in ipairs(log) do
				local at = line:match("^(%S+) TICK Rip")
				if at then ticks[#ticks + 1] = math.floor((tonumber(at) - castAt) * 10 + 0.5) / 10 end
			end
			assert.same({ 1.9, 3.9, 6.0, 8.0 }, ticks)
			assert.is_true(Logged("3 combo points (counted)"))
		end)

		it("tells Rend's ticks and crits from white hits", function()
			Learn(5, 15); Cast(5)
			Advance(2.95); Hit(20, 1)
			assert.equals("45 dmg from 1 DoT(s)", Marker())
			Advance(0.05); Hit(15, 1)
			assert.equals("30 dmg from 1 DoT(s)", Marker())
			Advance(0.15); Hit(15, 1)
			assert.equals("30 dmg from 1 DoT(s)", Marker())
			Advance(0.85); Hit(15, 1)
			assert.equals("30 dmg from 1 DoT(s)", Marker())
			Advance(1.95); Hit(41, 1, "CRITICAL")
			assert.equals("30 dmg from 1 DoT(s)", Marker())
			Advance(0.05); Hit(30, 1, "CRITICAL")
			assert.equals("15 dmg from 1 DoT(s)", Marker())
			assert.is_not_nil(log[#log]:find("expecting 15.0 for this tick", 1, true))
		end)

		it("counts combo points from builders, minus dodged ones", function()
			Cast(3); Advance(0.05); Hit(27, 1); Advance(1); Cast(3); Advance(0.05); Avoid("DODGE")
			Advance(1); Cast(3); Advance(0.05); Hit(27, 1)
			assert.equals(2, tracker.countedPoints)
			Advance(1); Cast(4)
			assert.is_true(Logged("2 combo points (counted)"))
		end)

		it("replay: matches a projectile DoT's late first tick and keeps its landing rhythm", function()
			Cast(7)
			Advance(2.2); Hit(28, 64); Hit(15, 1)
			Advance(1.5); Hit(4, 8)
			assert.is_true(Logged("TICK Serpent Sting 4"))
			Advance(0.5); Hit(13, 1); Advance(2.1); Hit(14, 1)
			assert.is_false(Logged("DROP"))
			local remaining
			for index, amount in ipairs({ 3, 3, 3, 4 }) do
				Advance(index == 1 and 0.4 or 3.0)
				Hit(amount, 8)
				remaining = Marker():match("^%d+")
			end
			assert.equals(5, Count("TICK Serpent Sting"))
			assert.equals("0", remaining)
			Advance(1.0)
			assert.is_true(Logged("EXPIRE Serpent Sting"))
		end)

		it("loses no tick while a projectile is in flight, yet drops one that never ticks", function()
			Learn(7, 3); Cast(7); Advance(3.7)
			assert.equals("15 dmg from 1 DoT(s)", Marker())
			Advance(3.5); Advance(3.0)
			assert.is_true(Logged("DROP Serpent Sting"))
		end)

		it("does not accept a late tick from a DoT without travel time", function()
			Learn(1, 10); Cast(1); Advance(3.8); Hit(10, 32)
			assert.is_false(Logged("TICK Corruption"))
		end)
	end)

	describe("mobs and units", function()
		it("puts a tab-dotted DoT on the mob targeted when the cast was sent", function()
			Target("A"); local guid = Send(6); Target("B"); Succeed(6, guid)
			assert.equals("72 dmg", MarkerOn("A"))
			assert.equals("0 dmg from 0 DoT(s)", Marker())
			assert.is_true(Logged("on A, the target when sent"))
		end)

		it("keeps DoTs on a mob whose ticks cannot be seen until they expire", function()
			Learn(1, 10); Target("A"); Cast(1); Advance(0.5); Target("B"); Advance(9)
			assert.equals("10 dmg", MarkerOn("A"))
			assert.is_false(Logged("DROP"))
			Target("A")
			assert.equals("10 dmg from 1 DoT(s)", Marker())
			Advance(3)
			assert.equals("0 dmg", MarkerOn("A"))
		end)

		it("drops a DoT that never ticks on a focused mob, and counts ticks seen on the focus", function()
			Learn(1, 10); Target("A"); Cast(1); Target("B"); Mock.guids.focus = "A"; Advance(7)
			assert.is_true(Logged("DROP Corruption"))
			tracker:Release("spec"); tracker:Acquire("spec")
			Learn(1, 10); Target("A"); Cast(1); Target("B")
			Advance(3); Hit(10, 32, "", "focus")
			assert.equals("30 dmg", MarkerOn("A"))
		end)

		it("counts a hit reported for both target and focus once", function()
			Learn(1, 10); Mock.guids.focus = "mob"; Cast(1)
			Advance(3); Hit(10, 32); Hit(10, 32, "", "focus")
			assert.equals("30 dmg from 1 DoT(s)", Marker())
			assert.equals(1, Count("TICK Corruption"))
		end)

		it("tracks the current target only while its GUID is secret", function()
			Learn(1, 10)
			Mock.guids.target = Mock.Secret("Creature-0-1")
			assert.equals("target", tracker:KeyFor("target"))
			Mock.guids.focus = Mock.Secret("Creature-0-2")
			assert.is_nil(tracker:KeyFor("focus"))
			Cast(1)
			assert.equals("40 dmg from 1 DoT(s)", Marker())
			changes = {}
			Target(Mock.Secret("Creature-0-3"))
			assert.equals("0 dmg from 0 DoT(s)", Marker())
			assert.same({ "target" }, changes)
		end)

		it("ignores secret spellcast payloads and combat values", function()
			Learn(1, 10)
			Mock.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-x", Mock.Secret(1))
			Mock.FireEvent("UNIT_SPELLCAST_SENT", "player", "", Mock.Secret("cast-y"), 1)
			assert.equals("0 dmg from 0 DoT(s)", Marker())
			Cast(1); Advance(3)
			Hit(Mock.Secret(10), 32)
			Hit(10, Mock.Secret(32))
			Mock.FireEvent("UNIT_COMBAT", "target", Mock.Secret("WOUND"), "", 10, 32)
			assert.equals("40 dmg from 1 DoT(s)", Marker())
		end)
	end)

	describe("waiting for the first tick", function()
		it("hides an unlearned DoT until its first tick when unsure", function()
			waitMode = "unsure"
			Cast(1)
			assert.equals("0 dmg from 0 DoT(s)", Marker())
			Advance(3); Hit(10, 32)
			assert.equals("30 dmg from 1 DoT(s)", Marker())
		end)

		it("hides even a learned DoT until it ticks when always waiting, per reader", function()
			Learn(1, 10); Cast(1)
			waitMode = "always"
			assert.equals("0 dmg from 0 DoT(s)", Marker())
			waitMode = "off"
			assert.equals("40 dmg from 1 DoT(s)", Marker())
		end)
	end)

	describe("lifecycle and cost", function()
		it("listens to nothing until acquired and forgets everything once released by all owners", function()
			tracker:Release("spec")
			assert.is_false(tracker.events:IsEventRegistered("UNIT_COMBAT"))
			tracker:Acquire("a"); tracker:Acquire("b")
			assert.is_true(tracker.events:IsEventRegistered("UNIT_COMBAT"))
			assert.is_true(tracker.events:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED"))
			Learn(1, 10); Cast(1)
			tracker:Release("a")
			assert.equals("40 dmg from 1 DoT(s)", Marker())
			tracker:Release("b")
			assert.is_false(tracker.events:IsEventRegistered("UNIT_COMBAT"))
			assert.is_nil(tracker.driver:GetScript("OnUpdate"))
			assert.same({}, tracker.dots)
			assert.equals(10, tracker.ticks[1])
		end)

		it("only runs its update while DoTs exist and only works at the next deadline", function()
			assert.is_nil(tracker.driver:GetScript("OnUpdate"))
			Learn(1, 10); Cast(1)
			assert.equals("function", type(tracker.driver:GetScript("OnUpdate")))
			Advance(0.01)
			changes = {}
			Advance(1)
			assert.same({}, changes)
			assert.equals(103.45, math.floor(tracker.deadline * 100 + 0.5) / 100)
			Advance(12)
			assert.same({ "mob" }, changes)
			assert.is_true(Logged("EXPIRE Corruption"))
			assert.is_nil(tracker.driver:GetScript("OnUpdate"))
		end)

		it("announces casts, ticks and drops of a mob but not unmatched hits", function()
			Learn(1, 10); Cast(1)
			assert.same({ "mob" }, changes)
			Advance(1.5); Hit(99, 32)
			assert.same({ "mob" }, changes)
			Advance(1.5); Hit(10, 32)
			assert.same({ "mob", "mob" }, changes)
		end)

		it("fills a reused breakdown oldest first, with each DoT's share", function()
			Learn(1, 10); Learn(6, 6); Cast(6); Advance(0.5); Cast(1)
			local out = { { name = "stale" }, { name = "stale" }, { name = "stale" } }
			local first = out[1]
			local total, count, list = tracker:Breakdown("mob", "off", out)
			assert.equals(out, list)
			assert.is_true(out[1] == first or out[2] == first)
			assert.equals(112, total)
			assert.equals(2, count)
			assert.equals(2, #out)
			assert.equals("Bane of Agony", out[1].name)
			assert.equals(72, out[1].damage)
			assert.equals("Corruption", out[2].name)
			assert.equals(1, out[2].spellID)
			assert.equals(32, out[2].school)
			assert.equals(0, select(2, tracker:Breakdown(nil, "off", out)))
		end)

		it("keeps learned tick sizes account-wide in the saved variables and resets old versions", function()
			Cast(1); Advance(3); Hit(11, 32)
			assert.equals(11, UnitFramesDB.global.dotTicks[1])
			assert.equals(1, UnitFramesDB.global.dotTicksVersion)
			tracker:ResetLearned()
			assert.same({}, UnitFramesDB.global.dotTicks)
			tracker:Release("spec")
			UnitFramesDB.global.dotTicks, UnitFramesDB.global.dotTicksVersion = { [1] = 50 }, 0
			tracker:Acquire("spec")
			assert.same({}, tracker.ticks)
		end)

		it("toggles tracking with its trace in chat through /uf dots", function()
			tracker:Release("spec")
			tracker:SetTrace(nil)
			local messages = {}
			ns.Print = function(_, ...) messages[#messages + 1] = table.concat({ ... }, " ") end
			SlashCmdList.UNITFRAMES("dots")
			assert.is_true(tracker:IsActive())
			Learn(1, 10); Cast(1)
			assert.is_not_nil(messages[#messages]:find("CAST Corruption", 1, true))
			SlashCmdList.UNITFRAMES("dots reset")
			assert.same({}, tracker.ticks)
			SlashCmdList.UNITFRAMES("dots")
			assert.is_false(tracker:IsActive())
			assert.is_nil(tracker.trace)
		end)
	end)
end)
