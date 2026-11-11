local Helpers = require("helpers")

local function UnitPreview(entry)
	return function()
		local _, workbench = Helpers.LoadWorkbench()
		workbench:Open(entry)
		return workbench.handle.parts.uf:GetFrame()
	end
end

local function ClickGridPreview(entry)
	return function()
		local _, _, workbench = Helpers.LoadClickGrid(true)
		workbench:Open(entry)
		return workbench.handle.frame
	end
end

local function DruidMemberHeals()
	local _, _, workbench = Helpers.LoadClickGrid(true)
	UnitClass = function() return "Druid", "DRUID", 11 end
	workbench:Open("clickgrid.panel")
	return workbench.handle.cells[1].frame
end

return {
	{ name = "workbench-player", build = UnitPreview("unit.player") },
	{ name = "workbench-target", build = UnitPreview("unit.target") },
	{ name = "clickgrid-panel", build = ClickGridPreview("clickgrid.panel") },
	{ name = "clickgrid-member-heals", build = DruidMemberHeals },
}
