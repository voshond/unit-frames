local addonName, ns = ...

-- Public handle so companion addons (Workbench, Options) can reach the core.
UnitFrames = ns

ns.name = addonName
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"

ns.Components = {} -- component classes by name, filled by Component:Extend
ns.Widgets = {}    -- widget classes by name, filled by Widget:Extend

-- Client capabilities, probed once at load. Code branches on these instead of
-- wrapping calls in pcall (docs/02 §4.4).
do
	local probe = CreateFrame("StatusBar")
	ns.Caps = {
		smoothBars = Enum ~= nil and Enum.StatusBarInterpolation ~= nil,
		timerBars = probe.SetTimerDuration ~= nil and Enum ~= nil and Enum.StatusBarTimerDirection ~= nil,
		durations = C_DurationUtil ~= nil and C_DurationUtil.CreateDuration ~= nil,
		curves = C_CurveUtil ~= nil and C_CurveUtil.CreateColorCurve ~= nil,
		secrets = issecretvalue ~= nil,
		booleanAlpha = probe.SetAlphaFromBoolean ~= nil,
		groupRange = UnitInRange ~= nil,
		spellRange = C_Spell ~= nil and C_Spell.IsSpellInRange ~= nil,
	}
	probe:Hide()
end

function ns:Print(...)
	print("|cff4fa3ffUnitFrames|r:", ...)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
	if name ~= addonName then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	ns.Config:Initialize()
	ns.Media:Initialize()
	ns.Events:Fire("Initialized")
end)
