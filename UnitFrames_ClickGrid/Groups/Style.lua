local _, CG = ...
local UF, oUF = CG.UF, CG.UF.oUF
CG.STYLE = "UnitFramesClickGrid"

-- Fixed slots share the member's aura artwork config (including its on/off
-- state) and add their own slot groups; both resolve against the theme.
local function BuildSlotConfig(_, _, slots, uf)
	return UF.Util.Merge(UF.Util.Copy(uf:ChildConfig("auras")), UF.Util.Copy(slots or {}))
end

function CG:SlotConfig(uf)
	return UF.Schema.Memo(BuildSlotConfig, uf:GetSchema(), uf.config, self.Config:Get().slots, uf)
end

-- Status indicators and fixed slots belong to the member UnitFrame, sharing
-- its combat deferral, theme management and release.
function CG:AddMemberExtras(uf, button, live)
	local status = uf:Own(self.Status:New(button, self.Config:GetIndicators(), { unitFrame = uf, live = live }))
	local slots = uf:Own(self.Slots:New(button, self:SlotConfig(uf)))
	return status, slots
end

-- Frame-free style schema of a member/target bar (cached).
function CG:StyleSchema(kind)
	self.styleSchemas = self.styleSchemas or {}
	if not self.styleSchemas[kind] then
		local schema = UF.Schema.Build(UF.Components.UnitFrame.BuildSchema, UF.Units:GetSpec(self.definitions[kind]))
		if kind == "pet" then
			schema = UF.Schema.Concat(CG.PetSchema, schema)
		end
		if kind == "target" then
			schema = UF.Schema.Concat(schema, {
				{ key = "emptyText", type = "group", label = "No target text",
					schema = UF.Schema.Concat(UF.Components.Text.BuildSchema({ host = true }), {
						{ key = "label", type = "text", label = "Text", default = "No\nTarget" },
						{ key = "fit", type = "toggle", label = "Fit font to bar height", default = true },
					}), defaults = { color = { 0.6, 0.6, 0.6, 1 }, shadow = false } },
			})
			-- Narrow strips are useful beside a member bar.
			schema = UF.Schema.Override(schema, "width", { min = 20 })
			table.insert(schema, 1, { key = "shown", type = "toggle", label = "Show member targets", default = false,
				tooltip = "Shows a target bar beside each member, as tall as the member's bar. Hidden targets stop all unit updates." })
		end
		self.styleSchemas[kind] = schema
	end
	return self.styleSchemas[kind]
end

function CG:Measure()
	self.metrics = {}
	for _, kind in ipairs({ "member", "target" }) do
		local layout = UF.UnitFrameLayout.Compute(UF.Units:GetSpec(self.definitions[kind]), self.Config.styles[kind]:Resolved())
		self.metrics[kind] = { width = layout.width, height = layout.height }
	end
	self.metrics.target.shown = self:TargetsShown()
	local pet = self.Config.styles.pet:Resolved()
	local layout = UF.UnitFrameLayout.Compute(UF.Units:GetSpec(self.definitions.pet), pet, self.metrics.member.height)
	self.metrics.pet = { width = layout.width, height = layout.height, mode = pet.display, gap = pet.gap, side = pet.side }
end

function CG:TargetsShown()
	return self.Config.styles.target:Resolved().shown
end

-- ClickGrid's own state per unit button, kept off the secure buttons:
-- { kind = "member" or "target", status, slots, empty } (members have
-- status and slots, targets their empty state).
local buttons = {}

function CG:GetGridButton(frame)
	return buttons[frame]
end

function CG:StyleFrame(frame, kind)
	local target = frame:GetAttribute("ufcg-target")
	kind = kind or (frame:GetAttribute("ufcg-pet") and "pet" or target and "target" or "member")
	local button = { kind = kind }
	buttons[frame] = button
	frame.uf = UF.Units:CreateFromDefinition(CG.definitions[kind], frame, CG.Config:GetStyle(kind), frame)
	frame.uf:SetCombatDeferred(true)
	frame.uf:SetThemeManaged(true)
	frame:RegisterForClicks("AnyUp")
	frame:HookScript("OnEnter", UF.Units.ShowTooltip)
	frame:HookScript("OnLeave", UF.Units.HideTooltip)
	UF.Units:Bind(frame)
	if target then button.empty = CG.EmptyTarget:New(frame:GetParent(), frame)
	elseif kind == "member" then
		button.status, button.slots = CG:AddMemberExtras(frame.uf, frame, true)
		UF.Units.SetElement(frame, "UFCG_Slots", button.slots)
	end
	CG.frames[#CG.frames + 1] = frame
	if kind == "pet" then self:CreatePetHover(frame) end
end

oUF:RegisterStyle(CG.STYLE, function(frame) CG:StyleFrame(frame) end)
oUF:RegisterStyle(CG.STYLE .. "Pet", function(frame) CG:StyleFrame(frame, "pet") end)
