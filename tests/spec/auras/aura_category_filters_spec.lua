local Helpers = require("helpers")
local Mock = require("mock.wow")

describe("Category aura filters", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
	end)

	local function Values(list)
		local out = {}
		for _, entry in ipairs(list) do out[entry[1]] = true end
		return out
	end

	it("offers only filter strings native containers accept", function()
		local Auras = ns.Components.Auras
		local known = Mock.API.Snapshot().lua.auraFilters
		for _, list in ipairs({ Auras.BUFF_FILTERS, Auras.DEBUFF_FILTERS }) do
			for filter in pairs(Values(list)) do
				for component in filter:gmatch("[^|]+") do
					assert.is_true(known[component] == true, filter)
				end
			end
		end
		assert.is_true(Values(Auras.BUFF_FILTERS)["HELPFUL|PLAYER|RAID_IN_COMBAT"])
		assert.is_true(Values(Auras.BUFF_FILTERS)["HELPFUL|BIG_DEFENSIVE"])
		assert.is_true(Values(Auras.BUFF_FILTERS)["HELPFUL|EXTERNAL_DEFENSIVE"])
		assert.is_true(Values(Auras.BUFF_FILTERS)["HELPFUL|IMPORTANT"])
		assert.is_true(Values(Auras.DEBUFF_FILTERS)["HARMFUL|CROWD_CONTROL"])
	end)

	it("rejects unknown filter components like the native container", function()
		local container = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
		local options = { initializeFrame = function() end }
		assert.has_error(function() container:AddAuraGroup("buffs", "HELPFUL|BIG_DEFENSIVES", options) end)
		assert.has_error(function() container:AddAuraSlot("cc", "HARMFUL|!", options) end)
		container:AddAuraSlot("cc", "HARMFUL|CROWD_CONTROL", options)
		container:SetAuraSlotFilterString("cc", "HELPFUL|!PLAYER")
		assert.has_error(function() container:SetAuraSlotFilterString("cc", "HELPFUL|STUN") end)
	end)

	it("passes category filters to live containers", function()
		local uf = ns.Units:CreateFromDefinition(ns.Units:GetDefinition("target"), UIParent, {})
		uf:Apply({ auras = { buffs = { filter = "HELPFUL|BIG_DEFENSIVE" }, debuffs = { filter = "HARMFUL|CROWD_CONTROL" } } })
		local auras = uf:GetPart("auras")
		assert.equals("HELPFUL|BIG_DEFENSIVE", auras:GetContainer("buffs").__state.groups.buffs.filter)
		assert.equals("HARMFUL|CROWD_CONTROL", auras:GetContainer("debuffs").__state.groups.debuffs.filter)
	end)

	it("matches sample auras by their category flags", function()
		local Auras = ns.Components.Auras
		local function Icons(kind, filter)
			local out = {}
			for _, aura in ipairs(ns.Units.SAMPLE[kind]) do
				if Auras.MatchesSampleFilter(aura, filter, 0) then out[#out + 1] = aura.icon:match("([^\\]+)$") end
			end
			return out
		end
		assert.same({ "Spell_Holy_Renew", "Spell_Nature_LifeBloom" }, Icons("buffs", "HELPFUL|PLAYER|RAID_IN_COMBAT"))
		assert.same({ "Spell_Holy_DivineIntervention" }, Icons("buffs", "HELPFUL|BIG_DEFENSIVE"))
		assert.same({ "Spell_Holy_SealOfProtection" }, Icons("buffs", "HELPFUL|EXTERNAL_DEFENSIVE"))
		assert.same({ "Spell_Holy_DivineIntervention" }, Icons("buffs", "HELPFUL|IMPORTANT"))
		assert.same({ "Ability_Gouge" }, Icons("debuffs", "HARMFUL|CROWD_CONTROL"))
		assert.equals(4, #Icons("debuffs", "HARMFUL|RAID"))
		assert.equals(6, #Icons("buffs", "HELPFUL|PLAYER"))
	end)

	it("previews a category filter in the Workbench sample", function()
		local preview = ns.Units:CreateFrame("target", CreateFrame("Frame"))
		preview:Apply({ auras = { debuffs = { filter = "HARMFUL|CROWD_CONTROL" } } })
		ns.Units:ShowSample(preview, ns.Units.SAMPLE)
		local elements = preview:GetPart("auras").previewContainers.debuffs.ufElements
		assert.equals(1, #elements)
		assert.equals([[Interface\Icons\Ability_Gouge]], elements[1].ufIcon:GetTexture())
	end)
end)
