local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Slash command help", function()
	local ns, messages
	before_each(function()
		ns = Helpers.LoadAddon()
		messages = {}
		ns.Print = function(_, ...) messages[#messages + 1] = { ... } end
	end)

	it("announces the version in green once after its own initialization", function()
		Mock.FireEvent("ADDON_LOADED", "OtherAddon")
		assert.equals(0, #messages)
		Mock.FireEvent("ADDON_LOADED", "UnitFrames")
		assert.same({ { "|cff00ff00" .. ns.version .. "|r loaded. Use /uf for a list of commands." } }, messages)
		Mock.FireEvent("ADDON_LOADED", "UnitFrames_Workbench")
		Mock.FireEvent("ADDON_LOADED", "UnitFrames")
		assert.equals(1, #messages)
	end)

	it("captures client chat across initialized addon loads", function()
		local initialized = Helpers.LoadAddon(true)
		assert.same({ {
			"|cff4fa3ffUnitFrames|r:",
			"|cff00ff00" .. initialized.version .. "|r loaded. Use /uf for a list of commands.",
		} }, Mock.messages)
		initialized:Print("test message", 42)
		assert.same({ "|cff4fa3ffUnitFrames|r:", "test message", 42 }, Mock.messages[2])
		Helpers.LoadAddon()
		assert.same({}, Mock.messages)
	end)

	it("shows the same concise help for /uf, /uf help and unknown commands", function()
		SlashCmdList.UNITFRAMES("")
		local help = messages
		assert.same({
			{ "version", ns.version },
			{ "/uf help - show this list of commands" },
			{ "/uf wb - open settings and previews" },
			{ "/uf logs [clear] - show or clear saved diagnostic entries" },
			{ "/uf perf help - show developer performance commands" },
		}, help)
		for _, command in ipairs({ "  HELP  ", "unknown" }) do
			messages = {}
			SlashCmdList.UNITFRAMES(command)
			assert.same(help, messages)
		end
		assert.is_nil(ns.Workbench)
	end)

	it("shows performance subcommands only through perf help without measuring", function()
		ns.Perf.Snapshot = function() error("help must not snapshot") end
		ns.Perf.Measure = function() error("help must not measure") end
		ns.Perf.StartSuite = function() error("help must not start a suite") end
		SlashCmdList.UNITFRAMES("perf help")
		assert.equals(8, #messages)
		assert.equals("/uf perf - performance snapshot", messages[1][1])
		assert.equals("/uf perf startup - measure startup after the next /reload", messages[6][1])
		assert.equals("/uf perf suite baseline - run the out-of-combat baseline suite", messages[7][1])
		assert.equals("/uf perf suite report - show the last saved suite report", messages[8][1])
		assert.is_nil(ns.Workbench)
	end)
end)
