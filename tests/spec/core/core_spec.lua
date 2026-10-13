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

	it("layers nested group defaults, outer over inner, without changing them", function()
		local nested = {
			{ key = "row", type = "group", defaults = { bar = { color = { 0, 0, 1 }, size = 5, mode = "x" } }, schema = {
				{ key = "bar", type = "group", defaults = { color = { 1, 0, 0, 1 }, size = 2, inner = { depth = 1 } }, schema = {
					{ key = "color", type = "color", default = { 1, 1, 1, 1 } },
					{ key = "size", type = "range", default = 1 },
					{ key = "mode", type = "select", default = "y" },
					{ key = "inner", type = "group", defaults = { depth = 3, on = true }, schema = {
						{ key = "depth", type = "range", default = 0 },
						{ key = "on", type = "toggle", default = false },
					} },
				} },
			} },
		}
		local Util = Helpers.LoadAddon().Util
		local before = Util.Copy(nested)
		local resolved = Schema.Resolve(nested, { row = { bar = { inner = { on = false } } } }, nil)
		assert.same({ color = { 0, 0, 1, 1 }, size = 5, mode = "x", inner = { depth = 1, on = false } }, resolved.row.bar)
		resolved.row.bar.color[1] = 9
		assert.same(before, nested, "schema defaults stay unchanged")
		assert.same({ 0, 0, 1, 1 }, Schema.Resolve(nested, nil, nil).row.bar.color)
	end)

	it("reads theme paths per theme table", function()
		local Util = Helpers.LoadAddon().Util
		assert.equals(1, Util.GetPath({ colors = { health = 1 } }, "colors.health"))
		assert.equals(2, Util.GetPath({ colors = { health = 2 } }, "colors.health"))
		assert.is_nil(Util.GetPath({ colors = 3 }, "colors.health"))
		assert.is_nil(Util.GetPath({}, "colors.health"))
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

	-- Listeners run in hash order: a refresh must not depend on another
	-- listener (e.g. a cache invalidation) having run first.
	it("gives ThemeChanged listeners a current health gradient in any order", function()
		local stale = ns.Colors.HealthCurve()
		local events = ns.Events.callbacks.events
		local others = events.ThemeChanged
		events.ThemeChanged = nil -- only the probe listens
		local seen = {}
		ns.Events.RegisterCallback({}, "ThemeChanged", function()
			seen[#seen + 1] = ns.Colors.HealthCurve()
		end)
		ns.Config:SetThemeValue("colors.health", { 0, 0, 1, 1 })
		ns.Config.db:SetProfile("Other")
		events.ThemeChanged = others

		assert.equals(2, #seen)
		assert.is_true(stale ~= seen[1], "rebuilt for the new colour")
		assert.same({ 0, 0, 1 }, { seen[1]:Evaluate(1):GetRGB() })
		assert.is_true(seen[1] ~= seen[2], "a profile change rebuilds it too")
		local r, g, b = seen[2]:Evaluate(1):GetRGB()
		assert.same({ 10, 80, 10 }, { math.floor(r * 100 + 0.5), math.floor(g * 100 + 0.5), math.floor(b * 100 + 0.5) },
			"the new profile's default health colour")
	end)
end)

describe("UnitFrames_Media", function()
	it("registers its fonts with LibSharedMedia for every font picker", function()
		local ns = Helpers.LoadAddon(true)
		Helpers.LoadToc("UnitFrames_Media/UnitFrames_Media.toc", "UnitFrames_Media")
		local fonts = {}
		for _, name in ipairs(ns.Media:List("font")) do
			fonts[name] = true
		end
		for _, name in ipairs({ "Roboto Condensed", "Roboto Condensed Light", "Roboto Condensed Medium", "Roboto Condensed Bold" }) do
			assert.is_true(fonts[name], name)
		end
		assert.equals([[Interface\AddOns\UnitFrames_Media\Fonts\RobotoCondensed-Medium.ttf]],
			ns.Media:Fetch("font", "Roboto Condensed Medium"))
	end)

	it("ships every font file it registers, with the licence", function()
		local ns = Helpers.LoadAddon(true)
		Helpers.LoadToc("UnitFrames_Media/UnitFrames_Media.toc", "UnitFrames_Media")
		local count = 0
		for _, path in pairs(ns.Media.LSM:HashTable("font")) do
			local file = path:match("^Interface\\AddOns\\UnitFrames_Media\\Fonts\\(.+)$")
			if file then
				count = count + 1
				assert.is_not_nil(io.open("UnitFrames_Media/Fonts/" .. file), file)
			end
		end
		assert.is_true(count >= 4, "Roboto Condensed: 4 weights")
		assert.is_not_nil(io.open("UnitFrames_Media/Fonts/RobotoCondensed-OFL.txt"))
	end)
end)

describe("Schema composition", function()
	local Schema
	before_each(function()
		Schema = Helpers.LoadAddon().Schema
	end)

	local function Keys(schema)
		local keys = {}
		for i, opt in ipairs(schema) do keys[i] = opt.key end
		return table.concat(keys, ",")
	end

	it("inserts, removes, joins and overrides without touching the inputs", function()
		local base = { { key = "enabled" }, { key = "color", inherit = "colors.health" }, { key = "size" } }
		assert.equals("enabled,a,b,color,size", Keys(Schema.Insert(base, "enabled", { { key = "a" }, { key = "b" } })))
		assert.equals("a,enabled,color,size", Keys(Schema.Insert(base, "missing", { { key = "a" } })))
		assert.equals("enabled,size", Keys(Schema.Without(base, { color = true })))
		assert.equals("enabled,color,size,x", Keys(Schema.Concat(base, { { key = "x" } })))
		local overridden = Schema.Override(base, "color", { inherit = "colors.cast" })
		assert.equals("colors.cast", overridden[2].inherit)
		assert.equals("colors.health", base[2].inherit)
		assert.equals(base[1], overridden[1])
		assert.equals("enabled,color,size", Keys(base))
	end)
end)
