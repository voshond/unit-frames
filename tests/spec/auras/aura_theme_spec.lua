local Helpers = require("helpers")

describe("Global aura icon settings", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
	end)

	local function Resolved(unit)
		return ns.Config:UnitStore(unit):Resolved().auras
	end

	it("lets every frame follow the shared aura icon look unless it sets its own", function()
		ns.Config:SetThemeValue("auras.countSize", 14)
		ns.Config:SetThemeValue("auras.border.size", 5)
		ns.Config:SetThemeValue("auras.dispelGlow.enabled", true)
		local target = Resolved("target")
		assert.equals(14, target.countSize)
		assert.equals(5, target.border.size)
		assert.is_true(target.dispelGlow.enabled)
		assert.equals("Shared appearance", (ns.Config:UnitStore("target"):Target().source("auras.countSize")))

		ns.Config:SetUnitValue("target", "auras.countSize", 12)
		assert.equals(12, Resolved("target").countSize)
		assert.equals(8, Resolved("pet").countSize, "a frame's own default stays ahead of the shared value")
		assert.equals(5, Resolved("pet").border.size)
	end)

	it("keeps the built-in aura look and its links to the global border and font", function()
		local target = Resolved("target")
		assert.equals(8, target.border.size)
		assert.equals("None", target.border.background)
		assert.equals(10, target.durationSize)

		ns.Config:SetThemeValue("borderSize", 20)
		ns.Config:SetThemeValue("borderTexture", "Global Border")
		ns.Config:SetThemeValue("font", "Global Font")
		target = Resolved("target")
		assert.equals(8, target.border.size)
		assert.equals("Global Border", target.border.border)
		assert.equals("Global Font", ns.Schema.Resolve(ns.AuraIcon.schema, nil, ns.Config:GetTheme()).font)
		assert.is_nil(ns.Schema.Find(ns.Theme.schema, "auras.font"))
		assert.is_nil(ns.Schema.Find(ns.Theme.schema, "auras.border.border"))
	end)

	it("keeps inside-only time positions on embedded and priority icons", function()
		ns.Config:SetThemeValue("auras.durationPosition", "below")
		assert.equals("BOTTOM", ns.Schema.Resolve(ns.Components.AuraBar.schema, nil, ns.Config:GetTheme()).durationPosition)
		assert.equals("below", Resolved("target").durationPosition)
	end)

	it("restyles live aura icons when the shared value changes", function()
		local uf = ns.Units:CreateFromDefinition(ns.Units:GetDefinition("target"), UIParent,
			{ portrait = { enabled = false }, castbar = { placement = "off" }, auras = { enabled = true } })
		local part = uf:GetPart("auras")
		part:SetUnit("target")
		uf:Apply(uf.config)
		local button = part:GetContainer("buffs"):GetAuraGroupFrame("buffs", 1)
		assert.equals(10, button.ufCount.__state.font[2])
		ns.Config:SetThemeValue("auras.countSize", 16)
		uf:Apply(uf.config)
		assert.equals(16, button.ufCount.__state.font[2])
	end)
end)
