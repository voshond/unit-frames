local Helpers = require("helpers")

local MAGIC = { 0.21, 0.32, 0.43, 0.54 }

local function Registered(button)
	local glow, other = {}, 0
	local textures = {}
	for _, texture in ipairs(button.ufGlow.textures) do textures[texture] = true end
	for texture, options in pairs(button.__state.dispelTextures) do
		if textures[texture] then glow[#glow + 1] = options else other = other + 1 end
	end
	return glow, other
end

local function AddCalls(button)
	local count = 0
	local add = button.AddDispelTypeTexture
	button.AddDispelTypeTexture = function(...)
		count = count + 1
		return add(...)
	end
	return function() return count end
end

describe("Native debuff glow #glow", function()
	local ns, auras, container

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		ns.Config:SetUnitValue("player", "auras", {
			dispelBorder = true,
			dispelColors = { Magic = MAGIC },
			border = { enabled = true, border = "UnitFrames Pixel" },
		})
		auras = ns.Units.frames.player.uf:GetPart("auras")
		container = auras:GetContainer("debuffs")
	end)

	local function Button(index)
		return container:GetAuraGroupFrame("debuffs", index or 1)
	end

	it("stays off by default and registers nothing", function()
		local button = Button()
		local glow, other = Registered(button)
		assert.equals(0, #glow)
		assert.equals(8, other)
		assert.is_false(button.ufGlow:IsShown())
	end)

	it("registers Blizzard's eight glow border pieces with the shared dispel curve, typed debuffs only", function()
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", true)
		local button = Button()
		local glow = Registered(button)
		assert.equals(8, #glow)
		local curve = ns.AuraIcon.DispelCurve(auras.dispelColors)
		for _, options in ipairs(glow) do
			assert.equals(Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset, options.style)
			assert.is_true(options.showWhenHarmful)
			assert.is_false(options.showWhenHelpful)
			assert.is_false(options.showWithoutDispelType)
			assert.equals(curve, options.customDispelColorCurve)
		end
		for _, texture in ipairs(button.ufGlow.textures) do
			assert.is_true(texture:GetTexture():find("Interface\\Common\\GlowBorder-", 1, true) == 1)
			assert.equals("ADD", texture.__state.blendMode)
		end
		assert.is_true(button.ufGlow:IsShown())
		assert.is_false(auras:GetContainer("buffs"):GetAuraGroupFrame("buffs", 1).ufGlow:IsShown())

		button:MockUpdateDispelTextures("Magic")
		for _, texture in ipairs(button.ufGlow.textures) do
			assert.is_true(texture:IsShown())
			assert.same(MAGIC, texture.__state.vertexColor)
		end
		button:MockUpdateDispelTextures("None")
		for _, texture in ipairs(button.ufGlow.textures) do assert.is_false(texture:IsShown()) end
		for _, texture in ipairs(button.ufDispelTextures) do assert.is_true(texture:IsShown()) end
	end)

	it("keeps registrations through geometry restyles and renews them for colours and toggles", function()
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", true)
		local button = Button()
		local adds = AddCalls(button)
		ns.Config:SetUnitValue("player", "auras.dispelGlow.size", 20)
		ns.Config:SetUnitValue("player", "auras.dispelGlow.opacity", 0.5)
		ns.Config:SetUnitValue("player", "auras.dispelGlow.additive", false)
		assert.equals(0, adds())
		assert.equals(0.5, button.ufGlow:GetAlpha())
		assert.equals("BLEND", button.ufGlow.textures[1].__state.blendMode)

		ns.Config:SetUnitValue("player", "auras.dispelColors.Magic", { 1, 0, 1, 1 })
		assert.equals(8, #Registered(button))
		assert.is_true(adds() >= 8)

		-- Any toggle order, including with the border off.
		for _, path in ipairs({ "auras.dispelBorder", "auras.border.enabled" }) do
			ns.Config:SetUnitValue("player", path, false)
			assert.equals(8, #Registered(button), path)
		end
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", false)
		assert.same({}, button.__state.dispelTextures)
		assert.is_false(button.ufGlow:IsShown())
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", true)
		assert.equals(8, #Registered(button))
		assert.is_true(button.ufGlow:IsShown())
	end)

	it("clamps the corners to the configured icon size", function()
		ns.Config:SetUnitValue("player", "auras.debuffs.size", 20)
		ns.Config:SetUnitValue("player", "auras.dispelGlow", { enabled = true, size = 32, offset = 4 })
		local corner = Button().ufGlow.TopLeft
		assert.equals(14, corner:GetWidth())
		assert.same({ "TOPLEFT", Button().ufGlow, "TOPLEFT", -4, 4 }, { corner:GetPoint() })
	end)

	it("matches sample glow to the live type colour and leaves untyped samples unlit", function()
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", true)
		auras:ShowSample({ debuffs = { { icon = "sample", dispelName = "Magic" }, { icon = "sample" } } })
		local typed, untyped = auras.previewContainers.debuffs.ufElements[1], auras.previewContainers.debuffs.ufElements[2]
		assert.is_true(typed.ufGlow:IsShown())
		for index, texture in ipairs(typed.ufGlow.textures) do
			assert.is_true(texture:IsShown())
			assert.same(MAGIC, texture.__state.vertexColor)
			assert.equals(Button().ufGlow.textures[index]:GetTexture(), texture:GetTexture())
		end
		for _, texture in ipairs(untyped.ufGlow.textures) do assert.is_false(texture:IsShown()) end
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", false)
		assert.is_false(typed.ufGlow:IsShown())
	end)
end)
