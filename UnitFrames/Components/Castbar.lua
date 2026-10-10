local _, ns = ...
local Util = ns.Util
local Bar, Text = ns.Components.Bar, ns.Components.Text

--[[
Cast bar: a Bar plus spell icon, spell name and remaining time.

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

function Castbar:GetSchema()
	if self.schemaCache then
		return self.schemaCache
	end
	self.schemaCache = {
		{ key = "enabled", type = "toggle", label = "Enabled", default = true },
		{ key = "icon", type = "group", label = "Icon", schema = {
			{ key = "enabled", type = "toggle", label = "Enabled", default = true },
			{ key = "position", type = "select", label = "Position", values = Castbar.ICON_POSITIONS, default = "LEFT" },
			{ key = "gap", type = "range", label = "Gap", min = 0, max = 10, step = 1, default = 1 },
		} },
		{ key = "bar", type = "group", label = "Bar", schema = self.barComp:GetSchema(),
			defaults = { spark = true, smooth = false, border = { enabled = true } } },
		{ key = "name", type = "group", label = "Spell name", schema = Text.schema, defaults = { justifyH = "LEFT" } },
		{ key = "time", type = "group", label = "Time", schema = Text.schema, defaults = { justifyH = "RIGHT" } },
		{ key = "colors", type = "group", label = "Colours", schema = {
			Color("cast", "Cast", "colors.cast"),
			Color("channel", "Channel", "colors.channel"),
			Color("nonInterruptible", "Not interruptible", "colors.nonInterruptible"),
			Color("failed", "Failed / interrupted", "colors.castFailed"),
			Color("success", "Succeeded", "colors.castSuccess"),
		} },
		{ key = "holdTime", type = "range", label = "Hold after finish (s)", min = 0, max = 2, step = 0.1, default = 0.4 },
		{ key = "fadeTime", type = "range", label = "Fade out (s)", min = 0, max = 2, step = 0.1, default = 0.3 },
	}
	return self.schemaCache
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
	self.frame = CreateFrame("Frame", nil, parent)

	self.icon = self.frame:CreateTexture(nil, "ARTWORK")
	self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	self.barComp = Bar:New(self.frame, {}, { colorInherit = "colors.cast" })
	local textParent = self.barComp:GetTextParent()
	self.nameText = Text:New(textParent, {})
	self.timeText = Text:New(textParent, {})

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
	local height = self.frame:GetHeight()
	local icon, bar = self.icon, self.barComp
	icon:ClearAllPoints()
	bar:ClearAllPoints()
	if cfg.icon.enabled then
		icon:SetSize(height, height)
		icon:Show()
		if cfg.icon.position == "LEFT" then
			icon:SetPoint("TOPLEFT", self.frame, "TOPLEFT")
			bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", cfg.icon.gap, 0)
			bar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT")
		else
			icon:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT")
			bar:SetPoint("TOPLEFT", self.frame, "TOPLEFT")
			bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", -cfg.icon.gap, 0)
		end
	else
		icon:Hide()
		bar:SetAllPoints(self.frame)
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
	self.barComp:Release()
	self.nameText:Release()
	self.timeText:Release()
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
