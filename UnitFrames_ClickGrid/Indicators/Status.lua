local _, CG = ...
local UF = CG.UF
local Status = {}
CG.Status = Status
local definitions = {
	{ "GroupRoleIndicator", "role", "TOPLEFT", 1, -1 },
	{ "LeaderIndicator", "leader", "TOP", -8, 0 },
	{ "AssistantIndicator", "leader", "TOP", 8, 0 },
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

function Status:Create(frame)
	local result = {}
	for _, def in ipairs(definitions) do
		if def[1] == "PhaseIndicator" then
			local host = CreateFrame("Frame", nil, frame)
			host.Icon = host:CreateTexture(nil, "OVERLAY")
			host.Icon:SetAllPoints()
			host:EnableMouse(false)
			result[def[1]] = host
		else result[def[1]] = frame:CreateTexture(nil, "OVERLAY") end
		result[def[1]]:Hide()
	end
	local threat = frame:CreateTexture(nil, "OVERLAY")
	threat:SetTexture([[Interface\RAIDFRAME\UI-RaidFrame-Threat]])
	threat.Override = Threat
	threat:SetAllPoints(frame)
	threat:Hide()
	result.ThreatIndicator = threat
	result.ResurrectIndicator.Override = Resurrection
	local private = CreateFrame("Frame", nil, frame)
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

function Status:Apply(frame, widgets, cfg, live)
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
	widgets.AssistantIndicator:Hide()
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
