local _, CG = ...
local UF = CG.UF

--[[
Group status indicators on a member bar: role, leader/assistant, ready check,
resurrection, summon, phase, threat and private aura anchors. Widgets are
fields named after their oUF elements (status.GroupRoleIndicator, ...); each
icon's `ufcgHost` is the frame that positions it. Live frames bind them to oUF,
previews call ShowSample. Only configured geometry positions them.

spec: { unitFrame = the member UnitFrame, live = bind oUF elements on the parent button }
]]
local Status = UF.Component:Extend("ClickGridStatus")
CG.Status = Status
Status.schema = CG.IndicatorSchema

-- Fixed-position icons: { element, option key, point, x, y }.
local FIXED = {
	{ "ReadyCheckIndicator", "ready", "CENTER", 0, 0 },
	{ "ResurrectIndicator", "resurrection", "RIGHT", -2, 0 },
	{ "SummonIndicator", "summon", "LEFT", 2, 0 },
	{ "PhaseIndicator", "phase", "BOTTOMRIGHT", -1, 1 },
}

-- Movable icons and the option prefix of their settings.
local PLACED = { { "GroupRoleIndicator", "role" }, { "LeaderIndicator", "leader" }, { "AssistantIndicator", "leader" } }

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

local function Resurrection(frame)
	if not frame.__unit then return end
	frame.ResurrectIndicator:SetAlphaFromBoolean(UnitHasIncomingResurrection(frame.__unit), 1, 0)
	frame.ResurrectIndicator:Show()
end

local function Host(parent)
	local host = CreateFrame("Frame", nil, parent)
	host:EnableMouse(false)
	return host
end

function Status:OnCreate(button, spec)
	self.button, self.unitFrame, self.live = button, spec.unitFrame, spec.live
	self.nameText = nil -- the text currently given leading space
	-- Textures directly on the unit button render below its child bars,
	-- regardless of OVERLAY draw layer. Use a raised, click-through host.
	local overlay = Host(button)
	overlay:SetAllPoints(button)
	overlay:SetFrameLevel(button:GetFrameLevel() + 20)
	self.frame = overlay

	local roleHost = Host(overlay)
	local role = roleHost:CreateTexture(nil, "OVERLAY")
	role:SetAllPoints(roleHost)
	role.ufcgHost = roleHost
	-- oUF calls this after native role updates, also in combat: only plain
	-- addon hosts move, never the protected button.
	role.PostUpdate = function()
		if self.resolved and not self.released then self:LayoutIcons() end
	end
	role:Hide()
	self.GroupRoleIndicator = role

	local leaderHost = Host(overlay)
	for _, key in ipairs({ "LeaderIndicator", "AssistantIndicator" }) do
		local icon = leaderHost:CreateTexture(nil, "OVERLAY")
		icon:SetAllPoints(leaderHost)
		icon.ufcgHost = leaderHost
		icon:Hide()
		self[key] = icon
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
	self.ResurrectIndicator.Override = Resurrection

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

-- An enabled, left-aligned name text on the health bar (role/leader "NAME").
local function NameText(uf)
	local row = uf:GetRow("health")
	if row:IsEnabled() then
		for _, text in row:EnabledTexts() do
			if text.resolved.justifyH == "LEFT" and (text:GetFormat() == "name" or text:GetFormat() == "level:name") then return text end
		end
	end
end

function Status:ReleaseNameSpace()
	if self.nameText then
		self.nameText:SetLeadingSpace(0)
		self.nameText = nil
	end
end

