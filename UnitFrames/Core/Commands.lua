local _, ns = ...

local HELP = {
	"/uf help - show this list of commands",
	"/uf wb - open settings and previews",
	"/uf logs [clear] - show or clear saved diagnostic entries",
	"/uf perf help - show developer performance commands",
}

-- Loads the Workbench on demand and shows it, optionally at an entry.
function ns:OpenWorkbench(entryId)
	local loaded, reason = C_AddOns.LoadAddOn("UnitFrames_Workbench")
	if not loaded then
		self:Print("could not load UnitFrames_Workbench:", reason or "unknown reason")
		return
	end
	if entryId then
		self.Workbench:Open(entryId)
	else
		self.Workbench:Toggle()
	end
end

local commands = {}

function commands.help()
	ns:Print("version", ns.version)
	for _, line in ipairs(HELP) do
		ns:Print(line)
	end
end

function commands.wb()
	ns:OpenWorkbench()
end
commands.workbench = commands.wb

SLASH_UNITFRAMES1 = "/uf"
SLASH_UNITFRAMES2 = "/unitframes"
SlashCmdList.UNITFRAMES = function(msg)
	local command = strtrim(msg or ""):lower()
	local arguments = command:match("^perf%s*(.*)$")
	if command == "perf" or command:match("^perf%s") then ns.Perf:Command(arguments); return end
	if command == "logs" or command:match("^logs%s") then
		ns.Logs:Command(command:match("^logs%s*(.*)$"))
		return
	end
	local handler = commands[command]
	if handler then
		handler()
	else
		commands.help()
	end
end
