local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Text alignment", function()
	it("spans its host so the alignment moves the text", function()
		local ns = Helpers.LoadAddon(true)
		local host = CreateFrame("Frame")
		local text = ns.Components.Text:New(host, { justifyH = "RIGHT", inset = 6, offsetY = 2 }, { host = host })
		assert.same({ "LEFT", host, "LEFT", 6, 2 }, text.frame:GetAnchor("LEFT"))
		assert.same({ "RIGHT", host, "RIGHT", -6, 2 }, text.frame:GetAnchor("RIGHT"))
		local justify
		for _, call in ipairs(text.frame.__calls) do
			if call[1] == "SetJustifyH" then
				justify = call[2]
			end
		end
		assert.equals("RIGHT", justify)
	end)
end)

describe("TextBar", function()
	it("has three slots, only those with a default format switched on", function()
		local ns = Helpers.LoadAddon(true)
		local row = ns.Components.TextBar:New(CreateFrame("Frame"), {}, {
			formats = ns.Formats.HEALTH, textDefaults = { left = "name", right = "health:value" },
		})
		assert.is_true(row:GetText("left"):IsEnabled())
		assert.is_false(row:GetText("center"):IsEnabled())
		assert.equals("health:value", row:GetText("right"):GetFormat())
		assert.equals("CENTER", row:GetText("center").resolved.justifyH)

		row:Apply({ center = { enabled = true, format = "health:percent" } })
		row:ShowSample(ns.Units.SAMPLE)
		assert.equals("65%", row:GetText("center").frame:GetText())
	end)
end)

describe("Text below the name", function()
	local ns, row
	before_each(function()
		ns = Helpers.LoadAddon(true)
		row = ns.Components.TextBar:New(CreateFrame("Frame"), {}, {
			formats = ns.Formats.HEALTH,
			textDefaults = { left = "name", right = "health:value", belowLeft = { format = "level:class", enabled = false } },
		})
	end)

	local function Anchor(key, point)
		return row:GetText(key).frame:GetAnchor(point)
	end

	it("is offered but off by default, and the name stays centred", function()
		assert.is_false(row:GetText("belowLeft"):IsEnabled())
		assert.equals("level:class", row:GetText("belowLeft"):GetFormat())
		assert.is_not_nil(Anchor("left", "LEFT"))
	end)

	it("moves the name to the top half when switched on", function()
		row:Apply({ belowLeft = { enabled = true } })
		local host = row:GetBar():GetTextParent()
		assert.same({ "TOPLEFT", host, "TOPLEFT", 4, -1 }, Anchor("left", "TOPLEFT"))
		assert.same({ "BOTTOMLEFT", host, "BOTTOMLEFT", 4, 1 }, Anchor("belowLeft", "BOTTOMLEFT"))
		assert.equals(9, row:GetText("belowLeft").resolved.size, "smaller by default")
		assert.is_not_nil(Anchor("right", "RIGHT"), "the right text keeps its place")
		row:ShowSample(ns.Units.SAMPLE)
		assert.equals("42 Paladin", row:GetText("belowLeft").frame:GetText())
	end)

	it("respects a vertical position set by hand", function()
		row:Apply({ belowLeft = { enabled = true }, left = { vertical = "middle" } })
		assert.is_not_nil(Anchor("left", "LEFT"))
	end)
end)

describe("Formats", function()
	it("render samples and secret live values for every format", function()
		local ns = Helpers.LoadAddon(true)
		Mock.InstallUI()
		for _, format in ipairs(ns.Formats.list) do
			assert.equals("string", type(format.sample(ns.Units.SAMPLE)), format.id)
			assert.has_no_error(function()
				format.text("player")
			end, format.id)
		end
	end)

	it("are registered as oUF tags", function()
		local ns = Helpers.LoadAddon(true)
		local tags = ns.oUF.Tags
		assert.is_not_nil(tags.Methods["uf:health:value"])
		assert.equals("UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION", tags.Events["uf:health:value"])
		assert.is_true(tags.SharedEvents.PLAYER_XP_UPDATE, "XP events carry no unit")
	end)
end)

