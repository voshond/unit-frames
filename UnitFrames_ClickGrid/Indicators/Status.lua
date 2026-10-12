local _, CG = ...
local UF = CG.UF

--[[
Group status indicators on a member bar: role, leader/assistant, ready check,
dead/ghost, resurrection, summon, phase, threat and private aura anchors.
Widgets are fields named after their oUF elements (status.GroupRoleIndicator,
...); ready checks use the shared UnitFrame state instead of a second oUF
element. Each placed icon has an ordinary host in the UnitFrame's
DecorationStack. Live frames bind them to oUF, previews call
ShowSample. Only configured geometry positions them.

spec: { unitFrame = the member UnitFrame, live = bind oUF elements on the parent button }
]]
local Status = UF.Component:Extend("ClickGridStatus")
CG.Status = Status
Status.schema = CG.IndicatorSchema

-- Fixed-position icons: { element, option key, point, x, y }.
local FIXED = {
	{ "PhaseIndicator", "phase", "BOTTOMRIGHT", -1, 1 },
}

-- Stacked icons: { option prefix, elements sharing one host }.
local PLACED = {
	{ "role", { "GroupRoleIndicator" } },
	{ "leader", { "LeaderIndicator", "AssistantIndicator" } },
	{ "ready", { "ReadyCheckIndicator" } },
	{ "death", { "UFCG_DeathIndicator" } },
	{ "resurrection", { "ResurrectIndicator" } },
	{ "summon", { "SummonIndicator" } },
}

-- Spirit healer artwork used by the original resurrection indicator.
local DEATH_ATLAS = "RaidFrame-Icon-Rez"

--[[
UFCG_DeathIndicator: a texture shown while the unit is dead or a ghost.
Releasing changes health, so UNIT_HEALTH also covers other members becoming
ghosts. An opaque state counts as alive, like oUF's opaque leader flag.
]]
local function UpdateDeath(frame)
	local element, unit = frame.UFCG_DeathIndicator, frame.__unit
	local dead, ghost = false, false
	if unit then dead, ghost = UnitIsDead(unit), UnitIsGhost(unit) end
	if issecretvalue(dead) then dead = false end
	if issecretvalue(ghost) then ghost = false end
	if dead or ghost then
		element:SetAtlas(DEATH_ATLAS)
		element:Show()
	else
		element:Hide()
	end
	if element.PostUpdate then element:PostUpdate(dead, ghost) end
end

local function EnableDeath(frame)
	if not frame.UFCG_DeathIndicator then return end
	frame:RegisterEvent("UNIT_HEALTH", UpdateDeath)
	frame:RegisterEvent("UNIT_CONNECTION", UpdateDeath)
	for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
		frame:RegisterEvent(event, UpdateDeath, true)
	end
	return true
end

