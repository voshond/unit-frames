local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Component resolution reuse", function()
	local UF
	before_each(function() UF = Helpers.LoadAddon(true) end)

	local function Composition(schema, defaults, childSchema, config)
		local Child = UF.Component:Extend("ReuseChild")
		Child.schema = childSchema or UF.Util.Copy(schema)
		Child.OnCreate = function(self, parent) self.frame = CreateFrame("Frame", nil, parent) end
		local Parent = UF.Component:Extend("ReuseParent")
		Parent.schema = { { key = "child", type = "group", schema = schema, defaults = defaults } }
		Parent.OnCreate = function(self, parent)
			self.frame = CreateFrame("Frame", nil, parent)
			self.child = self:Own(Child:New(self.frame, self:ChildConfig("child")))
		end
		Parent.OnApply = function(self, cfg) self:ApplyChild(self.child, "child", cfg) end
		return Parent:New(UIParent, config or {})
	end

	local function Apply(parent, config)
		UF.Perf.counters = {}
		parent:Apply(config)
		local counters = UF.Perf.counters
		UF.Perf.counters = nil
		return counters
	end

	local function Equivalent(component)
		assert.same(UF.Schema.Resolve(component:GetSchema(), component.config, UF.Config:GetTheme()), component.resolved)
		for _, child in ipairs(component.children) do Equivalent(child) end
	end

	it("reuses an equivalent group while retaining raw overrides and scalar default precedence", function()
		local schema = {
			{ key = "enabled", type = "toggle", default = true },
			{ key = "size", type = "range", inherit = "fontSize", default = 5 },
			{ key = "font", type = "font", inherit = "font", default = "fallback" },
		}
		local config = { child = { enabled = false } }
		local before = UF.Util.Copy(config)
		local parent = Composition(schema, { size = 13 }, nil, config)
		local counters = Apply(parent)
		assert.equals(1, counters.resolveReuse)
		assert.equals(1, counters.resolveBuild)
		assert.equals(parent.resolved.child, parent.child.resolved)
		assert.is_false(parent.child.resolved.enabled)
		assert.equals(13, parent.child.resolved.size)
		assert.is_nil(parent.child.config.font)
		assert.same(before, config)
		Equivalent(parent)
		UF.Config:SetThemeValue("font", "Friz Quadrata TT")
		Equivalent(parent)
		assert.equals("Friz Quadrata TT", parent.child.resolved.font)
	end)

	it("preserves nested defaults, explicit false and independent copied colours", function()
		local schema = { { key = "inner", type = "group", defaults = { color = { 1, 0, 0, 1 }, enabled = false }, schema = {
			{ key = "color", type = "color", inherit = "colors.health", default = { 0, 1, 0, 1 } },
			{ key = "enabled", type = "toggle", default = true },
		} } }
		local config = { child = { inner = { color = { 0.2, 0.3, 0.4, 0.5 } } } }
		local before = UF.Util.Copy(config)
		local parent = Composition(schema, nil, nil, config)
		assert.equals(1, Apply(parent).resolveReuse)
		assert.is_false(parent.child.resolved.inner.enabled)
		assert.same(before, config)
		assert.is_true(parent.child.resolved.inner.color ~= config.child.inner.color)
		assert.is_true(parent.child.resolved.inner.color ~= schema[1].defaults.color)
		Equivalent(parent)
		Apply(parent, {})
		assert.same({ 1, 0, 0, 1 }, parent.child.resolved.inner.color)
		assert.same({ 0.2, 0.3, 0.4, 0.5 }, config.child.inner.color)
	end)

	it("falls back when outer table defaults change ChildConfig merge semantics", function()
		local schema = { { key = "color", type = "color", default = { 0, 1, 0, 1 } } }
		local parent = Composition(schema, { color = { 1, 0, 0, 1 } }, nil,
			{ child = { color = { 0.2, 0.3, 0.4 } } })
		local counters = Apply(parent)
		assert.is_nil(counters.resolveReuse)
		assert.equals(2, counters.resolveBuild)
		assert.same({ 0.2, 0.3, 0.4 }, parent.resolved.child.color)
		assert.same({ 0.2, 0.3, 0.4, 1 }, parent.child.resolved.color)
		Equivalent(parent)
	end)

	it("requires matching keys, types, inheritance and defaults rather than matching table shape", function()
		local schema = { { key = "value", type = "range", inherit = "fontSize", default = 5 } }
		for _, changes in ipairs({ { key = "other" }, { type = "select" }, { inherit = "font" }, { default = 9 } }) do
			local different = UF.Util.Copy(schema)
			for key, value in pairs(changes) do different[1][key] = value end
			local parent = Composition(schema, nil, different)
			assert.is_nil(Apply(parent).resolveReuse)
			Equivalent(parent)
			parent:Release()
		end
		local extra = UF.Util.Copy(schema)
		extra[2] = { key = "extra", type = "toggle", default = true }
		assert.is_nil(Apply(Composition(schema, nil, extra)).resolveReuse)
	end)

	it("rejects nested descriptor and group-default differences", function()
		local schema = { { key = "inner", type = "group", defaults = { value = 7 }, schema = {
			{ key = "value", type = "range", default = 2 },
		} } }
		for _, field in ipairs({ "schema", "defaults" }) do
			local different = UF.Util.Copy(schema)
			if field == "schema" then different[1].schema[1].default = 4
			else different[1].defaults.value = 11 end
			local parent = Composition(schema, nil, different)
			assert.is_nil(Apply(parent).resolveReuse)
			Equivalent(parent)
			parent:Release()
		end
	end)

	it("keeps fresh results across separate applies, instances and direct resolution calls", function()
		local schema = { { key = "color", type = "color", default = { 1, 0, 0, 1 } } }
		local first, second = Composition(schema), Composition(schema)
		assert.is_true(first.child.resolved ~= second.child.resolved)
		assert.is_true(first.child.resolved.color ~= second.child.resolved.color)
		local previous = first.child.resolved
		Apply(first)
		assert.is_true(previous ~= first.child.resolved)
		local a, b = UF.Schema.Resolve(schema), UF.Schema.Resolve(schema)
		a.color[1] = 0.4
		assert.equals(1, b.color[1])
		assert.is_nil(UF.Schema.ReuseGroup(first:GetSchema(), "child", first.child:GetSchema(), first.resolved))
		first.child:Apply({ color = { 0, 0, 1, 1 } })
		assert.equals(1, first.resolved.child.color[1])
	end)

	it("resolves the latest config and theme after combat rather than retaining a reused result", function()
		local parent = Composition({ { key = "size", type = "range", inherit = "fontSize", default = 5 } })
		parent:SetCombatDeferred(true)
		Mock.inCombat = true
		parent:Apply({ child = { size = 15 } })
		parent:Apply({ child = { size = 17 } })
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(17, parent.child.resolved.size)
		parent:Apply({})
		UF.Config:SetThemeValue("fontSize", 14)
		assert.equals(14, parent.child.resolved.size)
		Equivalent(parent)
	end)

	it("closes an implicit apply scope after errors and does not reuse mutable config across applies", function()
		local parent = Composition({ { key = "value", type = "range", default = 5 } })
		local apply = parent.child.OnApply
		parent.child.OnApply = function() error("reuse failure", 0) end
		assert.is_false(pcall(parent.Apply, parent))
		parent.child.OnApply = apply
		parent.config.child = { value = 23 }
		parent:Apply()
		assert.equals(23, parent.child.resolved.value)
		assert.is_nil(UF.Schema.ReuseGroup(parent:GetSchema(), "child", parent.child:GetSchema(), parent.resolved))
		Equivalent(parent)
	end)

	it("matches ordinary resolution throughout real and derived unit compositions", function()
		for _, unit in ipairs(UF.Units.order) do
			local frame = UF.Units:CreateFrame(unit, UIParent)
			local before = UF.Util.Copy(frame:GetSchema())
			Apply(frame, { health = { right = { size = 11 }, bar = { segments = { absorb = { enabled = false } } } } })
			Equivalent(frame)
			assert.same(before, frame:GetSchema())
			frame:Release()
		end
		local derived = UF.Units:Derive("pet", { rows = { health = { defaults = { right = { size = 13 } } } } })
		local frame = UF.Units:CreateFromDefinition(derived, UIParent)
		Equivalent(frame)
		assert.equals(13, frame:GetRow("health"):GetText("right").resolved.size)
		frame:Release()
	end)

	it("reduces builds and descriptor traversal without skipping presentation or binding work", function()
		local CG
		UF, CG = Helpers.LoadClickGrid()
		local reuse = UF.Schema.ReuseGroup
		local function Measure(operation, enabled)
			UF.Schema.ReuseGroup = enabled and reuse or function() end
			UF.Perf.counters = {}
			operation()
			local counters = UF.Perf.counters
			UF.Perf.counters = nil
			UF.Schema.ReuseGroup = reuse
			return counters
		end
		for _, operation in ipairs({
			function() for _, unit in ipairs(UF.Units.order) do UF.Units:Refresh(unit) end end,
			function() CG:Refresh() end,
		}) do
			local ordinary = Measure(operation, false)
			local reused = Measure(operation, true)
			assert.is_true(reused.resolveBuild < ordinary.resolveBuild)
			assert.is_true(reused.resolveOptions < ordinary.resolveOptions)
			assert.is_true(reused.resolveReuse > 0)
			assert.equals(ordinary.resolveCall, reused.resolveCall)
			for _, key in ipairs({ "rootApply", "childApply", "unitBind", "updateAllElements" }) do
				assert.equals(ordinary[key], reused[key])
			end
			for _, unit in ipairs(UF.Units.order) do Equivalent(UF.Units.frames[unit].uf) end
			for _, frame in ipairs(CG.frames) do Equivalent(frame.uf) end
		end
	end)
end)
