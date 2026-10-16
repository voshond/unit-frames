local _, ns = ...
local Rows, Colors = ns.UnitRows, ns.Colors

--[[
Data drivers: how a UnitFrame's state, rows and optional parts get their
values, declared once per key for every source.

  element                          the oUF element name
  bind(component)                  live oUF frames: the widget the element
                                   drives, plus an optional signature of what
                                   oUF reads only when enabling the element
                                   (sub-widgets, modes). A changed signature
                                   re-enables it (Units.SetElement).
  sample(component, values, cfg)   plain sample values (Units.SAMPLE)
  live(component, unit, ctx, cfg)  previews outside oUF polling an explicit
                                   unit; ctx is the caller's scratch table for
                                   that preview. Values go straight to widgets.

A source a key does not support is false, with the reason beside it.
Frame drivers receive the UnitFrame and decide for themselves when they are
off. Rows are bound, sampled and polled only while enabled. Parts are bound
while enabled; their sample/live calls follow their own enabled state.
Components stay oUF-free: drivers only call their public methods.
]]
local Drivers = { frame = {}, rows = {}, parts = {} }
ns.UnitDrivers = Drivers

-- Shared readers ---------------------------------------------------------------

-- (inRange, checked) for the UnitFrame's range settings. Either can be secret
-- in combat: they are only passed on, never tested.
function Drivers.RangeState(uf, unit)
	if not unit or not UnitExists(unit) or not UnitIsConnected(unit) then
		return true, false
	end
	local cfg = uf.resolved.range
	if cfg.mode == "spell" then
		local spell = cfg.spell:match("^%s*(.-)%s*$")
		if not ns.Caps.spellRange or spell == "" then
			return true, false
		end
		local inRange = C_Spell.IsSpellInRange(tonumber(spell) or spell, unit)
		if type(inRange) == "nil" then
			return true, false
		end
		return inRange, true
	elseif ns.Caps.groupRange then
		return UnitInRange(unit)
	end
	return true, false
end

-- UnitClassification is not secret; an opaque result shows nothing rather
-- than be inspected.
function Drivers.Classification(unit)
	if not unit or not UnitExists(unit) then return nil end
	local classification = UnitClassification(unit)
	if issecretvalue(classification) then return nil end
	return classification
end

-- The player's combo points on the frame's unit (a player frame shows those
-- on the target) and their maximum. Forever stores them on the target, like
-- Blizzard's ComboFrame. The count may be secret and only goes to
-- StatusBars; the player's maximum is plain, else the classic five.
function Drivers.ComboPoints(unit)
	local max = UnitPowerMax("player", Enum.PowerType.ComboPoints)
	if issecretvalue(max) then max = 5 end
	return GetComboPoints("player", unit == "player" and "target" or unit), max
end

-- Whole-frame state ------------------------------------------------------------

Drivers.frame = {
	-- Resting is plain player state (IsResting), never opaque unit data.
	{ key = "resting", element = "UF_Resting",
		bind = function(uf) return uf.spec.resting and uf.resolved.resting.enabled and uf or nil end,
		sample = function(uf, v) uf:SetResting(uf.spec.resting and v.resting == true, v.restingAnimated == true) end,
		live = function(uf, unit) uf:SetResting(uf.spec.resting == true and unit == "player" and IsResting()) end },
	{ key = "readyCheck", element = "UF_ReadyCheck",
		bind = function(uf)
			local readyCheck = uf:GetReadyCheck()
			return readyCheck and readyCheck:IsShown() and readyCheck or nil
		end,
		-- values.readyCheck: "waiting", "ready", "notready" or nil; with
		-- readyCheckTime the sample loops through a whole check (tints and icon).
		sample = function(uf, v)
			local readyCheck = uf:GetReadyCheck()
			if readyCheck then readyCheck:Sample(v.readyCheck, v.readyCheckTime, v.readyCheckAnswerAt) end
		end,
		-- A check is event-driven: it starts, collects answers and fades after
		-- it finishes. Only oUF frames follow one.
		live = false },
	-- The spell check is read when the element is enabled (events or polling).
	{ key = "range", element = "UF_Range",
		bind = function(uf)
			local range = uf.resolved.range
			if range.enabled and ns.Caps.booleanAlpha then return uf, { range.mode } end
		end,
		sample = function(uf, v) uf:SetRangeState(v.outOfRange ~= true, true) end,
		live = function(uf, unit) uf:SetRangeState(Drivers.RangeState(uf, unit)) end },
}
-- Also by key; ipairs still sees only the ordered list.
for _, driver in ipairs(Drivers.frame) do Drivers.frame[driver.key] = driver end

-- Rows ------------------------------------------------------------------------

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
	Rows.LiveHealthColor(self.uf:GetRow("health"), self.uf:GetRowConfig("health").colorMode, unit)
end

local function UpdatePowerColor(self, _, unit)
	if not unit or self.__unit ~= unit then -- same guard as oUF's own elements
		return
	end
	local _, token = UnitPowerType(unit)
	self.uf:GetRow("power"):SetColor(Colors.Power(token))
end

