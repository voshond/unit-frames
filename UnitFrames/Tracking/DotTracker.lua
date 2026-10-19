local _, ns = ...
local DotParser = ns.DotParser

--[[
Estimates the damage the player's DoTs still have to deal per mob (ported
from DoesItDie, MIT, Licenses/DoesItDie-MIT.txt). Target health, auras and
combat logs are out of reach on Forever, so a cast's description gives the
first estimate and UNIT_COMBAT hits on the target or focus, matched by
school, rhythm and size, replace it with the real tick size.

  Acquire(owner) / Release(owner)   events run only while someone listens
  Breakdown(key, waitMode, out)     total, count and per-DoT entries for a mob
  KeyFor(unit)                      the mob key behind a unit token

Fires ns.Events "DotsChanged"(key) whenever a mob's estimate changes. Work
only happens on events and at the next deadline (a late tick, an expiry).
All values are the addon's own plain numbers; no secret is ever compared.
]]
local DotTracker = ns.Object:Extend("DotTracker")

-- Ticks land within ~0.1s of their rhythm; tight windows keep same-school melee out.
local TICK_MATCH_WINDOW = 0.45
local TICK_MATCH_WINDOW_ANCHORED = 0.25
local MISSED_TICKS_BEFORE_DROP = 2
local TICK_AMOUNT_TOLERANCE = 0.25
local FIRST_TICK_AMOUNT_TOLERANCE = 0.3
local CRIT_MIN_RATIO, CRIT_MAX_RATIO = 1.3, 2.3
local SAME_SLOT_SECONDS = 0.2
-- A cast's own outcome arrives almost at once, sometimes just before the cast event.
local OUTCOME_WINDOW = 0.4
local OUTCOME_LOOKBACK = 0.25
local SENT_TARGET_SECONDS = 10
local COMBO_CAP = 5
local COMBO_CACHE_SECONDS = 3
local TICKS_VERSION = 1
local PHYSICAL = DotParser.SCHOOLS.Physical

DotTracker.WAIT_MODES = {
	{ "off", "Never (estimate straight away)" },
	{ "unsure", "When unsure" },
	{ "always", "Always (real ticks only)" },
}

local AVOIDED = {
	MISS = true, DODGE = true, PARRY = true, EVADE = true, IMMUNE = true, DEFLECT = true, RESIST = true, REFLECT = true,
}
local MELEE_ONLY_AVOIDS = { DODGE = true, PARRY = true, DEFLECT = true }

local function Trace(self, fmt, ...)
	if self.trace then self.trace(string.format(fmt, ...)) end
end

local function ByApplied(a, b)
	return a.appliedAt < b.appliedAt
end

function DotTracker:Init()
	self.owners, self.dots, self.sentTargets, self.lastCombat = {}, {}, {}, {}
	self.ticks, self.deadline = {}, 0
	self:ResetCombat()
	self.events = CreateFrame("Frame")
	self.events:SetScript("OnEvent", function(_, event, ...) self[event](self, ...) end)
	self.driver = CreateFrame("Frame")
	self.onUpdate = function()
		local now = GetTime()
		if now >= self.deadline then self:Housekeep(now) end
	end
end

function DotTracker:ResetCombat()
	self.countedPoints, self.comboAtSend, self.lastComboPoints, self.lastComboAt = 0, nil, nil, 0
	self.lastBuilder, self.lastDotCast, self.lastOutcome = nil, nil, nil
end

-- Lifecycle ------------------------------------------------------------------

function DotTracker:Acquire(owner)
	if not self:IsActive() then self:Start() end
	self.owners[owner] = true
end

function DotTracker:Release(owner)
	if not self.owners[owner] then return end
	self.owners[owner] = nil
	if not self:IsActive() then self:Stop() end
end

function DotTracker:IsActive()
	return next(self.owners) ~= nil
end

function DotTracker:Start()
	self.ticks = self:LearnedTicks()
	local events = self.events
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	events:RegisterUnitEvent("UNIT_COMBAT", "target", "focus")
	local _, class = UnitClass("player")
	if not issecretvalue(class) and ns.Units.COMBO_POINT_CLASSES[class] then
		events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	end
end

function DotTracker:Stop()
	self.events:UnregisterAllEvents()
	self.driver:SetScript("OnUpdate", nil)
	wipe(self.dots)
	wipe(self.sentTargets)
	self:ResetCombat()
end

