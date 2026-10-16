local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Portrait casts", function()
	local ns, uf, castbar
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		ns.Config:SetUnitValue("player", "experience.enabled", true)
		ns.Config:SetUnitValue("player", "castbar.enabled", true)
		Mock.InstallUI()
		uf = ns.Units.frames.player.uf
		castbar = uf:GetPart("castbar")
	end)

	it("covers either portrait side without adding a row and restores it when idle", function()
		ns.Config:SetUnitValue("player", "castbar.placement", "portrait")
		for _, side in ipairs({ "LEFT", "RIGHT" }) do
			for _, mode in ipairs({ "3D", "2D", "class" }) do
				ns.Config:SetUnitValue("player", "portrait.position", side)
				ns.Config:SetUnitValue("player", "portrait.mode", mode)
				assert.equals(3, #uf.layout.rows)
				assert.same({ "ALL", uf:GetPart("portrait"):GetFrame() }, castbar.frame.__state.points[1])
				assert.is_true(castbar.opaque)
				assert.is_false(castbar.iconFrame:IsShown())
				assert.is_true(castbar.frame:GetFrameLevel() > uf:GetPart("portrait").model:GetFrameLevel())
				ns.Units:ShowSample(uf, ns.Units:GetSample("player"))
				assert.is_true(castbar.frame:IsShown())
				local sample = ns.Units:GetSample("player")
				sample.showCast = false
				ns.Units:ShowSample(uf, sample)
				assert.is_false(castbar.frame:IsShown())
				assert.is_true(uf:GetPart("portrait"):GetFrame():IsShown())
			end
		end
	end)

	it("splits icon and bar, changes fill direction, and returns to normal rows", function()
		ns.Config:SetUnitValue("player", "castbar.placement", "portrait")
		castbar.frame:SetSize(60, 40)
		for _, orientation in ipairs({ "HORIZONTAL", "VERTICAL" }) do
			for _, layout in ipairs({ "split", "stack", "bar" }) do
				castbar:Apply({ portraitLayout = layout, border = { enabled = false }, bar = { orientation = orientation } })
				castbar:Apply()
				assert.equals(orientation, castbar.bar.bar.__state.orientation)
				assert.equals(layout ~= "bar", castbar.iconFrame:IsShown())
				if layout == "split" then
					assert.equals(29.5, castbar.iconFrame:GetWidth())
					assert.equals(40, castbar.iconFrame:GetHeight())
				elseif layout == "stack" then
					assert.equals(60, castbar.iconFrame:GetWidth())
					assert.equals(19.5, castbar.iconFrame:GetHeight())
				end
				castbar:Preview({ name = Mock.Secret("Frostbolt"), icon = Mock.Secret(123) }, 0.5, "1.2")
				assert.equals("1.2", castbar.timeText.frame:GetText())
			end
		end
		ns.Config:SetUnitValue("player", "castbar.placement", "bottom")
		assert.equals(4, #uf.layout.rows)
		assert.is_false(castbar.portraitPlacement)
		assert.is_false(castbar.opaque)
		assert.is_true(castbar.iconFrame:IsShown())
	end)

	it("disables portrait casts when no portrait exists and rebinds when restored", function()
		ns.Config:SetUnitValue("player", "castbar.placement", "portrait")
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		assert.is_false(castbar:IsEnabled())
		assert.is_false(ns.Units.frames.player:IsElementEnabled("UF_Castbar"))
		ns.Config:SetUnitValue("player", "portrait.enabled", true)
		assert.is_true(castbar:IsEnabled())
		assert.is_true(ns.Units.frames.player:IsElementEnabled("UF_Castbar"))
		uf:Release()
		assert.is_false(castbar.frame:IsShown())
	end)

	it("shows secret cast and channel names with an idle level/class fallback", function()
		ns.Config:SetUnitValue("player", "health.belowLeft.enabled", true)
		ns.Config:SetUnitValue("player", "health.belowLeft.format", "level:class:cast")
		local text = uf:GetRow("health"):GetText("belowLeft")
		local format = ns.Formats.Get("level:class:cast")
		local name = Mock.Secret("Frostbolt")
		UnitCastingInfo = function() return name end
		assert.is_true(rawequal(name, format.text("player")))
		UnitCastingInfo = function() return nil end
		UnitChannelInfo = function() return name end
		assert.is_true(rawequal(name, format.text("player")))
		UnitChannelInfo = function() return nil end
		assert.has_no_error(function() format.text("player") end)
		local sample = ns.Units:GetSample("player")
		ns.Units:ShowSample(uf, sample)
		assert.equals(sample.spell, text.frame:GetText())
		assert.equals(sample.spell, format.sample(sample))
		sample.showCast = false
		ns.Units:ShowSample(uf, sample)
		assert.equals(ns.Formats.Get("level:class").sample(sample), text.frame:GetText())
		assert.equals(ns.Formats.Get("level:class").sample(sample), format.sample(sample))
		assert.equals("", ns.Formats.Get("cast:name").sample(sample))
		assert.is_not_nil(ns.oUF.Tags.Events["uf:level:class:cast"]:find("UNIT_SPELLCAST_CHANNEL_STOP", 1, true))
	end)
end)
