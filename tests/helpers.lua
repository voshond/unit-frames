-- Shared helpers for specs: a fresh mocked client with the addon loaded.
local Mock = dofile("tests/mock/wow.lua")
local NewStubOUF = dofile("tests/mock/ouf.lua")

local Helpers = { Mock = Mock }

-- Libraries that need the real client; tests use stand-ins instead.
local SKIP = {
	"Libs/oUF/",         -- replaced by tests/mock/ouf.lua
	"Libs/LibEditMode/", -- optional at runtime (LibStub(..., true))
}

local function Skipped(path)
	for _, pattern in ipairs(SKIP) do
		if path:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Files are read and compiled once per run. Calling a compiled chunk again
-- runs its main body afresh (new locals and closures), like a fresh load, so
-- every addon load still starts from a clean state.
local chunks, includes, tocs = {}, {}, {}

local function Compile(path)
	local chunk = chunks[path]
	if not chunk then
		chunk = assert(loadfile(path))
		chunks[path] = chunk
	end
	return chunk
end

-- Only <Script file="..."/> and <Include file="..."/> are followed.
local function XmlIncludes(path)
	local files = includes[path]
	if not files then
		local dir = path:match("^(.*)/[^/]+$")
		local xml = assert(io.open(path)):read("*a")
		files = {}
		for file in xml:gmatch('<%a+%s+file%s*=%s*["\']([^"\']+)["\']') do
			files[#files + 1] = dir .. "/" .. file:gsub("\\", "/")
		end
		includes[path] = files
	end
	return files
end

local function TocFiles(tocPath)
	local files = tocs[tocPath]
	if not files then
		local dir = tocPath:match("^(.*)/[^/]+$")
		files = {}
		for line in io.lines(tocPath) do
			line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
			if line ~= "" and not line:match("^#") then
				files[#files + 1] = dir .. "/" .. line:gsub("\\", "/")
			end
		end
		tocs[tocPath] = files
	end
	return files
end

local function LoadFile(path, addonName, ns)
	if Skipped(path) then
		return
	end
	if path:match("%.xml$") then
		for _, file in ipairs(XmlIncludes(path)) do
			LoadFile(file, addonName, ns)
		end
	elseif path:match("%.lua$") then
		Compile(path)(addonName, ns)
	else
		error("tests can't load " .. path)
	end
end

-- Loads every file listed in a TOC, in order, passing (addonName, ns) as the
-- chunk varargs exactly like the client does.
function Helpers.LoadToc(tocPath, addonName, ns)
	ns = ns or {}
	for _, file in ipairs(TocFiles(tocPath)) do
		LoadFile(file, addonName, ns)
	end
	Mock.loadedAddons[addonName] = true
	return ns
end

-- Fresh mock client + freshly loaded UnitFrames (with the stub oUF as ns.oUF).
-- initialize = true also runs the ADDON_LOADED setup (AceDB, media);
-- login = true also runs the oUF factories (spawns the unit frames).
function Helpers.LoadAddon(initialize, login)
	Mock.Install()
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
function Helpers.LoadWorkbench()
	Mock.Install()
	Mock.InstallUI()
	local ns = { oUF = NewStubOUF(Mock) }
	Helpers.LoadToc("UnitFrames/UnitFrames.toc", "UnitFrames", ns)
	Mock.FireEvent("ADDON_LOADED", "UnitFrames")
	ns.oUF:RunFactories()
	Helpers.LoadToc("UnitFrames_Workbench/UnitFrames_Workbench.toc", "UnitFrames_Workbench")
	return ns, ns.Workbench
end

function Helpers.LoadClickGrid(workbench)
	local ns = Helpers.LoadAddon(true, true)
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

return Helpers
