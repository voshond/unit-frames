local _, ns = ...
local oUF = ns.oUF

-- Text formats as oUF tags: [uf:<format id>], e.g. [uf:health:value].
for _, format in ipairs(ns.Formats.list) do
	local name = "uf:" .. format.id
	oUF.Tags.Methods[name] = function(unit)
		return format.text(unit)
	end
	if format.events then
		oUF.Tags.Events[name] = format.events
		if format.shared then
			for event in format.events:gmatch("%S+") do
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
	local row = self.UF_Experience
	local max = UnitXPMax("player")
	row:SetRange(0, max)
	row:SetValue(UnitXP("player"))
	row:SetSegmentValue("rested", GetXPExhaustion() or 0)
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
UF_Castbar: drives our Castbar component (frame.UF_Castbar = component) from
the cast events. Cast info may be secret: it goes straight into the component,
and only type() is used to check whether there is a cast.
]]
local CAST_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- Blizzard's own player castbar listens to these; we mute it while ours is on
-- (same approach as oUF's Castbar element) and restore it afterwards.
local BLIZZARD_CAST_EVENTS = {
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START",
	"UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE",
	"UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
}

local castState = setmetatable({}, { __mode = "k" })

local function StartCast(castbar, state, unit)
	local name, _, texture, _, _, _, _, notInterruptible, _, castID = UnitCastingInfo(unit)
	if type(name) == "nil" then
		return false
	end
	castbar:Start({ name = name, icon = texture, notInterruptible = notInterruptible, duration = UnitCastingDuration(unit) })
	state.casting, state.channel, state.castID = true, false, castID
	return true
end

local function StartChannel(castbar, state, unit)
	local name, _, texture, _, _, _, notInterruptible, _, _, _, castID = UnitChannelInfo(unit)
	if type(name) == "nil" then
		return false
	end
	castbar:Start({ name = name, icon = texture, channel = true, notInterruptible = notInterruptible,
		duration = UnitChannelDuration(unit) })
	state.casting, state.channel, state.castID = true, true, castID
	return true
end

-- Only the cast we show may stop it: a failed second attempt (spamming a key
-- while casting) fires FAILED for the new cast ID. Cast IDs aren't secret.
local function Stop(castbar, state, result, castID)
	if state.casting and castID and castID == state.castID then
		castbar:Stop(result)
		state.casting = false
	end
end

-- Event payloads after the unit: castGUID, spellID, then
--   STOP: castID | CHANNEL_STOP: interruptedBy, castID
--   FAILED: castID | INTERRUPTED: interruptedBy, castID      (same as oUF's Castbar)
local function UpdateCastbar(self, event, unit, _, _, arg3, arg4)
	unit = unit or self.__unit
	if unit ~= self.__unit then
		return
	end
	local castbar = self.UF_Castbar
	local state = castState[self]
	if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
		StartCast(castbar, state, unit)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		StartChannel(castbar, state, unit)
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
		Stop(castbar, state, "interrupted", arg4)
	elseif event == "UNIT_SPELLCAST_FAILED" then
		Stop(castbar, state, "failed", arg3)
	elseif event == "UNIT_SPELLCAST_STOP" then
		Stop(castbar, state, "success", arg3)
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		Stop(castbar, state, arg3 and "interrupted" or "success", arg4)
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		if state.casting then
			castbar:ApplyCastColor({ channel = state.channel, notInterruptible = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" })
		end
	elseif not (StartCast(castbar, state, unit) or StartChannel(castbar, state, unit)) then
		-- Refresh / unit change without a cast in progress.
		state.casting = false
		castbar:GetFrame():Hide()
	end
end

local function EnableCastbar(self, unit)
	if not self.UF_Castbar then
		return
	end
	castState[self] = castState[self] or {}
	for _, event in ipairs(CAST_EVENTS) do
		self:RegisterEvent(event, UpdateCastbar)
	end
	if unit == "player" and PlayerCastingBarFrame then
		PlayerCastingBarFrame:UnregisterAllEvents()
		PlayerCastingBarFrame:Hide()
	end
	return true
end

local function DisableCastbar(self)
	for _, event in ipairs(CAST_EVENTS) do
		self:UnregisterEvent(event, UpdateCastbar)
	end
	if self.UF_Castbar then
		self.UF_Castbar:GetFrame():Hide()
	end
	if self.__unit == "player" and PlayerCastingBarFrame then
		for _, event in ipairs(BLIZZARD_CAST_EVENTS) do
			PlayerCastingBarFrame:RegisterUnitEvent(event, "player")
		end
		PlayerCastingBarFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	end
end

oUF:AddElement("UF_Castbar", UpdateCastbar, EnableCastbar, DisableCastbar)
