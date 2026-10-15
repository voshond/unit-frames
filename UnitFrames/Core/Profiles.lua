local _, ns = ...
local Schema, Util = ns.Schema, ns.Util

--[[
Profiles: AceDB profile management and shareable strings.

Profile operations change style only. The active profile keeps its Edit Mode
positions through new/copy/reset; switching shows that profile's own ones.

Strings are "!UF<format>!" followed by native CBOR, deflated and base64
encoded (C_EncodingUtil, ns.Caps.encoding). They carry one kind of data:

  Profiles:RegisterKind(key, {
    label,                    -- as used mid-sentence ("style")
    export  = function() return data end,
    prepare = function(data) return apply, dropped end,  -- or nil, reason
    perProfile = false,       -- optional: not stored in the profile, so no
                              -- "import as a new profile"
  })

prepare validates everything before anything is written and returns an
apply function plus the paths it skipped; apply then cannot fail. The core
"style" kind holds the theme and every unit's overrides; companions add
their own style data to it with RegisterStyleSection(key, { export, prepare }).
The "all" kind bundles every other kind in one string.
]]
local Profiles = { kinds = {}, kindOrder = {}, sections = {}, sectionOrder = {} }
ns.Profiles = Profiles

local FORMAT = 1
local MAX_NAME = 50

