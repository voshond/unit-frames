local _, ob = ...
local UF = UnitFrames
local Pending, Steps = ob.Pending, ob.Steps

--[[
Getting started: four steps over the shell. UF:OpenOnboarding() loads this
addon and calls Open. Closing it any way (Skip, Escape, the close button,
finishing) marks the guide done, so it never opens by itself again. Combat
hides it with the choices kept; it comes back when combat ends.
]]
local Onboarding = { steps = { Steps.Look, Steps.Tweaks, Steps.Extras, Steps.Ready } }
UF.Onboarding = Onboarding
ob.Onboarding = Onboarding

local APPLY_STEP = 3

function Onboarding:Build()
	self.shell = ob.Shell:New(self, self.steps)
	local frame = self.shell.frame
	frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
	frame:SetScript("OnHide", function() self:OnHidden() end)
	frame:SetScript("OnEvent", function(_, event) self:OnEvent(event) end)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	Pending.onChange = function()
		local step = self.steps[self.index]
		if step and step.page and step.Refresh and self.shell.frame:IsShown() then step:Refresh() end
	end
end

function Onboarding:Open()
	if not self.shell then self:Build() end
	if InCombatLockdown() then
		self.pendingOpen = true
		UF:Print("Getting started opens when combat ends.")
		return
	end
	if self.shell.frame:IsShown() then return end
	Pending:Reset()
	self.shell:Show()
	self:Go(1)
end

function Onboarding:IsShown()
	return self.shell ~= nil and self.shell.frame:IsShown()
end

function Onboarding:Close()
	if self.shell then self.shell.frame:Hide() end
end

function Onboarding:Go(index)
	local current = self.steps[self.index]
	if current and current.page then
		if current.Leave then current:Leave() end
		current.page:Hide()
	end
	self.index = index
	local step = self.steps[index]
	if not step.page then
		step.page = CreateFrame("Frame", nil, self.shell.body)
		step.page:SetPoint("TOPLEFT")
		step.page:SetSize(ob.Shell.PAGE_WIDTH, ob.Shell.PAGE_HEIGHT)
		step:Build(step.page, self)
	end
	step.page:Show()
	self.shell:SetStep(index, step, #self.steps)
	step:Enter()
end

function Onboarding:Next()
	if self.index == #self.steps then
		self:Close()
		return
	end
	if self.index == APPLY_STEP then
		local ok, reason = Pending:Apply()
		if not ok then
			self.shell:SetMessage(reason)
			return
		end
	end
	self:Go(self.index + 1)
end

function Onboarding:Back()
	if self.index > 1 and self.index < #self.steps then self:Go(self.index - 1) end
end

-- The rail: earlier steps only, and not once the look is applied.
function Onboarding:Jump(index)
	if index < self.index and self.index < #self.steps then self:Go(index) end
end

function Onboarding:OnUpdate(elapsed)
	self.shell:Tick(elapsed)
	local step = self.steps[self.index]
	if step and step.Tick then step:Tick(elapsed) end
end

function Onboarding:OnHidden()
	if self.combatHidden then return end
	local step = self.steps[self.index]
	if step and step.page and step.Leave then step:Leave() end
	self.index = nil
	UF.FirstRun:MarkDone()
end

function Onboarding:OnEvent(event)
	if event == "PLAYER_REGEN_DISABLED" then
		if not self:IsShown() then return end
		self.combatHidden = true
		self.shell.frame:Hide()
		return
	end
	if self.combatHidden then
		self.combatHidden = false
		self.shell:Show()
	elseif self.pendingOpen then
		self.pendingOpen = false
		self:Open()
	end
end
