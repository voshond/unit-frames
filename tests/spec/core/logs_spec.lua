local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Persistent addon diagnostics", function()
	local UF
	before_each(function() UF = Helpers.LoadAddon(true) end)

	it("bounds timestamped errors and general entries independently across reloads", function()
		for i = 1, 25 do
			Mock.time = i
			UF.Logs:Error("test", "error " .. i)
			UF.Logs:Info("test", "entry " .. i)
		end
		assert.equals(10, #UnitFramesLogs.errors)
		assert.equals(20, #UnitFramesLogs.general)
		assert.equals("error 16", UnitFramesLogs.errors[1].message)
		assert.equals("entry 6", UnitFramesLogs.general[1].message)
		assert.equals(1700000025, UnitFramesLogs.errors[10].timestamp)
		assert.equals(UF.version, UnitFramesLogs.errors[10].version)
		local saved = UnitFramesLogs
		UF = Helpers.LoadAddon(true, nil, nil, saved)
		UF.Logs:Error("reload", "still bounded")
		assert.equals(saved, UnitFramesLogs)
		assert.equals(10, #UnitFramesLogs.errors)
		assert.equals("error 17", UnitFramesLogs.errors[1].message)
	end)

	it("omits opaque values before formatting and bounds individual strings", function()
		UF.Logs:Error(Mock.Secret("context"), Mock.Secret("message"))
		local entry = UnitFramesLogs.errors[1]
		assert.equals("<secret omitted>", entry.context)
		assert.equals("<secret omitted>", entry.message)
		UF.Logs:Error("long", string.rep("x", 2000))
		assert.equals(1024, #UnitFramesLogs.errors[2].message)
	end)

	it("reports and clears through the slash command without changing the profile", function()
		local profile = UF.Config.db.profile
		UF.Logs:Error("test", "boom")
		local messages = {}
		UF.Print = function(_, ...) messages[#messages + 1] = { ... } end
		SlashCmdList.UNITFRAMES("logs")
		assert.equals("boom", messages[2][4])
		SlashCmdList.UNITFRAMES("logs clear")
		assert.equals(0, #UnitFramesLogs.errors)
		assert.equals(profile, UF.Config.db.profile)
	end)

	it("captures caught restyle failures once per pending retry and diagnostic failures", function()
		local auras = UF.Components.Auras:New(UIParent, {})
		Mock.aurasSecret = true
		auras:Apply({ durationSize = 15 })
		auras:RestyleButtons()
		assert.equals(1, #UnitFramesLogs.errors)
		assert.equals("Auras restyle deferred", UnitFramesLogs.errors[1].context)
		Mock.aurasSecret = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_false(UF.AfterCombat:IsQueued(auras, "restyle"))
		Mock.profilerEnabled = true
		UF.Perf:Measure("clickgrid")
		assert.equals("measure clickgrid", UnitFramesLogs.errors[2].context)
		auras:Release()
	end)
end)
