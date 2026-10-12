local Helpers = require("helpers")
local Mock = Helpers.Mock

-- Native renderer oracle; production code only passes secret alpha through.
local function ModelAlpha(portrait)
	local alpha = portrait.model.__state.modelAlpha
	if Mock.IsSecret(alpha) then return alpha.secretValue end
	return alpha == nil and 1 or alpha
end

describe("3D portrait opacity", function()
	it("follows secret range opacity, resets, mode changes and model replacement", function()
		local UF = Helpers.LoadAddon(true, true)
		local uf = UF.Units.frames.target.uf
		local portrait = uf:GetPortrait()
		UF.Config:SetUnitValue("target", "range.enabled", true)
		Mock.inCombat = true
		for _, checked in ipairs({ true, false }) do
			for _, inside in ipairs({ true, false }) do
				uf:SetRangeState(Mock.Secret(inside), Mock.Secret(checked))
				assert.equals(checked and not inside and 0.55 or 1, ModelAlpha(portrait))
				assert.is_true(Mock.IsSecret(portrait.model.__state.modelAlpha))
			end
		end
		Mock.inCombat = false
		uf:SetRangeState(Mock.Secret(false), Mock.Secret(true))
		for _, mode in ipairs({ "2D", "class", "3D" }) do UF.Config:SetUnitValue("target", "portrait.mode", mode) end
		assert.equals(0.55, ModelAlpha(portrait))
		portrait.model.__state.modelAlpha = 1 -- native model replacement may reset its material alpha
		portrait.model:PostUpdate("target", true)
		assert.equals(0.55, ModelAlpha(portrait))
		UF.Config:SetUnitValue("target", "range.enabled", false)
		assert.equals(1, ModelAlpha(portrait))
	end)

	it("follows cast coverage and restores the model while preserving the parent's secret fade", function()
		local UF = Helpers.LoadAddon(true, true)
		UF.Config:SetUnitValue("player", "range.enabled", true)
		UF.Config:SetUnitValue("player", "range.outsideAlpha", 0.3)
		UF.Config:SetUnitValue("player", "castbar.placement", "portrait")
		local uf = UF.Units.frames.player.uf
		local portrait, castbar = uf:GetPortrait(), uf:GetCastbar()
		uf:SetRangeState(Mock.Secret(false), Mock.Secret(true))
		castbar:Start({ name = Mock.Secret("Fireball"), icon = Mock.Secret(1), duration = C_DurationUtil.CreateDuration() })
		assert.equals(0, ModelAlpha(portrait))
		castbar:Stop("success")
		castbar.fadeAlpha.__state.progress = 0.5
		castbar.fade:RunScript("OnUpdate", 0.1)
		assert.equals(0.15, ModelAlpha(portrait))
		castbar:Hide()
		assert.equals(0.3, ModelAlpha(portrait))
		castbar:Start({ name = "Fireball", icon = 1, duration = C_DurationUtil.CreateDuration() })
		UF.Config:SetUnitValue("player", "castbar.placement", "bottom")
		assert.equals(0.3, ModelAlpha(portrait))
	end)

	it("keeps sample models synchronized without an update loop and clears their data callback on release", function()
		local UF = Helpers.LoadAddon(true, true)
		local uf = UF.Units:CreateFrame("target", UIParent)
		uf:Apply({ range = { enabled = true, outsideAlpha = 0.2 } })
		local sample = UF.Units:GetSample("target")
		sample.outOfRange = true
		UF.Units:ShowSample(uf, sample)
		local portrait = uf:GetPortrait()
		assert.equals(0.2, ModelAlpha(portrait))
		assert.is_nil(portrait.model:GetScript("OnUpdate"))
		sample.outOfRange = false
		UF.Units:ShowSample(uf, sample)
		assert.equals(1, ModelAlpha(portrait))
		uf:Release()
		assert.is_nil(rawget(portrait.model, "PostUpdate"))
	end)
end)
