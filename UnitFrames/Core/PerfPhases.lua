local _, ns = ...
local Perf = ns.Perf

function Perf.RankPhases(phases, key)
	local ranked = {}
	for index, phase in ipairs(phases) do ranked[index] = phase end
	table.sort(ranked, function(a, b)
		if a[key] == b[key] then return a.name < b.name end
		return a[key] > b[key]
	end)
	return ranked
end

function Perf.Phases(results)
	local phases, stack, ms, bytes = {}, {}, 0, 0
	local function Add(name, toMS, toBytes)
		local phase = phases[name] or { name = name, ms = 0, bytes = 0, calls = 0 }
		phases[name] = phase
		phase.ms, phase.bytes = phase.ms + toMS - ms, phase.bytes + toBytes - bytes
		ms, bytes = toMS, toBytes
	end
	for _, event in ipairs(results.events or {}) do
		Add(stack[#stack] or "unmarked", event.elapsedMilliseconds, event.allocatedBytes)
		local kind, name = event.name:sub(1, 1), event.name:sub(2)
		if kind == ">" then
			stack[#stack + 1] = name
			local phase = phases[name] or { name = name, ms = 0, bytes = 0, calls = 0 }
			phases[name], phase.calls = phase, phase.calls + 1
		elseif kind == "<" then
			stack[#stack] = nil
		end
	end
	Add("unmarked", results.elapsedMilliseconds, results.allocatedBytes)
	local list = {}
	for _, phase in pairs(phases) do list[#list + 1] = phase end
	return Perf.RankPhases(list, "bytes")
end

function Perf:ReportPhases(phases)
	for _, ranking in ipairs({ { "ms", "time" }, { "bytes", "allocation" } }) do
		ns:Print(string.format("phases by %s (exclusive; showing %d of %d)", ranking[2], math.min(15, #phases), #phases))
		for index, phase in ipairs(self.RankPhases(phases, ranking[1])) do
			if index > 15 then break end
			ns:Print(string.format("  %s: %.3f ms, %.1f KB allocated, %d entries",
				phase.name, phase.ms, phase.bytes / 1024, phase.calls))
		end
	end
end
