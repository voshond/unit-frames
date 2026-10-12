local Helpers = require("helpers")
local Mock = Helpers.Mock

-- A castbar placed over the health row or portrait replaces it, so a
-- translucent frame (out-of-range opacity) never shows both at once.
describe("Castbars covering health or the portrait", function()
	local ns, uf, castbar, health, portrait
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		uf = ns.Units.frames.player.uf
		castbar = uf:GetPart("castbar")
		health = uf:GetRow("health"):GetFrame()
		portrait = uf:GetPart("portrait"):GetFrame()
	end)

	local function Cast()
		castbar:Start({ name = Secret("Fireball"), icon = Secret(135812), duration = C_DurationUtil.CreateDuration() })
	end

	it("hides what it covers while casting and restores it when idle", function()
		for _, placement in ipairs({ "health", "portrait" }) do
			ns.Config:SetUnitValue("player", "castbar.placement", placement)
			local covered, other = placement == "health" and health or portrait, placement == "health" and portrait or health
			assert.equals(1, covered:GetAlpha(), placement .. " idle")
			Cast()
			assert.equals(0, covered:GetAlpha(), placement .. " casting")
			assert.equals(1, other:GetAlpha())
			castbar:Hide()
			assert.equals(1, covered:GetAlpha(), placement .. " cleared")
		end
	end)

	it("brings the covered region back as the castbar fades out", function()
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		Cast()
		castbar:Stop("success")
		assert.is_true(castbar.fade:IsPlaying())
		assert.equals(0, health:GetAlpha(), "held after the cast")
		castbar.fadeAlpha.__state.progress = 0.4
		castbar.fade:RunScript("OnUpdate", 0.1)
		assert.equals(0.4, health:GetAlpha(), "crossfading")
		Cast()
		assert.is_false(castbar.fade:IsPlaying())
		assert.equals(0, health:GetAlpha(), "a new cast interrupts the fade")
		castbar:Stop("interrupted")
		castbar.fade:RunScript("OnFinished")
		assert.is_false(castbar:GetFrame():IsShown())
		assert.equals(1, castbar:GetFrame():GetAlpha())
		assert.equals(1, health:GetAlpha(), "faded out")
	end)

	it("stays independent of the secret range opacity on the whole frame", function()
		ns.Config:SetUnitValue("player", "range.enabled", true)
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		uf:SetRangeState(Secret(false), Secret(true))
		Cast()
		assert.is_true(Mock.IsSecret(uf:GetFrame():GetAlpha()))
		assert.equals(0, health:GetAlpha())
		assert.equals(1, castbar:GetFrame():GetAlpha())
	end)

	it("restores the region when placement, unit, element or frame changes", function()
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		Cast()
		ns.Config:SetUnitValue("player", "castbar.placement", "portrait")
		assert.equals(1, health:GetAlpha(), "no longer covered")
		assert.equals(0, portrait:GetAlpha(), "the cast now covers the portrait")
		ns.Config:SetUnitValue("player", "castbar.placement", "bottom")
		assert.equals(1, portrait:GetAlpha(), "own row: nothing covered")
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		Cast()
		ns.Config:SetUnitValue("player", "castbar.placement", "off")
		assert.equals(1, health:GetAlpha(), "switched off")

		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		Cast()
		UnitCastingInfo = function() return nil end
		UnitChannelInfo = function() return nil end
		ns.Cast.Refresh(castbar, {}, "player")
		assert.equals(1, health:GetAlpha(), "unit change without a cast")

		ns.Config:SetUnitValue("player", "castbar.placement", "portrait")
		Cast()
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		assert.equals(1, portrait:GetAlpha(), "portrait removed")

		local preview = ns.Units:CreateFrame("target", UIParent)
		preview:Apply(ns.Util.Merge(ns.Util.Copy(ns.Config:GetUnitConfig("target")), { castbar = { placement = "health" } }))
		local previewHealth = preview:GetRow("health"):GetFrame()
		preview:GetPart("castbar"):Start({ name = "Frostbolt", icon = 1, duration = C_DurationUtil.CreateDuration() })
		assert.equals(0, previewHealth:GetAlpha())
		preview:Release()
		assert.equals(1, previewHealth:GetAlpha(), "released frames give the region back")
	end)

	it("replaces health in sample previews only while the sample cast shows", function()
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		local sample = ns.Units:GetSample("player")
		ns.Units:ShowSample(uf, sample)
		assert.equals(0, health:GetAlpha())
		sample.showCast = false
		ns.Units:ShowSample(uf, sample)
		assert.equals(1, health:GetAlpha())
	end)
end)
