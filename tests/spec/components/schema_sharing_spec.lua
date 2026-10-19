local Helpers = require("helpers")

describe("Immutable definition schemas", function()
	it("shares structural schemas while keeping configuration and resolution independent", function()
		local UF = Helpers.LoadAddon(true)
		local a = UF.Units:CreateFrame("pet", UIParent)
		local b = UF.Units:CreateFrame("pet", UIParent)
		assert.equals(a:GetSchema(), b:GetSchema())
		assert.equals(a:GetRow("health"):GetSchema(), b:GetRow("health"):GetSchema())
		assert.equals(a:GetRow("health"):GetText("left"):GetSchema(), b:GetRow("health"):GetText("right"):GetSchema())
		local before = UF.Util.Copy(a:GetSchema())
		a:Apply({ health = { bar = { color = { 1, 0, 0, 1 } } } })
		a.resolved.health.bar.color[1] = 0.3
		assert.is_true(a.resolved ~= b.resolved)
		assert.same(before, a:GetSchema())
		assert.same(before, b:GetSchema())
		local derived = UF.Units:Derive("pet", { rows = { health = { defaults = { height = 35 } } } })
		local c = UF.Units:CreateFromDefinition(derived, UIParent)
		assert.is_true(c:GetSchema() ~= a:GetSchema())
		assert.equals(35, c.resolved.health.height)
		local spec = UF.Units:GetSpec(derived)
		spec.portrait = nil
		local custom = UF.Components.UnitFrame:New(UIParent, {}, spec)
		assert.is_nil(UF.Schema.Find(custom:GetSchema(), "portrait"))
		assert.is_not_nil(UF.Schema.Find(c:GetSchema(), "portrait"))
	end)

	it("builds schemas from shared module descriptors without changing them", function()
		local UF = Helpers.LoadAddon(true)
		local C = UF.Components
		local modules = { C.Bar.schema, C.Backdrop.schema, C.Text.schema, C.AuraBar.schema }
		local before = UF.Util.Copy(modules)
		UF.Config:SetUnitValue("player", "castbar.bar.color", { 1, 0, 0, 1 })
		local uf = UF.Units:CreateFrame("player", UIParent)
		assert.equals(C.Backdrop.schema, UF.Schema.Find(uf:GetSchema(), "border").schema)
		assert.equals(C.Backdrop.schema, UF.Schema.Find(uf:GetPart("castbar"):GetSchema(), "border").schema)
		uf.resolved.border.color[1] = 0.25
		uf:GetPart("castbar").bar.resolved.color[2] = 0.75
		uf:GetRow("health").bar.resolved.color[3] = 0.5
		assert.same(before, modules)
	end)
end)
