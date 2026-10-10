local addonName, wb = ...
local UF = UnitFrames
local W, Skin, Util, Schema = UF.Widgets, UF.Skin, UF.Util, UF.Schema

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
      events = { "UNIT_SPELLCAST_START", ... },                   unit events for live sources
      onEvent = function(handle, data, entryState, event, ...) end,
    },
    styleTarget = function(handle) return target end,  optional, replaces the style inspector target
    autoSize = true,                 the component sizes itself (no width/height sliders)
    reset = function() end,          optional, what the "Reset" button does instead of clearing the config
  })
]]
local Workbench = {}
UF.Workbench = Workbench
wb.Workbench = Workbench

Workbench.entries = {}
Workbench.order = {}

-- Combat restriction CVars: with these on, the live API returns real secret
-- values outside combat (docs/01 §3.2).
local RESTRICTION_CVARS = { "addonCombatRestrictionsForced", "addonEncounterRestrictionsForced" }

local STAGE_BACKGROUNDS = {
	{ "dark", "Dark" },
	{ "grey", "Grey" },
	{ "light", "Light" },
}
local STAGE_COLORS = {
	dark = { 0.02, 0.02, 0.03, 1 },
	grey = { 0.25, 0.25, 0.27, 1 },
	light = { 0.8, 0.8, 0.8, 1 },
}

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

	return handle
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

function Workbench:Build()
	local db = self:GetDB()
	self.window = W.Window:New(UIParent, {
		name = "UnitFramesWorkbench",
		title = "UnitFrames Workbench",
		width = 1240, height = 700, minWidth = 1060, minHeight = 500,
		db = db.window,
		onHide = function()
			self:SetForcedRestrictions(false)
		end,
	})
	local content = self.window:GetContent()

	-- 1: entries.
	self.list = W.ScrollList:New(content, {
		rowHeight = 20,
		onSelect = function(item)
			self:Select(item.id)
		end,
	})
	self.list:SetPoint("TOPLEFT")
	self.list:SetPoint("BOTTOMLEFT")
	self.list:SetWidth(150)

	-- 2: sections of the selected entry.
	self.sectionList = W.ScrollList:New(content, {
		rowHeight = 20,
		onSelect = function(item)
			self:SelectSection(item.id)
		end,
	})
	self.sectionList:SetPoint("TOPLEFT", self.list:GetFrame(), "TOPRIGHT", 8, 0)
	self.sectionList:SetPoint("BOTTOMLEFT", self.list:GetFrame(), "BOTTOMRIGHT", 8, 0)
	self.sectionList:SetWidth(170)

	-- 3: settings of the selected section.
	local settings = CreateFrame("Frame", nil, content)
	settings:SetPoint("TOPLEFT", self.sectionList:GetFrame(), "TOPRIGHT", 8, 0)
	settings:SetPoint("BOTTOMLEFT", self.sectionList:GetFrame(), "BOTTOMRIGHT", 8, 0)
	settings:SetWidth(290)
	self.sectionTitle = Skin.FontString(settings, "title")
	self.sectionTitle:SetPoint("TOPLEFT", 0, -2)
	self.sectionTitle:SetPoint("TOPRIGHT", 0, -2)
	self.sectionTitle:SetJustifyH("LEFT")
	self.inspector = W.Inspector:New(settings)
	self.inspector:SetPoint("TOPLEFT", 0, -24)
	self.inspector:SetPoint("BOTTOMRIGHT")

	-- 4: preview: toolbar, stage, status line.
	local center = CreateFrame("Frame", nil, content)
	center:SetPoint("TOPLEFT", settings, "TOPRIGHT", 12, 0)
	center:SetPoint("BOTTOMRIGHT")
	self:BuildToolbar(center)

	local stage = CreateFrame("Frame", nil, center, "BackdropTemplate")
	stage:SetPoint("TOPLEFT", self.toolbar, "BOTTOMLEFT", 0, -6)
	stage:SetPoint("BOTTOMRIGHT", 0, 22)
	stage:SetClipsChildren(true)
	Skin.ApplyPanel(stage, "panel")
	self.stage = stage

	self.holder = CreateFrame("Frame", nil, stage)
	self.holder:SetSize(1, 1)
	self.holder:SetPoint("CENTER")

	self.bounds = CreateFrame("Frame", nil, self.holder, "BackdropTemplate")
	self.bounds:SetBackdrop({ edgeFile = Skin.WHITE, edgeSize = 1 })
	self.bounds:SetBackdropBorderColor(1, 0.2, 0.2, 0.9)
	self.bounds:SetFrameLevel(self.holder:GetFrameLevel() + 50) -- above the entry's frames

	self.banner = Skin.FontString(stage, "title")
	self.banner:SetPoint("TOP", 0, -8)
	self.banner:SetTextColor(unpack(Skin.colors.warning))
	self.banner:SetText("FORCED COMBAT RESTRICTIONS: live values are secret")

	self.status = Skin.FontString(center)
	self.status:SetPoint("BOTTOMLEFT", 2, 4)
	self.status:SetPoint("BOTTOMRIGHT", -2, 4)
	self.status:SetJustifyH("LEFT")

	self.eventFrame = CreateFrame("Frame")
	self.eventFrame:SetScript("OnEvent", function(_, event, ...)
		self:OnUnitEvent(event, ...)
	end)

	self.window:GetFrame():SetScript("OnUpdate", function(_, elapsed)
		self:OnUpdate(elapsed)
	end)
	self.window:GetFrame():HookScript("OnHide", function()
		self.eventFrame:UnregisterAllEvents()
	end)
	self.window:GetFrame():HookScript("OnShow", function()
		self:RegisterEntryEvents()
	end)

	self:ApplyStageOptions()
	self:FillList()
	local first = db.selected and self.entries[db.selected] and db.selected or (self.order[1] and self.order[1].id)
	if first then
		self.list:Select(first)
		self:Select(first)
	end
