local _, CG = ...
local Ordering = {}
CG.Ordering = Ordering

function Ordering.SampleRole(index)
	if index == 1 then return "TANK" end
	if index == 2 then return "HEALER" end
	return index % 8 == 0 and "NONE" or "DAMAGER"
end

function Ordering.Sample(first, count, order)
	local list, ranks = {}, {}
	local rank = 0
	for role in order:gmatch("[^,]+") do rank = rank + 1; ranks[role] = rank end
	for index = first, first + count - 1 do list[#list + 1] = index end
	table.sort(list, function(a, b)
		local left, right = ranks[Ordering.SampleRole(a)], ranks[Ordering.SampleRole(b)]
		if left == right then return a < b end
		return left < right
	end)
	return list
end
