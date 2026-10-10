local _, ns = ...

local HELP = {
	"/uf wb - open the Workbench (component gallery, test mode, frame settings)",
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

function commands.wb()
	ns:OpenWorkbench()
end
commands.workbench = commands.wb

SLASH_UNITFRAMES1 = "/uf"
SLASH_UNITFRAMES2 = "/unitframes"
SlashCmdList.UNITFRAMES = function(msg)
	local command = strtrim(msg or ""):lower()
	local handler = commands[command]
	if handler then
		handler()
	else
		ns:Print("version", ns.version)
		for _, line in ipairs(HELP) do
			print("  " .. line)
		end
	end
end
