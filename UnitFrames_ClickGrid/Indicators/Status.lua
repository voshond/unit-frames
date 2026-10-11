local _, CG = ...
local UF = CG.UF
local Status = {}
CG.Status = Status
local definitions = {
	{ "ReadyCheckIndicator", "ready", "CENTER", 0, 0 },
	{ "ResurrectIndicator", "resurrection", "RIGHT", -2, 0 },
	{ "SummonIndicator", "summon", "LEFT", 2, 0 },
	{ "PhaseIndicator", "phase", "BOTTOMRIGHT", -1, 1 },
}

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

function Status:Create(frame, uf)
	local result = {}
	-- Textures directly on the unit button render below its child bars,
	-- regardless of OVERLAY draw layer. Use a raised, click-through host.
	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints(frame)
	overlay:SetFrameLevel(frame:GetFrameLevel() + 20)
	overlay:EnableMouse(false)
	local roleHost = CreateFrame("Frame", nil, overlay)
	roleHost:EnableMouse(false)
	local role = roleHost:CreateTexture(nil, "OVERLAY")
	role:SetAllPoints(roleHost)
	role.ufcgHost, role.ufcgOverlay, role.ufcgUnitFrame = roleHost, overlay, uf
	role.ufcgNameText = false
	role.PostUpdate = function()
		if role.ufcgStatusConfig then Status:LayoutIcons(frame, result, role.ufcgStatusConfig) end
	end
	role:Hide()
	result.GroupRoleIndicator = role
	local leaderHost = CreateFrame("Frame", nil, overlay)
	leaderHost:EnableMouse(false)
	for _, key in ipairs({ "LeaderIndicator", "AssistantIndicator" }) do
		local icon = leaderHost:CreateTexture(nil, "OVERLAY")
		icon:SetAllPoints(leaderHost)
		icon.ufcgHost = leaderHost
		icon:Hide()
		result[key] = icon
	end
	result.LeaderIndicator.ufcgNameText = false
	for _, def in ipairs(definitions) do
		if def[1] == "PhaseIndicator" then
			local host = CreateFrame("Frame", nil, overlay)
			host.Icon = host:CreateTexture(nil, "OVERLAY")
			host.Icon:SetAllPoints()
			host:EnableMouse(false)
			result[def[1]] = host
		else result[def[1]] = overlay:CreateTexture(nil, "OVERLAY") end
		result[def[1]]:Hide()
	end
	local threat = overlay:CreateTexture(nil, "OVERLAY")
	threat:SetTexture([[Interface\RAIDFRAME\UI-RaidFrame-Threat]])
	threat.Override = Threat
	threat:SetAllPoints(frame)
	threat:Hide()
	result.ThreatIndicator = threat
	result.ResurrectIndicator.Override = Resurrection
	local private = CreateFrame("Frame", nil, overlay)
	private:SetPoint("CENTER", frame, "CENTER", 0, 0)
	-- Pre-create all addon anchors. Blizzard owns the actual aura art.
	private.num, private.maxCols = 3, 3
	for i = 1, 3 do
		local anchor = CreateFrame("Frame", nil, private)
		anchor.Icon = CreateFrame("Frame", nil, anchor)
		anchor.Icon:SetAllPoints()
		private[i] = anchor
	end
	result.PrivateAuras = private
	return result
end

local function NameText(uf)
	local row = uf:GetRow("health")
	if row:IsEnabled() then
		for _, text in row:EnabledTexts() do
			if text.resolved.justifyH == "LEFT" and (text:GetFormat() == "name" or text:GetFormat() == "level:name") then return text end
		end
	end
end