-- Role and leader positions. Stable configured slots: no reads of native icon
-- visibility, dimensions or live role/leader/marker values. Raid stays first.
function Status:LayoutIcons()
	local cfg, uf, button = self.resolved, self.unitFrame, self.button
	local role, leader = self.GroupRoleIndicator, self.LeaderIndicator
	self.frame:SetFrameLevel(button:GetFrameLevel() + 20)
	self:ReleaseNameSpace()
	local marker = uf and uf:GetRaidTarget()
	local context = uf and uf:GetLayoutContext()
	local previous, names, total = {}, {}, 0
	if marker then
		local anchor, host = marker:GetLayoutSlot()
		if anchor then previous[anchor] = host end
	end
	local nameText = uf and NameText(uf)
	local rolePresent = true
	if self.live and CG.Caps.roleEnum and button.__unit then
		local assigned = UnitGroupRolesAssignedEnum(button.__unit)
		-- Opaque roles cannot drive addon layout. Keep a safe reserved slot;
		-- ordinary unassigned roles (including solo) need no name padding.
		if not issecretvalue(assigned) then
			rolePresent = assigned == Enum.LFGRole.Tank or assigned == Enum.LFGRole.Healer or assigned == Enum.LFGRole.Damage
		end
	end
	for _, item in ipairs({ { role, "role" }, { leader, "leader" } }) do
		local icon, key = item[1], item[2]
		local host, position = icon.ufcgHost, cfg[key .. "Position"]
		local size, gap = cfg[key .. "Size"], cfg[key .. "Gap"]
		local x, y = cfg[key .. "OffsetX"], cfg[key .. "OffsetY"]
		host:ClearAllPoints()
		host:SetSize(size, size)
		local available = cfg[key] and context ~= nil
		if available and position == "NAME" then
			available = nameText ~= nil and (key ~= "role" or rolePresent)
			if available then
				names[#names + 1] = { host = host, size = size, gap = gap }
				total = total + size + gap
			end
		elseif available then
			available = UF.DecorationLayout.Place(host, context, position, size, x, y)
			if available then
				if previous[position] then
					host:ClearAllPoints()
					if position == "LEFT" or position == "RIGHT" then host:SetPoint("TOP", previous[position], "BOTTOM", x, -gap + y)
					else host:SetPoint("LEFT", previous[position], "RIGHT", gap + x, y) end
				end
				previous[position] = host
			end
		end
		host:SetShown(available)
	end
	if nameText and total > 0 then
		self.nameText = nameText
		nameText:SetLeadingSpace(total)
		local consumed = 0
		for _, item in ipairs(names) do
			item.host:SetPoint("RIGHT", nameText:GetFrame(), "LEFT", -(total - consumed - item.size), 0)
			consumed = consumed + item.size + item.gap
		end
	end
end

function Status:OnApply(cfg)
	self:LayoutIcons()
	local button, live = self.button, self.live
	local function Bind(element, widget)
		if live then UF.Units.SetElement(button, element, widget) end
	end
	for _, item in ipairs(PLACED) do
		Bind(item[1], cfg[item[2]] and self[item[1]] or nil)
		if not cfg[item[2]] then self[item[1]]:Hide() end
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
end

function Status:OnRelease()
	self:ReleaseNameSpace()
end

-- Live previews show no sample status art.
function Status:HideIndicators()
	for _, item in ipairs(PLACED) do self[item[1]]:Hide() end
	for _, def in ipairs(FIXED) do self[def[1]]:Hide() end
	self.ThreatIndicator:Hide()
	self.PrivateAuras:Hide()
end

-- Plain sample art for preview member `index`.
function Status:ShowSample(index)
	local cfg = self.resolved
	self.GroupRoleIndicator:SetAtlas(index == 1 and "UI-LFG-RoleIcon-Tank-Micro-Raid"
		or index == 2 and "UI-LFG-RoleIcon-Healer-Micro-Raid" or "UI-LFG-RoleIcon-DPS-Micro-Raid")
	self.GroupRoleIndicator:SetShown(cfg.role)
	self.LeaderIndicator:SetAtlas("UI-HUD-UnitFrame-Player-Group-LeaderIcon")
	self.LeaderIndicator:SetShown(cfg.leader and index == 1)
	self.AssistantIndicator:SetTexture([[Interface\GroupFrame\UI-Group-AssistantIcon]])
	self.AssistantIndicator:SetShown(cfg.leader and index == 2)
	self.ReadyCheckIndicator:SetAtlas("UI-LFG-ReadyMark-Raid")
	self.ReadyCheckIndicator:SetShown(cfg.ready and index == 2)
	self.ResurrectIndicator:SetAtlas("RaidFrame-Icon-Rez")
	self.ResurrectIndicator:SetShown(cfg.resurrection and index == 3)
	self.SummonIndicator:SetAtlas("RaidFrame-Icon-SummonPending")
	self.SummonIndicator:SetShown(cfg.summon and index == 4)
	self.PhaseIndicator:Hide()
	self.ThreatIndicator:SetVertexColor(1, 0, 0, 1)
	self.ThreatIndicator:SetShown(cfg.threat and index == 1)
end
