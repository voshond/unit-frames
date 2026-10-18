local _, CG = ...
local UF = CG.UF
local originals = {}
local names = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager" }

function CG:UpdateBlizzardFrames()
	if InCombatLockdown() then
		UF.AfterCombat:Queue("apply", originals, function() self:UpdateBlizzardFrames() end)
		return
	end
	UF.AfterCombat:Cancel(originals)
	local panel = self.Config:Resolved().panel
	local hidden = panel.enabled and panel.hideBlizzardFrames
	for _, name in ipairs(names) do
		local frame = _G[name]
		if frame and hidden then
			if not originals[frame] then
				originals[frame] = frame:GetRolesetNames()
				frame:SetRolesets("alwaysBlocked")
			end
		end
	end
	if hidden then return end
	for frame, rolesets in pairs(originals) do
		frame:SetRolesets(table.concat(rolesets, ","))
		originals[frame] = nil
	end
end
