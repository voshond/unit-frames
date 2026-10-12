local _, wb = ...
local UF = UnitFrames
local W, Util = UF.Widgets, UF.Util

--[[
Workbench: shows one component (or a small composition) at a time on a stage,
with its settings and fake or live data to drive it.

Four columns:
  entries | sections (the settings tree of the entry) | settings of the section | preview

Entries register themselves:
  Workbench:Register({
    id, category, name,
    size = { width, height },        default stage size
    create = function(stage) return handle end,  usually Workbench.Composite(...)
    defaultConfig = { ... },         style config used before the user changes anything
    presets = { { name, config, size? }, ... },
    data = {
      schema = { ... },              options for the Data tab
      update = function(handle, data, entryState) end,           on any change
      tick = function(handle, data, entryState, elapsed) end,    every frame (animated/live)
      tickStatic = true,            opt-in for actions that must finish in static mode
      events = { "UNIT_SPELLCAST_START", ... },                   unit events for live sources
      onEvent = function(handle, data, entryState, event, ...) end,
    },
    styleTarget = function(handle) return target end,  optional, replaces the style inspector target
    settingsPages = { { id = "@icons", label = "Icons", paths = { "raidTarget", "pvp" }, revision? } },
                                     optional navigation pages referring to existing schema paths
    autoSize = true,                 the component sizes itself (no width/height sliders)
    fitToStage = true,               opt-in for ordinary, plain-sized preview frames
    refreshOn = { "Event", { "Event", match } },  restyle the preview on these core events
                                     (a table entry only matches when the first payload equals `match`)
                                     notifyOnly = true on a watch updates the inspector/stage only,
                                     when a runtime owner already refreshed the preview
    reset = function() end,          optional, what the "Reset" button does instead of clearing the config
  })

create returns a handle:
  frame                          the stage frame to centre and size
  schema                         style schema (unless styleTarget replaces it)
  Apply(config), Resolved(), Release()
  parts                          optional, components by key for data hooks
  SetThemeManaged(managed)       optional; the session then restyles on ThemeChanged
  SetSizeChangedCallback(fn)     optional, with fitToStage: ordinary sizes only
Workbench.Composite and Workbench.ComponentHandle build the common ones.
]]
local Workbench = {}
UF.Workbench = Workbench
wb.Workbench = Workbench

Workbench.entries = {}
Workbench.order = {}

-- Combat restriction CVars: with these on, the live API returns real secret
-- values outside combat (docs/01 §3.2).
local RESTRICTION_CVARS = { "addonCombatRestrictionsForced", "addonEncounterRestrictionsForced" }

