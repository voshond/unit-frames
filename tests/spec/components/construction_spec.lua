local Helpers = require("helpers")

describe("Component construction", function()
	it("applies every component of a new unit frame once, fully initialized when New returns", function()
		local UF = Helpers.LoadAddon(true)
		local counts, applying = {}, {}
		for _, class in pairs(UF.Components) do
			local apply = rawget(class, "OnApply")
			if apply then
				class.OnApply = function(self, cfg)
					if applying[self] then return apply(self, cfg) end
					counts[self], applying[self] = (counts[self] or 0) + 1, true
					apply(self, cfg)
					applying[self] = nil
				end
			end
		end
		local uf = UF.Units:CreateFrame("player", UIParent)
		local visited = 0
		local function Check(component)
			visited = visited + 1
			assert.is_not_nil(component.resolved)
			assert.is_true((counts[component] or 1) <= 1, component.className .. " applied more than once")
			for _, child in ipairs(component.children) do Check(child) end
		end
		Check(uf)
		assert.is_true(visited > 20)
		uf:Apply()
		for component, count in pairs(counts) do assert.is_true(count <= 2, component.className) end
	end)

	it("applies components the creating parent does not reach and unwinds after OnCreate errors", function()
		local UF = Helpers.LoadAddon(true)
		local Child = UF.Component:Extend("ConstructionChild")
		Child.schema = { { key = "size", type = "range", min = 1, max = 10, step = 1, default = 4 } }
		Child.applies = 0
		function Child:OnCreate(parent) self.frame = CreateFrame("Frame", nil, parent) end
		function Child:OnApply() Child.applies = Child.applies + 1 end
		local Parent = UF.Component:Extend("ConstructionParent")
		function Parent:OnCreate(parent)
			self.frame = CreateFrame("Frame", nil, parent)
			self.child = self:Own(Child:New(self.frame, { size = 7 }))
			assert.is_nil(self.child.resolved, "joins the parent's construction")
		end
		local parent = Parent:New(UIParent)
		assert.equals(7, parent.child.resolved.size)
		assert.equals(1, Child.applies)
		local Broken = UF.Component:Extend("ConstructionBroken")
		function Broken:OnCreate(parent)
			self.frame = CreateFrame("Frame", nil, parent)
			Child:New(self.frame)
			error("create failed")
		end
		local ok, err = pcall(Broken.New, Broken, UIParent)
		assert.is_false(ok)
		assert.is_not_nil(tostring(err):find("create failed", 1, true))
		local standalone = Child:New(UIParent, { size = 2 })
		assert.equals(2, standalone.resolved.size, "later construction is not joined to the failed one")
	end)

	it("shares part schemas per definition, including the castbar's bar and texts", function()
		local UF = Helpers.LoadAddon(true)
		local a = UF.Units:CreateFrame("player", UIParent)
		local b = UF.Units:CreateFrame("player", UIParent)
		local castA, castB = a:GetPart("castbar"), b:GetPart("castbar")
		assert.equals(castA:GetSchema(), castB:GetSchema())
		assert.equals(castA.bar:GetSchema(), castB.bar:GetSchema())
		assert.equals(castA.nameText:GetSchema(), castB.timeText:GetSchema())
		assert.equals(a:GetPart("auraBar"):GetSchema(), b:GetPart("auraBar"):GetSchema())
		local derived = UF.Units:Derive("player", { castbar = { defaults = { height = 30 } } })
		local c = UF.Units:CreateFromDefinition(derived, UIParent)
		assert.is_true(c:GetPart("castbar"):GetSchema() ~= castA:GetSchema())
	end)

	it("keeps a castbar spark hidden when it is idled before its first apply", function()
		local UF = Helpers.LoadAddon(true)
		UF.Config:SetUnitValue("player", "castbar.bar.spark", true)
		local castbar = UF.Units:CreateFrame("player", UIParent):GetPart("castbar")
		assert.is_true(castbar.bar.resolved.spark)
		assert.is_false(castbar.bar.spark:IsShown())
		castbar.bar:SetSparkActive(true)
		assert.is_true(castbar.bar.spark:IsShown())
	end)
end)
