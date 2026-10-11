local _, wb = ...
local UF = UnitFrames
local Session = {}
Session.__index = Session
wb.PreviewSession = Session

-- One active preview and source. Inspector pages never capture this session;
-- their current targets are replaced when the controller selects another entry.
function Session.New(entry, state, scratch, parent)
	local handle = entry.create(parent)
	local session = setmetatable({ entry = entry, state = state, scratch = scratch, handle = handle }, Session)
	if handle.SetThemeManaged then
		handle:SetThemeManaged(true)
		UF.Events.RegisterCallback(session, "ThemeChanged", function() session:RefreshStyle() end)
	end
	-- refreshOn: event names, or { event, match } where the first payload
	-- argument must equal `match` (e.g. a unit's UnitConfigChanged).
	for _, watch in ipairs(entry.refreshOn or {}) do
		local event, match = watch, nil
		if type(watch) == "table" then event, match = watch[1], watch[2] end
		UF.Events.RegisterCallback(session, event, function(_, key)
			if match == nil or key == match then session:RefreshStyle() end
		end)
	end
	return session
end

function Session:RefreshStyle()
	if self.released then return end
	self.handle:Apply(self.state.config)
	self:Update()
	if self.onRefresh then self.onRefresh() end
end

-- Resolved data is cached until the data target reports an edit.
function Session:GetData()
	local data = self.entry.data
	if not data then return nil end
	if not self.values then
		self.values = UF.Schema.Resolve(data.schema, self.state.data, nil)
	end
	return self.values
end

function Session:InvalidateData()
	self.values = nil
end

function Session:Update()
	if self.released then return end
	local data = self.entry.data
	if data and data.update then data.update(self.handle, self:GetData(), self.scratch) end
end

function Session:Invoke(name)
	if self.released then return end
	local data = self.entry.data
	local action = data and data.actions and data.actions[name]
	if action then action(self.handle, self:GetData(), self.scratch) end
end

function Session:ActivateEvents(eventFrame, shown)
	eventFrame:UnregisterAllEvents()
	self.eventFrame = eventFrame
	local data = self.entry.data
	if self.released or not shown or not data or not data.events then return end
	local values = self:GetData()
	if not wb.Data.IsLive(values) then return end
	for _, event in ipairs(data.events) do eventFrame:RegisterUnitEvent(event, values.source) end
end

function Session:OnEvent(event, ...)
	local data = self.entry.data
	if not self.released and data and data.onEvent then
		data.onEvent(self.handle, self:GetData(), self.scratch, event, ...)
	end
end

function Session:Tick(elapsed)
	local data = self.entry.data
	if self.released or not data or not data.tick then return end
	local values = self:GetData()
	-- Castbar test actions need to finish/fade even with a static source.
	if values.source == "static" and not data.tickStatic then return end
	self.scratch.time = self.scratch.time + elapsed
	data.tick(self.handle, values, self.scratch, elapsed)
end

function Session:WatchSize(callback)
	if self.entry.fitToStage and self.handle.SetSizeChangedCallback then
		self.handle:SetSizeChangedCallback(callback)
	end
end

function Session:Release()
	if self.released then return end
	self.released = true
	UF.Events.UnregisterAllCallbacks(self)
	self.onRefresh = nil
	if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
	self:WatchSize(nil)
	self.handle:Release()
end
