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
