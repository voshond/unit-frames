local Helpers = require("helpers")

local MAGIC = { 0.21, 0.32, 0.43, 0.54 }

local function Halo(button) return _G.UnitFrames.AuraIcon.GetGlowHolder(button, "halo") end
local function Proc(button) return _G.UnitFrames.AuraIcon.GetGlowHolder(button, "proc") end

-- Registered options of the holder's textures (default: the halo), and the count of others.
local function Registered(button, holder)
	holder = holder or Halo(button)
	local glow, other = {}, 0
	local textures = {}
	for _, texture in ipairs(holder and holder.textures or {}) do textures[texture] = true end
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
		assert.is_nil(Halo(button), "no glow art is allocated until enabled")
		assert.is_nil(Proc(button))
	end)

	it("registers one sliced halo texture with the shared dispel curve, typed debuffs only", function()
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", true)
		local button = Button()
		local glow = Registered(button)
		assert.equals(1, #glow)
		local curve = ns.AuraIcon.DispelCurve(auras.dispelColors)
		for _, options in ipairs(glow) do
			assert.equals(Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset, options.style)
			assert.is_true(options.showWhenHarmful)
			assert.is_false(options.showWhenHelpful)
			assert.is_false(options.showWithoutDispelType)
			assert.equals(curve, options.customDispelColorCurve)
		end
		for _, texture in ipairs(Halo(button).textures) do
			assert.equals("Interface\\AddOns\\UnitFrames\\Media\\Glow", texture:GetTexture())
			assert.same({ 31, 31, 31, 31 }, { texture:GetTextureSliceMargins() })
			assert.equals(Enum.UITextureSliceMode.Stretched, texture:GetTextureSliceMode())
			assert.equals("ADD", texture.__state.blendMode)
		end
		assert.is_true(Halo(button):IsShown())
		assert.is_nil(Halo(auras:GetContainer("buffs"):GetAuraGroupFrame("buffs", 1)))

		button:MockUpdateDispelTextures("Magic")
		for _, texture in ipairs(Halo(button).textures) do
			assert.is_true(texture:IsShown())
			assert.same(MAGIC, texture.__state.vertexColor)
		end
		button:MockUpdateDispelTextures("None")
		for _, texture in ipairs(Halo(button).textures) do assert.is_false(texture:IsShown()) end
		for _, texture in ipairs(button.ufDispelTextures) do assert.is_true(texture:IsShown()) end
	end)

	it("keeps registrations through geometry restyles and renews them for colours and toggles", function()
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", true)
		local button = Button()
		local adds = AddCalls(button)
		ns.Config:SetUnitValue("player", "auras.dispelGlow.size", 20)
		ns.Config:SetUnitValue("player", "auras.dispelGlow.opacity", 0.5)
		assert.equals(0, adds())
		assert.equals(0.5, Halo(button):GetAlpha())

		ns.Config:SetUnitValue("player", "auras.dispelColors.Magic", { 1, 0, 1, 1 })
		assert.equals(1, #Registered(button))
		assert.is_true(adds() >= 1)

		-- Any toggle order, including with the border off.
		for _, path in ipairs({ "auras.dispelBorder", "auras.border.enabled" }) do
			ns.Config:SetUnitValue("player", path, false)
			assert.equals(1, #Registered(button), path)
		end
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", false)
		assert.same({}, button.__state.dispelTextures)
		assert.is_false(Halo(button):IsShown())
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", true)
		assert.equals(1, #Registered(button))
		assert.is_true(Halo(button):IsShown())
	end)

	it("draws the halo fully outside the icon, reaching the configured size", function()
		ns.Config:SetUnitValue("player", "auras.debuffs.size", 20)
		ns.Config:SetUnitValue("player", "auras.dispelGlow", { enabled = true, size = 32 })
		local holder = Halo(Button())
		local scale = holder.Halo:GetScale()
		local margin = holder.Halo:GetTextureSliceMargins()
		assert.equals(32, math.floor(scale * margin + 0.5), "the drawn slices reach the configured size")
		local point, relative, relativePoint, x, y = holder.Halo:GetPoint(1)
		assert.same({ "TOPLEFT", holder, "TOPLEFT" }, { point, relative, relativePoint })
		assert.same({ -margin, margin }, { x, y }, "the slices' inner edge meets the icon's edge")
		assert.same({ "BOTTOMRIGHT", holder, "BOTTOMRIGHT", margin, -margin }, { holder.Halo:GetPoint(2) })
		ns.Config:SetUnitValue("player", "auras.dispelGlow.size", 6)
		assert.equals(6, math.floor(holder.Halo:GetScale() * margin + 0.5))
	end)

	it("starts the halo at the icon artwork's edge, under the border, in any border order", function()
		ns.Config:SetUnitValue("player", "auras.debuffs.size", 20)
		ns.Config:SetUnitValue("player", "auras.border.padding", 3)
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", true)
		local button = Button()
		local holder = Halo(button)
		assert.same({ "TOPLEFT", button.ufIconFrame, "TOPLEFT", 3, -3 }, { holder:GetPoint(1) })
		assert.same({ "BOTTOMRIGHT", button.ufIconFrame, "BOTTOMRIGHT", -3, 3 }, { holder:GetPoint(2) })
		assert.same({ button.ufIcon:GetPoint(1) }, { holder:GetPoint(1) }, "the same edge as the artwork")
		ns.Config:SetUnitValue("player", "auras.border.enabled", false)
		assert.same({ "TOPLEFT", button.ufIconFrame, "TOPLEFT", 0, 0 }, { holder:GetPoint(1) })
		ns.Config:SetUnitValue("player", "auras.border.enabled", true)
		assert.same({ "TOPLEFT", button.ufIconFrame, "TOPLEFT", 3, -3 }, { holder:GetPoint(1) })
	end)

	it("matches sample glow to the live type colour and leaves untyped samples unlit", function()
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", true)
		auras:ShowSample({ debuffs = { { icon = "sample", dispelName = "Magic" }, { icon = "sample" } } })
		local typed, untyped = auras.previewContainers.debuffs.ufElements[1], auras.previewContainers.debuffs.ufElements[2]
		assert.is_true(Halo(typed):IsShown())
		for index, texture in ipairs(Halo(typed).textures) do
			assert.is_true(texture:IsShown())
			assert.same(MAGIC, texture.__state.vertexColor)
			assert.equals(Halo(Button()).textures[index]:GetTexture(), texture:GetTexture())
		end
		for _, texture in ipairs(Halo(untyped).textures) do assert.is_false(texture:IsShown()) end
		ns.Config:SetUnitValue("player", "auras.dispelGlow.enabled", false)
		assert.is_false(Halo(typed):IsShown())
	end)

	it("draws Blizzard's desaturated proc flipbooks for the proc style and moves the registration", function()
		ns.Config:SetUnitValue("player", "auras.debuffs.size", 30)
		ns.Config:SetUnitValue("player", "auras.dispelGlow", { enabled = true, style = "proc", opacity = 0.8 })
		local button = Button()
		local proc = Proc(button)
		assert.is_nil(Halo(button))
		assert.is_true(proc:IsShown())
		assert.equals("UI-HUD-ActionBar-Proc-Start-Flipbook", proc.Start.__state.atlas)
		assert.equals("UI-HUD-ActionBar-Proc-Loop-Flipbook", proc.Loop.__state.atlas)
		assert.equals(42, proc:GetWidth())
		assert.equals(100, proc.Start:GetWidth())
		assert.equals(0.8, proc:GetAlpha())
		for _, texture in ipairs(proc.textures) do assert.is_true(texture.__state.desaturated) end
		local glow, other = Registered(button, proc)
		assert.equals(2, #glow)
		assert.equals(8, other)
		for _, options in ipairs(glow) do
			assert.equals(Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset, options.style)
			assert.is_false(options.showWithoutDispelType)
		end
		button:MockUpdateDispelTextures("Magic")
		for _, texture in ipairs(proc.textures) do assert.same(MAGIC, texture.__state.vertexColor) end

		ns.Config:SetUnitValue("player", "auras.dispelGlow.style", "halo")
		assert.is_false(proc:IsShown())
		assert.equals(0, #Registered(button, proc))
		assert.equals(1, #Registered(button))
		ns.Config:SetUnitValue("player", "auras.dispelGlow.style", "proc")
		assert.equals(proc, Proc(button))
		assert.equals(2, #Registered(button, proc))
		assert.equals(0, #Registered(button))
	end)

	it("plays the proc burst on show, then loops, and stops when hidden", function()
		ns.Config:SetUnitValue("player", "auras.dispelGlow", { enabled = true, style = "proc" })
		local proc = Proc(Button())
		proc:RunScript("OnShow")
		assert.is_true(proc.StartAnim:IsPlaying())
		assert.is_false(proc.LoopAnim:IsPlaying())
		assert.equals(1, proc.Start:GetAlpha())
		assert.equals(0, proc.Loop:GetAlpha())
		proc.StartAnim:RunScript("OnFinished")
		assert.equals(0, proc.Start:GetAlpha())
		assert.equals(1, proc.Loop:GetAlpha())
		assert.is_true(proc.LoopAnim:IsPlaying())
		proc:RunScript("OnHide")
		assert.is_false(proc.StartAnim:IsPlaying())
		assert.is_false(proc.LoopAnim:IsPlaying())
	end)

	it("hides halo-only geometry settings for the proc style", function()
		local schema = ns.Schema.Find(ns.AuraIcon.schema, "dispelGlow").schema
		assert.is_nil(ns.Schema.Find(schema, "additive"), "the black-backed art only works additively")
		local option = ns.Schema.Find(schema, "size")
		assert.is_true(option.hidden({ style = "proc" }))
		assert.is_false(option.hidden({ style = "halo" }))
		assert.is_nil(ns.Schema.Find(schema, "offset"), "the halo always stays outside the icon")
		assert.is_nil(ns.Schema.Find(ns.Glow.schema, "size").hidden, "the shared halo schema stays unchanged")
	end)

	it("matches proc samples to the live type colour", function()
		ns.Config:SetUnitValue("player", "auras.dispelGlow", { enabled = true, style = "proc" })
		auras:ShowSample({ debuffs = { { icon = "sample", dispelName = "Magic" }, { icon = "sample" } } })
		local typed, untyped = auras.previewContainers.debuffs.ufElements[1], auras.previewContainers.debuffs.ufElements[2]
		assert.is_true(Proc(typed):IsShown())
		for _, texture in ipairs(Proc(typed).textures) do
			assert.is_true(texture:IsShown())
			assert.same(MAGIC, texture.__state.vertexColor)
		end
		for _, texture in ipairs(Proc(untyped).textures) do assert.is_false(texture:IsShown()) end
	end)
end)
