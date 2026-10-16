local Helpers = require("helpers")

describe("Component apply geometry", function()
	local ns, uf
	before_each(function()
		ns = Helpers.LoadAddon(true)
		uf = ns.Units:CreateFrame("target", UIParent)
	end)

	local function Watch(object, method)
		local count, original = 0, object[method]
		object[method] = function(self, ...)
			count = count + 1
			return original(self, ...)
		end
		return function() return count end
	end

	it("leaves row, portrait and text anchors alone for equal fresh configs and colour edits", function()
		local row = uf:GetRow("health")
		local rowClears = Watch(row:GetFrame(), "ClearAllPoints")
		local textClears = Watch(row:GetText("left"):GetFrame(), "ClearAllPoints")
		local portraitClears = Watch(uf:GetPart("portrait"):GetFrame(), "ClearAllPoints")
		uf:Apply(ns.Util.Copy(uf.config))
		uf:Apply({ health = { bar = { color = { 0.2, 0.3, 0.4, 1 } }, left = { color = { 1, 0, 0, 1 } } } })
		assert.equals(0, rowClears())
		assert.equals(0, textClears())
		assert.equals(0, portraitClears())
	end)

	it("updates width, padding, fill height and row toggles immediately", function()
		local row = uf:GetRow("health"):GetFrame()
		uf:Apply({ width = 310, border = { padding = 7 } })
		assert.equals(7, row:GetAnchor("TOPLEFT")[4])
		assert.equals(-uf.layout.rows[1].right, row:GetAnchor("TOPRIGHT")[4])
		assert.equals(310 + uf.layout.portrait.width + uf.resolved.portrait.gap, uf:GetFrame():GetWidth())
		uf:SetFillHeight(180)
		uf:Apply()
		assert.equals(180, uf:GetFrame():GetHeight())
		assert.is_true(row:GetHeight() > uf.resolved.health.height)
		uf:Apply({ health = { enabled = false } })
		assert.is_nil(row:GetAnchor("TOPLEFT"))
		uf:SetFillHeight(nil)
		uf:Apply({})
		assert.is_not_nil(row:GetAnchor("TOPLEFT"))
		assert.equals(uf.resolved.health.height, row:GetHeight())
	end)

	it("updates inherited text size, sibling dependencies and leading decoration space", function()
		uf:Apply({ health = { textLayout = "centred", belowLeft = { enabled = true } } })
		local row = uf:GetRow("health")
		local below = row:GetText("belowLeft"):GetFrame()
		ns.Config:SetThemeValue("fontSize", 18)
		assert.equals(-(row:GetText("left").resolved.size + uf.resolved.health.lineGap) / 2, below:GetAnchor("LEFT")[5])
		local text = row:GetText("left")
		text:SetLeadingSpace(23)
		assert.equals(text.resolved.inset + text.resolved.offsetX + 23, text:GetFrame():GetAnchor("LEFT")[4])
		text:SetLeadingSpace(0)
		assert.equals(text.resolved.inset + text.resolved.offsetX, text:GetFrame():GetAnchor("LEFT")[4])
	end)

	it("restores castbar row anchors after covering health", function()
		local config = { castbar = { enabled = true, placement = "top" } }
		uf:Apply(config)
		local castbar = uf:GetPart("castbar"):GetFrame()
		local anchor = castbar:GetAnchor("TOPLEFT")
		config.castbar.placement = "health"
		uf:Apply(config)
		config.castbar.placement = "top"
		uf:Apply(config)
		assert.same(anchor, castbar:GetAnchor("TOPLEFT"))
	end)
end)
