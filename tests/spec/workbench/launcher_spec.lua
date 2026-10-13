local Helpers = require("helpers")
local Mock = Helpers.Mock

local function AddBroker()
	local broker = LibStub:NewLibrary("LibDataBroker-1.1", 4)
	broker.objects, broker.created = {}, 0
	function broker:NewDataObject(name, object)
		assert.is_nil(self.objects[name], "launcher must only register once")
		self.created = self.created + 1
		self.objects[name] = object
		return object
	end
	return broker
end

describe("Workbench broker launcher", function()
	it("registers when the display loads later and ignores further addon loads", function()
		local ns = Helpers.LoadAddon(true)
		assert.is_nil(ns.launcher)
		Mock.FireEvent("ADDON_LOADED", "UnrelatedAddon")
		assert.is_nil(ns.launcher)
		local broker = AddBroker()
		Mock.FireEvent("ADDON_LOADED", "BrokerDisplay")
		assert.equals(ns.launcher, broker.objects.UnitFrames)
		assert.equals("launcher", ns.launcher.type)
		assert.equals("UnitFrames", ns.launcher.label)
		assert.equals("string", type(ns.launcher.icon))
		Mock.FireEvent("ADDON_LOADED", "AnotherAddon")
		assert.equals(1, broker.created)
	end)

	it("registers with a broker already loaded before the core", function()
		Mock.Install()
		dofile("UnitFrames/Libs/LibStub/LibStub.lua")
		local broker = AddBroker()
		local ns = Helpers.LoadToc("UnitFrames/UnitFrames.toc", "UnitFrames", {
			oUF = dofile("tests/mock/ouf.lua")(Mock),
		})
		assert.equals(ns.launcher, broker.objects.UnitFrames)
		assert.equals(1, broker.created)
	end)

	it("loads and toggles the Workbench through the slash command handler", function()
		local ns = Helpers.LoadAddon(true)
		AddBroker()
		Mock.FireEvent("ADDON_LOADED", "BrokerDisplay")
		local loads, toggles = {}, 0
		C_AddOns.LoadAddOn = function(name) loads[#loads + 1] = name; return true end
		ns.Workbench = { Toggle = function() toggles = toggles + 1 end }
		ns.launcher.OnClick(nil, "LeftButton")
		ns.launcher.OnClick(nil, "LeftButton")
		SlashCmdList.UNITFRAMES("wb")
		assert.same({ "UnitFrames_Workbench", "UnitFrames_Workbench", "UnitFrames_Workbench" }, loads)
		assert.equals(3, toggles)
		ns.launcher.OnClick(nil, "RightButton")
		assert.equals(3, toggles)
		local reported
		C_AddOns.LoadAddOn = function() return false, "DISABLED" end
		ns.Print = function(_, _, reason) reported = reason end
		ns.launcher.OnClick(nil, "LeftButton")
		assert.equals("DISABLED", reported)
		assert.equals(3, toggles)
	end)

	it("fills the display's tooltip without controlling its anchors or visibility", function()
		local ns = Helpers.LoadAddon(true)
		AddBroker()
		Mock.FireEvent("ADDON_LOADED", "BrokerDisplay")
		local lines = {}
		ns.launcher.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
		assert.same({ "UnitFrames", "Left-click to toggle the Workbench (/uf wb)." }, lines)
	end)
end)
