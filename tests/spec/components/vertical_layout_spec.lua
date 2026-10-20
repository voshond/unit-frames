local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Shared column layout #shields", function()
	local UF, uf
	before_each(function()
		UF = Helpers.LoadAddon(true)
		uf = UF.Units:CreateFromDefinition(UF.Units.definitions.pet, CreateFrame("Frame"), {
			barLayout = "columns", columnHeight = 90, spacing = 2,
			border = { enabled = false, padding = 0 },
			health = { columnWidth = 16, bar = { orientation = "VERTICAL" } },
			power = { columnWidth = 5, bar = { orientation = "VERTICAL", reverseFill = true } },
		})
	end)

	it("uses explicit column widths while preserving independent fill directions", function()
		assert.equals(23, uf.layout.width)
		assert.equals(90, uf.layout.height)
		local health, power = uf:GetRow("health"), uf:GetRow("power")
		assert.equals(16, health:GetBar().knownWidth)
		assert.equals(5, power:GetBar().knownWidth)
		assert.same({ "TOPLEFT", uf:GetFrame(), "TOPLEFT", 18, 0 }, power:GetFrame():GetAnchor("TOPLEFT"))
		assert.equals(90, power:GetFrame():GetHeight())
		assert.equals("VERTICAL", power:GetBar().bar.__state.orientation)
		assert.is_true(power:GetBar().bar.__state.reverseFill)
		UF.Units:ShowSample(uf, UF.Units.SAMPLE)
		assert.is_not_nil(health:GetBar().segmentsByKey.absorb)
		uf:SetFillHeight(120)
		uf:Layout()
		assert.equals(120, uf.layout.height)
	end)

	it("keeps auxiliary rows horizontal and disables native aura collapse in columns", function()
		local cfg = UF.Util.Copy(uf.config)
		cfg.castbar = { enabled = true, placement = "top", height = 14 }
		cfg.auraBar = { enabled = true, collapse = true, height = 18, position = "bottom" }
		uf:Apply(cfg)
		assert.is_false(uf.layout.auraBarCollapses)
		assert.equals(126, uf.layout.height)
		assert.equals(23, uf:GetPart("castbar").knownWidth)
		assert.equals(14, uf:GetPart("castbar").knownHeight)
		assert.equals(-16, uf.layout.rows[2].y)
	end)

	it("retains row sizing when returning to the default arrangement", function()
		uf:Apply({ width = 160, border = { padding = 0 }, health = { height = 24 }, power = { height = 5 }, spacing = 1 })
		assert.equals(160, uf.layout.width)
		assert.equals(30, uf.layout.height)
		assert.equals(160, uf:GetRow("health"):GetBar().knownWidth)
	end)
end)

describe("Shared rotated text", function()
	local UF, row
	before_each(function()
		UF = Helpers.LoadAddon(true)
		row = UF.Components.TextBar:New(CreateFrame("Frame"), {}, UF.UnitRows.Spec("health"))
		row:SetKnownSize(20, 100)
	end)

	it("uses configured bar height for rotated text and restores horizontal anchors", function()
		row:Apply({ left = { rotation = 90, enabled = true, vertical = "middle", size = 10, inset = 3 } })
		local text = row:GetText("left")
		assert.equals(math.pi / 2, text.frame.__state.rotation)
		assert.equals(94, text.frame:GetWidth())
		assert.is_not_nil(text.frame:GetAnchor("CENTER"))
		text:SetText(Mock.Secret("Opaque name"))
		row:SetKnownSize(20, 120)
		assert.equals(114, text.frame:GetWidth())
		row:Apply({ left = { rotation = -90, enabled = true, vertical = "middle" } })
		assert.equals(-math.pi / 2, text.frame.__state.rotation)
		row:Apply({ left = { enabled = true } })
		assert.equals(0, text.frame.__state.rotation)
		assert.is_not_nil(text.frame:GetAnchor("LEFT"))
		assert.is_nil(text.frame:GetAnchor("CENTER"))
	end)

	it("does not rewrite rotated geometry when the configuration and dimensions are unchanged", function()
		local config = { left = { rotation = 90, enabled = true } }
		row:Apply(config)
		UF.Perf.counters = {}
		row:Apply(config)
		row:SetKnownSize(20, 100)
		local counters = UF.Perf.counters
		UF.Perf.counters = nil
		assert.is_nil(counters.textLayoutWrite)
	end)
end)
