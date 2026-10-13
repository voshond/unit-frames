local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Component ownership", function()
	it("applies each child once per theme refresh and cancels deferred work on release", function()
		local ns = Helpers.LoadAddon(true)
		local uf = ns.Units:CreateFrame("player", UIParent)
		local counts, released = {}, {}
		local function Watch(component)
			local apply, release = component.OnApply, component.OnRelease
			component.OnApply = function(self, cfg)
				counts[self] = (counts[self] or 0) + 1
				apply(self, cfg)
			end
			component.OnRelease = function(self)
				released[self] = (released[self] or 0) + 1
				release(self)
			end
			counts[component] = 0
			for _, child in ipairs(component.children) do Watch(child) end
		end
		Watch(uf)
		ns.Config:SetThemeValue("barTexture", "Solid")
		for _, count in pairs(counts) do assert.equals(1, count) end
		uf:SetCombatDeferred(true)
		local function Deferred(component)
			assert.is_true(component.deferInCombat)
			for _, child in ipairs(component.children) do Deferred(child) end
		end
		Deferred(uf)
		Mock.inCombat = true
		uf:Apply()
		uf:Release()
		uf:Release()
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		ns.Config:SetThemeValue("fontSize", 14)
		for component, count in pairs(counts) do
			assert.equals(1, count)
			assert.equals(1, released[component])
		end
	end)

	it("leaves standalone components refreshable and lets runtime owners refresh their composition", function()
		local ns = Helpers.LoadAddon(true, true)
		local standalone = ns.Components.Bar:New(UIParent, {})
		local root = ns.Units.frames.player.uf
		local original, count = root.OnApply, 0
		root.OnApply = function(self, cfg) count = count + 1; original(self, cfg) end
		ns.Config:SetThemeValue("barTexture", "Solid")
		assert.equals(1, count)
		assert.equals([[Interface\Buttons\WHITE8X8]], standalone:GetStatusBar().__state.texture)
		assert.equals([[Interface\Buttons\WHITE8X8]], root:GetRow("health"):GetBar():GetStatusBar().__state.texture)
	end)
end)
