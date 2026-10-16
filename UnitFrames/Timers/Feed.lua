local _, ns = ...
local Feed = ns.Object:Extend("TimerFeed")
ns.TimerFeed = Feed

Feed.EVENTS = { "PLAYER_SWING", "WEAPON_SLOT_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_ATTACK_SPEED" }

function Feed:HasCastbar()
	return self.component:GetCastbar():IsEnabled() and self.component.resolved.castbar.visibility ~= "hidden"
end

function Feed:RefreshVisibility(combat, force)
	if combat == nil then combat = InCombatLockdown() end
	local component = self.component
	local enabled = component:IsEnabled()
	local mode = component.resolved.castbar.visibility
	local castbar = component:GetCastbar()
	castbar:SetIdleShown(enabled and castbar:IsEnabled() and (mode == "always" or mode == "combat" and combat))
	component.castHost:SetShown(enabled and castbar:IsEnabled()
		and (force or mode ~= "hidden" and (mode ~= "combat" or combat)))
	for key, swing in pairs(self.swings) do
		local row = component:GetRow(key)
		mode = component.resolved[key].visibility
		local active = swing.ends ~= nil or swing.previewActive
		row:GetFrame():SetShown(enabled and row:IsEnabled()
			and (force or mode == "always" or mode == "combat" and combat or mode == "active" and active))
	end
end

function Feed:Init(component)
	self.component, self.castState, self.swings = component, {}, {}
	for _, row in ipairs(component.SWING_ROWS) do
		self.swings[row.key] = ns.Swing:New(component:GetRow(row.key), row.label)
	end
	self.swingKeys = ns.Caps.swings and {
		[Enum.PlayerSwingType.MainHand] = "mainHand",
		[Enum.PlayerSwingType.OffHand] = "offHand",
		[Enum.PlayerSwingType.Ranged] = "ranged",
	} or {}
end

function Feed:HasSwings()
	if not ns.Caps.swings then return false end
	for key in pairs(self.swings) do
		if self.component:GetRow(key):IsEnabled() and self.component.resolved[key].visibility ~= "hidden" then return true end
	end
	return false
end

function Feed:HasActiveSwings()
	for _, swing in pairs(self.swings) do
		if swing.ends then return true end
	end
	return false
end

function Feed:RegisterEvents(frame)
	frame:UnregisterAllEvents()
	if not self.component:IsEnabled() then return end
	for _, options in ipairs({ self.component.resolved.castbar, self.component.resolved.mainHand,
		self.component.resolved.offHand, self.component.resolved.ranged }) do
		if options.enabled and options.visibility == "combat" then
			frame:RegisterEvent("PLAYER_REGEN_DISABLED")
			frame:RegisterEvent("PLAYER_REGEN_ENABLED")
			break
		end
	end
	local castbar = self.component:GetCastbar()
	if self:HasCastbar() then
		frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		for _, event in ipairs(ns.Cast.EVENTS) do frame:RegisterUnitEvent(event, "player") end
		if castbar:WantsGCD() then
			for _, event in ipairs(ns.Cast.GCD_EVENTS) do frame:RegisterEvent(event) end
		end
	end
	if not self:HasSwings() then return end
	for _, event in ipairs(self.EVENTS) do
		if event == "UNIT_ATTACK_SPEED" then frame:RegisterUnitEvent(event, "player")
		else frame:RegisterEvent(event) end
	end
end

function Feed:ClearCast()
	self.castState = {}
	local castbar = self.component:GetCastbar()
	castbar:Hide()
	castbar:StopGCD()
	if castbar.timeBinding then castbar.timeBinding:SetEnabled(false) end
end

function Feed:Clear()
	self:ClearCast()
	for _, swing in pairs(self.swings) do swing:Clear() end
	self:RefreshVisibility()
end

function Feed:RefreshWeapons(reset)
	if not self:HasSwings() then
		for _, swing in pairs(self.swings) do swing:Clear() end
		return
	end
	local speeds = { UnitAttackSpeed("player") }
	for index, row in ipairs(self.component.SWING_ROWS) do
		local speed = speeds[index]
		if reset or not self.component:GetRow(row.key):IsEnabled()
			or self.component.resolved[row.key].visibility == "hidden" or type(speed) == "nil"
			or not ns.Util.IsSecret(speed) and speed <= 0 then self.swings[row.key]:Clear() end
	end
end

function Feed:Refresh()
	if not self.component:IsEnabled() then self:Clear(); return end
	self:RefreshWeapons(false)
	local castbar = self.component:GetCastbar()
	if self:HasCastbar() then ns.Cast.Refresh(castbar, self.castState, "player")
	else self:ClearCast() end
	self:RefreshVisibility()
end

function Feed:Handle(event, ...)
	if not self.component:IsEnabled() then return end
	if event == "PLAYER_SWING" then
		local seconds, swingType = ...
		if ns.Util.IsSecret(swingType) then return end
		local key = self.swingKeys[swingType]
		if key and self.component.resolved[key].visibility ~= "hidden" then self.swings[key]:Start(seconds) end
	elseif event == "WEAPON_SLOT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		self:RefreshWeapons(true)
		if event == "PLAYER_ENTERING_WORLD" then self:Refresh() end
	elseif event == "UNIT_ATTACK_SPEED" then
		if (...) == "player" then self:RefreshWeapons(false) end
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		ns.Cast.UpdateGCD(self.component:GetCastbar(), self.castState)
	elseif (...) == "player" and self:HasCastbar() then
		ns.Cast.Handle(self.component:GetCastbar(), self.castState, event, ...)
	end
	self:RefreshVisibility()
end

function Feed:Tick()
	for _, swing in pairs(self.swings) do swing:Tick() end
	self:RefreshVisibility()
end

function Feed:Release()
	self:Clear()
	for _, swing in pairs(self.swings) do swing:Release() end
end
