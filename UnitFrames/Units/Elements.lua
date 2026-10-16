local _, ns = ...
local oUF, Drivers = ns.oUF, ns.UnitDrivers

-- Text formats as oUF tags: [uf:<format id>], e.g. [uf:health:value].
for _, format in ipairs(ns.Formats.list) do
	local name = "uf:" .. format.id
	oUF.Tags.Methods[name] = function(unit)
		return format.text(unit)
	end
	if format.events then
		oUF.Tags.Events[name] = format.events
		for event in format.events:gmatch("%S+") do
			if format.sharedEvents and format.sharedEvents[event] then
				oUF.Tags.SharedEvents[event] = true
			end
		end
	end
end

--[[
UF_Experience: player experience on a TextBar (frame.UF_Experience = row).
Fills the bar and its "rested" segment. XP events carry no unit.
]]
local function UpdateExperience(self)
	ns.UnitRows.PlayerExperience(self.UF_Experience)
end

local function EnableExperience(self, unit)
	if self.UF_Experience and unit == "player" then
		self:RegisterEvent("PLAYER_XP_UPDATE", UpdateExperience, true)
		self:RegisterEvent("UPDATE_EXHAUSTION", UpdateExperience, true)
		self:RegisterEvent("PLAYER_LEVEL_UP", UpdateExperience, true)
		return true
	end
end

local function DisableExperience(self)
	self:UnregisterEvent("PLAYER_XP_UPDATE", UpdateExperience)
	self:UnregisterEvent("UPDATE_EXHAUSTION", UpdateExperience)
	self:UnregisterEvent("PLAYER_LEVEL_UP", UpdateExperience)
end

oUF:AddElement("UF_Experience", UpdateExperience, EnableExperience, DisableExperience)

--[[
UF_ComboPoints: the player's combo points on a PointBar (frame.UF_ComboPoints),
on a target frame or a player frame (Drivers.ComboPoints). Forever stores them
on the target, like Blizzard's own ComboFrame: a target change, or points
moving to a new target (COMBO_TARGET_CHANGED, same count), redraws them too.
The power events are the player's, also on a target frame, so they are
registered unit-less and filtered here.
]]
local COMBO_POINT_POWER_EVENTS = { UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true,
	UNIT_POWER_POINT_CHARGE = true, UNIT_MAXPOWER = true }
local COMBO_POINT_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_POWER_POINT_CHARGE", "UNIT_MAXPOWER",
	"PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED", "PLAYER_ENTERING_WORLD" }

local function UpdateComboPoints(self, event, unit, powerType)
	if COMBO_POINT_POWER_EVENTS[event] then
		if unit ~= "player" then return end
		-- Other power types (energy ticks) change no combo points.
		if type(powerType) == "string" and not issecretvalue(powerType) and powerType ~= "COMBO_POINTS" then return end
	end
	local points, max = Drivers.ComboPoints(self.__unit)
	self.UF_ComboPoints:SetMax(max)
	self.UF_ComboPoints:SetValue(points)
end

local function EnableComboPoints(self, unit)
	if not self.UF_ComboPoints or (unit ~= "player" and unit ~= "target") then return end
	for _, event in ipairs(COMBO_POINT_EVENTS) do
		self:RegisterEvent(event, UpdateComboPoints, true)
	end
	return true
end

local function DisableComboPoints(self)
	for _, event in ipairs(COMBO_POINT_EVENTS) do
		self:UnregisterEvent(event, UpdateComboPoints)
	end
	self.UF_ComboPoints:SetValue(0)
end

oUF:AddElement("UF_ComboPoints", UpdateComboPoints, EnableComboPoints, DisableComboPoints)

local function UpdateResting(self)
	self.UF_Resting:SetResting(self.__unit == "player" and IsResting())
end

local function EnableResting(self)
	if not self.UF_Resting then return end
	self:RegisterEvent("PLAYER_UPDATE_RESTING", UpdateResting, true)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", UpdateResting, true)
	UpdateResting(self)
	return true
end

local function DisableResting(self)
	self:UnregisterEvent("PLAYER_UPDATE_RESTING", UpdateResting)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD", UpdateResting)
	self.UF_Resting:SetResting(false)
