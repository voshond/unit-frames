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

-- The mock's ScrollBox view creates no rows, so the sidebar's items are laid
-- out here through the list's own row code.
local function GlobalSettingsMenu()
	local _, workbench = Helpers.LoadWorkbench()
	workbench:Open("theme")
	workbench.list:Select("theme|@auraIcons", true)
	local list = workbench.list
	local menu = CreateFrame("Frame", nil, UIParent)
	menu:SetPoint("TOPLEFT")
	menu:SetSize(list:GetFrame():GetWidth(), #list.items * list.rowHeight)
	for index, item in ipairs(list.items) do
		local row = CreateFrame("Button", nil, menu)
		row:SetPoint("TOPLEFT", 0, -(index - 1) * list.rowHeight)
		row:SetPoint("TOPRIGHT", 0, -(index - 1) * list.rowHeight)
		row:SetHeight(list.rowHeight)
		row.text = false
		list:InitRow(row, item)
	end
	return menu
end

local function GlobalAuraIcons(configure)
	return function()
		local ns, workbench = Helpers.LoadWorkbench()
		if configure then configure(ns) end
		workbench:Open("theme")
		workbench.list:Select("theme|@auraIcons", true)
		return workbench.handle.frame
	end
end

local function LargeSharedDebuffs(ns)
	ns.Config:SetThemeValue("auras.debuffs.size", 34)
	ns.Config:SetThemeValue("auras.buffs.max", 6)
	ns.Config:SetThemeValue("auras.spacing", 4)
end

return {
	{ name = "workbench-global-settings-menu", build = GlobalSettingsMenu },
	{ name = "workbench-global-aura-icons", build = GlobalAuraIcons() },
	{ name = "workbench-global-aura-icons-changed", build = GlobalAuraIcons(LargeSharedDebuffs) },
	{ name = "workbench-player", build = UnitPreview("unit.player") },
	{ name = "workbench-target", build = UnitPreview("unit.target") },
	{ name = "clickgrid-panel", build = ClickGridPreview("clickgrid.panel") },
	{ name = "clickgrid-member-heals", build = DruidMemberHeals },
	{ name = "clickgrid-buffs-outside", build = BuffShowcase(1) },
	{ name = "clickgrid-buffs-inside", build = BuffShowcase(2) },
	{ name = "clickgrid-buffs-bar", build = BuffShowcase(3) },
	{ name = "onboarding-group-heals", build = OnboardingGroupHeals },
}
