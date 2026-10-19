local _, ns = ...
local DotSpells = {}
ns.DotSpells = DotSpells

local AGONY_SHAPE = { 0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1.5, 1.5, 1.5, 1.5 }

function DotSpells.IsCompatible()
	local version, build, _, interface = GetBuildInfo()
	return version .. "." .. build == ns.DotCatalog.build and interface == ns.DotCatalog.interface
end

function DotSpells.IsFinisher(spellID)
	if issecretvalue(spellID) then return false end
	return ns.DotCatalog.finishers[spellID] == true
end

function DotSpells.AwardedComboPoints(spellID)
	if issecretvalue(spellID) then return nil end
	return ns.DotCatalog.builders[spellID]
end

function DotSpells.Describe(spellID, comboPoints)
	if issecretvalue(spellID) then return nil end
	local spell = ns.DotCatalog.spells[spellID]
	if not spell then return nil end
	local points = comboPoints or 1
	local duration = spell.durationMs + spell.durationPerResourceMs * points
	if spell.maxDurationMs > 0 then duration = math.min(duration, spell.maxDurationMs) end
	duration = duration / 1000
	local interval = spell.periodMs / 1000
	local ticks = math.max(1, math.floor(duration / interval + 0.5))
	local tick = math.max(0, spell.basePoints + spell.pointsPerResource * points)
	return {
		family = spell.family,
		total = tick * ticks,
		school = spell.school,
		duration = duration,
		interval = interval,
		totalTicks = ticks,
		shape = spell.family == 980 and AGONY_SHAPE or spell.shape,
		travel = spell.projectile and 1.5 or nil,
	}
end
