local _, ns = ...

--[[
Ready check presentation for one unit frame: plain group statuses, one fade
driver and two sinks (row tints and an optional icon). Live subscriptions
stay with oUF (Units/Elements.lua UF_ReadyCheck). Statuses are
GetReadyCheckStatus's plain results: "waiting", "ready", "notready" or nil
(no check, or not part of it).

  ReadyCheck:New(parent, tint)  tint(color, amount): colour the owner's rows
  :Apply(cfg)                   the owner's resolved readyCheck settings
  :Set(status)                  during a check; nil removes tints and icon at once
  :Finish()                     the check ended: an unanswered check counts as not
                                ready; hold the result, then fade out
  :Sample(status, time, answerAt)  previews: the answer held, or with `time` a
                                looping check: waiting until `answerAt` (default
                                1.5 s), the answer until 3 s, then the end of the
                                check with hold and fade, then 1 s plain
  :Attach(icon) / :Detach(icon) show the mark on a ReadyCheckIcon; companions
                                attach their own icon, ownership never transfers
  :SetChangedCallback(fn)       after attachment changes (the live binding)
]]
local ReadyCheck = ns.Object:Extend("ReadyCheck")
ns.ReadyCheck = ReadyCheck
local COLORS = { waiting = "waitingColor", ready = "readyColor", notready = "notReadyColor" }

ReadyCheck.schema = {
	{ key = "enabled", type = "toggle", label = "Tint bars", default = true,
		tooltip = "During a ready check, grey this frame's bars until the unit answers, then turn them green (ready) or red (not ready). When the check ends, units without an answer turn red, then all bars fade back to their normal colours. The Ready check icon section places the matching check mark." },
	{ key = "waitingColor", type = "color", label = "Waiting colour", default = { 0.5, 0.5, 0.5, 1 } },
	{ key = "readyColor", type = "color", label = "Ready colour", default = { 0.15, 0.8, 0.15, 1 } },
	{ key = "notReadyColor", type = "color", label = "Not ready colour", default = { 0.85, 0.12, 0.12, 1 } },
	{ key = "hold", type = "range", label = "Hold after the check (seconds)", min = 0, max = 10, step = 0.5, default = 2,
		tooltip = "How long the result (tints and icon) stays after the check ends, before fading." },
	{ key = "fade", type = "range", label = "Fade duration (seconds)", min = 0, max = 5, step = 0.25, default = 1.5,
		tooltip = "Time to fade back to the normal bar colours and fade out the icon. 0 = switch back at once." },
}

local function Fade(cfg, elapsed)
	local fading = elapsed - cfg.hold
	if fading <= 0 then return 1 end
	if cfg.fade <= 0 then return 0 end
	return math.max(0, 1 - fading / cfg.fade)
end

function ReadyCheck:Init(parent, tint)
	self.driver = CreateFrame("Frame", nil, parent)
	self.tint = tint
end

-- Whether anything shows a check: the tints or an enabled icon.
function ReadyCheck:IsShown()
	return self.cfg ~= nil and (self.cfg.enabled or (self.icon ~= nil and self.icon:IsEnabled()))
end

function ReadyCheck:IsFinishing()
	return self.finished == true
end

-- The shown status and its opacity (0 = nothing shown).
function ReadyCheck:GetState()
	return self.shownStatus, self.shownAmount or 0
end

function ReadyCheck:GetIcon()
	return self.icon
end

function ReadyCheck:Show(status, amount)
	status = amount > 0 and status or nil
	self.shownStatus, self.shownAmount = status, amount
	local color = status and self.cfg and self.cfg.enabled and self.cfg[COLORS[status]]
	self.tint(color, amount)
	if self.icon then self.icon:SetStatus(self.icon:IsEnabled() and status or nil, amount) end
end

function ReadyCheck:Set(status)
	self.sample = nil
	self.status, self.finished = status, false
	self:Apply(self.cfg)
end

function ReadyCheck:Finish()
	if not self.status then return end
	if self.status == "waiting" then self.status = "notready" end
	self.finished, self.elapsed = true, 0
	self:Apply(self.cfg)
end

function ReadyCheck:Apply(cfg)
	self.cfg = cfg
	if self.sample then
		self:Sample(self.sample.status, self.sample.time, self.sample.answerAt)
		return
	end
	local amount = 0
	if self.status and self:IsShown() then
		amount = self.finished and Fade(cfg, self.elapsed) or 1
	end
	self:Show(self.status, amount)
	if amount > 0 and self.finished then
		if not self.driver:GetScript("OnUpdate") then
			self.driver:SetScript("OnUpdate", function(_, elapsed)
				self.elapsed = self.elapsed + elapsed
				local nextAmount = Fade(self.cfg, self.elapsed)
				if nextAmount <= 0 then
					self:Set(nil)
				elseif nextAmount ~= self.shownAmount then
					self:Show(self.status, nextAmount)
				end
			end)
		end
	else
		self.driver:SetScript("OnUpdate", nil)
	end
end

function ReadyCheck:SetChangedCallback(callback)
	self.onChanged = callback
end

local function SetIcon(self, icon)
	if self.icon and self.icon ~= icon then self.icon:SetStatus(nil, 0) end
	self.icon = icon
	if self.cfg then self:Apply(self.cfg) end
end

function ReadyCheck:Attach(icon)
	assert(not self.released, "Ready check presentation released")
	SetIcon(self, icon)
	if self.onChanged then self.onChanged() end
end

function ReadyCheck:Detach(icon)
	if self.released or not icon or self.icon ~= icon then return end
	SetIcon(self, nil)
	if self.onChanged then self.onChanged() end
end

function ReadyCheck:Sample(status, time, answerAt)
	self.sample = self.sample or {}
	self.sample.status, self.sample.time, self.sample.answerAt = status, time, answerAt
	self.driver:SetScript("OnUpdate", nil)
	self.status, self.finished = nil, false
	if not time or not status then
		self:Show(status, status and 1 or 0)
		return
	end
	local cfg = self.cfg
	local t = time % (4 + cfg.hold + cfg.fade)
	if t < (answerAt or 1.5) then self:Show("waiting", 1)
	elseif t < 3 then self:Show(status, 1)
	else self:Show(status == "waiting" and "notready" or status, Fade(cfg, t - 3)) end
end

function ReadyCheck:Release()
	if self.released then return end
	self.released = true
	self.driver:SetScript("OnUpdate", nil)
	self:Show(nil, 0)
	self.icon, self.tint, self.onChanged = nil, nil, nil
	self.sample = nil
end
