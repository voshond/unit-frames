local addonName, CG = ...
local UF = UnitFrames
UF.ClickGrid = CG
CG.name, CG.UF = addonName, UF
CG.frames, CG.headers, CG.previews = {}, {}, {}
CG.Caps = {
	roleEnum = UnitGroupRolesAssignedEnum ~= nil and Enum.LFGRole ~= nil,
	spellInfo = C_Spell and C_Spell.GetSpellInfo ~= nil,
	spellKnown = C_SpellBook and C_SpellBook.IsSpellKnown ~= nil,
	spellOverride = C_Spell and C_Spell.GetOverrideSpell ~= nil,
	specialization = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization ~= nil,
	privateAuras = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor ~= nil,
	cursor = GetCursorInfo ~= nil and ClearCursor ~= nil,
	spellBook = PlayerSpellsUtil ~= nil and PlayerSpellsUtil.OpenToSpellBookTab ~= nil,
	macros = GetNumMacros ~= nil and GetMacroInfo ~= nil and Constants ~= nil and Constants.MacroConsts ~= nil,
	macroFrame = ShowMacroFrame ~= nil,
}

function CG:Print(...)
	print("|cff4fa3ffUnitFrames ClickGrid|r:", ...)
end

-- All protected changes are coalesced; secure roster updates remain native.
function CG:RequestRefresh(kind, path)
	if not self.started then return end
	self.pendingChanges = self.MergeChanges(self.pendingChanges or {}, self:RefreshChanges(kind, path))
	self.pending = true
	if InCombatLockdown() then return end
	self:FlushRefresh()
end

function CG:FlushRefresh()
	if not self.started or InCombatLockdown() then return end
	local changes = self.pendingChanges or { full = true }
	if self.pendingBindings then changes.bindings = true end
	self.pending, self.pendingChanges, self.pendingBindings = nil, nil, nil
	for preview in pairs(self.retiredPreviews or {}) do
		preview:ReleaseComponents()
		self.retiredPreviews[preview] = nil
	end
	self:Refresh(changes)
end

function CG:RequestBindings(notify)
	if not self.started then return end
	if InCombatLockdown() then
		self.pendingBindings = true
		return
	end
	self.pendingBindings = nil
	self:ApplyBindings(notify)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE", "UPDATE_MACROS", "GROUP_ROSTER_UPDATE" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name == addonName then
			CG.Config:Initialize()
			CG.loaded = true
			if IsLoggedIn and IsLoggedIn() then CG:Start() end
		elseif name == "UnitFrames_Workbench" and CG.loaded then
			CG:RegisterWorkbench()
		end
		if CG.started then CG:UpdateBlizzardFrames() end
	elseif event == "PLAYER_LOGIN" then
		CG:Start()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if not CG.started then CG:Start()
		elseif CG.pending then CG:FlushRefresh()
		elseif CG.pendingBindings then CG:RequestBindings(true) end
	elseif event == "GROUP_ROSTER_UPDATE" then
		CG:RequestRoster()
	elseif event ~= "PLAYER_SPECIALIZATION_CHANGED" or name == "player" then
		-- Spells, macros, talents and specialization select bindings, not styles.
		CG:RequestBindings(true)
	end
end)

UF.Events.RegisterCallback(CG, "ThemeChanged", function() CG:RequestRefresh() end)
-- Core emits ThemeChanged after every profile change, refreshing the panel
-- and all preview styles through the same owner.

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
