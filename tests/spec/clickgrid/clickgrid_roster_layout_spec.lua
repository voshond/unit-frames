local Helpers = require("helpers")
local Mock = Helpers.Mock

local function Raid(subgroups)
	Mock.inRaid, Mock.groupSize, Mock.raidSubgroups = true, #subgroups, subgroups
	Mock.FireEvent("GROUP_ROSTER_UPDATE")
end

describe("ClickGrid raid roster layout", function()
	local UF, CG
	before_each(function() UF, CG = Helpers.LoadClickGrid() end)

	local function SlotX(slot)
		local block, gap = CG.layout.sections.group1.grid, CG.Config:Resolved().panel.spacingX
		local left = UF.Components.Backdrop.Padding(CG.Config:Resolved().border)
		return left + (slot - 1) * (block.width + gap)
	end

	it("packs populated subgroups and sizes the panel to them", function()
		Raid({ 1, 1, 5, 5, 2 })
		local layout = CG.layout
		assert.same({ 1, 2, 5 }, layout.groups)
		assert.equals(SlotX(1), layout.sections.group1.x)
		assert.equals(SlotX(2), layout.sections.group2.x)
		assert.equals(SlotX(3), layout.sections.group5.x)
		assert.is_false(layout.sections.group5.parked)
		assert.is_true(layout.sections.group3.parked)
		local _, right = UF.Components.Backdrop.Padding(CG.Config:Resolved().border)
		assert.equals(SlotX(3) + layout.sections.group1.grid.width + right, layout.raid.width)
		assert.equals(layout.raid.width, CG.panel:GetAttribute("raid-width"))
		assert.equals(layout.raid.width, CG.panel:GetWidth())
		assert.is_true(CG:GetHeaderTitles(CG.headers.group5).label:IsShown())
		assert.is_false(CG:GetHeaderTitles(CG.headers.group3).label:IsShown())
	end)

	it("wraps packed subgroups at the configured column count", function()
		CG.Config:Set("panel.columns", 2)
		Raid({ 1, 3, 4, 8 })
		local layout = CG.layout
		assert.equals(layout.sections.group1.y, layout.sections.group3.y)
		assert.equals(layout.sections.group1.x, layout.sections.group4.x)
		assert.is_true(layout.sections.group4.y > layout.sections.group1.y)
		assert.equals(SlotX(2), layout.sections.group8.x)
		assert.equals(layout.sections.group4.y, layout.sections.group8.y)
	end)

	it("keeps parked subgroups live in combat and re-packs after combat", function()
		Raid({ 1, 1 })
		local before = CG.layout
		assert.same({ 1 }, before.groups)
		Mock.inCombat = true
		assert.has_no_error(function() Raid({ 1, 1, 6 }) end)
		assert.equals(before, CG.layout)
		assert.is_true(CG.headers.group6:GetAttribute("showRaid"))
		assert.equals("custom [group:raid] show; hide", CG.headers.group6.visibility)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.same({ 1, 6 }, CG.layout.groups)
		assert.equals(SlotX(2), CG.layout.sections.group6.x)
		assert.is_true(CG:GetHeaderTitles(CG.headers.group6).label:IsShown())
	end)

	it("ignores roster updates that keep the same populated subgroups", function()
		Raid({ 1, 2 })
		local before = CG.layout
		Raid({ 2, 1, 1 })
		assert.equals(before, CG.layout)
		Raid({ 2, 1, 3 })
		assert.is_true(before ~= CG.layout)
	end)

	it("sizes the flat grid to the roster but keeps forty secure slots", function()
		CG.Config:Set("panel.mode", "flat")
		local twelve = {}
		for index = 1, 12 do twelve[index] = math.ceil(index / 5) end
		Raid(twelve)
		local header, section = CG.headers.raid, CG.layout.sections.raid
		assert.equals(2, section.grid.columns)
		assert.equals(10, section.grid.rows)
		assert.equals(10, header:GetAttribute("unitsPerColumn"))
		assert.equals(4, header:GetAttribute("maxColumns"))
		local columns = CG:GetHeaderTitles(header).columns
		assert.is_true(columns[2]:IsShown())
		assert.is_true(columns[3] == nil or not columns[3]:IsShown())
		CG.Config:Set("panel.flow", "across")
		section = CG.layout.sections.raid
		assert.equals(4, section.grid.columns)
		assert.equals(3, section.grid.rows)
		assert.equals(10, section.capacity.rows)
		Raid({ 1, 1, 1 })
		assert.equals(3, CG.layout.sections.raid.grid.columns)
		assert.equals(1, CG.layout.sections.raid.grid.rows)
	end)
end)

describe("ClickGrid raid roster layout #workbench", function()
	local CG, wb
	before_each(function() _, CG, wb = Helpers.LoadClickGrid(true); wb:Open("clickgrid.panel") end)

	it("previews only the subgroups a static raid fills", function()
		wb.dataTarget.set("count", 12)
		local preview = wb.handle
		assert.same({ 1, 2, 3 }, preview.layout.groups)
		assert.is_true(preview.labels.group3:IsShown())
		assert.is_true(preview.labels.group4 == nil or not preview.labels.group4:IsShown())
		local shown = 0
		for _, cell in ipairs(preview.cells) do if cell.frame:IsShown() then shown = shown + 1 end end
		assert.equals(12, shown)
		assert.equals(preview.layout.raid.width, preview.frame:GetWidth())
		assert.is_true(preview.layout.raid.width < CG.Layout.Compute(CG.Config:Resolved().panel, CG.metrics.member,
			CG.metrics.target, CG.Config:Resolved().titles, CG.Config:Resolved().border, 40).raid.width)
	end)
end)
