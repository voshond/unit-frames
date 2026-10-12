local _, ns = ...
local StackIcon = ns.Components.StackIcon

--[[
The ready check mark in the decoration stack: ready, not ready or waiting.
The owning UnitFrame drives it from its ready check state (live and sample
alike), together with the bar tints, so the mark fades out with them.
]]
local ReadyCheckIcon = StackIcon:Extend("ReadyCheckIcon")

ReadyCheckIcon.stackKey = "readyCheckIcon"

-- Blizzard's raid ready check marks (READY_CHECK_*_TEXTURE_RAID).
ReadyCheckIcon.ATLASES = {
	ready = "UI-LFG-ReadyMark-Raid",
	notready = "UI-LFG-DeclineMark-Raid",
	waiting = "UI-LFG-PendingMark-Raid",
}

ReadyCheckIcon.schema = StackIcon.BuildIconSchema({ anchor = "CENTER", size = 22 })

-- status: "ready", "notready", "waiting" or nil; alpha: 0..1 (fading out).
function ReadyCheckIcon:SetStatus(status, alpha)
	local atlas = status and ReadyCheckIcon.ATLASES[status]
	if atlas and (alpha or 1) > 0 then
		self.texture:SetAtlas(atlas)
		self.texture:SetAlpha(alpha or 1)
		self.texture:Show()
	else
		self.texture:Hide()
	end
	self:Reflow()
end
