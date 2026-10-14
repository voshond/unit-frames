local Helpers = require("helpers")
local Mock = Helpers.Mock

-- A text and the small text below it as one centred block (TextBar textLayout).
describe("Centred bar text #textlayout", function()
	local ns, row
	before_each(function()
		ns = Helpers.LoadAddon(true)
		row = ns.Components.TextBar:New(CreateFrame("Frame"), {}, {
			formats = ns.Formats.HEALTH,
			textDefaults = { left = "name", right = "health:value", belowLeft = { format = "level:class", enabled = false } },
		})
	end)

	local function Anchor(key, point)
		return row:GetText(key).frame:GetAnchor(point)
	end
	local function Host() return row:GetBar():GetTextParent() end

	it("keeps the top and bottom layout by default", function()
		row:Apply({ belowLeft = { enabled = true } })
		assert.equals("edges", row.resolved.textLayout)
		assert.same({ "TOPLEFT", Host(), "TOPLEFT", 4, -1 }, Anchor("left", "TOPLEFT"))
		assert.same({ "BOTTOMLEFT", Host(), "BOTTOMLEFT", 4, 1 }, Anchor("belowLeft", "BOTTOMLEFT"))
	end)

	it("centres both lines around the middle by their font sizes and the gap", function()
		row:Apply({ textLayout = "centred", belowLeft = { enabled = true } })
		local size = row:GetText("left").resolved.size
		assert.same({ "LEFT", Host(), "LEFT", 4, (9 + 1) / 2 }, Anchor("left", "LEFT"))
		assert.same({ "RIGHT", Host(), "RIGHT", -4, (9 + 1) / 2 }, Anchor("left", "RIGHT"))
		assert.same({ "LEFT", Host(), "LEFT", 4, -(size + 1) / 2 }, Anchor("belowLeft", "LEFT"))

		row:Apply({ textLayout = "centred", lineGap = 4, belowLeft = { enabled = true, size = 10, offsetY = 2 },
			left = { size = 14, offsetY = -1 } })
		assert.same({ "LEFT", Host(), "LEFT", 4, (10 + 4) / 2 - 1 }, Anchor("left", "LEFT"))
		assert.same({ "LEFT", Host(), "LEFT", 4, -(14 + 4) / 2 + 2 }, Anchor("belowLeft", "LEFT"))
	end)

	it("centres texts outside a block on their own", function()
		row:Apply({ textLayout = "centred", belowLeft = { enabled = true } })
		assert.same({ "RIGHT", Host(), "RIGHT", -4, 0 }, Anchor("right", "RIGHT"), "no small text below the right one")
		row:Apply({ textLayout = "centred", belowLeft = { enabled = true }, left = { enabled = false } })
		assert.same({ "LEFT", Host(), "LEFT", 4, 0 }, Anchor("belowLeft", "LEFT"), "no main text above")
	end)

	it("lets a position set by hand win and leaves no stale offset", function()
		row:Apply({ textLayout = "centred", belowLeft = { enabled = true }, left = { vertical = "top" } })
		assert.same({ "TOPLEFT", Host(), "TOPLEFT", 4, -1 }, Anchor("left", "TOPLEFT"))
		row:Apply({ textLayout = "centred", belowLeft = { enabled = true }, left = { vertical = "middle" } })
		assert.same({ "LEFT", Host(), "LEFT", 4, 0 }, Anchor("left", "LEFT"))
		row:Apply({ textLayout = "centred", belowLeft = { enabled = true } })
		row:Apply({ textLayout = "centred", belowLeft = { enabled = true } })
		assert.same({ "LEFT", Host(), "LEFT", 4, 5 }, Anchor("left", "LEFT"), "repeated apply")
		row:Apply({ textLayout = "centred" })
		assert.same({ "LEFT", Host(), "LEFT", 4, 0 }, Anchor("left", "LEFT"), "small text off")
		row:Apply({ belowLeft = { enabled = true } })
		assert.same({ "TOPLEFT", Host(), "TOPLEFT", 4, -1 }, Anchor("left", "TOPLEFT"), "back to edges")
		assert.same({ "BOTTOMLEFT", Host(), "BOTTOMLEFT", 4, 1 }, Anchor("belowLeft", "BOTTOMLEFT"))
	end)

	it("offers the gap only for the centred layout", function()
		local schema = ns.Components.TextBar.BuildSchema({ formats = ns.Formats.HEALTH })
		local gap = ns.Schema.Find(schema, "lineGap")
		assert.is_true(gap.hidden({ textLayout = "edges" }))
		assert.is_false(gap.hidden({ textLayout = "centred" }))
	end)
end)

describe("Centred bar text on a collapsing health bar #textlayout", function()
	it("stays on the resizing bar's middle without reading its geometry", function()
		local _, CG = Helpers.LoadClickGrid()
		CG.Config:SetStyle("member", "auraBar.enabled", true)
		CG.Config:SetStyle("member", "health.textLayout", "centred")
		CG.Config:SetStyle("member", "health.belowLeft.enabled", true)
		local uf = CG.headers.party:GetAttribute("child1").Member.uf
		local row = uf:GetRow("health")
		local overlay = row:GetBar():GetTextParent()
		local left, below = row:GetText("left"):GetFrame(), row:GetText("belowLeft"):GetFrame()
		local high, low = left:GetAnchor("LEFT"), below:GetAnchor("LEFT")
		assert.same({ "LEFT", overlay, "LEFT" }, { high[1], high[2], high[3] })
		assert.same({ "LEFT", overlay, "LEFT" }, { low[1], low[2], low[3] })
		assert.is_true(high[5] > 0 and low[5] < 0)
		assert.is_true(Mock.HasLayoutAspect(left) and Mock.HasLayoutAspect(below))
		-- Collapsing and expanding move the bar, not the anchors.
		assert.has_no_error(function() CG.Config:SetStyle("member", "auraBar.position", "top") end)
		assert.same(high, left:GetAnchor("LEFT"))
	end)
end)

describe("Centred bar text in the Workbench #textlayout", function()
	it("updates the preview row", function()
		local _, workbench = Helpers.LoadWorkbench()
		workbench:Toggle()
		workbench:Select("unit.target")
		workbench.styleTarget.set("health.belowLeft.enabled", true)
		workbench.styleTarget.set("health.textLayout", "centred")
		local health = workbench.handle.parts.uf:GetRow("health")
		local anchor = health:GetText("left"):GetFrame():GetAnchor("LEFT")
		assert.equals(health:GetBar():GetTextParent(), anchor[2])
		assert.is_true(anchor[5] > 0)
		workbench.styleTarget.set("health.textLayout", "edges")
		assert.is_not_nil(health:GetText("left"):GetFrame():GetAnchor("TOPLEFT"))
	end)
end)
