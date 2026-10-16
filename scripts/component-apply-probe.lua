package.path = "tests/?.lua;" .. package.path
local Helpers = require("helpers")
local Mock = Helpers.Mock
local UF, CG = Helpers.LoadClickGrid(false)
local counts = {}
for _, object in ipairs(Mock.objects) do
	for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetSize", "SetHeight", "SetAuraSlotEnabled" }) do
		local original = object[method]
		if original then
			object[method] = function(self, ...)
				counts[method] = (counts[method] or 0) + 1
				return original(self, ...)
			end
		end
	end
end
local function WatchTags(frame)
	local tag = frame.Tag
	frame.Tag = function(self, ...)
		counts.Tag = (counts.Tag or 0) + 1
		return tag(self, ...)
	end
end
for _, frame in pairs(UF.Units.frames) do WatchTags(frame) end
for _, frame in ipairs(CG.frames) do WatchTags(frame) end
local function Measure(label, run)
	counts = { Tag = 0, categoryArtBuild = 0, categoryButtonStyle = 0, SetAuraSlotEnabled = 0 }
	UF.Perf.counters = {}
	run()
	for key, value in pairs(UF.Perf.counters) do counts[key] = value end
	UF.Perf.counters = nil
	local keys = {}
	for key in pairs(counts) do keys[#keys + 1] = key end
	table.sort(keys)
	io.write(label .. "\n")
	for _, key in ipairs(keys) do io.write(string.format("  %s=%d\n", key, counts[key])) end
end
local function Units()
	for _, unit in ipairs(UF.Units.order) do UF.Units:Refresh(unit) end
end
Measure("standalone unchanged refresh", Units)
Measure("standalone refresh sharing scope", function() UF.Schema.Shared(Units) end)
Measure("ClickGrid unchanged refresh", function() CG:Refresh() end)
