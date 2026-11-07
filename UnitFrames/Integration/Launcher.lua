local _, ns = ...

local Launcher = {}
ns.Launcher = Launcher

local DBIcon = LibStub("LibDBIcon-1.0")

local function Settings()
	return ns.Config.db and ns.Config.db.global.minimap
end

function Launcher:IsMinimapShown()
	local settings = Settings()
	return not (settings and settings.hide)
end

function Launcher:SetMinimapShown(shown)
	local settings = Settings()
	if not settings then return end
	settings.hide = not shown
	if shown then
		DBIcon:Show(ns.name)
	else
		DBIcon:Hide(ns.name)
	end
	ns.Events:Fire("MinimapIconChanged", shown)
end

function Launcher:ToggleMinimap()
	self:SetMinimapShown(not self:IsMinimapShown())
end

local function BuildMenu(_, root)
	root:CreateTitle("UnitFrames")
	root:CreateButton("Toggle Workbench", function() ns:OpenWorkbench() end)
	root:CreateCheckbox("Show minimap icon",
		function() return Launcher:IsMinimapShown() end,
		function() Launcher:ToggleMinimap() end)
end

ns.launcher = LibStub("LibDataBroker-1.1"):NewDataObject(ns.name, {
	type = "launcher",
	label = "UnitFrames",
	icon = [[Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes]],
	iconCoords = { 0, 0.25, 0, 0.25 },
	OnClick = function(owner, button)
		if button == "LeftButton" then
			ns:OpenWorkbench()
			return
		end
		if button == "RightButton" then
			MenuUtil.CreateContextMenu(owner, BuildMenu)
		end
	end,
	OnTooltipShow = function(tooltip)
		tooltip:AddLine("UnitFrames")
		tooltip:AddLine("Left-click to toggle the Workbench (/uf wb).", 1, 1, 1)
		tooltip:AddLine("Right-click for options.", 1, 1, 1)
	end,
})

ns.Events.RegisterCallback(Launcher, "Initialized", function()
	DBIcon:Register(ns.name, ns.launcher, Settings())
end)
