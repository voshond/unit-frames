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

return {
	{ name = "player", build = UnitFrame("player") },
	{ name = "player-idle", build = UnitFrame("player", { showCast = false }) },
	{ name = "player-overheal", build = UnitFrame("player", { health = 22000, heal = 7000, showCast = false }, EnableOverheal) },
	{ name = "target", build = UnitFrame("target") },
	{ name = "target-35pct", build = UnitFrame("target", { health = 8400, showCast = false }) },
	{ name = "targettarget", build = UnitFrame("targettarget") },
	{ name = "focus", build = UnitFrame("focus") },
	{ name = "focustarget", build = UnitFrame("focustarget") },
	{ name = "pet", build = UnitFrame("pet") },
}
