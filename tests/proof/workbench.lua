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

local function BuffShowcase(index)
	return function()
		local _, _, workbench = Helpers.LoadClickGrid(true)
		UnitClass = function() return "Druid", "DRUID", 11 end
		workbench:Open("clickgrid.buffs")
		return workbench.handle.cards[index].frame
	end
end

local function OnboardingGroupHeals()
	local ns = Helpers.LoadClickGrid()
	local ob = Helpers.LoadToc("UnitFrames_Onboarding/UnitFrames_Onboarding.toc", "UnitFrames_Onboarding")
	UnitClass = function() return "Druid", "DRUID", 11 end
	ns.Onboarding:Open()
	ob.Pending:SelectPreset("healer")
	ns.Onboarding:Next()
	ns.Onboarding:Next()
	return ob.Steps.Extras.map
end

return {
	{ name = "workbench-player", build = UnitPreview("unit.player") },
	{ name = "workbench-target", build = UnitPreview("unit.target") },
	{ name = "clickgrid-panel", build = ClickGridPreview("clickgrid.panel") },
	{ name = "clickgrid-member-heals", build = DruidMemberHeals },
	{ name = "clickgrid-buffs-outside", build = BuffShowcase(1) },
	{ name = "clickgrid-buffs-inside", build = BuffShowcase(2) },
	{ name = "clickgrid-buffs-bar", build = BuffShowcase(3) },
	{ name = "onboarding-group-heals", build = OnboardingGroupHeals },
}
