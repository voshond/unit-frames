local _, ns = ...
local Timers = {}
ns.Timers = Timers

function Timers:GetSchema()
	if not self.schema then
		self.schema = ns.Components.CastbarFrame.BuildSchema({ standalone = true })
	end
	return self.schema
end

function ns.Config:GetTimerConfig()
	if self.db then
		self.db.profile.timers = self.db.profile.timers or {}
		return self.db.profile.timers
	end
	self.timerConfig = self.timerConfig or {}
	return self.timerConfig
end

function ns.Config:TimerStore()
	if not self.timerStore then
		self.timerStore = ns.Store:New({
			schema = function() return Timers:GetSchema() end,
			read = function() return self:GetTimerConfig() end,
			theme = true,
			validate = true,
			changed = function(path) ns.Events:Fire("TimerConfigChanged", path) end,
		})
	end
	return self.timerStore
end

ns.Profiles:RegisterStyleSection("timers", {
	export = function() return ns.Util.Copy(ns.Config:GetTimerConfig()) end,
	prepare = function(data)
		if type(data) ~= "table" then return nil, "Invalid timer settings." end
		local dropped = {}
		local config = ns.Schema.Sanitize(Timers:GetSchema(), data, "", dropped)
		return function() ns.Config:TimerStore():Replace(config) end, dropped
	end,
})
