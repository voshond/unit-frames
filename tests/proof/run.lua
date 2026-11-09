local Setup = dofile("tests/proof/setup.lua")
local Runner = require("wowproof.runner")

local SCENARIO_FILES = { "tests/proof/units.lua", "tests/proof/workbench.lua" }

local write = io.write
local function Print(line) write(line, "\n") end

local scenarios = {}
for _, file in ipairs(SCENARIO_FILES) do
	for _, scenario in ipairs(dofile(file)) do scenarios[#scenarios + 1] = scenario end
end

local _, failed = Runner.Run({
	proof = Setup.Proof(),
	scenarios = scenarios,
	filters = arg,
	print = Print,
})
os.exit(failed == 0 and 0 or 1, true)
