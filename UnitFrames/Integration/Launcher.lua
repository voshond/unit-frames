local _, ns = ...

-- Broker displays provide LibDataBroker themselves. Register immediately
-- when it is available, or after a later addon supplies it.
local loader = CreateFrame("Frame")
local function Register()
	local broker = LibStub("LibDataBroker-1.1", true)
	if not broker then return end
	ns.launcher = broker:NewDataObject(ns.name, {
		type = "launcher",
		label = "UnitFrames",
		icon = [[Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes]],
		iconCoords = { 0, 0.25, 0, 0.25 }, -- warrior portrait from Blizzard's class sheet
		OnClick = function(_, button)
			if button == "LeftButton" then ns:OpenWorkbench() end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("UnitFrames")
			tooltip:AddLine("Left-click to toggle the Workbench (/uf wb).", 1, 1, 1)
		end,
	})
	loader:UnregisterEvent("ADDON_LOADED")
	loader:SetScript("OnEvent", nil)
end

loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", Register)
Register()
