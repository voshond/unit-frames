local Helpers = require("helpers")

describe("ClickGrid empty target state #targets", function()
	local CG
	before_each(function() _, CG = Helpers.LoadClickGrid() end)

	it("draws No Target below each member's target bar while targets are shown", function()
		local cell = CG.headers.party:GetAttribute("child1")
		local empty = CG:GetGridButton(cell.Target).empty
		assert.is_false(empty.frame:IsShown())
		CG.Config:SetStyle("target", "shown", true)
		assert.is_true(empty.frame:IsShown())
		assert.equals("No\nTarget", empty.text:GetText())
		assert.equals(cell, empty.frame:GetParent())
		assert.is_true(empty.frame:GetFrameLevel() < cell.Target:GetFrameLevel())
		CG.Config:SetStyle("target", "shown", false)
		assert.is_false(empty.frame:IsShown())
	end)

	it("follows the target bar's border and fits the text to the row height", function()
		CG.Config:SetStyle("target", "shown", true)
		local empty = CG:GetGridButton(CG.headers.party:GetAttribute("child1").Target).empty
		assert.is_not_nil(empty.frame:GetBackdrop())
		CG.Config:SetStyle("target", "border.enabled", false)
		assert.is_nil(empty.frame:GetBackdrop())
		CG.Config:SetStyle("member", "health.height", 14)
		local _, size = empty.text:GetFont()
		assert.is_true(size * 2 <= CG.layout.cellHeight)
	end)
end)

describe("ClickGrid empty target state #targets #workbench", function()
	local CG, wb
	before_each(function() _, CG, wb = Helpers.LoadClickGrid(true); wb:Open("clickgrid.panel") end)

	it("shows untargeted sample members with the empty state", function()
		CG.Config:SetStyle("target", "shown", true)
		local cells = wb.handle.cells
		assert.is_true(cells[1].target:GetFrame():IsShown())
		assert.is_false(cells[2].target:GetFrame():IsShown())
		assert.is_true(cells[2].empty.frame:IsShown())
		assert.equals("No\nTarget", cells[2].empty.text:GetText())
		CG.Config:SetStyle("target", "shown", false)
		assert.is_false(cells[2].empty.frame:IsShown())
	end)
end)
