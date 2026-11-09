local _, ns = ...

--[[
Offers Getting started (UnitFrames_Onboarding, load on demand) once. A first
install opens it shortly after the first login, waiting for combat to end;
an existing install is marked done and gets a one-line hint instead. The
guide marks itself done when it is skipped, closed or applied.
]]
local FirstRun = {}
ns.FirstRun = FirstRun

FirstRun.DELAY = 2

local frame = CreateFrame("Frame")

local function Settings()
	return ns.Config.db.global.onboarding
end

function FirstRun:IsDone()
	return Settings().done == true
end

function FirstRun:MarkDone()
	Settings().done = true
end

local function OpenWhenReady()
	if FirstRun:IsDone() then return end
	if InCombatLockdown() then
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	ns:OpenOnboarding(true)
end

frame:SetScript("OnEvent", function(self, event, isInitialLogin)
	if event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent(event)
		if isInitialLogin then C_Timer.After(FirstRun.DELAY, OpenWhenReady) end
		return
	end
	OpenWhenReady()
end)

ns.Events.RegisterCallback(FirstRun, "Initialized", function()
	if FirstRun:IsDone() then return end
	if not ns.Config.freshInstall then
		FirstRun:MarkDone()
		ns:Print("New: /uf welcome walks you through preset looks and the most important options.")
		return
	end
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
end)
