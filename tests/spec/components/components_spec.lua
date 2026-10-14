local Helpers = require("helpers")
local Mock = Helpers.Mock

local HEALTH_SEGMENTS = {
	{ key = "heal", mode = "append", colorInherit = "colors.heal" },
	{ key = "absorb", mode = "append", colorInherit = "colors.absorb" },
	{ key = "healAbsorb", mode = "inset", colorInherit = "colors.healAbsorb" },
}

-- Snapshot of the visible state of a bar, to compare re-applies.
local function Snapshot(bar)
	local s = bar.bar.__state
	local out = {
		texture = s.texture, orientation = s.orientation, reverse = s.reverseFill,
		color = s.color, bgShown = bar.bg.__state.shown, segments = {},
	}
	for _, seg in ipairs(bar.segments) do
		local ss = seg.bar.__state
		out.segments[seg.key] = { shown = ss.shown, reverse = ss.reverseFill, points = #ss.points, width = ss.width }
	end
	return out
end

describe("Bar", function()
	local ns, C, parent
	before_each(function()
		ns = Helpers.LoadAddon(true)
		C = ns.Components
		parent = CreateFrame("Frame")
	end)

	it("resolves the texture from the theme through LibSharedMedia", function()
		local bar = C.Bar:New(parent, {})
		assert.equals([[Interface\TargetingFrame\UI-StatusBar]], bar.bar.__state.texture)
	end)

	it("chains append segments and pins inset segments to the fill end #shields", function()
		local bar = C.Bar:New(parent, {}, { segments = HEALTH_SEGMENTS })
		local fill = bar.bar:GetStatusBarTexture()
		local heal = bar.segmentsByKey.heal.bar
		local absorb = bar.segmentsByKey.absorb.bar
		local healAbsorb = bar.segmentsByKey.healAbsorb.bar

		assert.same({ "TOPLEFT", fill, "TOPRIGHT", 0, 0 }, heal:GetAnchor("TOPLEFT"))
		assert.same({ "TOPLEFT", heal:GetStatusBarTexture(), "TOPRIGHT", 0, 0 }, absorb:GetAnchor("TOPLEFT"))
		assert.same({ "TOPRIGHT", fill, "TOPRIGHT", 0, 0 }, healAbsorb:GetAnchor("TOPRIGHT"))
		assert.is_false(heal.__state.reverseFill)
		assert.is_true(healAbsorb.__state.reverseFill, "inset grows back into the fill")
	end)

	it("skips disabled segments in the chain #shields", function()
		local bar = C.Bar:New(parent, { segments = { heal = { enabled = false } } }, { segments = HEALTH_SEGMENTS })
		local absorb = bar.segmentsByKey.absorb.bar
		assert.is_false(bar.segmentsByKey.heal.bar:IsShown())
		assert.same({ "TOPLEFT", bar.bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0 }, absorb:GetAnchor("TOPLEFT"))
	end)

	it("lays segments out for reverse and vertical fills", function()
		local bar = C.Bar:New(parent, { reverseFill = true }, { segments = HEALTH_SEGMENTS })
		local heal = bar.segmentsByKey.heal.bar
		assert.same({ "TOPRIGHT", bar.bar:GetStatusBarTexture(), "TOPLEFT", 0, 0 }, heal:GetAnchor("TOPRIGHT"))
		assert.is_true(heal.__state.reverseFill)

		bar:Apply({ orientation = "VERTICAL" })
		assert.same({ "BOTTOMLEFT", bar.bar:GetStatusBarTexture(), "TOPLEFT", 0, 0 }, heal:GetAnchor("BOTTOMLEFT"))
		assert.equals("VERTICAL", heal.__state.orientation)
	end)

	it("sizes segments to the full bar length #shields", function()
		local bar = C.Bar:New(parent, {}, { segments = HEALTH_SEGMENTS })
		bar.bar:SetSize(200, 20)
		assert.equals(200, bar.segmentsByKey.absorb.bar:GetWidth())
		bar:Apply({ orientation = "VERTICAL" })
		bar.bar:SetSize(20, 120)
		assert.equals(120, bar.segmentsByKey.absorb.bar:GetHeight())
	end)

	it("passes secret values straight to the widgets", function()
		local bar = C.Bar:New(parent, {}, { segments = HEALTH_SEGMENTS })
		local cur, max, absorb = Secret(500), Secret(1000), Secret(100)
		assert.has_no_error(function()
			bar:SetRange(0, max)
			bar:SetValue(cur)
			bar:SetSegmentValue("absorb", absorb)
			bar:SetColor(Secret(1), Secret(0), Secret(0))
			bar:Apply()
		end)
		assert.equals(cur, bar.bar:GetValue())
		assert.equals(absorb, bar.segmentsByKey.absorb.bar:GetValue())
		local _, segMax = bar.segmentsByKey.heal.bar:GetMinMaxValues()
		assert.equals(max, segMax)
	end)

	it("anchors the spark and sizes segments without passing secret dimensions to size setters", function()
		local bar = C.Bar:New(parent, {}, { segments = HEALTH_SEGMENTS })
		local width, height = Secret(200), Secret(20)
		for _, orientation in ipairs({ "HORIZONTAL", "VERTICAL", "HORIZONTAL" }) do
			for _, reverse in ipairs({ false, true }) do
				for _, spark in ipairs({ false, true }) do
					assert.has_no_error(function()
						bar:Apply({ orientation = orientation, reverseFill = reverse, spark = spark })
						bar.bar:SetSize(200, 20)
						Mock.SetEngineSize(bar.bar, width, height)
						bar:Apply()
					end)
					local horizontal = orientation == "HORIZONTAL"
					assert.equals(12, horizontal and bar.spark:GetWidth() or bar.spark:GetHeight())
					assert.equals(1, bar.spark:GetScale())
					assert.equals(spark, bar.spark:IsShown())
					local fill = bar.bar:GetStatusBarTexture()
					local edge = C.Bar.LAYOUT[orientation][reverse].spark
					if horizontal then
						assert.same({ 0, 1, 0, 1 }, bar.spark.__state.texCoords)
						assert.same({ "TOP", fill, "TOP" .. edge, 0, 6 }, bar.spark:GetAnchor("TOP"))
						assert.same({ "BOTTOM", fill, "BOTTOM" .. edge, 0, -6 }, bar.spark:GetAnchor("BOTTOM"))
					else
						assert.same({ 0, 1, 1, 1, 0, 0, 1, 0 }, bar.spark.__state.texCoords)
						assert.same({ "LEFT", fill, edge .. "LEFT", -6, 0 }, bar.spark:GetAnchor("LEFT"))
						assert.same({ "RIGHT", fill, edge .. "RIGHT", 6, 0 }, bar.spark:GetAnchor("RIGHT"))
					end
					for _, call in ipairs(bar.spark.__calls) do
						assert.is_false(call[1] == "SetRotation", "spark artwork rotates within its bounds")
					end
					for _, seg in ipairs(bar.segments) do
						assert.equals(horizontal and 200 or 20, horizontal and seg.bar:GetWidth() or seg.bar:GetHeight(),
							"segments keep their last plain length")
					end
				end
			end
		end
	end)

	it("uses the client's smoothing when enabled", function()
		local bar = C.Bar:New(parent, { smooth = true })
		bar:SetValue(5)
		assert.equals(Enum.StatusBarInterpolation.ExponentialEaseOut, bar.bar.__state.interpolation)
		bar:Apply({ smooth = false })
		bar:SetValue(6)
		assert.is_nil(bar.bar.__state.interpolation)
	end)

	it("is idempotent when applied twice", function()
		local bar = C.Bar:New(parent, { border = { enabled = true } }, { segments = HEALTH_SEGMENTS })
		bar.bar:SetSize(200, 20)
		local first = Snapshot(bar)
		bar:Apply()
		assert.same(first, Snapshot(bar))
	end)

	it("keeps a data colour across re-styling until cleared", function()
		local bar = C.Bar:New(parent, {})
		bar:SetColor(0.1, 0.2, 0.3, 1)
		bar:Apply({ texture = "Solid" })
		assert.same({ 0.1, 0.2, 0.3, 1 }, bar.bar.__state.color)
		bar:ClearColor()
		assert.same(ns.Config:GetTheme().colors.health, bar.bar.__state.color)
	end)

	it("restyles live when the theme changes", function()
		local bar = C.Bar:New(parent, {})
		ns.Config:SetThemeValue("barTexture", "Solid")
		assert.equals([[Interface\Buttons\WHITE8X8]], bar.bar.__state.texture)
	end)

	it("adds the border inside the root frame", function()
		local bar = C.Bar:New(parent, { border = { enabled = true, padding = 5 } })
		assert.equals([[Interface\Tooltips\UI-Tooltip-Border]], bar.frame.__state.backdrop.edgeFile)
		assert.same({ "TOPLEFT", bar.frame, "TOPLEFT", 5, -5 }, bar.bar:GetAnchor("TOPLEFT"))
		bar:Apply({ border = { enabled = false } })
		assert.is_nil(bar.frame.__state.backdrop)
	end)

	it("toggles on and off", function()
		local bar = C.Bar:New(parent, { enabled = false })
		assert.is_false(bar.frame:IsShown())
		bar:Apply({ enabled = true })
		assert.is_true(bar.frame:IsShown())
	end)
end)

describe("Text", function()
	local C, parent
	before_each(function()
		C = Helpers.LoadAddon(true).Components
		parent = CreateFrame("Frame")
	end)

	it("applies the theme font and normalises outline flags", function()
		local text = C.Text:New(parent, { outline = "NONE" })
		local font = text.frame.__state.font
		assert.equals(11, font[2])
		assert.equals("", font[3])
	end)

	it("falls back to the default font when a font can't be set", function()
		local text = C.Text:New(parent, {})
		local calls = 0
		local original = text.frame.SetFont
		text.frame.SetFont = function(self, path, ...)
			calls = calls + 1
			if calls == 1 then
				return false
			end
			return original(self, path, ...)
		end
		text:Apply({ font = "Missing" })
		assert.equals(2, calls)
	end)

	it("accepts secret text", function()
		local text = C.Text:New(parent, {})
		local secret = Secret("name")
		assert.has_no_error(function()
			text:SetText(secret)
			text:SetFormattedText("%s / %s", Secret(1), Secret(2))
		end)
		assert.is_true(Mock.IsSecret(text.frame:GetText()))
	end)
end)

describe("Castbar", function()
	local ns, C, parent
	before_each(function()
		ns = Helpers.LoadAddon(true)
		C = ns.Components
		parent = CreateFrame("Frame")
	end)

	local function NewCastbar(config)
		local castbar = C.Castbar:New(parent, config or {})
		castbar:SetSize(200, 20)
		return castbar
	end

	it("stays hidden until a cast starts", function()
		local castbar = NewCastbar()
		castbar.frame:Hide()
		castbar:Apply()
		assert.is_false(castbar.frame:IsShown())
		castbar:Start({ name = "Fireball", duration = C_DurationUtil.CreateDuration() })
		assert.is_true(castbar.frame:IsShown())
	end)

	it("drives fill and time text from the duration object", function()
		local castbar = NewCastbar()
		local duration = C_DurationUtil.CreateDuration()
		castbar:Start({ name = "Drain Life", channel = true, duration = duration })
		local timer = castbar:GetBar().bar.__state.timer
		assert.equals(duration, timer.duration)
		assert.equals(Enum.StatusBarTimerDirection.RemainingTime, timer.direction)
		assert.is_not_nil(castbar.timeBinding)
	end)

	it("colours by cast type and handles a secret notInterruptible flag", function()
		local castbar = NewCastbar()
		local theme = ns.Config:GetTheme().colors
		castbar:Start({ name = "Frostbolt", duration = C_DurationUtil.CreateDuration() })
		assert.same(theme.cast, castbar:GetBar().bar.__state.color)
		castbar:Start({ name = "Frostbolt", notInterruptible = true, duration = C_DurationUtil.CreateDuration() })
		assert.same(theme.nonInterruptible, castbar:GetBar().bar.__state.color)
		assert.has_no_error(function()
			castbar:Start({ name = Secret("x"), notInterruptible = Secret(true), duration = C_DurationUtil.CreateDuration() })
		end)
	end)

	it("aligns cast time across the bar and relayouts when spell name is toggled", function()
		local castbar = NewCastbar()
		local duration = C_DurationUtil.CreateDuration()
		castbar:Start({ name = Secret("Frostbolt"), duration = duration })
		local time = castbar.timeText:GetFrame()
		local host = castbar:GetBar():GetTextParent()
		for _, alignment in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
			castbar:Apply({ name = { enabled = false }, time = { justifyH = alignment } })
			castbar:Apply()
			assert.same({ "LEFT", host, "LEFT", 4, 0 }, time:GetAnchor("LEFT"))
			assert.same({ "RIGHT", host, "RIGHT", -4, 0 }, time:GetAnchor("RIGHT"))
			local appliedAlignment
			for _, call in ipairs(time.__calls) do
				if call[1] == "SetJustifyH" then appliedAlignment = call[2] end
			end
			assert.equals(alignment, appliedAlignment)
			assert.equals(2, time:GetNumPoints())
			castbar:Apply({ name = { enabled = true }, time = { justifyH = alignment } })
			local offset = alignment == "LEFT" and 4 or alignment == "RIGHT" and -4 or 0
			assert.same({ alignment, host, alignment, offset, 0 }, time:GetAnchor(alignment))
			assert.equals(1, time:GetNumPoints())
			local name = castbar.nameText:GetFrame()
			if alignment == "LEFT" then
				assert.same({ "LEFT", time, "RIGHT", 4, 0 }, name:GetAnchor("LEFT"))
			else
				assert.same({ "RIGHT", time, "LEFT", -4, 0 }, name:GetAnchor("RIGHT"))
			end
		end
		assert.equals(duration, castbar:GetBar().bar.__state.timer.duration)
	end)

	it("shows the result when stopped", function()
		local castbar = NewCastbar()
		castbar:Start({ name = "Fireball", duration = C_DurationUtil.CreateDuration() })
		castbar:Stop("interrupted")
		local bar = castbar:GetBar().bar
		assert.equals(1, bar:GetValue())
		assert.same(ns.Config:GetTheme().colors.castFailed, bar.__state.color)
		assert.equals("Interrupted", castbar.nameText.frame:GetText())
	end)

	it("puts icon and bar inside its own border, icon left or right", function()
		local castbar = NewCastbar() -- 200 x 20, border padding 3
		local barFrame = castbar:GetBar().frame
		assert.is_not_nil(castbar.frame.__state.backdrop, "the castbar frame carries the border")
		assert.same({ "TOPLEFT", castbar.frame, "TOPLEFT", 3, -3 }, castbar.icon:GetAnchor("TOPLEFT"))
		assert.equals(14, castbar.icon:GetWidth(), "square icon filling the inner height")
		assert.same({ "TOPLEFT", castbar.icon, "TOPRIGHT", 1, 0 }, barFrame:GetAnchor("TOPLEFT"))
		assert.same({ "BOTTOMRIGHT", castbar.frame, "BOTTOMRIGHT", -3, 3 }, barFrame:GetAnchor("BOTTOMRIGHT"))

		castbar:Apply({ icon = { position = "RIGHT" } })
		assert.same({ "TOPRIGHT", castbar.frame, "TOPRIGHT", -3, -3 }, castbar.icon:GetAnchor("TOPRIGHT"))
		assert.same({ "BOTTOMRIGHT", castbar.icon, "BOTTOMLEFT", -1, 0 }, barFrame:GetAnchor("BOTTOMRIGHT"))

		castbar:Apply({ icon = { enabled = false } })
		assert.is_false(castbar.icon:IsShown())
		assert.same({ "TOPLEFT", castbar.frame, "TOPLEFT", 3, -3 }, barFrame:GetAnchor("TOPLEFT"))

		castbar:Apply({ icon = { enabled = false }, border = { enabled = false } })
		assert.is_nil(castbar.frame.__state.backdrop)
		assert.same({ "TOPLEFT", castbar.frame, "TOPLEFT", 0, 0 }, barFrame:GetAnchor("TOPLEFT"))
	end)

	it("passes group defaults to its bar (spark on, no own border)", function()
		local castbar = NewCastbar()
		local barResolved = castbar:GetBar().resolved
		assert.is_false(barResolved.border.enabled)
		assert.is_true(barResolved.spark)
		castbar:Apply({ bar = { spark = false } })
		assert.is_false(castbar:GetBar().resolved.spark)
		assert.is_false(castbar:GetBar().resolved.smooth, "other defaults stay")
	end)

	it("refreshes a castbar with secret status bar dimensions", function()
		local castbar = NewCastbar()
		assert.has_no_error(function()
			Mock.SetEngineSize(castbar:GetBar().bar, Secret(180), Secret(14))
			castbar:Apply()
			castbar:Apply({ bar = { spark = false } })
			castbar:Apply({ bar = { spark = true } })
		end)
	end)
end)

describe("Backdrop", function()
	it("uses the chamfered tooltip border from the theme", function()
		local ns = Helpers.LoadAddon(true)
		local backdrop = ns.Components.Backdrop:New(CreateFrame("Frame"), {})
		local info = backdrop.frame.__state.backdrop
		assert.equals([[Interface\Tooltips\UI-Tooltip-Border]], info.edgeFile)
		assert.equals(12, info.edgeSize)
		assert.same({ 0.5, 0.5, 0.5, 1 }, backdrop.frame.__state.backdropBorderColor)
	end)

	-- BackdropTemplate rebuilds its whole nine-slice layout for any other table.
	it("passes equal settings as the same info table so BackdropTemplate skips rebuilding", function()
		local ns = Helpers.LoadAddon(true)
		local Backdrop = ns.Components.Backdrop
		local a = Backdrop:New(CreateFrame("Frame"), {})
		local b = Backdrop:New(CreateFrame("Frame"), {})
		local info = a.frame.__state.backdrop
		a:Apply({})
		assert.equals(info, a.frame.__state.backdrop)
		assert.equals(info, b.frame.__state.backdrop)
		a:Apply({ size = 8 })
		assert.is_true(info ~= a.frame.__state.backdrop)
		assert.equals(8, a.frame.__state.backdrop.edgeSize)
		assert.equals(12, info.edgeSize, "shared info is never modified")
		a:Apply({ enabled = false })
		assert.is_nil(a.frame.__state.backdrop)
		a:Apply({})
		assert.equals(info, a.frame.__state.backdrop, "re-enabling reapplies the cleared backdrop")
	end)

	it("recomputes fixed-size texture coordinates when only the size changes", function()
		local ns = Helpers.LoadAddon(true)
		local Backdrop = ns.Components.Backdrop
		local frame = CreateFrame("Frame", nil, nil, "BackdropTemplate")
		local cfg = ns.Schema.Resolve(Backdrop.schema, {}, ns.Config:GetTheme())
		local info = Backdrop.ApplyToFixedSize(frame, cfg, 24, 24)
		assert.equals(info, frame.__state.backdrop)
		frame.__state.backdropRepeat = nil
		assert.equals(info, Backdrop.ApplyToFixedSize(frame, cfg, 24, 24))
		assert.is_nil(frame.__state.backdropRepeat, "unchanged backdrop and size do no UV work")
		Backdrop.ApplyToFixedSize(frame, cfg, 48, 36)
		assert.same({ 2, 1 }, frame.__state.backdropRepeat)
		cfg.enabled = false
		assert.is_nil(Backdrop.ApplyToFixedSize(frame, cfg, 60, 60))
	end)
end)
