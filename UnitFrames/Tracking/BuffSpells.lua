local _, ns = ...
local BuffSpells = {}
ns.BuffSpells = BuffSpells

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
