local _, ns = ...
local Schema, Util = ns.Schema, ns.Util

-- Profile storage (AceDB). The profile only stores values that differ from
-- the schema defaults; AceDB strips everything else on logout.
local Config = {}
ns.Config = Config

local function BuildDefaults()
	return {
		profile = {
			theme = Schema.Defaults(ns.Theme.schema),
			-- Per unit frame: only the user's changes; defaults come from the schema.
			units = { ["*"] = {} },
			-- Frame positions per Edit Mode layout name: positions[layout][frameKey] = { point, x, y }
			positions = { ["*"] = {} },
		},
	}
end

function Config:Initialize()
	self.db = LibStub("AceDB-3.0"):New("UnitFramesDB", BuildDefaults(), true)
	local function OnProfile()
		ns.Events:Fire("ProfileChanged")
		ns.Events:Fire("ThemeChanged")
	end
	self.db.RegisterCallback(self, "OnProfileChanged", OnProfile)
	self.db.RegisterCallback(self, "OnProfileCopied", OnProfile)
	self.db.RegisterCallback(self, "OnProfileReset", OnProfile)
end

-- Before ADDON_LOADED (and in offline tests) the static defaults are used.
function Config:GetTheme()
	if self.db then
		return self.db.profile.theme
	end
	self.defaultTheme = self.defaultTheme or Schema.Defaults(ns.Theme.schema)
	return self.defaultTheme
end

function Config:GetThemeDefaults()
	self.themeDefaults = self.themeDefaults or Schema.Defaults(ns.Theme.schema)
	return self.themeDefaults
end

-- The value at `path` if it differs from the default, else nil. AceDB copies
-- defaults into the profile, so "is it set" has to be answered by comparing.
function Config:GetThemeOverride(path)
	local value = Util.GetPath(self:GetTheme(), path)
	if Util.Equals(value, Util.GetPath(self:GetThemeDefaults(), path)) then
		return nil
	end
	return value
end

-- value nil resets the option to its default.
function Config:SetThemeValue(path, value)
	if value == nil then
		value = Util.Copy(Util.GetPath(self:GetThemeDefaults(), path))
	end
	Util.SetPath(self:GetTheme(), path, value)
	ns.Events:Fire("ThemeChanged", path)
end

-- Unit frames -------------------------------------------------------------------

function Config:GetUnitConfig(unit)
	if self.db then
		return self.db.profile.units[unit]
	end
	self.unitConfigs = self.unitConfigs or {}
	self.unitConfigs[unit] = self.unitConfigs[unit] or {}
	return self.unitConfigs[unit]
end

-- The write path for one unit's style. The saved table keeps its identity;
-- every change fires UnitConfigChanged(unit, path), path nil for all of it.
function Config:UnitStore(unit)
	self.unitStores = self.unitStores or {}
	local store = self.unitStores[unit]
	if not store then
		store = ns.Store.New({
			schema = function() return ns.Units:GetSchema(unit) end,
			read = function() return self:GetUnitConfig(unit) end,
			theme = true,
			changed = function(path) ns.Events:Fire("UnitConfigChanged", unit, path) end,
		})
		self.unitStores[unit] = store
	end
	return store
end

-- value nil removes the change (back to the default).
function Config:SetUnitValue(unit, path, value)
	self:UnitStore(unit):Set(path, value)
end

-- Positions -------------------------------------------------------------------------

function Config:GetPosition(layout, key)
	if not self.db then
		return nil
	end
	return self.db.profile.positions[layout or "default"][key]
end

function Config:SetPosition(layout, key, point, x, y)
	self.db.profile.positions[layout or "default"][key] = { point = point, x = x, y = y }
end