function Profiles:RegisterKind(key, kind)
	assert(not self.kinds[key], "Profiles: duplicate kind " .. key)
	self.kinds[key] = kind
	self.kindOrder[#self.kindOrder + 1] = key
end

function Profiles:RegisterStyleSection(key, section)
	assert(key ~= "theme" and key ~= "units" and not self.sections[key], "Profiles: bad style section " .. key)
	self.sections[key] = section
	self.sectionOrder[#self.sectionOrder + 1] = key
end

-- Profile management ------------------------------------------------------------

local function DB()
	return ns.Config.db
end

function Profiles:GetCurrent()
	return DB():GetCurrentProfile()
end

function Profiles:List()
	local list = DB():GetProfiles()
	table.sort(list)
	return list
end

function Profiles:Exists(name)
	return rawget(DB().profiles, name) ~= nil
end

local function CheckName(name)
	if type(name) ~= "string" then return nil, "Enter a profile name." end
	name = strtrim(name)
	if name == "" then return nil, "Enter a profile name." end
	if strlenutf8(name) > MAX_NAME then return nil, "Profile names are at most " .. MAX_NAME .. " characters." end
	return name
end

function Profiles:Switch(name)
	if not self:Exists(name) then return false, "There is no profile named " .. tostring(name) .. "." end
	DB():SetProfile(name)
	return true
end

-- A new profile with default style and the current positions, made active.
function Profiles:Create(name)
	local reason
	name, reason = CheckName(name)
	if not name then return false, reason end
	if self:Exists(name) then return false, "A profile named " .. name .. " already exists." end
	-- AceDB fills in the defaults when the profile is first used.
	DB().profiles[name] = { positions = ns.Config:GetPositions() }
	DB():SetProfile(name)
	return true, name
end

-- Runs fn (an AceDB operation on the active profile) and then restores that
-- profile's positions.
local function KeepingPositions(fn)
	local positions = ns.Config:GetPositions()
	fn()
	ns.Config:SetPositions(positions)
	ns.EditMode:ApplyPositions()
end

-- Copies another profile's style (and companion settings) into the active one.
function Profiles:Copy(from)
	if from == self:GetCurrent() then return false, "Choose another profile to copy from." end
	if not self:Exists(from) then return false, "There is no profile named " .. tostring(from) .. "." end
	KeepingPositions(function() DB():CopyProfile(from) end)
	return true
end

function Profiles:Delete(name)
	if name == self:GetCurrent() then return false, "The active profile can't be deleted." end
	if not self:Exists(name) then return false, "There is no profile named " .. tostring(name) .. "." end
	DB():DeleteProfile(name)
	return true
end

-- Back to the default style, keeping positions.
function Profiles:Reset()
	KeepingPositions(function() DB():ResetProfile(false, true) end)
	ns.Config:ProfileChanged()
	return true
end

-- Strings -------------------------------------------------------------------------

function Profiles:IsSupported()
	return ns.Caps.encoding
end

function Profiles:Export(kindKey)
	local kind = self.kinds[kindKey or "style"]
	assert(kind, "Profiles: unknown kind " .. tostring(kindKey))
	if not ns.Caps.encoding then return nil, "This client can't encode profile strings." end
	local payload = { addon = "UnitFrames", kind = kindKey or "style", version = ns.version, data = kind.export() }
	local E = C_EncodingUtil
	local compressed = E.CompressString(E.SerializeCBOR(payload), Enum.CompressionMethod.Deflate,
		Enum.CompressionLevel.OptimizeForSize)
	return "!UF" .. FORMAT .. "!" .. E.EncodeBase64(compressed)
end

local DAMAGED = "The string is incomplete or damaged. Copy the whole string again."

-- The payload table of a string, or nil and a reason.
function Profiles:Decode(text)
	if not ns.Caps.encoding then return nil, "This client can't decode profile strings." end
	if type(text) ~= "string" then return nil, "Paste a UnitFrames string first." end
	text = text:gsub("%s+", "")
	if text == "" then return nil, "Paste a UnitFrames string first." end
	local format, body = text:match("^!UF(%d+)!(.+)$")
	if not format then return nil, "This is not a UnitFrames string." end
	if tonumber(format) > FORMAT then return nil, "This string needs a newer version of UnitFrames." end
	local E = C_EncodingUtil
	local compressed = E.DecodeBase64(body)
	local serialized = compressed and E.DecompressString(compressed, Enum.CompressionMethod.Deflate)
	if not serialized then return nil, DAMAGED end
	-- External data boundary: malformed CBOR raises; report it as damaged.
	local ok, payload = pcall(E.DeserializeCBOR, serialized)
	if not ok or type(payload) ~= "table" or payload.addon ~= "UnitFrames" or type(payload.kind) ~= "string" then
		return nil, DAMAGED
	end
	return payload
end

--[[
Imports a string. With `profileName` (different from the active profile) the
data goes into a new profile, created and made active; otherwise it replaces
the active profile's data. Positions are never imported.
Returns true, the skipped paths and the kind's label, or false and a reason;
nothing is written when it fails.
]]
function Profiles:Import(text, profileName)
	local payload, reason = self:Decode(text)
	if not payload then return false, reason end
	local kind = self.kinds[payload.kind]
	if not kind then return false, "This string holds data this setup can't import (" .. payload.kind .. ")." end
	local apply, dropped = kind.prepare(payload.data)
	if not apply then return false, dropped end
	if profileName and strtrim(profileName) ~= "" and strtrim(profileName) ~= self:GetCurrent() then
		if kind.perProfile == false then return false, kind.label .. " aren't stored per profile." end
		local ok, created = self:Create(profileName)
		if not ok then return false, created end
	end
	apply()
	return true, dropped or {}, kind.label
end

-- The style kind ------------------------------------------------------------------

local function ExportStyle()
	local data = { theme = ns.Config:GetThemeOverrides(), units = {} }
	for _, unit in ipairs(ns.Units.order) do
		local overrides = ns.Config:GetUnitConfig(unit)
		if next(overrides) then data.units[unit] = Util.Copy(overrides) end
	end
	for _, key in ipairs(Profiles.sectionOrder) do
		data[key] = Profiles.sections[key].export()
	end
	return data
end

local function Prefixed(dropped, prefix, list)
	for _, path in ipairs(list or {}) do dropped[#dropped + 1] = prefix .. path end
end

local function PrepareStyle(data)
	if type(data) ~= "table" then return nil, DAMAGED end
	local dropped = {}
	local theme = Schema.Sanitize(ns.Theme.schema, data.theme, "theme.", dropped)
	local units = {}
	local imported = type(data.units) == "table" and data.units or {}
	for _, unit in ipairs(ns.Units.order) do
		local config = ns.Units:MigrateConfig(Util.Copy(imported[unit]))
		units[unit] = Schema.Sanitize(ns.Units:GetSchema(unit), config, "units." .. unit .. ".", dropped)
	end
	for unit in pairs(imported) do
		if not ns.Units.definitions[unit] then dropped[#dropped + 1] = "units." .. tostring(unit) end
	end
	local applies = {}
	for _, key in ipairs(Profiles.sectionOrder) do
		if data[key] ~= nil then
			local apply, sectionDropped = Profiles.sections[key].prepare(data[key])
			if not apply then return nil, sectionDropped end
			applies[#applies + 1] = apply
			Prefixed(dropped, key .. ".", sectionDropped)
		end
	end
	-- Data of companions that aren't loaded here (or unknown keys).
	for key in pairs(data) do
		if key ~= "theme" and key ~= "units" and not Profiles.sections[key] then dropped[#dropped + 1] = tostring(key) end
	end
	return function()
		for _, unit in ipairs(ns.Units.order) do
			ns.Config:UnitStore(unit):Replace(units[unit])
		end
		for _, apply in ipairs(applies) do apply() end
		-- Last: one ThemeChanged restyles everything with the new units.
		ns.Config:ReplaceTheme(theme)
	end, dropped
end

Profiles:RegisterKind("style", { label = "style", export = ExportStyle, prepare = PrepareStyle })

-- Every kind ------------------------------------------------------------------------

local ALL = "all"

local function ExportAll()
	local data = {}
	for _, key in ipairs(Profiles.kindOrder) do
		if key ~= ALL then data[key] = Profiles.kinds[key].export() end
	end
	return data
end

-- The style must import; other kinds that this setup lacks or that refuse
-- (bindings of another class) are skipped and listed with the reason.
local function PrepareAll(data)
	if type(data) ~= "table" or data.style == nil then return nil, DAMAGED end
	local applies, dropped = {}, {}
	for _, key in ipairs(Profiles.kindOrder) do
		if key ~= ALL and data[key] ~= nil then
			local apply, result = Profiles.kinds[key].prepare(data[key])
			if apply then
				applies[#applies + 1] = apply
				Prefixed(dropped, key == "style" and "" or key .. ".", result)
			elseif key == "style" then
				return nil, result
			else
				dropped[#dropped + 1] = Profiles.kinds[key].label .. " (" .. result .. ")"
			end
		end
	end
	for key in pairs(data) do
		if key == ALL or not Profiles.kinds[key] then dropped[#dropped + 1] = tostring(key) end
	end
	return function()
		for _, apply in ipairs(applies) do apply() end
	end, dropped
end

Profiles:RegisterKind(ALL, { label = "all settings", export = ExportAll, prepare = PrepareAll })

-- Public API on the UnitFrames handle (setup tools such as Wago) --------------------

function ns:ExportProfile()
	return Profiles:Export("style")
end

-- Returns true and the skipped paths, or false and a reason.
function ns:ImportProfile(text, profileName)
	return Profiles:Import(text, profileName)
end

function ns:SetProfile(name)
	return Profiles:Switch(name)
end

function ns:GetProfileKeys()
	return Profiles:List()
end

function ns:GetCurrentProfile()
	return Profiles:GetCurrent()
end
