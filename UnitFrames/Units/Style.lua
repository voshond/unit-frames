local _, ns = ...
local oUF, Units, Colors, Formats = ns.oUF, ns.Units, ns.Colors, ns.Formats

--[[
oUF integration: the style builds our UnitFrame component inside the oUF unit
button, then binds rows to oUF elements. oUF decides when values update (and
keeps to the secret-safe paths); our components decide how it looks.

Re-binding after a config change enables/disables elements and re-tags texts.
]]

Units.STYLE = "UnitFrames"

-- oUF element name per row key.
local ELEMENTS = {
	health = "Health",
	power = "Power",
	experience = "UF_Experience",
}

local function Smoothing(bar)
	if bar.resolved.smooth and ns.Caps.smoothBars then
		return Enum.StatusBarInterpolation.ExponentialEaseOut
	end
	return Enum.StatusBarInterpolation.Immediate
end

-- Colour overrides (oUF calls these after every update). Values may be secret.
local function UpdateHealthColor(self, _, unit)
	if not unit or self.__unit ~= unit then -- same guard as oUF's own elements
		return
	end
	ns.UnitRows.LiveHealthColor(self.uf:GetRow("health"), self.uf:GetRowConfig("health").colorMode, unit)
end

local function UpdatePowerColor(self, _, unit)
	if not unit or self.__unit ~= unit then -- same guard as oUF's own elements
		return
	end
	local _, token = UnitPowerType(unit)
	self.uf:GetRow("power"):SetColor(Colors.Power(token))
end

-- Row widgets for oUF, with their sub-widgets and options set.
local widgets = {}

function widgets.health(row)
	local bar = row:GetBar()
	local health = bar:GetStatusBar()
	local healing, absorb, healAbsorb = bar:GetSegmentBar("heal"), bar:GetSegmentBar("absorb"), bar:GetSegmentBar("healAbsorb")
	local predictionChanged = health.HealingAll ~= healing or health.DamageAbsorb ~= absorb or health.HealAbsorb ~= healAbsorb
	health.HealingAll, health.DamageAbsorb, health.HealAbsorb = healing, absorb, healAbsorb
	-- Both placements must show shields at full health. Appending reserves
	-- shield space inside the frame by including it in the native bar scale.
	-- Set initial oUF options AND the existing calculator when re-styling.
	health.maximumHealthClampMode = ns.UnitRows.HealthMaximumMode(bar)
	health.damageAbsorbClampMode = Enum.UnitDamageAbsorbClampMode.MaximumHealth
	if health.values then
		health.values:SetMaximumHealthMode(health.maximumHealthClampMode)
		health.values:SetDamageAbsorbClampMode(health.damageAbsorbClampMode)
	end
	health.smoothing = Smoothing(bar)
	-- Keep reaction/tap colours current even when health hasn't changed.
	health.colorReaction = true
	health.colorTapping = true
	health.UpdateColor = UpdateHealthColor
	return health, predictionChanged
end

function widgets.power(row)
	local bar = row:GetBar()
	local power = bar:GetStatusBar()
	power.CostPrediction = bar:GetSegmentBar("cost")
	power.smoothing = Smoothing(bar)
	power.frequentUpdates = true
	power.UpdateColor = UpdatePowerColor
	return power
end

function widgets.experience(row)
	return row
end

-- Points an oUF element at `widget` (nil switches it off). A different widget
-- (e.g. 3D model vs. texture portrait) needs the element re-enabled. Before
-- oUF has enabled the elements (inside the style function) only the key is set.
local function SetElement(frame, element, widget, rebind)
	local ready = frame.ufReady
	if ready and frame:IsElementEnabled(element) and (widget ~= frame[element] or rebind) then
		frame:DisableElement(element)
	end
	frame[element] = widget
	if ready and widget and not frame:IsElementEnabled(element) then
		frame:EnableElement(element)
	end
end

Units.SetElement = SetElement

local function TagRow(frame, row, rowEnabled)
	for _, slot in ipairs(ns.Components.TextBar.SLOTS) do
		local text = row:GetText(slot.key)
		local fs = text:GetFrame()
		local format = text:GetFormat()
		if rowEnabled and text:IsEnabled() and format ~= "none" then
			frame:Tag(fs, Formats.Tag(format))
		else
			frame:Untag(fs)
			fs:SetText("")
		end
	end
end

-- oUF element per optional part (UnitFrame.PARTS) and the widget it drives;
-- without `widget` the element drives the part component itself. Parts
-- without an entry are driven by the UnitFrame (the ready check icon).
local PART_ELEMENTS = {
	portrait = { element = "Portrait", widget = function(portrait) return portrait:GetWidget() end },
	castbar = { element = "UF_Castbar" },
	auras = { element = "UF_Auras" },
	raidTarget = { element = "RaidTargetIndicator", widget = function(marker) return marker:GetWidget() end },
	-- oUF reads the background circle on enable: re-enable when it changes.
	pvp = { element = "PvPIndicator", widget = function(flag) return flag:GetWidget() end,
		subWidget = function(flag) return flag:GetBackground() end },
	classification = { element = "UF_Classification" },
}

-- Points oUF elements and tags at the current rows and parts.
function Units:Bind(frame)
	local uf = frame.uf
	SetElement(frame, "UF_Resting", uf.spec.resting and uf.resolved.resting.enabled and uf or nil)
	SetElement(frame, "UF_ReadyCheck", uf.spec.readyCheck and uf:IsReadyCheckShown() and uf or nil)
	for key, row, cfg in uf:Rows() do
		local widget, rebind
		if cfg.enabled then widget, rebind = widgets[key](row) end
		-- Prediction subscriptions depend on which sub-widgets are enabled.
		SetElement(frame, ELEMENTS[key], widget, rebind)
		TagRow(frame, row, cfg.enabled)
	end
	frame.ufSubWidgets = frame.ufSubWidgets or {}
	for key, part in uf:Parts() do
		local binding = PART_ELEMENTS[key]
		if binding then
			local widget = part:IsEnabled() and (binding.widget and binding.widget(part) or part) or nil
			local subWidget = binding.subWidget and binding.subWidget(part)
			SetElement(frame, binding.element, widget, frame.ufSubWidgets[key] ~= subWidget)
			frame.ufSubWidgets[key] = subWidget
		end
	end
	local range = uf.resolved.range
	SetElement(frame, "UF_Range", range.enabled and ns.Caps.booleanAlpha and uf or nil,
		frame.ufRangeMode ~= range.mode)
	frame.ufRangeMode = range.mode
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

function Units:CopyPlayerSettings(unit)
	local player, target = self.frames.player, self.frames[unit]
	if unit == "player" or not player or not target then return false end
	local schema, theme = target.uf:GetSchema(), ns.Config:GetTheme()
	local overrides = ns.Config:GetUnitConfig("player")
	local source = ns.Schema.Resolve(player.uf:GetSchema(), overrides, theme)
	local defaults = ns.Schema.Resolve(schema, nil, theme)
	-- Positions live separately in Edit Mode. The target's schema excludes XP.
	return ns.Config:UnitStore(unit):Replace(CopySettings(schema, source, overrides, defaults))
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
	frame.ufReady = true -- oUF has enabled the elements now
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
