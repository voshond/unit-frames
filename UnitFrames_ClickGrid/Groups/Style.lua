local _, CG = ...
local UF, oUF = CG.UF, CG.UF.oUF
CG.STYLE = "UnitFramesClickGrid"

-- Fixed slots share the member's aura artwork config (including its on/off
-- state) and add their own slot groups; both resolve against the theme.
function CG:SlotConfig(uf)
	return UF.Util.Merge(uf:ChildConfig("auras"), UF.Util.Copy(self.Config:Get().slots or {}))
end

-- Status indicators and fixed slots belong to the member UnitFrame, sharing
-- its combat deferral, theme management and release.
function CG:AddMemberExtras(uf, button, live)
	local status = uf:Own(self.Status:New(button, self.Config:Get().indicators, { unitFrame = uf, live = live }))
	local slots = uf:Own(self.Slots:New(button, self:SlotConfig(uf)))
	return status, slots
end

-- Frame-free style schema of a member/target bar (cached).
function CG:StyleSchema(kind)
	self.styleSchemas = self.styleSchemas or {}
	if not self.styleSchemas[kind] then
		self.styleSchemas[kind] = UF.Components.UnitFrame.BuildSchema(UF.Units:GetSpec(self.definitions[kind]))
	end
	return self.styleSchemas[kind]
end

function CG:Measure()
	self.metrics = {}
	for _, kind in ipairs({ "member", "target" }) do
		local layout = UF.UnitFrameLayout.Compute(UF.Units:GetSpec(self.definitions[kind]), self.Config.styles[kind]:Resolved())
		self.metrics[kind] = { width = layout.width, height = layout.height }
	end
end

oUF:RegisterStyle(CG.STYLE, function(frame)
	local target = frame:GetAttribute("ufcg-target")
	local kind = target and "target" or "member"
	frame.ufcgKind = kind
	frame.uf = UF.Units:CreateFromDefinition(CG.definitions[kind], frame, CG.Config:GetStyle(kind), frame)
	frame.uf:SetCombatDeferred(true)
	frame.uf:SetThemeManaged(true)
	frame:RegisterForClicks("AnyUp")
	frame:HookScript("OnEnter", UF.Units.ShowTooltip)
	frame:HookScript("OnLeave", UF.Units.HideTooltip)
	UF.Units:Bind(frame)
	if not target then
		frame.ufcgStatus, frame.ufcgSlots = CG:AddMemberExtras(frame.uf, frame, true)
		UF.Units.SetElement(frame, "UFCG_Slots", frame.ufcgSlots)
	end
	CG.frames[#CG.frames + 1] = frame
end)

-- Initialization callbacks run after oUF enables the frame's elements.
oUF:RegisterInitCallback(function(frame)
	if frame.ufcgKind then frame.ufReady = true end
end)
