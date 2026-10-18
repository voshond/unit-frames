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

local PLACEMENT_KEYS = {}
for _, item in ipairs(PLACED) do PLACEMENT_KEYS[item[1]] = UF.IconPlacement.PrefixedKeys(item[1]) end

-- Private aura row offsets from the cell edge it sits on.
local PRIVATE_INSETS = { RIGHT = { -2, 0 }, LEFT = { 2, 0 }, TOP = { 0, -2 }, BOTTOM = { 0, 2 }, CENTER = { 0, 0 } }

-- Blizzard's compact raid frame aggro highlight, made to cover a whole frame.
-- (UI-RaidFrame-Threat is an 8px status dot and turns into a diamond when stretched.)
local THREAT_ATLAS = "RaidFrame-AgroFrame"

-- Spirit healer artwork used by the original resurrection indicator.
local DEATH_ATLAS = "RaidFrame-Icon-Rez"
local RESURRECTION_COLOR = CreateColor(0, 1, 0, 1)

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
	local present = dead or ghost
	if element.deathPresent == present then return end
	element.deathPresent = present
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
	frame.UFCG_DeathIndicator.deathPresent = nil
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
	element.deathPresent = nil
	element:Hide()
	if element.PostUpdate then element:PostUpdate(false, false) end
end

UF.oUF:AddElement("UFCG_DeathIndicator", UpdateDeath, EnableDeath, DisableDeath)

-- The threat holder carries both presentations; the curve colours whichever is shown.
local function ColorThreat(threat, r, g, b, a)
	threat.Highlight:SetVertexColor(r, g, b, a)
	UF.Glow.SetColor(threat.Glow, r, g, b, a)
end

--[[
UFCG_DispelGlow: a glow around the cell while the member has a dispellable
debuff. Auras are secret, so a hidden native aura slot is the gate: the
engine shows its button only while a matching debuff exists, and tints the
glow pieces registered on it by dispel type (native colours). The glow is
owned by that button but anchored to the whole cell; no aura data is read.
]]
local function UpdateDispel(frame)
	if frame.__unit then frame.UFCG_DispelGlow:SetDispelUnit(frame.__unit) end
end
UF.oUF:AddElement("UFCG_DispelGlow", UpdateDispel, function(frame) return frame.UFCG_DispelGlow ~= nil end, function() end)

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
	ColorThreat(frame.ThreatIndicator, threatCurve:Evaluate(status):GetRGBA())
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
	local color = not self.released and cfg.resurrection and cfg.resurrectionText and RESURRECTION_COLOR or nil
	for _, text in pairs(row.texts) do
		text:SetColorCondition(self.incomingResurrection, color)
	end
end

