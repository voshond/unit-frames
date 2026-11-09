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

return {
	{ name = "workbench-player", build = UnitPreview("unit.player") },
	{ name = "workbench-target", build = UnitPreview("unit.target") },
	{ name = "clickgrid-panel", build = ClickGridPreview("clickgrid.panel") },
}
