local addonName, CG = ...
local UF = UnitFrames
UF.ClickGrid = CG
CG.name, CG.UF = addonName, UF
CG.frames, CG.headers, CG.previews = {}, {}, {}
CG.Caps = {
	spellInfo = C_Spell and C_Spell.GetSpellInfo ~= nil,
	spellKnown = C_SpellBook and C_SpellBook.IsSpellKnown ~= nil,
	spellOverride = C_Spell and C_Spell.GetOverrideSpell ~= nil,
	specialization = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization ~= nil,
	privateAuras = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor ~= nil,
}

function CG:Print(...)
	print("|cff4fa3ffUnitFrames ClickGrid|r:", ...)
end

-- All protected changes are coalesced; secure roster updates remain native.
function CG:RequestRefresh()
	if not self.started then return end
	if InCombatLockdown() then
		self.pending = true
		return
	end
	self.pending = nil
	for preview in pairs(self.retiredPreviews or {}) do
		preview:ReleaseComponents()
		self.retiredPreviews[preview] = nil
	end
	self:Refresh()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name == addonName then
			CG.Config:Initialize()
			CG.loaded = true
			if IsLoggedIn and IsLoggedIn() then CG:Start() end
		elseif name == "UnitFrames_Workbench" and CG.loaded then
			CG:RegisterWorkbench()
		end
	elseif event == "PLAYER_LOGIN" then
		CG:Start()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if not CG.started then CG:Start() elseif CG.pending then CG:RequestRefresh() end
	elseif event ~= "PLAYER_SPECIALIZATION_CHANGED" or name == "player" then
		CG:RequestRefresh()
	end
end)

UF.Events.RegisterCallback(CG, "ThemeChanged", function() CG:RequestRefresh() end)
UF.Events.RegisterCallback(CG, "ProfileChanged", function() CG:RequestRefresh() end)

SLASH_UNITFRAMESCLICKGRID1 = "/ufcg"
SlashCmdList.UNITFRAMESCLICKGRID = function(message)
	message = strtrim(message or ""):lower()
	if message == "on" or message == "off" then
		CG.Config:Set("panel.enabled", message == "on")
	elseif message == "bindings" then
		UF:OpenWorkbench("clickgrid.bindings")
	else
		UF:OpenWorkbench("clickgrid.panel")
	end
end
