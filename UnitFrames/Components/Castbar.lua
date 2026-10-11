local _, ns = ...
local Util = ns.Util
local Bar, Text, Backdrop = ns.Components.Bar, ns.Components.Text, ns.Components.Backdrop

--[[
Cast bar: one bordered frame holding the spell icon (left or right) and the
bar right next to it, with spell name and remaining time on the bar.

The fill and the time text are driven by the engine from a Duration object
(StatusBar:SetTimerDuration + DurationTextBinding), the same approach oUF uses,
so casts with secret timings work without any OnUpdate maths.

Data API:
  :Start({ name, icon, duration, channel, notInterruptible })
  :Stop("success" | "failed" | "interrupted", text?)
  :Preview({ name, icon, channel, notInterruptible }, progress, timeText)  static, for styling
]]
local Castbar = ns.Component:Extend("Castbar")

Castbar.ICON_POSITIONS = {
	{ "LEFT", "Left" },
	{ "RIGHT", "Right" },
}

local function Color(key, label, inherit)
	return { key = key, type = "color", label = label, inherit = inherit }
end

function Castbar.BuildSchema()
	return {
		{ key = "enabled", type = "toggle", label = "Enabled", default = true },
		{ key = "border", type = "group", label = "Border", schema = ns.Util.Copy(Backdrop.schema),
			defaults = { enabled = true, padding = 3 } },
		{ key = "icon", type = "group", label = "Icon", schema = {
			{ key = "enabled", type = "toggle", label = "Enabled", default = true },
			{ key = "position", type = "select", label = "Position", values = Castbar.ICON_POSITIONS, default = "LEFT" },
			{ key = "gap", type = "range", label = "Gap", min = 0, max = 10, step = 1, default = 1 },
		} },
		{ key = "bar", type = "group", label = "Bar", schema = Bar.BuildSchema({ colorInherit = "colors.cast" }),
			defaults = { spark = true, smooth = false } },
		{ key = "name", type = "group", label = "Spell name", schema = Text.BuildSchema(), defaults = { justifyH = "LEFT" } },
		{ key = "time", type = "group", label = "Time", schema = Text.BuildSchema(), defaults = { justifyH = "RIGHT" } },
		{ key = "colors", type = "group", label = "Colours", schema = {
			Color("cast", "Cast", "colors.cast"),
			Color("channel", "Channel", "colors.channel"),
			Color("nonInterruptible", "Not interruptible", "colors.nonInterruptible"),
			Color("failed", "Failed / interrupted", "colors.castFailed"),
			Color("success", "Succeeded", "colors.castSuccess"),
		} },
		{ key = "background", type = "color", label = "Background", default = { 0, 0, 0, 0 },
			tooltip = "Fills the castbar behind icon and bar. Fully opaque while it covers another bar." },
		{ key = "holdTime", type = "range", label = "Hold after finish (s)", min = 0, max = 2, step = 0.1, default = 0.4 },
		{ key = "fadeTime", type = "range", label = "Fade out (s)", min = 0, max = 2, step = 0.1, default = 0.3 },
	}
end

local timeFormatter
local function TimeFormatter()
	if not timeFormatter then
		timeFormatter = C_StringUtil.CreateSecondsFormatter()
		timeFormatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
		timeFormatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
		timeFormatter:SetMillisecondsThreshold(60)
	end
	return timeFormatter
end

function Castbar:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")

	-- Lowest layer: keeps whatever is behind the castbar from showing through.
	self.backing = self.frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	self.backing:SetAllPoints(self.frame)

	self.icon = self.frame:CreateTexture(nil, "ARTWORK")
	self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	self.barComp = self:Own(Bar:New(self.frame, {}, { colorInherit = "colors.cast" }))
	local textParent = self.barComp:GetTextParent()
	self.nameText = self:Own(Text:New(textParent, {}))
	self.timeText = self:Own(Text:New(textParent, {}))

	self.fade = self.frame:CreateAnimationGroup()
	local alpha = self.fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0)
	self.fadeAlpha = alpha
	self.fade:SetScript("OnFinished", function()
		self.frame:Hide()
		self.frame:SetAlpha(1)
	end)

	self.frame:SetScript("OnSizeChanged", function()
		self:LayoutParts()
	end)
end

function Castbar:OnApply(cfg)
	Backdrop.ApplyTo(self.frame, cfg.border)
	self:UpdateBacking()
	self:ApplyChild(self.barComp, "bar")
	self:ApplyChild(self.nameText, "name")
	self:ApplyChild(self.timeText, "time")
	self.fadeAlpha:SetStartDelay(cfg.holdTime)
	self.fadeAlpha:SetDuration(math.max(cfg.fadeTime, 0.01))
	self:LayoutParts()