end

function Workbench:BuildToolbar(parent)
	local db = self:GetDB()
	local toolbar = CreateFrame("Frame", nil, parent)
	toolbar:SetPoint("TOPLEFT")
	toolbar:SetPoint("TOPRIGHT")
	toolbar:SetHeight(72)
	self.toolbar = toolbar

	-- Stage options on top.
	local row = CreateFrame("Frame", nil, toolbar)
	row:SetPoint("TOPLEFT")
	row:SetPoint("TOPRIGHT")
	row:SetHeight(44)

	-- Presets of the current entry below, wrapping onto more lines.
	self.presetRow = CreateFrame("Frame", nil, toolbar)
	self.presetRow:SetPoint("TOPLEFT", 0, -50)
	self.presetRow:SetPoint("TOPRIGHT", 0, -50)
	self.presetRow:SetHeight(22)
	self.presetRow:SetScript("OnSizeChanged", function()
		self:LayoutPresets()
	end)
	self.presetButtons = {}

	local function Place(widget, width, previous)
		widget:SetWidth(width)
		if previous then
			widget:SetPoint("TOPLEFT", previous:GetFrame(), "TOPRIGHT", 10, 0)
		else
			widget:SetPoint("TOPLEFT", row, "TOPLEFT")
		end
		return widget
	end

	self.widthSlider = Place(W.Slider:New(row, { label = "Width", min = 10, max = 600, step = 1,
		onChange = function(value) self:SetEntrySize(value, nil) end }), 80)
	self.heightSlider = Place(W.Slider:New(row, { label = "Height", min = 4, max = 300, step = 1,
		onChange = function(value) self:SetEntrySize(nil, value) end }), 80, self.widthSlider)
	self.scaleSlider = Place(W.Slider:New(row, { label = "Scale", min = 0.5, max = 3, step = 0.1,
		onChange = function(value)
			db.stage.scale = value
			self:ApplyStageOptions()
		end }), 80, self.heightSlider)
	self.backgroundDropdown = Place(W.Dropdown:New(row, { label = "Background", values = STAGE_BACKGROUNDS,
		onChange = function(value)
			db.stage.background = value
			self:ApplyStageOptions()
		end }), 100, self.scaleSlider)

	self.boundsCheck = W.Checkbox:New(row, { label = "Bounds", onChange = function(value)
		db.stage.bounds = value
		self:ApplyStageOptions()
	end })
	self.boundsCheck:SetWidth(70)
	self.boundsCheck:SetPoint("TOPLEFT", self.backgroundDropdown:GetFrame(), "TOPRIGHT", 10, -2)

	self.secretCheck = W.Checkbox:New(row, {
		label = "Force secrets",
		tooltip = "Turns on the addonCombatRestrictionsForced and addonEncounterRestrictionsForced CVars so the live sources return real secret values outside combat. Turned off again when the Workbench closes.",
		onChange = function(value)
			self:SetForcedRestrictions(value)
		end,
	})
	self.secretCheck:SetWidth(110)
	self.secretCheck:SetPoint("TOPLEFT", self.boundsCheck:GetFrame(), "BOTTOMLEFT", 0, -2)