end

oUF:AddElement("UF_Resting", UpdateResting, EnableResting, DisableResting)

-- UF_Classification: the elite/rare/boss icon (frame.UF_Classification =
-- Classification component), read by Drivers.Classification.
local function UpdateClassification(self, _, unit)
	if unit and unit ~= self.__unit then return end
	self.UF_Classification:SetClassification(Drivers.Classification(self.__unit))
end

local function EnableClassification(self)
	if not self.UF_Classification then return end
	self:RegisterEvent("UNIT_CLASSIFICATION_CHANGED", UpdateClassification)
	return true
end

local function DisableClassification(self)
	self:UnregisterEvent("UNIT_CLASSIFICATION_CHANGED", UpdateClassification)
	self.UF_Classification:SetClassification(nil)
end

oUF:AddElement("UF_Classification", UpdateClassification, EnableClassification, DisableClassification)

--[[
UF_ReadyCheck: bar tints during a ready check (frame.UF_ReadyCheck = the
UnitFrame's ReadyCheck presenter). The events carry no unit of this frame
(confirmations name party/raid tokens), so every frame re-reads its own
unit's status. The
status is plain group state; an opaque one counts as none. After the check
the result fades on its own: only a new check interrupts it.
]]
local READY_CHECK_EVENTS = { "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED" }

local function UpdateReadyCheck(self, event)
	local readyCheck, unit = self.UF_ReadyCheck, self.__unit
	if event == "READY_CHECK_FINISHED" then
		readyCheck:Finish()
		return
	end
	if readyCheck:IsFinishing() and event ~= "READY_CHECK" then return end
	local status
	if unit and UnitExists(unit) then
		status = GetReadyCheckStatus(unit)
		if issecretvalue(status) then status = nil end
	end
	readyCheck:Set(status)
end

local function EnableReadyCheck(self)
	if not self.UF_ReadyCheck then return end
	for _, event in ipairs(READY_CHECK_EVENTS) do
		self:RegisterEvent(event, UpdateReadyCheck, true)
	end
	return true
end

local function DisableReadyCheck(self)
	for _, event in ipairs(READY_CHECK_EVENTS) do
		self:UnregisterEvent(event, UpdateReadyCheck)
	end
	self.UF_ReadyCheck:Set(nil)
end

oUF:AddElement("UF_ReadyCheck", UpdateReadyCheck, EnableReadyCheck, DisableReadyCheck)

--[[
UF_Castbar: drives our Castbar component (frame.UF_Castbar = component) from
the cast events through the shared state machine (Units/Cast.lua).
]]
local Cast = ns.Cast

-- Blizzard's own player castbar listens to these; we mute it while ours is on
-- (same approach as oUF's Castbar element) and restore it afterwards.
local BLIZZARD_CAST_EVENTS = {
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START",
	"UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE",
	"UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
}

local castState = setmetatable({}, { __mode = "k" })
-- The player frame whose castbar muted Blizzard's; only it restores it.
local blizzardCastbarMutedBy

local function UpdateCastbar(self, event, unit, ...)
	unit = unit or self.__unit
	if unit ~= self.__unit then
		return
	end
	Cast.Handle(self.UF_Castbar, castState[self], event, unit, ...)
end

local function UpdateGCD(self)
	Cast.UpdateGCD(self.UF_Castbar, castState[self])
end

local function EnableCastbar(self, unit)
	if not self.UF_Castbar then
		return
	end
	castState[self] = castState[self] or {}
	for _, event in ipairs(Cast.EVENTS) do
		self:RegisterEvent(event, UpdateCastbar)
	end
	if self.UF_Castbar:HasGCD() then
		for _, event in ipairs(Cast.GCD_EVENTS) do
			self:RegisterEvent(event, UpdateGCD, true)
		end
	end
	if unit == "player" and PlayerCastingBarFrame and not blizzardCastbarMutedBy then
		PlayerCastingBarFrame:UnregisterAllEvents()
		PlayerCastingBarFrame:Hide()
		blizzardCastbarMutedBy = self
	end
	return true
end

local function DisableCastbar(self)
	for _, event in ipairs(Cast.EVENTS) do
		self:UnregisterEvent(event, UpdateCastbar)
	end
	for _, event in ipairs(Cast.GCD_EVENTS) do
		self:UnregisterEvent(event, UpdateGCD)
	end
	if self.UF_Castbar then
		self.UF_Castbar:Hide()
		self.UF_Castbar:StopGCD()
	end
	if blizzardCastbarMutedBy == self then
		blizzardCastbarMutedBy = nil
		for _, event in ipairs(BLIZZARD_CAST_EVENTS) do
			PlayerCastingBarFrame:RegisterUnitEvent(event, "player")
		end
		PlayerCastingBarFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	end
end

oUF:AddElement("UF_Castbar", UpdateCastbar, EnableCastbar, DisableCastbar)

--[[
UF_Auras: keeps our Auras component (frame.UF_Auras) on the frame's unit.
The AuraContainer handles aura events itself; this only follows unit changes
(new target, ...) and refreshes, like oUF's own Auras element.
]]
local function UpdateAuras(self)
	if self.__unit then self.UF_Auras:SetUnit(self.__unit) end
end

local function EnableAuras(self)
	return self.UF_Auras ~= nil
end

local function DisableAuras() end

oUF:AddElement("UF_Auras", UpdateAuras, EnableAuras, DisableAuras)

-- Independent native containers allow the row and external icons to coexist.
local function UpdateAuraBar(self)
	if self.__unit then self.UF_AuraBar:SetUnit(self.__unit) end
end

local function EnableAuraBar(self)
	return self.UF_AuraBar ~= nil
end

oUF:AddElement("UF_AuraBar", UpdateAuraBar, EnableAuraBar, DisableAuras)

local function UpdateCategoryAuras(self)
	if self.__unit then self.UF_CategoryAuras:SetUnit(self.__unit) end
end

local function EnableCategoryAuras(self)
	return self.UF_CategoryAuras ~= nil
end

oUF:AddElement("UF_CategoryAuras", UpdateCategoryAuras, EnableCategoryAuras, DisableAuras)

-- UF_Range: group checks are event-driven; spell checks also poll because
-- SPELL_RANGE_CHECK_UPDATE only describes the player's current target, not
-- focus/target-of-target. Never inspect a live range boolean in Lua
-- (Drivers.RangeState).
local function UpdateRange(self)
	self.UF_Range:SetRangeState(Drivers.RangeState(self.UF_Range, self.__unit))
end

-- A separate, unprotected driver avoids changing scripts on secure buttons.
-- Only enabled spell-mode frames are tracked; hidden frames aren't polled.
local spellFrames = {}
local rangeDriver = CreateFrame("Frame")
local rangeElapsed = 0
rangeDriver:Hide()
rangeDriver:SetScript("OnUpdate", function(_, elapsed)
	rangeElapsed = rangeElapsed + elapsed
	if rangeElapsed < 0.2 then return end
	rangeElapsed = 0
	for frame in pairs(spellFrames) do
		if frame:IsShown() then UpdateRange(frame) end
	end
end)

local function EnableRange(self)
	if not self.UF_Range then return end
	self:RegisterEvent("UNIT_CONNECTION", UpdateRange)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", UpdateRange, true)
	if self.UF_Range.resolved.range.mode == "spell" then
		spellFrames[self] = true
		rangeDriver:Show()
	else
		self:RegisterEvent("UNIT_IN_RANGE_UPDATE", UpdateRange)
	end
	UpdateRange(self)
	return true
end

local function DisableRange(self)
	self:UnregisterEvent("UNIT_CONNECTION", UpdateRange)
	self:UnregisterEvent("GROUP_ROSTER_UPDATE", UpdateRange)
	self:UnregisterEvent("UNIT_IN_RANGE_UPDATE", UpdateRange)
	spellFrames[self] = nil
	if not next(spellFrames) then
		rangeDriver:Hide()
		rangeElapsed = 0
	end
	self.UF_Range:SetRangeState(true, false)
end

oUF:AddElement("UF_Range", UpdateRange, EnableRange, DisableRange)
