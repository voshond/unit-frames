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
		ns.Config:SetUnitValue("player", "experience.enabled", true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
	end)

	local function Row(key)
		return frame.uf:GetRow(key)
	end

	-- The plain bar stack, without the portrait and castbar.
	local function BarsOnly()
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		ns.Config:SetUnitValue("player", "castbar.enabled", false)
	end

	it("stacks health, power and experience inside the border", function()
		BarsOnly()
		assert.equals(230, frame:GetWidth())
		assert.equals(3 + 26 + 1 + 12 + 1 + 10 + 3, frame:GetHeight())
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3, -3 }, Row("health"):GetFrame():GetAnchor("TOPLEFT"))
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3, -30 }, Row("power"):GetFrame():GetAnchor("TOPLEFT"))
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3, -43 }, Row("experience"):GetFrame():GetAnchor("TOPLEFT"))
	end)

	it("binds rows and segments to oUF elements #shields", function()
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
		assert.equals(3 + 26 + 1 + 10 + 3, frame:GetHeight())
		assert.is_false(frame:IsElementEnabled("Power"))
		assert.is_nil(frame.Power)
		assert.is_nil(frame.tags[Row("power"):GetText("right"):GetFrame()], "its texts are untagged")
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3, -30 }, Row("experience"):GetFrame():GetAnchor("TOPLEFT"))

		ns.Config:SetUnitValue("player", "power.enabled", nil)
		assert.is_true(frame:IsElementEnabled("Power"))
		assert.equals(3 + 26 + 1 + 12 + 1 + 10 + 3, frame:GetHeight())
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
		ns.Config:SetUnitValue("player", "experience.enabled", true)
		ns.Config:SetUnitValue("player", "castbar.enabled", true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		uf = frame.uf
	end)

	-- Enabled stack: health 26, power 12, experience 10, castbar row 18, spacing 1.
	local STACK = 26 + 1 + 12 + 1 + 10 + 1 + 18

	it("puts a square portrait spanning all rows on the left", function()
		local portrait = uf:GetPart("portrait")
		assert.equals(STACK, portrait:GetFrame():GetWidth())
		assert.equals(STACK, portrait:GetFrame():GetHeight())
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3, -3 }, portrait:GetFrame():GetAnchor("TOPLEFT"))
		-- bars start after portrait + gap 2; the frame grows by that much
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3 + STACK + 2, -3 }, uf:GetRow("health"):GetFrame():GetAnchor("TOPLEFT"))
		assert.equals(230 + STACK + 2, frame:GetWidth())
		assert.equals(STACK + 6, frame:GetHeight())
	end)

	it("moves the portrait to the right and honours a fixed width", function()
		ns.Config:SetUnitValue("player", "portrait.position", "RIGHT")
		ns.Config:SetUnitValue("player", "portrait.size", 40)
		local portrait = uf:GetPart("portrait")
		assert.same({ "TOPRIGHT", frame, "TOPRIGHT", -3, -3 }, portrait:GetFrame():GetAnchor("TOPRIGHT"))
		assert.same({ "TOPRIGHT", frame, "TOPRIGHT", -(3 + 40 + 2), -3 }, uf:GetRow("health"):GetFrame():GetAnchor("TOPRIGHT"))
		assert.equals(230 + 42, frame:GetWidth())
	end)

	it("binds the portrait widget for its style", function()
		assert.equals(uf:GetPart("portrait").model, frame.Portrait)
		ns.Config:SetUnitValue("player", "portrait.mode", "class")
		assert.equals(uf:GetPart("portrait").texture, frame.Portrait)
		assert.is_true(frame.Portrait.showClass)
		assert.is_true(frame:IsElementEnabled("Portrait"))
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		assert.is_false(frame:IsElementEnabled("Portrait"))
	end)

	it("places the castbar as a bottom or top row", function()
		local castbar = uf:GetPart("castbar")
		local bottomY = -(3 + 26 + 1 + 12 + 1 + 10 + 1)
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3 + STACK + 2, bottomY }, castbar:GetFrame():GetAnchor("TOPLEFT"))
		ns.Config:SetUnitValue("player", "castbar.placement", "top")
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3 + STACK + 2, -3 }, castbar:GetFrame():GetAnchor("TOPLEFT"))
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3 + STACK + 2, -(3 + 18 + 1) }, uf:GetRow("health"):GetFrame():GetAnchor("TOPLEFT"))
	end)

	it("is opaque only while covering the health bar", function()
		local castbar = uf:GetPart("castbar")
		assert.equals(0, castbar.backing.__state.colorTexture[4], "transparent as a row")
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		assert.equals(1, castbar.backing.__state.colorTexture[4], "nothing shines through")
		ns.Config:SetUnitValue("player", "castbar.background", { 0.2, 0, 0, 0.3 })
		assert.same({ 0.2, 0, 0, 1 }, castbar.backing.__state.colorTexture, "colour kept, alpha forced")
	end)

	it("covers the health bar when placed over it", function()
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		local castFrame, health = uf:GetPart("castbar"):GetFrame(), uf:GetRow("health"):GetFrame()
		assert.same({ "ALL", health }, castFrame.__state.points[1])
		assert.is_true(castFrame:GetFrameLevel() > health:GetFrameLevel())
		assert.equals(3 + 26 + 1 + 12 + 1 + 10 + 3, frame:GetHeight(), "no extra row")
		-- falls back to a top row when there is no health bar to cover
		ns.Config:SetUnitValue("player", "health.enabled", false)
		assert.same({ "TOPLEFT", frame, "TOPLEFT", 3 + (12 + 1 + 10 + 1 + 18) + 2, -3 }, castFrame:GetAnchor("TOPLEFT"))
	end)

	it("turns the castbar element off with its enable toggle", function()
		assert.is_true(frame:IsElementEnabled("UF_Castbar"))
		ns.Config:SetUnitValue("player", "castbar.enabled", false)
		assert.is_false(frame:IsElementEnabled("UF_Castbar"))
	end)

	it("shows casts from events and stops only on its own cast ID", function()
		local update = ns.oUF.elements.UF_Castbar.update
		ns.oUF.elements.UF_Castbar.enable(frame, "player")
		local castbar = uf:GetPart("castbar")
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
		assert.is_false(uf:GetPart("castbar"):GetFrame():IsShown())
	end)

	it("previews sample values including portrait and cast", function()
		local preview = ns.Units:CreateFrame("player", CreateFrame("Frame"))
		assert.has_no_error(function()
			ns.Units:ShowSample(preview, ns.Units.SAMPLE)
		end)
		assert.is_true(preview:GetPart("castbar"):GetFrame():IsShown())
		assert.equals("Flash of Light", preview:GetPart("castbar").nameText.frame:GetText())
	end)
