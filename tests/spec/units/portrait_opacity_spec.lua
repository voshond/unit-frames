local Helpers = require("helpers")
local Mock = Helpers.Mock

-- Engine oracle. Addon code never reads these.
local function Oracle(value)
	if Mock.IsSecret(value) then return value.secretValue end
	return value == nil and 1 or value
end
local function Round(value)
	return math.floor(value * 1000 + 0.5) / 1000
end
-- Observed in game: the artwork renders with its material alpha only and
-- ignores frame alpha, inherited or its own.
local function RenderedAlpha(portrait)
	return Round(Oracle(portrait.model.__state.modelAlpha))
end
-- Material alpha times the model frame's own alpha: the secret-range fallback,
-- which can only select the fade natively on the frame.
local function ModelAlpha(portrait)
	local state = portrait.model.__state
	return Round(Oracle(state.modelAlpha) * Oracle(state.alpha))
end

describe("3D portrait opacity", function()
	it("fades the material alpha with plain range opacity, resets, mode changes and model replacement", function()
		local UF = Helpers.LoadAddon(true, true)
		local uf = UF.Units.frames.target.uf
		local portrait = uf:GetPart("portrait")
		UF.Config:SetUnitValue("target", "range.enabled", true)
		for _, checked in ipairs({ true, false }) do
			for _, inside in ipairs({ true, false }) do
				uf:SetRangeState(inside, checked)
				assert.equals(checked and not inside and 0.55 or 1, RenderedAlpha(portrait))
				assert.equals(1, Oracle(portrait.model.__state.alpha), "no second fade on the frame")
			end
		end
		uf:SetRangeState(false, true)
		for _, mode in ipairs({ "2D", "class", "3D" }) do UF.Config:SetUnitValue("target", "portrait.mode", mode) end
		assert.equals(0.55, RenderedAlpha(portrait))
		portrait.model.__state.modelAlpha = 1 -- native model replacement may reset its material alpha
		portrait.model:PostUpdate("target", true)
		assert.equals(0.55, RenderedAlpha(portrait))
		UF.Config:SetUnitValue("target", "range.enabled", false)
		assert.equals(1, RenderedAlpha(portrait))
	end)

	-- Behind a secret fade the client returns no effective alpha and secret
	-- alphas, and SetModelAlpha refuses both: the fade goes to the model's frame.
	it("follows a secret range fade on the model's own frame, never reading alpha back", function()
		local UF = Helpers.LoadAddon(true, true)
		local uf = UF.Units.frames.target.uf
		local portrait = uf:GetPart("portrait")
		UF.Config:SetUnitValue("target", "range.enabled", true)
		uf:SetRangeState(false, true)
		Mock.inCombat = true
		for _, checked in ipairs({ true, false }) do
			for _, inside in ipairs({ true, false }) do
				assert.has_no_error(function() uf:SetRangeState(Mock.Secret(inside), Mock.Secret(checked)) end)
				assert.is_nil(uf:GetFrame():GetEffectiveAlpha())
				assert.equals(checked and not inside and 0.55 or 1, ModelAlpha(portrait))
				assert.is_false(Mock.IsSecret(portrait.model.__state.modelAlpha), "material alpha stays plain")
				assert.is_true(Mock.IsSecret(portrait.model.__state.alpha), "the frame fade stays secret")
			end
		end
		assert.has_no_error(function() portrait.model:PostUpdate("target", true) end)
		assert.has_no_error(function() UF.Config:SetUnitValue("target", "portrait.border.padding", 2) end)
		assert.equals(1, ModelAlpha(portrait), "the last result was not checked")
		uf:SetRangeState(Mock.Secret(false), Mock.Secret(true))
		portrait.model.__state.alpha = 1 -- native model replacement may reset its alpha
		portrait.model:PostUpdate("target", true)
		assert.equals(0.55, ModelAlpha(portrait))
		UF.Config:SetUnitValue("target", "range.enabled", false)
		assert.equals(1, ModelAlpha(portrait))
	end)

	it("follows cast coverage combined with a plain range fade", function()
		local UF = Helpers.LoadAddon(true, true)
		UF.Config:SetUnitValue("player", "range.enabled", true)
		UF.Config:SetUnitValue("player", "range.outsideAlpha", 0.3)
		UF.Config:SetUnitValue("player", "castbar.enabled", true)
		UF.Config:SetUnitValue("player", "castbar.placement", "portrait")
		local uf = UF.Units.frames.player.uf
		local portrait, castbar = uf:GetPart("portrait"), uf:GetPart("castbar")
		uf:SetRangeState(false, true)
		castbar:Start({ name = Mock.Secret("Fireball"), icon = Mock.Secret(1), duration = C_DurationUtil.CreateDuration() })
		assert.equals(0, RenderedAlpha(portrait))
		castbar:Stop("success")
		castbar.fadeAlpha.__state.progress = 0.5
		castbar.fade:RunScript("OnUpdate", 0.1)
		assert.equals(0.15, RenderedAlpha(portrait))
		castbar:Hide()
		assert.equals(0.3, RenderedAlpha(portrait))
		castbar:Start({ name = "Fireball", icon = 1, duration = C_DurationUtil.CreateDuration() })
		UF.Config:SetUnitValue("player", "castbar.placement", "bottom")
		assert.equals(0.3, RenderedAlpha(portrait))
	end)

	it("follows cast coverage combined with a secret range fade", function()
		local UF = Helpers.LoadAddon(true, true)
		UF.Config:SetUnitValue("player", "range.enabled", true)
		UF.Config:SetUnitValue("player", "castbar.enabled", true)
		UF.Config:SetUnitValue("player", "castbar.placement", "portrait")
		local uf = UF.Units.frames.player.uf
		local portrait, castbar = uf:GetPart("portrait"), uf:GetPart("castbar")
		uf:SetRangeState(Mock.Secret(false), Mock.Secret(true))
		castbar:Start({ name = Mock.Secret("Fireball"), icon = Mock.Secret(1), duration = C_DurationUtil.CreateDuration() })
		assert.equals(0, ModelAlpha(portrait), "the cast still hides the model")
		castbar:Stop("success")
		castbar.fadeAlpha.__state.progress = 0.5
		castbar.fade:RunScript("OnUpdate", 0.1)
		assert.equals(0.275, ModelAlpha(portrait), "coverage and the secret range fade combine")
		castbar:Hide()
		assert.equals(0.55, ModelAlpha(portrait))
	end)

	it("keeps sample models synchronized without an update loop and clears their data callback on release", function()
		local UF = Helpers.LoadAddon(true, true)
		local uf = UF.Units:CreateFrame("target", UIParent)
		uf:Apply({ range = { enabled = true, outsideAlpha = 0.2 } })
		local sample = UF.Units:GetSample("target")
		sample.outOfRange = true
		UF.Units:ShowSample(uf, sample)
		local portrait = uf:GetPart("portrait")
		assert.equals(0.2, RenderedAlpha(portrait))
		assert.is_nil(portrait.model:GetScript("OnUpdate"))
		sample.outOfRange = false
		UF.Units:ShowSample(uf, sample)
		assert.equals(1, RenderedAlpha(portrait))
		uf:Release()
		assert.is_nil(rawget(portrait.model, "PostUpdate"))
	end)
end)