-- Account-wide: tick sizes belong to the character's spells, not a style.
function DotTracker:LearnedTicks()
	local db = ns.Config.db
	if not db then return self.ticks end
	local global = db.global
	if global.dotTicksVersion ~= TICKS_VERSION then
		global.dotTicks, global.dotTicksVersion = {}, TICKS_VERSION
	end
	return global.dotTicks
end

function DotTracker:ResetLearned()
	wipe(self:LearnedTicks())
end

function DotTracker:SetTrace(fn)
	self.trace = fn
end

-- A hidden GUID (restricted content) leaves only the current target trackable.
function DotTracker:KeyFor(unit)
	local guid = UnitGUID(unit)
	if issecretvalue(guid) then return unit == "target" and "target" or nil end
	return guid
end

function DotTracker:IsObservable(key)
	return self:KeyFor("target") == key or self:KeyFor("focus") == key
end

function DotTracker:Changed(key)
	self.deadline = 0
	self.driver:SetScript("OnUpdate", self.onUpdate)
	ns.Events:Fire("DotsChanged", key)
end

-- Tick arithmetic --------------------------------------------------------------

local function ExpectedTick(self, dot)
	if dot.normalTicks > 0 then return dot.tickSum / dot.normalTicks end
	return (dot.tickKey and self.ticks[dot.tickKey]) or dot.total / dot.totalTicks
end

local function TickNumberAt(dot, when)
	return math.max(1, math.floor((when - dot.appliedAt) / dot.interval + 0.5))
end