end)

describe("Player buffs and debuffs", function()
	local ns, frame, auras
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		auras = frame.uf:GetPart("auras")
	end)

	local function Container(kind)
		return auras:GetContainer(kind)
	end

	local function Group(kind)
		return Container(kind).__state.groups[kind]
	end

	it("delegates right-click cancellation only for live player buffs", function()
		assert.is_not_nil(ns.Units.frames.player.uf:GetPart("auras"):GetContainer("buffs"))
		for _, unit in ipairs(ns.Units.order) do
			local component = ns.Units.frames[unit].uf:GetPart("auras")
			-- Parts that were never enabled have no live buttons yet.
			for _, kind in ipairs(component:GetContainer("buffs") and { "buffs", "debuffs" } or {}) do
				for _, button in ipairs(component:GetContainer(kind).__state.groups[kind].frames) do
					local expected = unit == "player" and kind == "buffs" and "RightButtonDown" or nil
					assert.equals(expected, button.__state.cancelAuraButtons)
					assert.is_nil(button:GetScript("OnClick"), "Blizzard owns the secure click handler")
					local mouse, clicks
					for _, call in ipairs(button.__calls) do
						if call[1] == "EnableMouse" then mouse = call[2] end
						if call[1] == "RegisterForClicks" then clicks = call[2] end
					end
					assert.is_true(mouse, "live icons retain mouse input and tooltips")
					assert.equals(expected, clicks)
				end
			end
		end
	end)

	it("preserves native cancellation across refreshes, toggles and unit rebinding", function()
		ns.Config:SetUnitValue("player", "auras.buffs.enabled", false)
		ns.Config:SetUnitValue("player", "auras.buffs.enabled", true)
		ns.Config:SetUnitValue("player", "auras.enabled", false)
		ns.Config:SetUnitValue("player", "auras.enabled", true)
		frame.__unit = "vehicle"
		ns.oUF.elements.UF_Auras.update(frame, "UnitFramesRefresh")
		assert.equals("vehicle", Container("buffs"):GetUnit(), "native buttons follow the current unit")
		frame.__unit = "player"
		ns.oUF.elements.UF_Auras.update(frame, "UnitFramesRefresh")
		ns.Config:SetUnitValue("player", "auras.durationPosition", "CENTER")
		assert.is_true(Container("buffs"):IsEnabled())
		assert.equals("player", Container("buffs"):GetUnit())
		for _, button in ipairs(Group("buffs").frames) do
			assert.equals("RightButtonDown", button.__state.cancelAuraButtons)
		end
		assert.is_nil(Group("debuffs").frames[1].__state.cancelAuraButtons)
	end)

	it("configures cancellation when the native pool creates another buff button", function()
		local button = CreateFrame("AuraButton", nil, Container("buffs"), "CustomAuraButtonTemplate")
		Group("buffs").options.initializeFrame(button)
		local cancelToken
		for _, call in ipairs(button.__calls) do
			if call[1] == "SetCancelAuraButtons" then cancelToken = call[2] end
		end
		assert.equals("RightButtonDown", cancelToken)
		assert.is_nil(button:GetScript("OnClick"))
		assert.equals(20, button.ufIconFrame:GetHeight())
	end)

	it("positions buffs above and debuffs below with separate containers", function()
		local buffs, debuffs = Container("buffs"), Container("debuffs")
		assert.same({ "BOTTOMLEFT", frame, "TOPLEFT", 0, 2 }, buffs:GetAnchor("BOTTOMLEFT"))
		assert.same({ "TOPLEFT", frame, "BOTTOMLEFT", 0, -2 }, debuffs:GetAnchor("TOPLEFT"))
		assert.equals("BOTTOMLEFT", buffs.__state.flowAnchor)
		assert.same({ 1, 1 }, buffs.__state.growth)
		assert.same({ 1, -1 }, debuffs.__state.growth)
		assert.equals(frame:GetWidth(), buffs.__state.lineSize)
		assert.equals(frame:GetWidth(), debuffs.__state.lineSize)
		assert.is_true(buffs:IsEnabled())
		assert.is_true(debuffs:IsEnabled())
		assert.equals("HELPFUL", Group("buffs").filter)
		assert.equals("HARMFUL", Group("debuffs").filter)
	end)

	it("gives every icon a themed frame and reserves room for its timer", function()
		for _, kind in ipairs({ "buffs", "debuffs" }) do
			local button = Group(kind).frames[1]
			local size = kind == "buffs" and 20 or 26
			assert.equals(size, button:GetWidth())
			assert.equals(size + 12, button:GetHeight())
			assert.equals(size, button.ufIconFrame:GetHeight(), "the artwork stays square")
			assert.equals(ns.Media:Fetch("border", ns.Config:GetTheme().borderTexture),
				button.ufIconFrame.__state.backdrop.edgeFile)
			assert.same(kind == "debuffs" and { 0, 0, 0, 0 } or ns.Config:GetTheme().borderColor,
				button.ufIconFrame.__state.backdropBorderColor)
			assert.same({ "TOP", button.ufIconFrame, "BOTTOM", 0, -1 }, button.ufTime:GetAnchor("TOP"))
			assert.same({ "TOPLEFT", button.ufIconFrame, "TOPLEFT", 2, -2 }, button.ufIcon:GetAnchor("TOPLEFT"))
		end
		assert.is_false(Group("buffs").frames[1].ufBorder:IsShown())
		assert.is_true(Group("debuffs").frames[1].ufBorder:IsShown())
	end)

	it("keeps buffs on top while placing debuffs on the right, centred", function()
		ns.Config:SetUnitValue("player", "auras.debuffs.position", "right")
		ns.Config:SetUnitValue("player", "auras.debuffs.alignment", "center")
		ns.Config:SetUnitValue("player", "auras.debuffs.offsetX", 5)
		ns.Config:SetUnitValue("player", "auras.debuffs.offsetY", -3)
		local debuffs = Container("debuffs")
		assert.same({ "LEFT", frame, "RIGHT", 7, -3 }, debuffs:GetAnchor("LEFT"))
		assert.equals(AnchorUtil.FlowLayoutAxis.Vertical, debuffs.__state.flowAxis)
		assert.equals(frame:GetHeight(), debuffs.__state.lineSize)
		assert.same({ 1, -1 }, debuffs.__state.growth)
		assert.same({ "BOTTOMLEFT", frame, "TOPLEFT", 0, 2 }, Container("buffs"):GetAnchor("BOTTOMLEFT"))
	end)

	it("supports all four sides, alignments and growth directions", function()
		local sides = {
			top = { "BOTTOM", "TOP", false, 0, 2 },
			bottom = { "TOP", "BOTTOM", false, 0, -2 },
			left = { "RIGHT", "LEFT", true, -2, 0 },
			right = { "LEFT", "RIGHT", true, 2, 0 },
		}
		for side, expected in pairs(sides) do
			for _, alignment in ipairs({ "start", "center", "end" }) do
				for _, growth in ipairs({ "forward", "reverse" }) do
					ns.Config:SetUnitValue("player", "auras.buffs", {
						position = side, alignment = alignment, growth = growth,
					})
					local container = Container("buffs")
					local vertical = expected[3]
					local suffix = alignment == "center" and "" or alignment == "start" and "LEFT" or "RIGHT"
					local prefix = alignment == "center" and "" or alignment == "start" and "TOP" or "BOTTOM"
					local point = vertical and prefix .. expected[1] or expected[1] .. suffix
					local relative = vertical and prefix .. expected[2] or expected[2] .. suffix
					assert.same({ point, frame, relative, expected[4], expected[5] }, container:GetAnchor(point))
					assert.equals(1, container:GetNumPoints())
					local x = vertical and (side == "right" and 1 or -1) or (growth == "forward" and 1 or -1)
					local y = vertical and (growth == "forward" and -1 or 1) or (side == "top" and 1 or -1)
					assert.same({ x, y }, container.__state.growth)
					assert.equals((y == 1 and "BOTTOM" or "TOP") .. (x == 1 and "LEFT" or "RIGHT"),
						container.__state.flowAnchor, "buttons use a corner even when the block is centred")
				end
			end
		end
	end)

	it("applies filters, counts and sizes live and stops disabled containers", function()
		ns.Config:SetUnitValue("player", "auras.buffs.filter", "HELPFUL|PLAYER")
		ns.Config:SetUnitValue("player", "auras.debuffs.max", 8)
		ns.Config:SetUnitValue("player", "auras.buffs.size", 30)
		ns.Config:SetUnitValue("player", "auras.debuffs.enabled", false)
		assert.equals("HELPFUL|PLAYER", Group("buffs").filter)
		assert.equals(8, Group("debuffs").max)
		assert.equals(30, Group("buffs").layout.elementWidth)
		assert.equals(30, Group("buffs").frames[2]:GetWidth())
		assert.is_false(Group("debuffs").enabled)
		assert.is_false(Container("debuffs"):IsEnabled())
		assert.is_false(Container("debuffs"):IsShown())
		assert.is_true(Container("buffs"):IsEnabled())
	end)

	it("allows custom line lengths and keeps room for at least one icon", function()
		ns.Config:SetUnitValue("player", "auras.debuffs.lineSize", 100)
		assert.equals(100, Container("debuffs").__state.lineSize)
		ns.Config:SetUnitValue("player", "auras.debuffs.position", "left")
		assert.equals(100, Container("debuffs").__state.lineSize)
		ns.Config:SetUnitValue("player", "auras.debuffs.lineSize", 1)
		assert.equals(38, Container("debuffs").__state.lineSize, "includes the below-icon timer")
		ns.Config:SetUnitValue("player", "auras.durationPosition", "CENTER")
		assert.equals(26, Container("debuffs").__state.lineSize)
	end)

	it("moves duration text inside without keeping blank space below", function()
		ns.Config:SetUnitValue("player", "auras.durationSize", 16)
		ns.Config:SetUnitValue("player", "auras.countSize", 8)
		ns.Config:SetUnitValue("player", "auras.font", "Arial Narrow")
		ns.Config:SetUnitValue("player", "auras.fontOutline", "THICKOUTLINE")
		for _, position in ipairs({ "CENTER", "TOP", "BOTTOM" }) do
			ns.Config:SetUnitValue("player", "auras.durationPosition", position)
			local button = Group("buffs").frames[1]
			local y = position == "TOP" and -2 or position == "BOTTOM" and 2 or 0
			assert.same({ position, button.ufIconFrame, position, 0, y }, button.ufTime:GetAnchor(position))
			assert.equals(20, button:GetHeight())
			assert.equals(20, Group("buffs").layout.elementHeight)
			assert.same({ ns.Media:Fetch("font", "Arial Narrow"), 16, "THICKOUTLINE" }, button.ufTime.__state.font)
			assert.equals(8, button.ufCount.__state.font[2])
		end
		ns.Config:SetUnitValue("player", "auras.durationPosition", "below")
		assert.equals(38, Group("buffs").layout.elementHeight)
		ns.Config:SetUnitValue("player", "auras.showDuration", false)
		assert.equals(20, Group("buffs").layout.elementHeight)
		assert.is_false(Group("buffs").frames[1].ufTime:IsShown())
	end)

	it("keeps stack text hidden when the engine updates its shown state", function()
		ns.Config:SetUnitValue("player", "auras.showCount", false)
		local button = Group("buffs").frames[1]
		button.ufCount:Show() -- The engine can do this on any aura update.
		assert.is_false(button.ufCountHolder:IsShown())
		ns.Config:SetUnitValue("player", "auras.showCount", true)
		assert.is_true(button.ufCountHolder:IsShown())
	end)

	it("moves timers with the frame enabled when native dimensions are secret", function()
		local originalMixin = BackdropTemplateMixin
		local dimensions = {}
		-- Model BackdropTemplate's Lua arithmetic, which the generic widget
		-- mock otherwise skips. Native aura dimensions may be secret even
		-- when addon access to the buttons is permitted.
		BackdropTemplateMixin = {
			SetupTextureCoordinates = function(geometry)
				dimensions[#dimensions + 1] = {
					geometry:GetWidth() / 8, geometry:GetHeight() / 8,
				}
			end,
		}
		for _, kind in ipairs({ "buffs", "debuffs" }) do
			for _, button in ipairs(Group(kind).frames) do
				local iconFrame = button.ufIconFrame
				iconFrame.GetWidth = function() return Mock.Secret(20) end
				iconFrame.GetHeight = function() return Mock.Secret(20) end
				iconFrame.SetBackdrop = function(self, info)
					self.__state.backdrop = info
					self:SetupTextureCoordinates()
				end
			end
		end
		ns.Config:SetUnitValue("player", "auras.durationPosition", "CENTER")
		local styled = #Group("buffs").frames + #Group("debuffs").frames
		assert.equals(styled, #dimensions, "all existing buttons finish border styling")
		for _, kind in ipairs({ "buffs", "debuffs" }) do
			local size = kind == "buffs" and 20 or 26
			for _, button in ipairs(Group(kind).frames) do
				assert.same({ "CENTER", button.ufIconFrame, "CENTER", 0, 0 }, button.ufTime:GetAnchor("CENTER"))
				assert.equals(size, button:GetHeight())
				assert.is_not_nil(button.ufIconFrame.__state.backdrop)
				assert.is_nil(button.ufIconFrame:GetScript("OnSizeChanged"))
			end
		end
		ns.Config:SetUnitValue("player", "auras.buffs.size", 32)
		assert.same({ 4, 4 }, dimensions[styled + 1], "UVs follow the newly configured size")
		ns.Config:SetUnitValue("player", "auras.durationPosition", "below")
		assert.equals(44, Group("buffs").frames[1]:GetHeight())
		assert.is_not_nil(Group("buffs").frames[1].ufTime:GetAnchor("TOP"))
		BackdropTemplateMixin = originalMixin
	end)

	it("uses a private compact duration formatter for every aura", function()
		local formatter = Group("buffs").frames[1].__state.durationText.options.textFormatter
		local function Setting(name)
			for _, call in ipairs(formatter.__calls) do
				if call[1] == name then return call[2] end
			end
		end
		assert.equals(Enum.SecondsFormatterIntervalWhitespace.StripIgnoreLocale, Setting("SetStripIntervalWhitespace"))
		assert.equals(Enum.SecondsFormatterAbbreviation.OneLetter, Setting("SetDefaultAbbreviation"))
		assert.equals(1, Setting("SetDesiredUnitCount"))
		assert.equals(AuraContainerInbound.GetDefaultAuraDurationFormatter():GetMaxIntervalCurve(), Setting("SetMaxIntervalCurve"))
		for _, kind in ipairs({ "buffs", "debuffs" }) do
			for _, button in ipairs(Group(kind).frames) do
				assert.equals(formatter, button.__state.durationText.options.textFormatter)
			end
		end
	end)

	it("toggles dispel colouring independently of the permanent icon frame", function()
		ns.Config:SetUnitValue("player", "auras.dispelBorder", false)
		local button = Group("debuffs").frames[1]
		assert.is_false(button.ufBorder:IsShown())
		assert.is_not_nil(button.ufIconFrame.__state.backdrop)
		ns.Config:SetUnitValue("player", "auras.border.enabled", false)
		assert.is_nil(button.ufIconFrame.__state.backdrop)
		assert.same({ "TOPLEFT", button.ufIconFrame, "TOPLEFT", 0, 0 }, button.ufIcon:GetAnchor("TOPLEFT"))
	end)

	it("tints all eight themed border pieces instead of drawing a square outline", function()
		local button = Group("debuffs").frames[1]
		assert.equals(8, #button.ufDispelTextures)
		assert.is_nil(button.ufBorder.__state.backdrop.bgFile)
		for _, texture in ipairs(button.ufDispelTextures) do
			assert.equals(ns.Media:Fetch("border", ns.Config:GetTheme().borderTexture), texture:GetTexture())
			assert.same({ AuraUtil.GetAuraBorderColor("Magic"):GetRGBA() }, texture.__state.vertexColor)
			assert.equals(Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
				button.__state.dispelTextures[texture].style)
		end
		assert.equals(0, #Group("buffs").frames[1].ufDispelTextures)
	end)

	-- Natively these rebuild every aura or request relayout even when unchanged.
	it("sends only changed candidate filters, sort and group layout to native containers", function()
		local calls = {}
		for _, kind in ipairs({ "buffs", "debuffs" }) do
			local container = Container(kind)
			for _, method in ipairs({ "SetAuraGroupCandidateFilters", "SetAuraGroupSortMethod", "SetAuraGroupLayout" }) do
				local original = container[method]
				container[method] = function(...)
					calls[#calls + 1] = method
					return original(...)
				end
			end
		end
		ns.Units:Refresh("player")
		ns.Config:SetUnitValue("player", "auras.showCount", false)
		assert.same({}, calls)
		ns.Config:SetUnitValue("player", "auras.buffs.maxDuration", 60)
		assert.same({ "SetAuraGroupCandidateFilters" }, calls)
		assert.same({ maxDuration = 60 }, Group("buffs").candidateFilters)
		calls = {}
		ns.Config:SetUnitValue("player", "auras.debuffs.sort", "default")
		assert.same({ "SetAuraGroupSortMethod" }, calls)
		calls = {}
		ns.Config:SetUnitValue("player", "auras.buffs.size", 28)
		assert.same({ "SetAuraGroupLayout" }, calls)
		assert.equals(28, Group("buffs").layout.elementWidth)
	end)

	-- Each engine registration copies its options and redraws the button.
	it("re-registers dispel textures only when their artwork, size or colours change", function()
		local button = Group("debuffs").frames[1]
		local adds, add = 0, button.AddDispelTypeTexture
		button.AddDispelTypeTexture = function(...) adds = adds + 1; return add(...) end
		local tinted = button.ufDispelTextures[1]
		ns.Units:Refresh("player")
		ns.Config:SetUnitValue("player", "auras.showCount", false)
		assert.equals(0, adds)
		assert.equals(tinted, button.ufDispelTextures[1])
		assert.same({ AuraUtil.GetAuraBorderColor("Magic"):GetRGBA() }, tinted.__state.vertexColor)
		assert.same({ 0, 0, 0, 0 }, button.ufIconFrame.__state.backdropBorderColor,
			"the icon frame border stays hidden under the dispel border")
		ns.Config:SetUnitValue("player", "auras.dispelColors.Curse", { 1, 1, 0, 1 })
		assert.equals(8, adds)
		ns.Config:SetUnitValue("player", "auras.debuffs.size", 30)
		assert.equals(16, adds)
		ns.Config:SetUnitValue("player", "auras.border.size", 6)
		assert.equals(24, adds)
	end)

	it("updates the engine palette and restores the fixed colour when type colouring is off", function()
		local button = Group("debuffs").frames[1]
		local magic, fixed = { 1, 0.4, 0.1, 1 }, { 0.2, 0.8, 0.7, 0.5 }
		ns.Config:SetUnitValue("player", "auras.dispelColors.Magic", magic)
		for _, texture in ipairs(button.ufDispelTextures) do assert.same(magic, texture.__state.vertexColor) end
		ns.Config:SetUnitValue("player", "auras.border.color", fixed)
		assert.same(magic, button.ufDispelTextures[1].__state.vertexColor)
		ns.Config:SetUnitValue("player", "auras.dispelBorder", false)
		assert.same({}, button.__state.dispelTextures)
		assert.same(fixed, button.ufIconFrame.__state.backdropBorderColor)
		ns.Config:SetUnitValue("player", "auras.dispelBorder", true)
		assert.equals(8, #button.ufDispelTextures)
		for _, name in ipairs({ "Magic", "Curse", "Disease", "Poison", "None" }) do
			button:MockUpdateDispelTextures(name)
			assert.same(name == "Magic" and magic or { AuraUtil.GetAuraBorderColor(name):GetRGBA() },
				button.ufDispelTextures[1].__state.vertexColor)
		end
		ns.Config:SetUnitValue("player", "auras.border.border", "None")
		assert.equals(0, #button.ufDispelTextures)
		assert.same({}, button.__state.dispelTextures)
		ns.Config:SetUnitValue("player", "auras.border.border", ns.Config:GetTheme().borderTexture)
		assert.equals(8, #button.ufDispelTextures)
	end)

	it("restyles existing buttons only out of combat", function()
		Mock.inCombat = true
		ns.Config:SetUnitValue("player", "auras.buffs.size", 32)
		assert.equals(20, Group("buffs").frames[1]:GetWidth())
		assert.equals(32, Group("buffs").layout.elementWidth)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(32, Group("buffs").frames[1]:GetWidth())
	end)

	it("defers denied button enumeration and retries at combat end", function()
		local container = Container("buffs")
		local original = container.GetAuraGroupFrameCount
		container.GetAuraGroupFrameCount = function() error("Aura access denied") end
		assert.has_no_error(function()
			ns.Config:SetUnitValue("player", "auras.buffs.size", 31)
		end)
		assert.equals(20, Group("buffs").frames[1]:GetWidth())
		container.GetAuraGroupFrameCount = original
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(31, Group("buffs").frames[1]:GetWidth())
	end)

	it("follows the frame's unit through the UF_Auras element", function()
		assert.is_true(frame:IsElementEnabled("UF_Auras"))
		frame.__unit = "target"
		ns.oUF.elements.UF_Auras.update(frame, "UnitFramesRefresh")
		assert.equals("target", Container("buffs"):GetUnit())
		assert.equals("target", Container("debuffs"):GetUnit())
		ns.Config:SetUnitValue("player", "auras.enabled", false)
		assert.is_false(frame:IsElementEnabled("UF_Auras"))
		assert.is_false(auras:GetFrame():IsShown())
		assert.is_false(Container("buffs"):IsEnabled())
		assert.is_false(Container("debuffs"):IsEnabled())
	end)

	it("releases sample previews and leaves native containers disabled", function()
		local preview = ns.Units:CreateFrame("player", CreateFrame("Frame"))
		ns.Units:ShowSample(preview, ns.Units.SAMPLE)
		local previewAuras = preview:GetPart("auras")
		assert.equals(10, #previewAuras.previewContainers.buffs.ufElements)
		assert.equals(5, #previewAuras.previewContainers.debuffs.ufElements)
		Mock.inCombat = true
		previewAuras:Apply({ buffs = { size = 33 } })
		preview:Release()
		assert.is_false(previewAuras:GetContainer("buffs"):IsEnabled())
		assert.is_false(previewAuras:GetContainer("debuffs"):IsEnabled())
		assert.is_false(previewAuras:GetContainer("buffs"):IsShown())
		assert.is_false(previewAuras:GetContainer("debuffs"):IsShown())
		assert.is_false(previewAuras.previewContainers.buffs:IsShown())
		assert.is_false(previewAuras.previewContainers.debuffs:IsShown())
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(20, previewAuras:GetContainer("buffs").__state.groups.buffs.frames[1]:GetWidth(),
			"a released preview is removed from deferred restyling")
	end)
end)

describe("Aura samples", function()
	local ns, preview, auras
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		preview = ns.Units:CreateFrame("player", CreateFrame("Frame"))
		auras = preview:GetPart("auras")
		ns.Units:ShowSample(preview, ns.Units.SAMPLE)
	end)

	local function Sample(kind)
		return auras.previewContainers[kind]
	end

	it("keeps sample icons non-interactive through live and sample switches", function()
		for _, unit in ipairs({ "player", "target", "player" }) do
			auras:SetUnit(unit)
			assert.equals(unit, auras:GetContainer("buffs"):GetUnit())
			auras:ShowSample(ns.Units.SAMPLE)
			assert.is_false(auras:GetContainer("buffs"):IsEnabled())
			for _, kind in ipairs({ "buffs", "debuffs" }) do
				for _, button in ipairs(Sample(kind).ufElements) do
					local mouse
					for _, call in ipairs(button.__calls) do
						assert.is_false(call[1] == "SetCancelAuraButtons" or call[1] == "RegisterForClicks")
						if call[1] == "EnableMouse" then mouse = call[2] end
					end
					assert.is_false(mouse)
					assert.is_nil(button:GetScript("OnClick"))
				end
			end
		end
	end)

	it("shows timed, permanent, stacked and coloured auras without live data", function()
		assert.is_false(auras:GetContainer("buffs"):IsEnabled())
		assert.is_false(auras:GetContainer("debuffs"):IsEnabled())
		assert.is_nil(auras:GetContainer("buffs"):GetUnit())
		assert.is_true(ns.Units.frames.player.uf:GetPart("auras"):GetContainer("buffs"):IsEnabled(), "live frame is unaffected")
		assert.equals(ns.Units.SAMPLE.buffs[1].icon, Sample("buffs").ufElements[1].ufIcon:GetTexture())
		assert.equals("3m", Sample("buffs").ufElements[2].ufTime:GetText())
		assert.equals(3, Sample("buffs").ufElements[7].ufCount:GetText())
		assert.equals("", Sample("buffs").ufElements[8].ufTime:GetText())
		assert.is_false(Sample("buffs").ufElements[8].ufCooldown:IsShown())
		assert.is_true(Sample("buffs").ufElements[1].ufCooldown.__state.paused)
		for i, aura in ipairs(ns.Units.SAMPLE.debuffs) do
			local button = Sample("debuffs").ufElements[i]
			assert.same({ AuraUtil.GetAuraBorderColor(aura.dispelName or "None"):GetRGBA() }, button.ufDispelTextures[1].__state.vertexColor)
		end
	end)

	it("uses the configured placement and restyles samples immediately", function()
		auras:Apply({ durationPosition = "CENTER", durationSize = 16,
			buffs = { size = 32 }, debuffs = { position = "right", alignment = "center" } })
		local button = Sample("buffs").ufElements[1]
		assert.equals(32, button:GetHeight())
		assert.equals(16, button.ufTime.__state.font[2])
		assert.same({ "CENTER", button.ufIconFrame, "CENTER", 0, 0 }, button.ufTime:GetAnchor("CENTER"))
		assert.same({ "LEFT", preview:GetFrame(), "RIGHT", 2, 0 }, Sample("debuffs"):GetAnchor("LEFT"))
		assert.equals(AnchorUtil.FlowLayoutAxis.Vertical, Sample("debuffs").ufFlow.axis)
		auras:Apply({ showDuration = false, showCount = false, border = { enabled = false } })
		assert.equals(20, button:GetHeight())
		assert.is_false(button.ufTime:IsShown())
		assert.is_false(button.ufCountHolder:IsShown())
		assert.is_nil(button.ufIconFrame.__state.backdrop)
	end)

	it("previews custom type colours on the full themed frame and can use a fixed colour", function()
		local palette = {
			Magic = { 1, 0.5, 0, 1 }, Curse = { 0, 1, 0.5, 1 }, Disease = { 0.5, 0, 1, 1 },
			Poison = { 0.5, 1, 0, 1 }, None = { 0, 0.5, 1, 1 },
		}
		local fixed = { 0.8, 0.7, 0.6, 1 }
		auras:Apply({ dispelColors = palette, border = { color = fixed } })
		for i, aura in ipairs(ns.Units.SAMPLE.debuffs) do
			local button = Sample("debuffs").ufElements[i]
			assert.equals(8, #button.ufDispelTextures)
			for _, texture in ipairs(button.ufDispelTextures) do
				assert.same(palette[aura.dispelName or "None"], texture.__state.vertexColor)
				assert.equals(ns.Media:Fetch("border", auras.resolved.border.border), texture:GetTexture())
			end
		end
		auras:Apply({ dispelBorder = false, border = { color = fixed } })
		for _, kind in ipairs({ "buffs", "debuffs" }) do
			for _, button in ipairs(Sample(kind).ufElements) do
				assert.is_false(button.ufBorder:IsShown())
				assert.same(fixed, button.ufIconFrame.__state.backdropBorderColor)
			end
		end
		auras:Apply({ dispelColors = palette })
		assert.same(palette.Magic, Sample("debuffs").ufElements[1].ufDispelTextures[1].__state.vertexColor)
	end)

	it("honours filters, maximum counts and disabled groups", function()
		auras:Apply({ buffs = { max = 2 }, debuffs = { filter = "HARMFUL|PLAYER" } })
		assert.equals(2, #Sample("buffs").ufElements)
		assert.equals(2, #Sample("debuffs").ufElements)
		auras:Apply({ buffs = { filter = "HELPFUL|RAID" }, debuffs = { filter = "HARMFUL|RAID" } })
		assert.equals(3, #Sample("buffs").ufElements)
		assert.equals(4, #Sample("debuffs").ufElements)
		auras:Apply({ debuffs = { enabled = false } })
		assert.equals(0, #Sample("debuffs").ufElements)
		assert.is_false(Sample("debuffs"):IsShown())
	end)

	it("hides empty groups and reuses sample buttons", function()
		local button = Sample("buffs").ufElements[1]
		auras:ShowSample({ buffs = {}, debuffs = {} })
		assert.equals(0, #Sample("buffs").ufElements)
		assert.is_false(button:IsShown())
		auras:ShowSample(ns.Units.SAMPLE)
		assert.equals(button, Sample("buffs").ufElements[1])
		assert.is_true(button:IsShown())
	end)

	it("restyles ordinary sample buttons under combat restrictions", function()
		Mock.inCombat = true
		auras:GetContainer("buffs").GetAuraGroupFrameCount = function() error("Aura access denied") end
		auras:Apply({ durationPosition = "CENTER", buffs = { size = 34 } })
		assert.equals(34, Sample("buffs").ufElements[1]:GetHeight())
	end)

	it("can return to live unit data", function()
		auras:SetUnit("target")
		assert.is_nil(auras.previewData)
		assert.is_false(Sample("buffs"):IsShown())
		assert.is_false(Sample("debuffs"):IsShown())
		assert.is_true(auras:GetContainer("buffs"):IsEnabled())
		assert.equals("target", auras:GetContainer("buffs"):GetUnit())
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
