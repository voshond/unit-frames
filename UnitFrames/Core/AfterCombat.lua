local _, ns = ...

--[[
Work that must wait for combat to end, keyed by (kind, owner) so repeated
requests coalesce. Kinds run in a fixed order when combat ends, each in the
order it was first requested:
  apply     re-apply a component's configuration
  layout    resize protected unit buttons
  restyle   restyle native aura buttons (may need the new layout)
  position  move protected frames to their saved positions

  ns.AfterCombat:Queue("layout", owner, function(owner) ... end)
  ns.AfterCombat:Cancel(owner[, kind])

Work queued while running waits for the next combat end.
]]
local AfterCombat = {}
ns.AfterCombat = AfterCombat

AfterCombat.ORDER = { "apply", "layout", "restyle", "position" }

local function NewQueue()
	return { order = {}, work = {} }
end

local queues = {}
for _, kind in ipairs(AfterCombat.ORDER) do queues[kind] = NewQueue() end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	for _, kind in ipairs(AfterCombat.ORDER) do
		local queue = queues[kind]
		queues[kind] = NewQueue()
		for _, owner in ipairs(queue.order) do
			local work = queue.work[owner]
			if work then work(owner) end
		end
	end
end)

function AfterCombat:Queue(kind, owner, work)
	local queue = assert(queues[kind], "Unknown after-combat kind")
	if not queue.work[owner] then queue.order[#queue.order + 1] = owner end
	queue.work[owner] = work
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- kind nil cancels all of the owner's work.
function AfterCombat:Cancel(owner, kind)
	for _, name in ipairs(AfterCombat.ORDER) do
		if kind == nil or kind == name then queues[name].work[owner] = nil end
	end
end

function AfterCombat:IsQueued(owner, kind)
	return queues[kind].work[owner] ~= nil
end
