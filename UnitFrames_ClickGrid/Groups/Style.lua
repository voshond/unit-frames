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
	for _, kind in ipairs({ "member", "target" }) do
		local spec = UF.Units:GetSpec(self.definitions[kind])
		local schema = self.styleSchemas[kind] or UF.Components.UnitFrame.BuildSchema(spec)
		self.styleSchemas[kind] = schema
		local cfg = UF.Schema.Resolve(schema, self.Config:GetStyle(kind), UF.Config:GetTheme())
		local layout = UF.UnitFrameLayout.Compute(spec, cfg)
		self.metrics[kind] = { width = layout.width, height = layout.height }
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
	frame.uf:SetThemeManaged(true)
	frame:RegisterForClicks("AnyUp")
	frame:HookScript("OnEnter", Tooltip)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
	UF.Units:Bind(frame)
	if not target then
		frame.ufcgStatus = CG.Status:Create(frame, frame.uf)
		CG.Status:Apply(frame, frame.ufcgStatus, CG.Config:Resolved().indicators, true)
		frame.ufcgSlots = CG.Slots:New(frame, CG:SlotConfig(frame.uf))
		frame.ufcgSlots:SetCombatDeferred(true)
		frame.ufcgSlots:SetThemeManaged(true)
		UF.Units.SetElement(frame, "UFCG_Slots", frame.ufcgSlots)
	end
	CG.frames[#CG.frames + 1] = frame
end)

-- Initialization callbacks run after oUF enables the frame's elements.
oUF:RegisterInitCallback(function(frame)
	if frame.ufcgKind then frame.ufReady = true end
end)
