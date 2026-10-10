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
