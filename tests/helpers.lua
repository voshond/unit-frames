-- Shared helpers for specs: a fresh mocked client with the addon loaded.
local Mock = dofile("tests/mock/wow.lua")

local Helpers = { Mock = Mock }

-- Loads every .lua file listed in a TOC, in order, passing (addonName, ns)
-- as the chunk varargs exactly like the client does.
function Helpers.LoadToc(tocPath, addonName, ns)
	local dir = tocPath:match("^(.*)/[^/]+$")
	ns = ns or {}
	for line in io.lines(tocPath) do
		line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" and not line:match("^#") then
			local path = dir .. "/" .. line:gsub("\\", "/")
			if not path:match("%.lua$") then
				error("tests only load .lua files from the TOC: " .. path)
			end
			local chunk = assert(loadfile(path))
			chunk(addonName, ns)
		end
	end
	return ns
end

-- Fresh mock client + freshly loaded UnitFrames. Pass initialize = true to
-- also run the ADDON_LOADED setup (AceDB, media).
function Helpers.LoadAddon(initialize)
	Mock.Install()
	local ns = Helpers.LoadToc("UnitFrames/UnitFrames.toc", "UnitFrames")
	if initialize then
		Mock.FireEvent("ADDON_LOADED", "UnitFrames")
	end
	return ns
end

-- Core + Workbench, with the extra UI mocks. Returns core ns and the Workbench.
function Helpers.LoadWorkbench()
	local ns = Helpers.LoadAddon(true)
	Mock.InstallUI()
	Helpers.LoadToc("UnitFrames_Workbench/UnitFrames_Workbench.toc", "UnitFrames_Workbench")
	return ns, ns.Workbench
end

return Helpers
