local Helpers = require("helpers")

describe("Shared icon placement", function()
	it("preserves companion visibility and NAME offset policy", function()
		local UF, CG = Helpers.LoadClickGrid()
		local schema = CG.IndicatorSchema
		local off = UF.Schema.Find(schema, "rolePosition").hidden
		local offset = UF.Schema.Find(schema, "roleOffsetX").hidden
		assert.is_true(off({ role = false }))
		assert.is_false(off({ role = true }))
		assert.is_true(offset({ role = true, rolePosition = "NAME" }))
		assert.is_false(offset({ role = true, rolePosition = "TOP" }))
		local cfg = UF.IconPlacement.Read(CG.Config:Resolved().indicators, UF.IconPlacement.PrefixedKeys("ready"))
		assert.equals("CENTER", cfg.anchor)
		assert.equals(22, cfg.size)
	end)

	it("builds independent descriptors without changing supplied defaults or choices", function()
		local UF = Helpers.LoadAddon()
		local choices = { { "TOP", "Top" } }
		local opts = { defaults = { enabled = false }, fields = { anchor = { values = choices } } }
		local first, second = UF.IconPlacement.BuildSchema(opts), UF.IconPlacement.BuildSchema(opts)
		first[2].values[1][2] = "Changed"
		assert.equals("Top", second[2].values[1][2])
		assert.equals("Top", choices[1][2])
		assert.is_false(first[1].default)
		assert.same({ enabled = false }, opts.defaults)
	end)
end)