Drivers.rows.health = {
	element = "Health",
	-- Prediction subscriptions depend on which sub-widgets are enabled.
	bind = function(row)
		local bar = row:GetBar()
		local health = bar:GetStatusBar()
		local healing, absorb, healAbsorb = bar:GetSegmentBar("heal"), bar:GetSegmentBar("absorb"), bar:GetSegmentBar("healAbsorb")
		health.HealingAll, health.DamageAbsorb, health.HealAbsorb = healing, absorb, healAbsorb
		-- Both placements must show shields at full health. Appending reserves
		-- shield space inside the frame by including it in the native bar scale.
		-- Set initial oUF options AND the existing calculator when re-styling.
		health.maximumHealthClampMode = Rows.HealthMaximumMode(bar)
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
		return health, { healing, absorb, healAbsorb }
	end,
	sample = function(row, v, cfg)
		Rows.SampleHealth(row, v)
		if cfg.colorMode == "class" then
			row:SetColor(Colors.Sample(v))
		elseif cfg.colorMode == "gradient" then
			row:SetColor(Colors.HealthCurve():Evaluate(v.health / v.healthMax):GetRGB())
		else
			row:ClearColor()
		end
	end,
	live = function(row, unit, ctx, cfg)
		ctx.calculator = ctx.calculator or CreateUnitHealPredictionCalculator()
		Rows.LiveHealth(row, unit, ctx.calculator, cfg.colorMode)
	end,
}

Drivers.rows.power = {
	element = "Power",
	bind = function(row)
		local bar = row:GetBar()
		local power = bar:GetStatusBar()
		power.CostPrediction = bar:GetSegmentBar("cost")
		power.smoothing = Smoothing(bar)
		power.frequentUpdates = true
		power.UpdateColor = UpdatePowerColor
		return power
	end,
	sample = function(row, v) Rows.SamplePower(row, v) end,
	live = function(row, unit) Rows.LivePower(row, unit) end,
}

-- Experience is player-only.
Drivers.rows.experience = {
	element = "UF_Experience",
	bind = function(row) return row end,
	sample = function(row, v) Rows.Experience(row, v.xp, v.xpMax, v.rested) end,
	live = function(row, unit)
		if unit ~= "player" then return end
		Rows.PlayerExperience(row)
		row:ShowLive(unit)
	end,
}

-- Optional parts (UnitFrame.PARTS) --------------------------------------------

Drivers.parts.portrait = {
	element = "Portrait",
	bind = function(portrait) return portrait:GetWidget() end,
	-- The real character; there's no sample model.
	sample = function(portrait) if portrait:IsEnabled() then portrait:SetUnit("player") end end,
	live = function(portrait, unit) if portrait:IsEnabled() then portrait:SetUnit(unit) end end,
}

Drivers.parts.castbar = {
	element = "UF_Castbar",
	bind = function(castbar) return castbar end,
	-- values.showCast = false hides the sample cast (it can cover the health bar).
	sample = function(castbar, v)
		if not castbar:IsEnabled() then return end
		if v.showCast == false then
			castbar:Hide()
		else
			local progress = v.castProgress
			castbar:Preview({ name = v.spell, icon = v.spellIcon, castTime = v.castTime, latency = v.castLatency },
				progress, string.format("%.1f", v.castTime * (1 - progress)))
		end
		if v.gcdProgress then castbar:PreviewGCD(v.gcdProgress) else castbar:StopGCD() end
	end,
	-- Casts are event-driven (Units/Cast.lua); polling would restart them.
	live = false,
}

-- Target and player frames (Units.definitions).
Drivers.parts.comboPoints = {
	element = "UF_ComboPoints",
	bind = function(points) return points end,
	sample = function(points, v) points:Preview(v.comboPoints, v.comboPointsMax) end,
	live = function(points, unit)
		if unit ~= "player" and unit ~= "target" then return end
		local count, max = Drivers.ComboPoints(unit)
		points:SetMax(max)
		points:SetValue(count)
	end,
}

Drivers.parts.auras = {
	element = "UF_Auras",
	bind = function(auras) return auras end,
	sample = function(auras, v) auras:ShowSample(v) end,
	live = function(auras, unit)
		auras:SetEnabled(auras.resolved.enabled)
		auras:SetUnit(unit)
	end,
}

Drivers.parts.auraBar = {
	element = "UF_AuraBar",
	bind = function(bar) return bar end,
	sample = function(bar, v) bar:ShowSample(v) end,
	live = function(bar, unit)
		bar:SetEnabled(bar.resolved.enabled)
		bar:SetUnit(unit)
	end,
}

Drivers.parts.raidTarget = {
	element = "RaidTargetIndicator",
	bind = function(marker) return marker:GetWidget() end,
	sample = function(marker, v) marker:SetIndex(v.raidTarget) end,
	live = function(marker, unit) marker:SetIndex(GetRaidTargetIndex(unit)) end,
}

Drivers.parts.pvp = {
	element = "PvPIndicator",
	-- oUF reads the background circle on enable.
	bind = function(flag) return flag:GetWidget(), { flag:GetBackground() } end,
	sample = function(flag, v) flag:SetSample(v.pvp) end,
	-- oUF's PvPIndicator owns the secret-safe art choice; not repeated here.
	live = false,
}

Drivers.parts.classification = {
	element = "UF_Classification",
	bind = function(icon) return icon end,
	sample = function(icon, v) icon:SetClassification(v.isPlayer == false and v.classification or nil) end,
	live = function(icon, unit) icon:SetClassification(Drivers.Classification(unit)) end,
}

-- The UnitFrame's ReadyCheck presenter drives whichever icon is attached
-- (this part, or a companion's own), live and in samples.
Drivers.parts.readyCheckIcon = { bind = false, sample = false, live = false }

function Drivers.Row(key)
	return assert(Drivers.rows[key], "No data driver for row: " .. tostring(key))
end

function Drivers.Part(key)
	return assert(Drivers.parts[key], "No data driver for part: " .. tostring(key))
end