-- Uneven DoTs (DotParser.TICK_SHAPES) scale each tick; shapes stretch to the tick count.
local function TickShape(dot, number)
	local shape = dot.shape
	if not shape then return 1 end
	local i = math.ceil(math.min(math.max(number, 1), dot.totalTicks) / dot.totalTicks * #shape)
	return shape[math.max(1, math.min(i, #shape))]
end

-- Anchored on the first tick once seen, else on the cast; a projectile may
-- still be in flight for up to its travel time.
local function DistanceToExpectedTick(dot, now)
	local anchor = dot.firstTickAt or dot.appliedAt
	if not dot.firstTickAt and dot.travel then
		local late = now - (anchor + dot.interval)
		if late > 0 then anchor = anchor + math.min(late, dot.travel) end
	end
	local k = math.max(1, math.floor((now - anchor) / dot.interval + 0.5))
	return math.abs(now - (anchor + k * dot.interval)), k
end

local function PlausibleTickAmount(self, dot, amount, isCrit, number)
	local known, tolerance
	if dot.normalTicks > 0 then
		known, tolerance = dot.tickSum / dot.normalTicks, TICK_AMOUNT_TOLERANCE
	else
		known, tolerance = dot.tickKey and self.ticks[dot.tickKey], FIRST_TICK_AMOUNT_TOLERANCE
	end
	if not known then return true end
	known = known * TickShape(dot, number)
	if isCrit then
		return amount >= known * CRIT_MIN_RATIO - 1 and amount <= known * CRIT_MAX_RATIO + 1
	end
	return math.abs(amount - known) <= math.max(1, known * tolerance)
end

-- Never the learned size: that is what a collision corrupts.
local function ReferenceTickSize(dot)
	if dot.normalTicks > 1 then
		return (dot.tickSum - dot.lastTickAmount / dot.lastTickShape) / (dot.normalTicks - 1)
	end
	return dot.total / dot.totalTicks
end

local function SaveLearnedTick(self, dot)
	if dot.tickKey and dot.normalTicks > 0 then
		self.ticks[dot.tickKey] = math.floor(dot.tickSum / dot.normalTicks * 10 + 0.5) / 10
	end
end

local function AnchorTick(dot, index, now)
	dot.missed = 0
	if dot.firstTickAt then
		dot.lastTickIndex = index
	else
		dot.firstTickAt, dot.lastTickIndex = now, 0
		if dot.travel then dot.appliedAt = now - index * dot.interval end
	end
	dot.lastTickAt = now
	dot.nextTickAt = now + dot.interval
	-- Ticks arrive slightly late; expiry from the cast would cut off the last one.
	local tickIndex = math.max(1, math.floor((now - dot.appliedAt) / dot.interval + 0.5))
	dot.expiresAt = now + (dot.totalTicks - tickIndex) * dot.interval
	return tickIndex
end

-- Two same-school hits in one tick slot: the one closer to the expected size is the tick.
local function TrySwapSameSlot(self, dot, name, amount, isCrit, now)
	if isCrit or dot.lastTickCrit or not dot.lastTickAt or now - dot.lastTickAt > SAME_SLOT_SECONDS then
		return false
	end
	local factor = dot.lastTickShape
	local reference = ReferenceTickSize(dot) * factor
	if math.abs(amount - reference) >= math.abs(dot.lastTickAmount - reference) then return false end
	Trace(self, "SWAP %s tick: %d was another hit, %d is the tick", name, dot.lastTickAmount, amount)
	dot.tickSum = dot.tickSum + (amount - dot.lastTickAmount) / factor
	dot.lastTickAmount = amount
	SaveLearnedTick(self, dot)
	return true
end

-- A wrong learned size rejects every real tick: two agreeing hits in
-- consecutive slots on the DoT's rhythm are the real ticks.
local function TryRelearn(self, dot, name, amount, isCrit, index, distance, now)
	local window = dot.firstTickAt and TICK_MATCH_WINDOW_ANCHORED or TICK_MATCH_WINDOW
	local freshSlot = not dot.firstTickAt or index > dot.lastTickIndex
	if isCrit or not freshSlot or distance > window then return false end
	local previous = dot.offBeatCandidate
	local factor = TickShape(dot, TickNumberAt(dot, now))
	local average = amount / factor
	dot.offBeatCandidate = { index = index, amount = amount, average = average, at = now }
	if not previous or index ~= previous.index + 1
		or math.abs(average - previous.average) > math.max(1, previous.average * TICK_AMOUNT_TOLERANCE) then
		return false
	end
	Trace(self, "RELEARN %s: ticks of %d and %d on its rhythm didn't fit %.1f/tick", name,
		previous.amount, amount, ExpectedTick(self, dot))
	dot.offBeatCandidate = nil
	dot.tickSum, dot.normalTicks = previous.average + average, 2
	dot.ticksSeen = dot.ticksSeen + 2
	dot.lastTickAmount, dot.lastTickShape, dot.lastTickCrit = amount, factor, false
	SaveLearnedTick(self, dot)
	if not dot.firstTickAt then
		dot.firstTickAt, dot.lastTickIndex = previous.at, 0
		index = 1
	end
	AnchorTick(dot, index, now)
	return true
end

local function RemainingDamage(self, dot)
	if dot.nextTickAt > dot.expiresAt + dot.interval / 2 then return 0 end
	local ticksLeft = math.floor((dot.expiresAt - dot.nextTickAt) / dot.interval + 0.5) + 1
	local average = ExpectedTick(self, dot)
	if not dot.shape then return ticksLeft * average end
	local total = 0
	for number = math.max(1, dot.totalTicks - ticksLeft + 1), dot.totalTicks do
		total = total + average * TickShape(dot, number)
	end
	return total
end

-- Combo points ---------------------------------------------------------------
-- Secret in combat, so builders are also counted ("Awards N combo point"),
-- taken back when avoided and reset by finishers and target changes.

local function ReadComboPoints()
	local points = GetComboPoints("player", "target")
	if issecretvalue(points) then return nil end
	return points
end

function DotTracker:ComboPointsForCast()
	local points, source = self.comboAtSend, "read"
	if not (points and points > 0) then
		if self.lastComboPoints and GetTime() - self.lastComboAt <= COMBO_CACHE_SECONDS then
			points, source = self.lastComboPoints, "cached"
		elseif self.countedPoints > 0 then
			points, source = self.countedPoints, "counted"
		else
			points, source = nil, "unknown"
		end
	end
	self.comboAtSend = nil
	self.countedPoints, self.lastBuilder = 0, nil
	return points, source
end

-- Cast outcomes ----------------------------------------------------------------

function DotTracker:AvoidJustBefore(key)
	local outcome = self.lastOutcome
	if outcome and outcome.avoided and outcome.key == key and GetTime() - outcome.at <= OUTCOME_LOOKBACK then
		return outcome
	end
end

function DotTracker:OnBuilderCast(key, points)
	local avoided = self:AvoidJustBefore(key)
	if avoided then
		Trace(self, "COMBO builder %s (before cast event), counted=%d", avoided.action, self.countedPoints)
		return
	end
	self.countedPoints = math.min(COMBO_CAP, self.countedPoints + points)
	self.lastBuilder = { key = key, points = points, at = GetTime() }
end

-- An avoided DoT cast is not on the mob; a recast puts the earlier DoT back.
-- Spell DoTs ignore melee-only avoids (usually the pet's) and wait for their
-- first tick after an avoid outside their school. False: the avoid was not
-- this cast's, so its own outcome may still come.
function DotTracker:RemoveAvoidedDot(cast, action, school)
	local dot, dots = cast.dot, self.dots[cast.key]
	if not dots or dots[cast.name] ~= dot then return true end
	if dot.school ~= PHYSICAL and school ~= dot.school then
		if MELEE_ONLY_AVOIDS[action] then
			Trace(self, "AVOID %s (school %s) right after %s: not the spell, ignored", action, tostring(school), cast.name)
			return false
		end
		if not cast.previous then
			dot.doubtful = true
			Trace(self, "AVOID %s (school %s) right after %s: may be someone else's, waiting for its first tick",
				action, tostring(school), cast.name)
			self:Changed(cast.key)
			return true
		end
	end
	if cast.previous then
		dots[cast.name] = cast.previous
		Trace(self, "AVOID %s (school %s) right after %s recast; keeping the earlier one", action, tostring(school), cast.name)
	else
		dots[cast.name] = nil
		Trace(self, "AVOID %s (school %s) right after %s; dropped", action, tostring(school), cast.name)
	end
	self:Changed(cast.key)
	return true
end

function DotTracker:OnAvoided(key, action, school)
	local now = GetTime()
	self.lastOutcome = { key = key, avoided = true, action = action, school = school, at = now }
	local builder = self.lastBuilder
	if builder and builder.key == key then
		if now - builder.at <= OUTCOME_WINDOW then
			self.countedPoints = math.max(0, self.countedPoints - builder.points)
			Trace(self, "COMBO builder %s, counted=%d", action, self.countedPoints)
		end
		self.lastBuilder = nil
	end
	local cast = self.lastDotCast
	if cast and cast.key == key then
		if now - cast.at > OUTCOME_WINDOW or self:RemoveAvoidedDot(cast, action, school) then
			self.lastDotCast = nil
		end
	end
end

-- A hit lands the pending casts; for a spell DoT only a hit in its school does.
function DotTracker:OnHit(key, school)
	self.lastOutcome = { key = key, avoided = false, at = GetTime() }
	if self.lastBuilder and self.lastBuilder.key == key then self.lastBuilder = nil end
	local cast = self.lastDotCast
	if cast and cast.key == key and (cast.dot.school == PHYSICAL or cast.dot.school == school) then
		self.lastDotCast = nil
	end
end

-- Casts ------------------------------------------------------------------------

-- Instants confirm a round trip after the press; tab-dotters have moved on by then.
function DotTracker:CastTargetKey(castGUID)
	local sent = castGUID and self.sentTargets[castGUID]
	if not sent then return self:KeyFor("target") end
	self.sentTargets[castGUID] = nil
	return sent.key
end

function DotTracker:OnCastSent(spellID, castGUID)
	local now = GetTime()
	for guid, sent in pairs(self.sentTargets) do
		if now - sent.at > SENT_TARGET_SECONDS then self.sentTargets[guid] = nil end
	end
	self.sentTargets[castGUID] = { key = self:KeyFor("target"), at = now }
	if not DotParser.IsFinisher(C_Spell.GetSpellDescription(spellID)) then return end
	self.comboAtSend = ReadComboPoints()
	Trace(self, "COMBO at send: %s, counted=%d", tostring(self.comboAtSend), self.countedPoints)
end

function DotTracker:OnCast(spellID, castGUID)
	local key = self:CastTargetKey(castGUID)
	local name = C_Spell.GetSpellName(spellID)
	if issecretvalue(name) or not name then return end
	local desc = C_Spell.GetSpellDescription(spellID)
	local awarded = DotParser.AwardedComboPoints(desc)
	if awarded then self:OnBuilderCast(key, awarded) end
	if DotParser.IGNORED[name] then return end
	local isFinisher = DotParser.IsFinisher(desc)
	local comboPoints, comboSource
	if isFinisher then comboPoints, comboSource = self:ComboPointsForCast() end
	-- Unknown points parse the lowest entry (errs low) and neither use nor teach tick sizes.
	local dot = DotParser.Describe(name, desc, comboPoints or 1)
	if not dot or not key then return end

	local now = GetTime()
	local tickKey = spellID
	if isFinisher then tickKey = comboPoints and (spellID .. "x" .. comboPoints) or nil end
	dot.spellID, dot.tickKey = spellID, tickKey
	dot.appliedAt, dot.expiresAt, dot.nextTickAt = now, now + dot.duration, now + dot.interval
	dot.tickSum, dot.normalTicks, dot.ticksSeen, dot.missed = 0, 0, 0, 0
	local learned = tickKey and self.ticks[tickKey]
	dot.unsure = not learned

	local dots = self.dots[key] or {}
	self.dots[key] = dots
	local previous = dots[name]
	dots[name] = dot
	self.lastDotCast = { key = key, name = name, dot = dot, previous = previous, at = now }
	if self.trace then
		Trace(self, "CAST %s (id %d)%s: %d dmg over %ss, school %d, tick every %ss, per-tick %s%s", name, spellID,
			isFinisher and string.format(" %s combo points (%s)", tostring(comboPoints or "?"), comboSource) or "",
			dot.total, dot.duration, dot.school, dot.interval, learned and ("learned " .. learned) or "from description",
			key ~= self:KeyFor("target") and (" on " .. tostring(key) .. ", the target when sent") or "")
	end
	local avoided = self:AvoidJustBefore(key)
	if avoided and self:RemoveAvoidedDot(self.lastDotCast, avoided.action, avoided.school) then
		self.lastDotCast = nil
		return
	end
	self:Changed(key)
end

-- Ticks ------------------------------------------------------------------------

function DotTracker:OnCombat(unit, action, flag, amount, school)
	if issecretvalue(action) then return end
	local avoided = AVOIDED[action]
	if not avoided and action ~= "WOUND" then return end
	local key = self:KeyFor(unit)
	if not key then return end
	if issecretvalue(school) then school = nil end
	if avoided then return self:OnAvoided(key, action, school) end
	self:OnHit(key, school)
	if issecretvalue(amount) or type(amount) ~= "number" or not school then return end
	local isCrit = not issecretvalue(flag) and flag == "CRITICAL"
	local dots = self.dots[key]
	if not dots then return end

	-- Target and focus on the same mob report the same hit twice.
	local now, last = GetTime(), self.lastCombat
	if last.key == key and last.amount == amount and last.school == school and last.at == now then return end
	last.key, last.amount, last.school, last.at = key, amount, school, now

	local best, bestName, bestDistance, bestIndex
	for name, dot in pairs(dots) do
		if dot.school == school and PlausibleTickAmount(self, dot, amount, isCrit, TickNumberAt(dot, now)) then
			local distance, index = DistanceToExpectedTick(dot, now)
			local window = dot.firstTickAt and TICK_MATCH_WINDOW_ANCHORED or TICK_MATCH_WINDOW
			local freshSlot = not dot.firstTickAt or index > dot.lastTickIndex
			if freshSlot and distance <= window and (not bestDistance or distance < bestDistance) then
				best, bestName, bestDistance, bestIndex = dot, name, distance, index
			end
		end
	end
	if not best then
		for name, dot in pairs(dots) do
			if dot.school == school then
				local distance, index = DistanceToExpectedTick(dot, now)
				if TrySwapSameSlot(self, dot, name, amount, isCrit, now)
					or TryRelearn(self, dot, name, amount, isCrit, index, distance, now) then
					self:Changed(key)
					return
				end
			end
		end
		Trace(self, "HIT %d%s school %d on %s not matched to a DoT", amount, isCrit and " (crit)" or "", school, unit)
		return
	end

	local factor = TickShape(best, TickNumberAt(best, now))
	best.ticksSeen = best.ticksSeen + 1
	best.lastTickAmount, best.lastTickShape, best.lastTickCrit = amount, factor, isCrit
	best.offBeatCandidate = nil
	-- Crits are one-offs: they never raise the expected tick.
	if not isCrit then
		best.tickSum = best.tickSum + amount / factor
		best.normalTicks = best.normalTicks + 1
		SaveLearnedTick(self, best)
	end
	local tickIndex = AnchorTick(best, bestIndex, now)
	Trace(self, "TICK %s %d%s on %s (tick %d/%d, expecting %.1f for this tick)", bestName, amount,
		isCrit and " CRIT" or "", unit, tickIndex, best.totalTicks, ExpectedTick(self, best) * factor)
	self:Changed(key)
end

-- Late ticks and expiry ----------------------------------------------------------

-- Only a tick that could have been seen counts as missed: a mob that is
-- neither target nor focus keeps its DoTs until they expire.
function DotTracker:Housekeep(now)
	local deadline
	for key, dots in pairs(self.dots) do
		local changed, observable = false, nil
		for name, dot in pairs(dots) do
			local late = (dot.ticksSeen == 0 and dot.travel) or 0
			while dot.nextTickAt < now - TICK_MATCH_WINDOW - late and dot.nextTickAt <= dot.expiresAt do
				dot.nextTickAt = dot.nextTickAt + dot.interval
				changed = true
				if dot.ticksSeen == 0 then
					if observable == nil then observable = self:IsObservable(key) end
					if observable then dot.missed = dot.missed + 1 end
				end
			end
			if now > dot.expiresAt + TICK_MATCH_WINDOW then
				dots[name], changed = nil, true
				Trace(self, "EXPIRE %s", name)
			elseif dot.ticksSeen == 0 and dot.missed >= MISSED_TICKS_BEFORE_DROP then
				dots[name], changed = nil, true
				Trace(self, "DROP %s never ticked (resisted or immune?)", name)
			else
				local due = dot.expiresAt + TICK_MATCH_WINDOW
				if dot.nextTickAt <= dot.expiresAt then due = math.min(due, dot.nextTickAt + TICK_MATCH_WINDOW + late) end
				deadline = math.min(deadline or due, due)
			end
		end
		if next(dots) == nil then self.dots[key] = nil end
		if changed then ns.Events:Fire("DotsChanged", key) end
	end
	self.deadline = deadline or 0
	if not deadline then self.driver:SetScript("OnUpdate", nil) end
end

-- Reading ------------------------------------------------------------------------

-- waitMode (WAIT_MODES): whether a DoT counts before its first tick. One
-- doubted by an avoid right after its cast always waits.
function DotTracker:IsWaiting(dot, waitMode)
	if dot.ticksSeen > 0 then return false end
	if dot.doubtful or waitMode == "always" then return true end
	return waitMode == "unsure" and dot.unsure == true
end

-- Fills `out` (reused) with { name, spellID, school, appliedAt, damage } per
-- counted DoT, oldest first. Returns the rounded total, the count and `out`.
function DotTracker:Breakdown(key, waitMode, out)
	out = out or {}
	local count, total = 0, 0
	local dots = key and self.dots[key]
	if dots then
		for name, dot in pairs(dots) do
			if not self:IsWaiting(dot, waitMode) then
				count = count + 1
				local entry = out[count] or {}
				out[count] = entry
				entry.name, entry.spellID, entry.school, entry.appliedAt = name, dot.spellID, dot.school, dot.appliedAt
				entry.damage = RemainingDamage(self, dot)
				total = total + entry.damage
			end
		end
	end
	for i = #out, count + 1, -1 do out[i] = nil end
	if count > 1 then table.sort(out, ByApplied) end
	return math.floor(total + 0.5), count, out
end

-- Events -------------------------------------------------------------------------

function DotTracker:PLAYER_TARGET_CHANGED()
	if self.dots.target then
		self.dots.target = nil
		ns.Events:Fire("DotsChanged", "target")
	end
	self.countedPoints, self.lastBuilder = 0, nil
	Trace(self, "TARGET changed to %s", tostring(self:KeyFor("target")))
end

-- Payloads are secret when spellcasts are restricted.
function DotTracker:UNIT_SPELLCAST_SENT(_, _, castGUID, spellID)
	if issecretvalue(castGUID) or issecretvalue(spellID) then return end
	self:OnCastSent(spellID, castGUID)
end

function DotTracker:UNIT_SPELLCAST_SUCCEEDED(_, castGUID, spellID)
	if issecretvalue(castGUID) or issecretvalue(spellID) then return end
	self:OnCast(spellID, castGUID)
end

function DotTracker:UNIT_COMBAT(unit, action, flag, amount, school)
	self:OnCombat(unit, action, flag, amount, school)
end

-- Spent by the time a finisher's cast succeeds: a recent reading backs up the one at send.
function DotTracker:UNIT_POWER_FREQUENT(_, powerType)
	if issecretvalue(powerType) or powerType ~= "COMBO_POINTS" then return end
	local points = ReadComboPoints()
	if points and points > 0 then self.lastComboPoints, self.lastComboAt = points, GetTime() end
end

ns.DotTracker = DotTracker:New()
