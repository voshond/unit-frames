local Helpers = require("helpers")

describe("Schema resolution sources", function()
	it("uses identical precedence and nested default layers for values, sources and resets", function()
		local UF = Helpers.LoadAddon(true)
		local schema = { { key = "outer", type = "group", defaults = { inner = { value = 12 } }, schema = {
			{ key = "inner", type = "group", defaults = { value = 8 }, schema = {
				{ key = "value", type = "range", inherit = "fontSize", default = 4 },
				{ key = "theme", type = "range", inherit = "fontSize", default = 4 },
				{ key = "builtin", type = "range", default = 3 },
			} },
		} } }
		local config, theme = { outer = { inner = { value = 20 } } }, { fontSize = 11 }
		for _, case in ipairs({ { "value", "Custom value", 20 }, { "theme", "Shared appearance", 11 }, { "builtin", "Built-in default", 3 } }) do
			local path = "outer.inner." .. case[1]
			local source, value = UF.Schema.Source(schema, config, theme, path)
			assert.equals(case[2], source)
			assert.equals(case[3], value)
			assert.equals(value, UF.Util.GetPath(UF.Schema.Resolve(schema, config, theme), path))
		end
		local source, restored = UF.Schema.Source(schema, config, theme, "outer.inner.value", true)
		assert.equals("Frame default", source)
		assert.equals(12, restored)
		assert.equals(20, config.outer.inner.value)
	end)
end)
