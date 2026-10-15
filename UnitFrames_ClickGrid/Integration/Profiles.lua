local _, CG = ...
local UF = CG.UF

--[[
Profile strings (UnitFrames/Core/Profiles.lua). The panel settings and the
member/target bar styles travel with the UnitFrames style string; a style
string without them leaves ClickGrid as it is. Click bindings are saved per
character and specialization, and their spells per class, so they have a
string of their own that replaces the current specialization's bindings.
]]
local STYLE_PARTS = { "settings", "member", "target" }

local function Stores()
	local config = CG.Config
	return { settings = config.settings, member = config.styles.member, target = config.styles.target }
end

-- Sanitized and fully validated replacements for every store, or nil and a reason.
local function Prepare(stores, data, parts)
	if type(data) ~= "table" then return nil, "The ClickGrid data is damaged." end
	local clean, dropped = {}, {}
	for _, part in ipairs(parts) do
		local store = stores[part]
		clean[part] = UF.Schema.Sanitize(store:GetSchema(), data[part], part .. ".", dropped)
		local ok, reason = store:Check(clean[part])
		if not ok then return nil, "ClickGrid: " .. reason end
	end
	return function()
		for _, part in ipairs(parts) do stores[part]:Replace(clean[part]) end
	end, dropped
end

UF.Profiles:RegisterStyleSection("clickgrid", {
	export = function()
		local data = {}
		for part, store in pairs(Stores()) do data[part] = UF.Util.Copy(store:Read()) end
		return data
	end,
	prepare = function(data) return Prepare(Stores(), data, STYLE_PARTS) end,
})

-- The player's class token, or nil while it is secret.
local function PlayerClass()
	local _, class = UnitClass("player")
	if issecretvalue(class) then return nil end
	return class
end

UF.Profiles:RegisterKind("clickgrid.bindings", {
	label = "ClickGrid click bindings",
	perProfile = false,
	export = function()
		return { class = PlayerClass(), bindings = UF.Util.Copy(CG.Config:GetBindings()) }
	end,
	prepare = function(data)
		if type(data) ~= "table" then return nil, "The ClickGrid data is damaged." end
		local class = PlayerClass()
		if type(data.class) == "string" and class and data.class ~= class then
			local names = LOCALIZED_CLASS_NAMES_MALE or {}
			return nil, "These bindings are for " .. (names[data.class] or data.class) .. " spells."
		end
		return Prepare({ bindings = CG.Config.bindings }, data, { "bindings" })
	end,
})
