local _, CG = ...
local UF = CG.UF
local EMPTY_INDICATORS = {}
local Config = {}
CG.Config = Config
Config.schema = {
	{ key = "panel", type = "group", label = "Panel layout", schema = CG.LayoutSchema },
	{ key = "border", type = "group", label = "Panel border",
		schema = UF.Components.Backdrop.schema },
	{ key = "titles", type = "group", label = "Group / column titles", schema = CG.TitleSchema },
	{ key = "indicators", type = "group", label = "Status indicators", schema = CG.IndicatorSchema },
	{ key = "slots", type = "group", label = "Fixed friendly buff slots", schema = CG.SlotSchema },
}

-- Old profiles kept uniform padding in Panel layout. Read/import an
-- independent migrated copy; the next store write persists the new shape.
function Config:MigrateSettings(settings)
	if type(settings) ~= "table" or type(settings.panel) ~= "table" or settings.panel.padding == nil then return settings or {} end
	local migrated = UF.Util.Copy(settings)
	migrated.border = migrated.border or {}
	if type(migrated.border) == "table" and migrated.border.padding == nil then migrated.border.padding = migrated.panel.padding end
	migrated.panel.padding = nil
	return migrated
end

-- "Show member targets" moved from the panel settings to the target bar
-- style (Target bars > General). Carry an old choice over once, in the
-- saved profile, before either store reads it.
local function MigrateTargets(profile)
	local panel = profile.settings.panel
	if type(panel) ~= "table" or panel.targets == nil then return end
	if panel.targets == true and profile.target.shown == nil then profile.target.shown = true end
	panel.targets = nil
end

-- Fixed slots also need parseable spell IDs, beyond the schema's types.
local function CheckSlots(candidate)
	for _, slot in pairs(UF.Schema.Resolve(CG.SlotSchema, candidate.slots)) do
		local ids, reason = CG.Slots.ParseIDs(slot.spell)
		if not ids then return false, reason end
	end
	return true
end

local function Changed(kind, path)
	CG:RequestRefresh(kind, path)
	local eventPath = path
	if kind ~= "settings" then eventPath = kind end
	UF.Events:Fire("ClickGridConfigChanged", eventPath, kind, path)
end

-- Every write path is a validated store: settings, the member/target bar
-- styles and the current specialization's click bindings.
function Config:Initialize()
	self.db = UF.Config.db:RegisterNamespace("ClickGrid", {
		profile = { version = 1, settings = {}, member = {}, target = {} },
		char = { loadouts = {} },
	})
	local db = self.db
	self.settings = UF.Store:New({
		schema = self.schema, theme = true, validate = true, check = CheckSlots,
		changed = function(path) Changed("settings", path) end,
		read = function()
			MigrateTargets(db.profile)
			return self:MigrateSettings(db.profile.settings)
		end,
		write = function(settings) db.profile.settings = settings end,
	})
	self.styles = {}
	for _, kind in ipairs({ "member", "target" }) do
		self.styles[kind] = UF.Store:New({
			schema = function() return CG:StyleSchema(kind) end, theme = true, validate = true,
			read = function()
				MigrateTargets(db.profile)
				return UF.Units:MigrateConfig(db.profile[kind])
			end,
			write = function(style) db.profile[kind] = style end,
			changed = function(path) Changed(kind, path) end,
		})
	end
	self.bindings = UF.Store:New({
		schema = function() return CG.Bindings.schema end, validate = true,
		read = function() return self:GetBindings() end,
		write = function(bindings) db.char.loadouts[self:SpecKey()] = bindings end,
		-- The config event that follows refreshes the binding grid.
		changed = function(path)
			CG:RequestBindings(false)
			UF.Events:Fire("ClickGridConfigChanged", "bindings", "bindings", path)
		end,
	})
end

function Config:Get()
	return self.settings:Read()
end

function Config:Resolved()
	return self.settings:Resolved()
end

function Config:GetIndicators()
	return self:Get().indicators or EMPTY_INDICATORS
end

function Config:Set(path, value)
	return self.settings:Set(path, value)
end

function Config:GetStyle(kind)
	return self.styles[kind]:Read()
end

function Config:SetStyle(kind, path, value)
	return self.styles[kind]:Set(path, value)
end

function Config:SpecKey()
	if CG.Caps.specialization then
		local index = C_SpecializationInfo.GetSpecialization()
		if not issecretvalue(index) and index then return tostring(index) end
	end
	return "default"
end

function Config:GetBindings()
	local key = self:SpecKey()
	local loadouts = self.db.char.loadouts
	loadouts[key] = loadouts[key] or {}
	return loadouts[key]
end

function Config:SetBinding(button, modifier, reaction, field, value)
	return self.bindings:Set("button" .. button .. "." .. modifier .. "." .. reaction .. "." .. field, value)
end

-- One commit for a whole action group: never an intermediate action/argument
-- pair. nil resets the group to its default.
function Config:SetAction(button, modifier, reaction, action)
	return self.bindings:Set("button" .. button .. "." .. modifier .. "." .. reaction, action and UF.Util.Copy(action))
end
