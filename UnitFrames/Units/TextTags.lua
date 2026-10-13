local _, ns = ...
local oUF = ns.oUF

--[[
oUF tags for text slots that no shared [uf:<preset>] tag shows (custom
slots, presets partly unavailable on their host).

Each bound FontString holds a reusable handle tag [uf:t<n>]. Its method is a
fixed dispatcher to the slot's current template, so oUF's cached tag
functions never go stale and no RefreshMethods is needed. Its events are set
before every (re)tag, which is when oUF reads them. A content change retags
the FontString; an unchanged template is left alone. Unbinding untags it,
clears its text and returns the handle: idle handles show nothing, have no
events and hold no template, frame or unit. oUF's retained tag names and
functions therefore grow with the most slots bound at once, not with edits.
]]
local TextTags = {}
ns.TextTags = TextTags

local templates = {}   -- handle -> template
local free = {}        -- idle handles
local count = 0
local bindings = setmetatable({}, { __mode = "k" }) -- FontString -> { handle, template }

local function Name(handle)
	return "uf:t" .. handle
end

local function Acquire()
	local handle = table.remove(free)
	if handle then return handle end
	count = count + 1
	handle = count
	oUF.Tags.Methods[Name(handle)] = function(unit)
		local template = templates[handle]
		if template then return template.live(unit) end
		return ""
	end
	return handle
end

-- Binds `fs` on oUF `frame` to `template`. Returns true when it (re)tagged.
function TextTags.Bind(frame, fs, template)
	local binding = bindings[fs]
	if binding and binding.template == template then return false end
	if not binding then
		binding = { handle = Acquire() }
		bindings[fs] = binding
	end
	binding.template = template
	local name = Name(binding.handle)
	templates[binding.handle] = template
	oUF.Tags.Events[name] = template.events
	for event in pairs(template.sharedEvents or {}) do oUF.Tags.SharedEvents[event] = true end
	frame:Tag(fs, "[" .. name .. "]")
	return true
end

-- Releases `fs`'s handle, if it has one. The caller untags it.
function TextTags.Unbind(fs)
	local binding = bindings[fs]
	if not binding then return end
	bindings[fs] = nil
	templates[binding.handle] = nil
	oUF.Tags.Events[Name(binding.handle)] = nil
	free[#free + 1] = binding.handle
end

-- Test and diagnostics view: handles created and idle.
function TextTags.Stats()
	return count, #free
end

function TextTags.GetHandle(fs)
	local binding = bindings[fs]
	return binding and Name(binding.handle)
end
