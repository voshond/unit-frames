local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Live aura restyling", function()
	local ns, uf, styled
	local config = { portrait = { enabled = false }, castbar = { placement = "off" },
		auraBar = { enabled = true, height = 12 } }
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		uf = ns.Units:CreateFromDefinition(ns.Units:GetDefinition("target"), UIParent, config)
		styled = {}
		for _, key in ipairs({ "auras", "auraBar" }) do
			local part = uf:GetPart(key)
			part:SetUnit("target")
			local style = part.StyleButton
			part.StyleButton = function(self, button)
				styled[key] = (styled[key] or 0) + 1
				return style(self, button)
			end
		end
	end)

	local function Button(key)
		return uf:GetPart(key):GetContainer("buffs"):GetAuraGroupFrame("buffs", 1)
	end

	it("skips owned buttons when nothing they show changed", function()
		uf:Apply(config)
		assert.same({}, styled)
		uf:Apply(ns.Util.Copy(config))
		assert.same({}, styled, "equal settings in fresh tables")
	end)

	it("restyles every owned button when a setting, theme font or late media changes", function()
		uf:Apply({ portrait = { enabled = false }, castbar = { placement = "off" },
			auras = { durationSize = 14 }, auraBar = { enabled = true, height = 16 } })
		assert.is_true(styled.auras > 0 and styled.auraBar > 0)
		assert.equals(16, Button("auraBar"):GetHeight())
		assert.equals(14, Button("auras").ufTime.__state.font[2])

		styled = {}
		ns.Config:SetThemeValue("font", "Late Font")
		uf:Apply(uf.config)
		local before = styled.auras
		assert.is_true(before > 0, "theme font change")
		styled = {}
		LibStub("LibSharedMedia-3.0"):Register("font", "Late Font", "Fonts\\LATE.TTF")
		uf:Apply(uf.config)
		assert.equals(before, styled.auras, "a font registered later")
		assert.equals("Fonts\\LATE.TTF", Button("auras").ufTime.__state.font[1])
	end)

	it("restyles buttons a combat apply could not reach once combat ends", function()
		Mock.aurasSecret = true
		uf:Apply({ portrait = { enabled = false }, castbar = { placement = "off" },
			auraBar = { enabled = true, height = 16 } })
		assert.is_true(ns.AfterCombat:IsQueued(uf:GetPart("auraBar"), "restyle"))
		Mock.aurasSecret = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(16, Button("auraBar"):GetHeight())
		styled = {}
		uf:Apply(uf.config)
		assert.is_nil(styled.auraBar)
	end)
end)
