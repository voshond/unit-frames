local Helpers = require("helpers")

describe("Lazy live aura containers", function()
	local ns, uf
	local config = { portrait = { enabled = false }, castbar = { placement = "off" } }
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		uf = ns.Units:CreateFromDefinition(ns.Units:GetDefinition("target"), UIParent, config)
	end)

	it("builds no native containers or buttons for a part that was never enabled", function()
		local bar = uf:GetPart("auraBar")
		assert.is_false(bar:IsEnabled())
		assert.is_nil(bar:GetContainer("buffs"))
		assert.is_nil(bar.presence)
		bar:SetUnit("target")
		uf:Apply(config)
		assert.is_nil(bar:GetContainer("buffs"), "applies and unit changes keep it empty")
		assert.is_not_nil(uf:GetPart("auras"):GetContainer("buffs"), "enabled parts build theirs")
	end)

	it("builds configured, styled containers for the current unit once enabled", function()
		local bar = uf:GetPart("auraBar")
		bar:SetUnit("target")
		uf:Apply({ portrait = { enabled = false }, castbar = { placement = "off" },
			auraBar = { enabled = true, height = 16, buffs = { filter = "HELPFUL|RAID" } } })
		local buffs = bar:GetContainer("buffs")
		assert.is_true(buffs:IsEnabled())
		assert.equals("target", buffs:GetUnit())
		assert.equals("HELPFUL|RAID", buffs.__state.groups.buffs.filter)
		local button = buffs:GetAuraGroupFrame("buffs", 1)
		assert.equals(16, button:GetHeight())
		assert.equals(bar.styleToken, button.ufStyleToken)
		assert.is_not_nil(bar.presence, "the collapse probe comes with the row")
		assert.equals("target", bar.presence:GetUnit())
		uf:Apply(config)
		assert.equals(buffs, bar:GetContainer("buffs"), "kept once built")
		assert.is_false(buffs:IsEnabled())
	end)

	it("builds and configures containers when an owner enables the part directly", function()
		local bar = uf:GetPart("auraBar")
		bar:SetUnit("target")
		bar:SetEnabled(true)
		local debuffs = bar:GetContainer("debuffs")
		assert.is_true(debuffs:IsEnabled())
		assert.equals("target", debuffs:GetUnit())
		assert.equals(bar.resolved.debuffs.filter, debuffs.__state.groups.debuffs.filter)
		assert.equals(bar.styleToken, debuffs:GetAuraGroupFrame("debuffs", 1).ufStyleToken)
	end)

	it("hands rows, parts and their children their settings from the first apply", function()
		local first = {}
		for _, name in ipairs({ "TextBar", "Text", "Castbar" }) do
			local class = ns.Components[name]
			local apply = class.OnApply
			class.OnApply = function(self, cfg)
				if not first[self] then first[self] = ns.Util.Copy(cfg) end
				return apply(self, cfg)
			end
		end
		local made = ns.Units:CreateFromDefinition(ns.Units:GetDefinition("target"), UIParent, {
			power = { enabled = false, center = { size = 17 } },
			castbar = { placement = "bottom", name = { size = 13 } },
		})
		assert.is_false(first[made:GetRow("power")].enabled)
		assert.equals(17, first[made:GetRow("power").texts.center].size)
		assert.equals(13, first[made:GetPart("castbar").nameText].size)
	end)

	it("leaves the default grid's hidden parts empty", function()
		local _, CG = Helpers.LoadClickGrid()
		local cell = CG.headers.party:GetAttribute("child1")
		assert.is_not_nil(cell.Member.uf:GetPart("auras"):GetContainer("buffs"))
		for _, uf in ipairs({ cell.Member.uf, cell.Target.uf }) do
			assert.is_nil(uf:GetPart("auraBar"):GetContainer("buffs"))
		end
		assert.is_nil(cell.Target.uf:GetPart("auras"):GetContainer("buffs"))
	end)
end)
