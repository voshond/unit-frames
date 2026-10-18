local _, wb = ...
local UF = UnitFrames
local Workbench, Data = wb.Workbench, wb.Data

local function PreviewConfig()
	local config = UF.Util.Copy(UF.Config:GetTimerConfig())
	config.enabled = true
	return config
end

Workbench:Register({
	id = "timers",
	category = "Cast bar & swing timers",
	name = "Cast bar & swing timers",
	scope = "Standalone player timers",
	settingsTargets = function() return { { id = "style", schema = UF.Config:TimerStore():GetSchema() } } end,
	destinations = { { label = "Move standalone cast bar", aliases = "position edit mode independent player castbar",
		pageId = "@layout", hint = "Position these timers independently in Edit Mode. Player > Cast bar is a separate display." } },
	autoSize = true,
	fitToStage = true,
	size = { 280, 24 },
	refreshOn = { "TimerConfigChanged" },
	create = function(stage)
		local component = UF.Components.CastbarFrame:New(stage, PreviewConfig(), { standalone = true })
		local handle = Workbench.ComponentHandle("timers", component, PreviewConfig)
		handle.feed = UF.TimerFeed:New(component)
		local release = handle.Release
		handle.Release = function()
			handle.feed:Release()
			release()
		end
		return handle
	end,
	styleTarget = function() return UF.Config:TimerStore():Target() end,
	reset = function() UF.Config:TimerStore():Reset() end,
	data = {
		schema = {
			{ key = "source", type = "select", label = "Source", values = Data.Sources(false), default = "static" },
			{ key = "inCombat", type = "toggle", label = "In combat", default = false, hidden = Data.IsLive },
			{ key = "spell", type = "select", label = "Spell", values = Data.SpellValues, default = 1, hidden = Data.IsLive },
			{ key = "progress", type = "range", label = "Cast progress %", min = 0, max = 100, step = 1, default = 60,
				hidden = function(d) return d.source ~= "static" end },
		},
		update = function(handle, d, es)
			if Data.IsLive(d) then handle.feed:Refresh(); return end
			UF.TimerSamples.Show(handle.feed, d.source == "animated" and es.time or nil,
				d.progress / 100, Data.SPELLS[d.spell], d.inCombat)
		end,
		tick = function(handle, d, es)
			if Data.IsLive(d) then handle.feed:Tick(); return end
			UF.TimerSamples.Show(handle.feed, es.time, nil, Data.SPELLS[d.spell], d.inCombat)
		end,
		events = UF.Cast.EVENTS,
		registerEvents = function(handle, frame)
			handle.feed:RegisterEvents(frame)
			handle.feed:Refresh()
		end,
		deactivate = function(handle) handle.feed:Clear() end,
		onEvent = function(handle, _, _, event, ...) handle.feed:Handle(event, ...) end,
	},
})