local function DisableDeath(frame)
	for _, event in ipairs({ "UNIT_HEALTH", "UNIT_CONNECTION", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
		frame:UnregisterEvent(event, UpdateDeath)
	end
	local element = frame.UFCG_DeathIndicator
	element:Hide()
	if element.PostUpdate then element:PostUpdate(false, false) end
end

UF.oUF:AddElement("UFCG_DeathIndicator", UpdateDeath, EnableDeath, DisableDeath)

local threatCurve
local function Threat(frame)
	if not frame.__unit then return end
	local status = UnitThreatSituation(frame.__unit)
	if type(status) == "nil" then status = 0 end
	if not threatCurve then
		threatCurve = C_CurveUtil.CreateColorCurve()
		threatCurve:AddPoint(0, CreateColor(1, 0, 0, 0))
		threatCurve:AddPoint(1, CreateColor(1, 0.6, 0, 0.4))
		threatCurve:AddPoint(2, CreateColor(1, 0.3, 0, 0.8))
		threatCurve:AddPoint(3, CreateColor(1, 0, 0, 1))
	end
	frame.ThreatIndicator:SetVertexColor(threatCurve:Evaluate(status):GetRGBA())
	frame.ThreatIndicator:Show()
end

function Status:SetResurrection(incoming)
	self.incomingResurrection = incoming
	local icon = self.ResurrectIndicator
	icon:SetAlphaFromBoolean(incoming, 1, 0)
	if issecretvalue(incoming) then icon:Show() else icon:SetShown(incoming) end
	self:UpdateResurrectionText()
	if icon.PostUpdate then icon:PostUpdate() end
end

function Status:UpdateResurrectionText()
	local row = self.unitFrame:GetRow("health")
	if not row then return end
	local cfg = self.resolved
	local color = not self.released and cfg.resurrection and cfg.resurrectionText and CreateColor(0, 1, 0, 1) or nil
	for _, text in pairs(row.texts) do
		text:SetColorCondition(self.incomingResurrection, color)
	end
end

local function Host(parent)
	local host = CreateFrame("Frame", nil, parent)
	host:EnableMouse(false)
	return host
end

function Status:OnCreate(button, spec)
	self.button, self.unitFrame, self.live = button, spec.unitFrame, spec.live
	-- Textures directly on the unit button render below its child bars,
	-- regardless of OVERLAY draw layer. Use a raised, click-through host.
	local overlay = Host(button)
	overlay:SetAllPoints(button)
	overlay:SetFrameLevel(button:GetFrameLevel() + 20)
	self.frame = overlay

	-- oUF calls these after native updates, also in combat: only plain
	-- addon hosts move, never the protected button.
	local function Reflow()
		if not self.released then self.unitFrame:GetDecorations():Reflow() end
	end
	self.hosts = {}
	for _, item in ipairs(PLACED) do
		local ready = item[1] == "ready" and self:Own(UF.Components.ReadyCheckIcon:New(overlay, {})) or nil
		if ready then
			ready.stackKey = "ready"
			self.unitFrame.readyCheckIcon = ready
			self.readyCheckIcon = ready
		end
		local host = ready and ready:GetFrame() or Host(overlay)
		self.hosts[item[1]] = host
		for _, element in ipairs(item[2]) do
			local icon = ready and ready:GetWidget() or host:CreateTexture(nil, "OVERLAY")
			icon:SetAllPoints(host)
			icon.PostUpdate = Reflow
			icon:Hide()
			self[element] = icon
		end
	end
	for _, def in ipairs(FIXED) do
		if def[1] == "PhaseIndicator" then
			local host = Host(overlay)
			host.Icon = host:CreateTexture(nil, "OVERLAY")
			host.Icon:SetAllPoints()
			self[def[1]] = host
		else
			self[def[1]] = overlay:CreateTexture(nil, "OVERLAY")
		end
		self[def[1]]:Hide()
	end

	local threat = overlay:CreateTexture(nil, "OVERLAY")
	threat:SetTexture([[Interface\RAIDFRAME\UI-RaidFrame-Threat]])
	threat.Override = Threat
	threat:SetAllPoints(button)
	threat:Hide()
	self.ThreatIndicator = threat
	self.incomingResurrection = false
	self.ResurrectIndicator.Override = function(frame)
		if self.released then return end
		local incoming = false
		if frame.__unit then incoming = UnitHasIncomingResurrection(frame.__unit) end
		self:SetResurrection(incoming)
	end

	local private = CreateFrame("Frame", nil, overlay)
	private:SetPoint("CENTER", button, "CENTER", 0, 0)
	-- Pre-create all addon anchors. Blizzard owns the actual aura art.
	private.num, private.maxCols = 3, 3
	for i = 1, 3 do
		local anchor = CreateFrame("Frame", nil, private)
		anchor.Icon = CreateFrame("Frame", nil, anchor)
		anchor.Icon:SetAllPoints()
		private[i] = anchor
	end
	self.PrivateAuras = private
end

-- Ordinary unassigned roles (including solo) take no space; opaque roles
-- cannot drive addon layout and keep their slot (nil). Previews and clients
-- without the enum follow the icon's own visibility.
function Status:RolePresent()
	local unit = self.button.__unit
	if not unit then return nil end
	local assigned = UnitGroupRolesAssignedEnum(unit)
	if issecretvalue(assigned) then return nil end
	return assigned == Enum.LFGRole.Tank or assigned == Enum.LFGRole.Healer or assigned == Enum.LFGRole.Damage
end

-- Declares the placed icons in the member's stack. Configured geometry
-- only: no reads of native icon dimensions.
function Status:LayoutIcons()
	local cfg, stack = self.resolved, self.unitFrame:GetDecorations()
	self.readyCheckIcon:Apply(UF.IconPlacement.Read(cfg, UF.IconPlacement.PrefixedKeys("ready")))
	self.readyCheckIcon:Layout(self.unitFrame:GetLayoutContext())
	self.frame:SetFrameLevel(self.button:GetFrameLevel() + 20)
	local function RolePresent() return self:RolePresent() end
	local function ResurrectionPresent()
		if issecretvalue(self.incomingResurrection) then return nil end
		return self.incomingResurrection
	end
	for _, item in ipairs(PLACED) do
		local key, widgets = item[1], {}
		for i, element in ipairs(item[2]) do widgets[i] = self[element] end
		if key ~= "ready" then
			local placement = UF.IconPlacement.Read(cfg, UF.IconPlacement.PrefixedKeys(key))
			local present = key == "role" and self.live and CG.Caps.roleEnum and RolePresent
				or key == "resurrection" and ResurrectionPresent or nil
			stack:Set(key, UF.IconPlacement.Member(placement, self.hosts[key], widgets, present))
		end
	end
	stack:Reflow()
end

function Status:OnApply(cfg)
	local button, live = self.button, self.live
	local function Bind(element, widget)
		if live then UF.Units.SetElement(button, element, widget) end
	end
	for _, item in ipairs(PLACED) do
		for _, element in ipairs(item[2]) do
			-- The member's UF_ReadyCheck drives the shared icon and bar tints.
			if item[1] ~= "ready" then Bind(element, cfg[item[1]] and self[element] or nil) end
			if not cfg[item[1]] then self[element]:Hide() end
		end
	end
	for _, def in ipairs(FIXED) do
		local widget = self[def[1]]
		widget:SetSize(cfg.size, cfg.size)
		widget:ClearAllPoints()
		widget:SetPoint(def[3], button, def[3], def[4], def[5])
		Bind(def[1], cfg[def[2]] and widget or nil)
		if not cfg[def[2]] then widget:Hide() end
	end
	Bind("ThreatIndicator", cfg.threat and UF.Caps.curves and self.ThreatIndicator or nil)
	if not cfg.threat then self.ThreatIndicator:Hide() end
	local private = self.PrivateAuras
	private.size, private.spacing = cfg.privateSize, 2
	private:SetSize(3 * (cfg.privateSize + 2), cfg.privateSize)
	for i = 1, 3 do
		private[i]:SetSize(cfg.privateSize, cfg.privateSize)
		private[i]:ClearAllPoints()
		private[i]:SetPoint("LEFT", private, "LEFT", (i - 1) * (cfg.privateSize + 2), 0)
	end
	Bind("PrivateAuras", cfg.private and CG.Caps.privateAuras and private or nil)
	private:SetShown(cfg.private and CG.Caps.privateAuras)
	if not cfg.resurrection then self:SetResurrection(false) end
	self:UpdateResurrectionText()
	-- After binding: disabled elements have hidden their art.
	self:LayoutIcons()
	Bind("UF_ReadyCheck", self.unitFrame:IsReadyCheckShown() and self.unitFrame or nil)
	self.unitFrame:ApplyReadyCheck()
end

function Status:OnRelease()
	self:SetResurrection(false)
	self.unitFrame.readyCheckIcon = nil
	local stack = self.unitFrame:GetDecorations()
	for _, item in ipairs(PLACED) do stack:Remove(item[1]) end
	stack:Reflow()
end

-- Live previews show no sample status art.
function Status:HideIndicators()
	self:SetResurrection(false)
	for _, item in ipairs(PLACED) do
		for _, element in ipairs(item[2]) do self[element]:Hide() end
	end
	for _, def in ipairs(FIXED) do self[def[1]]:Hide() end
	self.ThreatIndicator:Hide()
	self.PrivateAuras:Hide()
	self.unitFrame:GetDecorations():Reflow()
end

-- Plain sample art for preview member `index`. `ready` is the member's
-- sample ready check { status, amount } (UnitFrame:GetReadyCheckState), or
-- nil for the static placement sample.
function Status:ShowSample(index, ready)
	local cfg = self.resolved
	self.GroupRoleIndicator:SetAtlas(index == 1 and "UI-LFG-RoleIcon-Tank-Micro-Raid"
		or index == 2 and "UI-LFG-RoleIcon-Healer-Micro-Raid" or "UI-LFG-RoleIcon-DPS-Micro-Raid")
	self.GroupRoleIndicator:SetShown(cfg.role)
	self.LeaderIndicator:SetAtlas("UI-HUD-UnitFrame-Player-Group-LeaderIcon")
	self.LeaderIndicator:SetShown(cfg.leader and index == 1)
	self.AssistantIndicator:SetTexture([[Interface\GroupFrame\UI-Group-AssistantIcon]])
	self.AssistantIndicator:SetShown(cfg.leader and index == 2)
	if ready then
		local status, amount = ready[1], ready[2]
		self.readyCheckIcon:SetStatus(cfg.ready and status or nil, amount)
	else
		self.readyCheckIcon:SetStatus(cfg.ready and index == 2 and "ready" or nil, 1)
	end
	-- Member 3 is dead with a resurrection on the way; member 5 is a ghost.
	self.UFCG_DeathIndicator:SetAtlas(DEATH_ATLAS)
	self.UFCG_DeathIndicator:SetShown(cfg.death and (index == 3 or index == 5))
	self.ResurrectIndicator:SetAtlas("RaidFrame-Icon-Rez")
	self:SetResurrection(cfg.resurrection and index == 3)
	self.SummonIndicator:SetAtlas("RaidFrame-Icon-SummonPending")
	self.SummonIndicator:SetShown(cfg.summon and index == 4)
	self.PhaseIndicator:Hide()
	self.ThreatIndicator:SetVertexColor(1, 0, 0, 1)
	self.ThreatIndicator:SetShown(cfg.threat and index == 1)
	self.unitFrame:GetDecorations():Reflow()
end
