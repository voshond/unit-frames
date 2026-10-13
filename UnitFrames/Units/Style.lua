local _, ns = ...
local oUF, Units, Formats = ns.oUF, ns.Units, ns.Formats

--[[
oUF integration: the style builds our UnitFrame component inside the oUF unit
button, then binds it to oUF elements through the data drivers
(Units/Drivers.lua). oUF decides when values update (and keeps to the
secret-safe paths); our components decide how it looks.

Re-binding after a config change enables/disables elements and re-tags texts.
]]

Units.STYLE = "UnitFrames"

-- Frames whose elements oUF has enabled. Init callbacks run right after it
-- enabled them, for every frame of this oUF (unit buttons and companions'
-- header children alike).
local ready = setmetatable({}, { __mode = "k" })
oUF:RegisterInitCallback(function(frame) ready[frame] = true end)

-- What oUF read when it last enabled each element, per frame (driver
-- signatures). Compared entry by entry: signatures may contain nils.
local signatures = setmetatable({}, { __mode = "k" })

local function SameSignature(a, b)
	if a == b then return true end
	if not a or not b then return false end
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	for k, v in pairs(b) do if a[k] ~= v then return false end end
	return true
end

-- Points an oUF element at `widget` (nil switches it off). A different widget
-- (e.g. 3D model vs. texture portrait) or a changed `signature` (sub-widgets
-- or modes oUF reads on enable) needs the element re-enabled. Before oUF has
-- enabled the elements (inside the style function) only the key is set.
local function SetElement(frame, element, widget, signature)
	local bound = signatures[frame] or {}
	signatures[frame] = bound
	local changed = not SameSignature(bound[element], signature)
	bound[element] = signature
	local enabled = ready[frame]
	if enabled and frame:IsElementEnabled(element) and (widget ~= frame[element] or changed) then
		frame:DisableElement(element)
	end
	frame[element] = widget
	if enabled and widget and not frame:IsElementEnabled(element) then
		frame:EnableElement(element)
	end
end

Units.SetElement = SetElement

-- Binds a driver's element (Units/Drivers.lua); `on` false switches it off.
-- Drivers without a binding are driven by something else.
local function BindDriver(frame, driver, component, on)
	if not driver.bind then return end
	local widget, signature
	if on then widget, signature = driver.bind(component) end
	SetElement(frame, driver.element, widget, signature)
end

-- Presets the host fully shows use their shared [uf:<id>] tag; other slots
-- a reusable handle tag (Units/TextTags.lua).
local function TagRow(frame, row, rowEnabled)
	local TextTags = ns.TextTags
	for _, slot in ipairs(ns.Components.TextBar.SLOTS) do
		local text = row:GetText(slot.key)
		local fs = text:GetFrame()
		local template, preset = text:GetTemplate(), text:GetPresetTag()
		if rowEnabled and text:IsEnabled() and not template.empty then
			if preset then
				TextTags.Unbind(fs)
				frame:Tag(fs, Formats.Tag(preset))
			else
				TextTags.Bind(frame, fs, template)
			end
		else
			TextTags.Unbind(fs)
			frame:Untag(fs)
			fs:SetText("")
		end
	end
end

-- Points oUF elements and tags at the current frame state, rows and parts.
function Units:Bind(frame)
	ns.Perf:Count("unitBind")
	local uf, Drivers = frame.uf, ns.UnitDrivers
	-- Companions attach their own ready check icon later: rebind on changes.
	local readyCheck = uf:GetReadyCheck()
	if readyCheck then
		readyCheck:SetChangedCallback(function() BindDriver(frame, Drivers.frame.readyCheck, uf, true) end)
	end
	for _, driver in ipairs(Drivers.frame) do
		BindDriver(frame, driver, uf, true)
	end
	for key, row, cfg in uf:Rows() do
		BindDriver(frame, Drivers.Row(key), row, cfg.enabled)
		TagRow(frame, row, cfg.enabled)
	end
	for key, part in uf:Parts() do
		BindDriver(frame, Drivers.Part(key), part, part:IsEnabled())
	end
	-- Element enable/disable can hide artwork after the component layout.
	uf:GetDecorations():Reflow()
end

