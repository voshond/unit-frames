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

-- Health gradient (low -> mid -> full) as a colour curve; use with
-- UnitHealthPercent(unit, true, curve) for secret health.
local healthCurve
function Colors.HealthCurve()
	if not healthCurve then
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

ns.Events.RegisterCallback(Colors, "ThemeChanged", function()
	healthCurve = nil
end)
