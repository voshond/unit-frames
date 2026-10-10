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

	it("stacks health, power and experience inside the border", function()
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
		assert.equals("[uf:name]", frame.tags[Row("health"):GetText("left"):GetFrame()])
		assert.equals("[uf:health:value]", frame.tags[Row("health"):GetText("right"):GetFrame()])
		assert.is_nil(frame.tags[Row("health"):GetText("center"):GetFrame()])
		assert.equals("[uf:xp:value:percent]", frame.tags[Row("experience"):GetText("center"):GetFrame()])
	end)

	it("collapses a switched-off row and disables its element", function()
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
		Mock.inCombat = true
		ns.Config:SetUnitValue("player", "width", 300)
		assert.equals(230, frame:GetWidth())
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(300, frame:GetWidth())
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
