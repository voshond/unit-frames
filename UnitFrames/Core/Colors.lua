local _, ns = ...
local Util = ns.Util

-- Colour helpers shared by unit frames and the Workbench. Everything here
-- works with secret values (curves, ColorMixin results passed through).
local Colors = {}
ns.Colors = Colors

function Colors.Theme(key)
	return Util.UnpackColor(ns.Config:GetTheme().colors[key])
end

-- Theme colour keys per power type token (UnitPowerType's second return).
Colors.POWER_KEYS = {
	MANA = "mana",
	RAGE = "rage",
	ENERGY = "energy",
	FOCUS = "focus",
	RUNIC_POWER = "runicPower",
}

function Colors.Power(token)
	local key = Colors.POWER_KEYS[token]
	if key then
		return Colors.Theme(key)
	end
	local color = PowerBarColor and PowerBarColor[token]
	if color then
		return color.r, color.g, color.b, 1
	end
	return Colors.Theme("mana")
end

-- Class colour as r, g, b. C_ClassColor accepts a secret class token.
function Colors.Class(token)
	-- Missing unit/sample class data is not a valid native API argument.
	-- type() is safe for opaque tokens; valid secret tokens still go native.
	if type(token) == "nil" then return 0.5, 0.5, 0.5 end
	if C_ClassColor and C_ClassColor.GetClassColor then
		local color = C_ClassColor.GetClassColor(token)
		if color then
			return color:GetRGB()
		end
	end
	local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if color then
		return color.r, color.g, color.b
	end
	return 0.5, 0.5, 0.5
end

-- Theme colour key for an NPC's reaction to the player (UnitReaction 1..8).
function Colors.ReactionKey(reaction)
	if reaction == nil then
		return "neutral"
	elseif reaction <= 3 then
		return "hostile"
	elseif reaction == 4 then
		return "neutral"
	end
	return "friendly"
end

--[[
Unit colour for the "class / reaction" mode: offline -> disconnected,
players -> class, NPCs tapped by others -> tapped, other NPCs -> reaction.
UnitIsPlayer, UnitIsConnected, UnitIsTapDenied and UnitReaction are not
secret; the class token may be, which C_ClassColor accepts.
]]
function Colors.Unit(unit)
	if not UnitIsConnected(unit) then
		return Colors.Theme("disconnected")
	elseif UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		return Colors.Class(class)
	elseif UnitIsTapDenied(unit) then
		return Colors.Theme("tapped")
	end
	return Colors.Theme(Colors.ReactionKey(UnitReaction(unit, "player")))
end

-- Same for plain sample values: { isPlayer, class, reaction ("hostile"/...) }
function Colors.Sample(values)
	if values.isPlayer == false then
		return Colors.Theme(values.reaction or "hostile")
	end
	return Colors.Class(values.class)
end

-- Health gradient (low -> mid -> full) as a colour curve; use with
-- UnitHealthPercent(unit, true, curve) for secret health. Rebuilt after
-- theme changes (Config.themeRevision).
local healthCurve, healthCurveRevision
function Colors.HealthCurve()
	if not healthCurve or healthCurveRevision ~= ns.Config.themeRevision then
		healthCurveRevision = ns.Config.themeRevision
		healthCurve = C_CurveUtil.CreateColorCurve()
		healthCurve:AddPoint(0, CreateColor(Colors.Theme("healthLow")))
		healthCurve:AddPoint(0.5, CreateColor(Colors.Theme("healthMid")))
		healthCurve:AddPoint(1, CreateColor(Colors.Theme("health")))
	end
	return healthCurve
end

-- Maps 0..1 to 0..100 for percent texts.
local percentCurve
function Colors.PercentCurve()
	if CurveConstants and CurveConstants.ScaleTo100 then
		return CurveConstants.ScaleTo100
	end
	if not percentCurve then
		percentCurve = C_CurveUtil.CreateCurve()
		percentCurve:AddPoint(0, 0)
		percentCurve:AddPoint(1, 100)
	end
	return percentCurve
end

--[[
Threat stages: low, medium, high and aggro, in the theme's threat colours.
`by` is what decides the stage, natively for secret values:
  "percent"  the scaled threat % (UnitDetailedThreatSituation): from 0, 50,
             80 and 100 (aggro)
  "status"   the threat situation (UnitThreatSituation): 0, 1, 2 and 3
Stages before `showFrom` are transparent (glows); nil shows every stage.
Rebuilt after theme changes.
]]
Colors.THREAT_STAGES = { "low", "medium", "high", "aggro" }
local THREAT_STAGE_COLORS = { low = "threatLow", medium = "threatMedium", high = "threatHigh", aggro = "threatAggro" }
local THREAT_STAGE_FROM = { percent = { 0, 50, 80, 100 }, status = { 0, 1, 2, 3 } }

local threatStageCurves, threatStageRevision = {}, nil
function Colors.ThreatStageCurve(by, showFrom)
	if threatStageRevision ~= ns.Config.themeRevision then
		threatStageRevision, threatStageCurves = ns.Config.themeRevision, {}
	end
	local key = by .. ":" .. tostring(showFrom)
	local curve = threatStageCurves[key]
	if curve then return curve end
	curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)
	local shown = showFrom == nil
	for i, stage in ipairs(Colors.THREAT_STAGES) do
		shown = shown or stage == showFrom
		local r, g, b = Colors.Theme(THREAT_STAGE_COLORS[stage])
		curve:AddPoint(THREAT_STAGE_FROM[by][i], CreateColor(r, g, b, shown and 1 or 0))
	end
	threatStageCurves[key] = curve
	return curve
end

-- Threat status (UnitThreatSituation, 0..3, may be secret) as a colour:
-- transparent without threat, orange to red towards secure tanking.
local threatCurve
function Colors.ThreatCurve()
	if not threatCurve then
		threatCurve = C_CurveUtil.CreateColorCurve()
		threatCurve:AddPoint(0, CreateColor(1, 0, 0, 0))
		threatCurve:AddPoint(1, CreateColor(1, 0.6, 0, 0.4))
		threatCurve:AddPoint(2, CreateColor(1, 0.3, 0, 0.8))
		threatCurve:AddPoint(3, CreateColor(1, 0, 0, 1))
	end
	return threatCurve
end