-- Hosts may sit before the member's name, which follows native geometry
-- on native-layout bars: those hosts carry the forbidden layout aspect.
local function Host(parent, native)
	local host = CreateFrame("Frame", nil, parent, native and "DisableUntrustedLayoutScriptsTemplate" or nil)
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
	self.placementWidgets = {}
	local native = self.unitFrame:IsNativeLayout()
	for _, item in ipairs(PLACED) do
		local ready = item[1] == "ready"
			and self:Own(UF.Components.ReadyCheckIcon:New(overlay, {}, { nativeLayout = native })) or nil
		if ready then
			ready.stackKey = "ready"
			self.readyCheckIcon = ready
		end
		local host = ready and ready:GetFrame() or Host(overlay, native)
		self.hosts[item[1]] = host
		local widgets = {}
		self.placementWidgets[item[1]] = widgets
		for _, element in ipairs(item[2]) do
			local icon = ready and ready:GetWidget() or host:CreateTexture(nil, "OVERLAY")
			icon:SetAllPoints(host)
			icon.PostUpdate = Reflow
			icon:Hide()
			self[element] = icon
			widgets[#widgets + 1] = icon
		end
	end
	self.rolePresent = function() return self:RolePresent() end
	self.resurrectionPresent = function()
		if issecretvalue(self.incomingResurrection) then return nil end
		return self.incomingResurrection
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

	local threat = Host(overlay)
	threat:SetAllPoints(button)
	threat.Highlight = threat:CreateTexture(nil, "OVERLAY")
	threat.Highlight:SetAtlas(THREAT_ATLAS)
	threat.Highlight:SetAllPoints()
	threat.Glow = UF.Glow.Create(threat)
	threat.Override = Threat
	threat:Hide()
	self.ThreatIndicator = threat
	-- Mouseover wash above the bars. Hooks cannot be removed: they check state.
	self.hover = overlay:CreateTexture(nil, "ARTWORK")
	self.hover:SetAllPoints(button)
	self.hover:Hide()
	self.hovered = false
	if self.live then
		button:HookScript("OnEnter", function() self:SetHovered(true) end)
		button:HookScript("OnLeave", function() self:SetHovered(false) end)
		-- Native slots are prepared outside combat, like the fixed buff slots.
		self.dispelContainer = CreateFrame("AuraContainer", nil, overlay, "CustomAuraContainerTemplate")
		self.dispelContainer:SetPoint("CENTER", overlay, "CENTER")
		self.dispelContainer:SetEnabled(false)
		self.dispelContainer:AddAuraSlot("dispel", "HARMFUL|RAID", {
			initializeFrame = function(slot) self:InitDispelSlot(slot) end,
		})
	end
	self.incomingResurrection = false
	self.ResurrectIndicator.Override = function(frame)
		if self.released then return end
		local incoming = false
		if frame.__unit then incoming = UnitHasIncomingResurrection(frame.__unit) end
		self:SetResurrection(incoming)
	end

	local private = CreateFrame("Frame", nil, overlay)
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

function Status:SetHovered(hovered)
	self.hovered = hovered
	self.hover:SetShown(hovered and not self.released and self.resolved ~= nil and self.resolved.hover)
end

-- Everything the locked slot button needs is set up once, here.
function Status:InitDispelSlot(slot)
	slot:EnableMouse(false)
	slot:SetMouseClickEnabled(false)
	slot:SetMouseMotionEnabled(false)
	slot:SetSize(1, 1)
	slot:SetPoint("CENTER", self.frame, "CENTER")
	local glow = UF.Glow.Create(slot)
	glow:ClearAllPoints()
	glow:SetAllPoints(self.button)
	glow:Show()
	for _, texture in ipairs(glow.textures) do
		slot:AddDispelTypeTexture(texture, {
			style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
			showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = false,
		})
	end
	self.dispelGlow = glow
end

function Status:SetDispelUnit(unit)
	if self.dispelContainer:GetUnit() ~= unit then self.dispelContainer:SetUnit(unit) end
end

-- The live glow descends from a native aura button, which denies addon access
-- while aura data is secret: restyle it at the next combat end then.
local function RestyleDispel(status)
	UF.Glow.Apply(status.dispelGlow, status.resolved.dispelGlow)
end

function Status:RestyleDispel()
	if InCombatLockdown() then
		UF.AfterCombat:Queue("dispelRestyle", self, Status.RestyleDispel)
		return
	end
	local ok, reason = pcall(RestyleDispel, self)
	if not ok then
		if not UF.AfterCombat:IsQueued(self, "dispelRestyle") then UF.Logs:Error("ClickGrid dispel glow restyle deferred", reason) end
		UF.AfterCombat:Queue("dispelRestyle", self, Status.RestyleDispel)
	else
		UF.AfterCombat:Cancel(self, "dispelRestyle")
	end
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
	self.readyCheckIcon:Apply(UF.Schema.Memo(UF.IconPlacement.Read, cfg, PLACEMENT_KEYS.ready))
	self.readyCheckIcon:Layout(self.unitFrame:GetLayoutContext())
	self.frame:SetFrameLevel(self.button:GetFrameLevel() + 20)
	for _, item in ipairs(PLACED) do
		local key = item[1]
		if key ~= "ready" then
			local placement = UF.Schema.Memo(UF.IconPlacement.Read, cfg, PLACEMENT_KEYS[key])
			local present = key == "role" and self.live and CG.Caps.roleEnum and self.rolePresent
				or key == "resurrection" and self.resurrectionPresent or nil
			stack:Set(key, UF.IconPlacement.Member(placement, self.hosts[key], self.placementWidgets[key], present))
		end
	end
	stack:Reflow()
end

local function Apply(self, cfg)
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
	local threat, glow = self.ThreatIndicator, cfg.threatStyle == "glow"
	threat.Highlight:SetShown(not glow)
	threat.Glow:SetShown(glow)
	if glow then
		UF.Glow.Apply(threat.Glow, cfg.threatGlow)
	end
	Bind("ThreatIndicator", cfg.threat and UF.Caps.curves and threat or nil)
	if not cfg.threat then threat:Hide() end
	if self.dispelContainer then
		self.dispelContainer:SetAuraSlotFilterString("dispel", cfg.dispelFilter)
		self.dispelContainer:SetEnabled(cfg.dispel)
		self.dispelContainer:SetShown(cfg.dispel)
		self:RestyleDispel()
	end
	Bind("UFCG_DispelGlow", cfg.dispel and self.dispelContainer and self or nil)
	self.hover:SetColorTexture(UF.Util.UnpackColor(cfg.hoverColor))
	self:SetHovered(self.hovered)
	if self.dispelSample then
		UF.Glow.Apply(self.dispelSample, cfg.dispelGlow)
		if not cfg.dispel then self.dispelSample:Hide() end
	end
	local private = self.PrivateAuras
	private.size, private.spacing = cfg.privateSize, 2
	private:SetSize(3 * (cfg.privateSize + 2), cfg.privateSize)
	local inset = PRIVATE_INSETS[cfg.privatePosition]
	private:ClearAllPoints()
	private:SetPoint(cfg.privatePosition, button, cfg.privatePosition, inset[1], inset[2])
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
	self.unitFrame:GetReadyCheck():Attach(self.readyCheckIcon)
end

function Status:OnApply(cfg)
	self.unitFrame:GetDecorations():Batch(Apply, self, cfg)
end

function Status:OnRelease()
	self:SetResurrection(false)
	self.hover:Hide()
	-- AuraContainer:SetUnit(nil) asserts: disable instead.
	if self.dispelContainer then
		self.dispelContainer:SetEnabled(false)
		UF.AfterCombat:Cancel(self, "dispelRestyle")
	end
	local readyCheck = self.unitFrame:GetReadyCheck()
	if readyCheck then readyCheck:Detach(self.readyCheckIcon) end
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
	if self.dispelSample then self.dispelSample:Hide() end
	self.PrivateAuras:Hide()
	self.unitFrame:GetDecorations():Reflow()
end

-- The first sample debuff the dispel filter would show, if any.
local function SampleDispel(cfg, debuffs)
	for _, aura in ipairs(debuffs or {}) do
		local typed = aura.dispelName ~= nil and aura.dispelName ~= "None"
		if typed and (cfg.dispelFilter ~= "HARMFUL|RAID" or aura.isRaid) then return aura end
	end
end

-- Plain sample art for preview member `index`. `ready` is the member's
-- simulated check flag; false/nil uses the static placement sample.
-- `values` are the member's sample values (debuffs light the dispel glow).
function Status:ShowSample(index, ready, values)
	local cfg = self.resolved
	self.GroupRoleIndicator:SetAtlas(index == 1 and "UI-LFG-RoleIcon-Tank-Micro-Raid"
		or index == 2 and "UI-LFG-RoleIcon-Healer-Micro-Raid" or "UI-LFG-RoleIcon-DPS-Micro-Raid")
	self.GroupRoleIndicator:SetShown(cfg.role)
	self.LeaderIndicator:SetAtlas("UI-HUD-UnitFrame-Player-Group-LeaderIcon")
	self.LeaderIndicator:SetShown(cfg.leader and index == 1)
	self.AssistantIndicator:SetTexture([[Interface\GroupFrame\UI-Group-AssistantIcon]])
	self.AssistantIndicator:SetShown(cfg.leader and index == 2)
	if not ready then
		-- Placement sample only. A simulated check has already written its icon.
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
	ColorThreat(self.ThreatIndicator, 1, 0, 0, 1)
	self.ThreatIndicator:SetShown(cfg.threat and index == 1)
	local dispel = cfg.dispel and SampleDispel(cfg, values and values.debuffs)
	if dispel then
		if not self.dispelSample then
			self.dispelSample = UF.Glow.Create(self.frame)
			self.dispelSample:ClearAllPoints()
			self.dispelSample:SetAllPoints(self.button)
			UF.Glow.Apply(self.dispelSample, cfg.dispelGlow)
		end
		UF.Glow.SetColor(self.dispelSample, AuraUtil.GetAuraBorderColor(dispel.dispelName):GetRGBA())
	end
	if self.dispelSample then self.dispelSample:SetShown(dispel and true or false) end
	self.unitFrame:GetDecorations():Reflow()
end
