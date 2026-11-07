local Helpers = require("helpers")
local Mock = Helpers.Mock

local function MinimapButton()
	return LibStub("LibDBIcon-1.0"):GetMinimapButton("UnitFrames")
end

local function MenuElement(kind)
	for _, element in ipairs(Mock.contextMenu.menu.__state.elements) do
		if element.__state.kind == kind then return element.__state end
	end
end

local function TrackWorkbench(ns)
	local tracked = { loads = {}, toggles = 0 }
	C_AddOns.LoadAddOn = function(name) tracked.loads[#tracked.loads + 1] = name; return true end
	ns.Workbench = { Toggle = function() tracked.toggles = tracked.toggles + 1 end }
	return tracked
end

describe("Minimap launcher #minimap", function()
	it("registers one broker launcher at load for Titan and other displays", function()
		local ns = Helpers.LoadAddon()
		local broker = LibStub("LibDataBroker-1.1")
		assert.equals(ns.launcher, broker:GetDataObjectByName("UnitFrames"))
		assert.equals("launcher", ns.launcher.type)
		assert.equals("UnitFrames", ns.launcher.label)
		assert.equals("string", type(ns.launcher.icon))
		assert.is_nil(MinimapButton())
	end)

	it("puts a minimap button on the minimap once initialized and shows it at login", function()
		Helpers.LoadAddon(true)
		local button = MinimapButton()
		assert.is_not_nil(button)
		assert.equals(Minimap, button:GetParent())
		Mock.FireEvent("PLAYER_LOGIN")
		assert.is_true(button:IsShown())
	end)

	it("toggles the Workbench on left-click and through the slash command", function()
		local ns = Helpers.LoadAddon(true)
		local tracked = TrackWorkbench(ns)
		ns.launcher.OnClick(MinimapButton(), "LeftButton")
		SlashCmdList.UNITFRAMES("wb")
		assert.same({ "UnitFrames_Workbench", "UnitFrames_Workbench" }, tracked.loads)
		assert.equals(2, tracked.toggles)
		local reported
		C_AddOns.LoadAddOn = function() return false, "DISABLED" end
		ns.Print = function(_, _, reason) reported = reason end
		ns.launcher.OnClick(MinimapButton(), "LeftButton")
		assert.equals("DISABLED", reported)
		assert.equals(2, tracked.toggles)
	end)

	it("opens an options menu on right-click without toggling the Workbench", function()
		local ns = Helpers.LoadAddon(true)
		local tracked = TrackWorkbench(ns)
		local button = MinimapButton()
		ns.launcher.OnClick(button, "RightButton")
		assert.equals(0, tracked.toggles)
		assert.equals(button, Mock.contextMenu.owner)
		assert.equals("UnitFrames", MenuElement("title").text)
		MenuElement("button").callback()
		assert.equals(1, tracked.toggles)
		local checkbox = MenuElement("checkbox")
		assert.equals("Show minimap icon", checkbox.text)
		assert.is_true(checkbox.isSelected())
	end)

	it("hides and shows the icon from the right-click menu and saves it account-wide", function()
		local ns = Helpers.LoadAddon(true)
		Mock.FireEvent("PLAYER_LOGIN")
		local changes = {}
		ns.Events.RegisterCallback(changes, "MinimapIconChanged", function(_, shown) changes[#changes + 1] = shown end)
		ns.launcher.OnClick(MinimapButton(), "RightButton")
		MenuElement("checkbox").setSelected()
		assert.is_false(MinimapButton():IsShown())
		assert.is_true(ns.Config.db.global.minimap.hide)
		assert.is_false(MenuElement("checkbox").isSelected())
		MenuElement("checkbox").setSelected()
		assert.is_true(MinimapButton():IsShown())
		assert.is_false(ns.Config.db.global.minimap.hide)
		assert.same({ false, true }, changes)
	end)

	it("restores a hidden icon and its position from saved variables", function()
		Helpers.LoadAddon(true, false, { global = { minimap = { hide = true, minimapPos = 90 } } })
		Mock.FireEvent("PLAYER_LOGIN")
		local button = MinimapButton()
		assert.is_false(button:IsShown())
		assert.equals(90, button.db.minimapPos)
	end)

	it("toggles the icon with /uf minimap", function()
		local ns = Helpers.LoadAddon(true)
		Mock.FireEvent("PLAYER_LOGIN")
		local printed = {}
		ns.Print = function(_, message) printed[#printed + 1] = message end
		SlashCmdList.UNITFRAMES("minimap")
		assert.is_false(MinimapButton():IsShown())
		SlashCmdList.UNITFRAMES("minimap")
		assert.is_true(MinimapButton():IsShown())
		assert.same({ "minimap icon hidden", "minimap icon shown" }, printed)
	end)

	it("describes both clicks in the tooltip without controlling its anchors or visibility", function()
		local ns = Helpers.LoadAddon(true)
		local lines = {}
		ns.launcher.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
		assert.same({ "UnitFrames", "Left-click to toggle the Workbench (/uf wb).", "Right-click for options." }, lines)
	end)

	it("offers the icon on the Global Settings General page and follows changes made elsewhere", function()
		local UF, wb = Helpers.LoadWorkbench()
		wb:Open("theme")
		wb:SelectFeaturePage("@general")
		local row
		for _, candidate in ipairs(wb.inspector.page.rows) do
			if candidate.path == "minimapIcon" then row = candidate end
		end
		assert.is_not_nil(row)
		assert.is_true(row.control:GetValue())
		row.control.opts.onChange(false)
		assert.is_false(row.control:GetValue())
		assert.is_false(UF.Launcher:IsMinimapShown())
		assert.is_false(MinimapButton():IsShown())
		UF.Launcher:SetMinimapShown(true)
		assert.is_true(row.control:GetValue())
		assert.is_true(MinimapButton():IsShown())
	end)
end)