end

function Workbench:ApplyStageOptions()
	local stageDB = self:GetDB().stage
	self.stage:SetBackdropColor(unpack(STAGE_COLORS[stageDB.background] or STAGE_COLORS.dark))
	self.holder:SetScale(stageDB.scale)
	self.scaleSlider:SetValue(stageDB.scale)
	self.backgroundDropdown:SetValue(stageDB.background)
	self.boundsCheck:SetValue(stageDB.bounds)
	self.bounds:SetShown(stageDB.bounds and self.handle ~= nil)
	self.secretCheck:SetValue(self.forcedRestrictions)
	self.banner:SetShown(self.forcedRestrictions == true)
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
	if self.handle then
		self.handle:Release()
		self.handle = nil
	end
	self.eventFrame:UnregisterAllEvents()
	self:GetDB().selected = id
	self.entry = entry
	self.entryState = { time = 0 } -- scratch space for animations, reset on every select
	local state = self:GetState(entry)
	self.state = state

	local handle = entry.create(self.holder)
	self.handle = handle
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
		self.dataTarget = W.Inspector.TableTarget(entry.data.schema, state.data, function(path)
			if path == "source" then
				self:RegisterEntryEvents()
			end
			self:UpdateData()
		end)
	end
	self:FillSections()

	self:BuildPresets(entry)
	self:ApplyStageOptions()
	self:RegisterEntryEvents()
	self:UpdateData()
end

-- Sections --------------------------------------------------------------------

local DATA_SECTION = "@data"

local function HasOptions(schema)
	for _, opt in ipairs(schema) do
		if opt.type ~= "group" then
			return true
		end
	end
	return false
end