describe("Player frame", function()
	local ns, frame
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
	end)

	local function Row(key)
		return frame.uf:GetRow(key)
	end

	-- The plain bar stack, without the portrait and castbar.
	local function BarsOnly()
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		ns.Config:SetUnitValue("player", "castbar.placement", "off")
	end

	it("stacks health, power and experience inside the border", function()
		BarsOnly()
		-- heights 26 + 12 + 10, spacing 1 between rows, padding 4 around
		assert.equals(230, frame:GetWidth())
		assert.equals(4 + 26 + 1 + 12 + 1 + 10 + 4, frame:GetHeight())
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 4, -4 }, Row("health"):GetFrame():GetAnchor("TOPLEFT"))
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 4, -31 }, Row("power"):GetFrame():GetAnchor("TOPLEFT"))
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 4, -44 }, Row("experience"):GetFrame():GetAnchor("TOPLEFT"))
	end)

	it("binds rows and segments to oUF elements", function()
		local health = Row("health"):GetBar()
		assert.equals(health:GetStatusBar(), frame.Health)
		assert.equals(health.segmentsByKey.heal.bar, frame.Health.HealingAll)
		assert.equals(health.segmentsByKey.absorb.bar, frame.Health.DamageAbsorb)
		assert.equals(health.segmentsByKey.healAbsorb.bar, frame.Health.HealAbsorb)
		assert.equals(Row("power"):GetBar().segmentsByKey.cost.bar, frame.Power.CostPrediction)
		assert.equals(Row("experience"), frame.UF_Experience)
		assert.is_true(frame:IsElementEnabled("Health"))
		assert.is_true(frame:IsElementEnabled("UF_Experience"))
	end)

	it("tags the texts with their formats", function()
		assert.is_nil(frame.tags[Row("health"):GetText("belowLeft"):GetFrame()], "below-name text is off by default")
		ns.Config:SetUnitValue("player", "health.belowLeft.enabled", true)
		assert.equals("[uf:level:class]", frame.tags[Row("health"):GetText("belowLeft"):GetFrame()])
		assert.equals("[uf:name]", frame.tags[Row("health"):GetText("left"):GetFrame()])
		assert.equals("[uf:health:value]", frame.tags[Row("health"):GetText("right"):GetFrame()])
		assert.is_nil(frame.tags[Row("health"):GetText("center"):GetFrame()])
		assert.equals("[uf:xp:value:percent]", frame.tags[Row("experience"):GetText("center"):GetFrame()])
	end)

	it("collapses a switched-off row and disables its element", function()
		BarsOnly()
		ns.Config:SetUnitValue("player", "power.enabled", false)
		assert.equals(4 + 26 + 1 + 10 + 4, frame:GetHeight())
		assert.is_false(frame:IsElementEnabled("Power"))
		assert.is_nil(frame.Power)
		assert.is_nil(frame.tags[Row("power"):GetText("right"):GetFrame()], "its texts are untagged")
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 4, -31 }, Row("experience"):GetFrame():GetAnchor("TOPLEFT"))

		ns.Config:SetUnitValue("player", "power.enabled", nil)
		assert.is_true(frame:IsElementEnabled("Power"))
		assert.equals(4 + 26 + 1 + 12 + 1 + 10 + 4, frame:GetHeight())
	end)

	it("re-binds segments and texts after changes", function()
		ns.Config:SetUnitValue("player", "health.bar.segments.heal.enabled", false)
		assert.is_nil(rawget(frame.Health, "HealingAll"))
		ns.Config:SetUnitValue("player", "health.center", { enabled = true, format = "health:percent" })
		assert.equals("[uf:health:percent]", frame.tags[Row("health"):GetText("center"):GetFrame()])
	end)

	it("colours health by mode, with secret unit values", function()
		local bar = Row("health"):GetBar()
		assert.has_no_error(function()
			frame.Health.UpdateColor(frame, "UNIT_HEALTH", "player")
		end)
		ns.Config:SetUnitValue("player", "health.colorMode", "gradient")
		assert.has_no_error(function()
			frame.Health.UpdateColor(frame, "UNIT_HEALTH", "player")
		end)
		assert.is_true(Mock.IsSecret(bar.bar.__state.color[1]), "gradient colour from the secret curve result")
		ns.Config:SetUnitValue("player", "health.colorMode", "theme")
		frame.Health.UpdateColor(frame, "UNIT_HEALTH", "player")
		assert.same(ns.Config:GetTheme().colors.health, bar.bar.__state.color)
	end)

	it("colours power by power type from the theme", function()
		frame.Power.UpdateColor(frame, "UNIT_DISPLAYPOWER", "player")
		assert.same(ns.Config:GetTheme().colors.mana, Row("power"):GetBar().bar.__state.color)
	end)

	it("fills experience from the XP API", function()
		ns.oUF.elements.UF_Experience.update(frame, "PLAYER_XP_UPDATE")
		local bar = Row("experience"):GetBar()
		assert.equals(1200, bar.bar:GetValue())
		assert.equals(0, bar.segmentsByKey.rested.bar:GetValue())
	end)

	it("waits for combat to end before resizing", function()
		BarsOnly()
		Mock.inCombat = true
		ns.Config:SetUnitValue("player", "width", 300)
		assert.equals(230, frame:GetWidth())
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(300, frame:GetWidth())
	end)
