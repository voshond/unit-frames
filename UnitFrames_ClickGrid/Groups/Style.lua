local _, CG = ...
local UF, oUF = CG.UF, CG.UF.oUF
CG.STYLE = "UnitFramesClickGrid"

function CG:SlotConfig(uf)
	local config = UF.Util.Copy(uf:GetAuras().resolved)
	local slots = self.Config:Resolved().slots
	for key, value in pairs(slots) do config[key] = value end
	return config
end

function CG:Measure()
	self.styleSchemas, self.metrics = self.styleSchemas or {}, {}
	self.prototypes = self.prototypes or {}
	for _, kind in ipairs({ "member", "target" }) do
		local uf = self.prototypes[kind]
		if not uf then
			uf = UF.Units:CreateFromDefinition(self.definitions[kind], UIParent, self.Config:GetStyle(kind))
			self.prototypes[kind] = uf
			uf:SetCombatDeferred(true)
		end
		uf:Apply(self.Config:GetStyle(kind))
		uf:GetFrame():Hide()
		self.styleSchemas[kind] = uf:GetSchema()
		self.metrics[kind] = { width = uf:GetFrame():GetWidth(), height = uf:GetFrame():GetHeight() }
	end
end

local function Tooltip(frame)
	if not frame.__unit then return end
	GameTooltip_SetDefaultAnchor(GameTooltip, frame)
	if GameTooltip:SetUnit(frame.__unit) then GameTooltip:Show() end
end

oUF:RegisterStyle(CG.STYLE, function(frame)
	local target = frame:GetAttribute("ufcg-target")
	local kind = target and "target" or "member"
	frame.ufcgKind = kind
	frame.uf = UF.Units:CreateFromDefinition(CG.definitions[kind], frame, CG.Config:GetStyle(kind), frame)
	frame.uf:SetCombatDeferred(true)
	frame:RegisterForClicks("AnyUp")
	frame:HookScript("OnEnter", Tooltip)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
	UF.Units:Bind(frame)
	if not target then
		frame.ufcgStatus = CG.Status:Create(frame)
		CG.Status:Apply(frame, frame.ufcgStatus, CG.Config:Resolved().indicators, true)
		frame.ufcgSlots = CG.Slots:New(frame, CG:SlotConfig(frame.uf))
		frame.ufcgSlots:SetCombatDeferred(true)
		UF.Units.SetElement(frame, "UFCG_Slots", frame.ufcgSlots)
	end
	CG.frames[#CG.frames + 1] = frame
end)

-- Initialization callbacks run after oUF enables the frame's elements.
oUF:RegisterInitCallback(function(frame)
	if frame.ufcgKind then frame.ufReady = true end
end)