end

function Castbar:LayoutParts()
	local cfg = self.resolved
	if not cfg then
		return
	end
	-- Icon and bar share the area inside the border.
	local pad = cfg.border.enabled and cfg.border.padding or 0
	local size = math.max(self.frame:GetHeight() - 2 * pad, 1)
	local icon, bar, frame = self.icon, self.barComp, self.frame
	icon:ClearAllPoints()
	bar:ClearAllPoints()
	if cfg.icon.enabled then
		icon:SetSize(size, size)
		icon:Show()
		if cfg.icon.position == "LEFT" then
			icon:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
			bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", cfg.icon.gap, 0)
			bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
		else
			icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -pad)
			bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
			bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", -cfg.icon.gap, 0)
		end
	else
		icon:Hide()
		bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
		bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
	end

	local textParent = bar:GetTextParent()
	local name, time = self.nameText, self.timeText
	time:ClearAllPoints()
	time:SetPoint("RIGHT", textParent, "RIGHT", -4, 0)
	name:ClearAllPoints()
	name:SetPoint("LEFT", textParent, "LEFT", 4, 0)
	if time:IsEnabled() then
		name:SetPoint("RIGHT", time:GetFrame(), "LEFT", -4, 0)
	else
		name:SetPoint("RIGHT", textParent, "RIGHT", -4, 0)
	end
end

function Castbar:OnRelease()
	self.fade:Stop()
	if self.timeBinding then
		self.timeBinding:SetEnabled(false)
	end
end

-- Opaque mode: the castbar covers another bar (e.g. health) and nothing of it
-- may show through, whatever alpha the background colour has.
function Castbar:SetOpaque(opaque)
	self.opaque = opaque and true or false
	self:UpdateBacking()
end

function Castbar:UpdateBacking()
	local r, g, b, a = Util.UnpackColor(self.resolved.background)
	self.backing:SetColorTexture(r, g, b, self.opaque and 1 or a)
end

-- The castbar is only shown while casting, so enabling it doesn't show it.
function Castbar:SetEnabled(enabled)
	self.enabled = enabled and true or false
	if not self.enabled then
		self.frame:Hide()
	end
end

-- notInterruptible may be a secret boolean: pick the colour without branching on it.
function Castbar:ApplyCastColor(info)
	local colors = self.resolved.colors
	local base = info.channel and colors.channel or colors.cast
	if type(info.notInterruptible) == "nil" or not ns.Caps.curves then
		self.barComp:SetColor(Util.UnpackColor(base))
		return
	end
	local color = C_CurveUtil.EvaluateColorFromBoolean(info.notInterruptible,
		CreateColor(Util.UnpackColor(colors.nonInterruptible)), CreateColor(Util.UnpackColor(base)))
	self.barComp:SetColor(color:GetRGBA())
end

function Castbar:ShowCast(info)
	self.fade:Stop()
	self.frame:SetAlpha(1)
	self:ApplyCastColor(info)
	self.nameText:SetText(info.name)
	self.icon:SetTexture(info.icon)
	if self.enabled then
		self.frame:Show()
	end
end

-- Data API ------------------------------------------------------------------

function Castbar:Start(info)
	self:ShowCast(info)
	local direction = info.channel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime
	self.barComp:SetTimerDuration(info.duration, direction)
	if not self.timeBinding then
		self.timeBinding = C_DurationUtil.CreateDurationTextBinding()
		self.timeBinding:SetFormatter(TimeFormatter())
		self.timeBinding:SetFontString(self.timeText:GetFrame())
	end
	self.timeBinding:SetDuration(info.duration)
	self.timeBinding:SetEnabled(true)
end

function Castbar:Stop(result, text)
	if self.timeBinding then
		self.timeBinding:SetEnabled(false)
	end
	self.timeText:SetText("")
	-- Setting a plain value ends the timer-driven fill (same as oUF).
	self.barComp:SetRange(0, 1)
	self.barComp:SetValue(1)
	local colors = self.resolved.colors
	if result == "failed" or result == "interrupted" then
		self.barComp:SetColor(Util.UnpackColor(colors.failed))
		self.nameText:SetText(text or (result == "interrupted" and (INTERRUPTED or "Interrupted") or (FAILED or "Failed")))
	else
		self.barComp:SetColor(Util.UnpackColor(colors.success))
	end
	self.fade:Play()
end

function Castbar:Preview(info, progress, timeText)
	if self.timeBinding then
		self.timeBinding:SetEnabled(false)
	end
	self:ShowCast(info)
	self.barComp:SetRange(0, 1)
	self.barComp:SetValue(progress)
	self.timeText:SetText(timeText or "")
end

function Castbar:GetBar()
	return self.barComp
end
