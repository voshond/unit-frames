local _, ns = ...
local PlayerCastbar = { owners = {} }
ns.PlayerCastbar = PlayerCastbar

local EVENTS = {
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START",
	"UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE",
	"UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
}

function PlayerCastbar:SetOwner(owner, enabled)
	self.owners[owner] = enabled and true or nil
	local frame = PlayerCastingBarFrame
	if next(self.owners) then
		if frame and self.mutedFrame ~= frame then
			frame:UnregisterAllEvents()
			frame:Hide()
			self.mutedFrame = frame
		end
		return
	end
	frame = self.mutedFrame
	if not frame then return end
	self.mutedFrame = nil
	for _, event in ipairs(EVENTS) do frame:RegisterUnitEvent(event, "player") end
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
end
