local Helpers = require("helpers")

describe("Generated Forever atlas table #proof", function()
	it("matches the library's pinned build without requiring the raw atlas tables", function()
		assert.equals(0, os.execute("python3 -B " .. Helpers.WutDir .. "/scripts/atlas_catalog.py --check-pin"
			.. " --scan 'UnitFrames*/*.lua' --output tests/proof/atlases.lua"))
	end)
end)
