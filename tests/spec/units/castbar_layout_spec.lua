local Helpers = require("helpers")

describe("Pure castbar layout", function()
	it("measures portrait splits, stacks, sides and ordinary rows without native frames", function()
		local UF = Helpers.LoadAddon()
		local cfg = UF.Schema.Resolve(UF.Components.Castbar.BuildSchema(), { border = { enabled = false } }, UF.Config:GetTheme())
		local create = CreateFrame
		CreateFrame = function() error("layout must not allocate native frames") end
		for _, side in ipairs({ "LEFT", "RIGHT" }) do
			cfg.icon.position, cfg.portraitLayout = side, "split"
			local split = UF.CastbarLayout.Compute(60, 40, cfg, true)
			assert.equals(29.5, split.icon.width)
			assert.equals(40, split.icon.height)
			assert.equals(side == "LEFT" and "TOPLEFT" or "TOPRIGHT", split.icon.point)
			assert.equals(40, split.icon.side)
			cfg.portraitLayout = "stack"
			local stack = UF.CastbarLayout.Compute(60, 40, cfg, true)
			assert.equals(60, stack.icon.width)
			assert.equals(19.5, stack.icon.height)
			assert.equals(60, stack.icon.side)
			assert.same({ "TOPLEFT", "icon", "BOTTOMLEFT", 0, -1 }, stack.bar[1])
			assert.equals(40, UF.CastbarLayout.Compute(60, 40, cfg, false).icon.width)
		end
		CreateFrame = create
	end)

	it("handles small hosts, padding and hidden icons and keeps host policy outside the leaf schema", function()
		local UF = Helpers.LoadAddon()
		local C = UF.Components.Castbar
		local cfg = UF.Schema.Resolve(C.BuildSchema(), {}, UF.Config:GetTheme())
		local tiny = UF.CastbarLayout.Compute(1, 1, cfg, false)
		assert.equals(1, tiny.icon.height)
		assert.equals(1, tiny.icon.side)
		assert.equals(70 - 6, UF.CastbarLayout.Compute(60, 40, cfg, false, 70).icon.side, "covers the tallest the host can grow")
		cfg.icon.enabled = false
		local noIcon = UF.CastbarLayout.Compute(60, 40, cfg, false)
		assert.is_nil(noIcon.icon)
		assert.same({ "TOPLEFT", "frame", "TOPLEFT", 3, -3 }, noIcon.bar[1])
		assert.is_true(UF.Schema.Find(C.BuildSchema(), "portraitLayout").hidden({ placement = "portrait" }))
		local schema = UF.Units:GetSchema("player")
		local hidden = UF.Schema.Find(schema, "castbar.portraitLayout").hidden
		assert.is_false(hidden({ placement = "portrait" }))
		assert.is_true(hidden({ placement = "bottom" }))
	end)
end)