-- The settings tree as list items: one item per group, indented by depth.
-- Groups with only sub-groups are headers (not selectable).
local function SectionItems(items, schema, prefix, depth)
	for _, opt in ipairs(schema) do
		if opt.type == "group" then
			local path = prefix .. opt.key
			if HasOptions(opt.schema) then
				items[#items + 1] = { id = path, text = opt.label or opt.key, depth = depth }
			else
				items[#items + 1] = { text = opt.label or opt.key, depth = depth, header = true }
			end
			SectionItems(items, opt.schema, path .. ".", depth + 1)
		end
	end
	return items
end

function Workbench:FillSections()
	local items = {}
	if self.dataTarget then
		items[#items + 1] = { id = DATA_SECTION, text = "Preview data" }
	end
	if HasOptions(self.styleTarget.schema) then
		items[#items + 1] = { id = "", text = "General" }
	end
	SectionItems(items, self.styleTarget.schema, "", 0)
	self.sections = items

	local wanted = self.state.section
	local first
	for _, item in ipairs(items) do
		if not item.header then
			first = first or item.id
			if item.id == wanted then
				first = wanted
				break
			end
		end
	end
	self.sectionList:SetItems(items)
	self.sectionList:Select(first)
	self.inspector:SetShown(first ~= nil)
	if first then
		self:SelectSection(first)
	else
		self.sectionTitle:SetText("")
	end
end

-- Shows the settings of one section ("" = top level, DATA_SECTION = data).
function Workbench:SelectSection(id)
	self.state.section = id
	local title
	for _, item in ipairs(self.sections) do
		if item.id == id then
			title = item.text
		end
	end
	if id == DATA_SECTION then
		self.inspector:SetTarget(self.dataTarget, self.entry.id .. "|" .. DATA_SECTION, "")
	else
		self.inspector:SetTarget(self.styleTarget, self.entry.id .. "|" .. id, id)
		-- Breadcrumb for nested sections: "Health > Bar > Background".
		local labels, schema = {}, self.styleTarget.schema
		for key in string.gmatch(id, "[^%.]+") do
			local opt = Schema.Find(schema, key)
			labels[#labels + 1] = opt.label or key
			schema = opt.schema
		end
		if #labels > 1 then
			title = table.concat(labels, " > ")
		end
	end
	self.sectionTitle:SetText(title or "")
end

function Workbench:StyleTarget(handle, state)
	return {
		schema = handle.schema,
		get = function(path)
			return Util.GetPath(state.config, path)
		end,
		set = function(path, value)
			if value == nil then
				Util.ClearPath(state.config, path)
			else
				Util.SetPath(state.config, path, value)
			end
			handle:Apply(state.config)
			self:UpdateData()
		end,
		resolved = function()
			return handle:Resolved()
		end,
	}
end

function Workbench:BuildPresets(entry)
	for _, button in ipairs(self.presetButtons) do
		button:Hide()
	end
	local presets = {}
	for _, preset in ipairs(entry.presets or {}) do
		presets[#presets + 1] = preset
	end
	presets[#presets + 1] = { name = "Reset", reset = true }

	for i, preset in ipairs(presets) do
		local button = self.presetButtons[i]
		if not button then
			button = W.Button:New(self.presetRow, {})
			self.presetButtons[i] = button
		end
		button:SetText(preset.name)
		button:SetWidth(math.max(60, button.text:GetStringWidth() + 20))
		button.opts.onClick = function()
			self:ApplyPreset(preset)
		end
		button:Show()
	end
	self.presetCount = #presets
	self:LayoutPresets()
end

-- Flows the preset buttons into lines that fit the preview column.
function Workbench:LayoutPresets()
	local maxWidth = self.presetRow:GetWidth()
	local x, line = 0, 0
	for i = 1, self.presetCount or 0 do
		local button = self.presetButtons[i]
		local width = button:GetFrame():GetWidth()
		if x > 0 and maxWidth > 0 and x + width > maxWidth then
			x, line = 0, line + 1
		end
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", self.presetRow, "TOPLEFT", x, -line * 26)
		x = x + width + 4
	end
	local height = (line + 1) * 26
	self.presetRow:SetHeight(height)
	self.toolbar:SetHeight(50 + height)
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

function Workbench:SetEntrySize(width, height)
	local state = self.state
	if not state then
		return
	end
	state.width = width or state.width
	state.height = height or state.height
	self:ApplySize()
end

function Workbench:ApplySize()
	local state, autoSize = self.state, self.entry.autoSize
	self.widthSlider:SetShown(not autoSize)
	self.heightSlider:SetShown(not autoSize)
	if autoSize then
		return
	end
	self.handle.frame:SetSize(state.width, state.height)
	self.widthSlider:SetValue(state.width)
	self.heightSlider:SetValue(state.height)
end

-- Data --------------------------------------------------------------------------

function Workbench:GetData()
	return Schema.Resolve(self.entry.data.schema, self.state.data, nil)
end

function Workbench:UpdateData()
	local data = self.entry and self.entry.data
	if data and data.update then
		data.update(self.handle, self:GetData(), self.entryState)
	end
end

-- Runs a named action of the current entry (buttons in the Data tab).
function Workbench:RunAction(name)
	local data = self.entry and self.entry.data
	local action = data and data.actions and data.actions[name]
	if action then
		action(self.handle, self:GetData(), self.entryState)
	end
end

function Workbench:RegisterEntryEvents()
	self.eventFrame:UnregisterAllEvents()
	local data = self.entry and self.entry.data
	if not data or not data.events then
		return
	end
	local resolved = self:GetData()
	if not wb.Data.IsLive(resolved) then
		return
	end
	for _, event in ipairs(data.events) do
		self.eventFrame:RegisterUnitEvent(event, resolved.source)
	end
end

function Workbench:OnUnitEvent(event, ...)
	local data = self.entry and self.entry.data
	if data and data.onEvent then
		data.onEvent(self.handle, self:GetData(), self.entryState, event, ...)
	end
end

local STATUS_INTERVAL = 0.5

function Workbench:OnUpdate(elapsed)
	local data = self.entry and self.entry.data
	if data and data.tick then
		self.entryState.time = self.entryState.time + elapsed
		data.tick(self.handle, self:GetData(), self.entryState, elapsed)
	end
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