-- Re-applies config to a live frame and refreshes everything shown on it.
function Units:Refresh(unit)
	local frame = self.frames[unit]
	if not frame then
		return
	end
	frame.uf:Apply(ns.Config:GetUnitConfig(unit))
	self:Bind(frame)
	ns.Perf:Count("updateAllElements")
	frame:UpdateAllElements("UnitFramesRefresh")
	frame:UpdateTags()
end

-- Copy effective settings, not just overrides: the units have different
-- defaults (notably the compact target-of-target). Keep theme inheritance
-- where the player hasn't overridden it and the target already matches.
local function CopySettings(schema, source, overrides, defaults)
	local result = {}
	for _, opt in ipairs(schema) do
		local value, raw = source[opt.key], overrides and overrides[opt.key]
		if opt.type == "group" and type(value) == "table" then
			local group = CopySettings(opt.schema, value, raw, defaults[opt.key])
			if next(group) then result[opt.key] = group end
		elseif opt.type ~= "group" and opt.type ~= "action" and value ~= nil
			and (raw ~= nil or not ns.Util.Equals(value, defaults[opt.key])) then
			result[opt.key] = ns.Util.Copy(value)
		end
	end
	return result
end

-- Text slots copy only what the destination can show (Text.AdaptCopy).
local function AdaptTexts(schema, source, copy)
	for _, opt in ipairs(schema) do
		if opt.type == "group" and type(source[opt.key]) == "table" then
			if opt.textSlot then
				local group = ns.Components.Text.AdaptCopy(copy[opt.key] or {}, source[opt.key], opt.textSlot)
				if next(group) then copy[opt.key] = group end
			else
				local child = copy[opt.key] or {}
				AdaptTexts(opt.schema, source[opt.key], child)
				if next(child) then copy[opt.key] = child end
			end
		end
	end
end

function Units:CopyPlayerSettings(unit)
	local player, target = self.frames.player, self.frames[unit]
	if unit == "player" or not player or not target then return false end
	local schema, theme = target.uf:GetSchema(), ns.Config:GetTheme()
	local overrides = ns.Config:GetUnitConfig("player")
	local source = ns.Schema.Resolve(player.uf:GetSchema(), overrides, theme)
	local defaults = ns.Schema.Resolve(schema, nil, theme)
	-- Positions live separately in Edit Mode. The target's schema excludes XP.
	local copy = CopySettings(schema, source, overrides, defaults)
	AdaptTexts(schema, source, copy)
	return ns.Config:UnitStore(unit):Replace(copy)
end

-- Unit tooltip hooks for oUF frames. Blizzard's UnitFrame_OnEnter reads
-- self.unit, which oUF frames don't have; oUF keeps the current unit in __unit.
function Units.ShowTooltip(frame)
	if not frame.__unit then return end
	GameTooltip_SetDefaultAnchor(GameTooltip, frame)
	if GameTooltip:SetUnit(frame.__unit) then
		GameTooltip:Show()
	end
end

function Units.HideTooltip()
	GameTooltip:Hide()
end

oUF:RegisterStyle(Units.STYLE, function(frame, unit)
	frame.uf = Units:CreateFrame(unit, UIParent, frame)
	frame.uf:SetThemeManaged(true)
	frame:RegisterForClicks("AnyUp")
	frame:HookScript("OnEnter", Units.ShowTooltip)
	frame:HookScript("OnLeave", Units.HideTooltip)
	Units:Bind(frame)
end)

-- Spawning --------------------------------------------------------------------

local function Spawn(factory, unit)
	local def = Units.definitions[unit]
	local name = "UnitFrames" .. unit:gsub("^%l", string.upper)
	local frame = factory:Spawn(unit, name)
	Units.frames[unit] = frame
	ns.EditMode:Register(frame, unit, "UnitFrames: " .. def.label, def.defaultPosition)
	return frame
end

oUF:Factory(function(factory)
	factory:SetActiveStyle(Units.STYLE)
	for _, unit in ipairs(Units.order) do Spawn(factory, unit) end
end)

ns.Events.RegisterCallback(Units, "UnitConfigChanged", function(_, unit)
	Units:Refresh(unit)
end)

-- Colours come from the theme too (power colours, health gradient).
ns.Events.RegisterCallback(Units, "ThemeChanged", function()
	for unit in pairs(Units.frames) do
		Units:Refresh(unit)
	end
end)
