local _, ns = ...

-- Only our own diagnostic/error paths write here. Never hook the global
-- error handler or retain unit/aura data. Bounds apply across reloads too.
local Logs = {}
ns.Logs = Logs
local LIMITS = { errors = 10, general = 20 }

local function Plain(value)
	if issecretvalue(value) then return "<secret omitted>" end
	return tostring(value):sub(1, 1024)
end

function Logs:Initialize()
	if type(UnitFramesLogs) ~= "table" then UnitFramesLogs = {} end
	for key, limit in pairs(LIMITS) do
		if type(UnitFramesLogs[key]) ~= "table" then UnitFramesLogs[key] = {} end
		while #UnitFramesLogs[key] > limit do table.remove(UnitFramesLogs[key], 1) end
	end
	return UnitFramesLogs
end

function Logs:Write(key, context, message)
	local entries = self:Initialize()[key]
	assert(entries and LIMITS[key], "Unknown log kind")
	if #entries == LIMITS[key] then table.remove(entries, 1) end
	entries[#entries + 1] = { timestamp = GetServerTime(), version = ns.version,
		context = Plain(context), message = Plain(message) }
end

function Logs:Error(context, message)
	self:Write("errors", context, message)
end

function Logs:Info(context, message)
	self:Write("general", context, message)
end

function Logs:Command(command)
	local logs = self:Initialize()
	if command == "clear" then
		wipe(logs.errors)
		wipe(logs.general)
		ns:Print("diagnostic log cleared")
	elseif command == "" then
		for _, key in ipairs({ "errors", "general" }) do
			ns:Print(key, #logs[key], "saved entries (Unix timestamps)")
			for _, entry in ipairs(logs[key]) do
				ns:Print(entry.timestamp, entry.version, entry.context, entry.message)
			end
		end
	else
		ns:Print("/uf logs [clear]")
	end
end

ns.Events.RegisterCallback(Logs, "Initialized", function() Logs:Initialize() end)
