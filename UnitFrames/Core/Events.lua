local _, ns = ...

-- Internal message bus.
--   ns.Events.RegisterCallback(owner, "ThemeChanged", handler)
--   ns.Events:Fire("ThemeChanged", path)
-- Messages: Initialized, ThemeChanged(path), ProfileChanged
local Events = {}
Events.callbacks = LibStub("CallbackHandler-1.0"):New(Events)

function Events:Fire(message, ...)
	self.callbacks:Fire(message, ...)
end

ns.Events = Events
