local _, ns = ...
local BlizzardAuras = {}
ns.BlizzardAuras = BlizzardAuras

local FRAMES = { hideBuffs = "BuffFrame", hideDebuffs = "DebuffFrame" }
local originals = {}

local function SetHidden(frame, hidden)
	if hidden and not originals[frame] then
		originals[frame] = frame:GetRolesetNames()
		frame:SetRolesets("alwaysBlocked")
	elseif not hidden and originals[frame] then
		frame:SetRolesets(table.concat(originals[frame], ","))
		originals[frame] = nil
	end
end

function BlizzardAuras:Update()
	if InCombatLockdown() then
		ns.AfterCombat:Queue("apply", originals, function() self:Update() end)
		return
	end
	ns.AfterCombat:Cancel(originals)
	local config = ns.Config:UnitStore("player"):Resolved().blizzardAuras
	for key, name in pairs(FRAMES) do
		local frame = _G[name]
		if frame then SetHidden(frame, config[key]) end
	end
end

ns.Events.RegisterCallback(BlizzardAuras, "Initialized", function() BlizzardAuras:Update() end)
ns.Events.RegisterCallback(BlizzardAuras, "ThemeChanged", function() BlizzardAuras:Update() end)
ns.Events.RegisterCallback(BlizzardAuras, "UnitConfigChanged", function(_, unit)
	if unit == "player" then BlizzardAuras:Update() end
end)
