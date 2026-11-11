local _, ns = ...
local BuffSpells = {}
ns.BuffSpells = BuffSpells

BuffSpells.HEAL_KINDS = { hot = true, absorb = true, proc = true }
-- Named sets of catalogue families. Own sets keep to the player's class and
-- their own casts; the others match any caster.
BuffSpells.SETS = {
	MY_HEALS = { kinds = BuffSpells.HEAL_KINDS, own = true, filter = "HELPFUL|PLAYER" },
	EXTERNALS = { kinds = { external = true, defensive = true }, filter = "HELPFUL" },
	RAID_BUFFS = { kinds = { raid = true }, filter = "HELPFUL" },
}
local setIDs = {}

function BuffSpells.Family(spellID)
	local root = ns.BuffCatalog.byId[spellID]
	return root and ns.BuffCatalog.families[root], root
end

function BuffSpells.Expand(ids)
	local expanded = {}
	for id in pairs(ids) do
		local family = BuffSpells.Family(id)
		if family then
			for _, member in ipairs(family.ids) do expanded[member] = true end
		else
			expanded[id] = true
		end
	end
	return expanded
end

function BuffSpells.ClassIDs(class, kinds)
	local ids = {}
	for _, family in pairs(ns.BuffCatalog.families) do
		if (class == nil or family.class == class) and kinds[family.kind] then
			for _, id in ipairs(family.ids) do ids[id] = true end
		end
	end
	return ids
end

function BuffSpells.PlayerClass()
	local _, class = UnitClass("player")
	if issecretvalue(class) then return nil end
	return class
end

function BuffSpells.SetIDs(name)
	local set = BuffSpells.SETS[name]
	local class = set.own and BuffSpells.PlayerClass() or nil
	local key = name .. ":" .. (class or "")
	setIDs[key] = setIDs[key] or BuffSpells.ClassIDs(class, set.kinds)
	return setIDs[key]
end

function BuffSpells.PlayerHealIDs()
	return BuffSpells.SetIDs("MY_HEALS")
end

function BuffSpells.Roots()
	local families, roots = ns.BuffCatalog.families, {}
	for root in pairs(families) do roots[#roots + 1] = root end
	table.sort(roots, function(a, b)
		local left, right = families[a], families[b]
		if left.class ~= right.class then return left.class < right.class end
		if left.name ~= right.name then return left.name < right.name end
		return a < b
	end)
	return roots
end
