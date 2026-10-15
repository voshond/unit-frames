local _, ns = ...
local Schema, Util = ns.Schema, ns.Util

-- Profile storage (AceDB). The profile only stores values that differ from
-- the schema defaults; AceDB strips everything else on logout.
local Config = {}
ns.Config = Config

-- Bumped before every ThemeChanged. Theme-derived caches compare it instead of
-- listening themselves: listeners run in no fixed order, so a refresh could
-- otherwise read a cache that has not been invalidated yet.
Config.themeRevision = 0

local function ThemeChanged(path)
	Config.themeRevision = Config.themeRevision + 1
	ns.Events:Fire("ThemeChanged", path)
end

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

-- Every character gets a profile of its own, once: one still using the
-- shared "Default" profile (new characters and those from before) moves to a
-- copy of it, with its style, positions and companion data. Afterwards a
-- deliberate choice of any profile, Default included, stays.
local function OwnProfile(db)
	local own = db.keys.char
	-- An opaque character name can't name a profile; stay on Default.
	if issecretvalue(own) or db.char.ownProfile then return end
	db.char.ownProfile = true
	if db:GetCurrentProfile() ~= "Default" or own == "Default" then return end
	local exists = rawget(db.profiles, own) ~= nil
	db:SetProfile(own)
	if not exists then db:CopyProfile("Default") end
end

function Config:Initialize()
	self.db = LibStub("AceDB-3.0"):New("UnitFramesDB", BuildDefaults(), true)
	OwnProfile(self.db)
	local function OnProfile()
		self:ProfileChanged()
	end
	self.db.RegisterCallback(self, "OnProfileChanged", OnProfile)
	self.db.RegisterCallback(self, "OnProfileCopied", OnProfile)
	self.db.RegisterCallback(self, "OnProfileReset", OnProfile)
end

-- Everything that reads the profile refreshes: positions on ProfileChanged,
-- styles (unit frames, ClickGrid, previews) on ThemeChanged.
function Config:ProfileChanged()
	ns.Events:Fire("ProfileChanged")
	ThemeChanged()
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

-- Only the options that differ from the defaults, as a fresh table.
local function Overrides(schema, values, defaults)
	local out = {}
	for _, opt in ipairs(schema) do
		local value, default = values[opt.key], defaults[opt.key]
		if opt.type == "group" and type(value) == "table" then
			local group = Overrides(opt.schema, value, default or {})
			if next(group) then out[opt.key] = group end
		elseif value ~= nil and not Util.Equals(value, default) then
			out[opt.key] = Util.Copy(value)
		end
	end
	return out
end

function Config:GetThemeOverrides()
	return Overrides(ns.Theme.schema, self:GetTheme(), self:GetThemeDefaults())
end

-- Replaces the whole theme with the defaults plus `overrides` (validated by
-- the caller), firing one ThemeChanged.
function Config:ReplaceTheme(overrides)
	local theme = self:GetTheme()
	wipe(theme)
	Util.Merge(theme, self:GetThemeDefaults())
	local function Apply(schema, values, prefix)
		for _, opt in ipairs(schema) do
			local value = values[opt.key]
			if opt.type == "group" and type(value) == "table" then
				Apply(opt.schema, value, prefix .. opt.key .. ".")
			elseif value ~= nil then
				-- Whole values: a three-channel colour must not keep a default alpha.
				Util.SetPath(theme, prefix .. opt.key, Util.Copy(value))
			end
		end
	end
	Apply(ns.Theme.schema, overrides or {}, "")
	ThemeChanged()
end

-- value nil resets the option to its default.
function Config:SetThemeValue(path, value)
	if value == nil then
		value = Util.Copy(Util.GetPath(self:GetThemeDefaults(), path))
	end
	Util.SetPath(self:GetTheme(), path, value)
	ThemeChanged(path)
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
		store = ns.Store:New({
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

-- Every layout's positions, copied (profile operations that keep them).
function Config:GetPositions()
	return Util.Copy(self.db.profile.positions)
end

function Config:SetPositions(positions)
	local stored = self.db.profile.positions
	wipe(stored)
	Util.Merge(stored, positions)
end
