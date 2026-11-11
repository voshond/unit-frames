local _, CG = ...
local UF = CG.UF
local Presets = CG.BuffPresets
local Showcase = UF.Object:Extend("ClickGridBuffShowcase")
CG.BuffShowcase = Showcase

-- One card per placement, each a sample member cell showing the selected buff
-- set there, on top of the member's own style. Plain samples only, like the
-- panel preview: no live units, no restricted art.
local CARD_WIDTH, CARD_HEIGHT, GAP, PADDING, HEADER_HEIGHT = 170, 136, 8, 8, 36
local CARDS = {
	{ placement = "outside", title = "Outside", note = "Icons along the cell's edge" },
	{ placement = "inside", title = "Inside", note = "One spell per corner" },
	{ placement = "bar", title = "Aura bar", note = "A strip under the health bar" },
}
local ACTIVE = " |cff4fa3ff(on your frames)|r"
local EMPTY_NOTE = "Your class has no heals or shields to show."

local function Label(parent, size)
	local label = parent:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(UF.Media:GetFontObject(UF.Config:GetTheme().font, size))
	label:SetJustifyH("LEFT")
	return label
end

function Showcase:Init(parent)
	self.frame = CreateFrame("Frame", nil, parent)
	self.frame:SetSize(#CARDS * CARD_WIDTH + (#CARDS - 1) * GAP, CARD_HEIGHT)
	self.selection = UF.Util.Copy(Presets.DEFAULT)
	self.cards = {}
	for index, spec in ipairs(CARDS) do self.cards[index] = self:CreateCard(spec, index) end
	self:Apply()
end

function Showcase:CreateCard(spec, index)
	local frame = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
	frame:SetSize(CARD_WIDTH, CARD_HEIGHT)
	frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (index - 1) * (CARD_WIDTH + GAP), 0)
	UF.Skin.ApplyPanel(frame, "button")
	local card = { spec = spec, frame = frame, title = Label(frame, 12), note = Label(frame, 10) }
	card.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
	card.note:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -2)
	for _, label in ipairs({ card.title, card.note }) do
		label:SetWidth(CARD_WIDTH - 2 * PADDING)
		label:SetWordWrap(false)
	end
	card.host = CreateFrame("Frame", nil, frame)
	card.host:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -HEADER_HEIGHT)
	card.host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING)
	card.member = UF.Units:CreateFromDefinition(CG.definitions.member, card.host, CG.Config:GetStyle("member"))
	card.member:SetCombatDeferred(true)
	card.member:SetThemeManaged(true)
	if spec.placement == "inside" then card.slots = card.member:Own(CG.Slots:New(card.member:GetFrame(), {})) end
	return card
end

function Showcase:Values(class)
	local values = UF.Util.Copy(UF.Units.SAMPLE)
	values.name, values.lastname, values.class, values.className = "Tank", "Example", "WARRIOR", "Warrior"
	values.health = values.healthMax * 0.7
	values.buffs = Presets.Samples(self.selection.preset, class)
	values.debuffs, values.categoryAuras = {}, {}
	values.showCast = false
	return values
end

function Showcase:ApplyCard(card, values, resolved, class, active)
	local placement, preset = card.spec.placement, self.selection.preset
	local style = UF.Util.Copy(CG.Config:GetStyle("member"))
	Presets.EditStyle(style, resolved, preset, placement, self.selection.side)
	card.member:Apply(style)
	card.member:ClearAllPoints()
	card.member:SetPoint("CENTER", card.host, "CENTER", 0, 0)
	UF.Units:ShowSample(card.member, values)
	if card.slots then
		local slots = {}
		Presets.EditSlots(slots, nil, preset, "inside", class)
		card.slots:Apply(UF.Util.Merge(UF.Util.Copy(card.member:ChildConfig("auras")), slots))
		card.slots:SetEnabled(card.slots.resolved.enabled)
		card.slots:ShowSample(values)
	end
	local isActive = active ~= nil and active.preset == preset and active.placement == placement
	card.active = isActive
	card.frame:SetBackdropBorderColor(unpack(UF.Skin.colors[isActive and "accent" or "border"]))
	card.title:SetText(card.spec.title .. (isActive and ACTIVE or ""))
	card.note:SetText(#values.buffs == 0 and EMPTY_NOTE or card.spec.note)
end

function Showcase:Apply()
	if self.released then return end
	local class = UF.BuffSpells.PlayerClass()
	local resolved = CG.Config.styles.member:Resolved()
	local active = Presets.Detect(resolved, CG.Config:Resolved().slots)
	local values = self:Values(class)
	for _, card in ipairs(self.cards) do self:ApplyCard(card, values, resolved, class, active) end
end

function Showcase:Release()
	if self.released then return end
	self.released = true
	for _, card in ipairs(self.cards) do card.member:Release() end
	self.frame:Hide()
end
