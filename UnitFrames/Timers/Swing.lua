local _, ns = ...
local Swing = ns.Object:Extend("Swing")
ns.Swing = Swing

local formatter
local function Formatter()
	if not formatter then
		formatter = C_StringUtil.CreateSecondsFormatter()
		formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
		formatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
		formatter:SetMillisecondsThreshold(60)
	end
	return formatter
end

function Swing:Init(row, label)
	self.row, self.label = row, label
	self:Clear()
end

function Swing:Clear()
	self.ends = nil
	self.previewActive = false
	self.row:GetBar():SetSparkActive(false)
	if self.binding then self.binding:SetEnabled(false) end
	self.row:SetRange(0, 1)
	self.row:SetValue(0)
	self.row:GetText("left"):SetText(self.label)
	self.row:GetText("right"):SetText("")
end

function Swing:Start(seconds)
	self:Clear()
	if not self.row:IsEnabled() or not ns.Caps.durations or not ns.Caps.timerBars
		or ns.Util.IsSecret(seconds) or type(seconds) ~= "number" or seconds <= 0 then return end
	self.duration = self.duration or C_DurationUtil.CreateDuration()
	self.duration:SetTimeFromStart(GetTime(), seconds)
	self.ends = GetTime() + seconds
	self.row:GetBar():SetSparkActive(true)
	self.row:GetBar():SetTimerDuration(self.duration, Enum.StatusBarTimerDirection.ElapsedTime)
	if not self.binding then
		self.binding = C_DurationUtil.CreateDurationTextBinding()
		self.binding:SetFormatter(Formatter())
		self.binding:SetFontString(self.row:GetText("right"):GetFrame())
	end
	self.binding:SetDuration(self.duration)
	self.binding:SetEnabled(true)
end

function Swing:Tick()
	if self.ends and GetTime() >= self.ends then self:Clear() end
end

function Swing:Preview(progress, seconds)
	self:Clear()
	self.previewActive = true
	self.row:GetBar():SetSparkActive(progress > 0 and progress < 1)
	self.row:SetValue(progress)
	self.row:GetText("right"):SetText(string.format("%.1f", seconds * (1 - progress)))
end

function Swing:Release()
	self:Clear()
	self.duration = nil
end
