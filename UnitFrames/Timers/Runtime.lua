local _, ns = ...
local Timers = ns.Timers

function Timers:UpdateTick()
	self.events:SetScript("OnUpdate", self.feed:HasActiveSwings() and function()
		self.feed:Tick()
		if not self.feed:HasActiveSwings() then self.events:SetScript("OnUpdate", nil) end
	end or nil)
end

function Timers:Refresh()
	if not self.started then return end
	local config = ns.Config:GetTimerConfig()
	local enabled = ns.Config:TimerStore():Resolved().enabled
	if not self.component and not enabled then return end
	if not self.component then
		self.component = ns.Components.CastbarFrame:New(UIParent, config, { standalone = true })
		self.component:SetThemeManaged(true)
		self.feed = ns.TimerFeed:New(self.component)
		self.events = CreateFrame("Frame", nil, self.component:GetFrame())
		self.events:SetScript("OnEvent", function(_, event, ...)
			self.feed:Handle(event, ...)
			self:UpdateTick()
		end)
		ns.EditMode:Register(self.component:GetFrame(), "timers", "UnitFrames: Standalone castbar",
			{ point = "CENTER", x = 0, y = -220 }, "timers")
	end
	self.component:Apply(config)
	self.events:UnregisterAllEvents()
	self.events:SetScript("OnUpdate", nil)
	ns.PlayerCastbar:SetOwner(self, enabled and self.component:GetCastbar():IsEnabled())
	if self.editing and enabled then
		ns.TimerSamples.Show(self.feed)
		return
	end
	self.feed:RegisterEvents(self.events)
	self.feed:Refresh()
	self:UpdateTick()
	if not enabled then self.feed:Clear() end
end

local LEM = LibStub("LibEditMode", true)
if LEM then
	local function SetEditing(editing)
		Timers.editing = editing
		if Timers.feed then Timers.feed:Clear() end
		Timers:Refresh()
	end
	LEM:RegisterCallback("enter", function() SetEditing(true) end)
	LEM:RegisterCallback("exit", function() SetEditing(false) end)
end

ns.oUF:Factory(function()
	Timers.started = true
	Timers:Refresh()
end)

ns.Events.RegisterCallback(Timers, "TimerConfigChanged", function() Timers:Refresh() end)
ns.Events.RegisterCallback(Timers, "ThemeChanged", function() Timers:Refresh() end)
ns.Events.RegisterCallback(Timers, "ProfileChanged", function()
	if Timers.feed then Timers.feed:Clear() end
end)