end)

describe("Player frame portrait and castbar", function()
	local ns, frame, uf
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		uf = frame.uf
	end)

	-- Default stack: health 26, power 12, experience 10, castbar row 18, spacing 1.
	local STACK = 26 + 1 + 12 + 1 + 10 + 1 + 18

	it("puts a square portrait spanning all rows on the left", function()
		local portrait = uf:GetPortrait()
		assert.equals(STACK, portrait:GetFrame():GetWidth())
		assert.equals(STACK, portrait:GetFrame():GetHeight())
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 4, -4 }, portrait:GetFrame():GetAnchor("TOPLEFT"))
		-- bars start after portrait + gap 2; the frame grows by that much
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 4 + STACK + 2, -4 }, uf:GetRow("health"):GetFrame():GetAnchor("TOPLEFT"))
		assert.equals(230 + STACK + 2, frame:GetWidth())
		assert.equals(STACK + 8, frame:GetHeight())
	end)

	it("moves the portrait to the right and honours a fixed width", function()
		ns.Config:SetUnitValue("player", "portrait.position", "RIGHT")
		ns.Config:SetUnitValue("player", "portrait.size", 40)
		local portrait = uf:GetPortrait()
		assert.same({ "TOPRIGHT", frame, "TOPRIGHT", -4, -4 }, portrait:GetFrame():GetAnchor("TOPRIGHT"))
		assert.same({ "TOPRIGHT", frame, "TOPRIGHT", -(4 + 40 + 2), -4 }, uf:GetRow("health"):GetFrame():GetAnchor("TOPRIGHT"))
		assert.equals(230 + 42, frame:GetWidth())
	end)

	it("binds the portrait widget for its style", function()
		assert.equals(uf:GetPortrait().model, frame.Portrait)
		ns.Config:SetUnitValue("player", "portrait.mode", "class")
		assert.equals(uf:GetPortrait().texture, frame.Portrait)
		assert.is_true(frame.Portrait.showClass)
		assert.is_true(frame:IsElementEnabled("Portrait"))
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		assert.is_false(frame:IsElementEnabled("Portrait"))
	end)

	it("places the castbar as a bottom or top row", function()
		local castbar = uf:GetCastbar()
		local bottomY = -(4 + 26 + 1 + 12 + 1 + 10 + 1)
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 4 + STACK + 2, bottomY }, castbar:GetFrame():GetAnchor("TOPLEFT"))
		ns.Config:SetUnitValue("player", "castbar.placement", "top")
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 4 + STACK + 2, -4 }, castbar:GetFrame():GetAnchor("TOPLEFT"))
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 4 + STACK + 2, -(4 + 18 + 1) }, uf:GetRow("health"):GetFrame():GetAnchor("TOPLEFT"))
	end)

	it("is opaque only while covering the health bar", function()
		local castbar = uf:GetCastbar()
		assert.equals(0, castbar.backing.__state.colorTexture[4], "transparent as a row")
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		assert.equals(1, castbar.backing.__state.colorTexture[4], "nothing shines through")
		ns.Config:SetUnitValue("player", "castbar.background", { 0.2, 0, 0, 0.3 })
		assert.same({ 0.2, 0, 0, 1 }, castbar.backing.__state.colorTexture, "colour kept, alpha forced")
	end)

	it("covers the health bar when placed over it", function()
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		local castFrame, health = uf:GetCastbar():GetFrame(), uf:GetRow("health"):GetFrame()
		assert.same({ "ALL", health }, castFrame.__state.points[1])
		assert.is_true(castFrame:GetFrameLevel() > health:GetFrameLevel())
		assert.equals(4 + 26 + 1 + 12 + 1 + 10 + 4, frame:GetHeight(), "no extra row")
		-- falls back to a top row when there is no health bar to cover
		ns.Config:SetUnitValue("player", "health.enabled", false)
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 4 + (12 + 1 + 10 + 1 + 18) + 2, -4 }, castFrame:GetAnchor("TOPLEFT"))
	end)

	it("turns the castbar element off with placement off", function()
		assert.is_true(frame:IsElementEnabled("UF_Castbar"))
		ns.Config:SetUnitValue("player", "castbar.placement", "off")
		assert.is_false(frame:IsElementEnabled("UF_Castbar"))
	end)

	it("shows casts from events and stops only on its own cast ID", function()
		local update = ns.oUF.elements.UF_Castbar.update
		ns.oUF.elements.UF_Castbar.enable(frame, "player")
		local castbar = uf:GetCastbar()
		_G.UnitCastingInfo = function()
			return Secret("Fireball"), nil, Secret(1), nil, nil, false, nil, Secret(false), 133, 77
		end
		-- Stop() plays the fade-out animation; count those.
		local function Stops()
			local n = 0
			for _, call in ipairs(castbar.fade.__calls) do
				if call[1] == "Play" then
					n = n + 1
				end
			end
			return n
		end
		update(frame, "UNIT_SPELLCAST_START", "player")
		assert.is_true(castbar:GetFrame():IsShown())
		update(frame, "UNIT_SPELLCAST_FAILED", "player", "guid", 133, 99) -- another cast attempt failed
		assert.equals(0, Stops(), "a failed second attempt must not stop the cast")
		update(frame, "UNIT_SPELLCAST_INTERRUPTED", "player", "guid", 133, "kicker", 77)
		assert.equals(1, Stops())
	end)

	it("hides an idle castbar on refresh", function()
		_G.UnitCastingInfo = function() return nil end
		_G.UnitChannelInfo = function() return nil end
		ns.oUF.elements.UF_Castbar.enable(frame, "player")
		ns.oUF.elements.UF_Castbar.update(frame, "UnitFramesRefresh")
		assert.is_false(uf:GetCastbar():GetFrame():IsShown())
	end)

	it("previews sample values including portrait and cast", function()
		local preview = ns.Units:CreateFrame("player", CreateFrame("Frame"))
		assert.has_no_error(function()
			ns.Units:ShowSample(preview, ns.Units.SAMPLE)
		end)
		assert.is_true(preview:GetCastbar():GetFrame():IsShown())
		assert.equals("Flash of Light", preview:GetCastbar().nameText.frame:GetText())
	end)
end)

describe("Edit Mode positions", function()
	it("uses the default, then the position saved for the active layout", function()
		local ns = Helpers.LoadAddon(true, true)
		local frame = ns.Units.frames.player
		assert.same({ "CENTER", UIParent, "CENTER", -280, -160 }, frame:GetAnchor("CENTER"))

		ns.Config:SetPosition("Healer", "player", "TOPLEFT", 50, -80)
		ns.EditMode.layout = "Healer"
		ns.EditMode:ApplyPosition("player")
		assert.same({ "TOPLEFT", UIParent, "TOPLEFT", 50, -80 }, frame:GetAnchor("TOPLEFT"))

		ns.EditMode.layout = "DPS"
		ns.EditMode:ApplyPosition("player")
		assert.same({ "CENTER", UIParent, "CENTER", -280, -160 }, frame:GetAnchor("CENTER"), "other layouts keep the default")
	end)
end)