function Workbench:Register(entry)
	assert(entry.id and not self.entries[entry.id], "Workbench: missing or duplicate entry id")
	self.entries[entry.id] = entry
	self.order[#self.order + 1] = entry
end

--[[
Wraps components as one inspectable handle. Each part becomes a group in the
style inspector and gets its own sub-table of the entry's config.
  parts: array of { key, label, component }
]]
function Workbench.Composite(parts, frame)
	local handle = { parts = {}, frame = frame or parts[1].component:GetFrame() }
	local schema = {}
	for _, part in ipairs(parts) do
		handle.parts[part.key] = part.component
		schema[#schema + 1] = { key = part.key, type = "group", label = part.label, schema = part.component:GetSchema() }
	end
	handle.schema = schema

	function handle:Apply(config)
		for _, part in ipairs(parts) do
			part.component:Apply(config[part.key] or {})
		end
	end

	function handle:Resolved()
		local out = {}
		for _, part in ipairs(parts) do
			out[part.key] = part.component.resolved
		end
		return out
	end

	function handle:Release()
		for _, part in ipairs(parts) do
			part.component:Release()
		end
	end

	function handle:SetThemeManaged(managed)
		for _, part in ipairs(parts) do part.component:SetThemeManaged(managed) end
	end

	return handle
end

-- One component configured from elsewhere (e.g. a saved unit style), so the
-- entry's own config is ignored.
function Workbench.ComponentHandle(key, component, getConfig)
	return {
		frame = component:GetFrame(),
		parts = { [key] = component },
		schema = component:GetSchema(),
		Apply = function() component:Apply(getConfig()) end,
		Resolved = function() return component.resolved end,
		Release = function() component:Release() end,
		SetThemeManaged = function(_, managed) component:SetThemeManaged(managed) end,
	}
end

-- Saved state ---------------------------------------------------------------

-- Bump when saved entry configs no longer fit the entries; old ones are dropped.
local DB_VERSION = 2

function Workbench:GetDB()
	UnitFramesWorkbenchDB = UnitFramesWorkbenchDB or {}
	local db = UnitFramesWorkbenchDB
	if db.version ~= DB_VERSION then
		db.entries = nil
		db.version = DB_VERSION
	end
	db.window = db.window or {}
	db.entries = db.entries or {}
	db.stage = db.stage or { background = "dark", scale = 1, bounds = false }
	return db
end

function Workbench:GetState(entry)
	local db = self:GetDB()
	local state = db.entries[entry.id]
	if not state then
		state = {
			config = Util.Copy(entry.defaultConfig or {}),
			data = {},
			width = entry.size and entry.size[1] or 200,
			height = entry.size and entry.size[2] or 24,
		}
		db.entries[entry.id] = state
	end
	return state
end

-- Window ----------------------------------------------------------------------

function Workbench:Toggle()
	if not self.window then
		self:Build() -- new windows start shown
		return
	end
	self.window:Toggle()
end

-- Shows the Workbench at a given entry.
function Workbench:Open(id)
	if not self.window then
		self:Build()
	end
	self.window:Show()
	if self.entries[id] then
		self.list:Select(id)
		self:Select(id)
	end
end

function Workbench:FillList()
	local categories, byCategory = {}, {}
	for _, entry in ipairs(self.order) do
		if not byCategory[entry.category] then
			byCategory[entry.category] = {}
			categories[#categories + 1] = entry.category
		end
		table.insert(byCategory[entry.category], entry)
	end
	local items = {}
	for _, category in ipairs(categories) do
		items[#items + 1] = { text = category, header = true }
		for _, entry in ipairs(byCategory[category]) do
			items[#items + 1] = { id = entry.id, text = entry.name }
		end
	end
	self.list:SetItems(items)
end

-- Entries ---------------------------------------------------------------------

function Workbench:Select(id)
	local entry = self.entries[id]
	if not entry then
		return
	end
	self.inspector:ClearTarget()
	if self.session then self.session:Release() end
	self.session, self.handle = nil, nil
	self.eventFrame:UnregisterAllEvents()
	self:GetDB().selected = id
	self.entry = entry
	self.entryState = { time = 0 } -- scratch space for animations, reset on every select
	local state = self:GetState(entry)
	self.state = state

	local session = wb.PreviewSession:New(entry, state, self.entryState, self.holder)
	local handle = session.handle
	self.session = session
	self.handle = handle
	session.onRefresh = function()
		if self.session == session then self.inspector:Refresh(); self:FitStage() end
	end
	session:WatchSize(function() if self.session == session then self:FitStage() end end)
	handle.frame:ClearAllPoints()
	handle.frame:SetPoint("CENTER", self.holder, "CENTER")
	handle:Apply(state.config)
	self:ApplySize()
	self.bounds:ClearAllPoints()
	self.bounds:SetPoint("TOPLEFT", handle.frame, "TOPLEFT", -1, 1)
	self.bounds:SetPoint("BOTTOMRIGHT", handle.frame, "BOTTOMRIGHT", 1, -1)

	self.styleTarget = entry.styleTarget and entry.styleTarget(handle) or self:StyleTarget(handle, state)
	self.dataTarget = nil
	if entry.data then
		self.dataTarget = W.Inspector.TableTarget(entry.data.schema, function() return state.data end, function(path)
			session:InvalidateData()
			if path == "source" then
				self:RegisterEntryEvents()
			end
			self:UpdateData()
		end)
		self.dataTarget.invoke = function(path) self:RunAction(path) end
	end
	self:FillSections()

	self:BuildPresets(entry)
	self:ApplyStageOptions()
	self:RegisterEntryEvents()
	self:UpdateData()
end

function Workbench:ApplyPreset(preset)
	local entry, state = self.entry, self.state
	if preset.reset and entry.reset then
		entry.reset()
	elseif preset.reset then
		state.config = Util.Copy(entry.defaultConfig or {})
		state.width, state.height = entry.size[1], entry.size[2]
	else
		state.config = Util.Copy(preset.config or {})
		if preset.size then
			state.width, state.height = preset.size[1], preset.size[2]
		end
	end
	-- The style target reads state.config through closures, so rebuild it.
	self:Select(entry.id)
end

-- Data --------------------------------------------------------------------------

function Workbench:GetData()
	return self.session and self.session:GetData()
end

function Workbench:UpdateData()
	if self.session then self.session:Update() end
end

-- Re-reads the current inspector page, e.g. after an entry changes what its
-- target edits without changing the schema.
function Workbench:RefreshInspector()
	if self.inspector then self.inspector:Refresh() end
end

-- Runs a named action of the current entry (buttons in the Data tab).
function Workbench:RunAction(name)
	if self.session then self.session:Invoke(name) end
end

function Workbench:RegisterEntryEvents()
	self.eventFrame:UnregisterAllEvents()
	if self.session then
		self.session:ActivateEvents(self.eventFrame, self.window:IsShown())
	end
end

function Workbench:OnUnitEvent(event, ...)
	if self.session then self.session:OnEvent(event, ...) end
end

local STATUS_INTERVAL = 0.5

function Workbench:OnUpdate(elapsed)
	if self.pendingStageFit and not InCombatLockdown() then self:FitStage() end
	-- Select clears the previous handle before constructing the next preview.
	-- If creation raises, keep its original error visible without sending
	-- every subsequent frame/event to an entry that has no active preview.
	if self.session then self.session:Tick(elapsed) end
	self.statusElapsed = (self.statusElapsed or STATUS_INTERVAL) + elapsed
	if self.statusElapsed >= STATUS_INTERVAL then
		self.statusElapsed = 0
		self:UpdateStatus()
	end
end

function Workbench:UpdateStatus()
	local health = UnitHealth("player")
	local secret = UF.Util.IsSecret(health)
	self.status:SetFormattedText("UnitHealth(\"player\") is %s   |   combat restrictions forced: %s   |   in combat: %s",
		secret and "|cffff5555SECRET|r" or "|cff55ff55readable|r",
		self.forcedRestrictions and "yes" or "no",
		InCombatLockdown() and "yes" or "no")
end

function Workbench:SetForcedRestrictions(enabled)
	if not enabled and not self.forcedRestrictions then
		return
	end
	local value = enabled and "1" or "0"
	for _, cvar in ipairs(RESTRICTION_CVARS) do
		-- External boundary: the client may refuse; report instead of failing.
		local ok, err = pcall(C_CVar.SetCVar, cvar, value)
		if not ok then
			UF:Print("could not set", cvar, err)
		end
	end
	self.forcedRestrictions = enabled
	if self.stage then
		self:ApplyStageOptions()
		self:UpdateData()
	end
end
