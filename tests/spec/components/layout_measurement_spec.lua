local Helpers = require("helpers")

describe("Frame-free unit layout", function()
	it("builds independent schemas and measures all definitions without allocating frames", function()
		local ns = Helpers.LoadAddon(true)
		local create = CreateFrame
		CreateFrame = function() error("Measurement allocated a native frame") end
		local ok, err = pcall(function()
			for _, unit in ipairs(ns.Units.order) do
				local spec = ns.Units:GetSpec(ns.Units:GetDefinition(unit))
				local schema = ns.Components.UnitFrame.BuildSchema(spec)
				local cfg = ns.Schema.Resolve(schema, {}, ns.Config:GetTheme())
				local layout = ns.UnitFrameLayout.Compute(spec, cfg)
				assert.is_true(layout.width > 0)
				assert.is_true(layout.height > 0)
				ns.Schema.Find(schema, "health.bar.segments.absorb.placement").default = "append"
				local independent = ns.Components.UnitFrame.BuildSchema(spec)
				assert.equals("overlay", ns.Schema.Find(independent, "health.bar.segments.absorb.placement").default)
			end
		end)
		CreateFrame = create
		assert.is_true(ok, err)
	end)

	it("measures portrait spans and collapsed rows before creating the visual composition", function()
		local ns = Helpers.LoadAddon(true)
		local spec = ns.Units:GetSpec(ns.Units.definitions.player)
		local schema = ns.Components.UnitFrame.BuildSchema(spec)
		local config = { width = 280, portrait = { rowSpan = 1, position = "RIGHT" }, power = { enabled = false },
			experience = { enabled = true }, castbar = { enabled = true, placement = "health" } }
		local cfg = ns.Schema.Resolve(schema, config, ns.Config:GetTheme())
		local measured = ns.UnitFrameLayout.Compute(spec, cfg)
		assert.equals(308, measured.width)
		assert.equals(43, measured.height)
		assert.equals(26, measured.portrait.height)
		assert.equals(31, measured.rows[1].right)
		assert.equals(3, measured.rows[2].right)
		local uf = ns.Units:CreateFromDefinition(ns.Units.definitions.player, UIParent, config)
		assert.equals(measured.width, uf:GetFrame():GetWidth())
		assert.equals(measured.height, uf:GetFrame():GetHeight())
	end)

	it("keeps frames of one width equally wide whatever their portrait when it counts into the width", function()
		local ns = Helpers.LoadAddon(true)
		local function Measure(unit, config)
			local spec = ns.Units:GetSpec(ns.Units.definitions[unit])
			local cfg = ns.Schema.Resolve(ns.Components.UnitFrame.BuildSchema(spec), config, ns.Config:GetTheme())
			return ns.UnitFrameLayout.Compute(spec, cfg)
		end
		local short = Measure("player", { width = 230 })
		local tall = Measure("player", { width = 230, experience = { enabled = true } })
		assert.is_true(tall.portrait.width > short.portrait.width)
		assert.equals(230 + short.portrait.width + 2, short.width)
		assert.is_true(short.width < tall.width)

		short = Measure("player", { width = 230, portrait = { includeInWidth = true } })
		tall = Measure("player", { width = 230, experience = { enabled = true }, portrait = { includeInWidth = true } })
		assert.equals(230, short.width)
		assert.equals(230, tall.width)
		assert.equals(short.rows[1].left, short.portrait.width + 2 + short.rows[1].right)

		local narrow = Measure("player", { width = 60, portrait = { includeInWidth = true, size = 100 } })
		local padding = narrow.rows[1].right * 2
		assert.equals(100 + 2 + padding + ns.UnitFrameLayout.MIN_ROW_WIDTH, narrow.width)
	end)

	it("adds nothing for a hidden portrait that counts into the width", function()
		local ns = Helpers.LoadAddon(true)
		local spec = ns.Units:GetSpec(ns.Units.definitions.player)
		local cfg = ns.Schema.Resolve(ns.Components.UnitFrame.BuildSchema(spec),
			{ width = 230, portrait = { enabled = false, includeInWidth = true } }, ns.Config:GetTheme())
		assert.equals(230, ns.UnitFrameLayout.Compute(spec, cfg).width)
	end)
end)
