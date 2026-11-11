local Helpers = require("helpers")
local Mock = Helpers.Mock

local function UnitFrame(unit, overrides, configure)
	return function()
		local ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		if configure then configure(ns) end
		local frame = ns.Units.frames[unit]
		frame:Show()
		local values = ns.Units:GetSample(unit)
		for key, value in pairs(overrides or {}) do values[key] = value end
		ns.Units:ShowSample(frame.uf, values)
		return frame
	end
end

local function EnableOverheal(ns)
	ns.Config:SetUnitValue("player", "health.bar.overheal.enabled", true)
end

local function TooltipBorder(ns)
	ns.Config:SetUnitValue("player", "border.enabled", true)
	ns.Config:SetUnitValue("player", "border.border", "Blizzard Tooltip")
end

local function NoBorder(ns)
	ns.Config:SetUnitValue("player", "border.enabled", false)
end

local function Enable(unit, keys)
	return function(ns)
		for _, key in ipairs(keys) do ns.Config:SetUnitValue(unit, key .. ".enabled", true) end
	end
end

local function ThickAuraBorder(ns)
	ns.Config:SetUnitValue("target", "auras.border", { enabled = true, border = "Blizzard Tooltip", size = 10, padding = 2 })
end

local function WideAuras(ns)
	for _, kind in ipairs({ "buffs", "debuffs" }) do
		ns.Config:SetUnitValue("target", "auras." .. kind .. ".size", 32)
		ns.Config:SetUnitValue("target", "auras." .. kind .. ".separateHeight", true)
		ns.Config:SetUnitValue("target", "auras." .. kind .. ".height", 18)
	end
end

local function AuraTextAnchors(ns)
	ns.Config:SetUnitValue("target", "auras.durationPosition", "BOTTOMRIGHT")
	ns.Config:SetUnitValue("target", "auras.countPosition", "TOPLEFT")
	for _, kind in ipairs({ "buffs", "debuffs" }) do ns.Config:SetUnitValue("target", "auras." .. kind .. ".size", 30) end
end

return {
	{ name = "player", build = UnitFrame("player") },
	{ name = "player-idle", build = UnitFrame("player", { showCast = false }) },
	{ name = "player-tooltip-border", build = UnitFrame("player", { showCast = false }, TooltipBorder) },
	{ name = "player-no-border", build = UnitFrame("player", { showCast = false }, NoBorder) },
	{ name = "player-dead", build = UnitFrame("player", { status = "dead", showCast = false }) },
	{ name = "player-overheal", build = UnitFrame("player", { health = 22000, heal = 7000, showCast = false }, EnableOverheal) },
	{ name = "target", build = UnitFrame("target") },
	{ name = "target-35pct", build = UnitFrame("target", { health = 8400, showCast = false }) },
	{ name = "target-aura-border", build = UnitFrame("target", { showCast = false }, ThickAuraBorder) },
	{ name = "target-aura-text-anchors", build = UnitFrame("target", { showCast = false }, AuraTextAnchors) },
	{ name = "target-aura-wide", build = UnitFrame("target", { showCast = false }, WideAuras) },
	{ name = "targettarget", build = UnitFrame("targettarget") },
	{ name = "focus", build = UnitFrame("focus") },
	{ name = "focus-portrait", build = UnitFrame("focus", { showCast = false }, Enable("focus", { "portrait" })) },
	{ name = "focustarget", build = UnitFrame("focustarget") },
	{ name = "pet", build = UnitFrame("pet") },
	{ name = "pet-portrait", build = UnitFrame("pet", nil, Enable("pet", { "health", "power", "portrait" })) },
}
