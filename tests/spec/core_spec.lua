local Helpers = require("helpers")

describe("Util", function()
	local Util
	before_each(function()
		Util = Helpers.LoadAddon().Util
	end)

	it("gets, sets and clears dot paths", function()
		local t = {}
		Util.SetPath(t, "a.b.c", 1)
		assert.equals(1, Util.GetPath(t, "a.b.c"))
		assert.is_nil(Util.GetPath(t, "a.x.c"))
		Util.ClearPath(t, "a.b.c")
		assert.same({}, t, "empty parent tables are pruned")
	end)

	it("keeps non-empty parents when clearing", function()
		local t = { a = { b = 1, c = 2 } }
		Util.ClearPath(t, "a.b")
		assert.same({ a = { c = 2 } }, t)
	end)

	it("deep copies and merges", function()
		local source = { a = { 1, 2 }, b = { c = true } }
		local copy = Util.Copy(source)
		copy.a[1] = 9
		assert.equals(1, source.a[1])
		local merged = Util.Merge({ b = { d = 1 }, e = 1 }, source)
		assert.same({ a = { 1, 2 }, b = { c = true, d = 1 }, e = 1 }, merged)
	end)

	it("compares tables deeply", function()
		assert.is_true(Util.Equals({ 1, { 2 } }, { 1, { 2 } }))
		assert.is_false(Util.Equals({ 1, 2 }, { 1, 2, 3 }))
		assert.is_true(Util.Equals("a", "a"))
	end)

	it("recognises secret values", function()
		assert.is_true(Util.IsSecret(Secret(5)))
		assert.is_false(Util.IsSecret(5))
	end)
end)

describe("Schema", function()
	local Schema
	local schema = {
		{ key = "size", type = "range", min = 1, max = 10, default = 4 },
		{ key = "texture", type = "statusbar", inherit = "barTexture", default = "Fallback" },
		{ key = "mode", type = "select", values = { { "a", "A" }, { "b", "B" } }, default = "a" },
		{ key = "border", type = "group", defaults = { enabled = false }, schema = {
			{ key = "enabled", type = "toggle", default = true },
			{ key = "color", type = "color", inherit = "borderColor", default = { 1, 1, 1, 1 } },
		} },
	}

	before_each(function()
		Schema = Helpers.LoadAddon().Schema
	end)

	it("builds static defaults including group overrides", function()
		assert.same({
			size = 4,
			texture = "Fallback",
			mode = "a",
			border = { enabled = false, color = { 1, 1, 1, 1 } },
		}, Schema.Defaults(schema))
	end)

	it("resolves config > group defaults > theme > default", function()
		local theme = { barTexture = "ThemeBar", borderColor = { 0.5, 0.5, 0.5, 1 } }
		local resolved = Schema.Resolve(schema, { size = 7, border = { enabled = true } }, theme)
		assert.equals(7, resolved.size, "config wins")
		assert.equals("ThemeBar", resolved.texture, "theme fills unset inherit options")
		assert.is_true(resolved.border.enabled, "config beats group defaults")
		assert.same({ 0.5, 0.5, 0.5, 1 }, resolved.border.color)

		local plain = Schema.Resolve(schema, {}, nil)
		assert.equals("Fallback", plain.texture, "default without a theme")
		assert.is_false(plain.border.enabled, "group default override")
	end)

	it("keeps false values from config", function()
		local resolved = Schema.Resolve(schema, { border = { enabled = false } }, nil)
		assert.is_false(resolved.border.enabled)
	end)

	it("returns copies so callers can't change defaults", function()
		local resolved = Schema.Resolve(schema, {}, nil)
		resolved.border.color[1] = 0
		assert.equals(1, Schema.Resolve(schema, {}, nil).border.color[1])
	end)

	it("validates types, ranges and choices", function()
		assert.same({}, Schema.Validate(schema, { size = 5, mode = "b" }))
		local errors = Schema.Validate(schema, { size = 50, mode = "z", texture = 3, border = { enabled = "yes" } })
		assert.equals(4, #errors)
	end)

	it("finds descriptors by path", function()
		assert.equals("color", Schema.Find(schema, "border.color").type)
		assert.is_nil(Schema.Find(schema, "border.nope"))
	end)
end)

describe("Config", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true)
	end)

	it("creates the profile with theme defaults", function()
		assert.equals("Blizzard", ns.Config:GetTheme().barTexture)
		assert.is_not_nil(UnitFramesDB)
	end)

	it("reports only values that differ from the default as overrides", function()
		assert.is_nil(ns.Config:GetThemeOverride("barTexture"))
		ns.Config:SetThemeValue("barTexture", "Solid")
		assert.equals("Solid", ns.Config:GetThemeOverride("barTexture"))
		ns.Config:SetThemeValue("barTexture", nil)
		assert.equals("Blizzard", ns.Config:GetTheme().barTexture, "nil resets to the default")
		assert.is_nil(ns.Config:GetThemeOverride("barTexture"))
	end)

	it("fires ThemeChanged", function()
		local fired
		ns.Events.RegisterCallback({}, "ThemeChanged", function(_, path)
			fired = path
		end)
		ns.Config:SetThemeValue("colors.health", { 0, 1, 0, 1 })
		assert.equals("colors.health", fired)
	end)
end)
