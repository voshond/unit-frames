-- Shared helpers for specs: a fresh mocked client with the addon loaded.
local Mock = dofile("tests/mock/wow.lua")
local NewStubOUF = dofile("tests/mock/ouf.lua")
local Loader = require("wowmock.loader")

local Helpers = { Mock = Mock }

-- The wow-ui-testing library folder, and the Blizzard UI source its pin names
-- (present after bash .wut/scripts/update-client-source.sh --sync).
Helpers.WutDir = package.searchpath("wowmock.loader", package.path):match("^(.*)/wowmock/loader%.lua$")
Helpers.ClientSource = Helpers.WutDir .. "/.client-source/forever"

-- Libraries that need the real client; tests use stand-ins instead.
Loader.Skip({
	"Libs/oUF/",         -- replaced by tests/mock/ouf.lua
	"Libs/LibEditMode/", -- optional at runtime (LibStub(..., true))
})

-- Loads every file listed in a TOC, in order, passing (addonName, ns) as the
-- chunk varargs exactly like the client does.
Helpers.LoadToc = Loader.LoadToc

-- Fresh mock client + freshly loaded UnitFrames (with the stub oUF as ns.oUF).
-- initialize = true also runs the ADDON_LOADED setup (AceDB, media);
-- login = true also runs the oUF factories (spawns the unit frames).
-- saved/logs: the UnitFramesDB/UnitFramesLogs saved variables found at load.
function Helpers.LoadAddon(initialize, login, saved, logs)
	Mock.Install()
	_G.UnitFramesLogs = logs
	_G.UnitFramesDB = saved
	local ns = { oUF = NewStubOUF(Mock) }
	Helpers.LoadToc("UnitFrames/UnitFrames.toc", "UnitFrames", ns)
	if initialize or login then
		Mock.FireEvent("ADDON_LOADED", "UnitFrames")
	end
	if login then
		ns.oUF:RunFactories()
	end
	return ns
end

-- Core + Workbench, with the extra UI mocks and the player frame spawned.
-- Returns core ns and the Workbench.
function Helpers.LoadWorkbench(build)
	Mock.Install()
	if build then
		local metadata = C_AddOns.GetAddOnMetadata
		C_AddOns.GetAddOnMetadata = function(name, key)
			if build[key] ~= nil then return build[key] end
			return metadata(name, key)
		end
	end
	_G.UnitFramesLogs = nil
	Mock.InstallUI()
	local ns = { oUF = NewStubOUF(Mock) }
	Helpers.LoadToc("UnitFrames/UnitFrames.toc", "UnitFrames", ns)
	Mock.FireEvent("ADDON_LOADED", "UnitFrames")
	ns.oUF:RunFactories()
	Helpers.LoadToc("UnitFrames_Workbench/UnitFrames_Workbench.toc", "UnitFrames_Workbench")
	return ns, ns.Workbench
end

-- Core (initialized, frames spawned) + Getting started, loaded the way
-- UF:OpenOnboarding loads it. saved: the UnitFramesDB found at load.
-- Returns core ns, the guide and its private namespace.
function Helpers.LoadOnboarding(saved)
	local ns = Helpers.LoadAddon(true, true, saved)
	Mock.InstallUI()
	local ob = Helpers.LoadToc("UnitFrames_Onboarding/UnitFrames_Onboarding.toc", "UnitFrames_Onboarding")
	C_AddOns.LoadAddOn = function(name) return name == "UnitFrames_Onboarding" end
	return ns, ns.Onboarding, ob
end

-- saved: the ClickGrid profile found at load ({ settings, member, target, pet }).
function Helpers.LoadClickGrid(workbench, saved)
	local db = saved and { namespaces = { ClickGrid = { profiles = { Default = saved } } } }
	local ns = Helpers.LoadAddon(true, true, db)
	Mock.InstallUI()
	local cg = Helpers.LoadToc("UnitFrames_ClickGrid/UnitFrames_ClickGrid.toc", "UnitFrames_ClickGrid")
	Mock.FireEvent("ADDON_LOADED", "UnitFrames_ClickGrid")
	Mock.FireEvent("PLAYER_LOGIN")
	if workbench then
		Helpers.LoadToc("UnitFrames_Workbench/UnitFrames_Workbench.toc", "UnitFrames_Workbench")
		Mock.FireEvent("ADDON_LOADED", "UnitFrames_Workbench")
	end
	return ns, cg, ns.Workbench
end

local proof
function Helpers.Snapshot(name, region, options)
	if os.getenv("UF_PROOF") ~= "1" then return nil end
	proof = proof or dofile("tests/proof/setup.lua").Proof()
	return proof:Snapshot(region, "spec-" .. name, options)
end

return Helpers
