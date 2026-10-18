describe("Saved performance diagnostics reader", function()
	local function Read(selection)
		local messages = {}
		local chunk = assert(loadfile("scripts/read-perf.lua"))
		setfenv(chunk, setmetatable({
			arg = { "tests/fixtures/perf_saved.lua", selection },
			print = function(message) messages[#messages + 1] = message end,
		}, { __index = _G }))
		chunk()
		return messages
	end

	it("reads saved suites and complete measurement rankings without exposing unrelated data or replacing globals", function()
		local db, logs = UnitFramesDB, UnitFramesLogs
		local output = table.concat(Read("all"), "\n")
		assert.is_not_nil(output:find("============ baseline suite ============", 1, true))
		assert.is_not_nil(output:find("median 285.554 ms", 1, true))
		assert.is_not_nil(output:find("============ measure clickgrid ============", 1, true))
		assert.is_not_nil(output:find("283.138 ms", 1, true))
		assert.is_not_nil(output:find("1762 shared hits", 1, true))
		assert.is_not_nil(output:find("phases by time", 1, true))
		assert.is_not_nil(output:find("phases by allocation", 1, true))
		assert.is_nil(output:find("unrelated profile data", 1, true))
		assert.is_nil(output:find("unrelated log data", 1, true))
		assert.equals(db, UnitFramesDB)
		assert.equals(logs, UnitFramesLogs)
	end)

	it("selects an individual measurement or suite and reports absent selections clearly", function()
		local measurement = table.concat(Read("measure clickgrid"), "\n")
		assert.is_nil(measurement:find("baseline suite completed", 1, true))
		local suite = table.concat(Read("suite"), "\n")
		assert.is_nil(suite:find("measure clickgrid", 1, true))
		local saved = table.concat(Read("saved"), "\n")
		assert.is_not_nil(saved:find("============ saved comparison baseline ============", 1, true))
		assert.is_not_nil(saved:find("no saved baseline suite report", 1, true))
		local ok, err = pcall(Read, "missing")
		assert.is_false(ok)
		assert.is_not_nil(err:find("No saved measurement: missing", 1, true))
	end)
end)
