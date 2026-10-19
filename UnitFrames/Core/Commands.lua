local _, ns = ...

local HELP = {
	"/uf help - show this list of commands",
	"/uf wb - open settings and previews",
	"/uf logs [clear] - show or clear saved diagnostic entries",
	"/uf dots [reset] - toggle DoT tracking with its trace in chat, or forget learned tick sizes",
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

-- Tracking (and its trace) in chat, to check estimates before any frame shows them.
local function DotsCommand(argument)
	local tracker = ns.DotTracker
	if argument == "reset" then
		tracker:ResetLearned()
		ns:Print("learned DoT tick sizes cleared")
	elseif tracker.owners.command then
		tracker:SetTrace(nil)
		tracker:Release("command")
		ns:Print("DoT trace off")
	else
		tracker:SetTrace(function(message) ns:Print("|cff888888" .. message .. "|r") end)
		tracker:Acquire("command")
		ns:Print("DoT trace on")
	end
end

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
	if command == "dots" or command:match("^dots%s") then DotsCommand(command:match("^dots%s*(.*)$")); return end
	local handler = commands[command]
	if handler then
		handler()
	else
		commands.help()
	end
end