function Status:LayoutIcons(frame, widgets, cfg)
	local role, leader = widgets.GroupRoleIndicator, widgets.LeaderIndicator
	local uf = role.ufcgUnitFrame
	role.ufcgOverlay:SetFrameLevel(frame:GetFrameLevel() + 20)
	for _, icon in ipairs({ role, leader }) do
		if icon.ufcgNameText then
			icon.ufcgNameText:SetLeadingSpace(0)
			icon.ufcgNameText = false
		end
	end
	local marker = uf and uf:GetRaidTarget()
	local context = uf and uf:GetLayoutContext()
	local previous, names, total = {}, {}, 0
	if marker then
		local anchor, host = marker:GetLayoutSlot()
		if anchor then previous[anchor] = host end
	end
	local nameText = uf and NameText(uf)
	local rolePresent = true
	if role.ufcgLive and CG.Caps.roleEnum and frame.__unit then
		local assigned = UnitGroupRolesAssignedEnum(frame.__unit)
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
			available = nameText ~= nil
			if key == "role" and not rolePresent then available = false end
			if available then
				icon.ufcgNameText = nameText
				names[#names + 1] = { host = host, size = size, gap = gap }
				total = total + size + gap
			end
		elseif available then
			available = UF.DecorationLayout.Place(host, context, position, size, x, y)
			if available then
				-- Stable configured slots: no reads of native icon visibility,
				-- dimensions or live role/leader/marker values. Raid stays first.
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
		nameText:SetLeadingSpace(total)
		local consumed = 0
		for _, item in ipairs(names) do
			item.host:SetPoint("RIGHT", nameText:GetFrame(), "LEFT", -(total - consumed - item.size), 0)
			consumed = consumed + item.size + item.gap
		end
	end
end

function Status:Release(widgets)
	local role = widgets.GroupRoleIndicator
	role.ufcgStatusConfig = nil
	for _, icon in ipairs({ role, widgets.LeaderIndicator }) do
		if icon.ufcgNameText then icon.ufcgNameText:SetLeadingSpace(0); icon.ufcgNameText = false end
	end
	role.ufcgOverlay:Hide()
end

function Status:Apply(frame, widgets, cfg, live)
	widgets.GroupRoleIndicator.ufcgStatusConfig, widgets.GroupRoleIndicator.ufcgLive = cfg, live
	self:LayoutIcons(frame, widgets, cfg)
	for _, item in ipairs({ { "GroupRoleIndicator", "role" }, { "LeaderIndicator", "leader" }, { "AssistantIndicator", "leader" } }) do
		if live then UF.Units.SetElement(frame, item[1], cfg[item[2]] and widgets[item[1]] or nil) end
		if not cfg[item[2]] then widgets[item[1]]:Hide() end
	end
	for _, def in ipairs(definitions) do
		local widget = widgets[def[1]]
		widget:SetSize(cfg.size, cfg.size)
		widget:ClearAllPoints()
		widget:SetPoint(def[3], frame, def[3], def[4], def[5])
		if live then UF.Units.SetElement(frame, def[1], cfg[def[2]] and widget or nil) end
		if not cfg[def[2]] then widget:Hide() end
	end
	if live then UF.Units.SetElement(frame, "ThreatIndicator", cfg.threat and UF.Caps.curves and widgets.ThreatIndicator or nil) end
	if not cfg.threat then widgets.ThreatIndicator:Hide() end
	local private = widgets.PrivateAuras
	private.size, private.spacing = cfg.privateSize, 2
	private:SetSize(3 * (cfg.privateSize + 2), cfg.privateSize)
	for i = 1, 3 do
		private[i]:SetSize(cfg.privateSize, cfg.privateSize)
		private[i]:ClearAllPoints()
		private[i]:SetPoint("LEFT", private, "LEFT", (i - 1) * (cfg.privateSize + 2), 0)
	end
	if live then UF.Units.SetElement(frame, "PrivateAuras", cfg.private and CG.Caps.privateAuras and private or nil) end
	private:SetShown(cfg.private and CG.Caps.privateAuras)
end

function Status:Sample(widgets, cfg, index)
	widgets.GroupRoleIndicator:SetAtlas(index == 1 and "UI-LFG-RoleIcon-Tank-Micro-Raid"
		or index == 2 and "UI-LFG-RoleIcon-Healer-Micro-Raid" or "UI-LFG-RoleIcon-DPS-Micro-Raid")
	widgets.GroupRoleIndicator:SetShown(cfg.role)
	widgets.LeaderIndicator:SetAtlas("UI-HUD-UnitFrame-Player-Group-LeaderIcon")
	widgets.LeaderIndicator:SetShown(cfg.leader and index == 1)
	widgets.AssistantIndicator:SetTexture([[Interface\GroupFrame\UI-Group-AssistantIcon]])
	widgets.AssistantIndicator:SetShown(cfg.leader and index == 2)
	widgets.ReadyCheckIndicator:SetAtlas("UI-LFG-ReadyMark-Raid")
	widgets.ReadyCheckIndicator:SetShown(cfg.ready and index == 2)
	widgets.ResurrectIndicator:SetAtlas("RaidFrame-Icon-Rez")
	widgets.ResurrectIndicator:SetShown(cfg.resurrection and index == 3)
	widgets.SummonIndicator:SetAtlas("RaidFrame-Icon-SummonPending")
	widgets.SummonIndicator:SetShown(cfg.summon and index == 4)
	widgets.PhaseIndicator:Hide()
	widgets.ThreatIndicator:SetVertexColor(1, 0, 0, 1)
	widgets.ThreatIndicator:SetShown(cfg.threat and index == 1)
end
