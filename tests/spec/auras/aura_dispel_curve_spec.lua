local Helpers = require("helpers")

local COLORS = {
	None = { 0.13, 0.24, 0.35, 0.46 },
	Magic = { 0.21, 0.32, 0.43, 0.54 },
	Curse = { 0.31, 0.42, 0.53, 0.64 },
	Disease = { 0.41, 0.52, 0.63, 0.74 },
	Poison = { 0.51, 0.62, 0.73, 0.84 },
}
local TYPES = { "None", "Magic", "Curse", "Disease", "Poison" }
local FALLBACK_TYPES = { "Bleed", "Enrage", "Stealth", "Invisibility", "All" }

local function AssertTint(button, expected)
	assert.equals(8, #button.ufDispelTextures)
	for _, texture in ipairs(button.ufDispelTextures) do
		assert.same(expected, texture.__state.vertexColor)
	end
end

local function RegisteredCurve(button)
	assert.equals(8, #button.ufDispelTextures)
	local curve, count = nil, 0
	for _ in pairs(button.__state.dispelTextures) do count = count + 1 end
	assert.equals(8, count)
	for _, texture in ipairs(button.ufDispelTextures) do
		local options = button.__state.dispelTextures[texture]
		assert.is_not_nil(options)
		assert.is_nil(options.customDispelColorMap)
		assert.is_not_nil(options.customDispelColorCurve)
		assert.equals(Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset, options.style)
		assert.is_true(options.showWhenHarmful)
		assert.is_false(options.showWhenHelpful)
		assert.is_true(options.showWithoutDispelType)

		curve = curve or options.customDispelColorCurve
		assert.equals(curve, options.customDispelColorCurve)
	end
	return curve
end

describe("Cached native aura dispel curves", function()
	local ns, auras, container

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		ns.Config:SetUnitValue("player", "auras", {
			dispelBorder = true,
			dispelColors = ns.Util.Copy(COLORS),
			border = { enabled = true, border = "UnitFrames Pixel" },
		})
		auras = ns.Units.frames.player.uf:GetPart("auras")
		container = auras:GetContainer("debuffs")
	end)

	local function Button(index)
		return container:GetAuraGroupFrame("debuffs", index or 1)
	end

	it("registers one shared native curve for all eight border pieces on every owned debuff button", function()
		local curve = RegisteredCurve(Button())
		assert.equals(Enum.LuaCurveType.Step, curve:GetType())
		local count = container:GetAuraGroupFrameCount("debuffs")
		assert.is_true(count > 1)
		for index = 1, count do
			assert.equals(curve, RegisteredCurve(Button(index)))
		end
	end)

	it("caches by palette identity without retaining discarded palette tables", function()
		local palette = auras.dispelColors
		local curve = ns.AuraIcon.DispelCurve(palette)
		assert.equals(curve, ns.AuraIcon.DispelCurve(palette))
		assert.equals(curve, RegisteredCurve(Button()))
		local other = {}
		for name, rgba in pairs(COLORS) do other[name] = CreateColor(unpack(rgba)) end
		local otherCurve = ns.AuraIcon.DispelCurve(other)
		assert.is_true(curve ~= otherCurve)
		assert.equals(otherCurve, ns.AuraIcon.DispelCurve(other))
		local weak = setmetatable({ other }, { __mode = "v" })
		other = nil
		collectgarbage("collect")
		collectgarbage("collect")
		assert.is_nil(weak[1])
		assert.same(COLORS.Magic, { otherCurve:Evaluate(1):GetRGBA() })
	end)

	it("uses step IDs for configured types and native fallback ranges beyond Poison", function()
		local curve = ns.AuraIcon.DispelCurve(auras.dispelColors)
		assert.equals(Enum.LuaCurveType.Step, curve:GetType())
		for index, name in ipairs(TYPES) do
			assert.same(COLORS[name], { curve:Evaluate(index - 1):GetRGBA() }, name)
			assert.same(COLORS[name], { curve:Evaluate(index - 0.5):GetRGBA() }, name)
		end
		local none = { AuraUtil.GetAuraBorderColor("None"):GetRGBA() }
		for id = 5, 10 do
			assert.same(none, { curve:Evaluate(id):GetRGBA() }, tostring(id))
		end
		assert.same({ AuraUtil.GetAuraBorderColor("Bleed"):GetRGBA() }, { curve:Evaluate(11):GetRGBA() })
		for _, id in ipairs({ 12, 13, 100 }) do
			assert.same(none, { curve:Evaluate(id):GetRGBA() }, tostring(id))
		end
	end)

	it("retains the curve for equal color settings and unrelated artwork restyles", function()
		local curve = RegisteredCurve(Button())
		local palette = auras.dispelColors
		for _, change in ipairs({
			{ "auras.dispelColors", ns.Util.Copy(COLORS) },
			{ "auras.durationSize", 14 },
			{ "auras.debuffs.size", 30 },
			{ "auras.border.size", 6 },
			{ "auras.border.color", { 0.9, 0.8, 0.7, 0.6 } },
		}) do
			ns.Config:SetUnitValue("player", change[1], change[2])
			assert.equals(palette, auras.dispelColors)
			assert.equals(curve, RegisteredCurve(Button()), change[1])
			AssertTint(Button(), COLORS.Magic)
		end
	end)

	it("replaces changed palettes without mutating old curves and immediately retints every live border", function()
		local oldPalette = auras.dispelColors
		local oldCurve = RegisteredCurve(Button())
		local changed = { 0.91, 0.82, 0.73, 0.27 }
		ns.Config:SetUnitValue("player", "auras.dispelColors.Magic", changed)
		local curve = RegisteredCurve(Button())
		assert.is_true(oldPalette ~= auras.dispelColors)
		assert.is_true(oldCurve ~= curve)
		assert.equals(oldCurve, ns.AuraIcon.DispelCurve(oldPalette))
		assert.same(changed, { curve:Evaluate(1):GetRGBA() })
		for index, name in ipairs(TYPES) do
			assert.same(COLORS[name], { oldCurve:Evaluate(index - 1):GetRGBA() }, name)
		end
		for index = 1, container:GetAuraGroupFrameCount("debuffs") do
			assert.equals(curve, RegisteredCurve(Button(index)))
			AssertTint(Button(index), changed)
		end
	end)

	it("preserves curve identity and tint through border and owner disable/re-enable", function()
		local button = Button()
		local curve = RegisteredCurve(button)
		button:MockUpdateDispelTextures("Curse")
		for _, path in ipairs({ "auras.dispelBorder", "auras.border.enabled", "auras.enabled" }) do
			ns.Config:SetUnitValue("player", path, false)
			if path ~= "auras.enabled" then
				assert.same({}, button.__state.dispelTextures)
				assert.is_false(button.ufBorder:IsShown())
			else
				assert.is_false(container:IsEnabled())
			end
			ns.Config:SetUnitValue("player", path, true)
			assert.equals(button, Button())
			assert.equals(curve, RegisteredCurve(button), path)
			assert.is_true(button.ufBorder:IsShown())
			AssertTint(button, COLORS.Curse)
		end
	end)

	local function AssertSampleLiveParity(name, expected)
		local live = Button()
		live:MockUpdateDispelTextures(name)
		AssertTint(live, expected)
		auras:ShowSample({ debuffs = { { icon = "sample", dispelName = name } } })
		local sample = auras.previewContainers.debuffs.ufElements[1]
		assert.is_not_nil(sample)
		AssertTint(sample, expected)
		for index, texture in ipairs(sample.ufDispelTextures) do
			assert.same(live.ufDispelTextures[index].__state.vertexColor, texture.__state.vertexColor)
		end
	end

	for _, name in ipairs(TYPES) do
		it("matches customized sample and native live RGBA for " .. name, function()
			AssertSampleLiveParity(name, COLORS[name])
		end)
	end

	for _, name in ipairs(FALLBACK_TYPES) do
		it("uses the native sample and live fallback for unconfigured " .. name, function()
			AssertSampleLiveParity(name, { AuraUtil.GetAuraBorderColor(name):GetRGBA() })
		end)
	end
end)
