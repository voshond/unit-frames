local _, ns = ...

-- Private presentation state: plain group statuses, one fade driver and two
-- sinks (row tints and an optional icon). Live subscriptions stay with oUF.
local ReadyCheck = {}
ReadyCheck.__index = ReadyCheck
ns.ReadyCheck = ReadyCheck
local COLORS = { waiting = "waitingColor", ready = "readyColor", notready = "notReadyColor" }

local function Fade(cfg, elapsed)
	local fading = elapsed - cfg.hold
	if fading <= 0 then return 1 end
	if cfg.fade <= 0 then return 0 end
	return math.max(0, 1 - fading / cfg.fade)
end

function ReadyCheck.New(parent, tint)
	return setmetatable({ driver = CreateFrame("Frame", nil, parent), tint = tint }, ReadyCheck)
end

function ReadyCheck:IsShown()
	return self.cfg ~= nil and (self.cfg.enabled or (self.icon ~= nil and self.icon:IsEnabled()))
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
				if Fade(self.cfg, self.elapsed) <= 0 then self:Set(nil) else self:Apply(self.cfg) end
			end)
		end
	else
		self.driver:SetScript("OnUpdate", nil)
	end
end

-- Attachment borrows presentation only; component ownership never transfers.
function ReadyCheck:Attach(icon)
	if self.icon and self.icon ~= icon then self.icon:SetStatus(nil, 0) end
	self.icon = icon
	if self.cfg then self:Apply(self.cfg) end
end

function ReadyCheck:Detach(icon)
	if not icon or self.icon ~= icon then return false end
	self:Attach(nil)
	return true
end

function ReadyCheck:Sample(status, time, answerAt)
	self.sample = { status = status, time = time, answerAt = answerAt }
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
	self.driver:SetScript("OnUpdate", nil)
	self:Show(nil, 0)
	self.icon, self.tint = nil, nil
	self.sample = nil
end
